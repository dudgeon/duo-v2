// A code block's Copy button (ENH-005, DL-220; papercuts-copy-tabs-handoff code-resting, code-hover,
// code-copied): hidden at rest with the language at the top right, shown with the pointer anywhere
// on the block, copying the code without its fences, reading "Copied" for about 1.5 s, and never
// moving the caret. Runs the built page at the pane's width in Chromium and WebKit, and writes each
// state's picture of the block for comparing with the boards.
//   node scripts/check-editor-copy.mjs [dir with editor.html and cm6.js] [chromium|webkit|both] [out dir]
// Needs playwright-core (NODE_PATH to a node_modules that has it) and Playwright's Chromium headless
// shell and WebKit in ~/Library/Caches/ms-playwright, as check-editor-selection.mjs does.
import fs from "fs";
import { createRequire } from "module";
import { addTypeVars } from "./editor-vars.mjs";
const require = createRequire(import.meta.url);
const { chromium, webkit } = require("playwright-core");
const dist = (process.argv[2] || "Vendor/codemirror/dist").replace(/^(?!\/)/, process.cwd() + "/");
const which = process.argv[3] || "both";
const out = process.argv[4] || "";
const cache = process.env.PLAYWRIGHT_BROWSERS_PATH || process.env.HOME + "/Library/Caches/ms-playwright";
const shell = fs.readdirSync(cache).filter((d) => d.startsWith("chromium_headless_shell-")).sort().pop();
// The boards' document.
const doc = "## Shipping the beta\n\nRun this once on the work Mac before the walk-through:\n\n```bash\ngit pull origin main\nscripts/bundle.sh\nopen build/Duo.app\n```\n\nThen open the walk page and tick each card as you go.\n\n```\nno language here\n```\n";
const code = "git pull origin main\nscripts/bundle.sh\nopen build/Duo.app";
const tokens = "--duo-pane:#FFFFFF;--duo-text:#1F2328;--duo-text2:#5B636D;--duo-selected:#E9ECEF;--duo-claude-edit:#D6EDDC;--duo-rule:#C9CDD3;--duo-control-edge:#8B939C;"
  + "--duo-ground:#F3F4F6;--duo-needs-you:#C2410C;--duo-radius-card:6px;--duo-heading-above:4px;--duo-motion-highlight-in-ms:400;--duo-motion-highlight-out-ms:600;";

