import test from 'node:test';
import assert from 'node:assert';
import { createHmac } from 'node:crypto';
import { startServer, openWs } from './helpers.js';
import { iceServers } from '../src/rtc.js';

function fakeMailer() {
  const sent = [];
  return { enabled: true, sent, send: async (m) => { sent.push(m); } };
}
const codeFrom = (mail) => /code is (\d{6})/.exec(mail.text)[1];

test('password reset: code flow, wrong code, attempts lockout, one-time use', async () => {
  const mailer = fakeMailer();
  const srv = await startServer({ mailer });
  const email = 'reset@example.com';
  await srv.api('POST', '/auth/signup', { body: { email, password: 'old-password-1', displayName: 'Rita' } });

  // unknown email gets the same answer and no mail
  assert.equal((await srv.api('POST', '/auth/forgot', { body: { email: 'ghost@example.com' } })).status, 200);
  assert.equal(mailer.sent.length, 0);

  assert.equal((await srv.api('POST', '/auth/forgot', { body: { email } })).status, 200);
  assert.equal(mailer.sent.length, 1);
  assert.equal(mailer.sent[0].to, email);
  const code = codeFrom(mailer.sent[0]);

  assert.equal((await srv.api('POST', '/auth/reset', { body: { email, code: '000000', newPassword: 'new-password-1' } })).status, 400);
  assert.equal((await srv.api('POST', '/auth/reset', { body: { email, code, newPassword: 'short' } })).status, 400);
  const ok = await srv.api('POST', '/auth/reset', { body: { email, code, newPassword: 'new-password-1' } });
  assert.equal(ok.status, 200);
  assert.ok(ok.json.token);
  assert.equal((await srv.api('POST', '/auth/login', { body: { email, password: 'old-password-1' } })).status, 401);
  assert.equal((await srv.api('POST', '/auth/login', { body: { email, password: 'new-password-1' } })).status, 200);
  assert.equal((await srv.api('POST', '/auth/reset', { body: { email, code, newPassword: 'another-pass-1' } })).status, 400);
  await srv.app.close();
});

test('password reset: too many wrong guesses locks the code', async () => {
  const mailer = fakeMailer();
  const srv = await startServer({ mailer });
  const email = 'lock@example.com';
  await srv.api('POST', '/auth/signup', { body: { email, password: 'old-password-1', displayName: 'Lou' } });
  await srv.api('POST', '/auth/forgot', { body: { email } });
  const code = codeFrom(mailer.sent[0]);
  for (let i = 0; i < 5; i += 1) {
    assert.equal((await srv.api('POST', '/auth/reset', { body: { email, code: '999999', newPassword: 'new-password-1' } })).status, 400);
  }
  assert.equal((await srv.api('POST', '/auth/reset', { body: { email, code, newPassword: 'new-password-1' } })).status, 400);
  await srv.app.close();
});

const idToken = (claims) => `h.${Buffer.from(JSON.stringify(claims)).toString('base64url')}.s`;

test('google sign-in: new account, existing account, unverified email, one-time poll', async () => {
  let claims = { email: 'gina@gmail.com', email_verified: true, given_name: 'Gina <3' };
  const fakeGoogle = async (url, init) => {
    if (String(url).includes('oauth2.googleapis.com/token')) {
      const p = new URLSearchParams(String(init.body));
      if (p.get('code') !== 'g-code') return new Response('{}', { status: 400 });
      return new Response(JSON.stringify({ id_token: idToken(claims) }), { status: 200 });
    }
    return new Response('{}', { status: 404 });
  };
  const srv = await startServer({ fetchImpl: fakeGoogle, env: { GOOGLE_OAUTH_CLIENT_ID: 'cid', GOOGLE_OAUTH_CLIENT_SECRET: 'cs' } });

  const run = async (code = 'g-code') => {
    const start = await srv.api('POST', '/auth/google/start');
    assert.equal(start.status, 200);
    const u = new URL(start.json.url);
    assert.equal(u.searchParams.get('scope'), 'openid email profile');
    assert.ok(u.searchParams.get('redirect_uri').endsWith('/auth/google/callback'));
    assert.equal((await srv.api('GET', `/auth/google/poll?state=${start.json.state}`)).json.status, 'pending');
    const cb = await fetch(`${srv.base}/auth/google/callback?code=${code}&state=${start.json.state}`);
    return { state: start.json.state, cb };
  };

  const a = await run();
  assert.equal(a.cb.status, 200);
  const poll = await srv.api('GET', `/auth/google/poll?state=${a.state}`);
  assert.equal(poll.json.status, 'done');
  assert.equal(poll.json.user.displayName, 'Gina 3'); // unsafe characters stripped
  assert.equal((await srv.api('POST', '/rooms', { token: poll.json.token, body: {} })).status, 200);
  assert.equal((await srv.api('GET', `/auth/google/poll?state=${a.state}`)).status, 404); // consumed

  const b = await run();
  const poll2 = await srv.api('GET', `/auth/google/poll?state=${b.state}`);
  assert.equal(poll2.json.user.id, poll.json.user.id); // same email -> same account

  claims = { email: 'evil@gmail.com', email_verified: false };
  const c = await run();
  assert.equal(c.cb.status, 400);
  assert.equal((await srv.api('GET', `/auth/google/poll?state=${c.state}`)).status, 404);

  assert.equal((await fetch(`${srv.base}/auth/google/callback?code=g-code&state=forged`)).status, 400);
  assert.equal((await run('bad-code')).cb.status, 400);
  await srv.app.close();
});

