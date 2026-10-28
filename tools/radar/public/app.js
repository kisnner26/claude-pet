const TOKEN = document.querySelector('meta[name=radar-token]').content;
const COLORS = ['#33cc5c', '#f2b632', '#e6213f', '#e6213f'];
let state = { hosts: [] };

async function api(path, body) {
  const r = await fetch(path, { method: body ? 'POST' : 'GET', headers: { 'x-radar-token': TOKEN, ...(body ? { 'content-type': 'application/json' } : {}) }, body: body && JSON.stringify(body) });
  const j = await r.json();
  if (!r.ok) throw new Error(j.error || 'error');
  return j;
}
const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; };
const sev = (h) => (h.diagnosis ? h.diagnosis.severity : -1);

function card(h) {
  const c = el('article', 'card');
  const row = el('div', 'row');
  row.append(el('span', `dot ${h.diagnosis ? 's' + h.diagnosis.severity : 'pending'}`), el('span', 'name', h.host));
  const meta = el('div', 'meta');
  if (h.diagnosis) {
    meta.append(el('span', null, 'DNS ' + (h.system.ok ? h.system.ms + ' ms' : 'falla')));
    meta.append(el('span', null, 'TCP ' + (h.tcp.ok ? h.tcp.ms + ' ms' : 'falla')));
  }
  row.append(meta);
  c.append(row);
  if (h.error) { c.append(el('p', 'detail', h.error)); return c; }
  if (!h.diagnosis) { c.append(el('p', 'detail', 'sondeando...')); return c; }
  c.append(el('p', 'title', h.diagnosis.title), el('p', 'detail', h.diagnosis.detail));
  if (h.diagnosis.fixes.length) {
    const box = el('div', 'fixes');
    for (const f of h.diagnosis.fixes) {
      const r = el('div', 'fix'); const t = el('div');
      t.append(el('small', null, f.label), el('code', null, f.command));
      const b = el('button', null, 'Copiar');
      b.onclick = async () => { await navigator.clipboard.writeText(f.command); b.textContent = 'Copiado'; setTimeout(() => (b.textContent = 'Copiar'), 1400); };
      r.append(t, b); box.append(r);
    }
    c.append(box);
  }
  c.append(spark(h.history));
  const tools = el('div', 'tools');
  const again = el('button', null, 'Volver a sondear'); again.onclick = () => act('/api/probe', h.host);
  const del = el('button', null, 'Quitar'); del.onclick = () => act('/api/remove', h.host);
  tools.append(again, del); c.append(tools);
  return c;
}

function spark(history) {
  const cv = el('canvas', 'spark'); cv.width = 600; cv.height = 44;
  const g = cv.getContext('2d'); const n = history.length;
  history.forEach((p, i) => {
    g.fillStyle = COLORS[p.sev] ?? COLORS[0];
    const h = p.ms == null ? 8 : Math.max(6, Math.min(40, p.ms / 20));
    g.globalAlpha = 0.35 + 0.65 * (i / Math.max(1, n - 1));
    g.beginPath(); g.roundRect(i * 15, 44 - h, 10, h, 3); g.fill();
  });
  return cv;
}

let lastSig = '';
function render() {
  const sig = JSON.stringify(state.hosts.map((h) => [h.host, h.at, h.pending]));
  if (sig === lastSig) return;
  const first = lastSig === '';
  lastSig = sig;
  const box = document.getElementById('cards');
  box.classList.toggle('settled', !first);
  box.replaceChildren(...state.hosts.slice().sort((a, b) => sev(b) - sev(a)).map(card));
  const bad = state.hosts.filter((h) => sev(h) >= 2).length;
  const slow = state.hosts.filter((h) => sev(h) === 1).length;
  document.getElementById('sub').textContent = state.hosts.length
    ? (bad ? `${bad} con problemas` : slow ? `${slow} lentos, el resto en orden` : 'todo en orden') + ` · ${state.hosts.length} servicios · se actualiza cada 30 s`
    : 'añade un host para vigilarlo';
}

async function act(path, host) { try { state = await api(path, { host }); render(); } catch (e) { alert(e.message); } }
document.getElementById('add').onsubmit = async (e) => {
  e.preventDefault();
  const i = document.getElementById('host'); const v = i.value.trim().toLowerCase();
  if (!v) return;
  await act('/api/add', v); i.value = '';
};

// radar: haz giratorio y un punto por servicio; el color es el estado, la distancia la latencia
const cv = document.getElementById('radar'); const g = cv.getContext('2d'); const S = cv.width, C = S / 2;
function angle(name, i, n) { let h = 0; for (const ch of name) h = (h * 31 + ch.charCodeAt(0)) >>> 0; return ((i / Math.max(1, n)) * 2 - 0.5) * Math.PI + ((h % 100) / 100 - 0.5) * 0.25; }
function frame(t) {
  g.clearRect(0, 0, S, S);
  g.strokeStyle = 'rgba(255,255,255,.1)'; g.lineWidth = 1.5;
  for (let r = 1; r <= 4; r++) { g.beginPath(); g.arc(C, C, (C - 30) * r / 4, 0, Math.PI * 2); g.stroke(); }
  g.beginPath(); g.moveTo(C, 30); g.lineTo(C, S - 30); g.moveTo(30, C); g.lineTo(S - 30, C); g.stroke();
  const sweep = (t / 3200) % 1 * Math.PI * 2 - Math.PI / 2;
  for (let k = 0; k < 40; k++) { // estela del haz
    g.strokeStyle = `rgba(41,102,237,${0.22 * (1 - k / 40)})`; g.lineWidth = 6;
    g.beginPath(); g.moveTo(C, C); g.lineTo(C + Math.cos(sweep - k * 0.03) * (C - 30), C + Math.sin(sweep - k * 0.03) * (C - 30)); g.stroke();
  }
  g.strokeStyle = 'rgba(120,160,255,.9)'; g.lineWidth = 2.5; g.beginPath(); g.moveTo(C, C); g.lineTo(C + Math.cos(sweep) * (C - 30), C + Math.sin(sweep) * (C - 30)); g.stroke();
  const n = state.hosts.length;
  state.hosts.forEach((h, i) => {
    const a = angle(h.host, i, n); const ms = h.tcp?.ok ? h.tcp.ms : 700;
    const d = (C - 30) * (0.28 + 0.65 * Math.min(1, ms / 700));
    const x = C + Math.cos(a) * d, y = C + Math.sin(a) * d;
    let diff = ((sweep - a) % (Math.PI * 2) + Math.PI * 2) % (Math.PI * 2);
    const glow = Math.max(0, 1 - diff / 2.4);
    const col = h.diagnosis ? COLORS[h.diagnosis.severity] : '#888';
    g.fillStyle = col; g.globalAlpha = 0.35 + 0.65 * glow; g.shadowColor = col; g.shadowBlur = 10 + 26 * glow;
    g.beginPath(); g.arc(x, y, 9 + 5 * glow, 0, Math.PI * 2); g.fill();
    g.globalAlpha = 1; g.shadowBlur = 0;
    g.fillStyle = 'rgba(242,243,246,.85)'; g.font = '600 22px -apple-system, system-ui, sans-serif';
    g.textAlign = x > C ? 'left' : 'right'; g.fillText(h.host, x + (x > C ? 20 : -20), y + 7);
  });
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);

async function poll() { try { state = await api('/api/state'); render(); } catch {} }
poll(); setInterval(poll, 4000);