async function run(name, launch) {
  const fails = [];
  const b = await launch();
  const page = await b.newPage({ viewport: { width: 460, height: 380 }, deviceScaleFactor: 2 });
  await page.goto("file://" + dist + "/editor.html");
  await addTypeVars(page);
  await page.evaluate(([t, css]) => {
    document.documentElement.setAttribute("style", css);
    window.__posted = [];
    window.webkit = { messageHandlers: { duo: { postMessage: (m) => window.__posted.push(m) } } };   // as Duo's web view has it
    duo.create(t);
    window.V = document.querySelector(".cm-content").cmTile.view;
    V.dispatch({ selection: { anchor: 3 } });   // the caret in the heading, away from the block
  }, [doc, tokens]);
  await page.waitForTimeout(200);
  const head = () => page.evaluate(() => [...document.querySelectorAll(".duo-code-head")].map((h) => {
    const b = h.querySelector(".duo-code-copy"), l = h.querySelector(".duo-code-lang"), line = h.closest(".cm-line").getBoundingClientRect(), r = h.getBoundingClientRect();
    return { lang: l?.textContent ?? null, shown: getComputedStyle(b).display !== "none", label: b.textContent.trim(), aria: b.getAttribute("aria-label"),
      right: Math.round(line.right - r.right), top: Math.round(r.top - line.top), height: Math.round(b.getBoundingClientRect().height) };
  }));
  const shot = async (state) => {
    if (!out) return;
    fs.mkdirSync(out, { recursive: true });
    const box = await page.evaluate(() => { const ls = [...document.querySelectorAll(".cm-line.duo-codeblock")]; const a = ls[0].getBoundingClientRect(), z = ls[4].getBoundingClientRect(); return { x: a.left, y: a.top, width: a.width, height: z.bottom - a.top }; });
    await page.screenshot({ path: `${out}/${name}-${state}.png`, clip: box });
  };

  // At rest: the language, no button.
  let h = await head();
  if (h.length !== 2) fails.push(`two blocks, two heads (${h.length})`);
  if (h[0]?.lang !== "bash" || h[0]?.shown) fails.push(`at rest: the language and no button (${JSON.stringify(h[0])})`);
  if (h[0] && (h[0].right !== 10 || h[0].top !== 6)) fails.push(`at rest the language is 10 in and 6 down (${h[0].right}, ${h[0].top})`);
  if (h[1]?.lang !== null) fails.push("a block without a language shows none");
  await shot("resting");

  // The pointer on the block's last code line: the first block's head shows Copy, 6 in and 5 down.
  const lastLine = await page.evaluate(() => { const r = document.querySelectorAll(".cm-line.duo-codeblock")[2].getBoundingClientRect(); return { x: r.left + 40, y: r.top + r.height / 2 }; });
  await page.mouse.move(lastLine.x, lastLine.y);
  await page.waitForTimeout(100);
  h = await head();
  if (!h[0]?.shown || h[0].label !== "Copy" || h[0].aria !== "Copy code") fails.push(`hover: Copy shows (${JSON.stringify(h[0])})`);
  if (h[0] && (h[0].right !== 6 || h[0].top !== 5 || h[0].height !== 22)) fails.push(`hover: the head is 6 in, 5 down, the button 22 high (${h[0].right}, ${h[0].top}, ${h[0].height})`);
  if (h[1]?.shown) fails.push("hover: the other block's button stays hidden");
  await shot("hover");

  // Click: the code without fences goes to Duo; "Copied"; the caret doesn't move.
  const caret = await page.evaluate(() => V.state.selection.main.head);
  const btn = await page.evaluate(() => { const r = document.querySelector(".duo-code-copy").getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; });
  await page.mouse.move(btn.x, btn.y);
  await page.mouse.down(); await page.mouse.up();
  await page.waitForTimeout(50);
  const posted = await page.evaluate(() => window.__posted.filter((m) => m.kind === "copyCode"));
  if (posted.length !== 1 || posted[0].text !== code) fails.push(`click: the code, without fences, goes to Duo (${JSON.stringify(posted)})`);
  h = await head();
  if (h[0]?.label !== "Copied" || h[0]?.aria !== "Copied") fails.push(`click: the button reads Copied (${h[0]?.label})`);
  if (await page.evaluate(() => V.state.selection.main.head) !== caret) fails.push("click: the caret stayed where it was");
  if (await page.evaluate(() => V.state.doc.toString()) !== doc) fails.push("click: the document is unchanged");
  await shot("copied");

  // "Copied" holds while the pointer goes, then reads Copy again after about 1.5 s.
  await page.mouse.move(5, 5);
  await page.waitForTimeout(1000);
  h = await head();
  if (h[0]?.label !== "Copied" || !h[0]?.shown) fails.push(`1 s on: still Copied (${h[0]?.label})`);
  await page.waitForTimeout(700);
  h = await head();
  if (h[0]?.label !== "Copy" || h[0]?.shown) fails.push(`1.7 s on, pointer away: back to rest (${JSON.stringify(h[0])})`);

  // An empty block copies nothing but still answers; the caret on the fence hides the language, keeps Copy.
  await page.evaluate(() => V.dispatch({ selection: { anchor: V.state.doc.toString().indexOf("```bash") + 2 } }));
  await page.waitForTimeout(50);
  h = await head();
  if (h[0]?.lang !== null) fails.push("caret on the fence: the language hides (the fence shows raw)");
  await page.mouse.move(lastLine.x, lastLine.y);
  await page.waitForTimeout(50);
  if (!(await head())[0]?.shown) fails.push("caret on the fence: Copy still shows under the pointer");

  await b.close();
  for (const f of fails) console.log(`FAIL ${name}: ${f}`);
  console.log(`${name}: ${fails.length ? fails.length + " failed" : "all passed"}`);
  return fails.length;
}

let bad = 0;
if (which !== "webkit") bad += await run("chromium", () => chromium.launch({ executablePath: `${cache}/${shell}/chrome-headless-shell-mac-arm64/chrome-headless-shell` }));
if (which !== "chromium") bad += await run("webkit", () => webkit.launch());
process.exit(bad ? 1 : 0);
