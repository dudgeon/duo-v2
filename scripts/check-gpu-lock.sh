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
# Shared and exclusive holds (F-298), with GPU_LOCK_SHARED_SLOTS=2:
#  - S1, S2, S3 shared: S1 and S2 run together, S3 waits for a slot;
#  - X exclusive queues behind a running shared job, then A2 shared queues behind X: X waits for the shared job, A2
#    waits for X although a slot is free, and X runs alone;
#  - a mix of 12 shared and exclusive jobs: an exclusive job never overlaps another job, and never more than 2 shared;
#  - dead holders in both shared slots are cleared, for an exclusive job and for a shared one.
# Expect: the dead ticket cleared, A then B then C in ticket order, no two holders ever overlapping, F's ticket gone,
# and G running once the ownerless lock is cleared.
# The time limit (F-510), ending in "PASS" or "FAIL" lines (the script exits 1 if any FAIL):
#  - a hung command that ignores TERM is KILLed past its limit, with its child, and the hold released; the next waiter runs;
#  - the loud line and the <lock>.log line are written; the exit status is 124; a bystander process outside is untouched;
#  - a caller that sets no limit is warned, not killed, until the backstop (6 h); GPU_LOCK_MAX_REASON turns the backstop off;
#    GPU_LOCK_ENFORCE=1 enforces the default;
#  - a normal command's exit code passes through; shared slots are as before; no limit needs a reason; --status lists.
#   scripts/check-gpu-lock.sh   (about 55 s, in /tmp)
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

# Shared and exclusive. Events are "<time> <job> <s|x> start|end"; holds() checks them.
export GPU_LOCK_SHARED_SLOTS=2
job() {  # job <shared|exclusive> <name> <seconds>
  "$R/scripts/gpu-lock.sh" --$1 "test $2" bash -c "ev '$2 ${1:0:1} start'; sleep $3; ev '$2 ${1:0:1} end'" 2> "$T/$2.err"
}
holds() {
  sort -n "$LOG" | awk '
    $4 == "start" && $3 == "e" { if (nx + ns) { print "OVERLAP: exclusive " $2 " started while " nx + ns " held it"; bad=1 } nx++ }
    $4 == "start" && $3 == "s" { if (nx) { print "OVERLAP: shared " $2 " started during an exclusive job"; bad=1 } if (++ns > max) max = ns }
    $4 == "start" { order = order " " $2 }
    $4 == "end" { if ($3 == "e") nx--; else ns-- }
    END { printf "order:%s; at most %d shared at once; %s\n", order, max, (bad || max > 2) ? "FAILED" : "no exclusive overlap" }'
}

echo "--- S: three shared jobs, two slots"
: > "$LOG"
for j in S1 S2 S3; do job shared $j 1.5 & sleep 0.1; done
wait; holds
sort -n "$LOG" | awk '$2 == "S3" && $4 == "start" { s3 = $1 } $4 == "end" && !first { first = $1 }
  END { print (s3 >= first) ? "S3 waited for a slot: ok" : "S3 FAILED: it started before a slot was free" }'
grep -q "waiting for a free slot" "$T/S3.err" && echo "S3 said it was waiting for a slot: ok"

echo "--- X: an exclusive waiter keeps new shared jobs out, then runs alone"
: > "$LOG"
job shared A1 2 & sleep 0.3
job exclusive X 1 & sleep 0.3
job shared A2 0.5 &
wait; holds
sort -n "$LOG" | awk '{ t[$2 " " $4] = $1 }
  END { print (t["X start"] >= t["A1 end"] && t["A2 start"] >= t["X end"]) ? "X waited for A1, and A2 waited for X: ok" : "X FAILED: the order is wrong" }'
grep -q "waiting for 1 shared job" "$T/X.err" && echo "X held the lock while A1 finished: ok"

echo "--- M: a mix of 12 jobs"
: > "$LOG"
for i in $(seq 1 12); do
  if [ $((i % 3)) -eq 0 ]; then job exclusive M$i 0.3 & else job shared M$i 0.4 & fi
  sleep 0.05
done
wait; holds
ls -A "$L.queue" | grep -vE '^\.(next)$' | sed 's/^/left in queue: /'
[ -z "$(ls -A "$L.shared")" ] && [ ! -d "$L" ] && echo "every hold released: ok"

