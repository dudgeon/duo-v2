#!/bin/zsh
# DL-336's live look at a Home session that needs you: an isolated dev instance, in the background (F-227), a session
# started on Home's page against the chat-mode spike's mock API (no login, no tokens), asked the mock's question (ask1).
# At All projects its Needs you card must be an ordinary card: name, `★ home`, the question, "Open Home"; no pointer
# card and no Home column. The capture is the proof; the stderr's `needs-you` lines say what the card shows.
#   scripts/check-home-card-live.sh <out>     APP=<Duo.app> (default build/Duo.app)  CLAUDE=<path> (default: on PATH)
# Isolated (CLAUDE.md): its own support folder and Claude config under /tmp, quit by SIGTERM to its pid.
set -u
export DUO_ISOLATED=1   # every duo2 here reaches only the test instance; refuses, never the user's Duo (F-529)
root=${0:A:h:h}
out=${1:A}
app=${APP:-$root/build/Duo.app}
real=${CLAUDE:-$(command -v claude)}
where=home-page
version=$($real --version 2>/dev/null | awk '{print $1}')
mkdir -p $out
fx=/tmp/chc
chmod -R u+w $fx 2>/dev/null; rm -rf $fx
$root/Spikes/chat-mode/scratch.sh $fx >/dev/null   # trusts $fx/ws
mkdir -p $fx/sup/Duo
print -- '---\ngoal: "home card proof"\n---\n\n# Home\n' > $fx/ws/HOME.md
print -- '{}' > $fx/cfg/settings.json
print -- "{\"claudePath\":\"$real\",\"home\":\"$fx/ws\"}" > $fx/sup/Duo/state.json
port=$((8900 + RANDOM % 90))
(cd $root/Spikes/chat-mode && MOCK_PORT=$port MOCK_CWD=$fx/ws MOCK_LOG=$out/mock.log node mock.mjs) >/dev/null 2>&1 &
mock=$!
sleep 0.5
png=$out/home-card.png; err=$out/stderr.txt; rm -f $png $err
home=$(basename $fx/ws)
then="wait:8,open:$home,wait:2,new,wait:10,chat:on,wait:3,chat-send:SCENARIO:ask1 go,wait:9,chat-state"
then+=",zoom-out,wait:4"
env -u DUO_SUPPORT_DIR -u DUO_SOCKET -u DUO_TOKEN -u DUO_SIGNAL -u DUO_AUTOCONFIRM DUO_SUPPORT_DIR=$fx/sup CLAUDE_CONFIG_DIR=$fx/cfg \
  ANTHROPIC_BASE_URL=http://127.0.0.1:$port ANTHROPIC_API_KEY=sk-ant-mock-key-0000000000000000000 DISABLE_AUTOUPDATER=1 \
  ANTHROPIC_MODEL=claude-haiku-5-5 \
  $app/Contents/MacOS/Duo --workspace $fx/ws --capture-window $png --then "$then" 2>$err &
pid=$!
for i in {1..90}; do [[ -f $png ]] && break; sleep 1; done
sleep 1
kill -TERM $pid 2>/dev/null; for i in {1..15}; do kill -0 $pid 2>/dev/null || break; sleep 1; done
kill $mock 2>/dev/null
grep -a "^chat-state:" $err | cut -c1-200
echo "capture: $png"
