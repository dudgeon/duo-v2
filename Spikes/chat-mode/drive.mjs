// Runs the real `claude` TUI in a PTY, mirrors it into a headless xterm, and plays a list of steps:
// {wait:"text"} {type:"text"} {key:"enter|esc|up|down|tab|space|ctrl-c|1"} {sleep:ms} {dump:"name"}
import pty from 'node-pty';
import xh from '@xterm/headless';
import fs from 'node:fs';
const [steps, out, ...args] = process.argv.slice(2);
if (!args.includes('--model')) args.push('--model', process.env.DUO_MODEL || 'claude-haiku-5-5');   // Haiku 5.5 unless asked (DL-153)
const cols = 100, rows = 34;
const term = new xh.Terminal({ cols, rows, allowProposedApi: true, scrollback: 2000 });
fs.mkdirSync(out, { recursive: true });
const raw = fs.createWriteStream(out + '/raw.bin');
const p = pty.spawn(process.env.CLAUDE_BIN || 'claude', args, { name: 'xterm-256color', cols, rows, cwd: process.cwd(), env: process.env });
p.onData(d => { raw.write(d); term.write(d); });
let exited = false; p.onExit(() => { exited = true; });
const screen = () => { const b = term.buffer.active; const L = []; for (let i = 0; i < rows; i++) L.push((b.getLine(b.viewportY + i)?.translateToString(true)) ?? ''); return L.join('\n'); };
const keys = { enter: '\r', esc: '\x1b', up: '\x1b[A', down: '\x1b[B', left: '\x1b[D', right: '\x1b[C', tab: '\t', 'shift-tab': '\x1b[Z', space: ' ', 'ctrl-c': '\x03', bs: '\x7f' };
const sleep = ms => new Promise(r => setTimeout(r, ms));
const t0 = Date.now();
const log = (s) => fs.appendFileSync(out + '/steps.log', `${((Date.now() - t0) / 1000).toFixed(2)} ${s}\n`);
for (const s of JSON.parse(fs.readFileSync(steps, 'utf8'))) {
  if (s.wait) { const re = new RegExp(s.wait); let ok = false; for (let i = 0; i < (s.timeout || 300); i++) { if (re.test(screen())) { ok = true; break; } await sleep(100); } log(`wait ${s.wait} ${ok ? 'ok' : 'TIMEOUT'}`); if (!ok) fs.writeFileSync(`${out}/timeout-${s.wait.replace(/\W/g, '')}.txt`, screen()); }
  if (s.type !== undefined) { p.write(s.paste ? `\x1b[200~${s.type}\x1b[201~` : s.type); log(`type ${JSON.stringify(s.type)}`); }
  if (s.key) { p.write(keys[s.key] ?? s.key); log(`key ${s.key}`); }
  if (s.sleep) await sleep(s.sleep);
  if (s.dump) { await sleep(400); fs.writeFileSync(`${out}/${s.dump}.txt`, screen()); log(`dump ${s.dump}`); }
  if (exited) { log('exited'); break; }
}
fs.writeFileSync(`${out}/final.txt`, screen());
p.kill(); setTimeout(() => process.exit(0), 300);