echo "--- dead shared holders"
mkdir -p "$L.shared"
for i in 1 2; do sleep 0 & d=$!; wait $d; mkdir "$L.shared/$i"; echo "ghost $d" > "$L.shared/$i/owner"; done
"$R/scripts/gpu-lock.sh" "test W" true 2> "$T/W.err"
[ "$(grep -c "clearing a stale lock" "$T/W.err")" = 2 ] && grep -q "taken by test W" "$T/W.err" && echo "W (exclusive) cleared both dead shared holders and ran: ok"
for i in 1 2; do sleep 0 & d=$!; wait $d; mkdir "$L.shared/$i"; echo "ghost $d" > "$L.shared/$i/owner"; done
"$R/scripts/gpu-lock.sh" --shared "test Z" true 2> "$T/Z.err"
grep -q "clearing a stale lock" "$T/Z.err" && grep -q "taken by test Z" "$T/Z.err" && echo "Z (shared) cleared a dead shared holder and ran: ok"

echo "--- max hold (F-510)"
fails=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fails=$((fails + 1)); }
rm -f "$L.log"; : > "$LOG"
cat > "$T/hung.sh" <<'EOS'
#!/bin/bash
# Ignores TERM, and starts a child that does too: only a KILL of the group ends it.
trap '' TERM
sleep 300 &
echo $! > "$HUNG_CHILD"
while :; do sleep 1; done
EOS
chmod +x "$T/hung.sh"
sleep 300 & bystander=$!
export HUNG_CHILD="$T/hung.child"
t0=$(date +%s)
GPU_LOCK_MAX_MIN=0.05 GPU_LOCK_GRACE=2 "$R/scripts/gpu-lock.sh" "test hung" "$T/hung.sh" 2> "$T/hung.err" & hp=$!
sleep 0.5
"$R/scripts/gpu-lock.sh" "test next" bash -c "ev 'next start'; ev 'next end'" 2> "$T/next.err" & np=$!
wait $hp; hs=$?
el=$(( $(date +%s) - t0 ))
wait $np
[ "$hs" = 124 ] && ok "the hung command ended with status 124" || bad "hung status was $hs"
[ "$el" -ge 3 ] && [ "$el" -le 10 ] && ok "it ended $el s in (limit 3 s + TERM grace 2 s)" || bad "it ran $el s"
grep -q "gpu-lock: test hung exceeded 0.05 min; ended" "$T/hung.err" && ok "the loud line was printed" || bad "no loud line: $(cat "$T/hung.err")"
grep -q "| test hung | exclusive | limit 0.05 min |" "$L.log" 2>/dev/null && ok "<lock>.log has the line" || bad "no log line"
kill -0 "$(cat "$HUNG_CHILD")" 2>/dev/null && bad "the hung command's child is still running" || ok "the command's child was killed too"
kill -0 $bystander 2>/dev/null && ok "a process outside the command was left alone" || bad "the bystander was killed"
kill $bystander 2>/dev/null; wait $bystander 2>/dev/null
grep -q "next start" "$LOG" && ok "the queue moved on: the next waiter ran" || bad "the next waiter never ran"
[ ! -d "$L" ] && ok "the lock was released" || bad "the lock is still held"

"$R/scripts/gpu-lock.sh" "test exit" bash -c 'exit 7' 2> /dev/null; [ $? = 7 ] && ok "a normal command's exit code 7 passes through" || bad "exit code lost"
"$R/scripts/gpu-lock.sh" --shared "test ok" true 2> /dev/null; [ $? = 0 ] && ok "a quick shared command exits 0" || bad "shared exit code"
"$R/scripts/gpu-lock.sh" "test nope" /no/such/command 2> /dev/null; [ $? = 127 ] && ok "a command that can't start exits 127" || bad "missing command status"

# A caller that sets no limit: warned at the default, not killed, until the backstop; the default and backstop are shrunk
# with test hooks (GPU_LOCK_DEFAULT_MIN, GPU_LOCK_BACKSTOP_MIN).
export GPU_LOCK_DEFAULT_MIN=0.03 GPU_LOCK_WARN_EVERY_MIN=0.03 GPU_LOCK_BACKSTOP_MIN=0.1 GPU_LOCK_GRACE=2
"$R/scripts/gpu-lock.sh" "test nolimit-warn" sleep 5 2> "$T/w.err"; wst=$?
[ "$wst" = 0 ] && grep -q "WARNING: test nolimit-warn has held" "$T/w.err" && ! grep -q exceeded "$T/w.err" && ok "no limit set: warned at the default, not killed" || bad "warn-only: status $wst: $(cat "$T/w.err")"
[ "$(grep -c WARNING "$T/w.err")" -ge 2 ] && ok "the warning repeats" || bad "the warning did not repeat"
grep -q "warning after .* no limit set" "$L.log" && ok "the warning is in <lock>.log" || bad "no warning in the log"
"$R/scripts/gpu-lock.sh" "test backstop" sleep 300 2> "$T/b.err"; bst=$?
[ "$bst" = 124 ] && grep -q "test backstop exceeded 0.1 min; ended" "$T/b.err" && ok "the backstop ends a hung command that set no limit" || bad "backstop: status $bst: $(cat "$T/b.err")"
GPU_LOCK_BACKSTOP_MIN=0.05 GPU_LOCK_MAX_REASON="long render" "$R/scripts/gpu-lock.sh" "test reason" sleep 6 2> /dev/null; [ $? = 0 ] && ok "GPU_LOCK_MAX_REASON turns the backstop off" || bad "backstop ignored the reason"
GPU_LOCK_ENFORCE=1 "$R/scripts/gpu-lock.sh" "test enforce" sleep 300 2> "$T/e.err"; est=$?
[ "$est" = 124 ] && grep -q "test enforce exceeded 0.03 min" "$T/e.err" && ok "GPU_LOCK_ENFORCE=1 enforces the default limit" || bad "enforce: status $est"
unset GPU_LOCK_DEFAULT_MIN GPU_LOCK_WARN_EVERY_MIN GPU_LOCK_BACKSTOP_MIN GPU_LOCK_GRACE

