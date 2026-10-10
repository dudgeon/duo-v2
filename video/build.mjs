#!/usr/bin/env node
// The intro video's build (DL-169). Milestone 0: one voiced line, one 4x capture with a push-in, rendered.
// Every product is content-addressed in .cache/, so an unchanged line is never re-voiced and an
// unchanged app and spec are never recaptured. Usage: node build.mjs [--force-capture] [--force-voice]
import {createHash} from 'node:crypto';
import {execFileSync, spawnSync} from 'node:child_process';
import {copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, '..');
const cache = join(here, '.cache');
const pub = join(here, 'build/public');
const out = join(here, 'out');
const args = new Set(process.argv.slice(2));
const report = [];
const log = (s) => { console.log(s); report.push(s); };
const fail = (s) => { console.error(`BUILD FAILED: ${s}`); process.exit(1); };
for (const d of [cache, pub, out, join(cache, 'voice'), join(cache, 'capture'), join(pub, 'voice'), join(pub, 'capture')]) mkdirSync(d, {recursive: true});

const sha = (...parts) => {
  const h = createHash('sha256');
  for (const p of parts) h.update(typeof p === 'string' ? p : JSON.stringify(p)).update('\0');
  return h.digest('hex').slice(0, 16);
};
const fileSha = (p) => createHash('sha256').update(readFileSync(p)).digest('hex').slice(0, 16);

// ---- The M0 spec (M1 moves this into script.md + shots.json) ----
const spec = {
  line: {id: 'M0-1', text: 'Each project keeps its sessions, its documents, and what needs you, together.'},
  title: {text: 'Duo v2', sub: 'Claude Code, around your projects'},
  capture: {state: 'project', scale: 4, windowWidthPt: 1440},
  // Points in the window capture (frame and toolbar included). The camera starts on the whole desk
  // (wallpaper and window) and lands on the Needs you rows. M1 replaces these numbers with anchors (H2).
  target: {x: 0, y: 79, w: 480, h: 270},
};
const style = JSON.parse(readFileSync(join(here, 'style/tokens.json'), 'utf8'));

// ---- 1. Voice ----
const voiceDir = join(here, 'voice');
const voice = JSON.parse(readFileSync(join(voiceDir, 'house/voice.json'), 'utf8'));
const voiceKey = sha(spec.line.text, voice, fileSha(join(voiceDir, voice.ref_wav)),
  readFileSync(join(voiceDir, 'models.lock.json'), 'utf8'), readFileSync(join(voiceDir, 'requirements.txt'), 'utf8'),
  readFileSync(join(voiceDir, 'tts.py'), 'utf8'));
const vWav = join(cache, 'voice', `${voiceKey}.wav`);
if (!existsSync(vWav) || args.has('--force-voice')) {
  const job = join(cache, 'voice', `${voiceKey}.job.json`);
  const jobOut = join(cache, 'voice', voiceKey);
  writeFileSync(job, JSON.stringify({lines: [spec.line], voice: {...voice, ref_wav: join(voiceDir, voice.ref_wav)}, out_dir: jobOut}));
  const py = join(voiceDir, '.venv/bin/python');
  const run = (script, ...a) => spawnSync(py, ['-I', join(voiceDir, script), ...a], {cwd: voiceDir, stdio: 'inherit'});
  if (run('tts.py', job).status !== 0) fail('voice: tts.py failed');
  if (run('asr_check.py', jobOut, spec.line.id).status !== 0) fail(`voice: ${spec.line.id} failed the speech check (see ${jobOut}/${spec.line.id}.asr.json)`);
  copyFileSync(join(jobOut, `${spec.line.id}.wav`), vWav);
  copyFileSync(join(jobOut, `${spec.line.id}.asr.json`), vWav.replace('.wav', '.asr.json'));
  log(`voice: ${spec.line.id} voiced (${voiceKey})`);
} else log(`voice: ${spec.line.id} unchanged, from cache (${voiceKey})`);
const asr = JSON.parse(readFileSync(vWav.replace('.wav', '.asr.json'), 'utf8'));
copyFileSync(vWav, join(pub, 'voice', `${spec.line.id}.wav`));
log(`voice: heard "${asr.heard}" (WER ${asr.wer}, ${asr.words_per_sec} words/s, ${asr.duration_s}s)`);

// ---- 2. Capture (fixture state, isolated support folder, background launch: F-227, F-113) ----
const app = join(repo, 'build/Duo.app');
const bin = join(app, 'Contents/MacOS/Duo');
if (!existsSync(bin)) fail(`capture: no app at ${app}; run scripts/bundle.sh`);
const fixture = join(app, 'Contents/Resources');
const captureKey = sha('window', fileSha(bin), spec.capture,
  execFileSync('/bin/sh', ['-c', `find "${fixture}" -name '*.json' -type f | sort | xargs shasum`]).toString());
