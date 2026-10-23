export class Room {
  constructor({ id, code, name, hostId, isPublic = false, now = () => Date.now() }) {
    this.id = id;
    this.code = code;
    this.name = name;
    this.hostId = hostId;
    this.isPublic = isPublic;
    this.now = now;
    this.playing = false;
    this.positionMs = 0;
    this.updatedAt = now();
    this.revision = 0;
    this.source = null;
    this.controlMode = 'everyone';
    this.buffering = new Set();
    /** userId -> { user, sockets:Set } */
    this.members = new Map();
  }

  addMember(user) {
    if (!this.members.has(user.id)) this.members.set(user.id, { user, sockets: new Set() });
    return this.members.get(user.id);
  }

  currentPositionMs() {
    return this.playing ? this.positionMs + (this.now() - this.updatedAt) : this.positionMs;
  }

  canControl(userId) {
    return this.controlMode === 'everyone' || userId === this.hostId;
  }

  snapshot() {
    return {
      type: 'state',
      revision: this.revision,
      playing: this.playing,
      positionMs: this.positionMs,
      updatedAt: this.updatedAt,
      serverNow: this.now(),
      source: this.source,
      hostId: this.hostId,
      controlMode: this.controlMode,
      isPublic: this.isPublic,
      buffering: [...this.buffering],
      participants: [...this.members.values()].map((m) => ({
        id: m.user.id,
        displayName: m.user.displayName,
        online: m.sockets.size > 0,
      })),
    };
  }

  #commit(playing, positionMs) {
    this.playing = playing;
    this.positionMs = Math.max(0, Math.floor(positionMs));
    this.updatedAt = this.now();
    this.revision += 1;
  }

  /** Apply a validated client message. Returns { ok } or { ok:false, code }. */
  apply(userId, msg) {
    switch (msg.type) {
      case 'play':
        if (!this.canControl(userId)) return { ok: false, code: 'forbidden' };
        this.#commit(true, msg.positionMs ?? this.currentPositionMs());
        return { ok: true };
      case 'pause':
        if (!this.canControl(userId)) return { ok: false, code: 'forbidden' };
        this.#commit(false, msg.positionMs ?? this.currentPositionMs());
        return { ok: true };
      case 'seek':
        if (!this.canControl(userId)) return { ok: false, code: 'forbidden' };
        this.#commit(this.playing, msg.positionMs);
        return { ok: true };
      case 'setSource':
        if (userId !== this.hostId) return { ok: false, code: 'forbidden' };
        this.source = msg.source;
        this.buffering.clear();
        this.#commit(false, 0);
        return { ok: true };
      case 'setControlMode':
        if (userId !== this.hostId) return { ok: false, code: 'forbidden' };
        this.controlMode = msg.mode;
        this.revision += 1;
        return { ok: true };
      case 'setPublic':
        if (userId !== this.hostId) return { ok: false, code: 'forbidden' };
        this.isPublic = msg.value;
        this.revision += 1;
        return { ok: true };
      case 'buffering':
        if (msg.value) this.buffering.add(userId);
        else this.buffering.delete(userId);
        this.revision += 1;
        return { ok: true };
      default:
        return { ok: false, code: 'unknown' };
    }
  }
}
