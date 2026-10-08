#!/bin/bash
# Renders the study boards to boards/png/<name>@2x.png with the handoff's renderer.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../../build-handoff/tools/lib.sh"
CHROME_BIN="$(find_chrome)"
mkdir -p "$here/boards/png"
for f in "$here"/boards/*.html; do
  name="$(basename "$f" .html)"
  [ -n "${ONLY:-}" ] && [[ "$name" != *$ONLY* ]] && continue
  size="$(sed -n 's/.*name="design-size" content="\([0-9]*x[0-9]*\)".*/\1/p' "$f" | head -1)"
  shoot "file://$(urlencode_path "$f")" "${size%x*}" "${size#*x}" "$here/boards/png/$name@2x.png" 2
  echo "rendered $name ($size)"
done
