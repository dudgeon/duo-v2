// Claude's highlight fading in and out in the editor (DL-130, F-138). Web views don't run page
// animations in a window that isn't on screen (F-102), so this runs the built page in Chromium at
// the pane's width and samples the highlight's colour over time, with Reduce Motion off and on.
//   node scripts/check-editor-motion.mjs [dir with editor.html and cm6.js]
// Needs playwright-core (npm i playwright-core in a scratch folder, NODE_PATH to it) and Playwright's
// Chromium headless shell in ~/Library/Caches/ms-playwright, as check-editor-selection.mjs does.
import fs from "fs";
import { createRequire } from "module";
const require = createRequire(import.meta.url);
const { chromium } = require("playwright-core");
const dist = (process.argv[2] || "Vendor/codemirror/dist").replace(/^(?!\/)/, process.cwd() + "/");
const cache = process.env.PLAYWRIGHT_BROWSERS_PATH || process.env.HOME + "/Library/Caches/ms-playwright";
const shell = fs.readdirSync(cache).filter((d) => d.startsWith("chromium_headless_shell-")).sort().pop();
const doc = "# PRD v2\n\n## Goals\n\nCut abandonment.\n";
// The app's token CSS, as DocumentEditor.tokenCSS() sets it: selected #E9ECEF, highlight 200 / 600 ms.
const tokens = "--duo-pane:#FFFFFF;--duo-text:#1F2328;--duo-text2:#5B636D;--duo-selected:#E9ECEF;--duo-rule:#C9CDD3;--duo-control-edge:#8B939C;"
  + "--duo-ground:#F3F4F6;--duo-needs-you:#C2410C;--duo-radius-card:6px;--duo-heading-above:4px;"
  + "--duo-motion-highlight-in-ms:200;--duo-motion-highlight-out-ms:600;";
const fails = [];
const b = await chromium.launch({ executablePath: `${cache}/${shell}/chrome-headless-shell-mac-arm64/chrome-headless-shell` });
for (const reduce of [false, true]) {
  const page = await b.newPage({ viewport: { width: 460, height: 400 }, reducedMotion: reduce ? "reduce" : "no-preference" });
  await page.goto("file://" + dist + "/editor.html");
  await page.evaluate(([t, css]) => {
    document.documentElement.setAttribute("style", css);
    window.__folded = false; duo.create(t);
    window.V = document.querySelector(".cm-content").cmTile.view;
  }, [doc, tokens]);
  await page.waitForTimeout(300);
  // The highlight's background, sampled every 50 ms for `ms`.
  const sample = (sel, ms) => page.evaluate(([sel, ms]) => new Promise((done) => {
    const out = [], t0 = performance.now();
    const tick = () => {
      const el = document.querySelector(sel);
      out.push([Math.round(performance.now() - t0), el ? getComputedStyle(el).backgroundColor : "none"]);
      if (performance.now() - t0 < ms) setTimeout(tick, 50); else done(out);
    };
    tick();
  }), [sel, ms]);
  await page.evaluate(() => duo.agentReplace("Cut", "Halve"));
  const into = await sample(".duo-added", 400);
  // The user's next edit clears it; what's left fades.
  await page.evaluate(() => V.dispatch({ changes: { from: 0, insert: "x" }, userEvent: "input.type" }));
  const out = await sample(".duo-added-fading", 900);
  const added = await page.evaluate(() => duo.addedCount());
  const label = reduce ? "Reduce Motion" : "motion";
  console.log(`${label}, in:  ` + into.map(([t, c]) => `${t}:${c.replace(/rgba?\(|\)/g, "")}`).join("  "));
  console.log(`${label}, out: ` + out.map(([t, c]) => `${t}:${c.replace(/rgba?\(|\)/g, "")}`).join("  "));
  const distinct = (xs) => new Set(xs.map(([, c]) => c)).size;
  if (added !== 0) fails.push(`${label}: the highlight is still there after the user's edit (${added})`);
  if (!reduce) {
    if (distinct(into.filter(([t]) => t < 250)) < 3) fails.push("motion: the highlight didn't fade in (fewer than 3 colours in 250 ms)");
    if (distinct(out.filter(([t]) => t < 650)) < 3) fails.push("motion: the cleared highlight didn't fade out (fewer than 3 colours in 650 ms)");
    if (out.at(-1)[1] !== "none") fails.push("motion: the fading copy is still there after 900 ms");
  } else {
    if (into[0][1] !== "rgb(233, 236, 239)") fails.push(`Reduce Motion: the highlight isn't there at once (${into[0][1]})`);
    if (out[0][1] !== "none") fails.push("Reduce Motion: a cleared highlight fades instead of going at once");
  }
  await page.close();
}
await b.close();
console.log(fails.length ? "FAIL\n" + fails.join("\n") : "ok: Claude's highlight fades in and out, and is at once with Reduce Motion");
process.exit(fails.length ? 1 : 0);
