#!/bin/bash
# C-73, F-249/F-250: a real ⌘V and a real Return, delivered with NSApp.sendEvent so the app's own key
# monitor sees them as typed keys, while a task note's references field has the keyboard and a chat
# shows beside it. The pasted text must land in the field (not the chat composer), and Return must save
# it as a link in `references:`, draw it, and leave the field.
#
#   scripts/check-task-paste.sh [path/to/Duo.app]      default build/Duo.app (run scripts/bundle.sh first)
#
# VISIBLE: a Duo window is shown (DUO_TEST_FOREGROUND=1) for about 20 s per case, so run it only with
# Geoff's OK. Isolated: its own short DUO_SUPPORT_DIR and a scratch project under /tmp. A web view's
# paste reads the real clipboard in WebKit's own process, so the harness's private pasteboard can't be
# used: with Geoff's OK, `real-key:cmd-v` saves every item on the general pasteboard, holds the test text
# there for 1 s and restores it; this script checks the text is the same afterwards.
# Captures: build/ui/task-paste-*.png.
# Exit status is the number of failures.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:-$root/build/Duo.app}"
mkdir -p "$root/build/ui"
fails=0
case_() {   # case_ <name> <text to paste> <expected link name>
  local name="$1" text="$2" want="$3"
  local ws; ws="$(mktemp -d /tmp/tpaste.XXXXXX)"
  mkdir -p "$ws/tasks" "$ws/docs"
  printf '# Plan\n' > "$ws/docs/plan.md"; printf '# Spec\n' > "$ws/docs/spec.md"
  printf -- '---\ntype: task\nstatus: todo\nsessions: []\nreferences:\n  - "[Plan](../docs/plan.md)"\n---\n\nNotes\n' > "$ws/tasks/t.md"
  text="${text//@ROOT@/$ws}"
  local log="$root/build/ui/task-paste-$name.log" png="$root/build/ui/task-paste-$name.png"
  rm -f "$png" "$log"
  local support="/tmp/d-tp-$name"; rm -rf "$support"; mkdir -p "$support"
  env -u DUO_SUPPORT_DIR DUO_SUPPORT_DIR="$support" DUO_TEST_FOREGROUND=1 open -g -n --env DUO_TEST_FOREGROUND=1 --stderr "$log" "$app" \
    --args --state chat-composer --capture-window "$png" \
    --then "wait:1,proof-task:$ws,wait:2,ref-focus,wait:3,real-key:cmd-v=$text,wait:1,proof-report,real-key:return,wait:1,proof-report"
  local i
  for ((i = 0; i < 60; i++)); do [[ -f "$png" ]] && break; sleep 1; done
  sleep 2
  local pid; pid=$(pgrep -f -- "--capture-window $png" | head -1)
  if [[ -n "$pid" ]]; then kill -TERM "$pid"; for ((i = 0; i < 10; i++)); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done; fi
  local before after
  before=$(grep '^proof-report:' "$log" | sed -n 1p); after=$(grep '^proof-report:' "$log" | sed -n 2p)
  local ok=1
  # The key monitor only acts for the key window, so a run whose window never became key proves nothing
  # (a locked screen, or the app not allowed to activate): say so instead of passing or failing.
  if ! grep -q '^real-key: cmd-v key=true' "$log"; then
    echo "✘ $name: Duo's window never became key (screen locked?), so ⌘V didn't go through the key monitor: $(grep -m1 '^real-key: cmd-v' "$log")"
    fails=$((fails + 1)); rm -rf "$ws"; return
  fi
  [[ -z "$before" || -z "$after" ]] && { echo "✘ $name: no report ($log)"; fails=$((fails + 1)); rm -rf "$ws"; return; }
  # After ⌘V: the text is in the field (so the editor, not the composer, took it), the composer is empty.
  [[ "$before" == *'composer=""'* ]] || { echo "✘ $name: the chat composer got the paste: ${before:0:200}"; ok=0; }
  [[ "$before" == *'"field":"'"$text"'"'* ]] || { echo "✘ $name: the field does not hold the pasted text: ${before:0:240}"; ok=0; }
  [[ "$before" == *'INPUT'* ]] || { echo "✘ $name: the references field did not hold the keyboard after ⌘V: ${before:0:200}"; ok=0; }
  # After Return: saved as a link, drawn, field left and empty.
  [[ "$after" == *"$want"* ]] || { echo "✘ $name: no link named '$want' after Return: ${after:0:240}"; ok=0; }
  [[ "$after" == *'"field":""'* ]] || { echo "✘ $name: the field kept its text: ${after:0:240}"; ok=0; }
  [[ "$after" == *'"editing":"INPUT"'* ]] && { echo "✘ $name: still in edit mode after Return"; ok=0; }
  [[ $ok == 1 ]] && echo "✔ $name: ⌘V landed in the references field, Return saved '$want' and left edit mode" || fails=$((fails + 1))
  rm -rf "$ws"
}
clip_before="$(pbpaste | shasum)"
case_ url "https://example.com/proof" "example.com"
case_ path "@ROOT@/docs/spec.md" "spec"
sleep 2
if [[ "$(pbpaste | shasum)" == "$clip_before" ]]; then echo "✔ the clipboard's text is as it was"; else echo "✘ the clipboard's text changed"; fails=$((fails + 1)); fi
echo "$fails failed"
exit "$fails"
