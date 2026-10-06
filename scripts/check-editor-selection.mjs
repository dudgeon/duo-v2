// The editor's selection (C-25, F-101): clicks, drags and shift+arrows must land where the text is
// drawn, across wrapped lines, soft breaks, headings and a table. Runs the built page in Chromium at
// the pane's width (web views don't draw in window captures, F-25).
//   node scripts/check-editor-selection.mjs [dir with editor.html and cm6.js]
// Needs playwright-core (npm i playwright-core in a scratch folder, NODE_PATH to it) and Playwright's
// Chromium headless shell in ~/Library/Caches/ms-playwright.
import fs from "fs";
import { createRequire } from "module";
const require = createRequire(import.meta.url);
const { chromium } = require("playwright-core");
const dist = (process.argv[2] || "Vendor/codemirror/dist").replace(/^(?!\/)/, process.cwd() + "/");
const cache = process.env.PLAYWRIGHT_BROWSERS_PATH || process.env.HOME + "/Library/Caches/ms-playwright";
const shell = fs.readdirSync(cache).filter((d) => d.startsWith("chromium_headless_shell-")).sort().pop();
const doc = `# Release plan

This first paragraph is long enough that it wraps across several lines in a pane four hundred and sixty points wide, with some \`inline code\` in it and more words after that.

## Thresholds

A paragraph with a soft break here
and a second source line that is also long enough to wrap in the pane at this width, so both kinds show.

- A list item that is long enough to wrap onto a second visual line in the pane at this width, really.
- Short item

| Path | Limit |
|---|---|
| a | 1 |
| b | 2 |

### Open questions

Last paragraph after the table, long enough to wrap onto another visual line in the pane, yes it is.
`;
const b = await chromium.launch({ executablePath: `${cache}/${shell}/chrome-headless-shell-mac-arm64/chrome-headless-shell` });
const page = await b.newPage({ viewport: { width: 460, height: 900 }, deviceScaleFactor: 2 });
await page.goto("file://" + dist + "/editor.html");
await page.evaluate((t) => {
  document.documentElement.setAttribute("style", "--duo-pane:#fff;--duo-text:#1f2328;--duo-text2:#59636e;--duo-selected:#ddf;--duo-rule:#ddd;--duo-control-edge:#ccc;--duo-ground:#f6f8fa;--duo-needs-you:#c00;--duo-radius-card:8px;--duo-heading-above:4px;");
  window.__folded = false; duo.create(t);
  window.V = document.querySelector(".cm-content").cmTile.view;
}, doc);
await page.waitForTimeout(400);
const fails = [];
const sel = () => page.evaluate(() => ({ a: V.state.selection.main.anchor, h: V.state.selection.main.head }));
const ctx = (p) => page.evaluate((p) => JSON.stringify(V.state.sliceDoc(Math.max(0, p - 8), p) + "|" + V.state.sliceDoc(p, p + 8)), p);
// Heightmap vs DOM: CodeMirror's idea of each line's top against where the browser draws it.
const drift = await page.evaluate(() => {
  const out = [];
  for (const el of document.querySelectorAll(".cm-line")) {
    const pos = V.posAtDOM(el, 0), blk = V.lineBlockAt(pos), r = el.getBoundingClientRect();
    const d = blk.top + V.documentTop - r.top;
    if (Math.abs(d) > 0.5) out.push({ line: V.state.doc.lineAt(pos).number, cm: blk.top + V.documentTop, dom: r.top, d });
  }
  return out;
});
for (const d of drift) fails.push(`heightmap: line ${d.line} CodeMirror says top ${d.cm.toFixed(1)}, drawn at ${d.dom.toFixed(1)}`);
// Click before characters (the left edge of each drawn character): the caret must land there.
const targets = await page.evaluate(() => {
  const out = [], text = V.state.doc.toString();
  for (let p = 0; p < text.length; p++) {
    if (!/\w/.test(text[p]) || (p > 0 && /\w/.test(text[p - 1]))) continue;   // word starts
    const r = V.coordsAtPos(p, 1);
    if (!r) continue;
    const el = document.elementFromPoint(r.left + 1, (r.top + r.bottom) / 2);
    if (!el || !el.closest(".cm-line") || el.closest(".duo-table, .cm-widgetBuffer")) continue;
    out.push({ p, x: r.left + 1, y: (r.top + r.bottom) / 2 });
  }
  return out;
});
// After moving the caret, headings show their `## ` and things move: click from a far line each time.
for (const t of targets) {
  await page.evaluate(() => V.dispatch({ selection: { anchor: 0 } }));
  const r = await page.evaluate((p) => { const r = V.coordsAtPos(p, 1); return r && { x: r.left + 1, y: (r.top + r.bottom) / 2 }; }, t.p);
  await page.mouse.click(r.x, r.y);
  const s = await sel();
  if (s.h !== t.p) fails.push(`click at ${await ctx(t.p)} put the caret at ${await ctx(s.h)}`);
}
// Drags between word starts on different visual lines.
const pairs = [];
for (let i = 0; i + 7 < targets.length; i += 5) pairs.push([targets[i], targets[i + 7]], [targets[i + 7], targets[i]]);   // down and up
for (const [x, y] of pairs) {
  await page.evaluate(() => V.dispatch({ selection: { anchor: 0 } }));
  await page.mouse.click(5, 895);
  const r1 = await page.evaluate((p) => { const r = V.coordsAtPos(p, 1); return { x: r.left + 1, y: (r.top + r.bottom) / 2 }; }, x.p);
  await page.mouse.move(r1.x, r1.y); await page.mouse.down();
  // The caret's line shows its markup on mousedown; aim at the far end after that.
  const r2 = await page.evaluate((p) => { const r = V.coordsAtPos(p, 1); return { x: r.left + 1, y: (r.top + r.bottom) / 2 }; }, y.p);
  await page.mouse.move(r2.x, r2.y, { steps: 8 }); await page.mouse.up();
  const s = await sel();
  if (s.a !== x.p || s.h !== y.p) fails.push(`drag ${await ctx(x.p)} → ${await ctx(y.p)} selected ${await ctx(s.a)} → ${await ctx(s.h)}`);
}
// Shift+Down from each word start: the head must go to the visual line below, near the same x.
for (const t of targets) {
  await page.evaluate((p) => { V.focus(); V.dispatch({ selection: { anchor: p } }); }, t.p);
  const before = await page.evaluate((p) => { const r = V.coordsAtPos(p, 1); return { x: r.left, y: r.bottom }; }, t.p);
  await page.keyboard.press("Shift+ArrowDown");
  const s = await sel();
  const after = await page.evaluate((p) => { const r = V.coordsAtPos(p, V.state.selection.main.assoc || 1); return { x: r.left, top: r.top, bottom: r.bottom }; }, s.h);
  // Expected: the first visual line below the start, any line (blank lines are 10 tall).
  if (s.a !== t.p) fails.push(`shift+down from ${await ctx(t.p)} moved the anchor`);
  if (after.top < before.y - 1) fails.push(`shift+down from ${await ctx(t.p)} went up/stayed: head ${await ctx(s.h)}`);
  else if (after.top - before.y > 26) fails.push(`shift+down from ${await ctx(t.p)} skipped a line: head ${await ctx(s.h)} (${(after.top - before.y).toFixed(1)} below)`);
}
console.log(`${targets.length} clicks, ${pairs.length} drags, ${targets.length} shift+down`);
console.log(fails.length ? fails.join("\n") : "PASS");
await b.close();
process.exit(fails.length ? 1 : 0);
