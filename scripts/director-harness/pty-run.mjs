// Runs an interactive `claude` in a PTY for the harness: types one prompt, waits, saves the screen.
//   CLAUDE_BIN=… node pty-run.mjs <out-dir> <seconds> "<prompt>" [claude args…]
// NODE_PATH must reach node-pty and @xterm/headless (the harness installs them in its scratch folder).
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire((process.env.NODE_PATH || '.') + '/');   // ESM ignores NODE_PATH
const pty = require('node-pty');
const xh = require('@xterm/headless');
const [out, secs, prompt, ...args] = process.argv.slice(2);
const cols = 110, rows = 40;
const term = new xh.Terminal({ cols, rows, allowProposedApi: true, scrollback: 4000 });
fs.mkdirSync(out, { recursive: true });
const p = pty.spawn(process.env.CLAUDE_BIN || 'claude', args, { name: 'xterm-256color', cols, rows, cwd: process.cwd(), env: process.env });
p.onData(d => term.write(d));
let exited = false; p.onExit(() => { exited = true; });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const screen = () => { const b = term.buffer.active; const L = []; for (let i = 0; i < b.length; i++) L.push(b.getLine(i)?.translateToString(true) ?? ''); return L.join('\n').replace(/\n+$/, ''); };
for (let i = 0; i < 100 && !/[>❯]\s/.test(screen()); i++) await sleep(100);
await sleep(500);
p.write(prompt); await sleep(300); p.write('\r');
const end = Date.now() + secs * 1000;
while (Date.now() < end && !exited) { await sleep(500); fs.writeFileSync(out + '/screen.txt', screen()); }
fs.writeFileSync(out + '/screen.txt', screen());
p.kill(); setTimeout(() => process.exit(0), 300);
