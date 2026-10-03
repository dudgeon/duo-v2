#!/bin/bash
# Renders every design screen in ../screens to a PNG, so there is a pixel target to build against.
#
#   bash docs/design/build-handoff/tools/render-references.sh
#
# Run it on the Mac: the designs use the system faces (SF Pro, SF Mono), which only resolve there.
# Output: ../screens/png/<name>@2x.png at twice the design size (1440x900 design -> 2880x1800 px).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
. "$here/lib.sh"
CHROME_BIN="$(find_chrome)"
out="$root/screens/png"
mkdir -p "$out/wireframes"

if [ "$(uname)" != "Darwin" ]; then
  echo "Warning: not macOS. The system faces will fall back, so these PNGs are not a faithful target." >&2
fi

count=0
while IFS= read -r f; do
  rel="${f#"$root/screens/"}"
  name="${rel%.html}"
  size="$(sed -n 's/.*name="design-size" content="\([0-9]*x[0-9]*\)".*/\1/p' "$f" | head -1)"
  if [ -z "$size" ]; then echo "Skipping $rel: no design-size meta" >&2; continue; fi
  w="${size%x*}"; h="${size#*x}"
  shoot "file://$(urlencode_path "$f")" "$w" "$h" "$out/$name@2x.png" 2
  echo "rendered  screens/png/$name@2x.png  (${w}x${h} pt)"
  count=$((count+1))
done < <(find "$root/screens" -name '*.html' -not -path '*/png/*' | sort)
echo "$count screens rendered with: $CHROME_BIN"
