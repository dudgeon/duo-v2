#!/bin/zsh
# F-539's live proof: chat mode shows Claude working for the whole of a long, silent turn, in a pane
# too narrow for the footer's `esc to interrupt`. An isolated Duo (its own support folder, in the
# background), Home's session on the real `claude` (your login, Haiku 5.5: one short turn that runs a
# 45 s foreground sleep), chat on, the window narrowed (Home's chat is ~43 columns at the default size anyway). Mid-turn it logs what chat reads every few
# seconds and draws the window twice; it passes when every mid-turn read is busy and the working line
# is drawn, while the terminal is narrower than the footer.
#   scripts/check-chat-working-live.sh <out> <workspace>   APP=<Duo.app>  CLAUDE=<claude>  WIDTH=<pt>
# The workspace must be one Claude Code already trusts (its trust question would stop the turn).
set -u
export DUO_ISOLATED=1   # every duo2 here reaches only the test instance; refuses, never the user's Duo (F-529)
root=${0:A:h:h}
out=${1:A} ws=${2:A}
app=${APP:-$root/build/Duo.app}
real=${CLAUDE:-$(command -v claude)}
version=$($real --version 2>/dev/null | awk '{print $1}')
width=${WIDTH:-760}
mkdir -p $out
sup=/tmp/cwl-${version//./}
chmod -R u+w $sup 2>/dev/null; rm -rf $sup; mkdir -p $sup/Duo
[[ -f $ws/HOME.md ]] || print -- '---\ngoal: "chat working proof"\n---\n\n# Home\n' > $ws/HOME.md
print -- "{\"claudePath\":\"$real\",\"home\":\"$ws\"}" > $sup/Duo/state.json
prompt="Use the Bash tool to run python3 -c 'import time; time.sleep(45)' in the foreground and then reply with one word."
tag=$version
then="window-width:$width,wait:8,chat:on,wait:3,term-info,chat-state,chat-send:$prompt,wait:4,chat-working,window-shot:$out/mid-$tag-early.png"
for i in {1..7}; do then+=",wait:5,chat-working"; done
then+=",term-info,window-shot:$out/mid-$tag-late.png,wait:20,chat-working,chat-state"
png=$out/end-$tag.png err=$out/stderr-$tag.txt
rm -f $png
env -u DUO_SUPPORT_DIR -u DUO_SOCKET -u DUO_TOKEN -u DUO_SIGNAL -u CLAUDE_CONFIG_DIR -u ANTHROPIC_BASE_URL -u CLAUDECODE \
  -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN \
  DUO_ISOLATED=1 DUO_SUPPORT_DIR=$sup CLAUDE_CONFIG_DIR=${DUO_CLAUDE_CONFIG_DIR:-$HOME/.claude} DUO_AUTOCONFIRM=1 DISABLE_AUTOUPDATER=1 ANTHROPIC_MODEL=${DUO_MODEL:-claude-haiku-5-5} \
  $app/Contents/MacOS/Duo --workspace $ws --capture-window $png --then "$then" 2>$err &
pid=$!
for i in {1..150}; do [[ -f $png ]] && break; sleep 1; done
sleep 1
kill -TERM $pid 2>/dev/null; for i in {1..15}; do kill -0 $pid 2>/dev/null || break; sleep 1; done
# Mid-turn: the reads between the send and the turn's end (the python sleep runs about 45 s).
reads=("${(@f)$(grep -a '^chat-working:' $err)}")
cols=$(grep -a '^term-info:' $err | tail -1 | sed -E 's/.*cols=([0-9]+).*/\1/')
mid=(${reads[1,8]})
idle=${#${(M)mid:#*screen=idle*}}
drawn=${#${(M)mid:#*line=Working*}}
echo "$version: terminal $cols columns; mid-turn reads ${#mid}, busy+drawn $drawn, idle $idle"
print -l -- $reads | sed 's/^/  /'
[[ ${#mid} -ge 6 && $idle == 0 && $drawn == ${#mid} ]] && { echo "$version: pass"; exit 0; } || { echo "$version: FAIL"; exit 1; }
