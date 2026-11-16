// View › Source (DL-346): a Markdown document's source is highlighted with the five syntax tokens; an HTML page opens as
// highlighted, editable source (HTML, CSS and JavaScript) and only ever source; the formatting bar's page side (Markdown) is
// untouched. Writes captures of both, in the scheme named by DUO_SCHEME (light | dark | classic).
//   node scripts/check-editor-view-source.mjs [dir with editor.html and cm6.js] [chromium|webkit|both] [capture dir]
// Needs playwright-core (NODE_PATH) with Chromium headless shell and WebKit installed.
import fs from "fs";
import { createRequire } from "module";
import { addTypeVars } from "./editor-vars.mjs";
const require = createRequire(import.meta.url);
const { chromium, webkit } = require("playwright-core");
const dist = (process.argv[2] || "Vendor/codemirror/dist").replace(/^(?!\/)/, process.cwd() + "/");
const which = process.argv[3] || "both";
const out = process.argv[4];
const scheme = process.env.DUO_SCHEME || "light";
const cache = process.env.PLAYWRIGHT_BROWSERS_PATH || process.env.HOME + "/Library/Caches/ms-playwright";
const shell = fs.readdirSync(cache).filter((d) => d.startsWith("chromium_headless_shell-")).sort().pop();

// The tokens, from tokens.json: the page gets exactly what the app sets.
const tk = JSON.parse(fs.readFileSync(new URL("../docs/design/build-handoff/tokens.json", import.meta.url), "utf8")).color;
const kebab = (k) => k.replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase();
const pick = (name) => (tk[scheme]?.[name] || tk.light[name]).value;
const names = ["ground", "pane", "selected", "rule", "controlEdge", "text", "text2", "needsYou", "syntaxTag", "syntaxAttr", "syntaxString", "syntaxComment", "syntaxMark", "reviewAuthor1", "reviewAuthor3"];
const tokens = names.map((n) => `--duo-${n.startsWith("reviewAuthor") ? "review-" + n.slice(12) : kebab(n)}:${(scheme === "dark" ? tk.dark[n] : scheme === "classic" ? tk.classic[n] : null)?.value || pick(n)}`).join(";") + ";--duo-radius-card:8px;--duo-heading-above:4px;";
const rgb = (hex) => { const n = parseInt(hex.slice(1), 16); return `rgb(${n >> 16}, ${(n >> 8) & 255}, ${n & 255})`; };
const want = (n) => rgb((scheme === "dark" ? tk.dark[n] : scheme === "classic" ? tk.classic[n] : null)?.value || tk.light[n].value);

const HTML = `<style>
  .up { color: #2f7d32; }
</style>
<h1>Refunds, Q3</h1>
<p class="lede">Down <span class="up">12%</span> since July.</p>
<!-- by reason -->
<script>
  const rows = "41,28,17".split(",");
</script>
`;
const MD = `---
status: draft
---
# Refunds review
Fell **12%** {++in Q3++}, see [export](q3.csv)
- \`refunds.sql\` {>>@geoff #c2: rerun <<}
`;

