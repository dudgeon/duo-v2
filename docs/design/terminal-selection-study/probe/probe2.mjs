// The riskiest assumption, headless: Duo can map Claude's input box cells and its caret to offsets in the
// prompt's exact text, and turn a selection into keys that edit exactly that text.
// node probe2.mjs <claude-bin> <cases.json> <out.json>   (kitty mode: answers CSI ? u as SwiftTerm does)
// A case: {name, setup:[{type}|{paste}|{nl}|{keys}], ops:[{keys, gap}|{snap:name}|{select:{from,to}}]}
import pty from 'node-pty';
import xh from '@xterm/headless';
import fs from 'node:fs';
const [bin, casesPath, outPath] = process.argv.slice(2);
const cols = +(process.env.COLS || 60), rows = 30;
const term = new xh.Terminal({ cols, rows, allowProposedApi: true, scrollback: 500 });
const p = pty.spawn(bin, ['--model', 'claude-haiku-5-5'], { name: 'xterm-256color', cols, rows, cwd: process.env.WS, env: process.env });
let flags = 0; const osc52 = []; let altToggles = 0, clears = 0;
p.onData(d => {
  if (d.includes('\x1b[?u')) p.write(`\x1b[?${flags}u`);
  for (const x of d.matchAll(/\x1b\[>(\d+)u/g)) flags = +x[1];
  altToggles += (d.match(/\x1b\[\?1049[hl]/g) || []).length; clears += (d.match(/\x1b\[2J/g) || []).length;
  for (const x of d.matchAll(/\x1b\]52;[^;]*;([A-Za-z0-9+/=]*)(\x07|\x1b\\)/g)) osc52.push(Buffer.from(x[1], 'base64').toString('utf8'));
  term.write(d);
});
term.onData(d => p.write(d));
const sleep = ms => new Promise(r => setTimeout(r, ms));
const screen = () => { const b = term.buffer.active; const L = []; for (let i = 0; i < rows; i++) L.push((b.getLine(b.viewportY + i)?.translateToString(true)) ?? ''); return L; };
// The box as InputBoxFinder finds it: the lowest rule pair with the prompt marker under the top one.
function box() {
  const L = screen(); const isRule = l => /[─━]{8,}/.test(l);
  for (let b = L.length - 1; b >= 2; b--) {
    if (!isRule(L[b])) continue;
    let t = b - 1; while (t >= 0 && !isRule(L[t])) t--;
    if (t < 0 || !/^\s*[❯>›]/.test(L[t + 1] || '')) continue;
    const buf = term.buffer.active;
    return { top: t + 1, bottom: b - 1, rows: L.slice(t + 1, b), cursor: { row: buf.cursorY - (t + 1), col: buf.cursorX }, screen: L };
  }
  return null;
}
// Cells of a box row, wide characters taking two cells (xterm's own cell widths).
function cells(r) {
  const line = term.buffer.active.getLine(term.buffer.active.viewportY + r); const out = [];
  for (let x = 0; x < cols; x++) { const c = line.getCell(x); if (!c) break; if (c.getWidth() === 0) continue; out.push({ x, ch: c.getChars() || ' ', w: c.getWidth(), hi: !!(c.isInverse() || c.getBgColorMode()), bg: c.getBgColorMode() ? [c.getBgColorMode(), c.getBgColor()] : null, fg: c.getFgColorMode() ? [c.getFgColorMode(), c.getFgColor()] : null, inv: c.isInverse() }); }
  return out;
}
const nl = '\x1b[13;2u';
// --- What Duo would do (strategy B's core) ---
const seg = new Intl.Segmenter(undefined, { granularity: 'grapheme' });
const units = (text) => {   // graphemes, a paste or image placeholder as one unit (Claude moves over it whole)
  const out = []; const re = /\[(Pasted text #\d+[^\]]*|Image #\d+)\]/g; let last = 0, m;
  while ((m = re.exec(text))) { for (const g of seg.segment(text.slice(last, m.index))) out.push(g.segment); out.push(m[0]); last = m.index + m[0].length; }
  for (const g of seg.segment(text.slice(last))) out.push(g.segment);
  return out;
};
// Aligns the prompt's exact text (in units) with the box's cells: cell → unit index. Soft wraps drop or keep a space,
// a hard new line is a "\n" unit consumed at a row's start.
function align(u, b) {
  const map = []; let pos = 0;
  for (let i = 0; i < b.rows.length; i++) {
    const cs = b.cells[i].filter(c => c.x >= 2); let lastInk = -1; cs.forEach((c, k) => { if (c.ch.trim()) lastInk = k; });
    if (i > 0) { let q = pos; while (u[q] === ' ') q++; if (u[q] === '\n') pos = q + 1; else if (q > pos && u[q] && cs[0]?.ch === u[q][0]) pos = q; }
    const rowMap = [];
    for (let k = 0; k <= lastInk && pos <= u.length; k++) {
      const c = cs[k], un = u[pos];
      if (un === undefined) break;
      // A paste placeholder on screen stands for text Ctrl+G hands over in full: one unit, as Claude moves over it.
      // It ends where the cells after it match the text again.
      const rowText = cs.slice(k, lastInk + 1).map(z => z.ch).join('');
      const ph = rowText.match(/^\[Pasted text #\d+[^\]]*\]/);
      if (ph && !u.slice(pos, pos + ph[0].length).join('').startsWith(ph[0])) {
        const after = cs.slice(k + ph[0].length, lastInk + 1).map(z => z.ch).join('');
        const rest = u.slice(pos).join(''); let cut = after ? rest.lastIndexOf(after.trimEnd()) : rest.length;
        if (cut < 0) return { ok: false, at: { row: i, placeholder: ph[0] } };
        // Collapse the pasted run into one unit in place.
        let n = 0, len = 0; while (len < cut) { len += u[pos + n].length; n++; }
        u.splice(pos, n, u.slice(pos, pos + n).join(''));
        for (let j = 0; j < ph[0].length; j++) rowMap.push({ x: cs[k + j].x, pos });
        k += ph[0].length - 1; pos++; continue;
      }
      // A cluster xterm splits over cells (ZWJ emoji): take cells until the unit is whole.
      if (un !== c.ch && un.startsWith(c.ch) && c.ch) {
        let acc = c.ch, j = k; rowMap.push({ x: c.x, pos });
        while (acc !== un && j < lastInk && un.startsWith(acc + cs[j + 1].ch)) { j++; acc += cs[j].ch; rowMap.push({ x: cs[j].x, pos }); }
        if (acc === un) { k = j; pos++; continue; }
      }
      if (c.ch === un || (c.ch === ' ' && un === ' ')) { rowMap.push({ x: c.x, pos }); pos++; }
      else return { ok: false, at: { row: i, x: c.x, cell: c.ch, unit: un, pos } };
    }
    map.push({ rowMap, end: pos });
  }
  return { ok: true, map, consumed: pos, total: u.length };
}
function caretOffset(al, cur) {
  const r = al.map[cur.row]; if (!r) return null;
  const hit = r.rowMap.find(m => m.x === cur.col); if (hit) return hit.pos;
  const before = r.rowMap.filter(m => m.x < cur.col); return before.length ? before[before.length - 1].pos + 1 : (cur.row > 0 ? al.map[cur.row - 1].end : 0);
}
const PEEK = process.env.PEEK_OUT;
async function peek() {
  try { fs.unlinkSync(PEEK); } catch {}
  p.write('\x07');
  // While the editor runs (PEEK_DELAY in peek.sh holds it open), what does the terminal show?
  for (let i = 0; i < 50; i++) { await sleep(100); if (i === 2) peekMid.push(screen().filter(l => l.trim()).slice(-6)); if (fs.existsSync(PEEK)) { await sleep(400); return fs.readFileSync(PEEK, 'utf8').replace(/\n$/, ''); } }
  return null;
}
const peekMid = [];
const L = '\x1b[D', R = '\x1b[C', BS = '\x7f';
const cases = JSON.parse(fs.readFileSync(casesPath, 'utf8'));
for (let i = 0; i < 200; i++) { if (box()) break; await sleep(100); }
await sleep(1500);
const results = [];
for (const c of cases) {
  for (const k of ['\x1b', '\x1b', '\x15\x15\x15\x15', '\x0c']) { p.write(k); await sleep(150); }
  for (const s of c.setup) {
    if (s.type) p.write(s.type);
    if (s.paste) p.write(`\x1b[200~${s.paste}\x1b[201~`);
    if (s.nl) p.write(nl);
    if (s.keys) for (const k of s.keys) { p.write(k); await sleep(120); }
    await sleep(s.paste ? 600 : 150);
  }
  await sleep(300);
  const snaps = [];
  const snap = (name) => { const b = box(); snaps.push({ name, box: b && { rows: b.rows, cursor: b.cursor, top: b.top, cells: b.rows.map((_, i) => cells(b.top + i)) } }); };
  snap('start');
  for (const op of c.ops || []) {
    if (op.keys) for (const k of op.keys) { p.write(k); await sleep(op.gap || 140); }
    if (op.snap) { await sleep(300); snap(op.snap); }
    if (op.mouse) {
      // [kind, boxRow, col] in the box's rows (0 = prompt row) and screen columns (0-based); SGR encoding.
      const b = box();
      for (const [kind, r, c] of op.mouse) {
        const y = b.top + r + 1, x = c + 1;
        const s = kind === 'down' ? `\x1b[<0;${x};${y}M` : kind === 'drag' ? `\x1b[<32;${x};${y}M` : kind === 'up' ? `\x1b[<0;${x};${y}m`
          : kind === 'sdown' ? `\x1b[<4;${x};${y}M` : kind === 'sup' ? `\x1b[<4;${x};${y}m` : '';
        p.write(s); await sleep(op.gap || 60);
      }
    }
    if (op.dragBox) {
      // Strategy B's ⌘A: a drag Claude reads as its own, from the box's first text cell to its last inked cell.
      // dragBox: 'all' | {fromCaret: n} (n cells left of the caret on its row, the anchor at the caret).
      const b = box(); const cs = b.rows.map((_, i) => cells(b.top + i));
      let from, to;
      if (op.dragBox === 'all') {
        let last = cs.length - 1; while (last > 0 && !cs[last].some(z => z.x >= 2 && z.ch.trim())) last--;
        const ink = cs[last].filter(z => z.x >= 2 && z.ch.trim()); const end = ink.length ? ink[ink.length - 1].x + ink[ink.length - 1].w + (+process.env.PAST || 0) - 1 : 2;
        from = [0, 2]; to = [last, end];
      } else { from = [b.cursor.row, b.cursor.col]; to = [b.cursor.row, b.cursor.col - op.dragBox.fromCaret]; }
      const seq = [['down', ...from], ['drag', ...to], ['up', ...to]];
      for (const [kind, r, c] of seq) {
        const y = b.top + r + 1, x = c + 1;
        p.write(kind === 'down' ? `\x1b[<0;${x};${y}M` : kind === 'drag' ? `\x1b[<32;${x};${y}M` : `\x1b[<0;${x};${y}m`); await sleep(60);
      }
      snaps.push({ name: 'dragBox', from, to });
    }
    if (op.osc) { await sleep(300); snaps.push({ name: 'osc52 ' + op.osc, clip: osc52.splice(0) }); }
    if (op.peek) { const a0 = altToggles, c0 = clears, t0 = Date.now(); const t = await peek(); const ms = Date.now() - t0; await sleep(400); snaps.push({ name: 'peek ' + op.peek, mid: peekMid.splice(0), text: t, altToggles: altToggles - a0, clears: clears - c0, ms }); }
    if (op.selectDelete) {
      // Duo's selection [from, to) in units of the exact text: put Claude's caret at `to`, then ⌫ (to - from) times.
      const text = await peek(); await sleep(500);
      const u = units(text); const b = box();
      const bx = { rows: b.rows, cells: b.rows.map((_, i) => cells(b.top + i)) };
      const al = align(u, bx);
      const rec = { name: 'selectDelete', text, units: u.length, align: al.ok ? { consumed: al.consumed, total: al.total } : al.at, cursor: b.cursor };
      if (al.ok) {
        const c = caretOffset(al, b.cursor); rec.caret = c;
        const [from, to] = op.selectDelete.map(x => x < 0 ? u.length + x : x);
        const moves = to - c; const keys = (moves > 0 ? R : L).repeat(Math.abs(moves)) + BS.repeat(to - from);
        rec.keys = { moves, backspaces: to - from };
        for (const k of keys.match(/\x1b\[[CD]|\x7f/g) || []) { p.write(k); await sleep(35); }
        await sleep(400);
        const expect = u.slice(0, from).join('') + u.slice(to).join('');
        const got = await peek(); await sleep(400);
        rec.expect = expect; rec.got = got; rec.pass = got === expect;
      }
      snaps.push(rec);
    }
  }
  results.push({ name: c.name, snaps });
  process.stderr.write('.');
}
fs.writeFileSync(outPath, JSON.stringify(results));
p.kill(); setTimeout(() => process.exit(0), 300);
