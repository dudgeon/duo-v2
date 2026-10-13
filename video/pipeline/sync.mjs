#!/usr/bin/env node
// The Doc → script.md sync (codebase review V1). The script's source of truth is the Claude Doc; an agent exports
// its tab as Markdown (Claude Docs `export`, format markdown) and runs this on the file:
//   node pipeline/sync.mjs <export.md> --rev <n>            what would change: lines, notes, the beats they move
//   node pipeline/sync.mjs <export.md> --rev <n> --write    write script.md and renumber shots.json's line refs
//   --accept-notes S7,S10                                   also take those scenes' changed Shot: notes (after re-reading them)
//   --film <name>                                           sync films/<name>/script.md and shots.json instead of the intro's
// Lines are matched old to new within each scene, so a bullet added, removed or split renumbers every beat,
// event and pause that names a later line; a ref to a removed line stops the sync. A changed Shot: note is shown
// as a diff and keeps stopping the build until it's re-read and accepted. script.md records the Doc revision it
// came from, so the next sync can read only what changed (the Docs read's sinceRev).
import {readFileSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {checkScript, lineDiff, noteSha, noteText} from './check.mjs';
import {filmPaths} from './film.mjs';
import {norm} from './plan.mjs';
import {parseScript, said} from './script.mjs';

const here = join(dirname(fileURLToPath(import.meta.url)), '..');
const argv = process.argv.slice(2);
const opt = (k) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : undefined; };
const src = argv[0];
const film = opt('--film') ?? 'intro';
const paths = filmPaths(here, film);
const rev = opt('--rev');
if (!src || !rev) { console.error('usage: node pipeline/sync.mjs <export.md> --rev <n> [--write] [--accept-notes S7,S10] [--film <name>]'); process.exit(2); }
const accept = new Set((opt('--accept-notes') ?? '').split(',').filter(Boolean));

