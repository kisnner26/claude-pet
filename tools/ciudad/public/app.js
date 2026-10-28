const TOKEN = document.querySelector('meta[name=ciudad-token]').content;
const cv = document.getElementById('city'), g = cv.getContext('2d'), tip = document.getElementById('tip');
let C = null, W = 0, H = 0, dpr = 1, view = { x: 0, y: 0, k: 1 }, hover = null;
const CELL = 2.6, FLOOR = 0.62;
const HUES = { Swift: 18, JavaScript: 50, TypeScript: 210, Python: 150, Rust: 24, Go: 190, Java: 8, Kotlin: 270, C: 220, 'C++': 235, PHP: 245, Ruby: 350, Web: 320, Otro: 215 };
const STATE_COLOR = { activo: '#33cc5c', tranquilo: '#f2b632', abandonado: '#6b7280' };
const stars = Array.from({ length: 90 }, (_, i) => ({ x: ((i * 7919) % 1000) / 1000, y: ((i * 104729) % 600) / 1000, r: 0.4 + ((i * 31) % 10) / 12 }));

function resize() { dpr = devicePixelRatio || 1; W = innerWidth; H = innerHeight; cv.width = W * dpr; cv.height = H * dpr; fit(); }
function fit() { const n = C?.size || 1; view.k = Math.min(W / (n * CELL * 1.9), H / (n * CELL * 1.25 + 9)) * 1.05; view.x = W / 2; view.y = H * 0.56 - (n * CELL * view.k * 0.5) + 40; }
const iso = (x, y, z = 0) => [view.x + (x - y) * 0.866 * view.k, view.y + (x + y) * 0.5 * view.k - z * view.k];
const hsl = (h, s, l, a = 1) => `hsla(${h},${s}%,${l}%,${a})`;
const poly = (pts, fill) => { g.beginPath(); pts.forEach(([x, y], i) => (i ? g.lineTo(x, y) : g.moveTo(x, y))); g.closePath(); g.fillStyle = fill; g.fill(); };
const ago = (d) => (d < 1 ? 'hoy' : d < 60 ? `hace ${d} d` : d < 730 ? `hace ${Math.round(d / 30)} meses` : `hace ${Math.round(d / 365)} años`);

function drawBuilding(b, time) {
  const fp = 0.9 + 0.5 * (b.width - 1), off = (CELL - fp) / 2;
  const x0 = b.col * CELL + off, y0 = b.row * CELL + off, h = b.height * FLOOR + 0.5;
  const dead = b.state === 'abandonado';
  const hue = HUES[b.language] ?? 215, sat = dead ? 6 : 55, lum = dead ? 24 : 36;
  const hot = hover === b;
  const T = (x, y, z) => iso(x0 + x, y0 + y, z);
  poly([T(0, 0, 0), T(fp, 0, 0), T(fp, fp, 0), T(0, fp, 0)], 'rgba(0,0,0,.28)');           // sombra/base
  poly([T(0, fp, 0), T(fp, fp, 0), T(fp, fp, h), T(0, fp, h)], hsl(hue, sat, lum - 8 + (hot ? 8 : 0))); // cara izquierda
  poly([T(fp, 0, 0), T(fp, fp, 0), T(fp, fp, h), T(fp, 0, h)], hsl(hue, sat, lum + 4 + (hot ? 8 : 0)));  // cara derecha
  poly([T(0, 0, h), T(fp, 0, h), T(fp, fp, h), T(0, fp, h)], STATE_COLOR[b.state]);   // techo = estado
  if (hot) poly([T(0, 0, h), T(fp, 0, h), T(fp, fp, h), T(0, fp, h)], 'rgba(255,255,255,.25)');
  // ventanas: cada una se enciende segun la actividad reciente
  const cols = Math.max(2, Math.round(fp * 3)), rows = Math.max(1, b.height);
  for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) {
    const seed = ((r * 131 + c * 31 + b.commits * 7 + b.name.length * 13) % 100) / 100;
    if (seed > b.lit * 0.9 + (dead ? 0 : 0.12)) continue;
    const z = 0.25 + r * FLOOR, u0 = (c + 0.2) / cols * fp, u1 = (c + 0.75) / cols * fp;
    const tw = 0.75 + 0.25 * Math.sin(time / 900 + seed * 40);
    poly([T(u0, fp, z), T(u1, fp, z), T(u1, fp, z + FLOOR * 0.5), T(u0, fp, z + FLOOR * 0.5)], hsl(48, 95, 68, 0.85 * tw));
    poly([T(fp, u0, z), T(fp, u1, z), T(fp, u1, z + FLOOR * 0.5), T(fp, u0, z + FLOOR * 0.5)], hsl(48, 95, 62, 0.7 * tw));
  }
  if (b.dirty > 0) { // baliza roja: hay cambios sin commit
    const [bx, by] = T(fp / 2, fp / 2, h + 0.5), p = 0.5 + 0.5 * Math.sin(time / 350);
    g.fillStyle = `rgba(230,33,63,${0.35 + 0.5 * p})`; g.shadowColor = '#e6213f'; g.shadowBlur = 16;
    g.beginPath(); g.arc(bx, by, 3.5 + 2 * p, 0, 7); g.fill(); g.shadowBlur = 0;
  }
  const [lx, ly] = T(fp / 2, fp, 0);
  g.font = '600 11px ui-monospace, SFMono-Regular, monospace'; g.textAlign = 'center'; g.fillStyle = hot ? '#fff' : 'rgba(242,243,246,.62)';
  if (hot || C.buildings.length <= 20) g.fillText(b.name, lx, ly + 16);   // con muchos repos solo se rotula el que tocas
  b._hit = { top: T(fp / 2, fp / 2, h), x0, y0, fp, h };
}

