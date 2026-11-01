#!/bin/bash
# Wait until any duo-v2 background worker stops (turns idle, waiting or blocked), or a GPU lock hold runs too long,
# then print which and exit.
# The director runs this in the background after every wake, so no worker is ever left stranded:
# it covers every worker, including ones started after it began (each is compared with its own last state).
# A hold on the machine's GPU lock (exclusive, or a shared slot) older than LOCK_MAX_MIN minutes (default 45) also
# wakes the director, once per hold (Geoff, 2026-11-01: "You left the gpu lock on all night and it screwed over
# another agent; DONT DO THIS").
# Usage: watch-workers.sh [poll-seconds]   (default 60)
POLL=${1:-60}
CLAUDE=${CLAUDE_BIN:-$HOME/.local/bin/claude}
LOCK=${GPU_LOCK:-/Users/geoff/repos/duo-voice/.gpu.lock}
LOCK_MAX_MIN=${LOCK_MAX_MIN:-45}
SEEN=${TMPDIR:-/tmp}/watch-workers-lock-seen
snap() { "$CLAUDE" agents --json --all 2>/dev/null | python3 -I -c '
import json, sys
for a in json.load(sys.stdin):
    if a.get("kind") != "background" or "/repos/duo-v2" not in (a.get("cwd") or ""): continue
    st = a.get("status") or a.get("state") or "gone"
    print("%s\t%s\t%s" % ((a.get("sessionId") or "")[:8], a.get("name") or "", st))' | sort; }
# Holds older than the limit that haven't been reported yet: "<path>\t<owner>\t<minutes>".
long_holds() {
  for h in "$LOCK" "$LOCK".shared/*; do
    [ -d "$h" ] && [ -f "$h/owner" ] || continue
    age=$(( ( $(date +%s) - $(stat -f %m "$h/owner") ) / 60 ))
    [ "$age" -ge "$LOCK_MAX_MIN" ] || continue
    key="$h $(cat "$h/owner")"
    grep -qxF "$key" "$SEEN" 2>/dev/null && continue
    echo "$key" >> "$SEEN"
    printf 'GPU LOCK held %s min\t%s\t%s\n' "$age" "$(cat "$h/owner")" "$h"
  done; }
base=$(snap)
while true; do
  sleep "$POLL"
  held=$(long_holds); if [ -n "$held" ]; then echo "$held"; exit 0; fi
  cur=$(snap); [ -z "$cur" ] && continue
  changed=$(comm -13 <(echo "$base") <(echo "$cur") | awk -F'\t' '$3 ~ /^(idle|waiting|blocked)$/')
  if [ -n "$changed" ]; then echo "$changed"; exit 0; fi
  base=$cur
done
