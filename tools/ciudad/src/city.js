// Layout de la ciudad: puro y determinista. Los mas grandes quedan en el centro (el "centro financiero").
export function buildCity(projects, { now = Date.now() / 1000 } = {}) {
  if (!projects.length) return { buildings: [], size: 0 };
  const maxC = Math.max(1, ...projects.map((p) => p.commits));
  const sorted = [...projects].sort((a, b) => b.commits - a.commits || a.name.localeCompare(b.name));
  const side = Math.ceil(Math.sqrt(sorted.length));
  const cells = [];
  const mid = (side - 1) / 2;
  for (let r = 0; r < side; r++) for (let c = 0; c < side; c++) cells.push({ r, c, d: Math.hypot(r - mid, c - mid) + (r * side + c) * 1e-6 });
  cells.sort((a, b) => a.d - b.d);
  const buildings = sorted.map((p, i) => {
    const days = p.last ? Math.max(0, (now - p.last) / 86400) : 9999;
    return {
      ...p, row: cells[i].r, col: cells[i].c,
      height: 1 + Math.round(9 * Math.sqrt(p.commits / maxC)),
      width: p.files > 150 ? 3 : p.files > 40 ? 2 : 1,
      lit: Math.max(0, Math.min(1, p.recent / 20)),   // ventanas encendidas = actividad de los ultimos 30 dias
      state: days > 90 ? 'abandonado' : days > 30 ? 'tranquilo' : 'activo',
      days: Math.round(days),
    };
  });
  return { buildings, size: side };
}
