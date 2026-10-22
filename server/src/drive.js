import { randomBytes } from 'node:crypto';

const SCOPE = 'https://www.googleapis.com/auth/drive.readonly';
const ID_RE = /^[A-Za-z0-9_-]{1,100}$/;

export class DriveError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

/**
 * Server-side Google OAuth (authorization-code flow) + Drive proxy.
 * Google tokens stay on the server (in memory) and are never sent to clients or room members.
 * Viewers can only stream the single file the host selected for the room.
 */
export class DriveManager {
  sessions = new Map();
  pending = new Map();

  constructor({ config, fetchImpl = fetch, now = () => Date.now() }) {
    this.config = config;
    this.fetchImpl = fetchImpl;
    this.now = now;
  }

  get enabled() {
    return Boolean(this.config.googleClientId && this.config.googleClientSecret);
  }

  get redirectUri() {
    return `${this.config.publicUrl}/drive/oauth/callback`;
  }

  authUrl(userId) {
    if (!this.enabled) throw new DriveError(501, 'drive_not_configured');
    const state = randomBytes(16).toString('hex');
    this.pending.set(state, { userId, expires: this.now() + 10 * 60 * 1000 });
    const p = new URLSearchParams({
      client_id: this.config.googleClientId,
      redirect_uri: this.redirectUri,
      response_type: 'code',
      scope: SCOPE,
      access_type: 'offline',
      prompt: 'consent',
      state,
    });
    return `https://accounts.google.com/o/oauth2/v2/auth?${p}`;
  }

  async handleCallback(code, state) {
    const p = this.pending.get(state);
    this.pending.delete(state);
    if (!p || p.expires < this.now()) throw new DriveError(400, 'invalid_state');
    const tok = await this.#tokenRequest({
      grant_type: 'authorization_code',
      code,
      redirect_uri: this.redirectUri,
    });
    if (!tok.refresh_token) throw new DriveError(502, 'no_refresh_token');
    this.sessions.set(p.userId, {
      refreshToken: tok.refresh_token,
      accessToken: tok.access_token,
      expiresAt: this.now() + (tok.expires_in - 60) * 1000,
    });
  }

  connected(userId) {
    return this.sessions.has(userId);
  }

  disconnect(userId) {
    this.sessions.delete(userId);
  }

  async #tokenRequest(params) {
    const res = await this.fetchImpl('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: this.config.googleClientId,
        client_secret: this.config.googleClientSecret,
        ...params,
      }),
    });
    if (!res.ok) throw new DriveError(502, 'token_request_failed');
    return res.json();
  }

  async accessToken(userId) {
    const s = this.sessions.get(userId);
    if (!s) throw new DriveError(401, 'drive_not_connected');
    if (s.expiresAt <= this.now()) {
      try {
        const tok = await this.#tokenRequest({ grant_type: 'refresh_token', refresh_token: s.refreshToken });
        s.accessToken = tok.access_token;
        s.expiresAt = this.now() + (tok.expires_in - 60) * 1000;
      } catch {
        this.sessions.delete(userId);
        throw new DriveError(401, 'drive_not_connected');
      }
    }
    return s.accessToken;
  }

  async #api(userId, url, headers = {}) {
    const token = await this.accessToken(userId);
    return this.fetchImpl(url, { headers: { ...headers, authorization: `Bearer ${token}` } });
  }

  async listVideos(userId, { parent = 'root', pageToken } = {}) {
    if (parent !== 'root' && !ID_RE.test(parent)) throw new DriveError(400, 'bad_parent');
    const q = `'${parent}' in parents and trashed=false and (mimeType='application/vnd.google-apps.folder' or mimeType contains 'video/')`;
    const p = new URLSearchParams({
      q,
      fields: 'nextPageToken, files(id,name,mimeType,size)',
      pageSize: '100',
      orderBy: 'folder,name',
      supportsAllDrives: 'true',
      includeItemsFromAllDrives: 'true',
    });
    if (pageToken) p.set('pageToken', String(pageToken).slice(0, 500));
    const res = await this.#api(userId, `https://www.googleapis.com/drive/v3/files?${p}`);
    if (!res.ok) throw new DriveError(res.status === 401 ? 401 : 502, 'drive_list_failed');
    return res.json();
  }

  async fileMeta(userId, fileId) {
    if (!ID_RE.test(fileId)) throw new DriveError(400, 'bad_file_id');
    const p = new URLSearchParams({ fields: 'id,name,mimeType,size', supportsAllDrives: 'true' });
    const res = await this.#api(userId, `https://www.googleapis.com/drive/v3/files/${fileId}?${p}`);
    if (!res.ok) throw new DriveError(res.status === 404 ? 404 : 502, 'drive_file_unavailable');
    const meta = await res.json();
    if (!String(meta.mimeType).startsWith('video/')) throw new DriveError(400, 'not_a_video');
    return { id: meta.id, name: meta.name, mime: meta.mimeType, size: Number(meta.size) };
  }

  media(userId, fileId, range) {
    if (!ID_RE.test(fileId)) throw new DriveError(400, 'bad_file_id');
    const url = `https://www.googleapis.com/drive/v3/files/${fileId}?alt=media&supportsAllDrives=true`;
    return this.#api(userId, url, { range: `bytes=${range.start}-${range.end}` });
  }
}
