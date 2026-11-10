#!/bin/zsh
# F-640's proof in a real Duo: an isolated dev instance, in the background (F-227), Home's session in chat against the
# chat-mode spike's mock API (no login, no tokens). On Home's own page, with a question pending (the mock's ask1), chat
# falls back to the terminal. The terminal's view must then sit in the console on screen, not in Home's column (which
# stays in the window, out of sight, under a project). The same after Back to Chat flips back, and at All projects
# afterwards (Home's column must hold it there).
#   scripts/check-chat-fallback-slot-live.sh <out>     APP=<Duo.app> (default build/Duo.app)  CLAUDE=<path> (default: on PATH)
#   WHERE=home-page (default) | all-projects           where the fallback happens
#   RULE=old                                           the slot rule before F-640: the run must FAIL (the failing-first proof)
# Isolated (CLAUDE.md): its own support folder and Claude config under /tmp, quit by SIGTERM to its pid.
set -u
export DUO_ISOLATED=1   # every duo2 here reaches only the test instance; refuses, never the user's Duo (F-529)
root=${0:A:h:h}
out=${1:A}
app=${APP:-$root/build/Duo.app}
real=${CLAUDE:-$(command -v claude)}
where=${WHERE:-home-page}
version=$($real --version 2>/dev/null | awk '{print $1}')
mkdir -p $out
fx=/tmp/cfs
chmod -R u+w $fx 2>/dev/null; rm -rf $fx
$root/Spikes/chat-mode/scratch.sh $fx >/dev/null   # trusts $fx/ws
mkdir -p $fx/sup/Duo
print -- '---\ngoal: "fallback slot proof"\n---\n\n# Home\n' > $fx/ws/HOME.md
print -- '{}' > $fx/cfg/settings.json
print -- "{\"claudePath\":\"$real\",\"home\":\"$fx/ws\"}" > $fx/sup/Duo/state.json
port=$((8900 + RANDOM % 90))
(cd $root/Spikes/chat-mode && MOCK_PORT=$port MOCK_CWD=$fx/ws MOCK_LOG=$out/mock.log node mock.mjs) >/dev/null 2>&1 &
mock=$!
sleep 0.5
png=$out/slot-$where.png; err=$out/stderr-$where.txt; rm -f $png $err
home=$(basename $fx/ws)
then="wait:8,chat:on,wait:3"
[[ $where == home-page ]] && then+=",open:$home,wait:2"
then+=",chat-send:SCENARIO:ask1 go,wait:7,chat-state"
then+=",chat-fallback,wait:2,term-info,chat-state"          # 1: right after the forced flip
then+=",chat:on,+chat-fallback,wait:3,term-info,chat-state"   # 2: Back to Chat, and straight back to the terminal
then+=",chat:off,wait:2,term-info"                           # 3: the terminal chosen
if [[ $where == home-page ]]; then then+=",home,wait:2,term-info"; else then+=",open:$home,wait:2,term-info"; fi   # 4: the other place
[[ $where == home-page ]] && then+=",open:$home,wait:2,term-info" || then+=",home,wait:2,term-info"   # 5: and back
then+=",dump"
env -u DUO_SUPPORT_DIR -u DUO_SOCKET -u DUO_TOKEN -u DUO_SIGNAL -u DUO_AUTOCONFIRM DUO_SLOT_RULE=${RULE:-new} DUO_SUPPORT_DIR=$fx/sup CLAUDE_CONFIG_DIR=$fx/cfg \
  ANTHROPIC_BASE_URL=http://127.0.0.1:$port ANTHROPIC_API_KEY=sk-ant-mock-key-0000000000000000000 DISABLE_AUTOUPDATER=1 \
  ANTHROPIC_MODEL=claude-haiku-5-5 \
  $app/Contents/MacOS/Duo --workspace $fx/ws --capture-window $png --then "$then" 2>$err &
pid=$!
for i in {1..90}; do [[ -f $png ]] && break; sleep 1; done
sleep 1
kill -TERM $pid 2>/dev/null; for i in {1..15}; do kill -0 $pid 2>/dev/null || break; sleep 1; done
kill $mock 2>/dev/null
grep -a "^term-info:\|^chat-state:\|^chat-send:" $err | cut -c1-260
infos=("${(@f)$(grep -a '^term-info:' $err)}")
ok=pass
(( ${#infos} == 5 )) || ok=FAIL
# Under a project the terminal belongs to the console's slot; at All projects, to Home's column.
if [[ $where == home-page ]]; then want=(console console console home console); else want=(home home home console home); fi
for i in 1 2 3 4 5; do
  got=${${infos[$i]:-}##*place=}; got=${got%% *}
  [[ $got == $want[$i] && ${infos[$i]:-} == *"onScreen=true"* ]] || { ok=FAIL; echo "step $i: the terminal is in '$got', wanted '$want[$i]'"; }
done
grep -aq "Which database" $err || { ok=FAIL; echo "the terminal's text doesn't hold the question"; }
echo "$version $where: $ok"
[[ $ok == pass ]]
