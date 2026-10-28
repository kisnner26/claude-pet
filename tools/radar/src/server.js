// Servidor local: solo 127.0.0.1, token por proceso, Host y Origin validados. Sondea los hosts cada 30 s.
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { probeHost, validHost } from './probe.js';

const PUBLIC = join(dirname(fileURLToPath(import.meta.url)), '..', 'public');
const STATIC = { '/': ['index.html', 'text/html; charset=utf-8'], '/app.css': ['app.css', 'text/css; charset=utf-8'], '/app.js': ['app.js', 'text/javascript; charset=utf-8'] };
export const DEFAULT_HOSTS = ['github.com', 'api.github.com', 'registry.npmjs.org', 'api.anthropic.com', 'icloud.com', 'developer.apple.com'];
const MAX_HOSTS = 24;

export async function startServer({ hosts = DEFAULT_HOSTS, port = 4848, interval = 30000, probe = probeHost } = {}) {
  const token = randomBytes(24).toString('hex');
  const list = [...new Set(hosts.filter(validHost))];
  const results = new Map();
  const history = new Map();

  async function run(host) {
    try {
      const r = await probe(host);
      results.set(host, r);
      const h = history.get(host) ?? [];
      h.push({ at: r.at, sev: r.diagnosis.severity, ms: r.tcp?.ok ? r.tcp.ms : null });
      history.set(host, h.slice(-40));
    } catch (e) { results.set(host, { host, error: e.message }); }
  }
  const runAll = () => Promise.all(list.map(run));
  runAll();
  const timer = setInterval(runAll, interval);
  timer.unref();

  const snapshot = () => ({ at: Date.now(), hosts: list.map((h) => ({ ...(results.get(h) ?? { host: h, pending: true }), history: history.get(h) ?? [] })) });

  const send = (res, code, body, type = 'application/json; charset=utf-8') => {
    res.writeHead(code, { 'content-type': type, 'cache-control': 'no-store', 'x-content-type-options': 'nosniff', 'content-security-policy': "default-src 'self'; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'" });
    res.end(typeof body === 'string' ? body : JSON.stringify(body));
  };
  const readBody = (req) => new Promise((resolve, reject) => {
    let size = 0; const chunks = [];
    req.on('data', (c) => { size += c.length; if (size > 4096) { reject(new Error('cuerpo demasiado grande')); req.destroy(); } else chunks.push(c); });
    req.on('end', () => { try { resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {}); } catch { reject(new Error('json no valido')); } });
    req.on('error', reject);
  });
  const tokenOk = (req) => {
    const got = Buffer.from(String(req.headers['x-radar-token'] ?? ''));
    const want = Buffer.from(token);
    return got.length === want.length && timingSafeEqual(got, want);
  };

  const server = createServer(async (req, res) => {
    const p = server.address().port;
    try {
      if (![`127.0.0.1:${p}`, `localhost:${p}`].includes(String(req.headers.host ?? '').toLowerCase())) return send(res, 403, { error: 'host no permitido' });
      const url = new URL(req.url, `http://127.0.0.1:${p}`);
      if (req.method === 'GET' && STATIC[url.pathname]) {
        const [file, type] = STATIC[url.pathname];
        let body = readFileSync(join(PUBLIC, file), 'utf8');
        if (file === 'index.html') body = body.replace('__TOKEN__', token);
        return send(res, 200, body, type);
      }
      if (!url.pathname.startsWith('/api/')) return send(res, 404, { error: 'no existe' });
      if (!tokenOk(req)) return send(res, 403, { error: 'token no valido' });
      if (req.method === 'GET' && url.pathname === '/api/state') return send(res, 200, snapshot());
      if (req.method === 'POST') {
        const origin = req.headers.origin;
        if (origin && origin !== `http://127.0.0.1:${p}` && origin !== `http://localhost:${p}`) return send(res, 403, { error: 'origen no permitido' });
        if (!String(req.headers['content-type'] ?? '').startsWith('application/json')) return send(res, 415, { error: 'se esperaba json' });
        const body = await readBody(req);
        if (!validHost(body.host)) return send(res, 400, { error: 'nombre de host no valido' });
        const host = body.host.toLowerCase();
        if (url.pathname === '/api/add') {
          if (!list.includes(host)) { if (list.length >= MAX_HOSTS) return send(res, 400, { error: 'demasiados hosts' }); list.push(host); }
          await run(host);
          return send(res, 200, snapshot());
        }
        if (url.pathname === '/api/remove') {
          const i = list.indexOf(host); if (i >= 0) list.splice(i, 1); results.delete(host); history.delete(host);
          return send(res, 200, snapshot());
        }
        if (url.pathname === '/api/probe') { await run(host); return send(res, 200, snapshot()); }
      }
      return send(res, 404, { error: 'no existe' });
    } catch (e) { send(res, 400, { error: e.message }); }
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, '127.0.0.1', resolve); });
  const actual = server.address().port;
  return { port: actual, token, url: `http://127.0.0.1:${actual}/`, close: () => { clearInterval(timer); server.closeAllConnections?.(); return new Promise((r) => server.close(r)); } };
}
