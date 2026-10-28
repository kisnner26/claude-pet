import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { startServer } from '../src/server.js';

const fake = async (host) => ({ host, at: Date.now(), ip: '1.2.3.4', system: { ok: true, ms: 5 }, cloudflare: { ok: true, ms: 5 }, google: { ok: true, ms: 5 }, tcp: { ok: true, ms: 20 }, diagnosis: { status: 'ok', severity: 0, title: 'ok', detail: '', fixes: [] } });
const start = () => startServer({ hosts: ['github.com'], port: 0, interval: 3600000, probe: fake });
const call = (s, path, { method = 'GET', body, headers = {} } = {}) => fetch(s.url.slice(0, -1) + path, { method, body: body && JSON.stringify(body), headers: { 'x-radar-token': s.token, ...(body ? { 'content-type': 'application/json' } : {}), ...headers } });

test('exige token en la api', async () => {
  const s = await start();
  try {
    assert.equal((await fetch(s.url + 'api/state')).status, 403);
    assert.equal((await call(s, '/api/state')).status, 200);
  } finally { await s.close(); }
});
test('rechaza Host ajeno y Origin ajeno', async () => {
  const s = await start();
  try {
    const status = await new Promise((resolve) => http.get({ host: '127.0.0.1', port: s.port, path: '/api/state', headers: { host: 'evil.com', 'x-radar-token': s.token } }, (r) => { r.resume(); resolve(r.statusCode); }));
    assert.equal(status, 403);
    assert.equal((await call(s, '/api/add', { method: 'POST', body: { host: 'a.com' }, headers: { origin: 'http://evil.com' } })).status, 403);
  } finally { await s.close(); }
});
test('anade, sondea y quita hosts; rechaza nombres invalidos', async () => {
  const s = await start();
  try {
    let st = await (await call(s, '/api/add', { method: 'POST', body: { host: 'Example.org' } })).json();
    assert.deepEqual(st.hosts.map((h) => h.host).sort(), ['example.org', 'github.com']);
    assert.equal(st.hosts.find((h) => h.host === 'example.org').diagnosis.status, 'ok');
    assert.equal((await call(s, '/api/add', { method: 'POST', body: { host: 'x.com; rm -rf /' } })).status, 400);
    st = await (await call(s, '/api/remove', { method: 'POST', body: { host: 'example.org' } })).json();
    assert.equal(st.hosts.length, 1);
  } finally { await s.close(); }
});
test('la pagina lleva el token y no queda marcador', async () => {
  const s = await start();
  try { const html = await (await fetch(s.url)).text(); assert.ok(html.includes(s.token)); assert.ok(!html.includes('__TOKEN__')); } finally { await s.close(); }
});
