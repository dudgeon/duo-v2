// Headless Chrome screenshot at an exact CSS viewport (headless windows have a 500px minimum, so we use
// the DevTools protocol's device-metrics override). Never shows a window.
// Usage: node shot.mjs <url> <out.png> <width> <height> <scale>
import { spawn } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
const [url, out, w, h, scale] = process.argv.slice(2);
const chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const prof = mkdtempSync(join(process.env.TMPDIR || tmpdir(), "shot."));
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
await send("Emulation.setDeviceMetricsOverride", { width: +w, height: +h, deviceScaleFactor: +scale, mobile: false }, sessionId);
await send("Page.enable", {}, sessionId);
await send("Page.navigate", { url }, sessionId);
await new Promise(r => setTimeout(r, 1200));
const { result } = await send("Page.captureScreenshot", { format: "png" }, sessionId);
writeFileSync(out, Buffer.from(result.data, "base64"));
ws.close();
const exited = new Promise(r => proc.on("exit", r)); proc.kill(); await exited;
await new Promise(r => setTimeout(r, 300));
try { rmSync(prof, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 }); } catch {}
