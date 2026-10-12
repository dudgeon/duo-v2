#!/usr/bin/env node
// The intro video's build (DL-169): script → voice → captures → timeline → lint → render → proof.
// Every product is content-addressed in .cache/, so an unchanged line is never re-voiced and an
// unchanged app is never recaptured.
//   node build.mjs              full build: out/intro.mp4, a still per scene, contact sheet, report
//   node build.mjs --draft      half-size render, for a quick look
//   node build.mjs --stills     no video: one still per scene, where its camera lands
//   --force-voice / --force-capture  redo those stages anyway
import {spawnSync} from 'node:child_process';
import {copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {captureStates} from './pipeline/capture.mjs';
import {plan} from './pipeline/plan.mjs';
import {parseScript, said} from './pipeline/script.mjs';
import {BuildError, sha} from './pipeline/util.mjs';
import {voiceLines} from './pipeline/voice.mjs';
import {scoreBed} from './pipeline/score.mjs';
import {prepareWallpaper} from './pipeline/wallpaper.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, '..');
const cache = join(here, '.cache'), pub = join(here, 'build/public'), out = join(here, 'out');
for (const d of [cache, pub, out]) mkdirSync(d, {recursive: true});
const args = new Set(process.argv.slice(2));
const report = [];
const log = (s) => { console.log(s); report.push(s); };
const remotion = (...a) => spawnSync(join(here, 'node_modules/.bin/remotion'), [...a, '--log=error'], {cwd: here, stdio: 'inherit'});
const fmt = (s) => `${Math.floor(s / 60)}:${(s % 60).toFixed(1).padStart(4, '0')}`;

try {
  const style = JSON.parse(readFileSync(join(here, 'style/tokens.json'), 'utf8'));
  const shots = JSON.parse(readFileSync(join(here, 'shots.json'), 'utf8'));

  // 1. Script
  const {scenes, lexicon} = parseScript(readFileSync(join(here, 'script.md'), 'utf8'));
  if (!scenes.length) throw new BuildError('script: no scenes in script.md');
  for (const id of Object.keys(shots).filter((k) => !k.startsWith('$'))) {
    if (!scenes.some((s) => s.id === id)) throw new BuildError(`shots: ${id} is in shots.json but not in the script`);
  }
  // Each Shot: note is a checklist (script v2's rule). shots.json records the note's hash and what it asks for;
  // a changed note stops the build until the shot is re-read, and anything not built yet is reported, never silent.
  const missing = [];
  for (const sc of scenes) {
    const shot = shots[sc.id];
    if (!shot || !sc.shot) continue;
    const noteSha = sha([sc.shot, ...sc.notes].join('\n')).slice(0, 12);
    if (shot.shotSha !== noteSha) throw new BuildError(`shots: ${sc.id}'s Shot: note changed since shots.json was written (now ${noteSha}). Re-read it, update ${sc.id}.requires, then set shotSha.`);
    if (!shot.requires?.length) throw new BuildError(`shots: ${sc.id} has a Shot: note but no requires list`);
    for (const r of shot.requires) if (!r.built) missing.push(`${sc.id}: ${r.what}`);
  }
  for (const m of missing) log(`NOT BUILT YET ${m}`);
  const lines = scenes.flatMap((s) => s.lines.map((l) => ({...l, said: said(l.text, lexicon)})));
  log(`script: ${scenes.length} scenes, ${lines.length} lines`);

  // 2. Voice
  const voiced = voiceLines(lines, {here, cache, pub, style, force: args.has('--force-voice'), log});

  // 3. Captures
  // Every state a shot shows: its list, plus (app scenes) the states its beats switch to or read anchors from, and its entry's.
  const shotStates = (s) => (s.kind === 'desk' ? [s.state] : [...(s.states ?? []), ...(s.beats ?? []).flatMap((b) => [b.state, b.in, b.wipe?.state, b.drag?.reveal]),
    s.entry?.base, ...Object.values(s.entry?.panes ?? {})].filter(Boolean));
  const states = [...new Set(Object.values(shots).filter((s) => typeof s === 'object').flatMap(shotStates))];
  const captures = captureStates(states, {repo, cache, pub, scale: style.capture.scale, fixture: style.capture.fixture, force: args.has('--force-capture'), log});

  // 4. Timeline
  const timeline = plan({scenes, shots, voiced, captures, style});
  // 5. Score: the bed for the film's length, mixed in the film under the voice (pipeline/score.mjs).
  if (!args.has('--no-score')) timeline.score = scoreBed({here, cache, pub, duration: timeline.duration, voiceWavs: voiced.slice(0, 8).map((l) => join(pub, l.src)), log});
  for (const sc of timeline.scenes) if (sc.transitionIn) log(`transition: into ${sc.id} by ${sc.transitionIn.name} (${sc.transitionIn.kind === 'app' ? 'app navigation' : 'motion graphic'})`);
  writeFileSync(join(pub, 'timeline.json'), JSON.stringify(timeline, null, 2));
  log(`timeline: ${fmt(timeline.duration)} (${timeline.scenes.map((s) => `${s.id} ${s.duration.toFixed(1)}s`).join(', ')})`);

  // 5. Wallpaper
  prepareWallpaper({style, here, cache, pub, remotion, log});

  // S1's browser window shows this real HTML page in an <IFrame> (src/lib/ClutterApps.tsx).
  { const proto = JSON.parse(readFileSync(join(here, 'fixture/docs/content.json'), 'utf8')).prototype.file; mkdirSync(dirname(join(pub, proto)), {recursive: true}); copyFileSync(join(here, 'fixture/docs', proto), join(pub, proto)); }

  // 6. Lint
  if (spawnSync('node', [join(here, 'lint.mjs')], {stdio: 'inherit'}).status !== 0) throw new BuildError('lint');

  // 7. Stills: each scene where its camera has landed, or its middle
  // Each scene at its most telling moment: a callout fully open, else where the camera lands, else the middle.
  const stillAt = (s) => s.start + Math.min(s.duration - 0.1,
    s.callouts?.length ? s.callouts[0].start + 1.0 : s.camera?.length > 1 ? s.camera[s.camera.length - 1].t + 0.3 : s.duration * 0.7);
  for (const s of timeline.scenes) {
    remotion('still', 'src/index.ts', 'Intro', join(out, `still-${s.id}.png`), `--frame=${Math.round(stillAt(s) * timeline.fps)}`);
  }
  // The thumbnail: the first scene's settled frame, when its shot names one (S0's logo and title).
  const first = timeline.scenes[0], thumbAt = shots[first.id]?.thumbnail;
  if (thumbAt !== undefined) {
    remotion('still', 'src/index.ts', 'Intro', join(out, 'thumbnail.png'), `--frame=${Math.round((first.start + (thumbAt < 0 ? (first.exit?.at ?? first.duration) + thumbAt : thumbAt)) * timeline.fps)}`);
    log('thumbnail: out/thumbnail.png');
  }
  const n = timeline.scenes.length;
  spawnSync('/bin/sh', ['-c', `ffmpeg -v error -y ${timeline.scenes.map((s) => `-i "${join(out, `still-${s.id}.png`)}"`).join(' ')} ` +
    `-filter_complex "${timeline.scenes.map((_, i) => `[${i}]scale=640:360,setsar=1[s${i}]`).join(';')};${timeline.scenes.map((_, i) => `[s${i}]`).join('')}concat=n=${n}:v=1:a=0,tile=4x${Math.ceil(n / 4)}:padding=6" -frames:v 1 "${join(out, 'stills.png')}"`]);

  // 8. Render
  if (!args.has('--stills')) {
    const mp4 = join(out, args.has('--draft') ? 'intro-draft.mp4' : 'intro.mp4');
    if (remotion('render', 'src/index.ts', 'Intro', mp4, ...(args.has('--draft') ? ['--scale=0.5'] : [])).status !== 0) throw new BuildError('render');
    spawnSync('ffmpeg', ['-v', 'error', '-y', '-i', mp4, '-vf', 'fps=1,scale=320:-1,tile=8x0:padding=4', '-frames:v', '1', join(out, 'contact-sheet.png')]);
    log(`render: ${mp4}`);
    // The score's ear check (after the sound-design method Geoff sent): a waveform of the final mix, and five
    // timecodes to listen at. The checks above are numbers; whether the bed sits right is decided by ear.
    if (timeline.score) {
      spawnSync('ffmpeg', ['-v', 'error', '-y', '-i', mp4, '-filter_complex', 'showwavespic=s=2400x360:split_channels=0:colors=#2F6FEB', '-frames:v', '1', join(out, 'score-qa.png')]);
      const lines = timeline.scenes.flatMap((s) => s.lines.map((l) => ({id: l.id, start: s.start + l.start, end: s.start + l.start + l.duration})));
      let gap = {at: 0, len: 0};
      for (let i = 1; i < lines.length; i++) if (lines[i].start - lines[i - 1].end > gap.len) gap = {at: lines[i - 1].end, len: lines[i].start - lines[i - 1].end};
      const topic = timeline.scenes.find((s, i) => i > 0 && s.topic && s.topic !== 'same');
      const at = [
        ['The open: the bed fades in under S0', 0.5],
        [`A topic change (${topic?.id}): a small swell while the topic list is up`, topic ? topic.start - 0.5 : 10],
        [`The longest gap between lines (${gap.len.toFixed(1)} s): the bed up, never louder than the voice`, gap.at],
        ['A busy stretch of speech (S6): the bed well under, words clear', timeline.scenes.find((s) => s.id === 'S6')?.start + 2 || 90],
        ['The end card: the bed fades out with the hold', timeline.duration - 6],
      ];
      writeFileSync(join(out, 'LISTEN.md'), `# Listen at\n\nThe score is checked by numbers; these five moments are for the ear.\n\n${at.map(([w, t]) => `- **${fmt(t)}**: ${w}`).join('\n')}\n\nWaveform: score-qa.png.\n`);
    }
  }
  const table = timeline.scenes.map((s) => `| ${s.id} | ${s.title} | ${fmt(s.start)} | ${s.duration.toFixed(1)} s | ${s.kind}${s.card?.standIn ? ' (stand-in)' : ''} |`).join('\n');
  const gaps = missing.length ? `## Not built yet\n\nThe script asks for these and this cut doesn't have them:\n\n${missing.map((m) => `- ${m}`).join('\n')}\n\n` : '';
  writeFileSync(join(out, 'report.md'), `# Intro video build\n\n${gaps}${report.map((l) => `- ${l}`).join('\n')}\n\n| Scene | Title | Starts | Length | Shot |\n|---|---|---|---|---|\n${table}\n`);
} catch (e) {
  if (e instanceof BuildError) { console.error(`BUILD FAILED: ${e.message}`); process.exit(1); }
  throw e;
}
