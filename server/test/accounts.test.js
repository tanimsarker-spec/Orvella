import test from 'node:test';
import assert from 'node:assert';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { startServer } from './helpers.js';
import { hashPassword, verifyPassword } from '../src/password.js';

test('password hashing: verifies right, rejects wrong, salts differ', async () => {
  const a = await hashPassword('correct horse');
  const b = await hashPassword('correct horse');
  assert.notEqual(a, b);
  assert.ok(await verifyPassword('correct horse', a));
  assert.ok(!(await verifyPassword('wrong horse', a)));
  assert.ok(!(await verifyPassword('x', 'garbage')));
});

test('signup/login: validation, duplicates, wrong password, case-insensitive email', async () => {
  const srv = await startServer();
  const body = { email: 'Tanim@Example.com', password: 'longenough1', displayName: 'Tanim' };

  assert.equal((await srv.api('POST', '/auth/signup', { body: { ...body, email: 'nope' } })).status, 400);
  assert.equal((await srv.api('POST', '/auth/signup', { body: { ...body, password: 'short' } })).status, 400);
  assert.equal((await srv.api('POST', '/auth/signup', { body: { ...body, displayName: '<b>' } })).status, 400);

  const ok = await srv.api('POST', '/auth/signup', { body });
  assert.equal(ok.status, 200);
  assert.equal(ok.json.user.displayName, 'Tanim');
  assert.ok(!JSON.stringify(ok.json).includes('longenough1'));
  assert.ok(!JSON.stringify(ok.json).includes('scrypt'));

  assert.equal((await srv.api('POST', '/auth/signup', { body: { ...body, email: 'tanim@example.com' } })).status, 409);

  const login = await srv.api('POST', '/auth/login', { body: { email: 'tanim@example.com', password: 'longenough1' } });
  assert.equal(login.status, 200);
  assert.equal(login.json.user.id, ok.json.user.id);
  const room = await srv.api('POST', '/rooms', { token: login.json.token, body: {} });
  assert.equal(room.status, 200);

  assert.equal((await srv.api('POST', '/auth/login', { body: { email: 'tanim@example.com', password: 'WRONGPASS1' } })).status, 401);
  assert.equal((await srv.api('POST', '/auth/login', { body: { email: 'nobody@example.com', password: 'whatever12' } })).status, 401);
  await srv.app.close();
});

test('accounts survive a server restart (SQLite file)', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'orvella-'));
  const dbPath = join(dir, 'data', 'o.db');
  const body = { email: 'keep@example.com', password: 'persist-me-1', displayName: 'Keeper' };

  const first = await startServer({ dbPath });
  const signup = await first.api('POST', '/auth/signup', { body });
  assert.equal(signup.status, 200);
  await first.app.close();

  const second = await startServer({ dbPath });
  const login = await second.api('POST', '/auth/login', { body: { email: body.email, password: body.password } });
  assert.equal(login.status, 200);
  assert.equal(login.json.user.id, signup.json.user.id);
  // Old token from before the restart is still valid only if the secret is unchanged; the user record must load.
  const me = await second.api('POST', '/rooms', { token: login.json.token, body: {} });
  assert.equal(me.status, 200);
  await second.app.close();
  rmSync(dir, { recursive: true, force: true });
});

test('guests can be disabled', async () => {
  const srv = await startServer({ env: { ALLOW_GUESTS: '0' } });
  assert.equal((await srv.api('POST', '/auth/guest', { body: { displayName: 'G' } })).status, 403);
  await srv.app.close();
});
