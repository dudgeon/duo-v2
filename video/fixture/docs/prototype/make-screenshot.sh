#!/bin/bash
# Rebuilds docs/research/feedback/denise-p3-screenshot.png: scan-review.html#linden at an iPhone viewport
# (390x844 at 3x) in headless Chrome driven by shot.mjs (DevTools protocol, exact viewport). Never shows a window or takes focus.
# Usage: make-screenshot.sh [preview-dir]   (with a dir, also writes preview PNGs at 960x590, 615x800, 390x844)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
python3 "$here/make-prototype.py"   # regenerates scan-review.html from world.json
page="$here/scan-review.html"
out="$here/../research/feedback/denise-p3-screenshot.png"
mkdir -p "$(dirname "$out")"

shot() { # <png> <scale> <w> <h> <url>
  node "$here/shot.mjs" "$5" "$1" "$3" "$4" "$2"
}

shot "$out" 3 390 844 "file://$page#linden"
echo "wrote $out"

if [ $# -gt 0 ]; then
  d="$1"; mkdir -p "$d"
  for size in 960x590 615x800 390x844; do
    w=${size%x*}; h=${size#*x}
    shot "$d/review-$size.png" 1 "$w" "$h" "file://$page"
    shot "$d/linden-$size.png" 1 "$w" "$h" "file://$page#linden"
  done
  echo "previews in $d"
fi
