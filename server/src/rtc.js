import { createHmac } from 'node:crypto';

/**
 * ICE servers for WebRTC voice chat. When a TURN server is configured, credentials are short-lived
 * (coturn "use-auth-secret" REST scheme), so no long-term password is ever sent to clients.
 */
export function iceServers(config, userId, now = Date.now()) {
  const servers = [{ urls: 'stun:stun.l.google.com:19302' }];
  if (config.turnSecret && config.turnHost) {
    const expiry = Math.floor(now / 1000) + 6 * 3600;
    const username = `${expiry}:${userId}`;
    const credential = createHmac('sha1', config.turnSecret).update(username).digest('base64');
    servers.push({
      urls: [
        `stun:${config.turnHost}:3478`,
        `turn:${config.turnHost}:3478?transport=udp`,
        `turn:${config.turnHost}:3478?transport=tcp`,
      ],
      username,
      credential,
    });
  }
  return servers;
}
