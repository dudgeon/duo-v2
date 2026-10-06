// Chat mode proof of concept (spike, docs/plan/spikes/chat-mode.md). Runs the real interactive
// Claude Code TUI in a PTY and serves a page with the terminal beside a chat rendering of the
// same session. The chat comes from three read-only sources: per-session hooks (MessageDisplay
// streams the assistant's Markdown; PermissionRequest says what is being asked), the transcript
// JSONL (history), and the screen (which dialog is up, its exact options, the input box). Every
// answer goes back as keystrokes into the PTY, after re-checking that the screen still shows the
// dialog the human answered. Hooks print nothing, so they never decide anything.
//
//   node server.mjs [--mock] [--port 8780] [--cwd <dir>] [-- <extra claude args>]
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import pty from 'node-pty';
import xh from '@xterm/headless';
import { WebSocketServer } from 'ws';
import { classify } from './screen.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
const extra = argv.includes('--') ? argv.slice(argv.indexOf('--') + 1) : [];
const port = +opt('--port', 8780);
const cwd = path.resolve(opt('--cwd', process.cwd()));
const runDir = path.resolve(opt('--run', path.join(here, '.run')));
fs.mkdirSync(runDir, { recursive: true });
const cols = +opt('--cols', 100), rows = +opt('--rows', 34);

// Per-session hooks, as Duo writes them (HookEvents.swift): append each payload to a file.
const sessionId = crypto.randomUUID();
const events = path.join(runDir, `${sessionId}.events.jsonl`);
const names = ['SessionStart', 'SessionEnd', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'PostToolUseFailure',
  'PermissionRequest', 'PermissionDenied', 'Notification', 'Stop', 'StopFailure', 'SubagentStart', 'SubagentStop',
  'PreCompact', 'PostCompact', 'MessageDisplay'];
