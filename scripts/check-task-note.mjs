// The task note's editor (F-249 to F-251): arrows and clicks in the notes land on the line they
// show (the properties block's rule counts its margins in its height), and the references field
// takes a URL or a pasted path on Return, saves it as a link, leaves edit mode and draws the link.
// Runs the built page in Chromium at the pane's width, like check-editor-selection.mjs.
//   node scripts/check-task-note.mjs [dir with editor.html and cm6.js]
// Needs playwright-core (NODE_PATH or a scratch node_modules) and Playwright's headless shell.
import fs from "fs";
import { createRequire } from "module";
const require = createRequire(process.env.PW_REQUIRE || import.meta.url);
const { chromium } = require("playwright-core");
const dist = (process.argv[2] || "Vendor/codemirror/dist").replace(/^(?!\/)/, process.cwd() + "/");
const cache = process.env.PLAYWRIGHT_BROWSERS_PATH || process.env.HOME + "/Library/Caches/ms-playwright";
const shell = fs.readdirSync(cache).filter((d) => d.startsWith("chromium_headless_shell-")).sort().pop();
const doc = `---
status: todo
sessions: []
references:
  - "[Plan](../docs/plan.md)"
---

Notes

- First bullet
- Second bullet
- Third bullet
`;
const b = await chromium.launch({ executablePath: `${cache}/${shell}/chrome-headless-shell-mac-arm64/chrome-headless-shell` });
const page = await b.newPage({ viewport: { width: 460, height: 900 } });
await page.goto("file://" + dist + "/editor.html");
await page.evaluate((t) => {
  document.documentElement.setAttribute("style", "--duo-pane:#fff;--duo-text:#1f2328;--duo-text2:#59636e;--duo-selected:#ddf;--duo-rule:#ddd;--duo-control-edge:#ccc;--duo-ground:#f6f8fa;--duo-needs-you:#c00;--duo-radius-card:8px;--duo-heading-above:4px;");
  window.__folded = false; duo.create(t);
  window.V = document.querySelector(".cm-content").cmTile.view;
  duo.setContext({ task: true, noteDir: "tasks", noteName: "t.md", root: "/Users/me/proj", home: "/Users/me", files: ["docs/plan.md", "docs/specs/", "docs/a b.md"], sessions: {} });
}, doc);
await page.waitForTimeout(400);
const fails = [];
const line = () => page.evaluate(() => V.state.doc.lineAt(V.state.selection.main.head).text);
const at = (n) => page.evaluate((n) => V.state.doc.toString().indexOf(n), n);
// Heightmap vs DOM below the properties block.
const drift = await page.evaluate(() => {
  const out = [];
  for (const el of document.querySelectorAll(".cm-line")) {
    const pos = V.posAtDOM(el, 0), n = V.state.doc.lineAt(pos).number;
    if (n < 8) continue;
    const d = V.lineBlockAt(pos).top + V.documentTop - el.getBoundingClientRect().top;
    if (Math.abs(d) > 0.5) out.push({ n, d });
  }
  return out;
});
if (drift.length) fails.push("heightmap drifts below the properties block: " + JSON.stringify(drift));
// ArrowUp from the third bullet goes to the second, then the first.
await page.evaluate((p) => { V.dispatch({ selection: { anchor: p } }); V.focus(); }, (await at("Third bullet")) + 3);
await page.keyboard.press("ArrowUp"); await page.waitForTimeout(100);
if ((await line()) !== "- Second bullet") fails.push("ArrowUp from bullet 3 landed on: " + (await line()));
await page.keyboard.press("ArrowUp"); await page.waitForTimeout(100);
if ((await line()) !== "- First bullet") fails.push("ArrowUp from bullet 2 landed on: " + (await line()));
// A click on each line puts the caret there.
for (const needle of ["Third bullet", "First bullet", "Notes"]) {
  const r = await page.evaluate((n) => { const c = V.coordsAtPos(V.state.doc.toString().indexOf(n) + 2); return { x: c.left + 1, y: (c.top + c.bottom) / 2 }; }, needle);
  await page.mouse.click(r.x, r.y); await page.waitForTimeout(100);
  if (!(await line()).includes(needle)) fails.push(`click on "${needle}" landed on: ` + (await line()));
}
// The field: a pasted path, a file:// URL and a web link, each saved with Return as a drawn link.
const add = async (text, expectDoc, expectName) => {
  const refs = () => page.evaluate(() => document.querySelectorAll(".duo-fm-ref").length);
  const before = await refs();
  await page.evaluate((p) => { V.dispatch({ selection: { anchor: p } }); }, await at("Third bullet"));
  await page.click(".duo-fm-reffield input");
  await page.keyboard.insertText(text);   // a paste: one input event
  await page.keyboard.press("Enter"); await page.waitForTimeout(150);
  const t = await page.evaluate(() => V.state.doc.toString());
  if (!t.includes(expectDoc)) fails.push(`"${text}" was not saved as ${expectDoc}`);
  if ((await refs()) !== before + 1) fails.push(`"${text}" does not draw as a link (${before} -> ${await refs()})`);
  const names = await page.evaluate(() => [...document.querySelectorAll(".duo-fm-ref-name")].map((e) => e.textContent));
  if (!names.includes(expectName)) fails.push(`"${text}": link name missing, have ${JSON.stringify(names)}`);
  if (await page.evaluate(() => document.activeElement?.tagName === "INPUT")) fails.push(`"${text}": the field is still in edit mode`);
  if (await page.evaluate(() => document.querySelector(".duo-fm-reffield input").value !== "")) fails.push(`"${text}": the field kept its text`);
};
await add("/Users/me/proj/docs/specs/design.md", "[design](../docs/specs/design.md)", "design");
await add("~/Desktop/notes.txt", "[notes.txt](../../Desktop/notes.txt)", "notes.txt");
await add("file:///Users/me/proj/docs/a%20b.md", "[a b](../docs/a%20b.md)", "a b");
await add("https://example.com/x", "[example.com](https://example.com/x)", "example.com");
await b.close();
if (fails.length) { console.log(fails.join("\n")); process.exit(1); }
console.log("task note: ok (arrows and clicks land on the right line; paths and links save, draw and leave edit mode)");
