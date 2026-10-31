#!/bin/zsh
# F-444's proof in a real Duo: an isolated dev instance, in the background (F-227), whose Home is a fresh folder its
# scratch Claude config has never trusted. Home's first session opens in chat, the real `claude` TUI asks "Accessing
# workspace … Yes, I trust this folder" (against the chat-mode spike's mock API: no login, no tokens), and chat must
# not fall back: Duo's trust sheet comes up, and the run answers it.
#   scripts/check-chat-trust-live.sh <out> [yes|no]     APP=<Duo.app> (default build/Duo.app)  CLAUDE=<path> (default: on PATH)
# yes: Trust Folder → Claude reaches its prompt in chat, and its own file now trusts the folder.
# no:  Don’t Trust → Claude exits, and the folder is still not trusted.
# Isolated (CLAUDE.md): its own support folder and Claude config under /tmp, quit by SIGTERM to its pid.
set -u
root=${0:A:h:h}
out=${1:A} answer=${2:-yes}
app=${APP:-$root/build/Duo.app}
real=${CLAUDE:-$(command -v claude)}
version=$($real --version 2>/dev/null | awk '{print $1}')
mkdir -p $out
fx=/tmp/ctl-$answer
chmod -R u+w $fx 2>/dev/null; rm -rf $fx
$root/Spikes/chat-mode/scratch.sh $fx >/dev/null
home=$fx/fresh
mkdir -p $home $fx/sup/Duo
print -- '---\ngoal: "trust proof"\n---\n\n# Home\n' > $home/HOME.md
print -- '{}' > $fx/cfg/settings.json
print -- "{\"claudePath\":\"$real\",\"home\":\"$home\"}" > $fx/sup/Duo/state.json
port=$((8900 + RANDOM % 90))
(cd $root/Spikes/chat-mode && MOCK_PORT=$port MOCK_CWD=$home MOCK_LOG=$out/mock-$answer.log node mock.mjs) >/dev/null 2>&1 &
mock=$!
sleep 0.5
label="Trust Folder"; [[ $answer == no ]] && label="Don’t Trust"
png=$out/$answer.png; rm -f $png
then="wait:8,chat:on,wait:3,chat-state,answer:$label,wait:6,chat-state"
err=$out/stderr-$answer.txt
env -u DUO_SUPPORT_DIR -u DUO_SOCKET -u DUO_TOKEN -u DUO_SIGNAL -u DUO_AUTOCONFIRM DUO_SUPPORT_DIR=$fx/sup CLAUDE_CONFIG_DIR=$fx/cfg \
  ANTHROPIC_BASE_URL=http://127.0.0.1:$port ANTHROPIC_API_KEY=sk-ant-mock-key-0000000000000000000 DISABLE_AUTOUPDATER=1 \
  ANTHROPIC_MODEL=claude-haiku-5-5 \
  $app/Contents/MacOS/Duo --workspace $home --capture-window $png --then "$then" 2>$err &
pid=$!
for i in {1..60}; do [[ -f $png ]] && break; sleep 1; done
sleep 1
kill -TERM $pid 2>/dev/null; for i in {1..15}; do kill -0 $pid 2>/dev/null || break; sleep 1; done
kill $mock 2>/dev/null
trusted=$(python3 - $fx/cfg/.claude.json $home <<'PY'
import json, os, sys
d = json.load(open(sys.argv[1])); p = os.path.realpath(sys.argv[2])
print(d.get('projects', {}).get(p, {}).get('hasTrustDialogAccepted') is True)
PY
)
grep -a "^answer:\|^chat-state:\|chat-fallback:" $err | cut -c1-220
first=$(grep -a "^chat-state:" $err | head -1); last=$(grep -a "^chat-state:" $err | tail -1)
ok=FAIL
if [[ $first == *"screen=trust"* && $first == *"showing=chat"* && $first == *"fallback=-"* ]] && grep -aq "^answer: Trust “fresh” for Claude Code?" $err; then
  if [[ $answer == yes && $trusted == True && $last == *"screen=idle"* && $last == *"showing=chat"* ]]; then ok=pass; fi
  if [[ $answer == no && $trusted == False ]]; then ok=pass; fi
fi
echo "$version $answer: $ok (folder trusted in Claude's file: $trusted)"
