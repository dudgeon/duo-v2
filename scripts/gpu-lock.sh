#!/bin/bash
# Run a job under the Mac's shared compute lock, so heavy jobs (voice fine-tunes, renders, timing measurements) don't
# thrash memory or skew each other's timings (codebase review V1).
#   GPU_LOCK=<lock dir> scripts/gpu-lock.sh [--exclusive|--shared] <owner name> <command...>
# Two kinds of hold (F-298):
#  - --exclusive, the default: model work, renders and the score, and every timing measurement. It waits until every
#    holder, exclusive or shared, is done, then runs alone. Its hold is the lock directory itself, holding `owner`.
#  - --shared: builds, DuoChecks, captures and pixel checks. Up to GPU_LOCK_SHARED_SLOTS (default 2) run at once, each
#    in a slot directory <lock>.shared/<n>, holding `owner`. None starts while an exclusive job holds the lock.
# An owner is "<name> <pid>". A live owner is waited for; an owner whose pid is gone is cleared (a job that died
# without releasing), and so is a hold that has had no owner for GPU_LOCK_ORPHAN seconds (default 60: one that died
# between its mkdir and writing `owner`). The hold is released when the command ends, however it ends.
# A hold has a time limit (F-510), counted from when the command starts. A caller that sets GPU_LOCK_MAX_MIN (minutes) or
# GPU_LOCK_ENFORCE=1 gets it enforced: 60 min exclusive and 45 shared by default; past it the command's own process group
# gets TERM, then KILL after GPU_LOCK_GRACE seconds (default 15), the hold is released, "gpu-lock: <owner> exceeded <n>
# min; ended" goes to stderr and a line to <lock>.log, and the exit status is 124. GPU_LOCK_MAX_MIN=0 means no limit and
# needs GPU_LOCK_MAX_REASON. A caller that sets neither (a long render from another repo) is only warned about: at 60
# (45) min and every GPU_LOCK_WARN_EVERY_MIN (15) after, to stderr and <lock>.log, never killed before the backstop of
# GPU_LOCK_BACKSTOP_MIN (360 min = 6 h), which GPU_LOCK_MAX_REASON turns off (voice fine-tunes that run for hours).
#   GPU_LOCK=<lock dir> scripts/gpu-lock.sh --status   lists every holder and waiter with its age.
# The lock's path is machine-local, so it comes from $GPU_LOCK, never from this file.
#
# Waiters queue in order (tickets in <lock>.queue/), and only the front ticket may take a hold, so a long job isn't
# starved by short ones that happen to poll first, and an exclusive waiter at the front keeps new shared jobs out until
# it has run. A ticket whose waiter has died is cleared. Call the main checkout's copy by its full path: an older copy
# doesn't know the shared slots. A bare `mkdir <lock>` still keeps exclusive and new shared jobs out, but doesn't
# wait for shared jobs already running, so use this script.
set -u
kind=exclusive
lock="${GPU_LOCK:?set GPU_LOCK to the lock directory}"
if [ "${1:-}" = "--status" ]; then
  now=$(date +%s)
  age() { local m; m=$(stat -f %m "$1" 2>/dev/null) || return 1; m=$((now - m)); printf '%dm%02ds' $((m / 60)) $((m % 60)); }
  found=""
  [ -f "$lock/owner" ] && { echo "exclusive holder: $(cat "$lock/owner"), held $(age "$lock/owner")"; found=1; }
  for o in "$lock.shared"/*/owner; do [ -f "$o" ] && { echo "shared holder:    $(cat "$o"), held $(age "$o")"; found=1; }; done
  for t in $(ls "$lock.queue" 2>/dev/null | grep -E '^[0-9]{10}$' | sort); do
    [ -f "$lock.queue/$t" ] && { echo "waiting:          $(cat "$lock.queue/$t" 2>/dev/null), for $(age "$lock.queue/$t")"; found=1; }
  done
  [ -n "$found" ] || echo "no holder, no waiter"
  exit 0
fi
case "${1:-}" in --shared) kind=shared; shift ;; --exclusive) shift ;; esac
name="${1:?usage: GPU_LOCK=<dir> scripts/gpu-lock.sh [--exclusive|--shared] <owner name> <command...>}"
shift
[ $# -gt 0 ] || { echo "gpu-lock: no command" >&2; exit 2; }
queue="$lock.queue"
shared="$lock.shared"
case "$kind" in exclusive) default_min=60 ;; *) default_min=45 ;; esac
[ -z "${GPU_LOCK_DEFAULT_MIN:-}" ] || default_min="$GPU_LOCK_DEFAULT_MIN"   # a test hook
max_min="${GPU_LOCK_MAX_MIN:-$default_min}"
[[ "$max_min" =~ ^[0-9]*\.?[0-9]+$ ]] || { echo "gpu-lock: GPU_LOCK_MAX_MIN must be a number of minutes" >&2; exit 2; }
if awk -v m="$max_min" 'BEGIN { exit !(m == 0) }'; then
  [ -n "${GPU_LOCK_MAX_REASON:-}" ] || { echo "gpu-lock: GPU_LOCK_MAX_MIN=0 (no limit) needs GPU_LOCK_MAX_REASON saying why" >&2; exit 2; }
fi
secs() { awk -v m="$1" 'BEGIN { printf "%d", m * 60 + 0.999 }'; }
warn_s=0; warn_every_s=$(secs "${GPU_LOCK_WARN_EVERY_MIN:-15}")
if [ -n "${GPU_LOCK_MAX_MIN:-}" ] || [ "${GPU_LOCK_ENFORCE:-}" = 1 ]; then
  limit_min="$max_min"          # enforced
else
  warn_s=$(secs "$max_min")     # warned only, until the backstop
  limit_min="${GPU_LOCK_BACKSTOP_MIN:-360}"; [ -z "${GPU_LOCK_MAX_REASON:-}" ] || limit_min=0
fi
limit_s=$(secs "$limit_min")
grace="${GPU_LOCK_GRACE:-15}"
slots="${GPU_LOCK_SHARED_SLOTS:-2}"
poll="${GPU_LOCK_POLL:-2}"
orphan="${GPU_LOCK_ORPHAN:-60}"

# A pid is alive unless it's certainly gone: kill -0 also fails with "not permitted" (another user's process, or one
# outside a sandboxed shell), so ask ps before calling an owner dead.
alive() { [[ "$1" =~ ^[0-9]+$ ]] && { kill -0 "$1" 2>/dev/null || ps -p "$1" >/dev/null 2>&1; }; }

# Is the hold at $1 (the lock directory or a shared slot) live? Sets $holder. A hold whose owner is gone, or that has
# had no owner for $orphan seconds, is cleared, and then it isn't.
live() {
  [ -d "$1" ] || return 1
  holder=$(cat "$1/owner" 2>/dev/null || true)
  if [ -z "$holder" ]; then
    holder="an owner that has not written its name yet"
    [ -n "$(find "$1" -maxdepth 0 -mtime +"$orphan"s 2>/dev/null)" ] || return 0
    echo "gpu-lock: clearing a lock that has had no owner for over $orphan s ($1)" >&2
    rmdir "$1" 2>/dev/null; return 1
  fi
  alive "${holder##* }" && return 0
  # Clear it only if it's still the dead owner's: someone may have cleared it and taken it since we read it.
  [ "$(cat "$1/owner" 2>/dev/null)" = "$holder" ] || return 0
  echo "gpu-lock: clearing a stale lock (owner \"$holder\" is gone)" >&2
  rm -f "$1/owner"; rmdir "$1" 2>/dev/null; return 1
}

# The live shared holders, cleared of dead ones: their count in $nshared, their names in $sharers.
count_shared() {
  nshared=0; sharers=""
  for s in "$shared"/*; do
    [ -d "$s" ] || continue
    if live "$s"; then nshared=$((nshared + 1)); sharers="${sharers:+$sharers, }$holder"; fi
  done
}

# A ticket: the next number, taken under a short mkdir mutex, written whole by a rename.
mkdir -p "$queue" "$shared"
until mkdir "$queue/.take" 2>/dev/null; do
  # A mutex left by a waiter killed between mkdir and rmdir: clear it after a few seconds.
  if [ -n "$(find "$queue/.take" -maxdepth 0 -mtime +5s 2>/dev/null)" ]; then rmdir "$queue/.take" 2>/dev/null; fi
  sleep 0.1
done
n=$(( $(cat "$queue/.next" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$queue/.next"
ticket="$queue/$(printf '%010d' "$n")"
echo "$name $$" > "$ticket.tmp" && mv "$ticket.tmp" "$ticket"
rmdir "$queue/.take"

# Release only a hold that is still ours. A script that releases twice (an unlock, then the same unlock again from its
# EXIT trap) deletes whoever took the lock in between, and the next release would cascade (F-296).
me="$name $$"
hold=""
drop() {
  [ -n "$hold" ] || return 0
  if [ "$(cat "$hold/owner" 2>/dev/null)" = "$me" ]; then rm -f "$hold/owner"; rmdir "$hold" 2>/dev/null
  else echo "gpu-lock: not releasing: the lock is no longer ours (owner now: $(cat "$hold/owner" 2>/dev/null || echo none))" >&2; fi
  hold=""
}
release() { [ -n "${watch:-}" ] && kill "$watch" 2>/dev/null; rm -f "$ticket"; drop; }
trap release EXIT
trap 'exit 143' TERM INT

say() { if [ "$said" != "$1" ]; then echo "gpu-lock: $1" >&2; said="$1"; fi; }
said=""
while :; do
  # Clear tickets whose waiter is gone, then find our place.
  pos=0; ahead=""
  for t in $(ls "$queue" 2>/dev/null | grep -E '^[0-9]{10}$' | sort); do
    who=$(cat "$queue/$t" 2>/dev/null) || continue   # gone since the listing: its waiter left
    if [ "$queue/$t" != "$ticket" ] && ! alive "${who##* }"; then
      echo "gpu-lock: clearing a dead ticket ($who)" >&2; rm -f "$queue/$t"; continue
    fi
    [ "$queue/$t" = "$ticket" ] && break
    pos=$((pos + 1)); [ -z "$ahead" ] && ahead="$who"
  done
  if [ "$pos" -gt 0 ]; then say "queue position $((pos + 1)), behind $ahead"; sleep "$poll"; continue; fi

  # At the front. An exclusive job takes the lock directory first, so no new shared job starts, then waits for the
  # shared jobs still running. A shared job takes a slot first, then backs off if an exclusive job has the lock: of
  # two that race, at least one sees the other, and it's always the shared one that steps aside.
  if [ "$kind" = exclusive ]; then
    if mkdir "$lock" 2>/dev/null; then
      echo "$me" > "$lock/owner"; hold="$lock"; break
    fi
    live "$lock" || continue   # a dead owner, cleared: try again now
    say "next in the queue, waiting for $holder"
  elif [ -d "$lock" ] && live "$lock"; then
    say "next in the queue (shared), waiting for the exclusive job $holder"
  else
    got=""
    for i in $(seq 1 "$slots"); do
      if mkdir "$shared/$i" 2>/dev/null; then got="$shared/$i"; break; fi
    done
    if [ -n "$got" ]; then
      echo "$me" > "$got/owner"; hold="$got"
      [ -d "$lock" ] || break
      drop; continue   # an exclusive job took the lock as we took the slot: it goes first
    fi
    count_shared
    [ "$nshared" -ge "$slots" ] && say "next in the queue (shared), waiting for a free slot: $sharers"
  fi
  sleep "$poll"
done
rm -f "$ticket"

# An exclusive job now waits for the shared jobs that started before it.
if [ "$kind" = exclusive ]; then
  said=""
  while count_shared; [ "$nshared" -gt 0 ]; do say "holding the lock, waiting for $nshared shared job(s) to finish: $sharers"; sleep "$poll"; done
  echo "gpu-lock: taken by $name ($$), exclusive" >&2
else
  echo "gpu-lock: taken by $name ($$), shared slot ${hold##*/} of $slots" >&2
