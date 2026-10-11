// What Duo's element picker (Sources/DuoKit/Editor/HTMLPicker.swift, describe()) reports for one element,
// read in headless Chrome at an exact viewport (the right pane's width). Never shows a window.
// Usage: node pick.mjs <url> <css-selector> <width> <height> <out.json>
import { spawn } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
const [url, sel, w, h, out] = process.argv.slice(2);
const chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const prof = mkdtempSync(join(process.env.TMPDIR || tmpdir(), "pick."));
const proc = spawn(chrome, ["--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run", "--remote-debugging-port=0",
  `--user-data-dir=${prof}`, "about:blank"], { stdio: ["ignore", "ignore", "pipe"] });
const wsUrl = await new Promise((res, rej) => {
  let buf = ""; const t = setTimeout(() => rej(new Error("chrome did not start")), 15000);
  proc.stderr.on("data", d => { buf += d; const m = buf.match(/ws:\/\/\S+/); if (m) { clearTimeout(t); res(m[0]); } });
});
const ws = new WebSocket(wsUrl); await new Promise(r => ws.addEventListener("open", r));
let id = 0; const pending = new Map();
ws.addEventListener("message", e => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } });
const send = (method, params = {}, sessionId) => new Promise(r => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params, sessionId })); });
const { result: { targetId } } = await send("Target.createTarget", { url: "about:blank" });
const { result: { sessionId } } = await send("Target.attachToTarget", { targetId, flatten: true });
await send("Emulation.setDeviceMetricsOverride", { width: +w, height: +h, deviceScaleFactor: 1, mobile: false }, sessionId);
await send("Page.enable", {}, sessionId);
await send("Page.navigate", { url }, sessionId);
await new Promise(r => setTimeout(r, 1200));
// HTMLPicker.swift's selector(), label(), trail() and describe(), verbatim.
const js = `(() => {
  function selector(el) {
    const parts = [];
    for (let e = el; e && e.nodeType === 1 && e !== document.documentElement; e = e.parentElement) {
      if (e.id && /^[A-Za-z][\\w-]*$/.test(e.id) && document.querySelectorAll("#" + e.id).length === 1) { parts.unshift("#" + e.id); break; }
      let step = e.localName;
      const sibs = e.parentElement ? Array.from(e.parentElement.children).filter((s) => s.localName === e.localName) : [];
      if (sibs.length > 1) step += ":nth-child(" + (Array.from(e.parentElement.children).indexOf(e) + 1) + ")";
      parts.unshift(step);
    }
    return parts.join(" > ");
  }
  function label(el) {
    let s = el.localName;
    if (el.id) s += "#" + el.id;
    const cls = typeof el.className === "string" ? el.className.trim().split(/\\s+/).filter(Boolean).slice(0, 3) : [];
    if (cls.length) s += "." + cls.join(".");
    return s;
  }
  function trail(el) {
    const heads = Array.from(document.querySelectorAll("h1,h2,h3,h4,h5,h6"))
      .filter((h) => h !== el && (h.compareDocumentPosition(el) & Node.DOCUMENT_POSITION_FOLLOWING || h.contains(el)));
    const out = [];
    let level = 7;
    for (let i = heads.length - 1; i >= 0; i--) {
      const l = Number(heads[i].localName[1]);
      if (l < level) { out.unshift(heads[i].innerText.trim().slice(0, 80)); level = l; }
    }
    return out;
  }
  const KEEP = /^(id|class|href|src|alt|title|role|name|type|placeholder|value|for|action|method|aria-.*|data-.*)$/;
  const STYLES = ["display", "position", "color", "background-color", "font-family", "font-size", "font-weight", "line-height",
                  "padding", "margin", "border", "border-radius", "width", "height", "gap", "box-shadow"];
  const el = document.querySelector(${JSON.stringify(sel)});
  const cs = getComputedStyle(el);
  const styles = {};
  for (const p of STYLES) {
    const v = cs.getPropertyValue(p);
    if (v && !["none", "normal", "auto", "0px", "rgba(0, 0, 0, 0)", "static"].includes(v)) styles[p] = v.length > 120 ? v.slice(0, 120) + "…" : v;
  }
  const attributes = {};
  for (const a of Array.from(el.attributes)) if (KEEP.test(a.name) && a.name !== "class" && a.name !== "id") attributes[a.name] = a.value.slice(0, 200);
  const r = el.getBoundingClientRect();
  return JSON.stringify({ tag: el.localName, label: label(el), selector: selector(el), trail: trail(el),
    text: (el.innerText || el.textContent || "").trim().slice(0, 2000), attributes, styles,
    rect: [r.left + scrollX, r.top + scrollY, r.width, r.height], html: el.outerHTML.slice(0, 4000), title: document.title });
})()`;
const { result } = await send("Runtime.evaluate", { expression: js, returnByValue: true }, sessionId);
writeFileSync(out, JSON.stringify(JSON.parse(result.result.value), null, 1) + "\n");
ws.close();
const exited = new Promise(r => proc.on("exit", r)); proc.kill(); await exited;
await new Promise(r => setTimeout(r, 300));
try { rmSync(prof, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 }); } catch {}
