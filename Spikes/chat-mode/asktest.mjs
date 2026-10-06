// End-to-end AskUserQuestion check (F-106): through the PoC server, the same path the page uses.
// Start the server first (./start.sh, the mock), then: node asktest.mjs [case…]
// Each case sends a prompt, waits for the question, sends the card's intents, then reads what
// Claude received from the transcript and compares it with what the human chose.
import WebSocket from 'ws';

const ws = new WebSocket('ws://127.0.0.1:8780');
const sleep = ms => new Promise(r => setTimeout(r, ms));
let screen = { kind: 'starting' }, id = 0;
const results = new Map(), records = [];
ws.on('message', d => {
  const m = JSON.parse(d);
  if (m.t === 'hello') { screen = m.screen; for (const h of m.history) if (h.t === 'record') records.push(h.r); }
  if (m.t === 'screen') screen = m.s;
  if (m.t === 'record') records.push(m.r);
  if (m.t === 'result') results.set(m.id, m);
});
const until = async (f, ms = 15000) => { for (let t = 0; t < ms; t += 100) { if (f()) return true; await sleep(100); } return false; };
const rpc = async msg => { const i = ++id; ws.send(JSON.stringify({ ...msg, id: i })); await until(() => results.has(i), 20000); return results.get(i) ?? { ok: false, why: 'no reply' }; };
const idle = () => until(() => screen.kind === 'idle', 30000);

// What Claude got back for the last AskUserQuestion: the answers, or how it was refused.
function lastAnswer(since) {
  for (let i = records.length - 1; i >= since; i--) {
    const r = records[i];
    if (r.type !== 'user' || !Array.isArray(r.message?.content)) continue;
    const tr = r.message.content.find(b => b.type === 'tool_result');
    if (!tr) continue;
    if (r.toolUseResult && typeof r.toolUseResult === 'object' && r.toolUseResult.answers)
      return { answers: r.toolUseResult.answers, annotations: r.toolUseResult.annotations };
    if (tr.is_error) return { declined: r.toolDenialKind || 'error', feedback: r.userFeedback };
  }
  return null;
}

const cases = {
  'single: pick': { prompt: 'ask1', steps: [{ type: 'pick', label: 'SQLite' }], expect: { answers: { 'Which database should we use?': 'SQLite' } } },
  'single: Other text': { prompt: 'ask1', steps: [{ type: 'other', text: 'DuckDB' }], expect: { answers: { 'Which database should we use?': 'DuckDB' } } },
  'multi: two ticks': { prompt: 'askmulti1', steps: [{ type: 'toggle', label: 'Lint' }, { type: 'toggle', label: 'Build' }, { type: 'next' }, { type: 'submit' }], expect: { answers: { 'Which checks should run on every commit?': 'Lint, Build' } } },
  'multi: untick': { prompt: 'askmulti1', steps: [{ type: 'toggle', label: 'Lint' }, { type: 'toggle', label: 'Unit tests' }, { type: 'toggle', label: 'Lint' }, { type: 'next' }, { type: 'submit' }], expect: { answers: { 'Which checks should run on every commit?': 'Unit tests' } } },
  'multi: tick + Other': { prompt: 'askmulti1', steps: [{ type: 'toggle', label: 'Type check' }, { type: 'other', text: 'Docs build' }, { type: 'next' }, { type: 'submit' }], expect: { answers: { 'Which checks should run on every commit?': 'Type check, Docs build' } } },
  'four questions, back and change': { prompt: 'ask4', steps: [
    { type: 'pick', label: 'AppKit' },
    { type: 'toggle', label: 'General' }, { type: 'toggle', label: 'Advanced' }, { type: 'next' },
    { type: 'pick', label: 'Keychain' },
    { type: 'tab', index: 0 }, { type: 'pick', label: 'SwiftUI (Recommended)' },
    { type: 'tab', index: 3 }, { type: 'toggle', label: 'macOS' }, { type: 'other', text: 'watchOS' }, { type: 'next' },
    { type: 'submit' }],
    expect: { answers: { 'Which framework should the settings page use?': 'SwiftUI (Recommended)', 'Which sections should it have?': 'General, Advanced', 'Where should settings be stored?': 'Keychain', 'Which platforms need it first?': 'macOS, watchOS' } } },
  'long, wrapped labels': { prompt: 'asklong', steps: [{ type: 'pick', label: 'Copy, verify, then delete' }], expect: { answers: { 'This question is deliberately long so that it wraps across more than one line of the terminal at its usual width: which migration strategy should we use for the existing sessions folder?': 'Copy, verify, then delete' } } },
  'preview: pick': { prompt: 'askpreview', steps: [{ type: 'pick', label: 'Compact' }], expect: { answers: { 'Which layout should the card use?': 'Compact' } } },
  'preview: notes': { prompt: 'askpreview', steps: [{ type: 'notes', label: 'Side by side', text: 'keep it short' }], expect: { answers: { 'Which layout should the card use?': 'Side by side' }, notes: 'keep it short' } },
  'chat about this': { prompt: 'ask1', steps: [{ type: 'chat' }], expect: { declined: true } },
  'decline (Esc)': { prompt: 'askmulti1', steps: [{ type: 'decline' }], expect: { declined: true } },
  'review: cancel': { prompt: 'askmulti1', steps: [{ type: 'toggle', label: 'Build' }, { type: 'next' }, { type: 'cancel-review' }], expect: { declined: true } },
  'stale card is refused': { prompt: 'ask1', steps: [{ type: 'pick', label: 'SQLite', sig: 'q:Some older question?' }, { type: 'pick', label: 'Postgres' }], expect: { answers: { 'Which database should we use?': 'Postgres' }, refused: 1 } },
};

const pick = process.argv.slice(2);
await until(() => ws.readyState === 1);
await idle();
const report = [];
for (const [name, c] of Object.entries(cases)) {
  if (pick.length && !pick.some(p => name.includes(p))) continue;
  const since = records.length;
  await rpc({ t: 'send', text: `SCENARIO:${c.prompt}` });
  if (!await until(() => screen.kind === 'question', 20000)) { report.push([name, 'FAIL', 'no question appeared', screen.kind]); await rpc({ t: 'interrupt' }); await idle(); continue; }
  await sleep(300);
  let refused = 0, err = null;
  for (const st of c.steps) {
    const { sig, ...intent } = st;
    const r = await rpc({ t: 'ask', sig: sig ?? screen.sig, intent });
    if (!r.ok) { refused++; if (!sig) { err = `${intent.type}: ${r.why}`; break; } }
    await sleep(350);
  }
  await idle();
  await sleep(600);
  const got = lastAnswer(since);
  let ok = !err && !!got;
  if (ok && c.expect.answers) ok = JSON.stringify(got.answers) === JSON.stringify(c.expect.answers);
  if (ok && c.expect.declined) ok = !!got.declined;
  if (ok && c.expect.notes) ok = Object.values(got.annotations || {}).some(a => a.notes === c.expect.notes);
  if (ok && c.expect.refused !== undefined) ok = refused === c.expect.refused;
  report.push([name, ok ? 'pass' : 'FAIL', err || '', JSON.stringify(got)]);
  if (screen.kind !== 'idle') { await rpc({ t: 'interrupt' }); await idle(); }
}
for (const [n, v, e, g] of report) console.log(`${v.padEnd(4)}  ${n.padEnd(34)} ${e} ${v === 'pass' ? '' : g}`.trimEnd());
console.log(`${report.filter(r => r[1] === 'pass').length}/${report.length} passed`);
process.exit(report.every(r => r[1] === 'pass') ? 0 : 1);
