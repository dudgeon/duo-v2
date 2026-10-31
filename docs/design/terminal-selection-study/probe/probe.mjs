// Feeds Claude Code's prompt box one byte string at a time and reads back what it did.
// node probe.mjs <claude-bin> <kitty|legacy> <cases.json> <out.json>
// Each case: the prompt is cleared, three lines are typed, the cursor is put at a known place
// ("delta epsil|on zeta", line 2), the case's bytes are sent, then a marker "¶" is typed and the box read.
import pty from 'node-pty';
import xh from '@xterm/headless';
import fs from 'node:fs';
const [bin, mode, casesPath, outPath] = process.argv.slice(2);
const cols = 90, rows = 30;
const term = new xh.Terminal({ cols, rows, allowProposedApi: true, scrollback: 500 });
const p = pty.spawn(bin, ['--model', 'claude-haiku-5-5'], { name: 'xterm-256color', cols, rows, cwd: process.env.WS, env: process.env });
let flags = 0, pushes = [];
p.onData(d => {
  if (mode === 'kitty') {
    if (d.includes('\x1b[?u')) p.write(`\x1b[?${flags}u`);
    const m = [...d.matchAll(/\x1b\[>(\d+)u/g)]; for (const x of m) { flags = +x[1]; pushes.push(x[0]); }
    if (/\x1b\[<u/.test(d)) pushes.push('pop');
  }
  for (const x of d.matchAll(/\x1b\[\?([\d;]+)([hl])/g)) modes.add(x[1] + x[2]);
  term.write(d);
});
const modes = new Set();
process.on('exit', () => { if (process.env.MODES_OUT) fs.writeFileSync(process.env.MODES_OUT, JSON.stringify([...modes])); });
term.onData(d => p.write(d));   // DA1 and other replies, as a real terminal answers
const sleep = ms => new Promise(r => setTimeout(r, ms));
const screen = () => { const b = term.buffer.active; const L = []; for (let i = 0; i < rows; i++) L.push((b.getLine(b.viewportY + i)?.translateToString(true)) ?? ''); return L; };
const box = () => {   // lines between the last two full rules
  const L = screen(); const r = []; L.forEach((l, i) => { if (/^─{20,}/.test(l.trim())) r.push(i); });
  if (r.length < 2) return { box: null, screen: L.join('\n') };
  const a = r[r.length - 2], b = r[r.length - 1];
  return { box: L.slice(a + 1, b).map(s => s.replace(/\s+$/, '')), below: L.slice(b + 1).filter(s => s.trim()).slice(0, 3) };
};
const nl = mode === 'kitty' ? '\x1b[13;2u' : '\x1b\r';
for (let i = 0; i < 200; i++) { if (/[>❯]\s/.test(screen().join('\n')) && screen().some(l => /^─{20,}/.test(l.trim()))) break; await sleep(100); }
await sleep(1500);
const cases = JSON.parse(fs.readFileSync(casesPath, 'utf8'));
const results = { bin, mode, pushes: null, cases: [] };
const write = s => p.write(s);
for (const c of cases) {
  for (const k of ['\x1b', '\x1b']) { write(k); await sleep(150); }
  write('\x15\x15\x15'); await sleep(100);      // ^U clears a line at a time
  if (process.env.VIM) { write('i'); await sleep(150); }
  write('\x0c'); await sleep(250);              // ^L clears the input (chat:clearInput)
  write('alpha beta gamma'); write(nl); write('delta epsilon zeta'); write(nl); write('eta theta iota');
  await sleep(250);
  write('\x1b[A'); await sleep(120); write('\x1b[D\x1b[D'); await sleep(200);
  const before = box();
  for (const b of c.bytes) { write(b); await sleep(c.gap || 150); }
  await sleep(250);
  write('¶'); await sleep(400);
  const after = box();
  results.cases.push({ name: c.name, bytes: c.bytes.map(b => JSON.stringify(b)), before: before.box, after: after.box, below: after.below, screen: after.screen });
  process.stderr.write('.');
}
results.pushes = pushes;
fs.writeFileSync(outPath, JSON.stringify(results, null, 1));
p.kill(); setTimeout(() => process.exit(0), 300);
