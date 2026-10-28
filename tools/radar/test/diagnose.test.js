import test from 'node:test';
import assert from 'node:assert/strict';
import { diagnose } from '../src/diagnose.js';
import { probeHost, validHost } from '../src/probe.js';

const ok = (ms, value) => ({ ok: true, ms, value });
const bad = (error, ms = 5) => ({ ok: false, ms, error });
const base = { host: 'github.com', ip: '140.82.114.4' };

test('todo bien: resuelve y conecta rapido', () => {
  const d = diagnose({ ...base, system: ok(20, ['140.82.114.4']), cloudflare: ok(15), google: ok(18), tcp: ok(40) });
  assert.equal(d.status, 'ok'); assert.equal(d.severity, 0); assert.deepEqual(d.fixes, []);
});
test('lento si la conexion pasa de 600 ms', () => {
  assert.equal(diagnose({ ...base, system: ok(20), cloudflare: ok(1), google: ok(1), tcp: ok(900) }).status, 'slow');
  assert.equal(diagnose({ ...base, system: ok(1200), cloudflare: ok(1), google: ok(1), tcp: ok(10) }).status, 'slow');
});
test('el caso de github.com: el sistema falla pero los DNS publicos resuelven', () => {
  const d = diagnose({ ...base, system: bad('ENOTFOUND'), cloudflare: ok(20, ['140.82.114.4']), google: ok(25), tcp: ok(60) });
  assert.equal(d.status, 'dns_local'); assert.equal(d.severity, 2);
  assert.ok(d.fixes.some((f) => f.command.startsWith('sudo dscacheutil -flushcache')));
  assert.ok(d.fixes.some((f) => f.command === 'git -c http.curloptResolve=github.com:443:140.82.114.4 push'));
  assert.ok(d.fixes.some((f) => f.command === 'dig +short github.com @1.1.1.1'));
  assert.match(d.detail, /Cloudflare/);
});
test('si solo Google resuelve, lo dice', () => {
  const d = diagnose({ ...base, system: bad('ENOTFOUND'), cloudflare: bad('ETIMEOUT'), google: ok(20), tcp: ok(60) });
  assert.match(d.detail, /Google/);
});
test('sin IP valida no ofrece comandos con IP', () => {
  const d = diagnose({ host: 'x.com', ip: '1.2.3.4; rm -rf /', system: bad('ENOTFOUND'), cloudflare: ok(1), google: ok(1), tcp: bad('SIN_IP') });
  assert.equal(d.status, 'dns_local');
  assert.ok(d.fixes.every((f) => !f.command.includes(';')));
  assert.equal(d.fixes.some((f) => f.command.includes('curloptResolve')), false);
});
test('ningun DNS resuelve: probablemente sin red', () => {
  const d = diagnose({ host: 'x.com', ip: null, system: bad('ENOTFOUND'), cloudflare: bad('x'), google: bad('x'), tcp: bad('SIN_IP') });
  assert.equal(d.status, 'dns_total'); assert.equal(d.severity, 3);
});
test('resuelve pero no conecta', () => {
  const d = diagnose({ ...base, system: ok(10), cloudflare: ok(1), google: ok(1), tcp: bad('ECONNREFUSED') });
  assert.equal(d.status, 'tcp'); assert.ok(d.fixes[0].command.startsWith('nc -vz 140.82.114.4'));
});

test('valida nombres de host', () => {
  for (const h of ['github.com', 'api.github.com', 'a-b.example.org']) assert.equal(validHost(h), true, h);
  for (const h of ['', 'localhost', 'a b.com', 'x.com; rm', '-a.com', 'a..com', 'http://x.com', 'x.c', 'a'.repeat(300) + '.com', 5, null]) assert.equal(validHost(h), false, String(h));
});

test('probeHost junta los resultados con dependencias inyectadas', async () => {
  const deps = {
    resolveSystem: async () => bad('ENOTFOUND'),
    resolvePublic: async (_h, server) => (server === '1.1.1.1' ? ok(12, ['10.0.0.9']) : bad('x')),
    tcpConnect: async (ip) => (ip === '10.0.0.9' ? ok(33) : bad('ECONNREFUSED')),
  };
  const r = await probeHost('github.com', deps);
  assert.equal(r.ip, '10.0.0.9'); assert.equal(r.diagnosis.status, 'dns_local');
  assert.equal(r.tcp.ms, 33);
});
test('probeHost rechaza un host invalido sin tocar la red', async () => {
  await assert.rejects(() => probeHost('x.com; rm -rf /', { resolveSystem: () => { throw new Error('no debe llamarse'); } }), /no valido/);
});
