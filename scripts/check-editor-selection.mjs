// The editor's selection (C-25, F-101): clicks, drags and shift+arrows must land where the text is
// drawn, across wrapped lines, soft breaks, headings and a table. Runs the built page in Chromium at
// the pane's width (web views don't draw in window captures, F-25).
//   node scripts/check-editor-selection.mjs [dir with editor.html and cm6.js] [chromium|webkit|both]
// Needs playwright-core (npm i playwright-core in a scratch folder, NODE_PATH to it) and Playwright's
// Chromium headless shell and WebKit (node_modules/playwright-core/cli.js install webkit) in
// ~/Library/Caches/ms-playwright. The document holds every block widget (properties block, image,
// Claude's deletion marker, table and its bar, rule, code fence): CodeMirror's height map must agree
// with the drawn lines at every caret position, and no click may land on another line (DL-167).
import fs from "fs";
import { createRequire } from "module";
const require = createRequire(import.meta.url);
const { chromium, webkit } = require("playwright-core");
const dist = (process.argv[2] || "Vendor/codemirror/dist").replace(/^(?!\/)/, process.cwd() + "/");
const cache = process.env.PLAYWRIGHT_BROWSERS_PATH || process.env.HOME + "/Library/Caches/ms-playwright";
const shell = fs.readdirSync(cache).filter((d) => d.startsWith("chromium_headless_shell-")).sort().pop();
const which = process.argv[3] || "both";
const doc = `---
title: Release plan
status: open
---

# Release plan

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

![A figure](missing.png)

Text after the figure that is long enough to wrap onto a second visual line in the pane at this width.

Claude will remove this first removed line
and this second one, so a marker stands here.

Paragraph after the marker, long enough to wrap onto a second visual line in the pane at this width.

---

Paragraph after the rule.

\`\`\`js
const a = 1;
const b = 2;
\`\`\`

Final paragraph after the code fence, long enough to wrap onto one more visual line in the pane.

| Name | Kind | Size |
|:--|:-:|--:|
| one | a | 1 |
| two | b | 2 |
| three | c | 3 |
| four | d | 4 |
| five | e | 5 |
| six | f | 6 |
| seven | g | 7 |

A paragraph after the tall table.
`;
async function run(name, launch) {
const fails = [];
const b = await launch();
const page = await b.newPage({ viewport: { width: 460, height: 900 }, deviceScaleFactor: 2 });
await page.addInitScript(() => { window.duoFlags = { noPost: true }; });
await page.goto("file://" + dist + "/editor.html");
await page.evaluate((t) => {
  document.documentElement.setAttribute("style", "--duo-pane:#fff;--duo-text:#1f2328;--duo-text2:#59636e;--duo-selected:#ddf;--duo-rule:#ddd;--duo-control-edge:#ccc;--duo-ground:#f6f8fa;--duo-needs-you:#c00;--duo-radius-card:8px;--duo-heading-above:4px;");
  window.__folded = false; duo.create(t);
  window.V = document.querySelector(".cm-content").cmTile.view;
  // Claude removes two lines: a deletion marker stands where they were.
  duo.agentReplace("Claude will remove this first removed line\nand this second one, so a marker stands here.\n\n", "");
}, doc);
await page.waitForTimeout(400);
const sel = () => page.evaluate(() => ({ a: V.state.selection.main.anchor, h: V.state.selection.main.head }));
const ctx = (p) => page.evaluate((p) => JSON.stringify(V.state.sliceDoc(Math.max(0, p - 8), p) + "|" + V.state.sliceDoc(p, p + 8)), p);
// Heightmap vs DOM: CodeMirror's idea of each line's top against where the browser draws it, with the
// caret in each place (a line is a different height, a table a different widget, when it holds the caret).
const driftAt = () => page.evaluate(() => {
  const out = [];
  // A line with block widgets before it comes back as one block; its own top is its text entry's.
  const textTop = (blk) => Array.isArray(blk.type) ? (blk.type.find((x) => x.type === 0)?.top ?? blk.top) : blk.top;
  for (const el of document.querySelectorAll(".cm-content > *")) {
    const r = el.getBoundingClientRect();
    if (!r.height) continue;
    const pos = V.posAtDOM(el, 0), blk = V.lineBlockAt(pos);
    if (el.classList.contains("cm-line")) {
      const d = textTop(blk) + V.documentTop - r.top;
      if (Math.abs(d) > 0.5) out.push({ what: `line ${V.state.doc.lineAt(pos).number}`, cm: textTop(blk) + V.documentTop, dom: r.top });
    } else {
      // A block widget (image, table, marker, properties heading): CodeMirror's block must be as tall as drawn.
      const kids = Array.isArray(blk.type) ? blk.type.filter((x) => x.type !== 0) : [blk];
      const mine = kids.find((x) => Math.abs(x.top + V.documentTop - r.top) < 0.5) || kids.find((x) => Math.abs(x.height - r.height) < 0.5);
      if (!mine || Math.abs(mine.height - r.height) > 0.5) out.push({ what: `widget "${el.className.slice(0, 24) || el.textContent.slice(0, 12)}" (${r.height.toFixed(1)} tall drawn)`, cm: mine ? mine.top + V.documentTop : NaN, dom: r.top });
    }
  }
  return out;
});
const carets = await page.evaluate(() => {
  const d = V.state.doc, find = (t) => { for (let n = 1; n <= d.lines; n++) if (d.line(n).text.startsWith(t)) return d.line(n).from; return 0; };
  return { start: 0, frontmatter: find("title:"), table: find("| a"), image: find("![A figure"), rule: (() => { let seen = 0; for (let n = 1; n <= d.lines; n++) if (d.line(n).text === "---" && ++seen === 3) return d.line(n).from; return 0; })(), fence: find("const a"), end: d.length };
});
for (const [name, pos] of Object.entries(carets)) {
  await page.evaluate((p) => V.dispatch({ selection: { anchor: p } }), pos);
  await page.waitForTimeout(60);
  for (const d of await driftAt()) fails.push(`heightmap (caret in ${name}): ${d.what}: CodeMirror says top ${d.cm.toFixed(1)}, drawn at ${d.dom.toFixed(1)}`);
}
// No line moves when the caret arrives (DL-167): with the caret on each line in turn, every other line
// keeps its top and the document its height, as with the caret parked on the last line. The image line
// is the one known exception (a picture's source is a line of text, Q-n): skipped and said so.
await page.setViewportSize({ width: 460, height: 1600 });   // every line drawn, none estimated
const layout = () => page.evaluate(() => {
  const d = V.state.doc, tops = [];
  for (let n = 1; n <= d.lines; n++) { const blk = V.lineBlockAt(d.line(n).from); tops.push(Array.isArray(blk.type) ? (blk.type.find((x) => x.type === 0)?.top ?? blk.top) : blk.top); }
  return { tops, height: V.contentHeight };
});
const lineInfo = await page.evaluate(() => {
  const d = V.state.doc, out = [];
  for (let n = 1; n <= d.lines; n++) out.push({ n, from: d.line(n).from, text: d.line(n).text });
  const image = out.findIndex((l) => l.text.startsWith("![A figure"));
  return { lines: out, table: out.filter((l) => l.text.startsWith("|")).map((l) => l.n), image: image + 1 };
});
await page.evaluate((p) => V.dispatch({ selection: { anchor: p } }), lineInfo.lines.at(-1).from);
await page.waitForTimeout(60);
const base = await layout();let moved = 0;
for (const l of lineInfo.lines) {
  if (l.n === lineInfo.image) continue;
  await page.evaluate((p) => V.dispatch({ selection: { anchor: p } }), l.from);
  await page.waitForTimeout(40);
  const now = await layout();
  if (Math.abs(now.height - base.height) > 0.5) { moved++; fails.push(`caret on line ${l.n} (${JSON.stringify(l.text.slice(0, 20))}) changed the document's height ${base.height.toFixed(1)} → ${now.height.toFixed(1)}`); continue; }
  for (let i = 0; i < now.tops.length; i++) {
    const n = i + 1;
    if (n === l.n || lineInfo.table.includes(n) || n === lineInfo.image) continue;
    if (Math.abs(now.tops[i] - base.tops[i]) > 0.5) { moved++; fails.push(`caret on line ${l.n} (${JSON.stringify(l.text.slice(0, 20))}) moved line ${n} by ${(now.tops[i] - base.tops[i]).toFixed(1)}`); break; }
  }
}
console.log(`${name}: no-line-moved: ${lineInfo.lines.length - 1} caret lines compared, ${moved} moved (the image line is skipped)`);
await page.setViewportSize({ width: 460, height: 900 });
await page.evaluate(() => V.dispatch({ selection: { anchor: 0 } }));
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
  const before = await page.evaluate((p) => { const r = V.coordsAtPos(p, 1); return { x: r.left, y: r.bottom + V.scrollDOM.scrollTop }; }, t.p);
  await page.keyboard.press("Shift+ArrowDown");
  const s = await sel();
  const after = await page.evaluate((p) => { const r = V.coordsAtPos(p, V.state.selection.main.assoc || 1); return { x: r.left, top: r.top + V.scrollDOM.scrollTop, bottom: r.bottom + V.scrollDOM.scrollTop }; }, s.h);
  // Expected: the first visual line below the start, any line (blank lines are 10 tall).
  if (s.a !== t.p) fails.push(`shift+down from ${await ctx(t.p)} moved the anchor`);
  const mid = (after.top + after.bottom) / 2;   // a 10 px blank line's caret box is taller than the line: judge by the middle
  if (mid < before.y - 1) fails.push(`shift+down from ${await ctx(t.p)} went up/stayed: head ${await ctx(s.h)}`);
  else if (mid - before.y > 36) fails.push(`shift+down from ${await ctx(t.p)} skipped a line: head ${await ctx(s.h)} (${(mid - before.y).toFixed(1)} below)`);
}
// IME composition (DL-167): text composed in the editor lands at the caret, once, with the caret after it, and
// the composition is the editor's (no chord or key handling mid-composition). Chromium only: Playwright's
// WebKit has no IME API, so there the case is reported as skipped.
if (name === "chromium") {
  const cdp = await page.context().newCDPSession(page);
  const para = await page.evaluate(() => { const d = V.state.doc; for (let n = 1; n <= d.lines; n++) if (d.line(n).text.startsWith("Paragraph after the rule")) return d.line(n).to; return 0; });
  await page.evaluate((p) => { V.focus(); V.dispatch({ selection: { anchor: p } }); }, para);
  const before = await page.evaluate(() => V.state.doc.toString());
  await cdp.send("Input.imeSetComposition", { text: "に", selectionStart: 1, selectionEnd: 1 });
  await cdp.send("Input.imeSetComposition", { text: "日本", selectionStart: 2, selectionEnd: 2 });
  const during = await page.evaluate(() => ({ composing: V.composing, view: V.compositionStarted }));
  if (!during.composing && !during.view) fails.push("IME: the editor didn't see the composition start");
  await cdp.send("Input.insertText", { text: "日本" });
  await page.waitForTimeout(100);
  const after = await page.evaluate(() => ({ text: V.state.doc.toString(), head: V.state.selection.main.head }));
  if (after.text !== before.slice(0, para) + "日本" + before.slice(para)) fails.push(`IME: the composed text didn't land once at the caret: ${JSON.stringify(after.text.slice(para - 6, para + 8))}`);
  if (after.head !== para + 2) fails.push(`IME: the caret should follow the composed text (${para + 2}), is ${after.head}`);
  // The same composition, undone as one step.
  await page.keyboard.press("Meta+z"); await page.keyboard.press("Control+z");
  if ((await page.evaluate(() => V.state.doc.toString())) !== before) fails.push("IME: undo didn't take the composed text out in one step");
  console.log("chromium: IME composition checked");
} else console.log(`${name}: IME composition skipped (no IME API in Playwright's WebKit)`);
console.log(`${name}: ${targets.length} clicks, ${pairs.length} drags, ${targets.length} shift+down`);
console.log(fails.length ? fails.map((f) => `${name}: ${f}`).join("\n") : `${name}: PASS`);
await b.close();
return fails.length;

}
let bad = 0;
if (which !== "webkit") bad += await run("chromium", () => chromium.launch({ executablePath: `${cache}/${shell}/chrome-headless-shell-mac-arm64/chrome-headless-shell` }));
if (which !== "chromium") bad += await run("webkit", () => webkit.launch());
process.exit(bad ? 1 : 0);
