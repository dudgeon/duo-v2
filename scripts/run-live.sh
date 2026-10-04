#!/bin/zsh
# Runs Duo once against a workspace with scripted actions, waits for the capture, then quits.
# Never hangs: gives up after $DUO_TIMEOUT seconds (default 90) and quits the app.
#   scripts/run-live.sh <workspace> <capture.png> <then-actions> [stderr-file]
# Set DUO_MODEL to run sessions on another model (e.g. claude-haiku-4-5-20251001, DL-33).
set -u
ws=$1 png=$2 then=$3 err=${4:-/dev/null}
rm -f "$png"
envargs=()
[[ -n ${DUO_MODEL:-} ]] && envargs=(--env "ANTHROPIC_MODEL=$DUO_MODEL")
[[ -n ${DUO_NO_EDIT_HOOK:-} ]] && envargs+=(--env "DUO_NO_EDIT_HOOK=1")   # sessions without the edit hook (DL-78)
open -n $envargs --stderr "$err" build/Duo.app --args --workspace "$ws" --capture-window "$png" --then "$then"
for i in {1..${DUO_TIMEOUT:-90}}; do
  [[ -f $png ]] && break
  sleep 1
done
sleep 2
# Quit the instance this script started, by pid (SIGTERM quits like ⌘Q). Never by app id: that
# can reach the user's own Duo (C-18).
pid=$(pgrep -f -- "--capture-window $png" | head -1)
if [[ -n $pid ]]; then kill -TERM $pid; for i in {1..10}; do kill -0 $pid 2>/dev/null || break; sleep 1; done; fi
[[ -f $png ]] && echo "captured $png" || { echo "no capture after ${DUO_TIMEOUT:-90}s"; exit 1; }
