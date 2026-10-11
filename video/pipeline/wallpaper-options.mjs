// Render the S3 wide shot once per wallpaper option, for choosing one (Q-175). Writes to the dir given.
//   node pipeline/wallpaper-options.mjs <outdir>
// Apple's wallpapers are read from this Mac and never copied into the repo.
import {execFileSync, spawnSync} from 'node:child_process';
import {copyFileSync, existsSync, mkdirSync, readFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const here = join(dirname(fileURLToPath(import.meta.url)), '..');
const outDir = process.argv[2];
mkdirSync(outDir, {recursive: true});
const pub = join(here, 'build/public');
const timeline = JSON.parse(readFileSync(join(pub, 'timeline.json'), 'utf8'));
const s3 = timeline.scenes.find((s) => s.id === 'S3');
const frame = Math.round((s3.start + 1.4) * timeline.fps);
const remotion = (...a) => spawnSync(join(here, 'node_modules/.bin/remotion'), [...a, '--log=error'], {cwd: here, stdio: 'inherit'});
const DP = '/System/Library/Desktop Pictures';
const WP = join(process.env.HOME, 'Library/Caches/duo-video/wallpapers'); // official ones fetched from 512pixels.net, never in the repo
const options = (process.argv[3] ? process.argv.slice(3) : ['27-Golden-Gate.png', '26-Tahoe-Light-6K.png', '26-Tahoe-Dark-6K.png', '26-Tahoe-Beach-Day.png', '26-Tahoe-Beach-Dusk.png', '27-Golden-Gate-Dark.png'])
  .map((f) => [f.replace(/\.(png|jpe?g|heic)$/, ''), {image: f.startsWith('/') ? f : join(WP, f)}]);
const saved = join(outDir, 'wallpaper-saved.png');
copyFileSync(join(pub, 'wallpaper.png'), saved);
for (const [name, o] of options) {
  const wp = join(outDir, `wp-${name}.png`);
  if (o.svg) remotion('still', 'src/index.ts', 'Wallpaper', wp, '--scale=4', `--props=${JSON.stringify({variant: o.svg})}`);
  else {
    if (!existsSync(o.image)) { console.log(`skip ${name}: no ${o.image}`); continue; }
    // Centre-crop the square original to 16:9, then size it to the desk wallpaper's pixels.
    execFileSync('/usr/bin/sips', ['-s', 'format', 'png', o.image, '--out', wp], {stdio: 'ignore'});
    const dims = execFileSync('/usr/bin/sips', ['-g', 'pixelWidth', '-g', 'pixelHeight', wp]).toString();
    const w = +dims.match(/pixelWidth: (\d+)/)[1], h = +dims.match(/pixelHeight: (\d+)/)[1];
    const [cw, ch] = w / h > 16 / 9 ? [Math.round(h * 16 / 9), h] : [w, Math.round(w * 9 / 16)];
    execFileSync('/usr/bin/sips', ['-c', String(ch), String(cw), wp], {stdio: 'ignore'}); // centre crop to 16:9
    execFileSync('/usr/bin/sips', ['-z', '4320', '7680', wp], {stdio: 'ignore'});
  }
  copyFileSync(wp, join(pub, 'wallpaper.png'));
  remotion('still', 'src/index.ts', 'Intro', join(outDir, `opt-${name}.png`), `--frame=${frame}`);
  console.log(`option ${name}`);
}
copyFileSync(saved, join(pub, 'wallpaper.png'));
