import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { startServer } from '../src/server.js';

const hist = { root: '/x/mi-repo', commits: [{ hash: '1', at: 1000, author: 'a', files: ['a.js', 'b.js'] }, { hash: '2', at: 2000, author: 'a', files: ['a.js', 'b.js'] }], tracked: new Set(['a.js', 'b.js']) };
const start = () => startServer({ port: 0, load: async () => hist });
const get = (s, path, headers = {}) => new Promise((resolve) => http.get({ host: '127.0.0.1', port: s.port, path, headers }, (r) => { let b = ''; r.on('data', (c) => (b += c)); r.on('end', () => resolve({ status: r.statusCode, body: b })); }));

test('la api exige token', async () => {
  const s = await start();
  try {
    assert.equal((await get(s, '/api/galaxy')).status, 403);
    const r = await get(s, '/api/galaxy', { 'x-galaxia-token': s.token });
    const j = JSON.parse(r.body);
    assert.equal(r.status, 200); assert.equal(j.name, 'mi-repo'); assert.equal(j.stars.length, 2); assert.equal(j.links.length, 1);
  } finally { await s.close(); }
});
test('rechaza Host ajeno y metodos de escritura', async () => {
  const s = await start();
  try {
    assert.equal((await get(s, '/api/galaxy', { host: 'evil.com', 'x-galaxia-token': s.token })).status, 403);
    const st = await new Promise((resolve) => { const q = http.request({ host: '127.0.0.1', port: s.port, path: '/api/galaxy', method: 'POST' }, (r) => { r.resume(); resolve(r.statusCode); }); q.end(); });
    assert.equal(st, 405);
  } finally { await s.close(); }
});
test('la pagina lleva el token', async () => {
  const s = await start();
  try { const r = await get(s, '/'); assert.ok(r.body.includes(s.token)); assert.ok(!r.body.includes('__TOKEN__')); } finally { await s.close(); }
});
