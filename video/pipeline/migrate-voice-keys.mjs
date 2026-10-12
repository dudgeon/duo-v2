#!/usr/bin/env node
// One-time re-key of the voice cache (DL-175). Lines were keyed by the whole voice file, absolute paths and all, so moving the
// voice to geoff-voice would have re-voiced the film; keys are now made of what the voice is (pipeline/voice.mjs). This copies
// each cached line from its old key to its new one, so nothing is re-voiced. The audio is the same only if geoff-voice speaks
// the same voice: check that first (geoff-voice README, "Same voice").
//   node pipeline/migrate-voice-keys.mjs <the old voice file, e.g. ~/Library/Caches/duo-video/voices/voxcpm-lora100.json>
//   --dry   only count
import {copyFileSync, existsSync, readFileSync} from 'node:fs';
import {dirname, isAbsolute, join, resolve} from 'node:path';
import {homedir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {parseScript, said} from './script.mjs';
import {fileSha, sha} from './util.mjs';
import {voiceSetup} from './voice.mjs';

const here = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const [oldFile, ...flags] = process.argv.slice(2);
if (!oldFile) { console.error('usage: node pipeline/migrate-voice-keys.mjs <old voice file> [--dry]'); process.exit(2); }
const old = JSON.parse(readFileSync(oldFile.replace(/^~/, homedir()), 'utf8'));
if (old.engine !== 'voxcpm') { console.error('migrate: only a voxcpm voice file has path-based keys to convert'); process.exit(2); }

// The old formula, as it was: the whole voice file, then the reference clip, the runner script and the LoRA weights.
const refWav = isAbsolute(old.ref_wav) ? old.ref_wav : join(here, 'voice', old.ref_wav);
const oldSetup = sha(old, fileSha(refWav), fileSha(join(old.root, old.script)), ...(old.lora ? [fileSha(join(old.root, old.lora, 'lora_weights.safetensors'))] : []));
const oldOwn = (t) => Object.entries(old.said ?? {}).reduce((s, [w, x]) => s.split(w).join(x), t);

const {scenes, lexicon} = parseScript(readFileSync(join(here, 'script.md'), 'utf8'));
const lines = scenes.flatMap((s) => s.lines.map((l) => ({...l, said: said(l.text, lexicon)})));
const next = voiceSetup({here}).keyed(lines);
const vc = join(here, '.cache/voice');
let copied = 0, had = 0, absent = 0;
next.forEach((l, i) => {
  const from = sha(oldOwn(lines[i].said), oldSetup);
  if (existsSync(join(vc, `${l.key}.asr.json`))) { had++; return; }
  if (!existsSync(join(vc, `${from}.asr.json`))) { absent++; return; }
  if (!flags.includes('--dry')) for (const ext of ['wav', 'asr.json']) copyFileSync(join(vc, `${from}.${ext}`), join(vc, `${l.key}.${ext}`));
  copied++;
});
console.log(`migrate: ${lines.length} lines: ${copied} ${flags.includes('--dry') ? 'would be ' : ''}copied to their new key, ${had} already there, ${absent} not in the cache under the old key (they will be voiced)`);
