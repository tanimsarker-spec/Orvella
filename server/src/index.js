import { fileURLToPath } from 'node:url';
import { loadConfig } from './config.js';
import { buildServer } from './app.js';

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const config = loadConfig();
  const app = await buildServer(config);
  await app.listen({ port: config.port, host: '0.0.0.0' });
}
