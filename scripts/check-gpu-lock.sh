#!/bin/bash
# check-gpu-lock.sh: proof for gpu-lock.sh's ticket queue, on a scratch lock (never the real one):
#  - a bare-mkdir holder D has the lock first;
#  - a dead ticket (a pid that's gone) sits at the front of the queue;
#  - A, B, C queue through gpu-lock.sh 0.5 s apart, each `sleep 2`;
#  - E, a bare-mkdir contender, retries every 0.5 s from the start and holds for 1 s when it wins.
#  - F queues and is stopped while waiting; G meets a lock that never got an owner (GPU_LOCK_ORPHAN=2).
#  - H waits behind an owner it can't signal (pid 1: kill -0 says "not permitted"), which must be waited on, not cleared;
#  - I: a bare holder releases and re-takes in a tight loop while J and K are queued at the front: never two at once;
#  - a bare script that releases twice (visible-gate.sh's unlock plus its EXIT trap) deletes Q's lock while Q's job
#    runs; Q must warn, and Q's release must leave the next holder's lock alone.
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

echo "--- H: an owner that can't be signalled (pid 1)"
mkdir "$L"; echo "launchd 1" > "$L/owner"
"$R/scripts/gpu-lock.sh" "test H" true 2> "$T/H.err" & h=$!
sleep 3
if [ "$(cat "$L/owner" 2>/dev/null)" = "launchd 1" ] && kill -0 $h 2>/dev/null; then echo "H waits behind pid 1: ok"; else echo "H FAILED: pid 1's lock was cleared"; fi
rm -f "$L/owner"; rmdir "$L"; wait $h; grep -q "taken by test H" "$T/H.err" && echo "H ran once it was released: ok"

echo "--- I: a bare holder in a tight loop, J and K queued"
: > "$LOG"
( for i in $(seq 1 40); do
    until mkdir "$L" 2>/dev/null; do sleep 0.05; done
    echo "bare $(sh -c 'echo $PPID')" > "$L/owner"; ev "I start"; sleep 0.05; ev "I end"; rm -f "$L/owner"; rmdir "$L"
  done ) &
sleep 0.2
for j in J K; do "$R/scripts/gpu-lock.sh" "test $j" bash -c "ev '$j start'; sleep 0.5; ev '$j end'" 2> "$T/$j.err" & sleep 0.1; done
wait
sort -n "$LOG" | awk '
  / start$/ { if (held != "") { print "OVERLAP: " $2 " started while " held " held it"; bad=1 } held=$2; n[$2]++ }
  / end$/   { held="" }
  END { printf "I held it %d times, J %d, K %d: %s\n", n["I"], n["J"], n["K"], bad ? "OVERLAP" : "no overlap" }'

echo "--- a double release takes the lock from Q"
GPU_LOCK_WATCH=0.3 "$R/scripts/gpu-lock.sh" "test Q" sleep 2 2> "$T/Q.err" & q=$!
sleep 0.5
# The double release (as visible-gate.sh's EXIT trap does it), then a bare contender takes the lock.
rm -f "$L/owner"; rmdir "$L" 2>/dev/null
mkdir "$L"; echo "contender $$" > "$L/owner"
wait $q
grep -q "WARNING: the lock was taken from test Q" "$T/Q.err" && echo "Q warned that its lock was taken: ok"
grep -q "not releasing" "$T/Q.err" && [ "$(cat "$L/owner" 2>/dev/null)" = "contender $$" ] && echo "Q's release left the contender's lock alone: ok"
rm -f "$L/owner"; rmdir "$L"
rm -rf "$T"
