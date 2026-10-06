#!/bin/bash
# Proves a motion with frames at set times (DL-130, Q-77): runs the fixture state with the motion
# clock slowed (DUO_MOTION_SCALE, default 10), does the setup actions, then the trigger with
# `film:` frames right after it, once with Reduce Motion off and once on.
#
#   scripts/check-motion.sh <name> <state> "<setup actions>" "<trigger action>" [offsets ms, default 0|500|1000|1500|2500]
#
# Frames land in build/motion/<name>/{motion,reduce}-<ms>.png, plus each run's log. Offsets are
# real milliseconds: at scale 10 a 200 ms motion runs 2000 ms. NO_BUILD=1 skips the bundle.
# A <state> of `live:<workspace>` runs on real folders (`--workspace`) with an empty scratch
# CLAUDE_CONFIG_DIR, so sessions start signed out and spend nothing. BEFORE_EACH="<command>" runs
# before each of the two runs (to put a workspace's files back).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
[ $# -ge 4 ] || { sed -n 2,10p "$0"; exit 2; }
name="$1" state="$2" setup="$3" trigger="$4" offsets="${5:-0|500|1000|1500|2500}"
scale="${DUO_MOTION_SCALE:-10}"
[ -n "${NO_BUILD:-}" ] || scripts/bundle.sh >/dev/null
out="$root/build/motion/$name"
rm -rf "$out"; mkdir -p "$out"
# A short support folder of its own (the control socket's path must stay under 104 characters).
support="$(mktemp -d /tmp/dmo.XXXX)"
trap 'rm -rf "$support"' EXIT

run() {
  local mode="$1" reduce="$2" actions="" last i pid
  [ -z "$setup" ] || actions="$setup,"
  actions+="$trigger,+film:$out/$mode:$offsets"
  last="${offsets##*|}"
  actions+=",wait:$(awk "BEGIN{print $last/1000}")"
  [ -z "${BEFORE_EACH:-}" ] || bash -c "$BEFORE_EACH"
  local where=(--state "$state") envs=()
  if [[ "$state" == live:* ]]; then
    where=(--workspace "${state#live:}")
    mkdir -p "$support/claude-$mode"; envs=(--env CLAUDE_CONFIG_DIR="$support/claude-$mode")
  fi
  open -W -n --env DUO_SUPPORT_DIR="$support/$mode" --env DUO_MOTION_SCALE="$scale" --env DUO_REDUCE_MOTION="$reduce" ${DUO_MOTION_HOLD:+--env DUO_MOTION_HOLD=$DUO_MOTION_HOLD} ${envs[@]+"${envs[@]}"} \
    --stdout /dev/null --stderr "$out/$mode.log" build/Duo.app --args "${where[@]}" --then "$actions" --capture "$out/$mode-rest.png" &
  pid=$!
  for ((i = 0; i < 240; i++)); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
  if kill -0 "$pid" 2>/dev/null; then kill "$pid"; echo "$name/$mode: no capture after 60 s" >&2; return 1; fi
  wait "$pid" || { echo "$name/$mode: failed (see $out/$mode.log)" >&2; return 1; }
  grep -h "^film:" "$out/$mode.log" | sed "s|$out/||" || true
}

run motion 0
run reduce 1
echo "$name → build/motion/$name/"
