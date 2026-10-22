/**
 * Relay for host-selected local files. The host app keeps one WebSocket open; viewers do
 * HTTP Range requests against the server, which forwards each range to the host and streams
 * the bytes back. Viewers never connect to the host directly, so no VPN or router setup is needed.
 *
 * Host protocol:
 *   server -> host (text): {type:'range', id, start, end} | {type:'cancel', id}
 *   host -> server (binary): 4-byte big-endian id + payload bytes
 *   host -> server (text):   {type:'end', id} | {type:'error', id}
 */
export class MediaRelay {
  hosts = new Map();

  constructor({ stallTimeoutMs = 20000 } = {}) {
    this.stallTimeoutMs = stallTimeoutMs;
  }

  hostFor(roomId) {
    return this.hosts.get(roomId) ?? null;
  }

  registerHost(roomId, socket) {
    const old = this.hosts.get(roomId);
    if (old) {
      this.#failAll(old);
      old.socket.close(4409, 'replaced');
    }
    const host = { socket, nextId: 1, pending: new Map() };
    this.hosts.set(roomId, host);

    socket.on('message', (data, isBinary) => {
      if (isBinary) {
        if (data.length < 5) return;
        const p = host.pending.get(data.readUInt32BE(0));
        if (!p) return;
        this.#onChunk(host, data.readUInt32BE(0), p, data.subarray(4));
        return;
      }
      let msg;
      try { msg = JSON.parse(data.toString()); } catch { return; }
      const p = host.pending.get(msg?.id);
      if (!p) return;
      if (msg.type === 'end') {
        if (p.remaining > 0) this.#fail(host, msg.id, p);
        else this.#finish(host, msg.id, p);
      } else if (msg.type === 'error') {
        this.#fail(host, msg.id, p);
      }
    });

    socket.on('close', () => {
      this.#failAll(host);
      if (this.hosts.get(roomId) === host) this.hosts.delete(roomId);
    });
  }

  #arm(host, id, p) {
    clearTimeout(p.timer);
    p.timer = setTimeout(() => this.#fail(host, id, p), this.stallTimeoutMs);
  }

  #onChunk(host, id, p, chunk) {
    const slice = chunk.length > p.remaining ? chunk.subarray(0, p.remaining) : chunk;
    p.remaining -= slice.length;
    p.res.write(slice);
    if (p.remaining <= 0) this.#finish(host, id, p);
    else this.#arm(host, id, p);
  }

  #finish(host, id, p) {
    clearTimeout(p.timer);
    host.pending.delete(id);
    p.res.end();
  }

  #fail(host, id, p) {
    clearTimeout(p.timer);
    host.pending.delete(id);
    p.res.destroy();
  }

  #failAll(host) {
    for (const [id, p] of [...host.pending]) this.#fail(host, id, p);
  }

  /** Stream bytes [range.start, range.end] of the host's file into the raw response. */
  serve(host, res, source, range) {
    const id = host.nextId;
    host.nextId = host.nextId >= 0xffffffff ? 1 : host.nextId + 1;
    const length = range.end - range.start + 1;
    const headers = {
      'content-type': source.mime,
      'accept-ranges': 'bytes',
      'content-length': String(length),
      'cache-control': 'no-store',
    };
    if (range.partial) headers['content-range'] = `bytes ${range.start}-${range.end}/${source.size}`;
    res.writeHead(range.partial ? 206 : 200, headers);

    const p = { res, remaining: length, timer: null };
    host.pending.set(id, p);
    this.#arm(host, id, p);
    res.on('close', () => {
      if (host.pending.get(id) === p) {
        clearTimeout(p.timer);
        host.pending.delete(id);
        if (host.socket.readyState === 1) host.socket.send(JSON.stringify({ type: 'cancel', id }));
      }
    });
    host.socket.send(JSON.stringify({ type: 'range', id, start: range.start, end: range.end }));
  }
}
