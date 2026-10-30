#!/bin/bash
# Does a fork resume after its parent's transcript is deleted? (F-405; Geoff, 2026-10-29). A /branch-style fork
# (its own transcript: a copy of the parent's records, `forkedFrom` naming it, then its own) is resumed with `-p`
# after the parent's file is removed. Scratch CLAUDE_CONFIG_DIR, a dummy key and a local stub that records the
# request and answers 500: no real turn runs. CLAUDE_BIN picks the CLI (the work Mac pins 2.1.284).
# Prints, for each marker, whether the request Claude sent carried it.
set -u
D=$(cd "$(dirname "$0")" && pwd)
W=/tmp/dfp; rm -rf "${W:?}"; mkdir -p $W/proj $W/cfg
PROJ=$(cd $W/proj && pwd -P)
ENC=$(echo "$PROJ" | sed 's/[^A-Za-z0-9]/-/g')
B=$W/cfg/projects/$ENC; mkdir -p $B
P=11111111-1111-4111-8111-111111111111
F=22222222-2222-4222-8222-222222222222
python3 - "$B" "$P" "$F" "$PROJ" <<'PY'
import json,sys
b,P,F,cwd=sys.argv[1:]
def rec(sid,typ,uuid,parent,text,ts,extra={}):
    r={"parentUuid":parent,"isSidechain":False,"userType":"external","cwd":cwd,"sessionId":sid,"version":"2.1.311","type":typ,"uuid":uuid,"timestamp":ts}
    if typ=="user": r["message"]={"role":"user","content":text}
    else: r["message"]={"id":"msg_1","type":"message","role":"assistant","model":"claude-haiku-5-5","content":[{"type":"text","text":text}],"stop_reason":"end_turn","stop_sequence":None,"usage":{"input_tokens":1,"output_tokens":1}}
    r.update(extra); return r
u1="aaaaaaaa-0000-4000-8000-000000000001"; a1="aaaaaaaa-0000-4000-8000-000000000002"; u2="aaaaaaaa-0000-4000-8000-000000000003"
parent=[rec(P,"user",u1,None,"PARENT-ONLY-MARKER: the plan is ducks","2026-10-29T10:00:00Z"),
        rec(P,"assistant",a1,u1,"SHARED-HISTORY-MARKER: noted, ducks","2026-10-29T10:00:05Z")]
ff={"forkedFrom":{"sessionId":P,"messageUuid":a1}}
fork=[dict(r,sessionId=F,**ff) for r in parent]+[rec(F,"user",u2,a1,"FORK-OWN-MARKER: and geese","2026-10-29T10:05:00Z",ff),
      rec(F,"assistant","aaaaaaaa-0000-4000-8000-000000000004",u2,"FORK-REPLY-MARKER: geese too","2026-10-29T10:05:05Z",ff)]
open(f"{b}/{P}.jsonl","w").write("".join(json.dumps(r)+"\n" for r in parent))
open(f"{b}/{F}.jsonl","w").write("".join(json.dumps(r)+"\n" for r in fork))
PY
# The parent goes, as Delete Session… sends it to the Trash.
rm "$B/$P.jsonl"
ls $B
# A stub API: records the body, answers 500 so nothing more happens.
python3 - <<'PY' &
import http.server, json
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n=int(self.headers.get('content-length',0)); body=self.rfile.read(n)
        if b'/messages' in self.path.encode(): open('/tmp/dfp/request.json','ab').write(body+b"\n")
        self.send_response(500); self.send_header('content-type','application/json'); self.end_headers()
        self.wfile.write(b'{"type":"error","error":{"type":"api_error","message":"stub"}}')
    def do_GET(self): self.send_response(404); self.end_headers()
    def log_message(self,*a): pass
http.server.HTTPServer(('127.0.0.1',47123),H).serve_forever()
PY
SRV=$!
sleep 1
cd $PROJ
env -u ANTHROPIC_AUTH_TOKEN CLAUDE_CONFIG_DIR=$W/cfg ANTHROPIC_API_KEY=sk-ant-dummy ANTHROPIC_BASE_URL=http://127.0.0.1:47123 \
  CLAUDE_CODE_MAX_RETRIES=0 DISABLE_TELEMETRY=1 DISABLE_AUTOUPDATER=1 \
  perl -e "alarm 60; exec @ARGV" ${CLAUDE_BIN:-claude} --resume $F -p "next step?" --model claude-haiku-5-5 > $W/out.txt 2>&1
echo "exit $?"
kill $SRV
head -c 400 $W/out.txt; echo
test -f $W/request.json && python3 - <<'PY'
import json
lines=[l for l in open('/tmp/dfp/request.json').read().splitlines() if l.strip()]
body=json.loads(lines[-1]); msgs=json.dumps(body.get("messages",[]))
for m in ["PARENT-ONLY-MARKER","SHARED-HISTORY-MARKER","FORK-OWN-MARKER","FORK-REPLY-MARKER","next step?"]:
    print(m, "sent" if m in msgs else "MISSING")
print("requests:",len(lines))
PY
