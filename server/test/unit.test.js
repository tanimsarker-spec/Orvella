import test from 'node:test';
import assert from 'node:assert';
import { signJwt, verifyJwt } from '../src/jwt.js';
import { parseRange } from '../src/range.js';
import { validateClientMessage } from '../src/validate.js';
import { Room } from '../src/room.js';

test('jwt: valid, tampered, expired, grace', () => {
  const t = signJwt({ sub: 'u1' }, 'secret', 60, 1_000_000);
  assert.equal(verifyJwt(t, 'secret', { now: 1_000_000 + 1000 }).sub, 'u1');
  assert.equal(verifyJwt(t, 'other', { now: 1_000_000 }), null);
  assert.equal(verifyJwt(t + 'x', 'secret', { now: 1_000_000 }), null);
  assert.equal(verifyJwt(t, 'secret', { now: 1_000_000 + 61_000 }), null);
  assert.ok(verifyJwt(t, 'secret', { now: 1_000_000 + 61_000, graceSec: 3600 }));
  assert.equal(verifyJwt('a.b.c', 'secret'), null);
  assert.equal(verifyJwt(undefined, 'secret'), null);
});

test('range parsing', () => {
  const MAX = 1000;
  assert.deepEqual(parseRange(undefined, 5000, MAX), { start: 0, end: 4999, partial: false });
  assert.deepEqual(parseRange('bytes=0-99', 5000, MAX), { start: 0, end: 99, partial: true });
  assert.deepEqual(parseRange('bytes=4500-', 5000, MAX), { start: 4500, end: 4999, partial: true });
  assert.deepEqual(parseRange('bytes=100-', 5000, MAX), { start: 100, end: 1099, partial: true });
  assert.deepEqual(parseRange('bytes=-200', 5000, MAX), { start: 4800, end: 4999, partial: true });
  assert.equal(parseRange('bytes=5000-', 5000, MAX), null);
  assert.equal(parseRange('bytes=9-2', 5000, MAX), null);
  assert.equal(parseRange('bytes=a-b', 5000, MAX), null);
  assert.equal(parseRange('items=0-1', 5000, MAX), null);
  assert.equal(parseRange('bytes=0-1', 0, MAX), null);
});

test('message validation', () => {
  assert.ok(validateClientMessage({ type: 'seek', positionMs: 5 }).ok);
  assert.ok(!validateClientMessage({ type: 'seek', positionMs: -1 }).ok);
  assert.ok(!validateClientMessage({ type: 'seek', positionMs: 1.5 }).ok);
  assert.ok(!validateClientMessage({ type: 'chat', text: '   ' }).ok);
  assert.ok(!validateClientMessage({ type: 'nope' }).ok);
  assert.ok(!validateClientMessage(null).ok);
  assert.ok(!validateClientMessage({ type: 'setSource', source: { kind: 'url', name: 'x', url: 'file:///etc/passwd' } }).ok);
  assert.ok(!validateClientMessage({ type: 'setSource', source: { kind: 'drive', name: 'x', fileId: '../etc' } }).ok);
  assert.ok(validateClientMessage({ type: 'setSource', source: { kind: 'url', name: 'x', url: 'https://example.com/a.mp4' } }).ok);
  assert.ok(validateClientMessage({ type: 'setSource', source: { kind: 'local', name: 'a.mp4', size: 10, mime: 'video/mp4' } }).ok);
});

test('room clock math and permissions', () => {
  let t = 1000;
  const room = new Room({ id: 'r', code: 'C', name: 'n', hostId: 'host', now: () => t });
  room.apply('host', { type: 'play', positionMs: 5000 });
  t += 2000;
  assert.equal(room.currentPositionMs(), 7000);
  room.apply('guest', { type: 'pause' });
  assert.equal(room.positionMs, 7000);
  t += 5000;
  assert.equal(room.currentPositionMs(), 7000);
  room.apply('host', { type: 'setControlMode', mode: 'host' });
  assert.equal(room.apply('guest', { type: 'play' }).code, 'forbidden');
  assert.equal(room.apply('guest', { type: 'setSource', source: {} }).code, 'forbidden');
});
