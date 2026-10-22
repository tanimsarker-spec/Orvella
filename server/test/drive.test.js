import test, { after } from 'node:test';
import assert from 'node:assert';
import { randomBytes } from 'node:crypto';
import { startServer, openWs } from './helpers.js';

const DRIVE_FILE = randomBytes(300_000);
const calls = [];

// Fake Google: token endpoint, list, metadata, media with Range.
const fakeGoogle = async (url, init = {}) => {
  const u = new URL(String(url));
  calls.push({ url: String(url), init });
  const json = (obj, status = 200) => new Response(JSON.stringify(obj), { status, headers: { 'content-type': 'application/json' } });
  if (u.host === 'oauth2.googleapis.com') {
    const p = new URLSearchParams(String(init.body));
    if (p.get('grant_type') === 'authorization_code' && p.get('code') === 'good-code')
      return json({ access_token: 'AT1', refresh_token: 'RT1', expires_in: 3600 });
    if (p.get('grant_type') === 'refresh_token' && p.get('refresh_token') === 'RT1')
      return json({ access_token: 'AT2', expires_in: 3600 });
    return json({ error: 'bad' }, 400);
  }
  const auth = init.headers?.authorization;
  if (!auth?.startsWith('Bearer AT')) return json({ error: 'unauth' }, 401);
  if (u.pathname === '/drive/v3/files')
    return json({ files: [{ id: 'folder12345', name: 'Movies', mimeType: 'application/vnd.google-apps.folder' }, { id: 'file123456', name: 'film.mp4', mimeType: 'video/mp4', size: String(DRIVE_FILE.length) }] });
  if (u.pathname === '/drive/v3/files/file123456') {
    if (u.searchParams.get('alt') === 'media') {
      const m = /^bytes=(\d+)-(\d+)$/.exec(init.headers.range);
      const body = DRIVE_FILE.subarray(Number(m[1]), Number(m[2]) + 1);
      return new Response(body, { status: 206 });
    }
    return json({ id: 'file123456', name: 'film.mp4', mimeType: 'video/mp4', size: String(DRIVE_FILE.length) });
  }
  if (u.pathname === '/drive/v3/files/doc1234567') return json({ id: 'doc1234567', name: 'a.pdf', mimeType: 'application/pdf', size: '5' });
  return json({ error: 'nf' }, 404);
};

const srv = await startServer({
  fetchImpl: fakeGoogle,
  env: { GOOGLE_OAUTH_CLIENT_ID: 'cid', GOOGLE_OAUTH_CLIENT_SECRET: 'csecret' },
});
after(() => srv.app.close());

test('drive: disabled server reports not configured', async () => {
  const plain = await startServer();
  const g = await plain.guest('A');
  assert.equal((await plain.api('GET', '/drive/status', { token: g.token })).json.enabled, false);
  assert.equal((await plain.api('POST', '/drive/oauth/start', { token: g.token })).status, 501);
  await plain.app.close();
});

test('drive: oauth, list, select, proxy ranges, access control', async () => {
  const host = await srv.guest('Host');
  const viewer = await srv.guest('Viewer');
  const eve = await srv.guest('Eve');
  const room = (await srv.api('POST', '/rooms', { token: host.token, body: {} })).json;
  await srv.api('POST', '/rooms/join', { token: viewer.token, body: { code: room.code } });

  assert.equal((await srv.api('GET', '/drive/status', { token: host.token })).json.connected, false);
  assert.equal((await srv.api('GET', '/drive/files', { token: host.token })).status, 401);

  const start = await srv.api('POST', '/drive/oauth/start', { token: host.token });
  const authUrl = new URL(start.json.url);
  assert.equal(authUrl.host, 'accounts.google.com');
  assert.equal(authUrl.searchParams.get('scope'), 'https://www.googleapis.com/auth/drive.readonly');
  const state = authUrl.searchParams.get('state');

  assert.equal((await fetch(`${srv.base}/drive/oauth/callback?code=good-code&state=forged`)).status, 400);
  assert.equal((await fetch(`${srv.base}/drive/oauth/callback?code=bad&state=${state}`)).status, 400);
  const start2 = await srv.api('POST', '/drive/oauth/start', { token: host.token });
  const state2 = new URL(start2.json.url).searchParams.get('state');
  assert.equal((await fetch(`${srv.base}/drive/oauth/callback?code=good-code&state=${state2}`)).status, 200);
  assert.equal((await srv.api('GET', '/drive/status', { token: host.token })).json.connected, true);
  assert.equal((await srv.api('GET', '/drive/status', { token: viewer.token })).json.connected, false);

  const list = await srv.api('GET', '/drive/files?parent=root', { token: host.token });
  assert.equal(list.json.files.length, 2);
  assert.equal((await srv.api('GET', "/drive/files?parent=x'%20or%20'1", { token: host.token })).status, 400);

  const ctl = openWs(`${srv.wsBase}/ws?room=${room.id}`, host.token);
  await ctl.opened;
  ctl.send({ type: 'setSource', source: { kind: 'drive', name: 'x', fileId: 'doc1234567' } });
  assert.equal((await ctl.next((m) => m.type === 'error')).code, 'not_a_video');
  ctl.send({ type: 'setSource', source: { kind: 'drive', name: 'x', fileId: 'file123456' } });
  const st = await ctl.next((m) => m.type === 'state' && m.source);
  assert.equal(st.source.name, 'film.mp4');
  assert.equal(st.source.size, DRIVE_FILE.length);

  const get = (token, range) => fetch(`${srv.base}/rooms/${room.id}/drive`, { headers: { authorization: `Bearer ${token}`, ...(range ? { range } : {}) } });
  const res = await get(viewer.token, 'bytes=1000-1999');
  assert.equal(res.status, 206);
  assert.equal(res.headers.get('content-range'), `bytes 1000-1999/${DRIVE_FILE.length}`);
  assert.deepEqual(Buffer.from(await res.arrayBuffer()), DRIVE_FILE.subarray(1000, 2000));
  assert.equal((await get(eve.token, 'bytes=0-9')).status, 403);
  assert.equal((await get('junk', 'bytes=0-9')).status, 401);

  // Google tokens never leak to the viewer's responses
  assert.ok(!JSON.stringify(st).includes('AT1'));
  ctl.close();
});

test('drive: expired access token is refreshed server-side', async () => {
  const host = await srv.guest('Host2');
  const start = await srv.api('POST', '/drive/oauth/start', { token: host.token });
  const state = new URL(start.json.url).searchParams.get('state');
  await fetch(`${srv.base}/drive/oauth/callback?code=good-code&state=${state}`);

  srv.app.drive.sessions.get(host.user.id).expiresAt = 0; // force expiry
  const before = calls.length;
  const list = await srv.api('GET', '/drive/files', { token: host.token });
  assert.equal(list.status, 200);
  const made = calls.slice(before);
  assert.ok(made.some((c) => String(c.init.body ?? '').includes('refresh_token')), 'refresh was requested');
  const listCall = made.find((c) => c.url.includes('/drive/v3/files?'));
  assert.equal(listCall.init.headers.authorization, 'Bearer AT2');

  // disconnect forgets the tokens
  await srv.api('POST', '/drive/disconnect', { token: host.token });
  assert.equal((await srv.api('GET', '/drive/files', { token: host.token })).status, 401);
});
