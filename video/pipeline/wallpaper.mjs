// The desk wallpaper, as a PNG at the capture scale (build/public/wallpaper.png).
// desk.wallpaper.image names an official Apple wallpaper (Geoff chose High Sierra, 2026-10-10; Q-175).
// Apple's files are fetched into ~/Library/Caches/duo-video/wallpapers and never committed.
// Without an image, the SVG look-alike is rendered instead.
import {execFileSync, spawnSync} from 'node:child_process';
import {copyFileSync, existsSync, mkdirSync} from 'node:fs';
import {join} from 'node:path';
import {BuildError, fileSha, sha} from './util.mjs';

export const WALLPAPER_DIR = join(process.env.HOME, 'Library/Caches/duo-video/wallpapers');

/** Centre-crop any image to 16:9 and size it to w x h pixels. */
export function fitImage(src, out, w, h) {
  execFileSync('/usr/bin/sips', ['-s', 'format', 'png', src, '--out', out], {stdio: 'ignore'});
  const dims = execFileSync('/usr/bin/sips', ['-g', 'pixelWidth', '-g', 'pixelHeight', out]).toString();
  const iw = +dims.match(/pixelWidth: (\d+)/)[1], ih = +dims.match(/pixelHeight: (\d+)/)[1];
  const [cw, ch] = iw / ih > w / h ? [Math.round(ih * w / h), ih] : [iw, Math.round(iw * h / w)];
  execFileSync('/usr/bin/sips', ['-c', String(ch), String(cw), out], {stdio: 'ignore'});
  execFileSync('/usr/bin/sips', ['-z', String(h), String(w), out], {stdio: 'ignore'});
}

export function prepareWallpaper({style, here, cache, pub, remotion, log}) {
  const wp = style.desk.wallpaper;
  const w = style.frame.width * style.capture.scale, h = style.frame.height * style.capture.scale;
  let out;
  if (wp.image) {
    const src = join(WALLPAPER_DIR, wp.image);
    if (!existsSync(src)) {
      mkdirSync(WALLPAPER_DIR, {recursive: true});
      const r = spawnSync('curl', ['-sSfL', '-o', src, wp.source], {stdio: 'inherit'});
      if (r.status !== 0) throw new BuildError(`wallpaper: ${wp.image} is not in ${WALLPAPER_DIR} and couldn't be fetched from ${wp.source}`);
      log(`wallpaper: fetched ${wp.image}`);
    }
    out = join(cache, `wallpaper-${sha(fileSha(src), w, h)}.png`);
    if (!existsSync(out)) { fitImage(src, out, w, h); log(`wallpaper: ${wp.image} fitted to ${w}x${h}`); }
  } else {
    out = join(cache, `wallpaper-${sha(wp, style.frame, style.capture.scale)}.png`);
    if (!existsSync(out)) {
      if (remotion('still', 'src/index.ts', 'Wallpaper', out, `--scale=${style.capture.scale}`).status !== 0) throw new BuildError('wallpaper');
      log('wallpaper: rendered');
    }
  }
  copyFileSync(out, join(pub, 'wallpaper.png'));
}
