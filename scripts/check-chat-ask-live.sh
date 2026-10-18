#!/bin/zsh
# F-328's proof in a real Duo (F-329): an isolated dev instance, in the background, whose Home session
# runs the real `claude` TUI against the chat-mode spike's mock API (no login, no tokens). In chat mode it
# sends a turn that runs a Bash and then asks an AskUserQuestion, as Geoff's shop-triage turn did, and
# `chat-watch` logs every 0.1 s whether the card is up (`card=`) and whether the view drew it (the
# composer gone). A run passes when the card is drawn within 1 s of the question being read.
#   scripts/check-chat-ask-live.sh <out> [runs]      APP=<Duo.app> (default build/Duo.app)
#   CLAUDE=<path>   another claude (default: the one on PATH)
#   SCENARIO=<name> the mock's scenario (default permask: Bash, then the question; 2.1.219 asks
#                   for the Bash, so it gets ask1, the question alone)
#   ANSWER=1        the last run also answers through the card (Postgres) and checks Claude got it
# Isolated (CLAUDE.md): its own support folder and Claude config under /tmp, quit by SIGTERM to its pid.
set -u
root=${0:A:h:h}
out=${1:A} runs=${2:-10}
app=${APP:-$root/build/Duo.app}
real=${CLAUDE:-$(command -v claude)}
version=$($real --version 2>/dev/null | awk '{print $1}')
scenario=${SCENARIO:-permask}
[[ -z ${SCENARIO:-} && $version == 2.1.2[0-6]* ]] && scenario=ask1
mkdir -p $out
pass=0
for n in {1..$runs}; do
  fx=/tmp/caq-$n
  chmod -R u+w $fx 2>/dev/null; rm -rf $fx
  $root/Spikes/chat-mode/scratch.sh $fx >/dev/null
  print -- '---\ngoal: "chat ask proof"\n---\n\n# Home\n' > $fx/ws/HOME.md
  print -- '{}' > $fx/cfg/settings.json   # the CLI's own default mode (auto on 2.1.284 and later)
  mkdir -p $fx/sup/Duo
  print -- "{\"claudePath\":\"$real\",\"home\":\"$fx/ws\"}" > $fx/sup/Duo/state.json
  port=$((8900 + RANDOM % 90))
  (cd $root/Spikes/chat-mode && MOCK_PORT=$port MOCK_CWD=$fx/ws MOCK_LOG=$out/mock-$n.log node mock.mjs) >/dev/null 2>&1 &
  mock=$!
  sleep 0.5
  png=$out/run-$n.png
  then="wait:6,chat:on,wait:3,chat-state,chat-send:SCENARIO:$scenario go,+chat-watch:12:$out/run-$n-1s.png,wait:13,chat-state"
  [[ ${ANSWER:-} == 1 && $n == $runs ]] && then+=",chat-ask:pick=Postgres,wait:5,chat-state"
  err=$out/stderr-$n.txt
  env -u DUO_SUPPORT_DIR -u DUO_SOCKET -u DUO_TOKEN -u DUO_SIGNAL DUO_SUPPORT_DIR=$fx/sup CLAUDE_CONFIG_DIR=$fx/cfg DUO_AUTOCONFIRM=1 \
    ANTHROPIC_BASE_URL=http://127.0.0.1:$port ANTHROPIC_API_KEY=sk-ant-mock-key-0000000000000000000 DISABLE_AUTOUPDATER=1 \
    ANTHROPIC_MODEL=claude-haiku-5-5 \
    $app/Contents/MacOS/Duo --workspace $fx/ws --capture-window $png --then "$then" 2>$err &
  pid=$!
  for i in {1..90}; do [[ -f $png ]] && break; sleep 1; done
  sleep 1
  kill -TERM $pid 2>/dev/null; for i in {1..15}; do kill -0 $pid 2>/dev/null || break; sleep 1; done
  kill $mock 2>/dev/null
  done_line=$(grep -a "^chat-watch: done" $err | tail -1)
  lag=${${done_line##*lagMs=}:-never}
  if [[ $lag == <-> ]] && (( lag <= 1000 )); then ok=pass; pass=$((pass + 1)); else ok=FAIL; fi
  echo "run $n: $ok ${done_line#chat-watch: done }"
done
echo "$version $(basename ${app:h:h}): $pass of $runs passed (scenario $scenario)"