function frame(time) {
  g.setTransform(dpr, 0, 0, dpr, 0, 0); g.clearRect(0, 0, W, H);
  for (const s of stars) { g.globalAlpha = 0.3 + 0.3 * Math.sin(time / 1700 + s.x * 30); g.fillStyle = '#fff'; g.beginPath(); g.arc(s.x * W, s.y * H, s.r, 0, 7); g.fill(); }
  g.globalAlpha = 1;
  if (C && C.buildings.length) {
    const n = C.size * CELL;
    poly([iso(-0.8, -0.8), iso(n + 0.8, -0.8), iso(n + 0.8, n + 0.8), iso(-0.8, n + 0.8)], 'rgba(20,22,40,.9)'); // suelo
    g.strokeStyle = 'rgba(255,255,255,.05)'; g.lineWidth = 1;
    for (let i = 0; i <= C.size; i++) { const a = iso(i * CELL, -0.8), b = iso(i * CELL, n + 0.8), c = iso(-0.8, i * CELL), d = iso(n + 0.8, i * CELL); g.beginPath(); g.moveTo(...a); g.lineTo(...b); g.moveTo(...c); g.lineTo(...d); g.stroke(); }
    for (const b of [...C.buildings].sort((p, q) => p.row + p.col - (q.row + q.col) || p.row - q.row)) drawBuilding(b, time);
  }
  requestAnimationFrame(frame);
}

function pick(mx, my) {
  if (!C) return null; let best = null, bd = 1e9;
  for (const b of C.buildings) {
    if (!b._hit) continue; const { x0, y0, fp, h } = b._hit;
    const pts = [iso(x0, y0 + fp, 0), iso(x0 + fp, y0 + fp, 0), iso(x0 + fp, y0, 0), iso(x0, y0, h), iso(x0 + fp, y0, h), iso(x0, y0 + fp, h), iso(x0 + fp, y0 + fp, h)];
    const xs = pts.map((p) => p[0]), ys = pts.map((p) => p[1]);
    if (mx < Math.min(...xs) || mx > Math.max(...xs) || my < Math.min(...ys) || my > Math.max(...ys)) continue;
    const d = Math.hypot(b._hit.top[0] - mx, b._hit.top[1] - my);
    if (d < bd) { bd = d; best = b; }
  }
  return best;
}
let drag = null;
cv.onpointerdown = (e) => { drag = { x: e.clientX, y: e.clientY, vx: view.x, vy: view.y }; cv.classList.add('drag'); cv.setPointerCapture(e.pointerId); };
cv.onpointerup = () => { drag = null; cv.classList.remove('drag'); };
cv.onpointermove = (e) => {
  if (drag) { view.x = drag.vx + e.clientX - drag.x; view.y = drag.vy + e.clientY - drag.y; tip.hidden = true; return; }
  hover = pick(e.clientX, e.clientY);
  if (!hover) { tip.hidden = true; return; }
  tip.replaceChildren(); const b = document.createElement('b'); b.textContent = hover.name; tip.append(b);
  for (const t of [`${hover.language} · ${hover.files} archivos`, `${hover.commits} commits · ${hover.recent} en 30 días`, `${hover.state} · último ${hover.last ? ago(hover.days) : 'nunca'}`, hover.dirty ? `${hover.dirty} cambios sin commit` : 'limpio']) { const s = document.createElement('span'); s.textContent = t; tip.append(s); }
  tip.hidden = false; tip.style.left = Math.min(W - 230, e.clientX + 16) + 'px'; tip.style.top = Math.min(H - 150, e.clientY + 16) + 'px';
};
cv.onwheel = (e) => { e.preventDefault(); const f = Math.exp(-e.deltaY * 0.0015); view.x = e.clientX - (e.clientX - view.x) * f; view.y = e.clientY - (e.clientY - view.y) * f; view.k = Math.max(4, Math.min(200, view.k * f)); };
cv.ondblclick = fit;
addEventListener('resize', resize);

async function load(fresh) {
  const r = await fetch('/api/city' + (fresh ? '?fresh=1' : ''), { headers: { 'x-ciudad-token': TOKEN } }); const j = await r.json();
  if (!r.ok) { document.getElementById('stats').textContent = j.error; return; }
  const first = !C; C = j; if (first) fit();
  document.getElementById('name').textContent = C.name + '.';
  const act = C.buildings.filter((b) => b.state === 'activo').length, dirty = C.buildings.filter((b) => b.dirty).length;
  document.getElementById('stats').textContent = C.buildings.length ? `${C.buildings.length} proyectos · ${act} activos · ${dirty} con cambios sin commit` : 'no hay repos de git en esta carpeta';
}
resize(); load(); setInterval(load, 30000); requestAnimationFrame(frame);
