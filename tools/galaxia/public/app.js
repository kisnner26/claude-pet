const TOKEN = document.querySelector('meta[name=galaxia-token]').content;
const cv = document.getElementById('sky'), g = cv.getContext('2d');
const tip = document.getElementById('tip'), range = document.getElementById('time'), dateEl = document.getElementById('date'), playBtn = document.getElementById('play');
let G = null, W = 0, H = 0, dpr = 1, view = { x: 0, y: 0, k: 1 }, hover = null, playing = false, t01 = 1;
const bg = Array.from({ length: 160 }, (_, i) => ({ x: ((i * 7919) % 1000) / 1000, y: ((i * 104729) % 1000) / 1000, r: 0.4 + ((i * 31) % 10) / 10, p: i }));

function resize() { dpr = devicePixelRatio || 1; W = innerWidth; H = innerHeight; cv.width = W * dpr; cv.height = H * dpr; fit(); }
function fit() { view.k = Math.min(W, H) * 0.42; view.x = W / 2; view.y = H / 2; }
const sx = (x) => view.x + x * view.k, sy = (y) => view.y + y * view.k;
const fmt = (s) => new Date(s * 1000).toLocaleDateString('es', { year: 'numeric', month: 'short', day: 'numeric' });
const ago = (s) => { const d = Math.round((Date.now() / 1000 - s) / 86400); return d < 1 ? 'hoy' : d < 60 ? `hace ${d} d` : d < 730 ? `hace ${Math.round(d / 30)} meses` : `hace ${Math.round(d / 365)} años`; };
const tNow = () => (G.totals.from ?? 0) + ((G.totals.to ?? 0) - (G.totals.from ?? 0)) * t01;

function frame(time) {
  g.setTransform(dpr, 0, 0, dpr, 0, 0); g.clearRect(0, 0, W, H);
  for (const s of bg) { g.globalAlpha = 0.25 + 0.35 * Math.sin(time / 1500 + s.p); g.fillStyle = '#fff'; g.beginPath(); g.arc(s.x * W, s.y * H, s.r, 0, 7); g.fill(); }
  g.globalAlpha = 1;
  if (G) {
    if (playing) { t01 = Math.min(1, t01 + 0.0016); range.value = t01 * 1000; if (t01 >= 1) setPlaying(false); }
    const now = tNow(); dateEl.textContent = t01 >= 1 ? 'hoy' : fmt(now);
    const vis = new Map();
    for (const s of G.stars) if (s.first <= now) vis.set(s.path, s);
    for (const c of G.constellations) { // nebulosa de cada carpeta
      const x = sx(c.x), y = sy(c.y), r = view.k * 0.42;
      const gr = g.createRadialGradient(x, y, 0, x, y, r);
      gr.addColorStop(0, `hsla(${c.hue},80%,60%,.11)`); gr.addColorStop(1, `hsla(${c.hue},80%,60%,0)`);
      g.fillStyle = gr; g.fillRect(x - r, y - r, r * 2, r * 2);
    }
    g.lineWidth = 1;
    for (const l of G.links) {
      const a = vis.get(l.a), b = vis.get(l.b); if (!a || !b) continue;
      const hot = hover && (hover.path === l.a || hover.path === l.b);
      g.strokeStyle = hot ? 'rgba(255,255,255,.7)' : `rgba(160,190,255,${Math.min(0.28, 0.05 + l.n * 0.03)})`;
      g.beginPath(); g.moveTo(sx(a.x), sy(a.y)); g.lineTo(sx(b.x), sy(b.y)); g.stroke();
    }
    for (const s of vis.values()) {
      const x = sx(s.x), y = sy(s.y), r = s.size * Math.max(0.7, view.k / 330);
      const pulse = 1 + 0.12 * Math.sin(time / 700 + s.x * 9);
      const glow = (t01 < 1 ? Math.max(0.15, Math.exp(-(now - s.last) / 86400 / 45)) : s.glow);
      const halo = r * (3 + 5 * glow) * pulse;
      const gr = g.createRadialGradient(x, y, 0, x, y, halo);
      gr.addColorStop(0, `hsla(${s.hue},90%,78%,${0.55 * glow + 0.1})`); gr.addColorStop(1, `hsla(${s.hue},90%,60%,0)`);
      g.fillStyle = gr; g.fillRect(x - halo, y - halo, halo * 2, halo * 2);
      g.fillStyle = `hsl(${s.hue},90%,${80 + 12 * glow}%)`; g.beginPath(); g.arc(x, y, r * (hover === s ? 1.5 : 1), 0, 7); g.fill();
    }
    g.font = '600 12px ui-monospace, SFMono-Regular, monospace'; g.textAlign = 'center'; g.fillStyle = 'rgba(242,243,246,.5)';
    for (const c of G.constellations) g.fillText((c.name === '.' ? 'raiz' : c.name).toUpperCase(), sx(c.x), sy(c.y) - view.k * 0.4);
  }
  requestAnimationFrame(frame);
}

function pick(mx, my) {
  if (!G) return null; const now = tNow(); let best = null, bd = 16;
  for (const s of G.stars) { if (s.first > now) continue; const d = Math.hypot(sx(s.x) - mx, sy(s.y) - my); if (d < bd) { bd = d; best = s; } }
  return best;
}
let drag = null;
cv.onpointerdown = (e) => { drag = { x: e.clientX, y: e.clientY, vx: view.x, vy: view.y }; cv.classList.add('drag'); cv.setPointerCapture(e.pointerId); };
cv.onpointerup = () => { drag = null; cv.classList.remove('drag'); };
cv.onpointermove = (e) => {
  if (drag) { view.x = drag.vx + e.clientX - drag.x; view.y = drag.vy + e.clientY - drag.y; tip.hidden = true; return; }
  hover = pick(e.clientX, e.clientY);
  if (!hover) { tip.hidden = true; return; }
  tip.replaceChildren(); const b = document.createElement('b'); b.textContent = hover.path;
  const m = document.createElement('span'); m.textContent = `${hover.commits} commits · ${hover.authors} autor${hover.authors > 1 ? 'es' : ''} · último ${ago(hover.last)}`;
  tip.append(b, m); tip.hidden = false;
  tip.style.left = Math.min(W - 340, e.clientX + 16) + 'px'; tip.style.top = Math.min(H - 90, e.clientY + 16) + 'px';
};
cv.onwheel = (e) => { e.preventDefault(); const f = Math.exp(-e.deltaY * 0.0015); view.x = e.clientX - (e.clientX - view.x) * f; view.y = e.clientY - (e.clientY - view.y) * f; view.k = Math.max(60, Math.min(4000, view.k * f)); };
cv.ondblclick = fit;
function setPlaying(p) { playing = p; playBtn.textContent = p ? 'Pausar' : 'Reproducir'; }
playBtn.onclick = () => { if (!playing && t01 >= 1) t01 = 0; setPlaying(!playing); };
range.oninput = () => { t01 = range.value / 1000; setPlaying(false); };
addEventListener('resize', resize);

async function init() {
  resize();
  const r = await fetch('/api/galaxy', { headers: { 'x-galaxia-token': TOKEN } }); G = await r.json();
  if (!r.ok) { document.getElementById('stats').textContent = G.error; return; }
  document.getElementById('name').textContent = G.name + '.';
  const t = G.totals;
  document.getElementById('stats').textContent = t.commits ? `${t.shown} estrellas de ${t.files} archivos · ${t.commits} commits · ${fmt(t.from)} a ${fmt(t.to)}` : 'este repo no tiene commits todavía';
}
init(); requestAnimationFrame(frame);
