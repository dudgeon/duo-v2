#!/bin/bash
# The comparison loop (handoff §0.2) for every target state, in one command.
#
#   scripts/check-ui.sh                    build, capture every state, compare each with its target
#   scripts/check-ui.sh overview project   only these states
#   NO_BUILD=1 scripts/check-ui.sh         reuse build/Duo.app
#   WINDOW=1280x800 scripts/check-ui.sh …  at another window size (DB-25)
#
# Writes build/ui/<state>.png (the app) and build/ui/<state>-compare.png (TARGET | BUILD | DIFFERENCE).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
[ -n "${NO_BUILD:-}" ] || scripts/bundle.sh >/dev/null
out="$root/build/ui"
mkdir -p "$out"
states=("$@")
[ ${#states[@]} -gt 0 ] || states=(overview flow-zoom-1 project flow-zoom-2 flow-zoom-3 flow-zoom-4)
extra=()
[ -z "${WINDOW:-}" ] || extra+=(--window "$WINDOW")

# Run the app with a watchdog: a launch that never captures (findings F-8) fails instead of hanging.
capture() {
  local s="$1" i
  # Launched through LaunchServices: once the bundle has been opened with `open`, executing its
  # binary directly can leave the app without a window (findings F-19).
  open -g -W -n --stdout /dev/null --stderr "$out/$s.log" "$root/build/Duo.app" --args --state "$s" --capture "$out/$s.png" ${extra[@]+"${extra[@]}"} &
  local pid=$!
  for ((i = 0; i < 120; i++)); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid"; echo "$s: no capture after 30 s (see build/ui/$s.log)" >&2; return 1
  fi
  wait "$pid" || { echo "$s: capture failed (see build/ui/$s.log)" >&2; return 1; }
}

for s in "${states[@]}"; do
  rm -f "$out/$s.png"
  capture "$s"
  [ -n "${NO_COMPARE:-}" ] && continue   # check-chat.sh crops and compares its own
  bash docs/design/build-handoff/tools/compare.sh "$s" "$out/$s.png" "$out/$s-compare.png" --content-only >/dev/null
  echo "$s  →  build/ui/$s-compare.png"
done
