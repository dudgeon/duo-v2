#!/bin/bash
# Multi-window slice 1's captures (DL-311 to DL-314; docs/design/multi-window-handoff): two windows in
# different colours, light and dark; the same under Classic; Home in a second window. Fixture state,
# background, isolated (F-227): nothing is shown and Geoff's Duo is never touched.
#
#   scripts/check-windows.sh            build, then capture every case to build/windows/
#   NO_BUILD=1 scripts/check-windows.sh reuse build/Duo.app
#   scripts/check-windows.sh two-light  only these cases (two-light two-dark classic home-light home-dark)
#
# Each case writes <case>-w1.png (window 1, whole, with its toolbar) and <case>-w2.png (window 2).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
[ -n "${NO_BUILD:-}" ] || scripts/bundle.sh >/dev/null
out="${UI_OUT:-$root/build/windows}"
mkdir -p "$out"; out="$(cd "$out" && pwd)"
cases=("$@")
[ ${#cases[@]} -gt 0 ] || cases=(two-light two-dark classic home-light home-dark)

run() {   # <case> <appearance> <then-actions...>
  local c="$1" look="$2"; shift 2
  local support; support="$(mktemp -d /tmp/duo-mw.XXXX)"
  rm -f "$out/$c-w1.png" "$out/$c-w2.png"
  local IFS=,   # --then takes one comma-separated list (no commas inside an action)
  local then=(--then "$*")
  unset IFS
  open -g -W -n --env DUO_APPEARANCE="$look" --env DUO_SUPPORT_DIR="$support" --stdout /dev/null --stderr "$out/$c.log" \
    "$root/build/Duo.app" --args --state overview "${then[@]}" --capture-window "$out/$c-w1.png" &
  local pid=$! i
  for ((i = 0; i < 160; i++)); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
  if kill -0 "$pid" 2>/dev/null; then kill "$pid"; echo "$c: no capture after 40 s (see $out/$c.log)" >&2; return 1; fi
  wait "$pid" || { echo "$c: capture failed (see $out/$c.log)" >&2; return 1; }
  rm -rf "$support"
  echo "$c  →  $out/$c-w1.png  $out/$c-w2.png"
}

for c in "${cases[@]}"; do
  case "$c" in
    # Window 1 Ochre at All projects; window 2 opens on checkout-redesign and takes Blue (the first free colour).
    two-light) run "$c" light window-colour:1:ochre window-new:checkout-redesign wait:1 "window-shot:2:$out/$c-w2.png" ;;
    two-dark)  run "$c" dark  window-colour:1:ochre window-new:checkout-redesign wait:1 "window-shot:2:$out/$c-w2.png" ;;
    # The same under Classic: both windows draw Classic, the swatch leaves the toolbar (board 4c A).
    classic)   run "$c" classic window-colour:1:ochre window-new:checkout-redesign wait:1 "window-shot:2:$out/$c-w2.png" ;;
    # Home in a second window (board 10′ A): window 1 Blue holds Home; window 2 opens at All projects and takes Ochre.
    home-light) run "$c" light window-colour:1:blue window-new wait:1 "window-shot:2:$out/$c-w2.png" ;;
    home-dark)  run "$c" dark  window-colour:1:deep-blue window-new wait:1 "window-shot:2:$out/$c-w2.png" ;;
    *) echo "unknown case $c" >&2; exit 2 ;;
  esac
done
