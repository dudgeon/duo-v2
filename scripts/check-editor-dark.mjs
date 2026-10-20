// The editor page in the dark appearance (DL-224), in WebKit at the right pane's width: the page's CSS
// variables set to color.dark from tokens.json, a document with a change of Claude's, a table, code
// and a task. Checks the computed colours the handoff names, and writes a capture.
//   node scripts/check-editor-dark.mjs [capture dir]
// Needs playwright-core (NODE_PATH) with WebKit installed.
import fs from "fs";
import { createRequire } from "module";
const require = createRequire(import.meta.url);
const { webkit } = require("playwright-core");
const root = new URL("..", import.meta.url).pathname;
const t = JSON.parse(fs.readFileSync(root + "docs/design/build-handoff/tokens.json", "utf8"));
const dark = t.color.dark, width = t.size.pane.project.right;
const out = process.argv[2];
const v = (k) => dark[k].value;
const vars = [["pane", "pane"], ["text", "text"], ["text2", "text2"], ["selected", "selected"], ["claude-edit", "claudeEdit"], ["rule", "rule"],
  ["control-edge", "controlEdge"], ["ground", "ground"], ["needs-you", "needsYou"]].map(([c, k]) => `--duo-${c}:${v(k)};`).join("")
  + "--duo-shadow:rgba(0, 0, 0, 0.5);--duo-radius-card:8px;--duo-heading-above:4px;--duo-motion-highlight-in-ms:0;--duo-motion-highlight-out-ms:0;";
const doc = `---\ntitle: Release plan\nstatus: open\n---\n\n# Release plan\n\nCut guest-checkout abandonment 15% by Q1.\n\n- [ ] A task\n- [x] Done task\n\n| Path | Limit |\n|---|---|\n| a | 1 |\n\n\`\`\`js\nconst a = 1;\n\`\`\`\n`;
const fails = [];
const ok = (c, m) => { if (!c) fails.push(m); };
const rgb = (hex) => { const n = parseInt(hex.slice(1), 16); return `rgb(${n >> 16}, ${(n >> 8) & 255}, ${n & 255})`; };
const cache = process.env.PLAYWRIGHT_BROWSERS_PATH || process.env.HOME + "/Library/Caches/ms-playwright";
const b = await webkit.launch();
const page = await b.newPage({ viewport: { width, height: 640 }, deviceScaleFactor: 2 });
await page.goto("file://" + root + "Vendor/codemirror/dist/editor.html");
await page.evaluate(([css, d]) => { document.documentElement.setAttribute("style", css); duo.create(d); }, [vars, doc]);
await page.waitForTimeout(300);
await page.evaluate(() => duo.agentReplace("Cut guest-checkout", "Halve guest-checkout"));
await page.waitForTimeout(300);
const c = (sel, prop) => page.evaluate(([s, p]) => { const e = document.querySelector(s); return e ? getComputedStyle(e)[p] : null; }, [sel, prop]);
ok(await c("body", "backgroundColor") === rgb(v("pane")), `the page is on pane: ${await c("body", "backgroundColor")}`);
ok(await c(".cm-content", "color") === rgb(v("text")), `text is text: ${await c(".cm-content", "color")}`);
ok(await c(".duo-added", "backgroundColor") === rgb(v("claudeEdit")), `Claude's change is on claudeEdit: ${await c(".duo-added", "backgroundColor")}`);
const raw = await page.evaluate(() => [...document.styleSheets].flatMap((s) => { try { return [...s.cssRules].map((r) => r.cssText); } catch { return []; } }).join("\n"));
ok(!/rgba\(31, 35, 40/.test(raw), "no light-only shadow colour is left in the page's styles");
if (out) { fs.mkdirSync(out, { recursive: true }); await page.screenshot({ path: `${out}/editor-dark.png` }); }
await b.close();
if (fails.length) { console.error("FAIL\n" + fails.join("\n")); process.exit(1); }
console.log("editor dark: ok");
