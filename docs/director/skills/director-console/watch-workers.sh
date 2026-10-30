#!/bin/bash
# Wait until any duo-v2 background worker stops (turns idle, waiting or blocked), then print which and exit.
# The director runs this in the background after every wake, so no worker is ever left stranded:
# it covers every worker, including ones started after it began (each is compared with its own last state).
# Usage: watch-workers.sh [poll-seconds]   (default 60)
POLL=${1:-60}
CLAUDE=${CLAUDE_BIN:-$HOME/.local/bin/claude}
snap() { "$CLAUDE" agents --json --all 2>/dev/null | python3 -I -c '
import json, sys
for a in json.load(sys.stdin):
    if a.get("kind") != "background" or "/repos/duo-v2" not in (a.get("cwd") or ""): continue
    st = a.get("status") or a.get("state") or "gone"
    print("%s\t%s\t%s" % ((a.get("sessionId") or "")[:8], a.get("name") or "", st))' | sort; }
base=$(snap)
while true; do
  sleep "$POLL"
  cur=$(snap); [ -z "$cur" ] && continue
  changed=$(comm -13 <(echo "$base") <(echo "$cur") | awk -F'\t' '$3 ~ /^(idle|waiting|blocked)$/')
  if [ -n "$changed" ]; then echo "$changed"; exit 0; fi
  base=$cur
done
