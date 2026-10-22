const isInt = (v, min, max) => Number.isInteger(v) && v >= min && v <= max;
const isStr = (v, min, max) => typeof v === 'string' && v.length >= min && v.length <= max;
const POS_MAX = 24 * 3600 * 1000;

export function validateSource(s) {
  if (!s || typeof s !== 'object') return null;
  if (!isStr(s.name, 1, 200)) return null;
  switch (s.kind) {
    case 'local':
      if (!isInt(s.size, 1, 2 ** 50) || !/^video\/[\w.+-]{1,60}$/.test(s.mime ?? '')) return null;
      return { kind: 'local', name: s.name, size: s.size, mime: s.mime };
    case 'drive':
      if (!/^[A-Za-z0-9_-]{5,100}$/.test(s.fileId ?? '')) return null;
      return { kind: 'drive', name: s.name, fileId: s.fileId };
    case 'url': {
      if (!isStr(s.url, 8, 2000)) return null;
      let u;
      try { u = new URL(s.url); } catch { return null; }
      if (u.protocol !== 'https:' && u.protocol !== 'http:') return null;
      return { kind: 'url', name: s.name, url: u.toString() };
    }
    default:
      return null;
  }
}

/** Validate a parsed client WebSocket message. Returns { ok, value } or { ok:false, error }. */
export function validateClientMessage(m) {
  if (!m || typeof m !== 'object' || typeof m.type !== 'string') return { ok: false, error: 'bad_message' };
  switch (m.type) {
    case 'ping':
      return Number.isFinite(m.t) ? { ok: true, value: { type: 'ping', t: m.t } } : { ok: false, error: 'bad_ping' };
    case 'play':
    case 'pause':
      if (m.positionMs !== undefined && !isInt(m.positionMs, 0, POS_MAX)) return { ok: false, error: 'bad_position' };
      return { ok: true, value: { type: m.type, positionMs: m.positionMs } };
    case 'seek':
      return isInt(m.positionMs, 0, POS_MAX)
        ? { ok: true, value: { type: 'seek', positionMs: m.positionMs } }
        : { ok: false, error: 'bad_position' };
    case 'buffering':
      return typeof m.value === 'boolean'
        ? { ok: true, value: { type: 'buffering', value: m.value } }
        : { ok: false, error: 'bad_buffering' };
    case 'chat':
      return isStr(m.text, 1, 500) && m.text.trim().length > 0
        ? { ok: true, value: { type: 'chat', text: m.text.trim() } }
        : { ok: false, error: 'bad_chat' };
    case 'setControlMode':
      return m.mode === 'everyone' || m.mode === 'host'
        ? { ok: true, value: { type: 'setControlMode', mode: m.mode } }
        : { ok: false, error: 'bad_mode' };
    case 'setSource': {
      const source = validateSource(m.source);
      return source ? { ok: true, value: { type: 'setSource', source } } : { ok: false, error: 'bad_source' };
    }
    case 'signal':
      if (!isStr(m.to, 1, 64) || !m.data || typeof m.data !== 'object') return { ok: false, error: 'bad_signal' };
      if (JSON.stringify(m.data).length > 8192) return { ok: false, error: 'signal_too_large' };
      return { ok: true, value: { type: 'signal', to: m.to, data: m.data } };
    default:
      return { ok: false, error: 'unknown_type' };
  }
}
