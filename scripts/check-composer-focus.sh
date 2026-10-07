#!/bin/bash
# Only the chat on screen has a composer (C-47, F-183): every chat board, and each again with Home's
# session in chat underneath (`home-chat`), must report no composer of a chat that isn't showing, so
# a hidden composer can never take the keyboard. Also Home's own chat at All projects (list-1440).
#
#   scripts/check-composer-focus.sh          reuse build/Duo.app (run scripts/bundle.sh first)
#
# Isolated: its own DUO_SUPPORT_DIR. Exit status is the number of failures.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
support="${DUO_CHECK_SUPPORT:-/tmp/d-focus}"
mkdir -p "$support"
out="$(mktemp -d /tmp/duo-focus.XXXXXX)"
# Every board in ChatTargets.boards (the array up to `screens`).
boards=$(sed -n '/static let boards = \[/,/static let screens/p' Sources/DuoKit/Debug/ChatTargets.swift | grep -v '^ *//' | grep -v 'static let screens' | grep -o '"[a-z-]*"' | tr -d '"' | sed 's/^/chat-/')
fails=0
run() {   # run <state> <then>
  local s="$1" then="$2" log="$out/$1-${2%%,*}.log"
  env -u DUO_SUPPORT_DIR DUO_SUPPORT_DIR="$support" open -W -n --stdout /dev/null --stderr "$log" "$root/build/Duo.app" \
    --args --state "$s" --then "$then" --capture "$out/$s.png" &
  local pid=$! i
  for ((i = 0; i < 160; i++)); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
  kill -0 "$pid" 2>/dev/null && { kill "$pid"; echo "✘ $s ($then): no capture"; fails=$((fails + 1)); return; }
  local r; r=$(grep -m1 '^focus-check:' "$log" || echo "focus-check: no report")
  if [[ "$r" == "focus-check: ok" ]]; then echo "✔ $s ${then%%,*}"; else echo "✘ $s ${then%%,*}: ${r#focus-check: }"; fails=$((fails + 1)); fi
}
for s in $boards; do
  run "$s" "wait:1,focus-check"
  run "$s" "home-chat,wait:1,focus-check"
done
run list-1440 "wait:1,focus-check"
echo "$fails failed"
rm -rf "$out"
exit "$fails"
