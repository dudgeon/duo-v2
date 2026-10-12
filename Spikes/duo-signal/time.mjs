// The duo-signal spike's clock (ENH-70): drive.mjs's steps against the real `claude` TUI, plus a
// 10 ms sampler that logs when the screen and the mod's signal file each change their mind about
// busy, the dialog and the mode. Copy beside the chat-mode spike's node_modules to run (run.sh does).
//   node time.mjs <steps.json> <out> [claude args...]      DUO_SIGNAL_FILE names the signal file
import pty from 'node-pty';
import xh from '@xterm/headless';
import fs from 'node:fs';
const [steps, out, ...args] = process.argv.slice(2);
if (!args.includes('--model')) args.push('--model', process.env.DUO_MODEL || 'claude-haiku-5-5');
const cols = 100, rows = 34;
const term = new xh.Terminal({ cols, rows, allowProposedApi: true, scrollback: 2000 });
fs.mkdirSync(out, { recursive: true });
const p = pty.spawn(process.env.CLAUDE_BIN || 'claude', args, { name: 'xterm-256color', cols, rows, cwd: process.cwd(), env: process.env });
p.onData(d => term.write(d));
let exited = false; p.onExit(() => { exited = true; });
const screen = () => { const b = term.buffer.active; const L = []; for (let i = 0; i < rows; i++) L.push((b.getLine(b.viewportY + i)?.translateToString(true)) ?? ''); return L.join('\n'); };
const keys = { enter: '\r', esc: '\x1b', up: '\x1b[A', down: '\x1b[B', tab: '\t', 'shift-tab': '\x1b[Z', space: ' ', 'ctrl-c': '\x03' };
const sleep = ms => new Promise(r => setTimeout(r, ms));
const t0 = Date.now();
const stamp = () => ((Date.now() - t0) / 1000).toFixed(3);
const log = s => fs.appendFileSync(out + '/timeline.log', `${stamp()} ${s}\n`);

// What the screen says, read the way chat reads it (footer below the last rule; F-281).
function readScreen() {
  const L = screen().split('\n');
  const rule = L.findLastIndex(l => /^─{20,}/.test(l));
  const foot = rule >= 0 ? L.slice(rule + 1).filter(l => !l.startsWith('⚠')).join('\n') : '';
  const all = L.join('\n');
  return {
    busy: /esc to interrupt/.test(foot),
    dialog: /Do you want to|Enter to select · |Would you like to proceed/.test(all) ? (/Enter to select · /.test(all) ? 'question' : 'permission') : null,
    mode: (foot.match(/(plan mode on|accept edits on|manual mode on|auto mode on|bypass permissions on)/g) || []).pop() || null,
  };
}
function readSignal() {
  try {
    const s = JSON.parse(fs.readFileSync(process.env.DUO_SIGNAL_FILE, 'utf8'));
    return { busy: s.busy, question: s.question?.tool ?? null, modes: JSON.stringify(s.modes), working: s.working, draft: s.draft, alive: s.at };
  } catch { return null; }
}
const last = {};
const note = (k, v) => { const j = JSON.stringify(v); if (last[k] !== j) { last[k] = j; log(`${k} ${j}`); } };
const sampler = setInterval(() => {
  const s = readScreen();
  note('screen.busy', s.busy); note('screen.dialog', s.dialog); note('screen.mode', s.mode);
  const g = readSignal();
  if (g) { note('signal.busy', g.busy); note('signal.question', g.question); note('signal.modes', g.modes); note('signal.working', g.working); note('signal.draft', g.draft); }
  else note('signal', 'none');
}, 10);

for (const s of JSON.parse(fs.readFileSync(steps, 'utf8'))) {
  if (s.wait) { const re = new RegExp(s.wait); let ok = false; for (let i = 0; i < (s.timeout || 300); i++) { if (re.test(screen())) { ok = true; break; } await sleep(100); } log(`step wait ${s.wait} ${ok ? 'ok' : 'TIMEOUT'}`); }
  if (s.type !== undefined) { p.write(s.type); log(`step type ${JSON.stringify(s.type)}`); }
  if (s.key) { p.write(keys[s.key] ?? s.key); log(`step key ${s.key}`); }
  if (s.sleep) await sleep(s.sleep);
  if (s.dump) { fs.writeFileSync(`${out}/${s.dump}.txt`, screen()); log(`step dump ${s.dump}`); }
  if (exited) { log('exited'); break; }
}
clearInterval(sampler);
fs.writeFileSync(`${out}/final.txt`, screen());
p.kill(); setTimeout(() => process.exit(0), 300);
