// One editor state per open document (DL-167 step 3): type in A, switch to B and back; A's caret,
// scroll position and undo history must survive, B must be untouched, and closing a document frees
// its state. Runs the built page in Chromium and WebKit at the pane's width.
//   node scripts/check-editor-state.mjs [dir with editor.html and cm6.js] [chromium|webkit|both]
// Needs playwright-core (NODE_PATH) with Chromium headless shell and WebKit installed.
import fs from "fs";
import { createRequire } from "module";
const require = createRequire(import.meta.url);
const { chromium, webkit } = require("playwright-core");
const dist = (process.argv[2] || "Vendor/codemirror/dist").replace(/^(?!\/)/, process.cwd() + "/");
const which = process.argv[3] || "both";
const cache = process.env.PLAYWRIGHT_BROWSERS_PATH || process.env.HOME + "/Library/Caches/ms-playwright";
const shell = fs.readdirSync(cache).filter((d) => d.startsWith("chromium_headless_shell-")).sort().pop();
const A = Array.from({ length: 120 }, (_, i) => `Line ${i + 1} of document A, long enough to be a line.`).join("\n\n") + "\n";
const B = "# Document B\n\nA short one.\n";

async function run(name, launch) {
  const fails = [];
  const ok = (cond, msg) => { if (!cond) fails.push(msg); };
  const b = await launch();
  const page = await b.newPage({ viewport: { width: 460, height: 700 } });
  await page.addInitScript(() => { window.duoFlags = { noPost: true }; });
  await page.goto("file://" + dist + "/editor.html");
  await page.evaluate(() => { document.documentElement.setAttribute("style", "--duo-pane:#fff;--duo-text:#1f2328;--duo-text2:#59636e;--duo-selected:#ddf;--duo-rule:#ddd;--duo-control-edge:#ccc;--duo-ground:#f6f8fa;--duo-needs-you:#c00;--duo-radius-card:8px;--duo-heading-above:4px;"); });
  const view = () => page.evaluate(() => { const V = document.querySelector(".cm-content").cmTile.view; return { text: V.state.doc.toString(), head: V.state.selection.main.head, scroll: Math.round(V.scrollDOM.scrollTop) }; });

  const r1 = await page.evaluate(([id, t]) => duo.show(id, t, { folded: false }), ["/a.md", A]);
  ok(r1.restored === false && r1.dirty === false, `first show of A: ${JSON.stringify(r1)}`);
  // Type in A at line 60, then scroll further down.
  await page.evaluate(() => { const V = document.querySelector(".cm-content").cmTile.view; const at = V.state.doc.line(60).to; V.dispatch({ selection: { anchor: at }, scrollIntoView: true }); V.focus(); });
  await page.keyboard.type(" TYPED");
  await page.evaluate(() => { document.querySelector(".cm-scroller").scrollTop = 1800; });
  await page.waitForTimeout(100);
  const a1 = await view();
  ok(a1.text.includes("TYPED") && a1.scroll > 500, `A before switching: ${JSON.stringify({ ...a1, text: a1.text.length })}`);

  const r2 = await page.evaluate(([id, t]) => duo.show(id, t, { folded: false }), ["/b.md", B]);
  ok(r2.restored === false, "B is new");
  const b1 = await view();
  ok(b1.text === B && !b1.text.includes("TYPED"), "B shows B");
  ok((await page.evaluate(() => duo.heldIds())).join() === "/a.md", "A is held while B shows");

  const r3 = await page.evaluate(([id, t]) => duo.show(id, t, { folded: false }), ["/a.md", A]);
  ok(r3.restored === true && r3.dirty === true, `A restored and dirty: ${JSON.stringify(r3)}`);
  await page.waitForTimeout(150);
  const a2 = await view();
  ok(a2.text === a1.text, "A's text survives the switch");
  ok(a2.head === a1.head, `A's caret survives: ${a1.head} → ${a2.head}`);
  ok(Math.abs(a2.scroll - a1.scroll) < 2, `A's scroll survives: ${a1.scroll} → ${a2.scroll}`);

  // ⌘Z undoes the typing in A; ⇧⌘Z brings it back.
  await page.evaluate(() => document.querySelector(".cm-content").cmTile.view.focus());
  await page.keyboard.press("Meta+z");
  await page.keyboard.press("Control+z");
  const a3 = await view();
  ok(!a3.text.includes("TYPED"), "⌘Z undoes the typing made before the switch");
  ok(a3.text === A, "…back to exactly A's text");

  // A closed document's state is freed; showing it again starts fresh from disk.
  await page.evaluate(() => duo.show("/b.md", "# Document B\n\nA short one.\n", {}));   // A is held, B shown
  ok((await page.evaluate(() => duo.close("/b.md"))) === false, "closing the shown document holds nothing");
  ok((await page.evaluate(() => duo.close("/a.md"))) === true, "close(A) had a state");
  ok((await page.evaluate(() => duo.heldIds())).join() === "", "nothing held for a closed document");
  const r4 = await page.evaluate(([id, t]) => duo.show(id, t, {}), ["/a.md", A]);
  ok(r4.restored === false && r4.dirty === false, "A reopened fresh");
  // Rename re-keys.
  await page.evaluate(() => duo.rename("/a.md", "/c.md"));
  await page.evaluate(([id, t]) => duo.show(id, t, {}), ["/b.md", B]);
  ok((await page.evaluate(() => duo.heldIds())).join() === "/c.md", "rename re-keys the held state");
  ok((await page.evaluate(() => { const V = document.querySelector(".cm-content").cmTile.view; return V.state.doc.toString(); })) === B, "B still shown");

  console.log(`${name}: ${fails.length ? fails.map((f) => `${name}: ${f}`).join("\n") : "PASS"}`);
  await b.close();
  return fails.length;
}
let bad = 0;
if (which !== "webkit") bad += await run("chromium", () => chromium.launch({ executablePath: `${cache}/${shell}/chrome-headless-shell-mac-arm64/chrome-headless-shell` }));
if (which !== "chromium") bad += await run("webkit", () => webkit.launch());
process.exit(bad ? 1 : 0);
