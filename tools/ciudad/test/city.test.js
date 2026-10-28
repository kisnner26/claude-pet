import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { buildCity } from '../src/city.js';
import { dominantLanguage, scanFolder } from '../src/scan.js';

const DAY = 86400;
const p = (name, o = {}) => ({ name, commits: 10, recent: 0, last: 1000 * DAY, files: 10, language: 'JavaScript', dirty: 0, ...o });

test('el repo con mas commits es el edificio mas alto y queda al centro', () => {
  const { buildings, size } = buildCity([p('a', { commits: 5 }), p('b', { commits: 100 }), p('c', { commits: 20 })], { now: 1000 * DAY });
  const b = buildings.find((x) => x.name === 'b');
  assert.equal(b.height, 10); assert.equal(size, 2);
  assert.ok(buildings.every((x) => x.height <= b.height));
});
test('estado por antiguedad de la ultima actividad', () => {
  const now = 1000 * DAY;
  const { buildings } = buildCity([p('v', { last: now - 5 * DAY }), p('t', { last: now - 40 * DAY }), p('x', { last: now - 200 * DAY }), p('n', { last: null })], { now });
  const s = Object.fromEntries(buildings.map((b) => [b.name, b.state]));
  assert.deepEqual(s, { v: 'activo', t: 'tranquilo', x: 'abandonado', n: 'abandonado' });
});
test('ventanas encendidas segun commits recientes, acotadas a 1', () => {
  const { buildings } = buildCity([p('a', { recent: 10 }), p('b', { recent: 500 })]);
  assert.equal(buildings.find((x) => x.name === 'a').lit, 0.5); assert.equal(buildings.find((x) => x.name === 'b').lit, 1);
});
test('celdas unicas y ciudad vacia', () => {
  const { buildings } = buildCity(Array.from({ length: 7 }, (_, i) => p('r' + i)));
  assert.equal(new Set(buildings.map((b) => `${b.row},${b.col}`)).size, 7);
  assert.deepEqual(buildCity([]), { buildings: [], size: 0 });
});
test('lenguaje dominante ignora docs', () => {
  assert.equal(dominantLanguage(['a.swift', 'b.swift', 'c.js', 'README.md', 'd.md', 'e.md']), 'Swift');
  assert.equal(dominantLanguage(['x.md']), 'Otro');
});
test('scanFolder mide repos reales y salta carpetas sin git', async () => {
  const root = await mkdtemp(join(tmpdir(), 'ciudad-'));
  const g = (cwd, ...a) => execFileSync('git', a, { cwd, stdio: 'ignore' });
  await mkdir(join(root, 'uno')); await mkdir(join(root, 'sin-git'));
  g(join(root, 'uno'), 'init', '-q', '-b', 'main');
  await writeFile(join(root, 'uno', 'a.py'), 'x'); await writeFile(join(root, 'uno', 'b.py'), 'y');
  g(join(root, 'uno'), 'add', '.'); g(join(root, 'uno'), '-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qm', 'x');
  await writeFile(join(root, 'uno', 'c.py'), 'z');
  const r = await scanFolder(root);
  assert.equal(r.length, 1);
  assert.deepEqual({ name: r[0].name, commits: r[0].commits, files: r[0].files, language: r[0].language, dirty: r[0].dirty }, { name: 'uno', commits: 1, files: 2, language: 'Python', dirty: 1 });
});
