import test, { after } from 'node:test';
import assert from 'node:assert';
import { randomBytes } from 'node:crypto';
import { startServer, openWs, sleep } from './helpers.js';

const srv = await startServer();
after(() => srv.app.close());

const FILE = randomBytes(1_000_000);

/** Simulates the host app: answers range requests from an in-memory "file". */
function runHost(hostWs, file, { chunk = 65536 } = {}) {
  const cancelled = new Set();
  hostWs.ws.on('message', async (data, isBinary) => {
    if (isBinary) return;
    const msg = JSON.parse(data.toString());
    if (msg.type === 'cancel') cancelled.add(msg.id);
    if (msg.type !== 'range') return;
    let pos = msg.start;
    while (pos <= msg.end && !cancelled.has(msg.id)) {
      const n = Math.min(chunk, msg.end - pos + 1);
      const frame = Buffer.alloc(4 + n);
      frame.writeUInt32BE(msg.id, 0);
      file.copy(frame, 4, pos, pos + n);
      hostWs.ws.send(frame);
      pos += n;
      await sleep(0);
    }
    if (!cancelled.has(msg.id)) hostWs.send({ type: 'end', id: msg.id });
  });
  return cancelled;
}

async function setup({ hostOnline = true } = {}) {
  const host = await srv.guest('Host');
  const viewer = await srv.guest('Viewer');
  const room = (await srv.api('POST', '/rooms', { token: host.token, body: {} })).json;
  await srv.api('POST', '/rooms/join', { token: viewer.token, body: { code: room.code } });
  const ctl = openWs(`${srv.wsBase}/ws?room=${room.id}`, host.token);
  await ctl.opened;
  ctl.send({ type: 'setSource', source: { kind: 'local', name: 'movie.mp4', size: FILE.length, mime: 'video/mp4' } });
  await ctl.next((m) => m.type === 'state' && m.source);
  let media = null;
  if (hostOnline) {
    media = openWs(`${srv.wsBase}/media/host?room=${room.id}`, host.token);
    await media.opened;
    runHost(media, FILE);
  }
  return { host, viewer, room, ctl, media };
}

const get = (room, token, range) =>
  fetch(`${srv.base}/rooms/${room.id}/media`, {
    headers: { authorization: `Bearer ${token}`, ...(range ? { range } : {}) },
  });

test('relay: viewer gets exact bytes for bounded, open-ended and suffix ranges', async () => {
  const { viewer, room, ctl, media } = await setup();

  let res = await get(room, viewer.token, 'bytes=100-999');
  assert.equal(res.status, 206);
  assert.equal(res.headers.get('content-range'), `bytes 100-999/${FILE.length}`);
  assert.deepEqual(Buffer.from(await res.arrayBuffer()), FILE.subarray(100, 1000));

  res = await get(room, viewer.token, 'bytes=500000-');
  assert.equal(res.status, 206);
  assert.deepEqual(Buffer.from(await res.arrayBuffer()), FILE.subarray(500000));

  res = await get(room, viewer.token, 'bytes=-1234');
  assert.deepEqual(Buffer.from(await res.arrayBuffer()), FILE.subarray(FILE.length - 1234));

  res = await get(room, viewer.token);
  assert.equal(res.status, 200);
  assert.deepEqual(Buffer.from(await res.arrayBuffer()), FILE);

  assert.equal((await get(room, viewer.token, 'bytes=9999999-')).status, 416);
  ctl.close(); media.close();
});

test('relay: media-scoped token works for its room only; bad/no token rejected', async () => {
  const { viewer, room, ctl, media } = await setup();
  const mt = (await srv.api('POST', `/rooms/${room.id}/media-token`, { token: viewer.token })).json.token;
  const ok = await get(room, mt, 'bytes=0-9');
  assert.equal(ok.status, 206);
  await ok.arrayBuffer();

  const other = await setup({ hostOnline: false });
  assert.equal((await get(other.room, mt, 'bytes=0-9')).status, 401);
  assert.equal((await get(room, 'garbage', 'bytes=0-9')).status, 401);
  assert.equal((await fetch(`${srv.base}/rooms/${room.id}/media`)).status, 401);

  // media tokens must not work on API routes
  assert.equal((await srv.api('POST', '/rooms', { token: mt, body: {} })).status, 401);
  ctl.close(); media.close(); other.ctl.close();
});

test('relay: non-member forbidden, offline host 503, only host may register', async () => {
  const { room, ctl, media } = await setup();
  const eve = await srv.guest('Eve');
  assert.equal((await get(room, eve.token, 'bytes=0-9')).status, 403);

  const viewer2 = await srv.guest('V2');
  await srv.api('POST', '/rooms/join', { token: viewer2.token, body: { code: room.code } });
  const fake = openWs(`${srv.wsBase}/media/host?room=${room.id}`, viewer2.token);
  await fake.opened;
  assert.equal(await fake.closed, 4403);

  const offline = await setup({ hostOnline: false });
  assert.equal((await get(offline.room, offline.viewer.token, 'bytes=0-9')).status, 503);
  ctl.close(); media.close(); offline.ctl.close();
});

test('relay: host disconnect mid-stream aborts instead of hanging', async () => {
  const { viewer, room, ctl, media } = await setup();
  media.ws.removeAllListeners('message');
  media.ws.on('message', (data) => {
    const msg = JSON.parse(data.toString());
    if (msg.type !== 'range') return;
    const frame = Buffer.alloc(4 + 1000);
    frame.writeUInt32BE(msg.id, 0);
    media.ws.send(frame);
    setTimeout(() => media.ws.close(), 50);
  });
  const res = await get(room, viewer.token, 'bytes=0-499999');
  await assert.rejects(async () => res.arrayBuffer());
  ctl.close();
});
