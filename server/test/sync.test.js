import test, { after } from 'node:test';
import assert from 'node:assert';
import { startServer, openWs, sleep } from './helpers.js';

const srv = await startServer();
after(() => srv.app.close());

async function setup() {
  const a = await srv.guest('Alice');
  const b = await srv.guest('Bob');
  const room = (await srv.api('POST', '/rooms', { token: a.token, body: { name: 'Movie night' } })).json;
  const joined = await srv.api('POST', '/rooms/join', { token: b.token, body: { code: room.code.toLowerCase() } });
  assert.equal(joined.status, 200);
  return { a, b, room };
}

test('auth: guest validation, refresh, protected routes', async () => {
  assert.equal((await srv.api('POST', '/auth/guest', { body: { displayName: '' } })).status, 400);
  assert.equal((await srv.api('POST', '/auth/guest', { body: { displayName: '<script>' } })).status, 400);
  assert.equal((await srv.api('POST', '/rooms', { body: {} })).status, 401);
  const g = await srv.guest('Zed');
  const r = await srv.api('POST', '/auth/refresh', { token: g.token });
  assert.equal(r.status, 200);
  assert.ok(r.json.token);
  assert.equal((await srv.api('POST', '/auth/refresh', { token: 'garbage' })).status, 401);
});

test('rooms: join by code, unknown code, non-member blocked', async () => {
  const { room } = await setup();
  const outsider = await srv.guest('Eve');
  assert.equal((await srv.api('GET', `/rooms/${room.id}`, { token: outsider.token })).status, 403);
  assert.equal((await srv.api('POST', '/rooms/join', { token: outsider.token, body: { code: 'ZZZZZZ' } })).status, 404);
});

test('ws: rejects bad token and non-members', async () => {
  const { room } = await setup();
  const bad = openWs(`${srv.wsBase}/ws?room=${room.id}`, 'nope');
  await bad.opened;
  assert.equal(await bad.closed, 4401);
  const eve = await srv.guest('Eve');
  const c = openWs(`${srv.wsBase}/ws?room=${room.id}`, eve.token);
  await c.opened;
  assert.equal(await c.closed, 4403);
});

test('sync: play/seek/pause propagate, late join and reconnect get current position', async () => {
  const { a, b, room } = await setup();
  const url = `${srv.wsBase}/ws?room=${room.id}`;
  const wa = openWs(url, a.token);
  const wb = openWs(url, b.token);
  await Promise.all([wa.opened, wb.opened]);
  await wb.next((m) => m.type === 'state');

  wa.send({ type: 'play', positionMs: 10_000 });
  const played = await wb.next((m) => m.type === 'state' && m.playing);
  assert.equal(played.positionMs, 10_000);

  wb.send({ type: 'seek', positionMs: 60_000 });
  const seeked = await wa.next((m) => m.type === 'state' && m.positionMs === 60_000);
  assert.equal(seeked.playing, true);

  await sleep(300);
  const c = await srv.guest('Carl');
  await srv.api('POST', '/rooms/join', { token: c.token, body: { code: room.code } });
  const wc = openWs(url, c.token);
  await wc.opened;
  const late = await wc.next((m) => m.type === 'state');
  const effective = late.positionMs + (late.serverNow - late.updatedAt);
  assert.ok(effective >= 60_300 && effective < 61_500, `effective ${effective}`);

  wb.close();
  await sleep(100);
  wa.send({ type: 'pause', positionMs: 70_000 });
  const wb2 = openWs(url, b.token);
  await wb2.opened;
  const re = await wb2.next((m) => m.type === 'state');
  assert.equal(re.playing, false);
  assert.equal(re.positionMs, 70_000);
  assert.equal(re.participants.length, 3);

  [wa, wb2, wc].forEach((w) => w.close());
});

test('sync: buffering list, chat, control mode, invalid input', async () => {
  const { a, b, room } = await setup();
  const url = `${srv.wsBase}/ws?room=${room.id}`;
  const wa = openWs(url, a.token);
  const wb = openWs(url, b.token);
  await Promise.all([wa.opened, wb.opened]);

  wb.send({ type: 'buffering', value: true });
  const st = await wa.next((m) => m.type === 'state' && m.buffering.length === 1);
  assert.equal(st.buffering[0], b.user.id);
  wb.send({ type: 'buffering', value: false });
  await wa.next((m) => m.type === 'state' && m.buffering.length === 0);

  wb.send({ type: 'chat', text: 'hello there' });
  const chat = await wa.next((m) => m.type === 'chat');
  assert.equal(chat.text, 'hello there');
  assert.equal(chat.from.displayName, 'Bob');

  wa.send({ type: 'setControlMode', mode: 'host' });
  await wb.next((m) => m.type === 'state' && m.controlMode === 'host');
  wb.send({ type: 'play' });
  assert.equal((await wb.next((m) => m.type === 'error')).code, 'forbidden');

  wb.send({ type: 'seek', positionMs: 'abc' });
  assert.equal((await wb.next((m) => m.type === 'error')).code, 'invalid');
  wb.ws.send('not json');
  assert.equal((await wb.next((m) => m.type === 'error')).code, 'bad_json');

  // WebRTC signaling relay (used by voice chat later)
  wb.send({ type: 'signal', to: a.user.id, data: { sdp: 'x' } });
  const sig = await wa.next((m) => m.type === 'signal');
  assert.equal(sig.from, b.user.id);

  [wa, wb].forEach((w) => w.close());
});

test('sync: only host can set source; test-video url source works', async () => {
  const { a, b, room } = await setup();
  const url = `${srv.wsBase}/ws?room=${room.id}`;
  const wa = openWs(url, a.token);
  const wb = openWs(url, b.token);
  await Promise.all([wa.opened, wb.opened]);
  const src = { kind: 'url', name: 'Sample', url: 'https://example.com/sample.mp4' };
  wb.send({ type: 'setSource', source: src });
  assert.equal((await wb.next((m) => m.type === 'error')).code, 'forbidden');
  wa.send({ type: 'setSource', source: src });
  const st = await wb.next((m) => m.type === 'state' && m.source);
  assert.equal(st.source.kind, 'url');
  assert.equal(st.positionMs, 0);
  [wa, wb].forEach((w) => w.close());
});
