#!/bin/zsh
# F-648: does an isolated Duo start Home's claude at launch with All projects' column closed (DL-315 default)?
# A stub `claude` logs each start; no real Claude, no tokens, background (F-227). Quit by SIGTERM to its pid.
#   docs/research/home-agent-panel-checks/check-f648.sh    APP=<Duo.app> (default the repo's build/Duo.app)  OUT=<folder> (default /tmp/hapf-out)
set -u
export DUO_ISOLATED=1
T=${0:A:h}
app=${APP:-${0:A:h:h:h:h}/build/Duo.app}
fx=/tmp/hapf; rm -rf $fx; mkdir -p ${OUT:-/tmp/hapf-out} $fx/ws $fx/sup/Duo $fx/cfg
print -- '---\ngoal: "f648"\n---\n\n# Home\n' > $fx/ws/HOME.md
print -- '{}' > $fx/cfg/settings.json
print -- "{\"claudePath\":\"$T/stub-claude\",\"home\":\"$fx/ws\"}" > $fx/sup/Duo/state.json
png=${OUT:-/tmp/hapf-out}/f648-launch.png; rm -f $png
err=${OUT:-/tmp/hapf-out}/f648-stderr.txt
env -u DUO_SUPPORT_DIR -u DUO_SOCKET -u DUO_TOKEN -u DUO_SIGNAL -u DUO_AUTOCONFIRM DUO_SUPPORT_DIR=$fx/sup CLAUDE_CONFIG_DIR=$fx/cfg \
  DUO_CLAUDE_CANDIDATES=$T/stub-claude DISABLE_AUTOUPDATER=1 \
  $app/Contents/MacOS/Duo --workspace $fx/ws --capture-window $png --then "wait:8,term-info" 2>$err &
pid=$!
for i in {1..60}; do [[ -f $png ]] && break; sleep 1; done
sleep 1
kill -TERM $pid 2>/dev/null; for i in {1..15}; do kill -0 $pid 2>/dev/null || break; sleep 1; done
pkill -f "$T/stub-claude" 2>/dev/null
echo "== claude starts"; cat $fx/claude-starts.log 2>/dev/null
echo "== term-info"; grep -a "^term-info" $err | cut -c1-300
echo "== support folder"; ls $fx/sup/Duo