const q = s => `'${s.replace(/'/g, `'\\''`)}'`;
// One write(2) per event, with O_APPEND: hooks fire concurrently (the last MessageDisplay and
// Stop together), and printf from sh split ~1 KB payloads into pieces that interleaved (F-105).
const command = `perl -MTime::HiRes=time -e 'local $/; my $p = <STDIN>; $p =~ s/\\n//g; open(my $f, ">>", $ARGV[0]) or exit 0; syswrite($f, sprintf("{\\"at\\":%.3f,\\"e\\":%s}\\n", time, $p))' ${q(events)}`;
const settings = path.join(runDir, `${sessionId}.settings.json`);
fs.writeFileSync(settings, JSON.stringify({ hooks: Object.fromEntries(names.map(n => [n, [{ hooks: [{ type: 'command', command }] }]])) }, null, 1));

const env = { ...process.env, TERM: 'xterm-256color' };
for (const k of Object.keys(env)) if (k === 'CLAUDECODE' || (k.startsWith('CLAUDE_') && k !== 'CLAUDE_CONFIG_DIR')) delete env[k];
const args = ['--session-id', sessionId, '--settings', settings, ...extra];
const term = new xh.Terminal({ cols, rows, allowProposedApi: true, scrollback: 5000 });
const p = pty.spawn(process.env.CLAUDE_BIN || 'claude', args, { name: 'xterm-256color', cols, rows, cwd, env });
const clients = new Set();
const broadcast = m => { const s = JSON.stringify(m); for (const c of clients) c.readyState === 1 && c.send(s); };
const screenText = () => { const b = term.buffer.active; const L = []; for (let i = 0; i < rows; i++) L.push(b.getLine(b.viewportY + i)?.translateToString(true) ?? ''); return L.join('\n'); };
// The same screen with faint (dim) text blanked: the input box's placeholder ("Try …") is dim, and
// read as plain text it looks like something the user typed.
const solidText = () => { const b = term.buffer.active; const L = []; const cell = b.getNullCell();
  for (let i = 0; i < rows; i++) { const line = b.getLine(b.viewportY + i); let s = '';
    if (line) for (let x = 0; x < line.length; x++) { line.getCell(x, cell); const ch = cell.getChars(); if (cell.getWidth() === 0) continue; s += cell.isDim() ? ' '.repeat(ch.length || 1) : (ch || ' '); }
    L.push(s.trimEnd()); }
  return L.join('\n'); };
const read = () => classify(screenText(), solidText());

let screen = { kind: 'starting' }, screenTimer = null, ptyLog = [];
// Each new screen state, as text and as read, for comparing CLI versions and logins (F-105).
let dumps = 0, lastDumped = null;
const dumpDir = path.join(runDir, 'screens');
fs.mkdirSync(dumpDir, { recursive: true });
function dump(s) {
  const name = `${String(++dumps).padStart(3, '0')}-${s.kind}`;
  fs.writeFileSync(path.join(dumpDir, name + '.txt'), screenText());
  fs.appendFileSync(path.join(dumpDir, 'states.jsonl'), JSON.stringify({ at: Date.now() / 1000, name, s }) + '\n');
}
p.onData(d => {
  term.write(d, () => {
    clearTimeout(screenTimer);
    // The TUI repaints in bursts; read the screen once it settles.
    screenTimer = setTimeout(() => { const s = read(); if (JSON.stringify(s) !== JSON.stringify(screen)) { screen = s; broadcast({ t: 'screen', s, at: Date.now() / 1000 }); if (s.kind !== lastDumped) { lastDumped = s.kind; dump(s); } } }, 60);
  });
  ptyLog.push(d); if (ptyLog.length > 4000) ptyLog = ptyLog.slice(-2000);
  broadcast({ t: 'pty', d });
});
p.onExit(() => { broadcast({ t: 'exit' }); setTimeout(() => process.exit(0), 500); });

// Tail a growing JSONL file; whole lines only.
function tail(file, onRecord, fromStart = true) {
  let pos = 0, buf = '';
  const tick = () => {
    let st; try { st = fs.statSync(file); } catch { return; }
    if (st.size < pos) pos = 0;
    if (st.size === pos) return;
    const fd = fs.openSync(file, 'r'); const b = Buffer.alloc(st.size - pos); fs.readSync(fd, b, 0, b.length, pos); fs.closeSync(fd);
    pos = st.size; buf += b.toString('utf8');
    let i; while ((i = buf.indexOf('\n')) >= 0) { const l = buf.slice(0, i); buf = buf.slice(i + 1); try { onRecord(JSON.parse(l)); } catch {} }
  };
  if (!fromStart) try { pos = fs.statSync(file).size; } catch {}
  return setInterval(tick, 50);
}

const history = [];   // everything sent to the page, replayed to late joiners
const send = m => { history.push(m); broadcast(m); };
let transcriptTail = null;
tail(events, ({ at, e }) => {
  send({ t: 'hook', at, e });
  if (e.hook_event_name === 'SessionStart' && e.transcript_path && !transcriptTail)
    transcriptTail = tail(e.transcript_path, r => send({ t: 'record', r, at: Date.now() / 1000 }));
});

// Input from the page. Every path ends in PTY keystrokes; nothing answers on the human's behalf.
const KEYS = { enter: '\r', esc: '\x1b', up: '\x1b[A', down: '\x1b[B', left: '\x1b[D', right: '\x1b[C', tab: '\t', space: ' ', 'shift-tab': '\x1b[Z' };
const sleep = ms => new Promise(r => setTimeout(r, ms));
async function keys(list) { for (const k of list) { p.write(KEYS[k] ?? k); await sleep(80); } }
function fresh() { return read(); }

async function handle(ws, m) {
  const reply = r => ws.send(JSON.stringify({ t: 'result', id: m.id, ...r }));
  if (m.t === 'raw') return p.write(m.d);                         // the terminal pane's own typing
  if (m.t === 'resize') { p.resize(m.cols, m.rows); term.resize(m.cols, m.rows); return; }
  const now = fresh();
  if (m.t === 'send') {
    // Paste only into an empty input box; anything already typed there would be glued on.
    if (!['idle', 'busy'].includes(now.kind)) return reply({ ok: false, fallback: true, why: `the terminal is showing ${now.kind}` });
    if (now.input) return reply({ ok: false, fallback: true, why: `Claude's input already holds "${now.input.slice(0, 40)}"` });
    p.write(`\x1b[200~${m.text}\x1b[201~`); await sleep(150);
    const echoed = fresh();
    if (!echoed.input || echoed.input.replace(/\s+/g, ' ').trim() !== m.text.replace(/\s+/g, ' ').trim().slice(0, echoed.input.replace(/\s+/g, ' ').trim().length))
      return reply({ ok: false, fallback: true, why: 'the pasted text did not appear as sent' });
    p.write('\r'); return reply({ ok: true });
  }
  if (m.t === 'answer') {
    // The human picked an option on a card drawn from an earlier screen. Re-read it now: the
    // same dialog must still be up, or nothing is sent.
    if (now.sig !== m.sig) return reply({ ok: false, fallback: true, why: 'the question changed before your answer arrived' });
    await keys(m.keys);
    if (m.text) { p.write(m.text); await sleep(80); }
    if (m.then) await keys(m.then);
    return reply({ ok: true });
  }
  if (m.t === 'interrupt') { await keys(['esc']); return reply({ ok: true }); }
  if (m.t === 'mode') { await keys(['shift-tab']); return reply({ ok: true }); }
}

const server = http.createServer((req, res) => {
  const f = req.url === '/' ? 'index.html' : req.url.slice(1);
  const map = { 'index.html': path.join(here, 'index.html'), 'xterm.js': path.join(here, 'node_modules/@xterm/xterm/lib/xterm.js'), 'xterm.css': path.join(here, 'node_modules/@xterm/xterm/css/xterm.css'), 'marked.js': path.join(here, 'node_modules/marked/lib/marked.umd.js') };
  if (!map[f]) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'content-type': f.endsWith('.js') ? 'text/javascript' : f.endsWith('.css') ? 'text/css' : 'text/html' });
  fs.createReadStream(map[f]).pipe(res);
});
new WebSocketServer({ server }).on('connection', ws => {
  clients.add(ws);
  ws.send(JSON.stringify({ t: 'hello', sessionId, cols, rows, pty: ptyLog.join(''), screen, history }));
  ws.on('message', d => { try { handle(ws, JSON.parse(d)); } catch {} });
  ws.on('close', () => clients.delete(ws));
});
server.listen(port, '127.0.0.1', () => console.log(`chat mode PoC on http://127.0.0.1:${port}  session ${sessionId}`));
process.on('SIGTERM', () => { p.kill(); process.exit(0); });
