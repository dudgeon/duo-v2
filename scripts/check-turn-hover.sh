#!/bin/bash
# F-738: the pointer goes from a chat turn onto its row's Copy and presses it, in an isolated background Duo (never shown,
# F-227). For each appearance, chat width and turn (Claude's reply and your message, from the chat-md-history fixture):
#   1. a run shows the turn's row and finds where its Copy is (anchors);
#   2. a run moves the pointer (real mouse-moved events, `pointer:`) from the turn down onto Copy in 3 pt steps, saying
#      which turn is hovered after each, then presses the button under the pointer (`ax-press:`, an accessibility hit
#      test) and says what Copy put on the pasteboard (an isolated run's own, never the clipboard, F-739).
# Passes when the turn stays hovered all the way and the press lands on Copy and copies that turn.
#
#   scripts/check-turn-hover.sh                 build, then light dark classic × 480 and wide
#   NO_BUILD=1 APPEARANCES="dark" WIDTHS="480" scripts/check-turn-hover.sh
#
# Writes build/ui/hover-<appearance>-<width>-<turn>.png (the row shown after the walk) and .log.
set -uo pipefail
export DUO_ISOLATED=1
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
[ -n "${NO_BUILD:-}" ] || scripts/bundle.sh >/dev/null || exit 1
out="$root/build/ui"
mkdir -p "$out"
fails=0
LEFT=${LEFT:-799}

run() {   # run <name> <appearance> <then>
  local name="$1" look="$2" then="$3" sup
  sup="$(mktemp -d /tmp/duo-hv.XXXXXX)"
  rm -f "$out/$name.png"
  open -g -W -n --env DUO_ISOLATED=1 --env "DUO_SUPPORT_DIR=$sup" --env "DUO_APPEARANCE=$look" --stdout /dev/null --stderr "$out/$name.log" \
    "$root/build/Duo.app" --args --state chat-md-history --then "$then" --capture "$out/$name.png" &
  local pid=$!
  for ((i = 0; i < 240; i++)); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
  if kill -0 "$pid" 2>/dev/null; then kill "$pid"; echo "$name: no capture after 60 s" >&2; fi
  wait "$pid" 2>/dev/null
  chmod -R u+w "$sup" 2>/dev/null; rm -rf "$sup"
}

for look in ${APPEARANCES:-light dark classic}; do
  for width in ${WIDTHS:-480 wide}; do
    # The chat pane 480 wide: the window at its narrowest (1280), the right pane hidden and the left pane widened to the rest.
    size=""; [ "$width" = 480 ] && size="right:hidden,window-width:1280,left-width:$LEFT,"
    for turn in 2 3; do
      who=$([ $turn = 2 ] && echo claude || echo you)
      name="hover-$look-$width-$who"
      run "$name-find" "$look" "wait:1,${size}chat-screen:idle,turn-uuids,turn-hover:$turn,wait:1,anchors:$out/$name.json"
      read -r x y < <(python3 - "$out/$name.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
c = [a["frame"] for a in d["anchors"] if a.get("role") == "AXButton" and a.get("label") == "Copy" and a["frame"]["height"] == 22]
print(*(f"{c[0]['x'] + 12:.0f} {c[0]['y'] + 11:.0f}".split()) if c else "0 0")
EOF
)
      if [ "$x" = 0 ]; then echo "✘ $name: no Copy in the row"; fails=$((fails + 1)); continue; fi
      # From 60 pt above Copy (on the turn) down onto Copy's middle.
      then="wait:1,${size}chat-screen:idle,turn-uuids,pointer:$x $((y - 60)),wait:0.3,turn-state:y$((y - 60))"
      for ((yy = y - 57; yy <= y; yy += 3)); do then="$then,+pointer:$x $yy,wait:0.15,turn-state:y$yy"; done
      then="$then,ax-press:$x $y,wait:0.5,turn-state:after"
      run "$name" "$look" "$then"
      hovers=$(grep '^turn-state y' "$out/$name.log" | sed 's/.*hover=\([^ ]*\).*/\1/' | tr -d '\n')
      press=$(grep '^ax-press' "$out/$name.log")
      after=$(grep '^turn-state after' "$out/$name.log")
      if [[ "$hovers" =~ ^$turn+$ ]] && [[ "$press" == *'"Copy@'* ]] && [[ "$after" == *"copied=$turn "* ]]; then
        echo "✔ $name: hovered $turn all the way to Copy ($x,$y); pressed; ${after#*copied=}"
      else
        echo "✘ $name: hover along the walk '$hovers'; $press; $after"; fails=$((fails + 1))
      fi
    done
  done
done
exit $((fails > 0))
