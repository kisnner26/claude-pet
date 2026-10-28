// Lee el historial de git sin shell y lo convierte en commits { hash, at, author, files[] }.
import { spawn } from 'node:child_process';

export function git(cwd, args) {
  return new Promise((resolve, reject) => {
    const p = spawn('git', args, { cwd, stdio: ['ignore', 'pipe', 'pipe'] });
    const out = []; let err = '';
    p.stdout.on('data', (c) => out.push(c));
    p.stderr.on('data', (c) => (err += c));
    p.on('error', reject);
    p.on('close', (code) => (code === 0 ? resolve(Buffer.concat(out).toString('utf8')) : reject(new Error(err.trim() || `git salio con ${code}`))));
  });
}

const MARK = '\u001e';
export function parseLog(text) {
  const commits = [];
  for (const block of text.split(MARK)) {
    const lines = block.split('\n').filter(Boolean);
    if (!lines.length) continue;
    const [hash, at, author] = lines[0].split('\u001f');
    if (!hash || !Number.isFinite(Number(at))) continue;
    commits.push({ hash, at: Number(at), author: author ?? '', files: lines.slice(1) });
  }
  return commits;
}

export async function loadHistory(dir, { max = 3000 } = {}) {
  const root = (await git(dir, ['rev-parse', '--show-toplevel'])).trim();
  const raw = await git(root, ['log', `-n${max}`, '--no-merges', '--name-only', `--format=${MARK}%H%x1f%ct%x1f%an`]);
  const tracked = new Set((await git(root, ['ls-files', '-z'])).split('\0').filter(Boolean));
  return { root, commits: parseLog(raw), tracked };
}