const cPng = join(cache, 'capture', `${captureKey}.png`);
if (!existsSync(cPng) || args.has('--force-capture')) {
  const support = mkdtempSync('/tmp/dvid.');
  const env = {...process.env, DUO_SUPPORT_DIR: support};
  for (const k of ['DUO_SOCKET', 'DUO_TOKEN']) delete env[k];
  const r = spawnSync('/usr/bin/open', ['-g', '-W', '-n', app, '--args', '--state', spec.capture.state,
    '--capture-scale', String(spec.capture.scale), '--capture-window', cPng], {env, timeout: 60000});
  rmSync(support, {recursive: true, force: true});
  if (r.status !== 0 || !existsSync(cPng)) fail(`capture: ${spec.capture.state} produced no PNG`);
  log(`capture: ${spec.capture.state} at ${spec.capture.scale}x (${captureKey})`);
} else log(`capture: ${spec.capture.state} unchanged, from cache (${captureKey})`);
const dims = execFileSync('/usr/bin/sips', ['-g', 'pixelWidth', '-g', 'pixelHeight', cPng]).toString();
const pw = +dims.match(/pixelWidth: (\d+)/)[1], ph = +dims.match(/pixelHeight: (\d+)/)[1];
const widthPt = pw / spec.capture.scale, heightPt = ph / spec.capture.scale;
if (widthPt !== spec.capture.windowWidthPt) fail(`capture: ${pw}px wide is not ${spec.capture.scale}x the ${spec.capture.windowWidthPt}-pt window; the capture scale was not applied`);
copyFileSync(cPng, join(pub, 'capture', `${spec.capture.state}.png`));

// ---- 3. Timeline (voice timing is the beat map) ----
const titleUntil = 2.0;
const appear = {start: titleUntil - 0.3, end: titleUntil + 0.5};
const vStart = appear.end + style.voice.leadIn;
const moveStart = vStart + 0.6, moveEnd = moveStart + 2.4; // the push-in lands before "what needs you"
const duration = Math.max(vStart + asr.duration_s + 1.6, moveEnd + style.camera.hold + 1);
const aspect = style.frame.width / style.frame.height;
const deskW = Math.round(widthPt / style.desk.windowWidthShare), deskH = Math.round(deskW / aspect);
const desk = {deskW, deskH, winX: (deskW - widthPt) / 2, winY: (deskH - heightPt) / 2, winW: widthPt, winH: heightPt};
const wide = {x: 0, y: 0, w: deskW, h: deskH};
const target = {...spec.target, x: spec.target.x + desk.winX, y: spec.target.y + desk.winY};
const timeline = {
  duration: +duration.toFixed(3),
  title: {...spec.title, until: titleUntil},
  capture: {src: `capture/${spec.capture.state}.png`, scale: spec.capture.scale},
  desk, appear,
  camera: [{t: 0, rect: wide}, {t: moveStart, rect: wide}, {t: moveEnd, rect: target}],
  voice: {src: `voice/${spec.line.id}.wav`, start: vStart, duration: asr.duration_s},
};
// Fail before rendering if any camera rect would magnify the capture past 1:1 at the output size.
for (const k of timeline.camera) {
  const mag = style.frame.width / k.rect.w / spec.capture.scale;
  if (mag > style.camera.maxMagnification + 1e-9) fail(`zoom: rect ${JSON.stringify(k.rect)} magnifies ${mag.toFixed(2)}x past the capture`);
}
writeFileSync(join(pub, 'timeline.json'), JSON.stringify(timeline, null, 2));
log(`timeline: ${timeline.duration}s; deepest zoom ${(style.frame.width / target.w / spec.capture.scale).toFixed(2)} output px per capture px`);

// ---- 4. Lint: nothing in the scenes may run on a wall clock ----
const lint = spawnSync('node', [join(here, 'lint.mjs')], {stdio: 'inherit'});
if (lint.status !== 0) fail('lint');

// ---- 5. Render ----
const mp4 = join(out, 'm0.mp4');
const rr = spawnSync(join(here, 'node_modules/.bin/remotion'), ['render', 'src/index.ts', 'M0', mp4, '--log=error'], {cwd: here, stdio: 'inherit'});
if (rr.status !== 0) fail('render');
for (const [name, t] of [['title', 1.0], ['wide', moveStart - 0.1], ['mid', (moveStart + moveEnd) / 2], ['landed', moveEnd + 0.5]]) {
  spawnSync(join(here, 'node_modules/.bin/remotion'), ['still', 'src/index.ts', 'M0', join(out, `m0-${name}.png`),
    `--frame=${Math.round(t * style.frame.fps)}`, '--log=error'], {cwd: here, stdio: 'inherit'});
}
log(`render: ${mp4}`);
writeFileSync(join(out, 'm0-report.md'), `# M0 build\n\n${report.map((l) => `- ${l}`).join('\n')}\n`);
