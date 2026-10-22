import { signJwt, verifyJwt } from './jwt.js';

export function bearer(req) {
  const h = req.headers.authorization;
  if (typeof h !== 'string' || !h.startsWith('Bearer ')) return null;
  return h.slice(7).trim();
}

export function issueAccessToken(config, userId) {
  return signJwt({ sub: userId, scope: 'access' }, config.jwtSecret, config.accessTokenTtlSec);
}

export function issueMediaToken(config, userId, roomId) {
  return signJwt({ sub: userId, scope: 'media', room: roomId }, config.jwtSecret, config.mediaTokenTtlSec);
}

/**
 * Authenticate a request. Media-scoped tokens are only valid for the room they were issued for
 * and only when `roomId` is passed (media/drive byte routes).
 */
export function authenticate(req, config, { roomId = null } = {}) {
  const payload = verifyJwt(bearer(req), config.jwtSecret);
  if (!payload) return null;
  if (payload.scope === 'media') {
    if (!roomId || payload.room !== roomId) return null;
  } else if (payload.scope !== 'access') {
    return null;
  }
  return { userId: payload.sub, scope: payload.scope };
}
