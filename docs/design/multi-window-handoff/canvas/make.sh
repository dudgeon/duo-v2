#!/bin/bash
# Writes ../screens/ from the canvas boards in this folder (a copy of
# https://claude.ai/artifact/46yWPpDZn16Qtfrfhbuaw1 as of DL-313), then renders each to ../screens/png/.
#
#   bash docs/design/multi-window-handoff/canvas/make.sh
#
# The boards are pictures written in HTML: build to what they draw, don't port the markup.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../../.." && pwd)"
out="$here/../screens"
mkdir -p "$out/png"
canvas="https://claude.ai/artifact/46yWPpDZn16Qtfrfhbuaw1"
board() { # <Board> <name> <decision>
  python3 "$root/scripts/dc-render.py" "$here" "$1.dc.html" "$out/$2.html" --surface multi-window \
    --comment "Multi-window slice 1 (DL-311) · $3 · board $1.dc.html of $canvas. A picture written in HTML."
}
board Open           board-1-new-window      "board 1, option A: New Window and Open in New Window (DL-141, DL-311)"
board ColourTwelve   board-4a-prime-colours  "board 4a′, direction C: the twelve window colours (DL-313)"
board ColourNew      board-4b-new-colour     "board 4b, option A: a new window's colour, and changing it (DL-312)"
board ColourClassic  board-4c-classic        "board 4c, option A: Classic turns window colours off (DL-312)"
board WindowMenu     board-9-window-menu     "board 9, option C for slice 1: the system's Window menu (DL-311); A's marks are slice 2"
board Home           board-10-home           "board 10, option B: Home live in one window, Show Here in the others (DL-311, Q-431)"
board WinColour12    mini-window-coloured    "the mini window with a colour (component), light, Blue: where each colour goes"
if [ "${1:-}" != "--no-png" ]; then
  . "$root/docs/design/build-handoff/tools/lib.sh"
  CHROME_BIN="$(find_chrome)"
  for f in "$out"/*.html; do
    n="$(basename "$f" .html)"
    size="$(sed -n 's/.*name="design-size" content="\([0-9]*x[0-9]*\)".*/\1/p' "$f" | head -1)"
    shoot "file://$f" "${size%x*}" "${size#*x}" "$out/png/$n@2x.png" 2
    echo "rendered screens/png/$n@2x.png ($size)"
  done
fi
