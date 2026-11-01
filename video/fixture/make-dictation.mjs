// The 0.2.22 film's dictation (films/release-0-2-22): what's said into the mic, in Geoff's own voice (the film's
// narrator, DL-279: "you should also just use my own geoff voice model for the transcription demo"). Each phrase is
// voiced and speech-checked by the pipeline's voice step, then joined with the pause a person leaves between phrases.
// The app hears the result through voice input's own path (VideoTargets+Voice.swift), and the film plays it.
//   node fixture/make-dictation.mjs        (from video/; under the GPU lock)
// Writes fixture/dictation/<id>.wav and dictation.json. Voiced audio may be committed (DL-246); the voice's weights
// and its training audio never are.
import {mkdirSync, writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {voiceLines} from '../pipeline/voice.mjs';
import {filmPaths, filmStyle} from '../pipeline/film.mjs';

const here = join(dirname(fileURLToPath(import.meta.url)), '..');
const TAKES = {
  // Something ordinary (Geoff, Nov 1: "the demo transcription is strange; please just use something benign").
  chat: ['Please update the PRD with the latest changes to the UI design.'],
  terminal: ['Can you add the new design to the release notes too?'],
};
const PAUSE = 0.7, LEAD = 0.4, TAIL = 1.2;   // seconds: between phrases, before the first, after the last
const paths = filmPaths(here, 'release-0-2-22');
const lines = Object.entries(TAKES).flatMap(([k, ps]) => ps.map((t, i) => ({id: `dictation-${k}-${i}`, text: t, said: t})));
const voiced = voiceLines(lines, {here, style: filmStyle(here, paths), cache: join(here, '.cache'), pub: paths.pub, log: console.log});
const out = join(here, 'fixture/dictation');
mkdirSync(out, {recursive: true});
const meta = {};
for (const [k, ps] of Object.entries(TAKES)) {
  const files = ps.map((_, i) => join(paths.pub, voiced.find((v) => v.id === `dictation-${k}-${i}`).src));
  // silence, phrase, pause, phrase, silence: one mono 48 kHz file
  const parts = [`aevalsrc=0:d=${LEAD}`, ...files.flatMap((_, i) => i < files.length - 1 ? [`[${i}:a]`, `aevalsrc=0:d=${PAUSE}`] : [`[${i}:a]`]), `aevalsrc=0:d=${TAIL}`];
  let filter = '', inputs = [], n = 0;
  const labels = parts.map((p) => { if (p.startsWith('[')) return p; filter += `${p}:s=48000[s${n}];`; return `[s${n++}]`; });
  filter += `${labels.map((l) => l).join('')}concat=n=${labels.length}:v=0:a=1,aresample=48000,aformat=channel_layouts=mono[out]`;
  for (const f of files) inputs.push('-i', f);
  const r = spawnSync('ffmpeg', ['-v', 'error', '-y', ...inputs, '-filter_complex', filter, '-map', '[out]', '-c:a', 'pcm_s16le', join(out, `${k}.wav`)], {stdio: 'inherit'});
  if (r.status !== 0) throw new Error(`ffmpeg failed for ${k}`);
  const d = spawnSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', join(out, `${k}.wav`)]).stdout.toString().trim();
  meta[k] = {phrases: ps, text: ps.join(' '), duration_s: +(+d).toFixed(3), voice: "Geoff's (geoff-voxcpm2-v2)"};
}
writeFileSync(join(out, 'dictation.json'), JSON.stringify(meta, null, 1) + '\n');
console.log(JSON.stringify(meta, null, 1));