test('google sign-in disabled without credentials', async () => {
  const srv = await startServer();
  assert.equal((await srv.api('POST', '/auth/google/start')).status, 501);
  await srv.app.close();
});

test('rtc config: STUN only by default, signed short-lived TURN when configured', async () => {
  const plain = await startServer();
  const g = await plain.guest('V');
  const r = await plain.api('GET', '/rtc/config', { token: g.token });
  assert.equal(r.json.iceServers.length, 1);
  assert.equal((await plain.api('GET', '/rtc/config')).status, 401);
  await plain.app.close();

  const cfg = { turnSecret: 'secret', turnHost: 'party.example.com' };
  const [, turn] = iceServers(cfg, 'user1', 1_000_000_000);
  assert.equal(turn.username, `${1_000_000 + 6 * 3600}:user1`);
  assert.equal(turn.credential, createHmac('sha1', 'secret').update(turn.username).digest('base64'));
  assert.ok(turn.urls.includes('turn:party.example.com:3478?transport=tcp'));
});

test('reactions broadcast; invalid emoji rejected', async () => {
  const srv = await startServer();
  const a = await srv.guest('Ann');
  const b = await srv.guest('Bo');
  const room = (await srv.api('POST', '/rooms', { token: a.token, body: {} })).json;
  await srv.api('POST', '/rooms/join', { token: b.token, body: { code: room.code } });
  const wa = openWs(`${srv.wsBase}/ws?room=${room.id}`, a.token);
  const wb = openWs(`${srv.wsBase}/ws?room=${room.id}`, b.token);
  await Promise.all([wa.opened, wb.opened]);
  wb.send({ type: 'react', emoji: '🔥' });
  const r = await wa.next((m) => m.type === 'reaction');
  assert.equal(r.emoji, '🔥');
  assert.equal(r.from.displayName, 'Bo');
  wb.send({ type: 'react', emoji: '💣' });
  assert.equal((await wb.next((m) => m.type === 'error')).code, 'invalid');
  [wa, wb].forEach((w) => w.close());
  await srv.app.close();
});

test('public parties: listed only when public and occupied; joinable without a code; host controls privacy', async () => {
  const srv = await startServer();
  const host = await srv.guest('Host');
  const guest = await srv.guest('Guest');
  const priv = (await srv.api('POST', '/rooms', { token: host.token, body: { name: 'Secret' } })).json;
  const pub = (await srv.api('POST', '/rooms', { token: host.token, body: { name: 'Open house', isPublic: true } })).json;

  const wPub = openWs(`${srv.wsBase}/ws?room=${pub.id}`, host.token);
  const wPriv = openWs(`${srv.wsBase}/ws?room=${priv.id}`, host.token);
  await Promise.all([wPub.opened, wPriv.opened]);
  await wPub.next((m) => m.type === 'state');

  const list = await srv.api('GET', '/rooms/public', { token: guest.token });
  assert.deepEqual(list.json.rooms.map((r) => r.name), ['Open house']);
  assert.equal(list.json.rooms[0].hostName, 'Host');
  assert.ok(!JSON.stringify(list.json).includes(pub.code)); // code is not leaked in the listing

  assert.equal((await srv.api('POST', `/rooms/${priv.id}/join-public`, { token: guest.token })).status, 404);
  assert.equal((await srv.api('POST', `/rooms/${pub.id}/join-public`, { token: guest.token })).status, 200);
  assert.equal((await srv.api('GET', `/rooms/${pub.id}`, { token: guest.token })).status, 200);

  // host flips a private room public; a non-host cannot
  const wGuest = openWs(`${srv.wsBase}/ws?room=${pub.id}`, guest.token);
  await wGuest.opened;
  wGuest.send({ type: 'setPublic', value: false });
  assert.equal((await wGuest.next((m) => m.type === 'error')).code, 'forbidden');
  wPriv.send({ type: 'setPublic', value: true });
  const st = await wPriv.next((m) => m.type === 'state' && m.isPublic === true);
  assert.equal(st.isPublic, true);
  const list2 = await srv.api('GET', '/rooms/public', { token: guest.token });
  assert.equal(list2.json.rooms.length, 2);
  [wPub, wPriv, wGuest].forEach((w) => w.close());
  await srv.app.close();
});
