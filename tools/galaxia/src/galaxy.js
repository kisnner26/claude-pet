// Convierte el historial en una galaxia: estrellas (archivos), constelaciones (carpetas) y enlaces (cambian juntos). Puro y determinista.
const hash = (s) => { let h = 2166136261; for (const c of s) h = Math.imul(h ^ c.charCodeAt(0), 16777619) >>> 0; return h; };
const rnd = (s, k) => (hash(s + k) % 10000) / 10000;
const topDir = (f) => (f.includes('/') ? f.split('/')[0] : '.');

export function buildGalaxy({ commits, tracked }, { now = Date.now() / 1000, maxStars = 400, maxLinks = 500 } = {}) {
  const files = new Map();
  const pairs = new Map();
  for (const c of commits) {
    const fs = c.files.filter((f) => tracked.has(f));
    for (const f of fs) {
      const s = files.get(f) ?? { path: f, commits: 0, first: c.at, last: c.at, authors: new Set() };
      s.commits++; s.first = Math.min(s.first, c.at); s.last = Math.max(s.last, c.at); s.authors.add(c.author);
      files.set(f, s);
    }
    if (fs.length > 1 && fs.length <= 12) for (let i = 0; i < fs.length; i++) for (let j = i + 1; j < fs.length; j++) {
      const k = fs[i] < fs[j] ? `${fs[i]}\0${fs[j]}` : `${fs[j]}\0${fs[i]}`;
      pairs.set(k, (pairs.get(k) ?? 0) + 1);
    }
  }
  const ranked = [...files.values()].sort((a, b) => b.commits - a.commits || a.path.localeCompare(b.path)).slice(0, maxStars);
  const keep = new Set(ranked.map((s) => s.path));
  const dirs = [...new Set(ranked.map((s) => topDir(s.path)))].sort();
  const centers = new Map(dirs.map((d, i) => {
    const a = (i / dirs.length) * Math.PI * 2 + rnd(d, 'a') * 0.4; const r = dirs.length === 1 ? 0 : 0.55 + rnd(d, 'r') * 0.25;
    return [d, { x: Math.cos(a) * r, y: Math.sin(a) * r }];
  }));
  const maxC = Math.max(1, ...ranked.map((s) => s.commits));
  const stars = ranked.map((s) => {
    const d = topDir(s.path); const c = centers.get(d);
    const a = rnd(s.path, 'a') * Math.PI * 2; const rad = 0.06 + Math.sqrt(rnd(s.path, 'r')) * 0.32;
    const ageDays = Math.max(0, (now - s.last) / 86400);
    return {
      path: s.path, dir: d, commits: s.commits, authors: s.authors.size, last: s.last, first: s.first,
      x: c.x + Math.cos(a) * rad, y: c.y + Math.sin(a) * rad,
      size: 1.2 + 5.5 * Math.sqrt(s.commits / maxC),
      glow: Math.max(0.08, Math.exp(-ageDays / 45)),   // brilla mas cuanto mas reciente
      hue: hash(d) % 360,
    };
  });
  const links = [...pairs.entries()].filter(([k, n]) => n >= 2 && k.split('\0').every((f) => keep.has(f)))
    .sort((a, b) => b[1] - a[1]).slice(0, maxLinks).map(([k, n]) => { const [a, b] = k.split('\0'); return { a, b, n }; });
  const constellations = dirs.map((d) => ({ name: d, ...centers.get(d), hue: hash(d) % 360, stars: stars.filter((s) => s.dir === d).length }));
  const times = commits.map((c) => c.at);
  return { stars, links, constellations, totals: { commits: commits.length, files: files.size, shown: stars.length, from: times.length ? Math.min(...times) : null, to: times.length ? Math.max(...times) : null } };
}
