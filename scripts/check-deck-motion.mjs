// The deck's motion (DL-130, F-140): ‹ › scrolls to the slide over `motion.slide`, and the picker's
// outline glides between shapes over `motion.outline`; both at once with Reduce Motion. Web views
// don't run animation frames in a window that isn't on screen (F-102), so this runs the page in
// Chromium, served from a scratch folder with Spikes/PptxViewer/decks/garden.pptx.
//   node scripts/check-deck-motion.mjs
// Needs playwright-core (NODE_PATH) and Playwright's Chromium headless shell, as check-editor-motion.mjs.
import fs from "fs";
import http from "http";
import os from "os";
import path from "path";
import { createRequire } from "module";
const require = createRequire(import.meta.url);
const { chromium } = require("playwright-core");
const repo = process.cwd();
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "duo-deck-"));
for (const f of ["deck.html", "deck.js", "pptx-renderer.js"]) fs.copyFileSync(path.join(repo, "Vendor/pptx-renderer", f), path.join(dir, f));
fs.copyFileSync(path.join(repo, "Spikes/PptxViewer/decks/garden.pptx"), path.join(dir, "deck.pptx"));
// The page's policy names Duo's own scheme; served here, the same rules name this origin.
fs.writeFileSync(path.join(dir, "deck.html"), fs.readFileSync(path.join(dir, "deck.html"), "utf8").replaceAll("duo-deck:", "'self'"));
const types = { ".html": "text/html", ".js": "text/javascript", ".pptx": "application/octet-stream" };
const server = http.createServer((q, r) => {
  const f = path.join(dir, decodeURIComponent(new URL(q.url, "http://x").pathname));
  if (!fs.existsSync(f)) { r.writeHead(404); return r.end(); }
  r.writeHead(200, { "content-type": types[path.extname(f)] || "application/octet-stream" }); fs.createReadStream(f).pipe(r);
}).listen(0);
const port = server.address().port;
const cache = process.env.PLAYWRIGHT_BROWSERS_PATH || process.env.HOME + "/Library/Caches/ms-playwright";
const shell = fs.readdirSync(cache).filter((d) => d.startsWith("chromium_headless_shell-")).sort().pop();
const tokens = "--duo-pane:#FFFFFF;--duo-text:#1F2328;--duo-text2:#5B636D;--duo-selected:#E9ECEF;--duo-rule:#C9CDD3;--duo-ground:#F3F4F6;"
  + "--duo-motion-slide-ms:250;--duo-motion-outline-ms:80;";
const fails = [];
const b = await chromium.launch({ executablePath: `${cache}/${shell}/chrome-headless-shell-mac-arm64/chrome-headless-shell` });
for (const reduce of [false, true]) {
  const label = reduce ? "Reduce Motion" : "motion";
  const page = await b.newPage({ viewport: { width: 460, height: 700 }, reducedMotion: reduce ? "reduce" : "no-preference" });
  page.on("pageerror", (e) => console.log("page error: " + e.message));
  page.on("console", (m) => { if (m.type() === "error") console.log("console: " + m.text()); });
  await page.goto(`http://localhost:${port}/deck.html`);
  await page.evaluate((css) => document.documentElement.setAttribute("style", css), tokens);
  await page.waitForFunction(() => window.__duo, null, { timeout: 8000 });
  const opened = await page.evaluate(() => window.__duo.open("garden.pptx", 1, 1));
  if (!opened.count) { fails.push(`${label}: the deck didn't open (${JSON.stringify(opened)})`); continue; }
  // Scroll position every 25 ms through ‹ › to slide 3.
  const scroll = await page.evaluate(() => new Promise((done) => {
    const out = [[-1, Math.round(scrollY)]], t0 = performance.now();   // where it was, then from the jump on
    window.__duo.go(3);
    const tick = () => { out.push([Math.round(performance.now() - t0), Math.round(scrollY)]); if (performance.now() - t0 < 450) setTimeout(tick, 25); else done(out); };
    tick();
  }));
  // The outline: hover one shape, then another, sampling its left edge every 10 ms.
  const glide = await page.evaluate(() => new Promise((done) => {
    const shapes = [...document.querySelectorAll('[data-slide-index="2"] [data-duo-shape-id]')];
    if (shapes.length < 2) return done({ error: "fewer than two shapes on slide 3" });
    window.__duo.start();
    const hover = (el) => el.dispatchEvent(new MouseEvent("mousemove", { bubbles: true }));
    hover(shapes[0]);
    setTimeout(() => {
      const out = [], t0 = performance.now(), o = document.getElementById("outline");
      hover(shapes[shapes.length - 1]);
      const tick = () => { out.push([Math.round(performance.now() - t0), Math.round(o.getBoundingClientRect().top)]); if (performance.now() - t0 < 150) setTimeout(tick, 10); else done(out); };
      tick();
    }, 100);
  }));
  console.log(`${label}, slide 1 → 3, scrollY: ` + scroll.map(([t, y]) => `${t}:${y}`).join("  "));
  console.log(`${label}, outline top: ` + (glide.error || glide.map(([t, y]) => `${t}:${y}`).join("  ")));
  const ys = scroll.map(([, y]) => y), end = ys.at(-1);
  const mid = scroll.filter(([t]) => t >= 0 && t < 230).map(([, y]) => y).filter((y) => y > ys[0] && y < end);
  if (end <= ys[0]) fails.push(`${label}: the deck didn't move to slide 3`);
  if (!reduce && mid.length < 3) fails.push("motion: the slide change jumped instead of scrolling over 250 ms");
  if (reduce && mid.length) fails.push("Reduce Motion: the slide change scrolled instead of jumping");
  if (!glide.error) {
    const tops = glide.map(([, y]) => y), last = tops.at(-1);
    const between = glide.filter(([t]) => t > 5 && t < 75).map(([, y]) => y).filter((y) => y !== tops[0] && y !== last);
    if (!reduce && between.length < 2) fails.push("motion: the outline jumped instead of gliding over 80 ms");
    if (reduce && between.length) fails.push("Reduce Motion: the outline glided");
  } else if (!reduce) fails.push("motion: " + glide.error);
  await page.close();
}
await b.close();
server.close();
fs.rmSync(dir, { recursive: true, force: true });
console.log(fails.length ? "FAIL\n" + fails.join("\n") : "ok: the deck scrolls to a slide and the outline glides, both at once with Reduce Motion");
process.exit(fails.length ? 1 : 0);
