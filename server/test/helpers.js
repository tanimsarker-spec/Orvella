import WebSocket from 'ws';
import { buildServer } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { openDb } from '../src/db.js';
import { Store } from '../src/store.js';

export async function startServer({ fetchImpl, env = {}, dbPath = ':memory:', mailer } = {}) {
  const config = { ...loadConfig({ JWT_SECRET: 'x'.repeat(40), ...env }), logger: false };
  const store = new Store(await openDb(dbPath));
  const app = await buildServer(config, { fetchImpl, store, mailer });
  await app.listen({ port: 0, host: '127.0.0.1' });
  const port = app.server.address().port;
  const base = `http://127.0.0.1:${port}`;
  const wsBase = `ws://127.0.0.1:${port}`;
  config.publicUrl = base;

  const api = async (method, path, { token, body, headers } = {}) => {
    const res = await fetch(base + path, {
      method,
      headers: {
        ...(body ? { 'content-type': 'application/json' } : {}),
        ...(token ? { authorization: `Bearer ${token}` } : {}),
        ...headers,
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    const text = await res.text();
    let json = null;
    try { json = JSON.parse(text); } catch { /* not json */ }
    return { status: res.status, json, text, headers: res.headers };
  };
  const guest = async (displayName) => (await api('POST', '/auth/guest', { body: { displayName } })).json;
  return { app, base, wsBase, api, guest, config };
}

export function openWs(url, token) {
  const ws = new WebSocket(url, { headers: token ? { authorization: `Bearer ${token}` } : {} });
  const queue = [];
  const waiters = [];
  const flush = () => [...waiters].forEach((w) => w());
  ws.on('message', (data, isBinary) => {
    queue.push(isBinary ? { binary: data } : JSON.parse(data.toString()));
    flush();
  });
  const opened = new Promise((resolve, reject) => {
    ws.once('open', resolve);
    ws.once('error', reject);
  });
  const closed = new Promise((resolve) => ws.once('close', (code) => resolve(code)));
  const next = (pred = () => true, timeout = 3000) =>
    new Promise((resolve, reject) => {
      const take = () => {
        const i = queue.findIndex(pred);
        if (i < 0) return false;
        resolve(queue.splice(i, 1)[0]);
        return true;
      };
      if (take()) return;
      const w = () => {
        if (take()) {
          clearTimeout(timer);
          waiters.splice(waiters.indexOf(w), 1);
        }
      };
      const timer = setTimeout(() => {
        waiters.splice(waiters.indexOf(w), 1);
        reject(new Error('timeout waiting for message'));
      }, timeout);
      waiters.push(w);
    });
  return {
    ws, opened, closed, next,
    send: (o) => ws.send(JSON.stringify(o)),
    close: () => ws.close(),
  };
}

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
