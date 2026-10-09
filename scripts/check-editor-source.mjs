// Source mode, per document (DL-167, Q3): the same text drawn as typed, with no live preview, and
// remembered per document. Checks the page's side in Chromium and WebKit, and writes a capture of
// each mode.
//   node scripts/check-editor-source.mjs [dir with editor.html and cm6.js] [chromium|webkit|both] [capture dir]
// Needs playwright-core (NODE_PATH) with Chromium headless shell and WebKit installed.
import fs from "fs";
import { createRequire } from "module";
const require = createRequire(import.meta.url);
const { chromium, webkit } = require("playwright-core");
const dist = (process.argv[2] || "Vendor/codemirror/dist").replace(/^(?!\/)/, process.cwd() + "/");
const which = process.argv[3] || "both";
const out = process.argv[4];
const cache = process.env.PLAYWRIGHT_BROWSERS_PATH || process.env.HOME + "/Library/Caches/ms-playwright";
const shell = fs.readdirSync(cache).filter((d) => d.startsWith("chromium_headless_shell-")).sort().pop();
const A = `---
title: Release plan
status: open
---

# Release plan

Some **bold** and \`code\` and a [link](https://example.com) in a paragraph.

- [ ] A task
- A bullet

| Path | Limit |
|---|---|
| a | 1 |

![A figure](missing.png)

---

\`\`\`js
const a = 1;
\`\`\`
`;
const B = "# Document B\n\nWith **bold**.\n";
const tokens = "--duo-pane:#fff;--duo-text:#1f2328;--duo-text2:#59636e;--duo-selected:#ddf;--duo-rule:#ddd;--duo-control-edge:#ccc;--duo-ground:#f6f8fa;--duo-needs-you:#c00;--duo-radius-card:8px;--duo-heading-above:4px;";

async function run(name, launch) {
  const fails = [];
  const ok = (cond, msg) => { if (!cond) fails.push(msg); };
  const b = await launch();
  const page = await b.newPage({ viewport: { width: 460, height: 640 }, deviceScaleFactor: 2 });
  await page.addInitScript(() => { window.duoFlags = { noPost: true }; });
  await page.goto("file://" + dist + "/editor.html");
  await page.evaluate((t) => document.documentElement.setAttribute("style", t), tokens);
  const dom = () => page.evaluate(() => ({
    table: !!document.querySelector(".duo-table"), figure: !!document.querySelector(".duo-figure"), props: !!document.querySelector(".duo-fm-head"),
    rule: !!document.querySelector(".duo-hr"), checkbox: !!document.querySelector(".duo-task"), strong: !!document.querySelector(".duo-strong"),
    text: document.querySelector(".cm-content").innerText,
  }));
  const shot = async (file) => { if (out) { fs.mkdirSync(out, { recursive: true }); await page.screenshot({ path: `${out}/${file}.png` }); } };

  await page.evaluate(([id, t]) => duo.show(id, t, {}), ["/a.md", A]);
  await page.evaluate(() => document.querySelector(".cm-content").cmTile.view.dispatch({ selection: { anchor: document.querySelector(".cm-content").cmTile.view.state.doc.length } }));
  await page.waitForTimeout(150);
  let d = await dom();
  ok(d.table && d.figure && d.props && d.rule && d.checkbox, `preview draws its widgets: ${JSON.stringify({ ...d, text: 0 })}`);
  ok(!d.text.includes("**bold**"), "preview hides the bold marks");
  ok((await page.evaluate(() => duo.source())) === false, "source() is false in preview");
  await shot(`editor-${name}-preview`);

  // Type something so there is history, then turn Source on.
  await page.evaluate(() => { const V = document.querySelector(".cm-content").cmTile.view; V.focus(); V.dispatch({ selection: { anchor: V.state.doc.line(7).to } }); });
  await page.keyboard.type(" EDIT");
  await page.evaluate(() => duo.setSource(true));
  await page.waitForTimeout(150);
  d = await dom();
  ok(!d.table && !d.figure && !d.props && !d.rule && !d.checkbox && !d.strong, `source draws no widget or mark: ${JSON.stringify({ ...d, text: 0 })}`);
  ok(d.text.includes("**bold**") && d.text.includes("| Path | Limit |") && d.text.includes("![A figure](missing.png)") && d.text.includes("title: Release plan"), "source shows the text as typed");
  ok((await page.evaluate(() => duo.source())) === true, "source() is true");
  await shot(`editor-${name}-source`);

  // The mode is the document's: B (new) is preview, A comes back in source with its history.
  await page.evaluate(([id, t]) => duo.show(id, t, {}), ["/b.md", B]);
  await page.waitForTimeout(100);
  d = await dom();
  ok(d.strong && !d.text.includes("**bold**"), "B opens in preview");
  await page.evaluate(([id, t]) => duo.show(id, t, {}), ["/a.md", A]);
  await page.waitForTimeout(150);
  d = await dom();
  ok(!d.table && d.text.includes("**bold**"), "A comes back in source");
  await page.evaluate(() => document.querySelector(".cm-content").cmTile.view.focus());
  await page.keyboard.press("Meta+z"); await page.keyboard.press("Control+z");
  ok(!(await dom()).text.includes("EDIT"), "undo still reaches the typing made before Source was turned on");

  // Back to preview keeps the text; a remembered id opens in source.
  await page.evaluate(() => duo.setSource(false));
  await page.waitForTimeout(150);
  ok((await dom()).table, "Source off draws the table again");
  await page.evaluate(() => duo.sourceModes(["/b.md"]));
  await page.evaluate(([id, t]) => duo.show(id, t, {}), ["/b.md", B]);   // B is held (preview): the remembered set applies when told
  await page.evaluate(([id, t]) => duo.show(id, t, { source: true }), ["/c.md", B]);
  ok((await dom()).text.includes("**bold**"), "a new document with source: true opens in source");
  await page.evaluate(([id, t]) => duo.show(id, t, {}), ["/d.md", B]);
  ok(!(await dom()).text.includes("**bold**") || (await page.evaluate(() => duo.source())), "consistent");

  console.log(fails.length ? fails.map((f) => `${name}: ${f}`).join("\n") : `${name}: PASS`);
  await b.close();
  return fails.length;
}
let bad = 0;
if (which !== "webkit") bad += await run("chromium", () => chromium.launch({ executablePath: `${cache}/${shell}/chrome-headless-shell-mac-arm64/chrome-headless-shell` }));
if (which !== "chromium") bad += await run("webkit", () => webkit.launch());
process.exit(bad ? 1 : 0);
