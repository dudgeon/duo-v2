// A stand-in for the Anthropic Messages API: scripted replies keyed by "SCENARIO:<name>" in the
// prompt, so the real interactive TUI can be driven through every interaction with no credentials.
import http from 'node:http';
import fs from 'node:fs';
const port = +(process.env.MOCK_PORT || 8765);
const log = process.env.MOCK_LOG || 'mock.log';
let n = 0;
const sleep = ms => new Promise(r => setTimeout(r, ms));

function textOf(content) {
  if (typeof content === 'string') return content;
  return (content || []).map(b => b.type === 'text' ? b.text : b.type === 'tool_result' ? '[tool_result] ' + JSON.stringify(b.content) : '').join('\n');
}
const MD = `## Results\n\nHere is **bold**, *italic*, \`code\` and a [link](https://example.com).\n\n| Col | Value |\n|---|---|\n| a | 1 |\n| b | 2 |\n\n\`\`\`swift\nlet x = 1\nprint(x)\n\`\`\`\n\n- one\n- two\n  - nested\n\nSee /tmp/example.txt:12 for more.`;

const Q = (question, header, multiSelect, labels) => ({ question, header, multiSelect, options: labels.map(l => ({ label: l, description: `About ${l.replace(/ \(Recommended\)/, '')}` })) });
const scenarios = {
  hello: () => [{ text: 'Hello from the mock. This is **Markdown**.' }],
  md: () => [{ text: MD, slow: true }],
  ask: () => [{ text: 'I need one choice from you.' }, { tool: 'AskUserQuestion', input: { questions: [{ question: 'Which colour should the button be?', header: 'Colour', multiSelect: false, options: [{ label: 'Blue', description: 'Matches the brand' }, { label: 'Green', description: 'Reads as go' }, { label: 'Grey', description: 'Quiet' }] }] } }],
  askmulti: () => [{ tool: 'AskUserQuestion', input: { questions: [
    { question: 'Which platforms should we ship?', header: 'Platforms', multiSelect: true, options: [{ label: 'macOS', description: 'Native' }, { label: 'iOS', description: 'Phone' }, { label: 'Web', description: 'Browser' }] },
    { question: 'How soon?', header: 'Timing', multiSelect: false, options: [{ label: 'This week', description: 'Fast' }, { label: 'Next month', description: 'Careful' }] }] } }],
  // AskUserQuestion variants (F-106): every shape the tool's schema allows.
  ask1: () => [{ tool: 'AskUserQuestion', input: { questions: [Q('Which database should we use?', 'Database', false, ['Postgres', 'SQLite', 'MySQL'])] } }],
  askmulti1: () => [{ tool: 'AskUserQuestion', input: { questions: [Q('Which checks should run on every commit?', 'Checks', true, ['Lint', 'Unit tests', 'Type check', 'Build'])] } }],
  ask4: () => [{ tool: 'AskUserQuestion', input: { questions: [
    Q('Which framework should the settings page use?', 'Framework', false, ['SwiftUI (Recommended)', 'AppKit']),
    Q('Which sections should it have?', 'Sections', true, ['General', 'Accounts', 'Advanced']),
    Q('Where should settings be stored?', 'Storage', false, ['UserDefaults', 'A JSON file', 'Keychain']),
    Q('Which platforms need it first?', 'Platforms', true, ['macOS', 'iOS'])] } }],
  asklong: () => [{ tool: 'AskUserQuestion', input: { questions: [{ question: 'This question is deliberately long so that it wraps across more than one line of the terminal at its usual width: which migration strategy should we use for the existing sessions folder?', header: 'Migration', multiSelect: false, options: [
    { label: 'Move everything in one pass with a journal so it can be undone (Recommended)', description: 'Fast and atomic per folder; needs free disk space equal to the largest folder, and a journal file so an interrupted run can be repaired on the next launch.' },
    { label: 'Copy, verify, then delete', description: 'Slower and needs double the space, but the originals stay until every copy is checked byte for byte.' },
    { label: 'Leave old sessions where they are', description: 'Nothing moves; new sessions go to the new place.' },
    { label: 'Ask per folder', description: 'Show each folder with its size and let the user choose.' }] }] } }],
  askpreview: () => [{ tool: 'AskUserQuestion', input: { questions: [{ question: 'Which layout should the card use?', header: 'Layout', multiSelect: false, options: [
    { label: 'Stacked', description: 'Question above, options below', preview: '+------------------+\n| Question?        |\n| [ Option one   ] |\n| [ Option two   ] |\n+------------------+' },
    { label: 'Side by side', description: 'Options left, detail right', preview: '+--------+---------+\n| > One  | Detail  |\n|   Two  | of one  |\n+--------+---------+' },
    { label: 'Compact', description: 'One line per option', preview: 'Question?  (o) One  ( ) Two  ( ) Three' }] }] } }],
  bash: () => [{ text: 'Running a command.' }, { tool: 'Bash', input: { command: 'echo hello > hello.txt && cat hello.txt', description: 'Write and read a file' } }],
  edit: () => [{ tool: 'Write', input: { file_path: (process.env.MOCK_CWD || process.cwd()) + '/notes.md', content: '# Notes\n\nFirst line.\n' } }],
  read: () => [{ tool: 'Read', input: { file_path: (process.env.MOCK_CWD || process.cwd()) + '/notes.md' } }],
  edit2real: () => [{ tool: 'Edit', input: { file_path: (process.env.MOCK_CWD || process.cwd()) + '/notes.md', old_string: 'First line.', new_string: 'First line, edited.\nSecond line.' } }],
  // Questions that follow a tool (F-245): the question comes on the reply to the tool's result.
  readask: () => [{ text: 'Reading a file first.' }, { tool: 'Read', input: { file_path: (process.env.MOCK_CWD || process.cwd()) + '/data.txt' } }],
  permask: () => [{ text: 'Running a command first.' }, { tool: 'Bash', input: { command: 'echo hi', description: 'Say hi' } }],
  // Awkward but realistic content: markdown and backticks in labels, wide characters and emoji, a multi-line
  // question, numbered lines inside a description, a long wrapping description.
  askodd: () => [{ tool: 'AskUserQuestion', input: { questions: [{ question: 'Which parser should we use for `config.toml`?\n\nPick one; the choice is hard to undo.', header: 'Parser', multiSelect: false, options: [
    { label: '`tomli` (Recommended)', description: 'Fast and small. Steps:\n1. install it\n2. import it' },
    { label: 'serde — 日本語 ✅', description: 'Wide characters and an emoji in the label' },
    { label: 'Roll our own', description: 'A very long description that goes on and on past the width of the pane so that it has to wrap onto at least two lines, perhaps three, in a narrow terminal window, to check the wrapping logic.' }] }] } }],
  // A description line that starts with "N. " (a wrapped numbered list, "Phase 1. … 2. …") reads as an option row.
  askdesc: () => [{ tool: 'AskUserQuestion', input: { questions: [{ question: 'Which rollout plan do you want?', header: 'Rollout', multiSelect: false, options: [
    { label: 'Phased', description: '3. Third-party integrations come last, after the core is stable.' },
    { label: 'All at once', description: 'One release for everything' }] }] } }],
  ask2: () => [{ tool: 'AskUserQuestion', input: { questions: [Q('Ship it now?', 'Ship', false, ['Yes', 'No'])] } }],
  askmulti4: () => [{ tool: 'AskUserQuestion', input: { questions: [Q('Which checks should run?', 'Checks', true, ['Lint', 'Unit tests', 'Type check', 'Build']), Q('Which environments?', 'Envs', true, ['Dev', 'Staging', 'Prod', 'Canary'])] } }],
  slowask: () => [{ text: 'Thinking it over before one question, and writing a few lines while I do: the reply streams.', slow: true }, { tool: 'AskUserQuestion', input: { questions: [Q('Which database should we use?', 'Database', false, ['Postgres', 'SQLite', 'MySQL'])] } }],
  plan: (body) => { const m = JSON.stringify(body).match(/(\/[^\s"'`\\]*\/plans\/[\w.-]+\.md)/); return [{ text: 'Writing the plan.' }, { tool: 'Write', input: { file_path: m ? m[1] : '/tmp/plan.md', content: '# Plan\n\n1. Read the code\n2. Change `foo`\n3. Run the checks\n' } }]; },
  agent: () => [{ tool: 'Agent', input: { description: 'Look around', prompt: 'SUBAGENT: summarise the folder', subagent_type: 'general-purpose' } }],
  long: () => [{ text: Array.from({ length: 40 }, (_, i) => `Line ${i + 1} of a long answer.`).join('\n'), slow: true }],
  err: () => 'error',
};

function plan(body) {
  // Claude Code 2.1.29x ends every request with a "system"-role message (a token count, the plan-mode
  // reminder); only the conversation's own turns count here.
  const msgs = (body.messages || []).filter(m => m.role === 'user' || m.role === 'assistant');
  const last = msgs[msgs.length - 1];
  const all = msgs.map(m => textOf(m.content)).join('\n');
  if (/SUBAGENT:/.test(textOf(msgs[0]?.content)) && last?.role === 'user' && !/tool_result/.test(textOf(last.content)))
    return [{ text: 'Subagent: the folder holds a few notes.' }];
  const prevTool = msgs.length > 1 && Array.isArray(msgs[msgs.length - 2].content) ? msgs[msgs.length - 2].content.find(b => b.type === 'tool_use') : null;
  const lastText = Array.isArray(last?.content) ? last.content.filter(b => b.type === 'text').map(b => b.text).join('\n') : textOf(last?.content);
  // Duo appends its own reminder blocks after the prompt, so the scenario is read from the latest prompt
  // (not the last message), and a tool that ran since the prompt counts whatever the last message is.
  // After an interrupted tool use the next prompt is merged into the rejected tool_result's message, so
  // the prompt is found by its text blocks (never a tool_result's content) and only what comes after
  // that block, later in the message or in later messages, counts as "since the prompt".
  const blocks = m => typeof m.content === 'string' ? [{ type: 'text', text: m.content }] : (m.content || []);
  let promptIdx = -1, blockIdx = -1;
  for (let i = msgs.length - 1; i >= 0 && promptIdx < 0; i--) {
    if (msgs[i].role !== 'user') continue;
    const bi = blocks(msgs[i]).findLastIndex(b => b.type === 'text' && /SCENARIO:/.test(b.text));
    if (bi >= 0) { promptIdx = i; blockIdx = bi; }
  }
  const after = promptIdx >= 0 ? [...blocks(msgs[promptIdx]).slice(blockIdx + 1), ...msgs.slice(promptIdx + 1).flatMap(blocks)] : [];
  const ranTool = after.some(b => b.type === 'tool_result');
  const asked = after.some(b => b.type === 'tool_use' && b.name === 'AskUserQuestion');
  const sname = promptIdx >= 0 ? [...blocks(msgs[promptIdx])[blockIdx].text.matchAll(/SCENARIO:(\w+)/g)].pop()?.[1] : null;
  // readask and permask: the question comes once their tool has run, and only once.
  if ((body.tools || []).length && (sname === 'readask' || sname === 'permask') && ranTool && !asked) return scenarios.ask1();
  // Title requests (no tools) and anything after a tool result skip the scenario.
  const sc = ranTool || !(body.tools || []).length || !sname ? null : ['SCENARIO', sname];
  if (sc && scenarios[sc[1]]) return scenarios[sc[1]](body);
  if (prevTool?.name === 'Write' && /\/plans\//.test(prevTool.input.file_path)) return [{ tool: 'ExitPlanMode', input: {} }];
  if (prevTool?.name === 'Read' && /notes\.md/.test(JSON.stringify(prevTool.input))) return scenarios.edit2real();
  if (!(body.tools || []).length) return [{ text: /summar/i.test(textOf(last?.content)) && !/SCENARIO:/.test(textOf(last?.content)) ? '<summary>Mock summary of the conversation.</summary>' : 'Mock title' }];
  if (false) return [{ text: '<summary>Mock summary of the conversation.</summary>' }];
  if (last && Array.isArray(last.content) && last.content.some(b => b.type === 'tool_result')) {
    const tr = last.content.find(b => b.type === 'tool_result');
    return [{ text: `Done. The tool said: ${JSON.stringify(tr.content).slice(0, 160)}` }];
  }
  const m = [...textOf(last?.content).matchAll(/SCENARIO:(\w+)/g)].pop();
  if (m && scenarios[m[1]]) return scenarios[m[1]]();
  return [{ text: 'ok' }];
}

async function stream(res, blocks, model) {
  const send = (ev, data) => res.write(`event: ${ev}\ndata: ${JSON.stringify({ type: ev, ...data })}\n\n`);
  res.writeHead(200, { 'content-type': 'text/event-stream', 'request-id': 'req_mock' + n });
  send('message_start', { message: { id: 'msg_mock' + n + Date.now(), type: 'message', role: 'assistant', model, content: [], stop_reason: null, usage: { input_tokens: 10, output_tokens: 1 } } });
  let stop = 'end_turn';
  for (const [i, b] of blocks.entries()) {
    if (b.text !== undefined) {
      send('content_block_start', { index: i, content_block: { type: 'text', text: '' } });
      const parts = b.slow ? b.text.match(/[\s\S]{1,12}/g) : [b.text];
      for (const p of parts) { send('content_block_delta', { index: i, delta: { type: 'text_delta', text: p } }); if (b.slow) await sleep(120); }
    } else {
      stop = 'tool_use';
      send('content_block_start', { index: i, content_block: { type: 'tool_use', id: 'toolu_mock' + n + i, name: b.tool, input: {} } });
      send('content_block_delta', { index: i, delta: { type: 'input_json_delta', partial_json: JSON.stringify(b.input) } });
    }
    send('content_block_stop', { index: i });
    await sleep(300);
  }
  send('message_delta', { delta: { stop_reason: stop, stop_sequence: null }, usage: { output_tokens: 20 } });
  send('message_stop', {});
  res.end();
}

http.createServer((req, res) => {
  let raw = '';
  req.on('data', d => raw += d);
  req.on('end', async () => {
    n++;
    let body = {};
    try { body = JSON.parse(raw || '{}'); } catch {}
    const entry = { n, at: Date.now() / 1000, method: req.method, url: req.url, model: body.model, stream: body.stream, tools: (body.tools || []).map(t => t.name), lastUser: textOf(body.messages?.at(-1)?.content).slice(-300) };
    fs.appendFileSync(log, JSON.stringify(entry) + '\n');
    if ((!globalThis.dumped && (body.tools || []).length && (globalThis.dumped = true)) || process.env.MOCK_DUMP) fs.writeFileSync(log + '.req' + n + '.json', raw);
    if (!req.url.startsWith('/v1/messages')) { res.writeHead(200, { 'content-type': 'application/json' }); return res.end('{}'); }
    if (req.url.includes('count_tokens')) { res.writeHead(200, { 'content-type': 'application/json' }); return res.end('{"input_tokens":100}'); }
    const blocks = plan(body);
    if (blocks === 'error') { res.writeHead(529, { 'content-type': 'application/json' }); return res.end(JSON.stringify({ type: 'error', error: { type: 'overloaded_error', message: 'Overloaded (mock)' } })); }
    if (body.stream) return stream(res, blocks, body.model);
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ id: 'msg_mock' + n, type: 'message', role: 'assistant', model: body.model, content: blocks.map(b => b.text !== undefined ? { type: 'text', text: b.text } : { type: 'tool_use', id: 'toolu_x' + n, name: b.tool, input: b.input }), stop_reason: 'end_turn', usage: { input_tokens: 10, output_tokens: 5 } }));
  });
}).listen(port, '127.0.0.1', () => console.log('mock on', port));
