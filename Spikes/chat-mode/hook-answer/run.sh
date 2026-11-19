#!/bin/zsh
# run.sh <claude> <tag> <mode pre|perm|deny> <wait s> [hook timeout s] [extra steps json]: does a hook's answer reach Claude with no dialog?
set -u
SP=${0:A:h:h}
T=${0:A:h}
BIN=$1; TAG=$2; MODE=$3; WAIT=$4; TMO=${5:-600}; SCEN=${6:-askvision}
D=/tmp/dmq-ha-$TAG; rm -rf $D; zsh $SP/scratch.sh $D >/dev/null
ID=$(uuidgen | tr A-Z a-z)
EVENT=PreToolUse; [ $MODE = perm ] && EVENT=PermissionRequest
cat > $D/settings.json <<J
{"hooks":{"$EVENT":[{"matcher":"AskUserQuestion","hooks":[{"type":"command","command":"MODE=$MODE WAIT=$WAIT HOOK_LOG=$D/hook.log python3 $T/answer.py","timeout":$TMO}]}]}}
J
PORT=$((19000 + RANDOM % 500))
MOCK_PORT=$PORT MOCK_CWD=$D/ws MOCK_LOG=$D/mock.log node $SP/mock.mjs >/dev/null 2>&1 & MP=$!
sleep 1
W=$((WAIT * 1000 + 4000))
cat > $D/steps.json <<J
[{"sleep":4000},{"type":"SCENARIO:$SCEN","paste":true},{"sleep":300},{"key":"enter"},${MID:-}{"sleep":$W},{"sleep":2500}]
J
cd $D/ws
env CLAUDE_CONFIG_DIR=$D/cfg ANTHROPIC_BASE_URL=http://127.0.0.1:$PORT ANTHROPIC_API_KEY=sk-ant-mock-key-0000000000000000000 DISABLE_AUTOUPDATER=1 TERM=xterm-256color \
  python3 $T/drive.py $BIN $D/steps.json $D/out --session-id $ID --settings $D/settings.json --model claude-haiku-5-5
sleep 1; kill $MP 2>/dev/null
echo "== $TAG mode=$MODE wait=$WAIT"; echo "hook process still running after the run: $(pgrep -f "hook-answer/answer.py" | wc -l | tr -d " ")"; cat $D/hook.log
echo "hook log: $(cat $D/hook.log 2>/dev/null | python3 -c "import sys,json; print([ (json.loads(l).get('phase'), json.loads(l).get('event')) for l in sys.stdin])")"
echo "dialog drawn on screen: $(grep -a -c 'Enter to select' $D/out/raw.bin)"
python3 - $D <<'PY'
import json,glob,sys
for f in glob.glob(sys.argv[1]+'/cfg/projects/*/*.jsonl'):
    for l in open(f):
        r=json.loads(l)
        if 'toolUseResult' in r:
            t=r['toolUseResult']
            print('toolUseResult:', json.dumps(t)[:300] if not isinstance(t,dict) else {'answers': t.get('answers')})
            c=(r.get('message') or {}).get('content')
            if isinstance(c,list): print('tool_result text:', str(c[0].get('content'))[:260])
PY