// The export escapes what the Doc shows literally, and marks kept trailing spaces; script.md is plain Markdown.
const HEADER = /^<!-- Synced from the script Doc at rev \d+[^\n]*-->\n/m;
const clean = (md) => md.replace(/&#32;/g, '').replace(/\\([*`])/g, '$1').split('\n').map((l) => l.trimEnd()).join('\n').replace(HEADER, '');
const oldMd = readFileSync(paths.script, 'utf8');
const lastRev = oldMd.match(/Synced from the script Doc at rev (\d+)/)?.[1];
let newMd = clean(readFileSync(src, 'utf8'));
const stamp = `<!-- Synced from the script Doc at rev ${rev} on ${new Date().toISOString().slice(0, 10)} by pipeline/sync.mjs; edit the Doc, not this file. -->\n`;
newMd = newMd.replace(/^(# [^\n]*\n)/, `$1${stamp}`);

const old = parseScript(oldMd), now = parseScript(newMd);
const shots = JSON.parse(readFileSync(paths.shots, 'utf8'));
const words = (t) => new Set(norm(t));
const like = (a, b) => { const A = words(a), B = words(b); return [...A].filter((w) => B.has(w)).length / Math.max(1, Math.max(A.size, B.size)); };

// Old line i → new line j (1-based), or null: the same text first (in order), then the most alike of what's left, in order.
function align(a, b) {
  const map = new Array(a.length).fill(null), taken = new Set();
  let j0 = 0;
  for (let i = 0; i < a.length; i++) for (let j = j0; j < b.length; j++) if (!taken.has(j) && a[i] === b[j]) { map[i] = j; taken.add(j); j0 = j + 1; break; }
  for (let i = 0; i < a.length; i++) {
    if (map[i] !== null) continue;
    const lo = Math.max(-1, ...map.slice(0, i).filter((x) => x !== null)), hi = Math.min(b.length, ...map.slice(i + 1).filter((x) => x !== null));
    let best = null, score = 0.5;
    for (let j = lo + 1; j < hi; j++) if (!taken.has(j) && like(a[i], b[j]) >= score) { best = j; score = like(a[i], b[j]); }
    if (best !== null) { map[i] = best; taken.add(best); }
  }
  return map.map((x) => (x === null ? null : x + 1));
}

const report = [], problems = [];
for (const sc of now.scenes) if (!old.scenes.some((s) => s.id === sc.id)) report.push(`+ scene ${sc.id} · ${sc.title}: needs a shot in shots.json`);
for (const os of old.scenes) {
  const ns = now.scenes.find((s) => s.id === os.id);
  if (!ns) { problems.push(`scene ${os.id} is gone from the Doc; remove its shot first`); continue; }
  const map = align(os.lines.map((l) => l.text), ns.lines.map((l) => l.text));
  map.forEach((j, i) => {
    if (j === null) report.push(`- ${os.id}-${i + 1}: "${os.lines[i].text}"`);
    else if (os.lines[i].text !== ns.lines[j - 1].text) report.push(`~ ${os.id}-${i + 1}${j !== i + 1 ? ` → ${os.id}-${j}` : ''}: "${os.lines[i].text}" → "${ns.lines[j - 1].text}"`);
    else if (j !== i + 1) report.push(`  ${os.id}-${i + 1} → ${os.id}-${j} (moved)`);
  });
  ns.lines.forEach((l, j) => { if (!map.includes(j + 1)) report.push(`+ ${os.id}-${j + 1}: "${l.text}"`); });
  // Renumber every ref to a line of this scene.
  const shot = shots[os.id];
  if (shot) {
    const re = (where, n) => { const j = map[n - 1]; if (j === undefined || j === null) { problems.push(`${os.id} ${where} names line ${n}, which the Doc no longer has: re-place it by hand`); return n; } return j; };
    (shot.beats ?? []).forEach((b, i) => { if (b.at?.line) b.at.line = re(`beat ${i}${b.id ? ` (#${b.id})` : ''}`, b.at.line); });
    for (const [k, e] of Object.entries(shot.events ?? {})) if (e.line) e.line = re(`event ${k}`, e.line);
    (shot.moves ?? []).forEach((m, i) => { if (m.line) m.line = re(`move ${i}`, m.line); });
    (shot.callouts ?? []).forEach((c, i) => { if (c.line) c.line = re(`callout ${i}`, c.line); });
    if (shot.pauses) shot.pauses = Object.fromEntries(Object.entries(shot.pauses).map(([k, v]) => [String(re(`pause`, +k)), v]));
    if (ns.shot && noteSha(ns) !== shot.shotSha) {
      if (accept.has(os.id)) { shot.shotSha = noteSha(ns); report.push(`${os.id}: Shot: note accepted (shotSha ${shot.shotSha}); check its requires`); }
      else report.push(`${os.id}: Shot: note changed; re-read it, then sync again with --accept-notes ${os.id}:\n${lineDiff(noteText(os), noteText(ns))}`);
    }
  }
}
// What the build would say about the result: words a beat lands on that a line no longer says, and the rest.
const {errors} = checkScript({here, repo: join(here, '..'), scenes: now.scenes, shots, lexicon: now.lexicon, said, cache: join(here, '.cache')});
console.log(`Doc rev ${rev}${lastRev ? ` (script.md was at rev ${lastRev})` : ''}`);
console.log(report.length ? report.join('\n') : 'no line or note changes');
if (errors.length) console.log(`\nthe build's check after this sync:\n${errors.map((e) => `- ${e}`).join('\n')}`);
if (problems.length) { console.log(`\nnot synced:\n${problems.map((p) => `- ${p}`).join('\n')}`); process.exit(1); }
if (argv.includes('--write')) {
  writeFileSync(paths.script, newMd);
  writeFileSync(paths.shots, JSON.stringify(shots, null, 2) + '\n');
  console.log('\nwrote script.md and shots.json');
} else console.log('\n(dry run: --write to apply)');
