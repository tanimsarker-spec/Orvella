import { fileURLToPath } from 'node:url';
import { loadConfig } from './config.js';
import { buildServer } from './app.js';
import { openDb } from './db.js';
import { Store } from './store.js';

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const config = loadConfig();
  const db = await openDb(config.dbPath);
  const app = await buildServer(config, { store: new Store(db) });
  await app.listen({ port: config.port, host: '0.0.0.0' });
}
