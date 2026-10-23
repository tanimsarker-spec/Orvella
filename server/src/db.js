import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

/** Opens the SQLite database and applies forward-only migrations (tracked by PRAGMA user_version). */
export async function openDb(path) {
  let DatabaseSync;
  try {
    ({ DatabaseSync } = await import('node:sqlite'));
  } catch {
    throw new Error('Node.js 22.13 or newer is required (built-in node:sqlite).');
  }
  if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true });
  const db = new DatabaseSync(path);
  db.exec('PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;');
  const { user_version: version } = db.prepare('PRAGMA user_version').get();
  if (version < 1) {
    db.exec(`
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        email TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
      PRAGMA user_version = 1;
    `);
  }
  if (version < 2) {
    db.exec(`
      CREATE TABLE password_resets (
        email TEXT PRIMARY KEY,
        code_hash TEXT NOT NULL,
        expires_at INTEGER NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      );
      PRAGMA user_version = 2;
    `);
  }
  return db;
}
