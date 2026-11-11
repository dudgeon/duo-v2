#!/bin/bash
# Repro for F-658: starts a shared and an exclusive taker together, N times, in a scratch lock folder, and fails if
# the two were ever held at once. Usage: scripts/check-gpu-lock-race.sh [rounds] [lock script]
set -u
rounds="${1:-200}"
script="${2:-$(cd "$(dirname "$0")" && pwd)/gpu-lock.sh}"
T="$(mktemp -d "${TMPDIR:-/tmp}/glr.XXXXXX")"
export GPU_LOCK="$T/lock" GPU_LOCK_POLL=${POLL:-0.05} GPU_LOCK_WATCH=1
bad=0
for i in $(seq 1 "$rounds"); do
  rm -rf "$T/v" "$T/x" "$T"/s.* "$GPU_LOCK" "$GPU_LOCK".*
  "$script" --shared "r$i-s" bash -c "touch '$T/s.1'; sleep 0.15; [ -e '$T/x' ] && echo shared-saw-exclusive >> '$T/v'; rm -f '$T/s.1'" 2>/dev/null &
  a=$!
  perl -e 'select(undef,undef,undef,rand(0.06))'
  "$script" --exclusive "r$i-x" bash -c "touch '$T/x'; ls '$T'/s.* >/dev/null 2>&1 && echo exclusive-saw-shared >> '$T/v'; sleep 0.15; ls '$T'/s.* >/dev/null 2>&1 && echo exclusive-saw-shared >> '$T/v'; rm -f '$T/x'" 2>/dev/null &
  b=$!
  ( for _ in $(seq 1 40); do
      st=$("$script" --status 2>/dev/null)
      case "$st" in *"exclusive holder"*"shared holder"*|*"shared holder"*"exclusive holder"*)
        case "$st" in *"waiting for shared"*|*running*) ;; *) echo status-ambiguous >> "$T/v" ;; esac ;;
      esac
      sleep 0.01
    done ) &
  wait $a $b
  [ -s "$T/v" ] && { bad=$((bad + 1)); echo "round $i: overlap ($(tr '\n' ' ' < "$T/v"))"; }
done
rm -rf "$T"
echo "gpu-lock race: $((rounds - bad)) of $rounds rounds clean"
[ "$bad" -eq 0 ]
