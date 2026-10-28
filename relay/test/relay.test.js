import { test } from 'node:test';
import assert from 'node:assert/strict';
import net from 'node:net';
import { startRelay, parsePreamble, TOKENS } from '../relay.js';

const ROOM = 'a'.repeat(32), OTHER = 'b'.repeat(32);
const open = (port) => new Promise((res, rej) => { const s = net.connect(port, '127.0.0.1', () => res(s)); s.on('error', rej); });
const read = (s, n, ms = 2000) => new Promise((res, rej) => {
  let buf = Buffer.alloc(0); const t = setTimeout(() => rej(new Error('sin datos')), ms);
  const on = (c) => { buf = Buffer.concat([buf, c]); if (buf.length >= n) { clearTimeout(t); s.off('data', on); s.pause(); res(buf); } };
  s.on('data', on); s.resume();
});
const closes = (s, ms = 2000) => new Promise((res, rej) => { const t = setTimeout(() => rej(new Error('no se cerro')), ms); s.on('close', () => { clearTimeout(t); res(); }); s.resume(); });

test('el saludo solo acepta HOST y JOIN con una sala de 32 hex', () => {
  assert.deepEqual(parsePreamble('HOST ' + ROOM), { kind: 'HOST', room: ROOM });
  assert.deepEqual(parsePreamble('JOIN ' + ROOM), { kind: 'JOIN', room: ROOM });
  for (const bad of ['', 'HOST', 'HOST x', 'GET / HTTP/1.1', 'HOST ' + 'A'.repeat(32), 'HOST ' + 'a'.repeat(31), 'HOST ' + ROOM + ' extra', 'host ' + ROOM]) assert.equal(parsePreamble(bad), null, bad);
});

test('una Mac espera, un movil se empareja y los bytes pasan en los dos sentidos', async () => {
  const r = await startRelay({ port: 0, host: '127.0.0.1' });
  const mac = await open(r.port); mac.write(`HOST ${ROOM}\n`);
  assert.equal((await read(mac, 8)).toString(), TOKENS.ready);
  const phone = await open(r.port); phone.write(`JOIN ${ROOM}\n`);
  assert.equal((await read(phone, 8)).toString(), TOKENS.ok);
  assert.equal((await read(mac, 8)).toString(), TOKENS.pair);
  phone.write('hola mac'); assert.equal((await read(mac, 8)).toString(), 'hola mac');
  mac.write('hola movil'); assert.equal((await read(phone, 10)).toString(), 'hola movil');
  assert.equal(r.stats.paired, 1);
  phone.destroy(); await closes(mac);       // al cerrar uno se cierra el otro
  await r.close();
});

test('sin Mac esperando el movil recibe RELAYNOH y se cierra', async () => {
  const r = await startRelay({ port: 0, host: '127.0.0.1' });
  const phone = await open(r.port); phone.write(`JOIN ${ROOM}\n`);
  assert.equal((await read(phone, 8)).toString(), TOKENS.noHost);
  await closes(phone);
  await r.close();
});

test('las salas no se mezclan', async () => {
  const r = await startRelay({ port: 0, host: '127.0.0.1' });
  const mac = await open(r.port); mac.write(`HOST ${ROOM}\n`); await read(mac, 8);
  const other = await open(r.port); other.write(`JOIN ${OTHER}\n`);
  assert.equal((await read(other, 8)).toString(), TOKENS.noHost);
  await r.close();
});

test('cada Mac en espera se empareja con un solo movil', async () => {
  const r = await startRelay({ port: 0, host: '127.0.0.1' });
  const mac = await open(r.port); mac.write(`HOST ${ROOM}\n`); await read(mac, 8);
  const a = await open(r.port); a.write(`JOIN ${ROOM}\n`); assert.equal((await read(a, 8)).toString(), TOKENS.ok);
  const b = await open(r.port); b.write(`JOIN ${ROOM}\n`); assert.equal((await read(b, 8)).toString(), TOKENS.noHost);
  await r.close();
});

test('varias Macs en espera de la misma sala atienden a varios moviles', async () => {
  const r = await startRelay({ port: 0, host: '127.0.0.1' });
  const m1 = await open(r.port); m1.write(`HOST ${ROOM}\n`); await read(m1, 8);
  const m2 = await open(r.port); m2.write(`HOST ${ROOM}\n`); await read(m2, 8);
  const a = await open(r.port); a.write(`JOIN ${ROOM}\n`); assert.equal((await read(a, 8)).toString(), TOKENS.ok);
  const b = await open(r.port); b.write(`JOIN ${ROOM}\n`); assert.equal((await read(b, 8)).toString(), TOKENS.ok);
  await r.close();
});

test('un saludo roto, enorme o que no llega se corta', async () => {
  const r = await startRelay({ port: 0, host: '127.0.0.1', helloMs: 300 });
  const bad = await open(r.port); bad.write('GET / HTTP/1.1\r\n\r\n'); await closes(bad);
  const huge = await open(r.port); huge.write(Buffer.alloc(200, 65)); await closes(huge);
  const silent = await open(r.port); await closes(silent);
  await r.close();
});

test('una Mac que habla antes de emparejarse se corta', async () => {
  const r = await startRelay({ port: 0, host: '127.0.0.1' });
  const mac = await open(r.port); mac.write(`HOST ${ROOM}\n`); await read(mac, 8);
  mac.write('intruso'); await closes(mac);
  await r.close();
});

test('limites: conexiones por IP y esperas por sala', async () => {
  const r = await startRelay({ port: 0, host: '127.0.0.1', maxPerIp: 3, maxIdlePerRoom: 2 });
  const held = [];
  for (let i = 0; i < 3; i++) { const s = await open(r.port); held.push(s); }
  const over = await open(r.port); await closes(over);       // la cuarta conexion de la misma IP se rechaza
  held.forEach((s) => s.destroy());
  await r.close();
  const r2 = await startRelay({ port: 0, host: '127.0.0.1', maxIdlePerRoom: 2 });
  const macs = [];
  for (let i = 0; i < 3; i++) { const m = await open(r2.port); m.write(`HOST ${ROOM}\n`); await read(m, 8); macs.push(m); }
  await closes(macs[0]);                                       // la mas vieja cede su sitio
  assert.equal(r2.rooms.get(ROOM).length, 2);
  await r2.close();
});

test('limite de intentos de unirse por minuto', async () => {
  const r = await startRelay({ port: 0, host: '127.0.0.1', joinsPerMinute: 3 });
  for (let i = 0; i < 3; i++) { const p = await open(r.port); p.write(`JOIN ${ROOM}\n`); assert.equal((await read(p, 8)).toString(), TOKENS.noHost); }
  const p = await open(r.port); p.write(`JOIN ${ROOM}\n`); await closes(p);
  await r.close();
});
