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
[ ${#boards[@]} -gt 0 ] || boards=(window toggle text tools permission-edit permission-bash plan question-multi question-other question-review question-previews question-chat-decline composer status fallback
  polish-collapsed polish-expanded polish-needs-you polish-output polish-edits polish-thinking polish-agents polish-todos polish-tools polish-failed polish-paste polish-bar-thin
  slash-output slash-context slash-model-card slash-effort-card slash-fallback-named slash-menu)
states=()
for b in "${boards[@]}"; do states+=("chat-$b"); done
NO_COMPARE=1 scripts/check-ui.sh "${states[@]}" >/dev/null
for b in "${boards[@]}"; do
  target="chat-mode-handoff/$b"
  case "$b" in
    window) box=(0 0 1440 860) ;;
    # chat-polish-handoff (DL-135): the run boards are the pane; the candidate boards are its feed, below the tab strip.
    polish-collapsed|polish-expanded|polish-needs-you) box=(300 0 680 860); target="chat-polish-handoff/${b#polish-}" ;;
    polish-bar-thin) box=(300 0 680 520); target="chat-polish-handoff/bar-thin" ;;
    polish-*) box=(300 36 680 560); target="chat-polish-handoff/${b#polish-}" ;;
    # chat-slash-handoff (DL-143): boards of the console pane, compared region by region.
    slash-*) box=(300 0 680 860); target="chat-slash-handoff/${b#slash-}" ;;
    *) box=(300 0 680 860) ;;
  esac
  python3 scripts/chat-crop.py "build/ui/chat-$b.png" "build/ui/chat-$b-board.png" "${box[@]}" >/dev/null
  bash docs/design/build-handoff/tools/compare.sh "$target" "build/ui/chat-$b-board.png" "build/ui/chat-$b-compare.png" >/dev/null
  # A composer draws its caret only while Duo is the active app: a capture made while another app
  # had focus (or the screen was locked) shows none, whatever has the keyboard.
  note=""; grep 'trace capture' "build/ui/chat-$b.log" 2>/dev/null | tail -1 | grep -q 'active=false' && note="  (Duo wasn't active: no caret)"
  echo "$b  →  build/ui/chat-$b-compare.png$note"
done
