import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import { scanRepo } from './scan.js';

const PUBLIC = join(dirname(fileURLToPath(import.meta.url)), '..', 'public');
const STATIC = { '/': ['index.html', 'text/html; charset=utf-8'], '/app.css': ['app.css', 'text/css; charset=utf-8'], '/app.js': ['app.js', 'text/javascript; charset=utf-8'] };
export async function startServer({ dir = process.cwd(), port = 4747, scan = scanRepo } = {}) {
  const token = randomBytes(24).toString('hex'), root = resolve(dir); let cache;
  const data = async (fresh) => { if (!cache || fresh || Date.now() - cache.at > 12000) cache = await scan(root); return cache; };
  await data(true);
  const send = (res, code, body, type = 'application/json; charset=utf-8') => { res.writeHead(code, { 'content-type': type, 'cache-control': 'no-store', 'x-content-type-options': 'nosniff', 'content-security-policy': "default-src 'self'; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'" }); res.end(typeof body === 'string' ? body : JSON.stringify(body)); };
  const server = createServer(async (req, res) => { try {
    const p = server.address().port, host = String(req.headers.host ?? '').toLowerCase(); if (![`127.0.0.1:${p}`, `localhost:${p}`].includes(host)) return send(res, 403, { error: 'host no permitido' });
    const url = new URL(req.url, `http://127.0.0.1:${p}`); if (req.method !== 'GET') return send(res, 405, { error: 'solo lectura' });
    if (STATIC[url.pathname]) { const [file, type] = STATIC[url.pathname]; let body = readFileSync(join(PUBLIC, file), 'utf8'); if (file === 'index.html') body = body.replace('__TOKEN__', token); return send(res, 200, body, type); }
    const got = Buffer.from(String(req.headers['x-trazo-token'] ?? '')), want = Buffer.from(token); if (url.pathname !== '/api/state') return send(res, 404, { error: 'no existe' }); if (got.length !== want.length || !timingSafeEqual(got, want)) return send(res, 403, { error: 'token no válido' });
    return send(res, 200, await data(url.searchParams.get('fresh') === '1'));
  } catch (e) { send(res, 500, { error: e.message }); } });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, '127.0.0.1', resolve); }); const actual = server.address().port;
  return { port: actual, token, name: (await data()).name, url: `http://127.0.0.1:${actual}/`, close: () => { server.closeAllConnections?.(); return new Promise((r) => server.close(r)); } };
}
