#!/bin/bash
# check-gpu-lock.sh: proof for gpu-lock.sh's ticket queue, on a scratch lock (never the real one):
#  - a bare-mkdir holder D has the lock first;
#  - a dead ticket (a pid that's gone) sits at the front of the queue;
#  - A, B, C queue through gpu-lock.sh 0.5 s apart, each `sleep 2`;
#  - E, a bare-mkdir contender, retries every 0.5 s from the start and holds for 1 s when it wins.
#  - F queues and is stopped while waiting; G meets a lock that never got an owner (GPU_LOCK_ORPHAN=2).
# Expect: the dead ticket cleared, A then B then C in ticket order, no two holders ever overlapping, F's ticket gone,
# and G running once the ownerless lock is cleared.
#   scripts/check-gpu-lock.sh   (about 20 s, in /tmp)
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"; T="$(mktemp -d /tmp/lockq.XXXX)"; L="$T/gpu.lock"; LOG="$T/events.log"
export GPU_LOCK="$L" GPU_LOCK_POLL=0.2
ev() { echo "$(perl -MTime::HiRes=time -e 'printf "%.2f", time') $*" >> "$LOG"; }
export -f ev; export LOG

# D: bare mkdir holder, 2 s.
mkdir "$L"; echo "D $$" > "$L/owner"; ev "D start"
# A dead ticket at the front.
mkdir -p "$L.queue"; sleep 0 & dead=$!; wait $dead; echo "ghost $dead" > "$L.queue/0000000000"
( sleep 2; ev "D end"; rm -f "$L/owner"; rmdir "$L" ) &

# E: bare-mkdir contender.
( for i in $(seq 1 60); do
    if mkdir "$L" 2>/dev/null; then echo "E $(sh -c 'echo $PPID')" > "$L/owner"; ev "E start"; sleep 1; ev "E end"; rm -f "$L/owner"; rmdir "$L"; break; fi
    sleep 0.5
  done ) &

# F queues and is stopped while waiting: its ticket must go.
"$R/scripts/gpu-lock.sh" "test F" sleep 1 2> "$T/F.err" & fpid=$!
sleep 0.3
for j in A B C; do
  "$R/scripts/gpu-lock.sh" "test $j" bash -c "ev '$j start'; sleep 2; ev '$j end'" 2> "$T/$j.err" &
  sleep 0.5
done
sleep 0.5; kill -TERM $fpid; sleep 0.5; [ -e "$L.queue/0000000001" ] && echo "F's ticket is still there!" || echo "F stopped while queued: its ticket is gone"
wait
echo "--- events"; sort -n "$LOG"
echo "--- what A, B and C printed"; for j in F A B C; do echo "[$j]"; cat "$T/$j.err"; done
echo "--- checks"
sort -n "$LOG" | awk '
  / start$/ { if (held != "") { print "OVERLAP: " $2 " started while " held " held it"; bad=1 } held=$2; order = order $2 }
  / end$/   { if (held != $2) { print "MISMATCH end " $2 }; held="" }
  END { print "order: " order; if (!bad) print "no overlap" }'
ls -A "$L.queue" | grep -vE '^\.(next)$' | sed 's/^/left in queue: /'
[ -d "$L" ] && echo "lock still held!" || echo "lock free"
# An ownerless lock (a holder that died between mkdir and writing owner) is cleared after GPU_LOCK_ORPHAN seconds.
mkdir "$L"; start=$(date +%s)
GPU_LOCK_ORPHAN=2 "$R/scripts/gpu-lock.sh" "test G" true 2> "$T/G.err"
echo "ownerless lock: G ran after $(( $(date +%s) - start )) s:"; cat "$T/G.err"
rm -rf "$T"
