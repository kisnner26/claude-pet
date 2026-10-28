// Recorre los hijos directos de una carpeta y mide cada repo de git. Solo lectura, git sin shell.
import { spawn } from 'node:child_process';
import { readdir, stat } from 'node:fs/promises';
import { join, extname } from 'node:path';

const run = (cwd, args) => new Promise((resolve) => {
  const p = spawn('git', args, { cwd, stdio: ['ignore', 'pipe', 'ignore'] });
  const out = []; p.stdout.on('data', (c) => out.push(c)); p.on('error', () => resolve(null));
  p.on('close', (code) => resolve(code === 0 ? Buffer.concat(out).toString('utf8') : null));
});

export const LANGS = { '.swift': 'Swift', '.js': 'JavaScript', '.mjs': 'JavaScript', '.ts': 'TypeScript', '.tsx': 'TypeScript', '.py': 'Python', '.rs': 'Rust', '.go': 'Go', '.java': 'Java', '.kt': 'Kotlin', '.c': 'C', '.cpp': 'C++', '.php': 'PHP', '.rb': 'Ruby', '.html': 'Web', '.css': 'Web', '.md': 'Docs' };
export function dominantLanguage(files) {
  const n = new Map();
  for (const f of files) { const l = LANGS[extname(f).toLowerCase()]; if (l && l !== 'Docs') n.set(l, (n.get(l) ?? 0) + 1); }
  return [...n.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0]?.[0] ?? 'Otro';
}

export async function measure(dir, name) {
  const [count, last, files, dirty] = await Promise.all([run(dir, ['rev-list', '--count', 'HEAD']), run(dir, ['log', '-1', '--format=%ct']), run(dir, ['ls-files', '-z']), run(dir, ['status', '--porcelain'])]);
  if (count === null && files === null) return null;
  const list = (files ?? '').split('\0').filter(Boolean);
  const since = await run(dir, ['rev-list', '--count', '--since=30 days ago', 'HEAD']);
  return { name, commits: Number(count) || 0, recent: Number(since) || 0, last: Number(last) || null, files: list.length, language: dominantLanguage(list), dirty: (dirty ?? '').split('\n').filter(Boolean).length };
}

export async function scanFolder(root, { limit = 60 } = {}) {
  const entries = await readdir(root, { withFileTypes: true });
  const dirs = entries.filter((e) => e.isDirectory() && !e.name.startsWith('.') && e.name !== 'node_modules').map((e) => e.name).sort();
  const out = [];
  for (let i = 0; i < dirs.length && out.length < limit; i += 6) {
    const batch = await Promise.all(dirs.slice(i, i + 6).map(async (d) => { try { await stat(join(root, d, '.git')); return await measure(join(root, d), d); } catch { return null; } }));
    out.push(...batch.filter(Boolean));
  }
  return out;
}
