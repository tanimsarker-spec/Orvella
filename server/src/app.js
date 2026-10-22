import Fastify from 'fastify';
import rateLimit from '@fastify/rate-limit';
import websocket from '@fastify/websocket';
import { Readable } from 'node:stream';
import { authenticate, bearer, issueAccessToken, issueMediaToken } from './auth.js';
import { verifyJwt } from './jwt.js';
import { Store } from './store.js';
import { MediaRelay } from './media.js';
import { DriveManager, DriveError } from './drive.js';
import { parseRange } from './range.js';
import { validateClientMessage } from './validate.js';

const NAME_RE = /^[\p{L}\p{N} ._-]{1,32}$/u;

export async function buildServer(config, { fetchImpl = fetch, store = new Store() } = {}) {
  const app = Fastify({
    trustProxy: config.isProd,
    logger: config.logger
      ? {
          redact: ['req.headers.authorization'],
          serializers: {
            req: (req) => ({ method: req.method, url: String(req.url).split('?')[0], ip: req.ip }),
          },
        }
      : false,
  });
  const drive = new DriveManager({ config, fetchImpl });
  const relay = new MediaRelay();
  app.decorate('drive', drive);

  await app.register(rateLimit, { max: 300, timeWindow: '1 minute' });
  await app.register(websocket, { options: { maxPayload: 1024 * 1024 } });

  const fail = (reply, status, error) => reply.code(status).send({ error });

  function requireAuth(req, reply, opts) {
    const auth = authenticate(req, config, opts);
    if (!auth) {
      fail(reply, 401, 'unauthorized');
      return null;
    }
    const user = store.getUser(auth.userId);
    if (!user) {
      fail(reply, 401, 'unknown_user');
      return null;
    }
    return { ...auth, user };
  }

  function requireMember(req, reply, roomId, opts) {
    const room = store.getRoom(roomId);
    if (!room) {
      fail(reply, 404, 'room_not_found');
      return null;
    }
    const auth = requireAuth(req, reply, { roomId: room.id, ...opts });
    if (!auth) return null;
    if (!room.members.has(auth.userId)) {
      fail(reply, 403, 'not_a_member');
      return null;
    }
    return { room, auth };
  }

  const broadcast = (room, payload) => {
    const text = JSON.stringify(payload);
    for (const m of room.members.values()) for (const s of m.sockets) if (s.readyState === 1) s.send(text);
  };
  const broadcastState = (room) => broadcast(room, room.snapshot());

  // ---------- basic ----------
  app.get('/healthz', async () => ({ status: 'ok' }));

  // ---------- auth ----------
  app.post('/auth/guest', { config: { rateLimit: { max: 20, timeWindow: '1 minute' } } }, async (req, reply) => {
    const name = String(req.body?.displayName ?? '').trim();
    if (!NAME_RE.test(name)) return fail(reply, 400, 'invalid_display_name');
    const user = store.createUser(name);
    return { token: issueAccessToken(config, user.id), user };
  });

  app.post('/auth/refresh', { config: { rateLimit: { max: 60, timeWindow: '1 minute' } } }, async (req, reply) => {
    const payload = verifyJwt(bearer(req), config.jwtSecret, { graceSec: config.refreshGraceSec });
    if (!payload || payload.scope !== 'access' || !store.getUser(payload.sub)) return fail(reply, 401, 'unauthorized');
    return { token: issueAccessToken(config, payload.sub) };
  });

  // ---------- rooms ----------
  app.post('/rooms', async (req, reply) => {
    const auth = requireAuth(req, reply);
    if (!auth) return;
    const name = String(req.body?.name ?? '').trim().slice(0, 60) || `${auth.user.displayName}'s room`;
    const room = store.createRoom(auth.user, name);
    return { id: room.id, code: room.code, name: room.name, hostId: room.hostId };
  });

  app.post('/rooms/join', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (req, reply) => {
    const auth = requireAuth(req, reply);
    if (!auth) return;
    const room = store.getRoomByCode(String(req.body?.code ?? '').trim());
    if (!room) return fail(reply, 404, 'room_not_found');
    room.addMember(auth.user);
    broadcastState(room);
    return { id: room.id, code: room.code, name: room.name, hostId: room.hostId };
  });

  app.get('/rooms/:id', async (req, reply) => {
    const ctx = requireMember(req, reply, req.params.id);
    if (!ctx) return;
    const { room } = ctx;
    return { id: room.id, code: room.code, name: room.name, hostId: room.hostId };
  });

  app.post('/rooms/:id/media-token', async (req, reply) => {
    const ctx = requireMember(req, reply, req.params.id);
    if (!ctx) return;
    return { token: issueMediaToken(config, ctx.auth.userId, ctx.room.id), expiresInSec: config.mediaTokenTtlSec };
  });

  // ---------- realtime sync (control messages only, never media bytes) ----------
  app.get('/ws', { websocket: true }, (socket, req) => {
    const auth = authenticate(req, config);
    const room = store.getRoom(String(req.query?.room ?? ''));
    const user = auth && store.getUser(auth.userId);
    if (!user) return socket.close(4401, 'unauthorized');
    if (!room) return socket.close(4404, 'room_not_found');
    const member = room.members.get(user.id);
    if (!member) return socket.close(4403, 'not_a_member');

    member.sockets.add(socket);
    const send = (obj) => socket.readyState === 1 && socket.send(JSON.stringify(obj));
    let tokens = 40;
    const refill = setInterval(() => { tokens = Math.min(40, tokens + 20); }, 1000);
    broadcastState(room);

    socket.on('message', async (data, isBinary) => {
      if (isBinary || data.length > 16384) return socket.close(1009, 'bad_frame');
      if (tokens < 1) return send({ type: 'error', code: 'rate_limited' });
      tokens -= 1;
      let raw;
      try { raw = JSON.parse(data.toString()); } catch { return send({ type: 'error', code: 'bad_json' }); }
      const v = validateClientMessage(raw);
      if (!v.ok) return send({ type: 'error', code: 'invalid', message: v.error });
      const msg = v.value;

      try {
        switch (msg.type) {
          case 'ping':
            return send({ type: 'pong', t: msg.t, serverTime: Date.now() });
          case 'chat':
            return broadcast(room, {
              type: 'chat',
              from: { id: user.id, displayName: user.displayName },
              text: msg.text,
              at: Date.now(),
            });
          case 'signal': {
            const target = room.members.get(msg.to);
            if (!target) return send({ type: 'error', code: 'unknown_target' });
            for (const s of target.sockets) s.send(JSON.stringify({ type: 'signal', from: user.id, data: msg.data }));
            return undefined;
          }
          case 'setSource': {
            if (user.id !== room.hostId) return send({ type: 'error', code: 'forbidden' });
            if (msg.source.kind === 'drive') {
              const meta = await drive.fileMeta(user.id, msg.source.fileId);
              msg.source = { kind: 'drive', fileId: meta.id, name: meta.name, mime: meta.mime, size: meta.size };
            }
            room.apply(user.id, msg);
            return broadcastState(room);
          }
          default: {
            const r = room.apply(user.id, msg);
            if (!r.ok) return send({ type: 'error', code: r.code });
            return broadcastState(room);
          }
        }
      } catch (e) {
        return send({ type: 'error', code: e instanceof DriveError ? e.code : 'internal' });
      }
    });

    socket.on('close', () => {
      clearInterval(refill);
      member.sockets.delete(socket);
      if (member.sockets.size === 0) room.buffering.delete(user.id);
      broadcastState(room);
    });
  });

  // ---------- host-side media relay ----------
  app.get('/media/host', { websocket: true }, (socket, req) => {
    const auth = authenticate(req, config);
    const room = store.getRoom(String(req.query?.room ?? ''));
    if (!auth) return socket.close(4401, 'unauthorized');
    if (!room) return socket.close(4404, 'room_not_found');
    if (auth.userId !== room.hostId) return socket.close(4403, 'host_only');
    relay.registerHost(room.id, socket);
  });

  app.get('/rooms/:id/media', { config: { rateLimit: { max: 3000, timeWindow: '1 minute' } } }, async (req, reply) => {
    const ctx = requireMember(req, reply, req.params.id);
    if (!ctx) return;
    const { room } = ctx;
    const src = room.source;
    if (!src || src.kind !== 'local') return fail(reply, 404, 'no_local_source');
    const range = parseRange(req.headers.range, src.size, config.maxMediaChunk);
    if (!range) return reply.code(416).header('content-range', `bytes */${src.size}`).send({ error: 'bad_range' });
    const host = relay.hostFor(room.id);
    if (!host) return fail(reply, 503, 'host_offline');
    reply.hijack();
    relay.serve(host, reply.raw, src, range);
    return reply;
  });

  // ---------- Google Drive ----------
  const driveGuard = (req, reply) => {
    const auth = requireAuth(req, reply);
    if (!auth) return null;
    if (!drive.enabled) {
      fail(reply, 501, 'drive_not_configured');
      return null;
    }
    return auth;
  };
  const driveError = (reply, e) => {
    if (e instanceof DriveError) return fail(reply, e.status, e.code);
    throw e;
  };

  app.get('/drive/status', async (req, reply) => {
    const auth = requireAuth(req, reply);
    if (!auth) return;
    return { enabled: drive.enabled, connected: drive.connected(auth.userId) };
  });

  app.post('/drive/oauth/start', async (req, reply) => {
    const auth = driveGuard(req, reply);
    if (!auth) return;
    return { url: drive.authUrl(auth.userId) };
  });

  app.get('/drive/oauth/callback', async (req, reply) => {
    const { code, state } = req.query ?? {};
    reply.type('text/html');
    try {
      if (typeof code !== 'string' || typeof state !== 'string') throw new DriveError(400, 'bad_request');
      await drive.handleCallback(code, state);
      return '<!doctype html><meta charset="utf-8"><title>Orvella</title><body style="font-family:sans-serif;text-align:center;padding:3rem"><h2>Google Drive connected</h2><p>You can close this tab and return to Orvella.</p>';
    } catch {
      return reply.code(400).send('<!doctype html><meta charset="utf-8"><title>Orvella</title><body style="font-family:sans-serif;text-align:center;padding:3rem"><h2>Could not connect Google Drive</h2><p>Return to Orvella and try again.</p>');
    }
  });

  app.get('/drive/files', async (req, reply) => {
    const auth = driveGuard(req, reply);
    if (!auth) return;
    try {
      return await drive.listVideos(auth.userId, { parent: req.query?.parent || 'root', pageToken: req.query?.pageToken });
    } catch (e) {
      return driveError(reply, e);
    }
  });

  app.post('/drive/disconnect', async (req, reply) => {
    const auth = requireAuth(req, reply);
    if (!auth) return;
    drive.disconnect(auth.userId);
    return { ok: true };
  });

  app.get('/rooms/:id/drive', { config: { rateLimit: { max: 3000, timeWindow: '1 minute' } } }, async (req, reply) => {
    const ctx = requireMember(req, reply, req.params.id);
    if (!ctx) return;
    const { room } = ctx;
    const src = room.source;
    if (!src || src.kind !== 'drive') return fail(reply, 404, 'no_drive_source');
    const range = parseRange(req.headers.range, src.size, config.maxMediaChunk);
    if (!range) return reply.code(416).header('content-range', `bytes */${src.size}`).send({ error: 'bad_range' });
    let upstream;
    try {
      // Only the host-selected file is ever fetched, using the host's own Drive authorization.
      upstream = await drive.media(room.hostId, src.fileId, range);
    } catch (e) {
      return driveError(reply, e);
    }
    if (!upstream.ok || !upstream.body) return fail(reply, 502, 'drive_unavailable');
    const length = range.end - range.start + 1;
    reply.hijack();
    reply.raw.writeHead(range.partial ? 206 : 200, {
      'content-type': src.mime,
      'accept-ranges': 'bytes',
      'content-length': String(length),
      'cache-control': 'no-store',
      ...(range.partial ? { 'content-range': `bytes ${range.start}-${range.end}/${src.size}` } : {}),
    });
    const body = Readable.fromWeb(upstream.body);
    reply.raw.on('close', () => body.destroy());
    body.on('error', () => reply.raw.destroy());
    body.pipe(reply.raw);
    return reply;
  });

  return app;
}