async function run(name, launch) {
  const fails = [];
  const ok = (cond, msg) => { if (!cond) fails.push(msg); };
  const b = await launch();
  const page = await b.newPage({ viewport: { width: 460, height: 420 }, deviceScaleFactor: 2 });
  await page.addInitScript(() => { window.duoFlags = { noPost: true }; });
  await page.goto("file://" + dist + "/editor.html");
  await addTypeVars(page);
  await page.evaluate((t) => document.documentElement.setAttribute("style", t), tokens);
  const shot = async (file) => { if (out) { fs.mkdirSync(out, { recursive: true }); await page.screenshot({ path: `${out}/${file}.png` }); } };
  // The computed colour of the first element whose own text is exactly `text`.
  const colourOf = (text) => page.evaluate((t) => {
    const w = document.createTreeWalker(document.querySelector(".cm-content"), NodeFilter.SHOW_TEXT);
    for (let n = w.nextNode(); n; n = w.nextNode()) if (n.nodeValue === t) return getComputedStyle(n.parentElement).color;
    return null;
  }, text);

  // HTML: only ever source, mono, highlighted.
  await page.evaluate(([id, t]) => duo.show(id, t, { kind: "html" }), ["/q3.html", HTML]);
  await page.waitForTimeout(250);
  ok((await page.evaluate(() => duo.source())) === true, "an HTML page is in source");
  ok(!(await page.evaluate(() => !!document.querySelector(".duo-table, .duo-h, .duo-task, .duo-fm-head"))), "no live-preview widget on an HTML page");
  const mono = await page.evaluate(() => getComputedStyle(document.querySelector(".cm-content")).fontFamily);
  ok(/mono|menlo|courier/i.test(mono), `HTML source is set in the mono face (${mono})`);
  ok((await colourOf("\"lede\"")) === want("syntaxString"), `an attribute value is syntaxString: ${await colourOf("\"lede\"")}`);
  ok((await colourOf("class")) === want("syntaxAttr"), `an attribute name is syntaxAttr: ${await colourOf("class")}`);
  ok((await colourOf("h1")) === want("syntaxTag"), `a tag name is syntaxTag: ${await colourOf("h1")}`);
  ok((await colourOf("<!-- by reason -->")) === want("syntaxComment"), `a comment is syntaxComment: ${await colourOf("<!-- by reason -->")}`);
  ok((await colourOf("color")) === want("syntaxAttr"), `a CSS property is syntaxAttr: ${await colourOf("color")}`);
  ok((await colourOf("const")) === want("syntaxTag"), `a JS keyword is syntaxTag: ${await colourOf("const")}`);
  ok((await page.evaluate(() => duo.setSource(false))) === true && (await page.evaluate(() => duo.source())) === true, "turning source off does nothing to an HTML page");
  await page.evaluate(() => { const V = document.querySelector(".cm-content").cmTile.view; V.focus(); V.dispatch({ selection: { anchor: V.state.doc.length } }); });
  await page.keyboard.type("<b>x</b>");
  ok((await page.evaluate(() => duo.text())).includes("<b>x"), "an HTML page's source is editable");
  await shot(`source-html-${scheme}-${name}`);

  // Markdown, in source: its marks, links, code and frontmatter take the tokens; the text is untouched.
  await page.evaluate(([id, t]) => duo.show(id, t, { source: true, kind: "markdown" }), ["/r.md", MD]);
  await page.waitForTimeout(250);
  ok((await page.evaluate(() => duo.text())) === MD, "the source text is as typed");
  ok((await colourOf("status")) === want("syntaxAttr"), `a frontmatter key is syntaxAttr: ${await colourOf("status")}`);
  ok(await page.evaluate(() => { const w = document.createTreeWalker(document.querySelector(".cm-content"), NodeFilter.SHOW_TEXT); for (let n; (n = w.nextNode());) if (n.nodeValue === "status") return getComputedStyle(n.parentElement).fontWeight === "400"; return false; }), "a frontmatter key is not bold");
  ok((await colourOf("draft")) === want("syntaxString"), `a frontmatter value is syntaxString: ${await colourOf("draft")}`);
  ok((await colourOf("q3.csv")) === want("syntaxString"), `a link target is syntaxString: ${await colourOf("q3.csv")}`);
  ok((await colourOf("export")) === want("syntaxTag"), `a link's text is syntaxTag: ${await colourOf("export")}`);
  ok((await colourOf("in Q3")) === want("reviewAuthor3"), `an addition is green: ${await colourOf("in Q3")}`);
  ok((await colourOf("@geoff #c2: rerun ")) === want("reviewAuthor1"), `a comment is red: ${await colourOf("@geoff #c2: rerun ")}`);
  ok(!(await colourOf("Fell ")) || (await colourOf("Fell ")) !== want("syntaxTag"), "plain text stays the text colour");
  await shot(`source-md-${scheme}-${name}`);

  // The page side of a Markdown document draws no source colours.
  await page.evaluate(() => duo.setSource(false));
  await page.waitForTimeout(150);
  ok((await page.evaluate(() => duo.source())) === false, "Markdown goes back to its page");
  ok(!(await page.evaluate(() => !!document.querySelector(".duo-src-attr, .duo-src-mark"))), "no source marks on the page side");

  console.log(fails.length ? fails.map((f) => `${name}: ${f}`).join("\n") : `${name}: PASS`);
  await b.close();
  return fails.length;
}
let bad = 0;
if (which !== "webkit") bad += await run("chromium", () => chromium.launch({ executablePath: `${cache}/${shell}/chrome-headless-shell-mac-arm64/chrome-headless-shell` }));
if (which !== "chromium") bad += await run("webkit", () => webkit.launch());
process.exit(bad ? 1 : 0);
