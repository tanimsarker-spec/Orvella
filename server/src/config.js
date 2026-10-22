import { randomBytes } from 'node:crypto';

export function loadConfig(env = process.env) {
  const isProd = env.NODE_ENV === 'production';
  let jwtSecret = env.JWT_SECRET;
  if (!jwtSecret) {
    if (isProd) throw new Error('JWT_SECRET is required in production');
    jwtSecret = randomBytes(32).toString('hex');
  }
  if (isProd && jwtSecret.length < 32) throw new Error('JWT_SECRET must be at least 32 characters');
  const port = Number(env.PORT ?? 8080);
  return {
    isProd,
    port,
    jwtSecret,
    publicUrl: env.PUBLIC_URL ?? `http://localhost:${port}`,
    googleClientId: env.GOOGLE_OAUTH_CLIENT_ID ?? '',
    googleClientSecret: env.GOOGLE_OAUTH_CLIENT_SECRET ?? '',
    accessTokenTtlSec: 3600,
    mediaTokenTtlSec: 6 * 3600,
    refreshGraceSec: 7 * 24 * 3600,
    maxMediaChunk: 16 * 1024 * 1024,
    logger: true,
  };
}
