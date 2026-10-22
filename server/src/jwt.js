import { createHmac, timingSafeEqual } from 'node:crypto';

const enc = (v) => Buffer.from(v).toString('base64url');

export function signJwt(payload, secret, ttlSeconds, now = Date.now()) {
  const iat = Math.floor(now / 1000);
  const body = { ...payload, iat, exp: iat + ttlSeconds };
  const data = `${enc(JSON.stringify({ alg: 'HS256', typ: 'JWT' }))}.${enc(JSON.stringify(body))}`;
  return `${data}.${createHmac('sha256', secret).update(data).digest('base64url')}`;
}

/** Returns the payload, or null if invalid. graceSec lets callers accept recently expired tokens (refresh only). */
export function verifyJwt(token, secret, { now = Date.now(), graceSec = 0 } = {}) {
  if (typeof token !== 'string') return null;
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  try {
    const header = JSON.parse(Buffer.from(parts[0], 'base64url').toString());
    if (header.alg !== 'HS256') return null;
    const expected = createHmac('sha256', secret).update(`${parts[0]}.${parts[1]}`).digest();
    const given = Buffer.from(parts[2], 'base64url');
    if (given.length !== expected.length || !timingSafeEqual(given, expected)) return null;
    const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
    if (typeof payload.exp !== 'number' || (payload.exp + graceSec) * 1000 <= now) return null;
    return payload;
  } catch {
    return null;
  }
}
