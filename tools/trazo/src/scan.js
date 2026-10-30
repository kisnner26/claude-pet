import { spawn } from 'node:child_process';
import { basename } from 'node:path';

const git = (cwd, args) => new Promise((resolve, reject) => {
  const p = spawn('git', args, { cwd, stdio: ['ignore', 'pipe', 'pipe'] }); const out = [], err = [];
  p.stdout.on('data', (c) => out.push(c)); p.stderr.on('data', (c) => err.push(c)); p.on('error', reject);
  p.on('close', (code) => code === 0 ? resolve(Buffer.concat(out).toString('utf8')) : reject(new Error(Buffer.concat(err).toString('utf8').trim() || 'git no disponible')));
});
const group = (path) => path.includes('/') ? path.split('/')[0] : 'raíz';
const kind = (code) => code === '??' ? 'nuevo' : code.includes('D') ? 'borrado' : code.includes('A') ? 'nuevo' : code.includes('R') ? 'movido' : 'editado';

export async function scanRepo(dir) {
  const [root, branch, porcelain, stats] = await Promise.all([
    git(dir, ['rev-parse', '--show-toplevel']), git(dir, ['branch', '--show-current']), git(dir, ['status', '--porcelain=v1']), git(dir, ['diff', '--numstat']),
  ]);
  const deltas = new Map(stats.split('\n').filter(Boolean).map((line) => { const [add, del, file] = line.split('\t'); return [file, { add: Number(add) || 0, del: Number(del) || 0 }]; }));
  const files = porcelain.split('\n').filter(Boolean).map((line) => {
    const code = line.slice(0, 2), raw = line.slice(3); const path = raw.includes(' -> ') ? raw.split(' -> ').at(-1) : raw;
    return { path, code, kind: kind(code), group: group(path), ...(deltas.get(path) ?? { add: 0, del: 0 }) };
  });
  const groups = [...new Set(files.map((f) => f.group))].map((name) => ({ name, files: files.filter((f) => f.group === name) }));
  return { name: basename(root.trim()), branch: branch.trim() || 'HEAD', files, groups, at: Date.now() };
}
