import { randomBytes, randomInt } from 'node:crypto';
import { Room } from './room.js';

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/**
 * In-memory store. Accounts and rooms are lost on restart.
 * Replace with a database (and migrations) before real production use.
 */
export class Store {
  users = new Map();
  rooms = new Map();
  codes = new Map();

  constructor(db = null) {
    this.db = db;
  }

  createUser(displayName) {
    const user = { id: randomBytes(12).toString('hex'), displayName };
    this.users.set(user.id, user);
    return user;
  }

  getUser(id) {
    const cached = this.users.get(id);
    if (cached) return cached;
    if (!this.db) return null;
    const row = this.db.prepare('SELECT id, display_name FROM users WHERE id = ?').get(id);
    if (!row) return null;
    const user = { id: row.id, displayName: row.display_name };
    this.users.set(id, user);
    return user;
  }

  findAccountByEmail(email) {
    if (!this.db) return null;
    return this.db.prepare('SELECT id, password_hash FROM users WHERE email = ?').get(email) ?? null;
  }

  setReset(email, codeHash, expiresAt) {
    this.db
      .prepare('INSERT OR REPLACE INTO password_resets (email, code_hash, expires_at, attempts, created_at) VALUES (?, ?, ?, 0, ?)')
      .run(email, codeHash, expiresAt, Date.now());
  }

  getReset(email) {
    return this.db?.prepare('SELECT * FROM password_resets WHERE email = ?').get(email) ?? null;
  }

  bumpResetAttempts(email) {
    this.db.prepare('UPDATE password_resets SET attempts = attempts + 1 WHERE email = ?').run(email);
  }

  deleteReset(email) {
    this.db.prepare('DELETE FROM password_resets WHERE email = ?').run(email);
  }

  updatePassword(id, passwordHash) {
    this.db.prepare('UPDATE users SET password_hash = ? WHERE id = ?').run(passwordHash, id);
  }

  createAccount({ email, displayName, passwordHash }) {
    const id = randomBytes(12).toString('hex');
    this.db
      .prepare('INSERT INTO users (id, email, display_name, password_hash, created_at) VALUES (?, ?, ?, ?, ?)')
      .run(id, email, displayName, passwordHash, Date.now());
    const user = { id, displayName };
    this.users.set(id, user);
    return user;
  }

  #newCode() {
    for (;;) {
      let code = '';
      for (let i = 0; i < 6; i += 1) code += ALPHABET[randomInt(ALPHABET.length)];
      if (!this.codes.has(code)) return code;
    }
  }

  createRoom(host, name, isPublic = false) {
    const room = new Room({
      id: randomBytes(9).toString('hex'),
      code: this.#newCode(),
      name,
      hostId: host.id,
      isPublic,
    });
    room.addMember(host);
    this.rooms.set(room.id, room);
    this.codes.set(room.code, room.id);
    return room;
  }

  getRoom(id) {
    return this.rooms.get(id) ?? null;
  }

  getRoomByCode(code) {
    const id = this.codes.get(String(code).toUpperCase());
    return id ? this.rooms.get(id) : null;
  }
}
