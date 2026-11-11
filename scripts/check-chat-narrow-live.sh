#!/bin/zsh
# F-456's proof in a real Duo, rewritten for DL-336 (Home's column is gone, so the narrow console is Home's page with the
# right pane widened): an isolated dev instance, in the background (F-227), a session started on Home's page, in chat against the
# chat-mode spike's mock API (no login, no tokens). With chat showing and a long reply: the hidden terminal follows each settled
# pane (one resize per settled move) and is never narrower than TerminalSession.heldMinColumns (60, Q-488 (a)), however
# narrow the console gets; switching to the terminal then costs no resize when the pane is 60 columns or more (a pane narrower
# than 60 costs one: Q-488's accepted cost, not reachable on Home's page, whose console has a 480 pt floor).
#   scripts/check-chat-narrow-live.sh <out>     APP=<Duo.app> (default build/Duo.app)  CLAUDE=<path> (default: on PATH)
# Isolated (CLAUDE.md): its own support folder and Claude config under /tmp, quit by SIGTERM to its pid.
set -u
export DUO_ISOLATED=1   # every duo2 here reaches only the test instance; refuses, never the user's Duo (F-529)
typeset -a c r
root=${0:A:h:h}
out=${1:A}
app=${APP:-$root/build/Duo.app}
real=${CLAUDE:-$(command -v claude)}
version=$($real --version 2>/dev/null | awk '{print $1}')
mkdir -p $out
fx=/tmp/cnl
chmod -R u+w $fx 2>/dev/null; rm -rf $fx
$root/Spikes/chat-mode/scratch.sh $fx >/dev/null   # trusts $fx/ws
mkdir -p $fx/sup/Duo
print -- '---\ngoal: "narrow proof"\n---\n\n# Home\n' > $fx/ws/HOME.md
print -- '{}' > $fx/cfg/settings.json
print -- "{\"claudePath\":\"$real\",\"home\":\"$fx/ws\"}" > $fx/sup/Duo/state.json
port=$((8900 + RANDOM % 90))
(cd $root/Spikes/chat-mode && MOCK_PORT=$port MOCK_CWD=$fx/ws MOCK_LOG=$out/mock.log node mock.mjs) >/dev/null 2>&1 &
mock=$!
sleep 0.5
png=$out/narrow.png; rm -f $png $out/stderr.txt
home=$(basename $fx/ws)
then="wait:8,open:$home,wait:2,new,wait:10,chat:on,wait:3,chat-send:SCENARIO:long go,wait:9,term-info"   # 1: the console's own width
then+=",right-width:760,wait:2,term-info"      # 2: the right pane wide, the console at its narrowest
then+=",right-width:460,wait:2,term-info"      # 3: back
then+=",chat:off,wait:2,term-info,chat-state"  # 4: the terminal chosen
err=$out/stderr.txt
env -u DUO_SUPPORT_DIR -u DUO_SOCKET -u DUO_TOKEN -u DUO_SIGNAL -u DUO_AUTOCONFIRM DUO_SUPPORT_DIR=$fx/sup CLAUDE_CONFIG_DIR=$fx/cfg \
  ANTHROPIC_BASE_URL=http://127.0.0.1:$port ANTHROPIC_API_KEY=sk-ant-mock-key-0000000000000000000 DISABLE_AUTOUPDATER=1 \
  ANTHROPIC_MODEL=claude-haiku-5-5 \
  $app/Contents/MacOS/Duo --workspace $fx/ws --capture-window $png --then "$then" 2>$err &
pid=$!
for i in {1..90}; do [[ -f $png ]] && break; sleep 1; done
sleep 1
kill -TERM $pid 2>/dev/null; for i in {1..15}; do kill -0 $pid 2>/dev/null || break; sleep 1; done
kill $mock 2>/dev/null
grep -a "^term-info:\|^chat-state:\|^chat-send:\|chat-fallback:" $err | cut -c1-200
sizes=("${(@f)$(grep -a '^term-info:' $err)}")
field() { print -- ${${1##*$2=}%% *} }
ok=FAIL
if (( ${#sizes} == 4 )); then
  for i in 1 2 3 4; do c[$i]=$(field "$sizes[$i]" cols); r[$i]=$(field "$sizes[$i]" hiddenResizes); done
  shown=$(field "$sizes[4]" onScreen)
  last=$(grep -a '^chat-state:' $err | tail -1)
  # Never under 60 columns; narrower with the right pane wide (but not below the floor), the same back; one resize per settled move;
  # none at the switch to the terminal; Claude's prompt on screen.
  if (( c[1] >= 60 && c[2] >= 60 && c[2] <= c[1] && c[3] == c[1] && r[2] - r[1] <= 1 && r[3] - r[2] <= 1 && c[4] == c[3] && r[4] == r[3] )) \
     && [[ $shown == true && $last == *"fallback=-"* ]]; then ok=pass; fi
  echo "cols: console ${c[1]}, right pane wide ${c[2]}, back ${c[3]}, terminal on screen ${c[4]}; hidden resizes ${r[1]} → ${r[2]} → ${r[3]} → ${r[4]}"
fi
echo "$version: $ok"
