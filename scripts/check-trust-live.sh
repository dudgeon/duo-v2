#!/bin/zsh
# DL-229's live proof in a real Duo (F-361): an isolated dev instance, in the background, whose Home session runs the
# real `claude` TUI against the chat-mode spike's mock API (no login, no tokens, no real turn). The Home folder sits
# under a trusted parent, with no entry of its own; it becomes a git repository after the session starts, so `/fork`
# says "Workspace not trusted" (F-344). Then: the bar is read, Trust This Folder… asked, the sheet answered, Fork Again
# typed, and the second `/fork` must succeed in the same session. Never touches ~/.claude.json: its own config.
#   scripts/check-trust-live.sh <out>      APP=<Duo.app> (default build/Duo.app)   CLAUDE=<path> another claude
set -u
root=${0:A:h:h}
out=${1:A}
app=${APP:-$root/build/Duo.app}
real=${CLAUDE:-$(command -v claude)}
fx=/tmp/tnl
chmod -R u+w $fx 2>/dev/null; rm -rf $fx; mkdir -p $out $fx/cfg $fx/parent/ws $fx/sup/Duo
key=sk-ant-mock-key-0000000000000000000
parent=${fx:A}/parent
cat > $fx/cfg/.claude.json <<JSON
{"hasCompletedOnboarding":true,"theme":"dark","numStartups":5,"unknownKey":{"keep":[1,2,3]},
 "customApiKeyResponses":{"approved":["${key[-20,-1]}"],"rejected":[]},
 "projects":{"$parent":{"hasTrustDialogAccepted":true,"hasCompletedProjectOnboarding":true},
             "$parent/ws":{"hasTrustDialogAccepted":false}}}
JSON
cp $fx/cfg/.claude.json $out/claude-json-before.json
print -- '{}' > $fx/cfg/settings.json
print -- '---\ngoal: "trust proof"\n---\n\n# Home\n' > $fx/parent/ws/HOME.md
print -- "{\"claudePath\":\"$real\",\"home\":\"${fx:A}/parent/ws\"}" > $fx/sup/Duo/state.json
port=$((8900 + RANDOM % 90))
(cd $root/Spikes/chat-mode && MOCK_PORT=$port MOCK_CWD=$fx/parent/ws MOCK_LOG=$out/mock.log node mock.mjs) >/dev/null 2>&1 &
mock=$!
sleep 0.5
png=$out/live.png err=$out/stderr.txt
then="wait:8,type:SCENARIO:hello hi,enter,wait:6,wait:12,type:/fork try it,enter,wait:6,trust-state,dump,trust-ask,wait:1,answer:Trust Folder,wait:2,trust-state,trust-fork-again,wait:8,trust-state,dump"
env -u DUO_SUPPORT_DIR -u DUO_SOCKET -u DUO_TOKEN -u DUO_SIGNAL DUO_SUPPORT_DIR=$fx/sup CLAUDE_CONFIG_DIR=$fx/cfg HOME=$fx \
  ANTHROPIC_BASE_URL=http://127.0.0.1:$port ANTHROPIC_API_KEY=$key DISABLE_AUTOUPDATER=1 ANTHROPIC_MODEL=claude-haiku-5-5 \
  $app/Contents/MacOS/Duo --workspace $fx/parent/ws --capture-window $png --then "$then" 2>$err &
pid=$!
sleep 14; git -C $fx/parent/ws init -q   # a repository after the session started
for i in {1..120}; do [[ -f $png ]] && break; sleep 1; done
sleep 1
kill -TERM $pid 2>/dev/null; for i in {1..15}; do kill -0 $pid 2>/dev/null || break; sleep 1; done
kill $mock 2>/dev/null
cp $fx/cfg/.claude.json $out/claude-json-after.json
grep -a "trust-state\|trusted .* for Claude\|answer:" $err
echo "--- file diff"; diff $out/claude-json-before.json $out/claude-json-after.json
