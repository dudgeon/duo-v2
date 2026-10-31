#!/bin/bash
# Renders the handoff's screens to screens/png/<name>.png with the handoff's renderer (1×).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../../build-handoff/tools/lib.sh"
CHROME_BIN="$(find_chrome)"
screens="$here/../screens"
mkdir -p "$screens/png"
for f in "$screens"/*.html; do
  name="$(basename "$f" .html)"
  size="$(sed -n 's/.*name="design-size" content="\([0-9]*x[0-9]*\)".*/\1/p' "$f" | head -1)"
  shoot "file://$(urlencode_path "$f")" "${size%x*}" "${size#*x}" "$screens/png/$name.png" 1
  echo "rendered $name ($size)"
done
