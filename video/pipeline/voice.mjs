// Voice every line, re-voicing only lines whose spoken text or voice setup changed.
// One tts.py run (one model load) voices all the missing lines; each is then checked by speech recognition.
import {spawnSync} from 'node:child_process';
import {copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {BuildError, fileSha, sha} from './util.mjs';

export function voiceLines(lines, {here, cache, pub, style, force = false, log}) {
  const dir = join(here, 'voice');
  const voice = JSON.parse(readFileSync(join(dir, 'house/voice.json'), 'utf8'));
  const setup = sha(voice, fileSha(join(dir, voice.ref_wav)), ...['models.lock.json', 'requirements.txt', 'tts.py']
    .map((f) => readFileSync(join(dir, f), 'utf8')));
  const vc = join(cache, 'voice');
  mkdirSync(vc, {recursive: true});
  mkdirSync(join(pub, 'voice'), {recursive: true});
  const keyed = lines.map((l) => ({...l, key: sha(l.said, setup)}));
  const missing = keyed.filter((l) => force || !existsSync(join(vc, `${l.key}.asr.json`)));
  const py = join(dir, '.venv/bin/python');
  const run = (script, ...a) => spawnSync(py, ['-I', join(dir, script), ...a], {cwd: dir, stdio: ['ignore', 'ignore', 'inherit'], env: {...process.env, DUO_MAX_WPS: String(style.voice.maxWps)}});
  // A line that fails the speech check is re-rolled with the next seed, up to RETRIES times; the
  // passing seed is kept with the line (its .asr.json), so the build stays reproducible.
  const RETRIES = 3, {maxWps: MAX_WPS, targetWps: TARGET_WPS, maxStretch: MAX_STRETCH} = style.voice;
  const onlyTooFast = (a) => a.fail_reasons.length === 1 && a.words_per_sec > MAX_WPS && a.words_per_sec <= MAX_WPS * MAX_STRETCH;
  let todo = missing, failures = [];
  for (let attempt = 0; todo.length && attempt <= RETRIES; attempt++) {
    const seed = voice.seed + attempt;
    const jobKey = sha(todo.map((l) => l.key), seed);
    const out = join(vc, `job-${jobKey}`);
    const job = join(vc, `job-${jobKey}.json`);
    writeFileSync(job, JSON.stringify({lines: todo.map((l) => ({id: l.key, text: l.said, expect: l.text, seed})),
      voice: {...voice, ref_wav: join(dir, voice.ref_wav)}, out_dir: out}));
    if (run('tts.py', job).status !== 0) throw new BuildError('voice: tts.py failed');
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
