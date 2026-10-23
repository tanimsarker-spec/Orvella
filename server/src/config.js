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
    dbPath: env.DB_PATH ?? './data/orvella.db',
    allowGuests: env.ALLOW_GUESTS ? env.ALLOW_GUESTS === '1' : !isProd,
    publicUrl: env.PUBLIC_URL ?? `http://localhost:${port}`,
    smtpHost: env.SMTP_HOST ?? '',
    smtpPort: Number(env.SMTP_PORT ?? 587),
    smtpUser: env.SMTP_USER ?? '',
    smtpPass: env.SMTP_PASS ?? '',
    mailFrom: env.MAIL_FROM ?? 'Orvella <no-reply@localhost>',
    turnSecret: env.TURN_SECRET ?? '',
    turnHost: env.TURN_HOST ?? '',
    googleClientId: env.GOOGLE_OAUTH_CLIENT_ID ?? '',
    googleClientSecret: env.GOOGLE_OAUTH_CLIENT_SECRET ?? '',
    accessTokenTtlSec: 3600,
    mediaTokenTtlSec: 6 * 3600,
    refreshGraceSec: 30 * 24 * 3600,
    maxMediaChunk: 16 * 1024 * 1024,
    logger: true,
  };
}
