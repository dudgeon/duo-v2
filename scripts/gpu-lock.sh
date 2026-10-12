#!/bin/bash
# Run a heavy job (a render, TTS voicing, a score) under the shared GPU lock, a mkdir mutex that the Mac's other
# heavy jobs (voice fine-tunes) also take, so two never thrash memory at once (codebase review V1).
#   GPU_LOCK=<lock dir> scripts/gpu-lock.sh <owner name> <command...>
# The lock is a directory holding `owner` ("<name> <pid>"). A live owner is waited for; an owner whose pid is
# gone is cleared (a job that died without releasing). The lock is released when the command ends, however it ends.
# The lock's path is machine-local, so it comes from $GPU_LOCK, never from this file.
set -u
lock="${GPU_LOCK:?set GPU_LOCK to the lock directory}"
name="${1:?usage: GPU_LOCK=<dir> scripts/gpu-lock.sh <owner name> <command...>}"
shift
[ $# -gt 0 ] || { echo "gpu-lock: no command" >&2; exit 2; }

said=""
while ! mkdir "$lock" 2>/dev/null; do
  owner=$(cat "$lock/owner" 2>/dev/null || true)
  pid=${owner##* }
  if [[ "$pid" =~ ^[0-9]+$ ]] && ! kill -0 "$pid" 2>/dev/null; then
    echo "gpu-lock: clearing a stale lock (owner \"$owner\" is gone)" >&2
    rm -f "$lock/owner"; rmdir "$lock" 2>/dev/null
    continue
  fi
  if [ "$said" != "$owner" ]; then echo "gpu-lock: waiting for ${owner:-an owner that has not written its name yet}" >&2; said="$owner"; fi
  sleep 15
done
echo "$name $$" > "$lock/owner"
release() { rm -f "$lock/owner"; rmdir "$lock" 2>/dev/null; }
trap release EXIT
echo "gpu-lock: taken by $name ($$)" >&2
# The job runs as a child, so a TERM to this script reaches it (and the lock is still released after).
"$@" &
child=$!
trap 'kill -TERM "$child" 2>/dev/null' TERM INT
while :; do wait "$child"; status=$?; kill -0 "$child" 2>/dev/null || break; done
exit "$status"
