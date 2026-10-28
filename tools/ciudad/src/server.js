// Servidor local: 127.0.0.1, token por proceso, Host validado, solo lectura.
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { dirname, join, basename, resolve } from 'node:path';
import { scanFolder } from './scan.js';
import { buildCity } from './city.js';

const PUBLIC = join(dirname(fileURLToPath(import.meta.url)), '..', 'public');
const STATIC = { '/': ['index.html', 'text/html; charset=utf-8'], '/app.css': ['app.css', 'text/css; charset=utf-8'], '/app.js': ['app.js', 'text/javascript; charset=utf-8'] };

export async function startServer({ dir = process.cwd(), port = 5050, scan = scanFolder } = {}) {
  const token = randomBytes(24).toString('hex');
  const root = resolve(dir);
  const name = basename(root);
  let cache = null;
  const city = async (fresh) => { if (!cache || fresh || Date.now() - cache.at > 20000) cache = { at: Date.now(), data: { name, ...buildCity(await scan(root)) } }; return cache.data; };
  await city(true);
  const send = (res, code, body, type = 'application/json; charset=utf-8') => {
    res.writeHead(code, { 'content-type': type, 'cache-control': 'no-store', 'x-content-type-options': 'nosniff', 'content-security-policy': "default-src 'self'; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'" });
    res.end(typeof body === 'string' ? body : JSON.stringify(body));
  };
  const tokenOk = (req) => {
    const got = Buffer.from(String(req.headers['x-ciudad-token'] ?? '')); const want = Buffer.from(token);
    return got.length === want.length && timingSafeEqual(got, want);
  };
  const server = createServer(async (req, res) => {
    try {
      const p = server.address().port;
      if (![`127.0.0.1:${p}`, `localhost:${p}`].includes(String(req.headers.host ?? '').toLowerCase())) return send(res, 403, { error: 'host no permitido' });
      const url = new URL(req.url, `http://127.0.0.1:${p}`);
      if (req.method !== 'GET') return send(res, 405, { error: 'solo lectura' });
      if (STATIC[url.pathname]) {
        const [file, type] = STATIC[url.pathname];
        let body = readFileSync(join(PUBLIC, file), 'utf8');
        if (file === 'index.html') body = body.replace('__TOKEN__', token);
        return send(res, 200, body, type);
      }
      if (url.pathname === '/api/city') {
        if (!tokenOk(req)) return send(res, 403, { error: 'token no valido' });
        return send(res, 200, await city(url.searchParams.get('fresh') === '1'));
      }
      return send(res, 404, { error: 'no existe' });
    } catch (e) { send(res, 500, { error: e.message }); }
  });
  await new Promise((r, j) => { server.once('error', j); server.listen(port, '127.0.0.1', r); });
  const actual = server.address().port;
  return { port: actual, token, name, url: `http://127.0.0.1:${actual}/`, close: () => { server.closeAllConnections?.(); return new Promise((r) => server.close(r)); } };
}
