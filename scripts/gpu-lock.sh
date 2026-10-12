#!/bin/bash
# Run a heavy job (a render, TTS voicing, a score) under the shared GPU lock, a mkdir mutex that the Mac's other
# heavy jobs (voice fine-tunes) also take, so two never thrash memory at once (codebase review V1).
#   GPU_LOCK=<lock dir> scripts/gpu-lock.sh <owner name> <command...>
# The lock is a directory holding `owner` ("<name> <pid>"). A live owner is waited for; an owner whose pid is
# gone is cleared (a job that died without releasing), and so is a lock that has had no owner for a minute (one that
# died between its mkdir and writing `owner`). The lock is released when the command ends, however it ends.
# The lock's path is machine-local, so it comes from $GPU_LOCK, never from this file.
#
# Waiters queue in order (tickets in <lock>.queue/), so a long job isn't starved by short ones that happen to poll
# first. The front ticket still takes the mkdir lock itself, so a bare `mkdir <lock>` from a brief or a script that
# doesn't use this one stays safe: it just isn't queued. A ticket whose waiter has died is cleared.
set -u
lock="${GPU_LOCK:?set GPU_LOCK to the lock directory}"
name="${1:?usage: GPU_LOCK=<dir> scripts/gpu-lock.sh <owner name> <command...>}"
shift
[ $# -gt 0 ] || { echo "gpu-lock: no command" >&2; exit 2; }
queue="$lock.queue"
poll="${GPU_LOCK_POLL:-2}"

alive() { [[ "$1" =~ ^[0-9]+$ ]] && kill -0 "$1" 2>/dev/null; }

# A ticket: the next number, taken under a short mkdir mutex, written whole by a rename.
mkdir -p "$queue"
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

release() { rm -f "$lock/owner"; rmdir "$lock" 2>/dev/null; }
leave() { rm -f "$ticket"; }
trap leave EXIT
trap 'exit 143' TERM INT

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
  if [ "$pos" -eq 0 ]; then
    # At the front: take the lock itself, clearing an owner that died.
    if mkdir "$lock" 2>/dev/null; then break; fi
    owner=$(cat "$lock/owner" 2>/dev/null || true)
    # No owner yet: a holder between its mkdir and writing `owner`, or one that died in between. After a minute
    # (GPU_LOCK_ORPHAN seconds), it's the second.
    if [ -z "$owner" ] && [ -n "$(find "$lock" -maxdepth 0 -mtime +"${GPU_LOCK_ORPHAN:-60}"s 2>/dev/null)" ]; then
      echo "gpu-lock: clearing a lock that has had no owner for over ${GPU_LOCK_ORPHAN:-60} s" >&2
      rmdir "$lock" 2>/dev/null
      continue
    fi
    if alive "${owner##* }" || [ -z "$owner" ]; then
      msg="next in the queue, waiting for ${owner:-an owner that has not written its name yet}"
    else
      echo "gpu-lock: clearing a stale lock (owner \"$owner\" is gone)" >&2
      rm -f "$lock/owner"; rmdir "$lock" 2>/dev/null
      continue
    fi
  else
    msg="queue position $((pos + 1)), behind $ahead"
  fi
  if [ "$said" != "$msg" ]; then echo "gpu-lock: $msg" >&2; said="$msg"; fi
  sleep "$poll"
done
echo "$name $$" > "$lock/owner"
rm -f "$ticket"
trap release EXIT
echo "gpu-lock: taken by $name ($$)" >&2
# The job runs as a child, so a TERM to this script reaches it (and the lock is still released after).
"$@" &
child=$!
trap 'kill -TERM "$child" 2>/dev/null' TERM INT
while :; do wait "$child"; status=$?; kill -0 "$child" 2>/dev/null || break; done
exit "$status"
