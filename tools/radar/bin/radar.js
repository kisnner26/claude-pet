#!/usr/bin/env node
import { startServer, DEFAULT_HOSTS } from '../src/server.js';
import { validHost } from '../src/probe.js';

const args = process.argv.slice(2);
if (args.includes('-h') || args.includes('--help')) {
  console.log('uso: radar [host ...] [--port 4848]\n  sin hosts vigila: ' + DEFAULT_HOSTS.join(', '));
  process.exit(0);
}
let port = 4848; const hosts = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--port') port = Number(args[++i]);
  else if (args[i] === '--no-open') continue;
  else if (validHost(args[i])) hosts.push(args[i].toLowerCase());
  else { console.error(`argumento no valido: ${args[i]}`); process.exit(2); }
}
const s = await startServer({ hosts: hosts.length ? hosts : DEFAULT_HOSTS, port });
console.log(`radar en ${s.url}`);
if (process.platform === 'darwin' && !args.includes('--no-open')) (await import('node:child_process')).spawn('open', [s.url], { stdio: 'ignore', detached: true }).unref();
