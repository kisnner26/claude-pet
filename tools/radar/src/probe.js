// Sondeo de un servicio: DNS del sistema, DNS publicos y conexion TCP al 443. Las dependencias se pueden inyectar en las pruebas.
import dns from 'node:dns';
import net from 'node:net';
import { diagnose } from './diagnose.js';

const HOST_RE = /^(?=.{1,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/i;
export const validHost = (h) => typeof h === 'string' && HOST_RE.test(h);

async function timed(fn) {
  const t = performance.now();
  try { const value = await fn(); return { ok: true, ms: Math.round(performance.now() - t), value }; }
  catch (e) { return { ok: false, ms: Math.round(performance.now() - t), error: e.code || e.message || 'ERROR' }; }
}

export const resolveSystem = (host) => timed(async () => (await dns.promises.lookup(host, { all: true, family: 4 })).map((a) => a.address));
export const resolvePublic = (host, server) => timed(() => {
  const r = new dns.promises.Resolver({ timeout: 3000, tries: 1 });
  r.setServers([server]);
  return r.resolve4(host);
});
export const tcpConnect = (ip, port = 443, timeout = 4000) => timed(() => new Promise((resolve, reject) => {
  const s = net.connect({ host: ip, port });
  const timer = setTimeout(() => { s.destroy(); reject(Object.assign(new Error('timeout'), { code: 'ETIMEDOUT' })); }, timeout);
  s.once('connect', () => { clearTimeout(timer); s.destroy(); resolve(true); });
  s.once('error', (e) => { clearTimeout(timer); reject(e); });
}));

export async function probeHost(host, deps = {}) {
  if (!validHost(host)) throw new Error('nombre de host no valido');
  const sys = await (deps.resolveSystem ?? resolveSystem)(host);
  const pub = deps.resolvePublic ?? resolvePublic;
  const [cloudflare, google] = await Promise.all([pub(host, '1.1.1.1'), pub(host, '8.8.8.8')]);
  const ip = (sys.ok && sys.value[0]) || (cloudflare.ok && cloudflare.value[0]) || (google.ok && google.value[0]) || null;
  const tcp = ip ? await (deps.tcpConnect ?? tcpConnect)(ip, 443) : { ok: false, ms: 0, error: 'SIN_IP' };
  const result = { host, at: Date.now(), system: sys, cloudflare, google, ip, tcp };
  return { ...result, diagnosis: diagnose(result) };
}
