#!/bin/bash
# Renders the Duo Decks handoff screens to screens/png/<name>.png with the handoff renderer (headless Chrome).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../build-handoff/tools/lib.sh"
CHROME_BIN="$(find_chrome)"
mkdir -p "$here/screens/png"
for f in "$here"/screens/*.html; do
  name="$(basename "$f" .html)"
  [ -n "${ONLY:-}" ] && [[ "$name" != *$ONLY* ]] && continue
  size="$(sed -n 's/.*name="design-size" content="\([0-9]*x[0-9]*\)".*/\1/p' "$f" | head -1)"
  shoot "file://$(urlencode_path "$f")" "${size%x*}" "${size#*x}" "$here/screens/png/$name.png" 2
  echo "rendered $name ($size)"
done
