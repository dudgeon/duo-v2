// Render the film a scene at a time, cached (codebase review V2). Each scene's frames are rendered once and kept in
// .cache/render/ under a key of everything that draws them; a build renders only the scenes whose key changed and
// joins the rest from the cache. The soundtrack (voice, score, ducking) is rendered once for the whole film, so the
// music and its ducking run on unbroken across scene edges, then normalised and muxed with the joined picture.
//
// What draws a scene's frames: its own slice of timeline.json (start replaced by its sub-frame phase, so a scene
// that only moved later in the film keeps its key), the topic list and the topic changes near it (the topic list
// slides in over the scene edges), the scene before it when that scene's frames spill into this one's range, the
// content of every published file it names (captures by their pixels, not by the app build that took them), the
// published files every scene uses (wallpaper, topic paper, prototype), the source (src/, style/, remotion.config.ts,
// package-lock.json), and the render settings.
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {existsSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync} from 'node:fs';
import {join, relative} from 'node:path';
import {BuildError, fileSha, sha} from './util.mjs';
import {filmNames, INTRO} from './film.mjs';

const walk = (dir, skip = () => false) => (existsSync(dir) ? readdirSync(dir).sort().flatMap((n) => {
  const p = join(dir, n);
  if (n.startsWith('.') || skip(p)) return [];
  return statSync(p).isDirectory() ? walk(p, skip) : [p];
}) : []);
const files = (p) => (!existsSync(p) ? [] : statSync(p).isDirectory() ? walk(p) : [p]);
// Markdown under style/ is for people (shot grammar, taste), not read by the film, so it doesn't key a render.
// A source line containing `@film-hook` is the film registry's hook in Film.tsx (a pure insertion); it is left out of the hash,
// so adding a film leaves the intro's keys as they were.
const HOOK = '@film-hook';
const srcSha = (f) => {
  if (!f.endsWith('.tsx')) return fileSha(f);
  const text = readFileSync(f, 'utf8');
  return text.includes(HOOK) ? createHash('sha256').update(text.split('\n').filter((l) => !l.includes(HOOK)).join('\n')).digest('hex').slice(0, 16) : fileSha(f);
};
const treeKey = (root, paths, skip = () => false) => sha(...paths.flatMap((p) => files(join(root, p))).filter((f) => !f.endsWith('.md') && !skip(relative(root, f))).map((f) => `${relative(root, f)} ${srcSha(f)}`));
// What draws a film's frames. A film's own scenes live in src/scenes/<film>/, and src/scenes/registry.ts lists them, so
// one film's key leaves out the other films' scene folders, and the intro's leaves out the registry too.
function sourceKey(here, film) {
  const others = filmNames(here).filter((n) => n !== INTRO && n !== film);
  const skip = (rel) => others.some((n) => rel.startsWith(`src/scenes/${n}/`)) || (film === INTRO && rel === 'src/scenes/registry.ts');
  return treeKey(here, ['src', 'style', 'remotion.config.ts', 'package-lock.json'], skip);
}

// The frame ranges: scene k from its first frame to the frame before the next scene's first, the last to the end.
export function sceneRanges(timeline) {
  const {fps, scenes, frames} = timeline;
  const first = scenes.map((s) => Math.round(s.start * fps));
  return scenes.map((s, k) => ({id: s.id, from: first[k], to: (k + 1 < scenes.length ? first[k + 1] : frames) - 1}));
}

