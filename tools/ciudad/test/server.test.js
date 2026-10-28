import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { startServer } from '../src/server.js';

const scan = async () => [{ name: 'a', commits: 4, recent: 2, last: 1, files: 3, language: 'Swift', dirty: 0 }];
const start = () => startServer({ dir: '/x/proyectos', port: 0, scan });
const get = (s, path, headers = {}, method = 'GET') => new Promise((resolve) => { const q = http.request({ host: '127.0.0.1', port: s.port, path, headers, method }, (r) => { let b = ''; r.on('data', (c) => (b += c)); r.on('end', () => resolve({ status: r.statusCode, body: b })); }); q.end(); });

test('la api exige token y devuelve la ciudad', async () => {
  const s = await start();
  try {
    assert.equal((await get(s, '/api/city')).status, 403);
    const r = await get(s, '/api/city', { 'x-ciudad-token': s.token });
    const j = JSON.parse(r.body);
    assert.equal(r.status, 200); assert.equal(j.name, 'proyectos'); assert.equal(j.buildings.length, 1);
  } finally { await s.close(); }
});
test('rechaza Host ajeno y escritura', async () => {
  const s = await start();
  try {
    assert.equal((await get(s, '/api/city', { host: 'evil.com', 'x-ciudad-token': s.token })).status, 403);
    assert.equal((await get(s, '/api/city', { 'x-ciudad-token': s.token }, 'POST')).status, 405);
  } finally { await s.close(); }
});
test('la pagina lleva el token', async () => {
  const s = await start();
  try { const r = await get(s, '/'); assert.ok(r.body.includes(s.token)); assert.ok(!r.body.includes('__TOKEN__')); } finally { await s.close(); }
});
