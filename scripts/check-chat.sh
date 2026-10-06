#!/bin/bash
# Chat mode's comparison loop (chat-mode-handoff): each board's fixture state, captured, cropped to
# the board (the console pane, 680×860 at x 300; the window board whole), and compared.
#
#   scripts/check-chat.sh                  build, then every board
#   scripts/check-chat.sh text tools       only these boards
#   NO_BUILD=1 scripts/check-chat.sh       reuse build/Duo.app
#
# Writes build/ui/chat-<board>.png (the crop) and build/ui/chat-<board>-compare.png (TARGET | BUILD | DIFFERENCE).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
boards=("$@")
[ ${#boards[@]} -gt 0 ] || boards=(window toggle text tools permission-edit permission-bash plan question-multi question-other question-review question-previews question-chat-decline composer status fallback)
states=()
for b in "${boards[@]}"; do states+=("chat-$b"); done
NO_COMPARE=1 scripts/check-ui.sh "${states[@]}" >/dev/null
for b in "${boards[@]}"; do
  if [ "$b" = window ]; then box=(0 0 1440 860); else box=(300 0 680 860); fi
  python3 scripts/chat-crop.py "build/ui/chat-$b.png" "build/ui/chat-$b-board.png" "${box[@]}" >/dev/null
  bash docs/design/build-handoff/tools/compare.sh "chat-mode-handoff/$b" "build/ui/chat-$b-board.png" "build/ui/chat-$b-compare.png" >/dev/null
  echo "$b  →  build/ui/chat-$b-compare.png"
done
