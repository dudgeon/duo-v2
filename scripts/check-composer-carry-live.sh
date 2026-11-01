#!/bin/zsh
# ENH-292's proof in a real Duo (F-485): an isolated dev instance, in the background, whose Home session runs the real
# `claude` TUI against the chat-mode spike's mock API (no login, no tokens). Two runs:
#   typed:  words typed into chat's composer, then Terminal chosen (`chat:off`); then back to chat.
#   voice:  a spoken file dictated into the composer at speaking pace, Terminal chosen 4 s in.
# Each passes when Claude's prompt holds the words after the switch and no message reached Claude (the mock's log).
#   scripts/check-composer-carry-live.sh <out>      APP=<Duo.app> (default build/Duo.app), CLAUDE=<path> (default: on PATH)
# Isolated (CLAUDE.md): its own support folder and Claude config under /tmp, quit by SIGTERM to its pid.
set -u
root=${0:A:h:h}
out=${1:A}
app=${APP:-$root/build/Duo.app}
real=${CLAUDE:-$(command -v claude)}
version=$($real --version 2>/dev/null | awk '{print $1}')
mkdir -p $out
say -o $out/spoken.aiff "This sentence was dictated into chat, and the session then switched to the terminal while I kept talking." 2>/dev/null
pass=0
for run in typed voice; do
  fx=/tmp/ccl-$run
  chmod -R u+w $fx 2>/dev/null; rm -rf $fx
  $root/Spikes/chat-mode/scratch.sh $fx >/dev/null
  print -- '---\ngoal: "composer carry proof"\n---\n\n# Home\n' > $fx/ws/HOME.md
  print -- '{}' > $fx/cfg/settings.json
  mkdir -p $fx/sup/Duo
  print -- "{\"claudePath\":\"$real\",\"home\":\"$fx/ws\"}" > $fx/sup/Duo/state.json
  port=$((8900 + RANDOM % 90))
  (cd $root/Spikes/chat-mode && MOCK_PORT=$port MOCK_CWD=$fx/ws MOCK_LOG=$out/mock-$run.log node mock.mjs) >/dev/null 2>&1 &
  mock=$!
  sleep 0.5
  png=$out/$run.png
  if [[ $run == typed ]]; then
    then="wait:8,chat:on,wait:3,chat-type:typed in chat then switched,wait:1,chat-state,chat:off,wait:5,chat-state,chat:on,wait:4,chat-state"
  else
    then="wait:8,chat:on,wait:3,voice-file:$out/spoken.aiff,wait:4,voice-log,chat:off,wait:6,voice-log,chat-state"
  fi
  err=$out/stderr-$run.txt
  env -u DUO_SUPPORT_DIR -u DUO_SOCKET -u DUO_TOKEN -u DUO_SIGNAL DUO_SUPPORT_DIR=$fx/sup CLAUDE_CONFIG_DIR=$fx/cfg DUO_AUTOCONFIRM=1 \
    ANTHROPIC_BASE_URL=http://127.0.0.1:$port ANTHROPIC_API_KEY=sk-ant-mock-key-0000000000000000000 DISABLE_AUTOUPDATER=1 \
    ANTHROPIC_MODEL=claude-haiku-5-5 DUO_VOICE_FILE_REALTIME=1 \
    $app/Contents/MacOS/Duo --workspace $fx/ws --capture-window $png --then "$then" 2>$err &
  pid=$!
  for i in {1..90}; do [[ -f $png ]] && break; sleep 1; done
  sleep 1
  kill -TERM $pid 2>/dev/null; for i in {1..15}; do kill -0 $pid 2>/dev/null || break; sleep 1; done
  kill $mock 2>/dev/null
  # The chat-state line after the switch: the terminal showing, and Claude's prompt holding the words.
  after=$(grep -a -A1 "showing=terminal" $err | grep -a "input=" | tail -1)
  after=${after//\\n/ }   # the prompt's rows, as the screen wraps them
  want="dictated into chat"
  [[ $run == typed ]] && want="typed in chat then switched"
  sent=$(grep -ac "$want" $out/mock-$run.log 2>/dev/null)
  if [[ $after == *"$want"* ]] && (( ${sent:-0} == 0 )); then ok=pass; pass=$((pass + 1)); else ok=FAIL; fi
  echo "$run: $ok  ${after## }  (messages to the mock: ${sent:-0})"
  grep -a "chat-state:\|  mode=\|voice-log:" $err | sed 's/^/    /'
done
echo "$version: $pass of 2 passed"
