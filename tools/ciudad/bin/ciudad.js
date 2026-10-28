#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { startServer } from '../src/server.js';

const args = process.argv.slice(2);
if (args.includes('-h') || args.includes('--help')) { console.log('uso: ciudad [carpeta-con-repos] [--port 5050] [--no-open]'); process.exit(0); }
let port = 5050, dir = process.cwd(), open = true;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--port') port = Number(args[++i]);
  else if (args[i] === '--no-open') open = false;
  else if (!args[i].startsWith('-')) dir = args[i];
  else { console.error(`argumento no valido: ${args[i]}`); process.exit(2); }
}
try {
  const s = await startServer({ dir, port });
  console.log(`ciudad de ${s.name} en ${s.url}`);
  if (open && process.platform === 'darwin') spawn('open', [s.url], { stdio: 'ignore', detached: true }).unref();
} catch (e) { console.error(`no se pudo leer la carpeta: ${e.message}`); process.exit(1); }
