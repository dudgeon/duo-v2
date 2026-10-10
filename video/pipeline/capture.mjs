// Capture fixture states: the window at N x with its anchors, in the background with a throwaway
// support folder (F-227, F-113). Recaptured only when the app, its fixtures or the spec change.
import {execFileSync, spawnSync} from 'node:child_process';
import {copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {BuildError, fileSha, sha} from './util.mjs';

export function captureStates(states, {repo, cache, pub, scale, fixture, force = false, log}) {
  const app = join(repo, 'build/Duo.app');
  const bin = join(app, 'Contents/MacOS/Duo');
  if (!existsSync(bin)) throw new BuildError(`capture: no app at ${app}; run scripts/bundle.sh`);
  const appKey = sha(fileSha(bin), execFileSync('/bin/sh', ['-c',
    `find "${join(app, 'Contents/Resources')}" -type f \\( -name '*.json' -o -name '*.html' -o -name '*.md' \\) | sort | xargs shasum`]).toString());
  const cc = join(cache, 'capture');
  mkdirSync(cc, {recursive: true});
  mkdirSync(join(pub, 'capture'), {recursive: true});
  const out = {};
  let taken = 0;
  for (const state of states) {
    // The video's demo fixture (H3): the design fixture plus real document text. It's part of the key.
    const fx = fixture ? join(repo, fixture) : null;
    const fxKey = fx ? execFileSync('/bin/sh', ['-c', `shasum "${dirname(fx)}"/*`]).toString() : '';
    const key = sha('window+anchors', appKey, state, scale, fxKey);
    const png = join(cc, `${key}.png`), anchors = join(cc, `${key}.anchors.json`);
    if (force || !existsSync(png)) {
      const support = mkdtempSync('/tmp/dvid.');
      // open(1) doesn't hand its own environment to the app: pass the support folder with --env.
      const env = {...process.env};
      for (const k of ['DUO_SOCKET', 'DUO_TOKEN', 'DUO_SUPPORT_DIR']) delete env[k];
      const r = spawnSync('/usr/bin/open', ['-g', '-W', '-n', '--env', `DUO_SUPPORT_DIR=${support}`, app, '--args', '--state', state,
        '--capture-scale', String(scale), ...(fx ? ['--fixture', fx] : []), '--then', `anchors:${anchors}`, '--capture-window', png], {env, timeout: 90000});
      rmSync(support, {recursive: true, force: true});
      if (r.status !== 0 || !existsSync(png)) throw new BuildError(`capture: ${state} produced no PNG (is it a fixture state?)`);
      taken++;
    }
    const dims = execFileSync('/usr/bin/sips', ['-g', 'pixelWidth', '-g', 'pixelHeight', png]).toString();
    const pw = +dims.match(/pixelWidth: (\d+)/)[1], ph = +dims.match(/pixelHeight: (\d+)/)[1];
    copyFileSync(png, join(pub, 'capture', `${state}.png`));
    out[state] = {src: `capture/${state}.png`, png, widthPt: pw / scale, heightPt: ph / scale,
      anchors: existsSync(anchors) ? JSON.parse(readFileSync(anchors, 'utf8')) : null, key};
  }
  log(`capture: ${states.length} states, ${taken} captured, ${states.length - taken} from cache`);
  return out;
}
