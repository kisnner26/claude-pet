#!/usr/bin/env node
// Relay de Visto: une la Mac y el movil cuando no estan en la misma red. No lee nada: tras el saludo solo copia bytes de un lado al otro,
// y esos bytes ya van cifrados de extremo a extremo con una clave que sale del codigo de emparejamiento, que el relay no conoce.
// Protocolo (una linea de texto al empezar y luego bytes opacos):
//   la Mac:   "HOST <sala>\n"  -> "RELAYRDY" (8 bytes) y espera en silencio hasta que llegue un movil -> "RELAYPAR"
//   el movil: "JOIN <sala>\n"  -> "RELAYOK!" si hay una Mac esperando, o "RELAYNOH" y se cierra
// La sala es un hash del codigo: nadie puede sacar el codigo de ella. Cero dependencias.
import net from 'node:net';
import tls from 'node:tls';
import fs from 'node:fs';
import { pathToFileURL } from 'node:url';

export const TOKENS = { ready: 'RELAYRDY', pair: 'RELAYPAR', ok: 'RELAYOK!', noHost: 'RELAYNOH' };
const ROOM = /^[0-9a-f]{32}$/;

export function parsePreamble(line) {
  const m = /^(HOST|JOIN) ([0-9a-f]{32})$/.exec(line);
  return m ? { kind: m[1], room: m[2] } : null;
}

export function startRelay({ port = 7777, host = '0.0.0.0', cert, key, maxIdlePerRoom = 6, maxRooms = 2000, maxPerIp = 40, joinsPerMinute = 30, idleMs = 15 * 60_000, sessionIdleMs = 60 * 60_000, helloMs = 10_000 } = {}) {
  const rooms = new Map();           // sala -> sockets de Macs esperando
  const perIp = new Map();           // ip -> conexiones abiertas
  const joins = new Map();           // ip -> instantes de los JOIN del ultimo minuto
  const stats = { hosted: 0, paired: 0, refused: 0 };
  const sockets = new Set();

  const idleOf = (room) => rooms.get(room) ?? [];
  const forget = (room, s) => { const l = idleOf(room).filter((x) => x !== s); if (l.length) rooms.set(room, l); else rooms.delete(room); };

  const handler = (socket) => {
    const ip = socket.remoteAddress ?? '?';
    sockets.add(socket); socket.on('close', () => sockets.delete(socket));
    const count = (perIp.get(ip) ?? 0) + 1;
    perIp.set(ip, count);
    socket.on('close', () => { const n = (perIp.get(ip) ?? 1) - 1; if (n <= 0) perIp.delete(ip); else perIp.set(ip, n); });
    socket.on('error', () => socket.destroy());
    if (count > maxPerIp) { stats.refused++; return socket.destroy(); }
    socket.setNoDelay(true);
    socket.setKeepAlive(true, 30_000);

    let buf = Buffer.alloc(0);
    const timer = setTimeout(() => socket.destroy(), helloMs);   // quien no saluda a tiempo se corta
    const onData = (chunk) => {
      buf = Buffer.concat([buf, chunk]);
      const nl = buf.indexOf(0x0a);
      if (nl < 0) { if (buf.length > 64) { stats.refused++; socket.destroy(); } return; }
      socket.off('data', onData); clearTimeout(timer); socket.pause();
      const hello = parsePreamble(buf.subarray(0, nl).toString('latin1'));
      const rest = buf.subarray(nl + 1);
      if (!hello) { stats.refused++; return socket.destroy(); }
      hello.kind === 'HOST' ? onHost(socket, hello.room, rest) : onJoin(socket, hello.room, rest, ip);
    };
    socket.on('data', onData);
  };

  function onHost(socket, room, rest) {
    if (rest.length) return socket.destroy();     // una Mac no habla hasta que la emparejan
    if (!rooms.has(room) && rooms.size >= maxRooms) { stats.refused++; return socket.destroy(); }
    if (idleOf(room).length >= maxIdlePerRoom) { const old = idleOf(room)[0]; old.destroy(); }     // la mas vieja cede su sitio
    rooms.set(room, [...idleOf(room), socket]);
    stats.hosted++;
    socket.write(TOKENS.ready);
    socket.setTimeout(idleMs, () => socket.destroy());
    socket.on('close', () => forget(room, socket));
    socket.resume();
    // si la Mac manda algo antes de ser emparejada, algo va mal
    socket.once('data', () => { if (idleOf(room).includes(socket)) socket.destroy(); });
  }

  function onJoin(client, room, rest, ip) {
    const now = Date.now();
    const recent = (joins.get(ip) ?? []).filter((t) => now - t < 60_000);
    recent.push(now); joins.set(ip, recent);
    if (recent.length > joinsPerMinute) { stats.refused++; return client.destroy(); }
    let hostSocket;
    while ((hostSocket = idleOf(room).shift())) {
      forget(room, hostSocket);
      if (!hostSocket.destroyed && hostSocket.writable) break;
      hostSocket = undefined;
    }
    if (!hostSocket) { client.end(TOKENS.noHost); return; }
    hostSocket.removeAllListeners('data'); hostSocket.setTimeout(0);
    stats.paired++;
    hostSocket.write(TOKENS.pair);
    client.write(TOKENS.ok);
    if (rest.length) hostSocket.write(rest);
    for (const s of [hostSocket, client]) s.setTimeout(sessionIdleMs, () => { hostSocket.destroy(); client.destroy(); });
    hostSocket.pipe(client); client.pipe(hostSocket);
    const end = () => { hostSocket.destroy(); client.destroy(); };
    hostSocket.on('close', end); client.on('close', end);
    hostSocket.resume(); client.resume();
  }

  const server = cert && key ? tls.createServer({ cert: fs.readFileSync(cert), key: fs.readFileSync(key) }, handler) : net.createServer(handler);
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, host, () => resolve({ port: server.address().port, stats, rooms, close: () => new Promise((r) => { for (const s of sockets) s.destroy(); server.close(() => r()); }) }));
  });
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);
  if (args.includes('-h') || args.includes('--help')) {
    console.log('uso: node relay.js [--port 7777] [--host 0.0.0.0] [--cert cert.pem --key key.pem]\n  sin --cert/--key escucha en claro (el trafico de Visto ya va cifrado de extremo a extremo).');
    process.exit(0);
  }
  const opt = (name, def) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : def; };
  const r = await startRelay({ port: Number(opt('--port', 7777)), host: opt('--host', '0.0.0.0'), cert: opt('--cert'), key: opt('--key') });
  console.log(`relay de visto en el puerto ${r.port}${opt('--cert') ? ' (tls)' : ''}`);
  process.on('SIGTERM', () => r.close().then(() => process.exit(0)));
}
