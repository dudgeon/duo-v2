// A stand-in for the Anthropic Messages API, driven by a script of turns, so a real `claude` (any
// version) can be run through a director scenario with no credentials and no tokens (DL-206, tier 1).
//
//   MOCK_SCRIPT=turns.json MOCK_LOG=out.jsonl MOCK_PORT=8766 node mock-api.mjs
//
// turns.json is a list of rules, tried in order against each request that offers tools:
//   {"when": "<regex over the newest user content>", "once": true, "reply": [blocks…]}
// A block is {"text": "…"} or {"tool": "<name>", "input": {…}}. The first rule whose regex matches the
// newest user message's text (tool results included) answers; "once" rules answer once. No match → "ok".
// Requests without tools (titles, summaries) get a short text. Every request is logged, one JSON line
// each, with the newest user content in full, which is what the checks read.
import http from 'node:http';
import fs from 'node:fs';
const port = +(process.env.MOCK_PORT || 8766);
const log = process.env.MOCK_LOG || 'mock.jsonl';
const rules = JSON.parse(fs.readFileSync(process.env.MOCK_SCRIPT, 'utf8'));
const used = new Set();
let n = 0;
const sleep = ms => new Promise(r => setTimeout(r, ms));

const textOf = c => typeof c === 'string' ? c : (c || []).map(b =>
  b.type === 'text' ? b.text : b.type === 'tool_result' ? '[tool_result] ' + (typeof b.content === 'string' ? b.content : textOf(b.content)) : '').join('\n');

function plan(body) {
  if (!(body.tools || []).length) return [{ text: 'Mock title' }];
  const msgs = (body.messages || []).filter(m => m.role === 'user' || m.role === 'assistant');
  const last = msgs.findLast(m => m.role === 'user');
  const text = textOf(last?.content);
  for (const [i, r] of rules.entries()) {
    if (r.once && used.has(i)) continue;
    if (new RegExp(r.when, 's').test(text)) { used.add(i); return r.reply; }
  }
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
      send('content_block_delta', { index: i, delta: { type: 'text_delta', text: b.text } });
    } else {
      stop = 'tool_use';
      send('content_block_start', { index: i, content_block: { type: 'tool_use', id: `toolu_mock${n}_${i}`, name: b.tool, input: {} } });
      send('content_block_delta', { index: i, delta: { type: 'input_json_delta', partial_json: JSON.stringify(b.input) } });
    }
    send('content_block_stop', { index: i });
    await sleep(50);
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
    const msgs = (body.messages || []).filter(m => m.role === 'user');
    fs.appendFileSync(log, JSON.stringify({ n, at: Date.now() / 1000, url: req.url, tools: (body.tools || []).map(t => t.name), lastUser: textOf(msgs.at(-1)?.content) }) + '\n');
    if (!req.url.startsWith('/v1/messages')) { res.writeHead(200, { 'content-type': 'application/json' }); return res.end('{}'); }
    if (req.url.includes('count_tokens')) { res.writeHead(200, { 'content-type': 'application/json' }); return res.end('{"input_tokens":100}'); }
    const blocks = plan(body);
    if (body.stream) return stream(res, blocks, body.model);
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ id: 'msg_mock' + n, type: 'message', role: 'assistant', model: body.model, content: blocks.map((b, i) => b.text !== undefined ? { type: 'text', text: b.text } : { type: 'tool_use', id: `toolu_x${n}_${i}`, name: b.tool, input: b.input }), stop_reason: blocks.some(b => b.tool) ? 'tool_use' : 'end_turn', usage: { input_tokens: 10, output_tokens: 5 } }));
  });
}).listen(port, '127.0.0.1', () => console.log('mock on', port));