export function sceneKeys({here, pub, timeline, scale, encode = null, film = INTRO, styleOverride = null}) {
  const {fps} = timeline;
  const src = sourceKey(here, film);
  // Another film's own style/tokens.json changes how its frames are drawn; the intro has none, so its key is as before.
  const own = styleOverride ? fileSha(styleOverride) : null;
  const shared = treeKey(pub, ['wallpaper.png', 'topics-bg.png', 'prototype']);
  // The topic list's changes, as Film.tsx computes them (src/lib/Topics.tsx topicChanges).
  const topics = [], changes = [];
  let last;
  timeline.scenes.forEach((s, i) => {
    if (!s.topic || s.topic === last) return;
    topics.push(s.topic);
    if (i > 0 && last !== undefined) changes.push({at: s.start, index: topics.length - 1, from: topics.length - 2});
    last = s.topic;
  });
  const ranges = sceneRanges(timeline);
  const named = (o) => {
    const out = new Set();
    const visit = (v) => { if (typeof v === 'string') { if (/\.(png|jpe?g|svg|html|wav|mp4|json)$/.test(v) && existsSync(join(pub, v))) out.add(v); } else if (v && typeof v === 'object') Object.values(v).forEach(visit); };
    visit(o);
    return [...out].sort().map((f) => `${f} ${fileSha(join(pub, f))}`);
  };
  return timeline.scenes.map((s, k) => {
    const r = ranges[k];
    // A line's voice file and key name its audio, which a scene's frames don't draw (they render muted): a re-voice or a
  // voice cache re-key (DL-179) keeps the scene.
  const silent = (l) => { const {src: _src, key: _key, ...rest} = l; return rest; };
  const local = {...s, start: +(r.from - s.start * fps).toFixed(6), lines: s.lines.map(silent)};
    const near = changes.filter((c) => c.at > s.start - 10 && c.at < s.start + s.duration + 10).map((c) => ({...c, at: +(c.at - s.start).toFixed(6)}));
    const prev = timeline.scenes[k - 1];
    const spills = prev && Math.round(prev.start * fps) + Math.ceil(prev.duration * fps) > r.from;
    const key = sha(...['scene-render-1', src, ...(own ? [own] : []), shared, scale, encode, fps, timeline.fade, r.to - r.from + 1, k === timeline.scenes.length - 1, local, topics, near,
      spills ? {...prev, start: +(prev.start - s.start).toFixed(6), lines: prev.lines.map(silent)} : null, named(local)]);
    return {...r, key};
  });
}

// The soundtrack's key: what Film.tsx's <Audio>s play. Each scene's span (its Sequence cuts its lines), each line's
// timing and voice file by content, the score bed by content with its gain settings, the topic changes it ducks at,
// the film's length, the frames wanted and the source. A camera move or a new capture keeps the soundtrack.
export function soundtrackKey({here, pub, timeline, from, to, film = INTRO}) {
  const src = sourceKey(here, film);
  const {fps} = timeline;
  const scenes = timeline.scenes.map((s) => ({start: s.start, duration: s.duration, topic: s.topic ?? null,
    lines: s.lines.map((l) => ({start: l.start, duration: l.duration, wav: fileSha(join(pub, l.src))}))}));
  const score = timeline.score ? {...timeline.score, wav: fileSha(join(pub, timeline.score.src))} : null;
  return sha('soundtrack-1', src, fps, timeline.fade, timeline.duration, timeline.frames, from, to, scenes, score);
}

