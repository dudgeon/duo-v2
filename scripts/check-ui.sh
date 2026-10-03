#!/bin/bash
# The comparison loop (handoff §0.2) for every target state, in one command.
#
#   scripts/check-ui.sh                    build, capture every state, compare each with its target
#   scripts/check-ui.sh overview project   only these states
#   NO_BUILD=1 scripts/check-ui.sh         reuse build/Duo.app
#
# Writes build/ui/<state>.png (the app) and build/ui/<state>-compare.png (TARGET | BUILD | DIFFERENCE).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
[ -n "${NO_BUILD:-}" ] || scripts/bundle.sh >/dev/null
app="$root/build/Duo.app/Contents/MacOS/Duo"
out="$root/build/ui"
mkdir -p "$out"
states=("$@")
[ ${#states[@]} -gt 0 ] || states=(overview flow-zoom-1 project flow-zoom-2 flow-zoom-3 flow-zoom-4)
extra=()

# Run the app with a watchdog: a launch that never captures (findings F-8) fails instead of hanging.
capture() {
  local s="$1" i
  "$app" --state "$s" --capture "$out/$s.png" ${extra[@]+"${extra[@]}"} >/dev/null 2>"$out/$s.log" &
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
  bash docs/design/build-handoff/tools/compare.sh "$s" "$out/$s.png" "$out/$s-compare.png" --content-only >/dev/null
  echo "$s  →  build/ui/$s-compare.png"
done
