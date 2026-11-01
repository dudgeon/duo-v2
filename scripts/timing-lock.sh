#!/bin/bash
# Runs a timing measurement or check under the main checkout's gpu-lock.sh, exclusive, with its time limit enforced
# (GPU_LOCK_ENFORCE=1, F-510): a run that hangs is ended at 60 min instead of holding the lock all night.
#   GPU_LOCK=<lock dir> scripts/timing-lock.sh <owner name> <command...>
#   GPU_LOCK=… scripts/timing-lock.sh check-scale scripts/check-scale.sh
#   GPU_LOCK=… scripts/timing-lock.sh check-chat-perf scripts/check-chat-perf.sh
#   GPU_LOCK=… scripts/timing-lock.sh duochecks-editorperf swift run DuoChecks editorperf
# A run that needs longer sets GPU_LOCK_MAX_MIN=<minutes>.
set -u
: "${GPU_LOCK:?set GPU_LOCK to the lock folder of this machine (machine-local; the director gives it in each brief)}"
[ $# -ge 2 ] || { echo "usage: GPU_LOCK=<lock dir> scripts/timing-lock.sh <owner name> <command...>" >&2; exit 2; }
here="$(cd "$(dirname "$0")/.." && pwd)"
main="$(cd "$(git -C "$here" rev-parse --path-format=absolute --git-common-dir)/.." && pwd)"
lock="$main/scripts/gpu-lock.sh"
[ -x "$lock" ] || { echo "timing-lock: $lock is missing" >&2; exit 2; }
name="$1"; shift
GPU_LOCK_ENFORCE=1 exec "$lock" --exclusive "$name" "$@"
