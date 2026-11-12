#!/bin/bash
# DL-338's boards (docs/design/chat-hover-actions-study/): captures of the turn row on hover, Copy's check, the selected
# message, Rewind's sheet and a busy chat, from the chat fixture, in the background (never shown, F-227).
#
#   scripts/check-chat-turn-actions.sh            build, then capture every state
#   NO_BUILD=1 scripts/check-chat-turn-actions.sh reuse build/Duo.app
#
# Writes build/ui/turn-<state>.png. The boards are the canvas https://claude.ai/artifact/HLHzGsZNpn3hS1KsZAZx71 (their
# sources hold the measurements: 22-high buttons, radius 6, a 1 pt controlEdge edge on pane, 12 icon in text2); look at each
# capture against its board, region by region, and measure with scripts/pixels.py.
set -euo pipefail
export DUO_ISOLATED=1
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
[ -n "${NO_BUILD:-}" ] || scripts/bundle.sh >/dev/null
out="$root/build/ui"
mkdir -p "$out"

capture() {   # capture <name> <then>
  local name="$1" then="$2" sup
  sup="$(mktemp -d /tmp/duo-ui.XXXXXX)"
  rm -f "$out/turn-$name.png"
  open -g -W -n --env DUO_ISOLATED=1 --env "DUO_SUPPORT_DIR=$sup" --stdout /dev/null --stderr "$out/turn-$name.log" "$root/build/Duo.app" \
    --args --state chat-text --then "$then" --capture "$out/turn-$name.png" &
  local pid=$!
  for ((i = 0; i < 120; i++)); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
  if kill -0 "$pid" 2>/dev/null; then kill "$pid"; echo "$name: no capture after 30 s" >&2; return 1; fi
  wait "$pid" || { echo "$name: capture failed (see build/ui/turn-$name.log)" >&2; return 1; }
  chmod -R u+w "$sup" 2>/dev/null; rm -rf "$sup"
  echo "$name → build/ui/turn-$name.png"
}

capture row-you "wait:1,chat-screen:idle,turn-hover:1,wait:1"
capture row-busy "wait:1,turn-hover:1,wait:1"
capture row-claude "wait:1,chat-screen:idle,turn-hover:2,wait:1"
capture copied "wait:1,chat-screen:idle,turn-hover:2,turn-copy:2,wait:1"
capture selected "wait:1,chat-screen:idle,turn-select:1,wait:1"
capture rewind-sheet "wait:1,chat-screen:idle,turn-rewind:1,wait:1"