# Shared slots: two run at once, a third waits, and a hung shared job is ended without blocking the others.
: > "$LOG"
for j in P1 P2 P3; do job shared $j 1.5 & sleep 0.1; done
wait
holds | grep -q "at most 2 shared at once; no exclusive overlap" && ok "shared slots: two at once, as before" || bad "shared slots changed"
GPU_LOCK_MAX_MIN=0.05 GPU_LOCK_GRACE=2 "$R/scripts/gpu-lock.sh" --shared "test hungshared" sleep 300 2> "$T/hs.err"; [ $? = 124 ] && grep -q "| shared |" "$L.log" && ok "a hung shared job is ended too (45 min default, per-run override)" || bad "hung shared job"
[ -z "$(ls -A "$L.shared")" ] && ok "its slot was released" || bad "slot still held"

# No limit needs a reason.
GPU_LOCK_MAX_MIN=0 "$R/scripts/gpu-lock.sh" "test nolimit" true 2> "$T/nl.err"; [ $? = 2 ] && ok "no limit without a reason is refused" || bad "no-limit was allowed without a reason"
GPU_LOCK_MAX_MIN=0 GPU_LOCK_MAX_REASON="voice fine-tune" "$R/scripts/gpu-lock.sh" "test nolimit" true 2> /dev/null; [ $? = 0 ] && grep -q "no time limit: voice fine-tune" "$L.log" && ok "no limit with a reason runs, and is logged" || bad "no limit with reason"

# --status
"$R/scripts/gpu-lock.sh" "test held" sleep 3 2> /dev/null & sleep 1
"$R/scripts/gpu-lock.sh" "test waiter" true 2> /dev/null & sleep 1
st=$("$R/scripts/gpu-lock.sh" --status)
echo "$st" | grep -q "exclusive holder: test held .*held 0m0" && echo "$st" | grep -q "waiting: .*test waiter .*for 0m0" && ok "--status lists the holder and the waiter with ages" || bad "--status said: $st"
wait
[ "$("$R/scripts/gpu-lock.sh" --status)" = "no holder, no waiter" ] && ok "--status on an idle lock" || bad "--status idle"
# timing-lock.sh finds the main checkout's gpu-lock.sh from a linked work tree, whatever the caller's cwd (the relative
# --git-common-dir bug): a scratch repo with a stub gpu-lock.sh, a work tree, and a call from an unrelated directory.
M="$T/main"; git init -q "$M" && cp -R "$R/scripts" "$M/scripts" 2>/dev/null
printf '#!/bin/bash\necho "stub lock: $*"\n' > "$M/scripts/gpu-lock.sh"; chmod +x "$M/scripts/gpu-lock.sh"
git -C "$M" add -A >/dev/null 2>&1; git -C "$M" -c user.name=t -c user.email=t@t commit -qm init >/dev/null 2>&1
git -C "$M" worktree add -q "$T/wt" -b wt >/dev/null 2>&1
out=$(cd "$T" && GPU_LOCK="$L" "$T/wt/scripts/timing-lock.sh" "test tl" echo hi 2>&1)
[ "$out" = "stub lock: --exclusive test tl echo hi" ] && ok "timing-lock.sh from a work tree finds the main checkout's gpu-lock.sh" || bad "timing-lock.sh from a work tree said: $out"
out=$(cd "$T" && GPU_LOCK="$L" "$M/scripts/timing-lock.sh" "test tl" echo hi 2>&1)   # the main checkout itself: git says ".git"
[ "$out" = "stub lock: --exclusive test tl echo hi" ] && ok "timing-lock.sh from the main checkout, from another directory" || bad "timing-lock.sh from the main checkout said: $out"
echo "max hold: $fails failure(s)"
rm -rf "$T"
[ "$fails" = 0 ]