// encode: remotion flags for the scenes' encoder, when not remotion.config.ts's H.264. V2's frame-identical proof
// renders ProRes, which codes each frame alone, so the same pixels make the same frames however the film is split
// (Remotion refuses H.264 at CRF 0). A ProRes film goes in a .mov.
export function renderFilm({here, pub, out, cache, timeline, scale = 1, encode = null, only = null, name = null, cover = null, film = INTRO, publicDirArgs = [], styleOverride = null, log}) {
  const rc = join(cache, 'render');
  mkdirSync(rc, {recursive: true});
  const ext = encode?.some((a) => a.includes('prores')) ? 'mov' : 'mp4';
  const scaleArgs = [...(scale !== 1 ? [`--scale=${scale}`] : []), ...(encode ?? [])];
  const remotion = (...a) => spawnSync(join(here, 'node_modules/.bin/remotion'), [...a, '--log=error', ...publicDirArgs], {cwd: here, stdio: 'inherit'});
  const keys = sceneKeys({here, pub, timeline, scale, encode, film, styleOverride});
  const want = only ? keys.filter((k) => only.includes(k.id)) : keys;
  if (only && want.length !== only.length) throw new BuildError(`render: no scene ${only.filter((id) => !keys.some((k) => k.id === id)).join(', ')} in the timeline`);
  const rendered = [];
  for (const k of want) {
    const mp4 = join(rc, `${k.key}.${ext}`);
    if (existsSync(mp4)) continue;
    log(`render: ${k.id}, frames ${k.from}–${k.to}`);
    const tmp = join(rc, `${k.key}.part.${ext}`);
    if (remotion('render', 'src/index.ts', 'Intro', tmp, `--frames=${k.from}-${k.to}`, '--muted', ...scaleArgs).status !== 0) throw new BuildError(`render: ${k.id} failed`);
    renameSync(tmp, mp4);
    rendered.push(k.id);
  }
  log(`render: ${want.length} scene(s), ${rendered.length} rendered, ${want.length - rendered.length} from cache`);
  // The soundtrack for the frames wanted, in one piece, then -16 LUFS (peaks under -1.5 dBTP), the level web video plays at.
  const from = want[0].from, to = want[want.length - 1].to;
  // Cached on its inputs (soundtrackKey), so a build that changed only pictures doesn't redo it (about 3.4 min).
  // --crf=0: the config's CRF is for the picture, and Remotion refuses any other CRF for an audio codec (it ignores 0).
  const wav = join(rc, `audio-${soundtrackKey({here, pub, timeline, from, to, film})}.wav`);
  if (existsSync(wav)) log('render: soundtrack from cache');
  else {
    const part = join(rc, `audio-${process.pid}.part.wav`);
    if (remotion('render', 'src/index.ts', 'Intro', part, '--codec=wav', '--crf=0', `--frames=${from}-${to}`).status !== 0) throw new BuildError('render: the soundtrack failed');
    renameSync(part, wav);
  }
  const list = join(rc, `concat-${process.pid}.txt`);
  writeFileSync(list, want.map((k) => `file '${join(rc, `${k.key}.${ext}`)}'\n`).join(''));
  name ??= only ? `scene-${only.join('-')}${scale !== 1 ? '-draft' : ''}.mp4` : scale !== 1 ? `${film}-draft.mp4` : `${film}.mp4`;
  const mp4 = join(out, name);
  // cover: a picture for the file's cover art (out/thumbnail.png, the title card), which QuickTime and Finder show.
  const art = cover && existsSync(cover) ? ['-i', cover, '-map', '2:v', '-c:v:1', 'png', '-disposition:v:1', 'attached_pic'] : [];
  const mux = spawnSync('ffmpeg', ['-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', list, '-i', wav, ...art.slice(0, 2), '-map', '0:v', '-map', '1:a', ...art.slice(2), '-c:v:0', 'copy',
    '-af', 'loudnorm=I=-16:TP=-1.5:LRA=11', '-c:a', 'aac', '-b:a', '256k', '-ar', '48000', '-movflags', '+faststart', mp4]);
  rmSync(list, {force: true});
  if (mux.status !== 0) throw new BuildError('render: joining the scenes failed');
  log(`render: ${mp4}${only ? '' : ', soundtrack at -16 LUFS'}`);
  return {mp4, rendered, keys};
}

// Clips for review: each scene re-rendered in this build, at 480p, cut from the joined film.
export function reviewClips({out, timeline, rendered, film = INTRO}) {
  const dir = join(out, 'review');
  mkdirSync(dir, {recursive: true});
  const clips = {};
  for (const s of timeline.scenes.filter((x) => rendered.includes(x.id))) {
    const clip = join(dir, `${s.id}.mp4`);
    spawnSync('ffmpeg', ['-v', 'error', '-y', '-ss', String(s.start), '-t', String(s.duration), '-i', join(out, `${film}.mp4`), '-vf', 'scale=-2:480',
      '-c:v', 'libx264', '-crf', '28', '-preset', 'veryfast', '-c:a', 'aac', '-b:a', '128k', clip]);
    if (existsSync(clip)) clips[s.id] = `review/${s.id}.mp4`;
  }
  return clips;
}

// Cache housekeeping (--gc): remove captures and scene renders the current build doesn't use, and leftover job
// folders. Voiced lines and score beds stay: another narrator's lines (DUO_VOICE_JSON) cost a GPU run to redo.
export function gcCache({cache, liveCaptureKeys, liveRenderKeys, log}) {
  let n = 0, bytes = 0;
  const rm = (p) => { try { bytes += statSync(p).size; } catch {} rmSync(p, {recursive: true, force: true}); n++; };
  const cc = join(cache, 'capture');
  if (existsSync(cc)) for (const f of readdirSync(cc)) if (!liveCaptureKeys.has(f.split('.')[0])) rm(join(cc, f));
  const rc = join(cache, 'render');
  if (existsSync(rc)) for (const f of readdirSync(rc)) if (!liveRenderKeys.has(f.split('.')[0])) rm(join(rc, f));
  const vc = join(cache, 'voice');
  if (existsSync(vc)) for (const f of readdirSync(vc)) if (f.startsWith('job-')) rm(join(vc, f));
  log(`gc: removed ${n} cache entries (${(bytes / 1e9).toFixed(2)} GB)`);
}
