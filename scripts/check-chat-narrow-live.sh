#!/bin/zsh
# F-452's proof in a real Duo: an isolated dev instance, in the background (F-227), Home's session in chat against the
# chat-mode spike's mock API (no login, no tokens). Home's chat is narrow at All projects and wide on Home's own page, the
# move that left Geoff's terminal at two widths (F-449). With chat showing: a long reply, Home's page (wide), back to All
# projects (narrow), then four quick flips. The hidden terminal must follow each settled pane (one resize per settled
# move, at most one for the flips), and switching to the terminal must not resize it again: it comes back at the width
# Claude drew at.
#   scripts/check-chat-narrow-live.sh <out>     APP=<Duo.app> (default build/Duo.app)  CLAUDE=<path> (default: on PATH)
# Isolated (CLAUDE.md): its own support folder and Claude config under /tmp, quit by SIGTERM to its pid.
set -u
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
then="wait:8,chat:on,wait:3,chat-send:SCENARIO:long go,wait:9,term-info"
then+=",open:$home,wait:2,term-info,home,wait:2,term-info"
then+=",open:$home,+home,+open:$home,+home,wait:2,term-info"
then+=",chat:off,wait:2,term-info,chat-state"
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
if (( ${#sizes} == 5 )); then
  for i in 1 2 3 4 5; do c[$i]=$(field "$sizes[$i]" cols); r[$i]=$(field "$sizes[$i]" hiddenResizes); done
  shown=$(field "$sizes[5]" onScreen)
  last=$(grep -a '^chat-state:' $err | tail -1)
  # Wide on Home's page and narrow again, one resize each; the flips at most one; none at the switch; Claude's prompt on screen.
  if (( c[2] > c[1] && c[3] == c[1] && r[2] - r[1] == 1 && r[3] - r[2] == 1 && r[4] - r[3] <= 1 && c[5] == c[4] && r[5] == r[4] )) \
     && [[ $shown == true && $last == *"fallback=-"* ]]; then ok=pass; fi
  echo "cols: All projects ${c[1]}, Home's page ${c[2]}, back ${c[3]}, after the flips ${c[4]}, terminal on screen ${c[5]}; hidden resizes ${r[1]} → ${r[2]} → ${r[3]} → ${r[4]} → ${r[5]}"
fi
echo "$version: $ok"
