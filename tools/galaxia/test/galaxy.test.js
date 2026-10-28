import test from 'node:test';
import assert from 'node:assert/strict';
import { parseLog } from '../src/history.js';
import { buildGalaxy } from '../src/galaxy.js';

const E = '\u001e', U = '\u001f';
test('parseLog lee commits y archivos', () => {
  const c = parseLog(`${E}h1${U}1000${U}ana\n\na.js\nsrc/b.js\n${E}h2${U}2000${U}luis\n\nc.js\n`);
  assert.equal(c.length, 2); assert.deepEqual(c[0].files, ['a.js', 'src/b.js']); assert.equal(c[1].author, 'luis');
});
test('parseLog ignora bloques corruptos', () => assert.deepEqual(parseLog(`${E}basura\n${E}`), []));

const commits = [
  { hash: '1', at: 1000, author: 'a', files: ['src/a.js', 'src/b.js'] },
  { hash: '2', at: 2000, author: 'b', files: ['src/a.js', 'src/b.js', 'old.js'] },
  { hash: '3', at: 3000, author: 'a', files: ['src/a.js', 'gone.js'] },
];
const tracked = new Set(['src/a.js', 'src/b.js', 'old.js']);

test('solo cuenta archivos que siguen existiendo y ordena por commits', () => {
  const g = buildGalaxy({ commits, tracked }, { now: 3000 });
  assert.deepEqual(g.stars.map((s) => s.path), ['src/a.js', 'src/b.js', 'old.js']);
  assert.equal(g.stars[0].commits, 3); assert.equal(g.stars[0].authors, 2);
  assert.equal(g.totals.files, 3);
});
test('enlaza archivos que cambian juntos al menos 2 veces', () => {
  const g = buildGalaxy({ commits, tracked }, { now: 3000 });
  assert.deepEqual(g.links, [{ a: 'src/a.js', b: 'src/b.js', n: 2 }]);
});
test('brilla mas lo reciente y es determinista', () => {
  const day = 86400;
  const c = [{ hash: '1', at: 0, author: 'a', files: ['x.js'] }, { hash: '2', at: 100 * day, author: 'a', files: ['y.js'] }];
  const t = new Set(['x.js', 'y.js']);
  const g = buildGalaxy({ commits: c, tracked: t }, { now: 100 * day });
  const x = g.stars.find((s) => s.path === 'x.js'), y = g.stars.find((s) => s.path === 'y.js');
  assert.ok(y.glow > x.glow);
  assert.deepEqual(buildGalaxy({ commits: c, tracked: t }, { now: 100 * day }), g);
});
test('agrupa por carpeta de primer nivel', () => {
  const g = buildGalaxy({ commits, tracked }, { now: 3000 });
  assert.deepEqual(g.constellations.map((c) => c.name).sort(), ['.', 'src']);
});
test('respeta maxStars y repos vacios', () => {
  assert.equal(buildGalaxy({ commits, tracked }, { maxStars: 1 }).stars.length, 1);
  const e = buildGalaxy({ commits: [], tracked: new Set() });
  assert.equal(e.stars.length, 0); assert.equal(e.totals.from, null);
});