fi
# Watch for the hold being taken from under the job (someone else's release deleted it): say so, loudly, once.
( while sleep "${GPU_LOCK_WATCH:-10}"; do
    kill -0 $$ 2>/dev/null || exit 0
    o=$(cat "$hold/owner" 2>/dev/null || echo "no lock")
    [ "$o" = "$me" ] || { echo "gpu-lock: WARNING: the lock was taken from $name while its job runs (owner now: $o). Some script released a lock it didn't hold." >&2; exit 0; }
  done ) &
watch=$!
# The job runs as a child in its own process group, so a TERM to this script reaches it, and the time limit can end it and
# everything it started without touching anything else (F-510). The hold is still released after.
perl -e 'setpgrp(0, 0); exec { $ARGV[0] } @ARGV; print STDERR "gpu-lock: cannot run $ARGV[0]: $!\n"; exit 127' "$@" &
child=$!
trap 'kill -TERM -- -"$child" 2>/dev/null || kill -TERM "$child" 2>/dev/null' TERM INT
logline() { echo "$(date '+%F %T') | $name | $kind | limit ${limit_min} min | $*" >> "$lock.log" 2>/dev/null; }
over="$(mktemp "${TMPDIR:-/tmp}/gpu-lock-over.XXXXXX")"; rm -f "$over"
wd=""
if [ "$limit_s" -gt 0 ] || [ "$warn_s" -gt 0 ]; then
  me_pid=$$
  ( start=$SECONDS; next_warn=$warn_s
    while :; do
      kill -0 "$me_pid" 2>/dev/null && kill -0 "$child" 2>/dev/null || exit 0
      el=$((SECONDS - start))
      [ "$limit_s" -gt 0 ] && [ "$el" -ge "$limit_s" ] && break
      if [ "$warn_s" -gt 0 ] && [ "$el" -ge "$next_warn" ]; then
        echo "gpu-lock: WARNING: $name has held the $kind lock for $((el / 60)) min and set no GPU_LOCK_MAX_MIN; it is not ended before $limit_min min" >&2
        logline "warning after $((el / 60)) min, no limit set"
        next_warn=$((next_warn + warn_every_s))
      fi
      sleep 1
    done
    echo "gpu-lock: $name exceeded $limit_min min; ended" >&2
    : > "$over"
    # Kill the command's own group only, and only if it really is one (never this script's group, never Duo's).
    pg=$(ps -o pgid= -p "$child" 2>/dev/null | tr -d ' ')
    sig() { if [ "$pg" = "$child" ]; then kill -"$1" -- -"$child" 2>/dev/null; else kill -"$1" "$child" 2>/dev/null; fi; }
    sig TERM; res="TERM sent; ended"
    t=0; while [ "$t" -lt "$grace" ] && sig 0; do sleep 1; t=$((t + 1)); done
    if sig 0; then sig KILL; res="TERM sent, still running after $grace s; KILL sent"; fi
    logline "exceeded the limit: $res"
  ) &
  wd=$!
fi
[ "$limit_s" -gt 0 ] || [ -z "${GPU_LOCK_MAX_REASON:-}" ] || logline "no time limit: $GPU_LOCK_MAX_REASON"
while :; do wait "$child"; status=$?; kill -0 "$child" 2>/dev/null || break; done
if [ -n "$wd" ]; then
  if [ -e "$over" ]; then wait "$wd"; status=124; else kill "$wd" 2>/dev/null; fi
fi
rm -f "$over"
exit "$status"
