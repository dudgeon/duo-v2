// Capture fixture states: the window at N x with its anchors, in the background with a throwaway
// support folder (F-227, F-113). Recaptured only when the app, its fixtures or the spec change.
import {execFileSync, spawnSync} from 'node:child_process';
import {copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {BuildError, fileSha, sha} from './util.mjs';

// cachedOnly (the check stage): never launch the app; null when any state isn't captured yet.
export function captureStates(states, {repo, cache, pub, scale, fixture, force = false, cachedOnly = false, log}) {
  const app = join(repo, 'build/Duo.app');
  const bin = join(app, 'Contents/MacOS/Duo');
  if (!existsSync(bin)) throw new BuildError(`capture: no app at ${app}; run scripts/bundle.sh`);
  // Paths relative to Resources, so the key is the app's content, not where the work tree is (a cache copied to
  // another work tree still hits).
  const appKey = sha(fileSha(bin), execFileSync('/bin/sh', ['-c',
    `cd "${join(app, 'Contents/Resources')}" && find . -type f \\( -name '*.json' -o -name '*.html' -o -name '*.md' \\) | sort | xargs shasum`]).toString());
  const cc = join(cache, 'capture');
  mkdirSync(cc, {recursive: true});
  mkdirSync(join(pub, 'capture'), {recursive: true});
  const out = {};
  let taken = 0;
  // The video's demo fixture (H3): the design fixture plus real document text. It's part of the key.
  const fx = fixture ? join(repo, fixture) : null;
  const fxKey = fx ? execFileSync('/bin/sh', ['-c', `cd "${dirname(fx)}" && find . -type f ! -name '.*' | sort | xargs shasum`]).toString() : '';
  const keyOf = (state) => sha('window+anchors', appKey, state, scale, fxKey);
  if (cachedOnly && states.some((st) => !existsSync(join(cc, `${keyOf(st)}.png`)))) return null;
  for (const state of states) {
    const key = keyOf(state);
    const png = join(cc, `${key}.png`), anchors = join(cc, `${key}.anchors.json`);
    if (force || !existsSync(png)) {
      // One retry: a background launch very occasionally exits without drawing (seen once in a run of five).
      let ok = false;
      for (let attempt = 0; attempt < 2 && !ok; attempt++) {
        const support = mkdtempSync('/tmp/dvid.');
        // open(1) doesn't hand its own environment to the app: pass the support folder with --env. Light always: a capture
        // otherwise follows macOS, which turns dark at sunset on this Mac (F-399).
        const env = {...process.env};
        for (const k of ['DUO_SOCKET', 'DUO_TOKEN', 'DUO_SUPPORT_DIR']) delete env[k];
        // A `-settings-` state is Duo's Settings view, drawn by `render-settings` at 2x (the release films' second window); the
        // main window's capture is only what ends the run.
        const settings = state.includes('-settings-');
        // A `-rec` state records the real app while it works (VideoTargets+Voice.swift `vv-rec`): frames into this folder.
        const recDir = join(cc, `${key}.rec`);
        if (state.includes('-rec')) { rmSync(recDir, {recursive: true, force: true}); env.DUO_VIDEO_REC_DIR = recDir; }
        const then = settings ? `render-settings:${png},wait:3,anchors:${anchors}` : `anchors:${anchors}`;
        const r = spawnSync('/usr/bin/open', ['-g', '-W', '-n', '--env', `DUO_SUPPORT_DIR=${support}`, '--env', 'DUO_APPEARANCE=light', ...(env.DUO_VIDEO_REC_DIR ? ['--env', `DUO_VIDEO_REC_DIR=${recDir}`] : []), app, '--args', '--state', state,
          '--capture-scale', String(scale), ...(fx ? ['--fixture', fx] : []), '--then', then, '--capture-window', settings ? `${png}.window.png` : png], {env, timeout: 90000});
        if (settings) rmSync(`${png}.window.png`, {force: true});
        rmSync(support, {recursive: true, force: true});
        ok = r.status === 0 && existsSync(png);
      }
      if (!ok) throw new BuildError(`capture: ${state} produced no PNG (is it a fixture state?)`);
      if (state.includes('-rec')) recordingToVideo(recDir, join(cc, `${key}.mp4`), state);
      taken++;
    }
    const dims = execFileSync('/usr/bin/sips', ['-g', 'pixelWidth', '-g', 'pixelHeight', png]).toString();
    const pw = +dims.match(/pixelWidth: (\d+)/)[1], ph = +dims.match(/pixelHeight: (\d+)/)[1];
    copyFileSync(png, join(pub, 'capture', `${state}.png`));
    const k = state.includes('-settings-') ? 2 : scale;   // render-settings draws at 2x
    // A recording: its video and where it sits in the window.
    let rec;
    if (state.includes('-rec')) {
      const meta = JSON.parse(readFileSync(join(cc, `${key}.rec`, 'times.json'), 'utf8'));
      copyFileSync(join(cc, `${key}.mp4`), join(pub, 'capture', `${state}.mp4`));
      rec = {src: `capture/${state}.mp4`, region: meta.region, duration: meta.times[meta.times.length - 1]};
    }
    out[state] = {src: `capture/${state}.png`, png, widthPt: pw / k, heightPt: ph / k, ...(rec ? {rec} : {}),
      anchors: existsSync(anchors) ? JSON.parse(readFileSync(anchors, 'utf8')) : null, key};
  }
  log(`capture: ${states.length} states, ${taken} captured, ${states.length - taken} from cache`);
  return out;
}

// A recording's frames as a 30 fps video, each frame held until the next one's time (times.json), so the video runs
// at the pace the app ran: nothing in it is sped up or slowed down.
function recordingToVideo(dir, mp4, state) {
  const meta = JSON.parse(readFileSync(join(dir, 'times.json'), 'utf8'));
  const t = meta.times, list = join(dir, 'frames.txt');
  const lines = t.map((s, i) => `file 'frame-${String(i).padStart(4, '0')}.png'\nduration ${((t[i + 1] ?? s + 1 / meta.fps) - s).toFixed(4)}`);
  writeFileSync(list, lines.join('\n') + `\nfile 'frame-${String(t.length - 1).padStart(4, '0')}.png'\n`);
  const r = spawnSync('ffmpeg', ['-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', list, '-vf', 'fps=30,format=yuv420p', '-c:v', 'libx264', '-crf', '14', '-preset', 'medium', mp4]);
  if (r.status !== 0) throw new BuildError(`capture: ${state}'s recording didn't encode: ${r.stderr}`);
}
