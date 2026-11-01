"""Pull Drive connector payloads out of this session's transcript (exact bytes, no re-typing).
usage: transcript_tool.py <transcript.jsonl> inputs            -> list create_file uploads (title, len)
       transcript_tool.py <transcript.jsonl> input <title> <out>  -> write the decoded base64 that was sent
       transcript_tool.py <transcript.jsonl> results             -> list download results (fileId, mime, len)
       transcript_tool.py <transcript.jsonl> result <n> <out>     -> write the n-th download's decoded content
"""
import base64, json, sys

path, cmd = sys.argv[1], sys.argv[2]
uses, results = {}, []
for line in open(path):
    try:
        ev = json.loads(line)
    except Exception:
        continue
    msg = ev.get('message') or {}
    content = msg.get('content')
    if not isinstance(content, list):
        continue
    for c in content:
        if c.get('type') == 'tool_use' and 'Google_Drive' in c.get('name', ''):
            uses[c['id']] = c
        if c.get('type') == 'tool_result' and c.get('tool_use_id') in uses:
            u = uses[c['tool_use_id']]
            if u['name'].endswith('download_file_content'):
                body = c.get('content')
                if isinstance(body, list):
                    body = ''.join(x.get('text', '') for x in body if isinstance(x, dict))
                try:
                    d = json.loads(body)
                    results.append((u['input'], d))
                except Exception:
                    pass

if cmd == 'inputs':
    for u in uses.values():
        if u['name'].endswith('create_file') and 'base64Content' in u['input']:
            print(u['input']['title'], len(u['input']['base64Content']))
elif cmd == 'input':
    title, out = sys.argv[3], sys.argv[4]
    for u in uses.values():
        if u['name'].endswith('create_file') and u['input'].get('title') == title:
            open(out, 'wb').write(base64.b64decode(u['input']['base64Content']))
            print('wrote', out)
elif cmd == 'results':
    for i, (inp, d) in enumerate(results):
        print(i, inp.get('fileId'), inp.get('exportMimeType'), d.get('title'), len(d.get('content', '')))
elif cmd == 'result':
    n, out = int(sys.argv[3]), sys.argv[4]
    open(out, 'wb').write(base64.b64decode(results[n][1]['content']))
    print('wrote', out)
