#!/bin/bash
# Renders every screen in ../screens to a PNG, using the renderer that ships with build-handoff.
#
#   bash docs/design/frontmatter-handoff/tools/render-references.sh
#
# Run it on the Mac: the designs use the system faces, which only resolve there.
# Output: ../screens/png/<name>@2x.png at twice the design size.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
lib="${DUO_RENDER_LIB:-$root/../build-handoff/tools/lib.sh}"
[ -f "$lib" ] || { echo "Cannot find the renderer at $lib (set DUO_RENDER_LIB)" >&2; exit 1; }
. "$lib"
CHROME_BIN="$(find_chrome)"
out="$root/screens/png"
mkdir -p "$out"

if [ "$(uname)" != "Darwin" ]; then
  echo "Warning: not macOS. The system faces will fall back, so these PNGs are not a faithful target." >&2
fi

count=0
for f in "$root"/screens/*.html; do
  name="$(basename "$f" .html)"
  size="$(sed -n 's/.*name="design-size" content="\([0-9]*x[0-9]*\)".*/\1/p' "$f" | head -1)"
  if [ -z "$size" ]; then echo "Skipping $name: no design-size meta" >&2; continue; fi
  w="${size%x*}"; h="${size#*x}"
  shoot "file://$(urlencode_path "$f")" "$w" "$h" "$out/$name@2x.png" 2
  echo "rendered  screens/png/$name@2x.png  (${w}x${h} pt)"
  count=$((count+1))
done
echo "$count screens rendered with: $CHROME_BIN"
