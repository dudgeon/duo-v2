#!/bin/zsh
# Isolated Duo probe of a public Google Doc with every duo2 browser verb (gdocs-frame, 2026-10-29).
set -u
tree=/Users/geoff/repos/duo-v2/.claude/worktrees/gdocs-frame
app=$tree/build/Duo.app; duo2=$app/Contents/Helpers/duo2
root=/tmp/gdf; rm -rf $root; mkdir -p $root/sup/Duo $root/cc $root/ws/Home $root/ws/work/gdocs $root/dl
printf -- '---\ngoal: "Home"\n---\n\n# Home\n' > $root/ws/Home/HOME.md
printf -- '---\ngoal: "Probe"\n---\n\n# gdocs\n' > $root/ws/work/gdocs/PROJECT.md
printf '# test instance only\ndocs.google.com\n' > $root/sup/Duo/allowed-sites.txt
open -g -n --env DUO_SUPPORT_DIR=$root/sup --env CLAUDE_CONFIG_DIR=$root/cc --env ANTHROPIC_MODEL=claude-haiku-5-5 --env DUO_DOWNLOADS_DIR=$root/dl --env DUO_AUTOCONFIRM=1 \
  --stdout $root/duo.log --stderr $root/duo.log "$app" --args --workspace $root/ws
for i in {1..30}; do pid=$(pgrep -f -- "--workspace $root/ws" | head -1); [[ -n $pid ]] && break; sleep 1; done
[[ -n ${pid:-} ]] || { echo "no Duo"; exit 1; }
ep=$root/sup/Duo/endpoint.json
for i in {1..60}; do [[ -f $ep ]] && break; sleep 1; done
export DUO_SOCKET=$(python3 -I -c "import json,sys;print(json.load(open(sys.argv[1]))['socket'])" $ep)
export DUO_TOKEN=$(python3 -I -c "import json,sys;print(json.load(open(sys.argv[1]))['token'])" $ep)
[[ -n $DUO_SOCKET && -n $DUO_TOKEN ]] || { echo "no endpoint"; kill -TERM $pid; exit 1; }
echo "pid $pid socket $DUO_SOCKET"
ms() { python3 -c 'import time;print(int(time.time()*1000))'; }
d() { local t0=$(ms); echo "\$ duo2 $*"; "$duo2" "$@" 2>&1 | head -${LINES_MAX:-25}; echo "  [$(( $(ms) - t0 )) ms]"; }
U="https://docs.google.com/document/d/1dCR2aEoBJj_Yqcs6GuM7lUPr0gag77L5OSgDa8bebsI/edit"
sleep 6
d open gdocs
d browser sites
d browser open "$U"
d browser wait ".kix-canvas-tile-content" --timeout 20
sleep 3
d browser tabs
LINES_MAX=40 d browser read
d browser read ".docs-title-input"
d browser read ".kix-canvas-tile-content"
d browser read ".navigation-widget-content"
d browser screenshot
d browser screenshot --full-page
d browser scroll down
d browser scroll 2000
d browser scroll top
d browser click ".kix-canvas-tile-content"
d browser click "#docs-file-menu"
sleep 1
LINES_MAX=12 d browser read "[role=menu]"
d browser click ".docs-texteventtarget-iframe"
d browser fill ".docs-texteventtarget-iframe" "hello"
d browser zoom 125
d browser zoom reset
d browser print --pdf $root/doc.pdf
d browser go "https://docs.google.com/document/d/1dCR2aEoBJj_Yqcs6GuM7lUPr0gag77L5OSgDa8bebsI/export?format=md"
sleep 3
d browser downloads
d browser back
d browser go "https://docs.google.com/document/d/1dCR2aEoBJj_Yqcs6GuM7lUPr0gag77L5OSgDa8bebsI/mobilebasic"
sleep 3
LINES_MAX=8 d browser read
d browser go "https://accounts.google.com/"
d browser allow accounts.google.com
ls -la $root/dl $root/doc.pdf 2>&1
kill -TERM $pid; for i in {1..10}; do kill -0 $pid 2>/dev/null || break; sleep 1; done
echo done
