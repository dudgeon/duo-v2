#!/bin/zsh
# Live run of duo2 view group / project pin against an isolated, background Duo (sample projects only).
set -u
export DUO_ISOLATED=1
cd /Users/geoff/repos/duo-v2/.claude/worktrees/board-by-activity || exit 1
S=$(cd "$(mktemp -d /tmp/pin.XXXX)" && pwd -P)
WS=$S/ws CFG=$S/cfg SUP=$S/sup
mkdir -p $WS/alpha $WS/beta $CFG/projects $SUP/Duo
print -- "# Home" > $WS/HOME.md
for p in alpha beta; do print -r -- "---"$'\n'"goal: sample $p"$'\n'"health: on-track"$'\n'"next: none"$'\n'"---"$'\n\n'"# $p" > $WS/$p/PROJECT.md; done
printf '#!/bin/sh\nexec sleep 900\n' > $S/claude; chmod +x $S/claude
print -r -- "{\"claudePath\":\"$S/claude\",\"root\":\"$WS\"}" > $SUP/Duo/state.json
env -u DUO_SOCKET -u DUO_TOKEN -u DUO_SESSION_ID DUO_SUPPORT_DIR=$SUP CLAUDE_CONFIG_DIR=$CFG \
  build/Duo.app/Contents/MacOS/Duo --workspace $WS 2> $S/duo.err &
duo=$!
trap 'kill -TERM $duo 2>/dev/null' EXIT
for i in {1..40}; do [[ -f $SUP/Duo/endpoint.json ]] && break; sleep 1; done
export DUO_SOCKET=$(python3 -c "import json;print(json.load(open('$SUP/Duo/endpoint.json'))['socket'])")
export DUO_TOKEN=$(python3 -c "import json;print(json.load(open('$SUP/Duo/endpoint.json'))['token'])")
d=build/Duo.app/Contents/Helpers/duo2
sleep 3
run() { print -- "\$ duo2 $*"; $d "$@" 2>&1 | head -5; print -- "  exit ${pipestatus[1]}"; }
run view home board
run view group none
run view group folder
run view group activity
run view group bogus
run view group earlier expand
run project pin alpha
run project pin alpha
run project pin alpha off
run project pin beta on
run project pin nonesuch
run projects
print -- "state: $(cat $SUP/Duo/state.json)"
