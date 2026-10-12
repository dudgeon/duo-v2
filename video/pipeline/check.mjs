// The check stage (codebase review V1): everything about the script and the shots that can be known without
// voicing, capturing or rendering, so a renamed state or a beat on a word the line doesn't have stops the build in
// seconds, not after ten minutes of voicing. Every problem is collected, not just the first.
import {existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {HEARD_AS, TRANSITIONS, fromOk, norm, sceneType, toOk} from './plan.mjs';
import {sha} from './util.mjs';

// The fixture states the app can draw: VideoTargets' screen lists, read from its source.
export function appStates(repo) {
  const dir = join(repo, 'Sources/DuoKit/Debug');
  const out = new Set();
  for (const f of readdirSync(dir).filter((n) => /^VideoTargets.*\.swift$/.test(n))) {
    const src = readFileSync(join(dir, f), 'utf8');
    for (const m of src.matchAll(/static (?:let|var) \w*[sS]creens\s*(?::[^=\n]*)?=\s*\[([\s\S]*?)\]/g))
      for (const s of m[1].matchAll(/"(video-[a-z0-9-]+)"/g)) out.add(s[1]);
  }
  return out;
}

// Every state a shot shows: its list, plus (app scenes) the states its beats switch to or read anchors from, and its entry's.
export const shotStates = (s) => (s.kind === 'desk' ? [s.state] : [...(s.states ?? []), ...(s.beats ?? []).flatMap((b) => [b.state, b.in, b.wipe?.state, b.drag?.reveal]),
  s.entry?.base, ...Object.values(s.entry?.panes ?? {})].filter(Boolean));

export const noteText = (sc) => [sc.shot, ...sc.notes].join('\n');
export const noteSha = (sc) => sha(noteText(sc)).slice(0, 12);

// Does `phrase` occur `nth` times in these words (as wordTime reads them: a heard word stands for its name)?
const hasPhrase = (words, phrase, nth = 1) => {
  const w = words.map((x) => HEARD_AS[x] ?? x), want = norm(phrase);
  let seen = 0;
  for (let i = 0; i < w.length; i++) if (want.every((p, j) => w[i + j] === p) && ++seen === nth) return true;
  return false;
};

// A `requires` item's `by`: what realises it. "#id" a beat with that id, "event:name", "state:name", "transition",
// or "src:path" (a component under video/ that draws it). An item is built when its refs all resolve; an item
// without one must say `built: false`, and the report names it.
function resolveBy(ref, shot, here) {
  if (ref.startsWith('#')) return (shot.beats ?? []).some((b) => b.id === ref.slice(1));
  if (ref.startsWith('event:')) return !!shot.events?.[ref.slice(6)];
  if (ref.startsWith('state:')) return shotStates(shot).includes(ref.slice(6));
  if (ref === 'transition') return !!shot.transitionIn;
  if (ref.startsWith('src:')) return existsSync(join(here, ref.slice(4)));
  return false;
}

export function checkScript({here, repo, scenes, shots, lexicon, said, cache}) {
  const errors = [], missing = [];
  const ids = Object.keys(shots).filter((k) => !k.startsWith('$'));
  for (const id of ids) if (!scenes.some((s) => s.id === id)) errors.push(`shots: ${id} is in shots.json but not in the script`);
  const states = appStates(repo);
  const notes = join(cache, 'shot-notes');
  mkdirSync(notes, {recursive: true});
  let prev = null;
  for (const sc of scenes) {
    const shot = shots[sc.id];
    if (!shot) { errors.push(`shots: scene ${sc.id} "${sc.title}" has no shot in shots.json`); continue; }
    // The Shot: note is a checklist: a changed note stops the build until the shot is re-read. The text each
    // hash stood for is kept in .cache/shot-notes, so a change shows as a diff.
    if (sc.shot) {
      const now = noteSha(sc);
      if (shot.shotSha !== now) {
        const was = join(notes, `${shot.shotSha}.txt`);
        const diff = existsSync(was) ? lineDiff(readFileSync(was, 'utf8'), noteText(sc)) : '  (the text it was is not in this machine\'s cache)';
        errors.push(`shots: ${sc.id}'s Shot: note changed since shots.json was written (now ${now}). Re-read it, update ${sc.id}.requires, then set shotSha.\n${diff}`);
      } else writeFileSync(join(notes, `${now}.txt`), noteText(sc));
      if (!shot.requires?.length) errors.push(`shots: ${sc.id} has a Shot: note but no requires list`);
      for (const r of shot.requires ?? []) {
        if (r.built === false && !r.by?.length) { missing.push(`${sc.id}: ${r.what}`); continue; }
        if (!r.by?.length) { errors.push(`shots: ${sc.id} requires "${r.what}", but names nothing that builds it: give it by: ["#beat-id" | "event:…" | "state:…" | "transition" | "src:…"], or built: false`); continue; }
        for (const ref of r.by) if (!resolveBy(ref, shot, here)) errors.push(`shots: ${sc.id} requires "${r.what}" by ${ref}, which ${sc.id} doesn't have`);
      }
    }
    // States the app can't draw.
    if (shot.kind !== 'card') for (const st of new Set(shotStates(shot))) if (!states.has(st)) errors.push(`shots: ${sc.id} uses state ${st}, which isn't in VideoTargets' screens. Renamed?`);
    const beatIds = (shot.beats ?? []).map((b) => b.id).filter(Boolean);
    for (const d of beatIds.filter((x, i) => beatIds.indexOf(x) !== i)) errors.push(`shots: ${sc.id} has two beats with id ${d}`);
    // The way in.
    if (prev) {
      const tr = TRANSITIONS[shot.transitionIn];
      if (!tr) errors.push(`transition: ${sc.id} has no way in from ${prev.id}${shot.transitionIn ? ` ("${shot.transitionIn}" is not in plan.mjs TRANSITIONS)` : ''}`);
      else if (!fromOk(tr, sceneType(shots[prev.id] ?? {})) || !toOk(tr, sceneType(shot))) errors.push(`transition: "${shot.transitionIn}" goes ${tr.from} -> ${tr.to}, but ${prev.id} -> ${sc.id} is ${sceneType(shots[prev.id] ?? {})} -> ${sceneType(shot)}`);
    }
    prev = sc;
    // Every timed thing lands on a line the scene has, on a word that line says.
    const refs = [
      ...(shot.beats ?? []).map((b, i) => [`beat ${i}${b.id ? ` (#${b.id})` : ''}`, b.at]),
      ...Object.entries(shot.events ?? {}).map(([k, e]) => [`event ${k}`, e]),
      ...(shot.moves ?? []).map((m, i) => [`move ${i}`, {line: m.line, word: m.land}]),
      ...(shot.callouts ?? []).map((c, i) => [`callout ${i}`, c]),
    ];
    for (const [what, a] of refs) {
      if (!a || typeof a !== 'object' || a.line === undefined) continue;
      const line = sc.lines[a.line - 1];
      if (!line) { errors.push(`shots: ${sc.id} ${what} names line ${a.line}, but the scene has ${sc.lines.length}`); continue; }
      if (!a.word) continue;
      const words = norm(line.text), heard = norm(said(line.text, lexicon));
      if (!hasPhrase(words, a.word, a.nth) && !hasPhrase(heard, a.word, a.nth))
        errors.push(`shots: ${sc.id} ${what} lands on "${a.word}"${a.nth > 1 ? ` (#${a.nth})` : ''}, which ${line.id} doesn't say: "${line.text}"`);
    }
    for (const k of Object.keys(shot.pauses ?? {})) if (!sc.lines[+k - 1]) errors.push(`shots: ${sc.id} pauses after line ${k}, but the scene has ${sc.lines.length}`);
  }
  return {errors, missing};
}

// The script's lines against the last build's: what changed, by line id.
export function scriptChanges(scenes, file) {
  const now = Object.fromEntries(scenes.flatMap((s) => s.lines.map((l) => [l.id, l.text])));
  if (!existsSync(file)) return {now, changes: null};
  const was = JSON.parse(readFileSync(file, 'utf8'));
  const changes = [];
  for (const [id, t] of Object.entries(now)) if (was[id] === undefined) changes.push(`+ ${id}: ${t}`); else if (was[id] !== t) changes.push(`~ ${id}: "${was[id]}" → "${t}"`);
  for (const id of Object.keys(was)) if (now[id] === undefined) changes.push(`- ${id}: ${was[id]}`);
  return {now, changes};
}

// A small line diff (enough for a Shot: note): lines only in the old text, then only in the new.
export function lineDiff(a, b) {
  const A = a.split('\n'), B = b.split('\n');
  return [...A.filter((l) => !B.includes(l)).map((l) => `  - ${l}`), ...B.filter((l) => !A.includes(l)).map((l) => `  + ${l}`)].join('\n') || '  (same lines, reordered)';
}
