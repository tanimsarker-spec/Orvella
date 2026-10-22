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

  createUser(displayName) {
    const user = { id: randomBytes(12).toString('hex'), displayName };
    this.users.set(user.id, user);
    return user;
  }

  getUser(id) {
    return this.users.get(id) ?? null;
  }

  #newCode() {
    for (;;) {
      let code = '';
      for (let i = 0; i < 6; i += 1) code += ALPHABET[randomInt(ALPHABET.length)];
      if (!this.codes.has(code)) return code;
    }
  }

  createRoom(host, name) {
    const room = new Room({
      id: randomBytes(9).toString('hex'),
      code: this.#newCode(),
      name,
      hostId: host.id,
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
