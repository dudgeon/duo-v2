// Voice every line, re-voicing only lines whose spoken text or voice setup changed.
// One tts.py run (one model load) voices all the missing lines; each is then checked by speech recognition.
import {spawnSync} from 'node:child_process';
import {copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {isAbsolute, join} from 'node:path';
import {homedir} from 'node:os';
import {BuildError, fileSha, sha} from './util.mjs';

// The narrator and what keys its lines: shared by the voicing and the check stage (pipeline/check.mjs).
export function voiceSetup({here}) {
  const dir = join(here, 'voice');
  const house = JSON.parse(readFileSync(join(dir, 'house/voice.json'), 'utf8'));
  // A voice kept outside the repo (Geoff's own, DL-169): its file and reference audio never enter duo-v2.
  // A named voice file that isn't there stops the build: falling back would change the narrator, and every
  // timing with it (the two clones' cuts differ by 39 s). DUO_VOICE_JSON=house asks for the house voice.
  // Geoff's voice itself lives in his private repo dudgeon/geoff-voice; GEOFF_VOICE_DIR names its checkout (README, "The voice").
  const env = process.env.DUO_VOICE_JSON, gv = process.env.GEOFF_VOICE_DIR;
  const ext = env === 'house' ? '' : (env ?? house.external ?? '').replace(/^~/, homedir());
  const hasCard = ext && existsSync(ext);
  if (ext && !hasCard && !(gv && !env)) throw new BuildError(`voice: ${env ? 'DUO_VOICE_JSON' : 'voice.json external'} names ${ext}, which isn't there. Fix the path, point GEOFF_VOICE_DIR at a geoff-voice checkout, or set DUO_VOICE_JSON=house for the house voice.`);
  const card = hasCard ? JSON.parse(readFileSync(ext, 'utf8')) : null;
  // GEOFF_VOICE_DIR alone is enough: Duo's own choices for the voice (which voice folder, seed, tempo, spellings) are `house.geoff`.
  const vox = env !== 'house' && (card ? card.engine === 'voxcpm' : !!gv);
  const voice = vox ? geoffVoice({house, card: card ?? {}, ext, gv}) : (card ?? house);
  const refWav = isAbsolute(voice.ref_wav) ? voice.ref_wav : join(dir, voice.ref_wav);
  if (!existsSync(refWav)) throw new BuildError(`voice: the reference audio ${refWav} isn't there`);
  // `engine: "voxcpm"` (DL-173): VoxCPM2 with a LoRA, run from the geoff-voice checkout (its own venv and speak script);
  // nothing of it enters duo-v2. A line's key is made of what the voice IS (LoRA, runner script, reference clip and its text,
  // seed, tempo, spellings), never of where it is kept: moving or re-cloning the checkout re-voices nothing.
  // (The other engines hash their voice file, minus its notes.)
  const {$note, history, external, ...keyable} = voice;
  const setup = vox ? sha('voxcpm', fileSha(join(voice.root, voice.lora, 'lora_weights.safetensors')), fileSha(join(voice.root, voice.script)), fileSha(refWav),
    voice.ref_text, voice.seed, voice.tempo ?? 1, voice.said ?? {})
    : sha(keyable, fileSha(refWav), ...['models.lock.json', 'requirements.txt', 'tts.py'].map((f) => readFileSync(join(dir, f), 'utf8')));
  // A voice's own spellings (`said` in its file, {written: said}), for words only that voice gets wrong; the script's
  // table stays the same for every voice. The speech check still expects the written line.
  const own = (t) => Object.entries(voice.said ?? {}).reduce((s, [w, x]) => s.split(w).join(x), t);
  const keyed = (lines) => lines.map((l) => ({...l, said: own(l.said), key: sha(own(l.said), setup)}));
  return {dir, house, ext: vox && !card ? `GEOFF_VOICE_DIR ${voice.root}` : ext, voice, refWav, vox, setup, keyed};
}

// Geoff's voice as geoff-voice describes it (voices/<name>/voice.json), with Duo's choices on top: `house.geoff`, then the
// machine-local card. Returns what voiceLines uses: `python`, `script` and `lora` relative to `root`, an absolute `ref_wav`.
function geoffVoice({house, card, ext, gv}) {
  const spec = {...house.geoff, ...card};
  const root = (gv || spec.root || '').replace(/^~/, homedir());
  const where = gv ? 'GEOFF_VOICE_DIR' : `root in ${ext}`;
  const way = 'Clone dudgeon/geoff-voice and run its setup.sh, or set DUO_VOICE_JSON=house for the house voice.';
  if (!root) throw new BuildError(`voice: Geoff's voice needs a geoff-voice checkout: set GEOFF_VOICE_DIR (or "root" in ${ext}). ${way}`);
  const vfile = join(root, spec.voice, 'voice.json');
  if (!existsSync(vfile)) throw new BuildError(`voice: geoff-voice isn't at ${root} (${where}): no ${join(spec.voice, 'voice.json')} there. ${way}`);
  const python = spec.python ?? '.venv/bin/python', script = spec.script ?? 'geoff_voice/speak.py';
  for (const [what, f] of [['venv python', join(root, python)], ['speak script', join(root, script)]])
    if (!existsSync(f)) throw new BuildError(`voice: the geoff-voice ${what} ${f} isn't there. Run ${join(root, 'setup.sh')}.`);
  const v = JSON.parse(readFileSync(vfile, 'utf8')), vdir = join(root, spec.voice);
  const lora = join(spec.voice, v.lora ?? '.');
  if (!existsSync(join(root, lora, 'lora_weights.safetensors'))) throw new BuildError(`voice: the LoRA ${join(root, lora, 'lora_weights.safetensors')} isn't there`);
  const ref_text = v.ref_text ?? readFileSync(join(vdir, v.ref_text_file), 'utf8').trim();
  return {engine: 'voxcpm', root, python, script, lora, ref_wav: join(vdir, v.ref_wav), ref_text, seed: spec.seed ?? v.seed ?? 0, tempo: spec.tempo ?? v.tempo ?? 1, said: spec.said ?? {}};
}

export function voiceLines(lines, {here, cache, pub, style, force = false, log}) {
  const {dir, house, ext, voice, refWav, vox, keyed: keyLines} = voiceSetup({here});
  log(`voice: ${voice === house ? 'house voice' : `external voice (${ext})`}, tempo ${voice.tempo ?? 1}`);
  const vc = join(cache, 'voice');
  mkdirSync(vc, {recursive: true});
  mkdirSync(join(pub, 'voice'), {recursive: true});
  const keyed = keyLines(lines);
  const missing = keyed.filter((l) => force || !existsSync(join(vc, `${l.key}.asr.json`)));
  const py = join(dir, '.venv/bin/python');
  const run = (script, ...a) => spawnSync(py, ['-I', join(dir, script), ...a], {cwd: dir, stdio: ['ignore', 'ignore', 'inherit'], env: {...process.env, DUO_MAX_WPS: String(style.voice.maxWps)}});
  // A line that fails the speech check is re-rolled with the next seed, up to RETRIES times; the
  // passing seed is kept with the line (its .asr.json), so the build stays reproducible.
  const RETRIES = +(process.env.DUO_VOICE_RETRIES ?? 3), {maxWps: MAX_WPS, targetWps: TARGET_WPS, maxStretch: MAX_STRETCH} = style.voice;
  const onlyTooFast = (a) => a.fail_reasons.length === 1 && a.words_per_sec > MAX_WPS && a.words_per_sec <= MAX_WPS * MAX_STRETCH;
  let todo = missing, failures = [];
  for (let attempt = 0; todo.length && attempt <= RETRIES; attempt++) {
    const seed = voice.seed + attempt;
    const jobKey = sha(todo.map((l) => l.key), seed);
    const out = join(vc, `job-${jobKey}`);
    const job = join(vc, `job-${jobKey}.json`);
    writeFileSync(job, JSON.stringify({lines: todo.map((l) => ({id: l.key, text: l.said, expect: l.text, seed})),
      voice: {...voice, ref_wav: refWav}, out_dir: out}));
    if (vox) {
      const linesJson = join(vc, `job-${jobKey}.lines.json`);
      writeFileSync(linesJson, JSON.stringify(todo.map((l) => ({id: l.key, text: l.said}))));
      const r = spawnSync(join(voice.root, voice.python), ['-I', join(voice.root, voice.script), '--ref-wav', refWav, '--ref-text', voice.ref_text,
        '--lines', linesJson, '--out', out, '--seed', String(seed), ...(voice.lora ? ['--lora', join(voice.root, voice.lora)] : [])],
      {cwd: voice.root, stdio: ['ignore', 'ignore', 'inherit']});
      if (r.status !== 0) throw new BuildError('voice: voxcpm failed');
      // The speech check reads each line's <id>.json, as tts.py writes it.
      for (const l of todo) writeFileSync(join(out, `${l.key}.json`), JSON.stringify({id: l.key, text: l.said, expect: l.text, seed}));
    } else if (run('tts.py', job).status !== 0) throw new BuildError('voice: tts.py failed');
    // The house voice's pace (voice.json `tempo`, Geoff 2026-10-11: "even quicker, say 10%"): atempo alone, so
    // the pitch is unchanged; applied before the speech check, which then judges the line at the pace it's heard.
    if (voice.tempo && voice.tempo !== 1) for (const l of todo) {
      const wav = join(out, `${l.key}.wav`), raw = join(out, `${l.key}.raw.wav`);
      copyFileSync(wav, raw);
      if (spawnSync('ffmpeg', ['-v', 'error', '-y', '-i', raw, '-filter:a', `atempo=${voice.tempo}`, wav]).status !== 0) throw new BuildError(`voice: tempo ${voice.tempo} failed on ${l.id}`);
    }
    run('asr_check.py', out, ...todo.map((l) => l.key));
    failures = [];
    for (const l of todo) {
      const asr = JSON.parse(readFileSync(join(out, `${l.key}.asr.json`), 'utf8'));
      if (!asr.passed && onlyTooFast(asr)) {
        // This voice rushes some short lines. Slow such a line toward the target pace, by at most
        // MAX_STRETCH in all (atempo is clean at that size), checking it again after each pass.
        const wav = join(out, `${l.key}.wav`), fast = join(out, `${l.key}.fast.wav`);
        copyFileSync(wav, fast);
        let tempo = 1, again = asr;
        for (let pass = 0; pass < 3 && !again.passed && onlyTooFast(again); pass++) {
          tempo = Math.max(tempo * TARGET_WPS / again.words_per_sec, 1 / MAX_STRETCH);
          spawnSync('ffmpeg', ['-v', 'error', '-y', '-i', fast, '-filter:a', `atempo=${tempo.toFixed(4)}`, wav]);
          run('asr_check.py', out, l.key);
          again = JSON.parse(readFileSync(join(out, `${l.key}.asr.json`), 'utf8'));
        }
        if (again.passed) {
          again.stretched = +tempo.toFixed(4);
          writeFileSync(join(out, `${l.key}.asr.json`), JSON.stringify(again, null, 2));
          log(`voice: ${l.id} slowed to ${again.words_per_sec} words/s (tempo ${tempo.toFixed(3)})`);
          asr.passed = true;
        }
      }
      if (!asr.passed) { failures.push({l, asr}); continue; }
      copyFileSync(join(out, `${l.key}.wav`), join(vc, `${l.key}.wav`));
      copyFileSync(join(out, `${l.key}.asr.json`), join(vc, `${l.key}.asr.json`));
      if (attempt) log(`voice: ${l.id} passed on seed ${seed}`);
    }
    todo = failures.map((f) => f.l);
  }
  if (failures.length) {
    throw new BuildError(`voice: ${failures.length} line(s) failed the speech check after ${RETRIES + 1} seeds:\n` +
      failures.map(({l, asr}) => `  ${l.id} "${l.text}": ${asr.fail_reasons.join('; ')} (heard "${asr.heard}")`).join('\n'));
  }
  log(`voice: ${lines.length} lines, ${missing.length} voiced, ${lines.length - missing.length} from cache`);
  return keyed.map((l) => {
    const asr = JSON.parse(readFileSync(join(vc, `${l.key}.asr.json`), 'utf8'));
    copyFileSync(join(vc, `${l.key}.wav`), join(pub, 'voice', `${l.key}.wav`));
    return {...l, src: `voice/${l.key}.wav`, duration: asr.duration_s, words: asr.words, wer: asr.wer};
  });
}
