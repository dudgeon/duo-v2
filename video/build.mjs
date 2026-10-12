#!/usr/bin/env node
// The intro video's build (DL-169): script → voice → captures → timeline → lint → render → proof.
// Every product is content-addressed in .cache/, so an unchanged line is never re-voiced and an
// unchanged app is never recaptured.
//   node build.mjs              full build: out/intro.mp4, a still per scene, contact sheet, report
//   node build.mjs --draft      half-size render, for a quick look
//   node build.mjs --scene S7   render one scene (or S7,S8) to out/scene-S7.mp4, from the cache where unchanged; with --draft, half size
//   --whole                     render the film in one pass (no scene cache); --gc  drop unused captures and scene renders
//   node build.mjs --stills     no video: one still per scene, where its camera lands
//   node build.mjs --check      the check stage only (seconds, no voicing, capture or render); with voice and captures cached, the plan too
//   --force-voice / --force-capture  redo those stages anyway
//   --accept-anchors            take this build's framing as the new record for the stale-anchor check
import {spawnSync} from 'node:child_process';
import {copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {checkAnchors} from './pipeline/anchors.mjs';
import {checkScript, scriptChanges, shotStates} from './pipeline/check.mjs';
import {captureStates} from './pipeline/capture.mjs';
import {plan} from './pipeline/plan.mjs';
import {parseScript, said} from './pipeline/script.mjs';
import {BuildError} from './pipeline/util.mjs';
import {voiceLines, voiceSetup} from './pipeline/voice.mjs';
import {gcCache, renderFilm, reviewClips, sceneKeys, soundtrackKey} from './pipeline/render.mjs';
import {scoreBed} from './pipeline/score.mjs';
import {prepareWallpaper} from './pipeline/wallpaper.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, '..');
const cache = join(here, '.cache'), pub = join(here, 'build/public'), out = join(here, 'out');
for (const d of [cache, pub, out]) mkdirSync(d, {recursive: true});
const argv = process.argv.slice(2), args = new Set(argv);
const report = [];
const log = (s) => { console.log(s); report.push(s); };
const remotion = (...a) => spawnSync(join(here, 'node_modules/.bin/remotion'), [...a, '--log=error'], {cwd: here, stdio: 'inherit'});
const fmt = (s) => `${Math.floor(s / 60)}:${(s % 60).toFixed(1).padStart(4, '0')}`;

try {
  const style = JSON.parse(readFileSync(join(here, 'style/tokens.json'), 'utf8'));
  const shots = JSON.parse(readFileSync(join(here, 'shots.json'), 'utf8'));

  // 1. Script, and the check stage: everything that can be known without voicing, capturing or rendering.
  const {scenes, lexicon} = parseScript(readFileSync(join(here, 'script.md'), 'utf8'));
  if (!scenes.length) throw new BuildError('script: no scenes in script.md');
  const {errors, missing} = checkScript({here, repo, scenes, shots, lexicon, said, cache});
  // The voice's file is checked here too: a missing one stops the build before anything is voiced.
  const voice = voiceSetup({here});
  const changes = scriptChanges(scenes, join(cache, 'last-build-script.json'));
  if (changes.changes?.length) log(`script since the last build:\n${changes.changes.map((c) => `  ${c}`).join('\n')}`);
  if (errors.length) throw new BuildError(`check: ${errors.length} problem(s):\n${errors.map((e) => `- ${e}`).join('\n')}`);
  for (const m of missing) log(`NOT BUILT YET ${m}`);
  const lines = scenes.flatMap((s) => s.lines.map((l) => ({...l, said: said(l.text, lexicon)})));
  log(`script: ${scenes.length} scenes, ${lines.length} lines; check passed`);
  const states = [...new Set(Object.values(shots).filter((s) => typeof s === 'object').flatMap(shotStates))];
  if (args.has('--check')) {
    // With every line voiced and every state captured already, the plan itself is checked too: anchors, heard words, stale framing.
    const keyed = voice.keyed(lines);
    const unvoiced = keyed.filter((l) => !existsSync(join(cache, 'voice', `${l.key}.asr.json`)));
    const captures = captureStates(states, {repo, cache, pub, scale: style.capture.scale, fixture: style.capture.fixture, cachedOnly: true, log: () => {}});
    if (unvoiced.length || !captures) { log(`check: plan not checked (${unvoiced.length ? `${unvoiced.length} line(s) not voiced yet` : 'captures not all cached'}); a build voices and captures them`); process.exit(0); }
    const voiced = keyed.map((l) => { const a = JSON.parse(readFileSync(join(cache, 'voice', `${l.key}.asr.json`), 'utf8')); return {...l, duration: a.duration_s, words: a.words}; });
    const used = [];
    const tl = plan({scenes, shots, voiced, captures, style, used});
    const anchors = checkAnchors({used, captures, cache, record: false});
    for (const m of anchors.stale) log(`STALE ${m}`);
    log(`check: plan ok, ${fmt(tl.duration)}, ${used.length} rects read, ${anchors.moved.length} moved with the app, ${anchors.stale.length} stale`);
    process.exit(anchors.stale.length ? 1 : 0);
  }

  // 2. Voice
  const voiced = voiceLines(lines, {here, cache, pub, style, force: args.has('--force-voice'), log});

  // 3. Captures
  const captures = captureStates(states, {repo, cache, pub, scale: style.capture.scale, fixture: style.capture.fixture, force: args.has('--force-capture'), log});

  // 4. Timeline
  const used = [];
  const timeline = plan({scenes, shots, voiced, captures, style, used});
  // Rects that follow anchors move with the app; rects in window points that the app moved under are stale (pipeline/anchors.mjs).
  const anchors = checkAnchors({used, captures, cache, accept: args.has('--accept-anchors')});
  for (const m of anchors.moved) log(`anchors: ${m}`);
  for (const m of anchors.stale) log(`STALE ${m}`);
  log(`anchors: ${used.length} rects read, ${anchors.absolute} in window points${anchors.first ? ' (first record: nothing to compare)' : ''}`);
  // 5. Score: the bed for the film's length, mixed in the film under the voice (pipeline/score.mjs).
  if (!args.has('--no-score')) timeline.score = scoreBed({here, cache, pub, duration: timeline.duration, voiceWavs: voiced.slice(0, 8).map((l) => join(pub, l.src)), log});
  for (const sc of timeline.scenes) if (sc.transitionIn) log(`transition: into ${sc.id} by ${sc.transitionIn.name} (${sc.transitionIn.kind === 'app' ? 'app navigation' : 'motion graphic'})`);
  // The poster: the first scene's settled frame (S0's icon, title and line), when its shot names one. Film draws the
  // film's frame 0 as that frame, so a player with no poster image shows the title card until play (Geoff, Oct 12),
  // and out/thumbnail.png is the same frame.
  const first = timeline.scenes[0], thumbAt = shots[first.id]?.thumbnail;
  const posterFrame = thumbAt === undefined ? undefined : Math.round((first.start + (thumbAt < 0 ? (first.exit?.at ?? first.duration) + thumbAt : thumbAt)) * timeline.fps);
  if (posterFrame !== undefined) first.poster = +(posterFrame / timeline.fps - first.start).toFixed(6);
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
  // A one-scene preview (--scene) makes no stills.
  for (const s of args.has('--scene') ? [] : timeline.scenes) {
    remotion('still', 'src/index.ts', 'Intro', join(out, `still-${s.id}.png`), `--frame=${Math.round(stillAt(s) * timeline.fps)}`);
  }
  // The thumbnail: the poster frame (above), also the video's cover art (pipeline/render.mjs).
  if (posterFrame !== undefined && !args.has('--scene')) {
    remotion('still', 'src/index.ts', 'Intro', join(out, 'thumbnail.png'), `--frame=${posterFrame}`);
    log('thumbnail: out/thumbnail.png');
  }
  const n = timeline.scenes.length;
  if (!args.has('--scene')) spawnSync('/bin/sh', ['-c', `ffmpeg -v error -y ${timeline.scenes.map((s) => `-i "${join(out, `still-${s.id}.png`)}"`).join(' ')} ` +
    `-filter_complex "${timeline.scenes.map((_, i) => `[${i}]scale=640:360,setsar=1[s${i}]`).join(';')};${timeline.scenes.map((_, i) => `[s${i}]`).join('')}concat=n=${n}:v=1:a=0,tile=4x${Math.ceil(n / 4)}:padding=6" -frames:v 1 "${join(out, 'stills.png')}"`]);

  // 8. Render: a scene at a time, from the cache where a scene is unchanged (pipeline/render.mjs); `--scene S7` renders
  // just that scene to out/scene-S7.mp4, for a quick look. `--whole` renders the film in one pass, as before V2.
  const scale = args.has('--draft') ? 0.5 : 1;
  const sceneArg = argv[argv.indexOf('--scene') + 1];
  let rendered = [];
  if (args.has('--scene')) {
    if (!sceneArg || sceneArg.startsWith('--')) throw new BuildError('render: --scene needs a scene id, e.g. --scene S7');
    renderFilm({here, pub, out, cache, timeline, scale, only: sceneArg.split(','), log});
  } else if (!args.has('--stills')) {
    let mp4;
    if (args.has('--whole')) {
      mp4 = join(out, scale !== 1 ? 'intro-draft.mp4' : 'intro.mp4');
      if (remotion('render', 'src/index.ts', 'Intro', mp4, ...(scale !== 1 ? [`--scale=${scale}`] : [])).status !== 0) throw new BuildError('render');
      // Loudness: the voice comes out of the TTS near -28 LUFS; the film's soundtrack is brought to -16 LUFS
      // (peaks under -1.5 dBTP), the level web video plays at, with the picture copied untouched.
      const loud = join(out, 'intro.loud.mp4');
      const thumb = join(out, 'thumbnail.png'), art = existsSync(thumb) ? ['-i', thumb, '-map', '0:v', '-map', '0:a', '-map', '1:v', '-c:v:1', 'png', '-disposition:v:1', 'attached_pic'] : [];
      if (spawnSync('ffmpeg', ['-v', 'error', '-y', '-i', mp4, ...art, '-c:v:0', 'copy', '-af', 'loudnorm=I=-16:TP=-1.5:LRA=11', '-c:a', 'aac', '-b:a', '256k', '-ar', '48000', loud]).status === 0) {
        copyFileSync(loud, mp4);
        log('render: soundtrack at -16 LUFS');
      }
      rendered = timeline.scenes.map((s) => s.id);
    } else ({mp4, rendered} = renderFilm({here, pub, out, cache, timeline, scale, cover: join(out, 'thumbnail.png'), log}));
    // The poster check: the film's first frame must be the title card (Geoff, Oct 12: the still a player shows before
    // play is the icon, title and line), the same picture as out/thumbnail.png.
    const thumb = join(out, 'thumbnail.png');
    if (existsSync(thumb) && scale === 1) {
      const r = spawnSync('ffmpeg', ['-v', 'info', '-i', mp4, '-i', thumb, '-lavfi', '[0:v]trim=end_frame=1[a];[1:v]format=yuv420p[b];[a][b]psnr', '-f', 'null', '-'], {encoding: 'utf8'});
      const db = +(r.stderr.match(/PSNR .*average:([0-9.]+|inf)/)?.[1]?.replace('inf', '99') ?? 0);
      if (db < 35) throw new BuildError(`poster: the film's first frame isn't the title card (${db.toFixed(1)} dB against out/thumbnail.png); Film.tsx draws frame 0 at the first scene's poster time`);
      log(`poster: frame 0 is the title card (${db >= 99 ? 'identical' : `${db.toFixed(1)} dB`} against out/thumbnail.png), and the file's cover art`);
    }
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
  // What Geoff reviews (out/review.json): each scene's place, its still, what its Shot: note asks for and when each is
  // on screen, and, for the scenes this build re-rendered, a 480p clip, so a cut is reviewed by what changed.
  const clips = rendered.length && scale === 1 && !args.has('--scene') ? reviewClips({out, timeline, rendered}) : {};
  const at = (sc, ref) => {
    if (ref.startsWith('#')) return sc.app?.beatAt?.[ref.slice(1)];
    if (ref.startsWith('event:')) return sc.drawn?.events?.[ref.slice(6)];
    if (ref.startsWith('state:')) return sc.app?.steps.find((st) => st.state === ref.slice(6))?.at;
    if (ref === 'transition') return 0;
    return undefined;
  };
  writeFileSync(join(out, 'review.json'), JSON.stringify({duration: timeline.duration, scenes: timeline.scenes.map((sc) => ({
    id: sc.id, title: sc.title, topic: sc.topic, start: fmt(sc.start), end: fmt(sc.start + sc.duration), still: `still-${sc.id}.png`,
    rerendered: rendered.includes(sc.id), clip: clips[sc.id] ?? null,
    requires: (shots[sc.id]?.requires ?? []).map((r) => ({what: r.what, built: r.built !== false,
      at: [...new Set((r.by ?? []).map((ref) => at(sc, ref)).filter((t) => t !== undefined).map((t) => fmt(sc.start + t)))]})),
  }))}, null, 1));
  if (args.has('--gc')) gcCache({cache, liveCaptureKeys: new Set(Object.values(captures).map((c) => c.key)),
    liveRenderKeys: new Set([...[1, 0.5].flatMap((sc) => sceneKeys({here, pub, timeline, scale: sc}).map((k) => k.key)),
      `audio-${soundtrackKey({here, pub, timeline, from: 0, to: timeline.frames - 1})}`]), log});
  const table = timeline.scenes.map((s) => `| ${s.id} | ${s.title} | ${fmt(s.start)} | ${s.duration.toFixed(1)} s | ${s.kind}${s.card?.standIn ? ' (stand-in)' : ''} |`).join('\n');
  const staleMd = anchors.stale.length ? `## Stale framing\n\nThe app moved under these rects; they are framed as before until fixed:\n\n${anchors.stale.map((m) => `- ${m}`).join('\n')}\n\n` : '';
  const gaps = missing.length ? `## Not built yet\n\nThe script asks for these and this cut doesn't have them:\n\n${missing.map((m) => `- ${m}`).join('\n')}\n\n` : '';
  // The script as built, for the next build's "since the last build".
  writeFileSync(join(cache, 'last-build-script.json'), JSON.stringify(changes.now, null, 1));
  writeFileSync(join(out, 'report.md'), `# Intro video build\n\n${staleMd}${gaps}${report.map((l) => `- ${l}`).join('\n')}\n\n| Scene | Title | Starts | Length | Shot |\n|---|---|---|---|---|\n${table}\n`);
} catch (e) {
  if (e instanceof BuildError) { console.error(`BUILD FAILED: ${e.message}`); process.exit(1); }
  throw e;
}
