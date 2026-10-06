#!/bin/bash
# Puts a screenshot of the app next to its design target and shows where they differ.
#
#   bash docs/design/build-handoff/tools/compare.sh <screen> <app-screenshot.png> [out.png] [--content-only]
#
#   <screen>          a target in ../screens without .html: overview, project, flow-zoom-3, ...
#   <app-screenshot>  the app window at the design size (1440x900 pt), any pixel density
#   --content-only    the screenshot has no toolbar (a view snapshot, not a window capture);
#                     it is compared against the target below the toolbar, which is 38 pt plus
#                     its 1 pt bottom border (CSS content-box): content starts at 39
#
# Output: one PNG with three panels: TARGET | BUILD | DIFFERENCE.
# In DIFFERENCE, black means identical. Bright edges are things in the wrong place or the wrong colour.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
. "$here/lib.sh"
CHROME_BIN="$(find_chrome)"

screen="${1:?usage: compare.sh <screen> <app-screenshot.png> [out.png] [--content-only]}"
shot="${2:?usage: compare.sh <screen> <app-screenshot.png> [out.png] [--content-only]}"
out=""; top=0
shift 2
for a in "$@"; do
  case "$a" in
    --content-only) top=39 ;;
    *) out="$a" ;;
  esac
done
target="$root/screens/$screen.html"
# <handoff>/<screen> names a target in another handoff outright (chat-mode-handoff/text: board names repeat).
if [[ "$screen" == */* ]]; then root="$(cd "$root/../${screen%%/*}" && pwd)"; screen="${screen#*/}"; target="$root/screens/$screen.html"; fi
# Search's targets live in their own handoff (search-handoff/screens); same renderer, same compare.
for other in search-handoff surfaces-handoff slice2-handoff slice3-handoff many-projects-handoff stand-ins-handoff folder-handoff tables-handoff; do
  [ -f "$target" ] || { [ -f "$root/../$other/screens/$screen.html" ] && root="$(cd "$root/../$other" && pwd)" && target="$root/screens/$screen.html"; } || true
done
[ -f "$target" ] || { echo "No such target: screens/$screen.html" >&2; exit 1; }
[ -f "$shot" ] || { echo "No such screenshot: $shot" >&2; exit 1; }
shot="$(cd "$(dirname "$shot")" && pwd)/$(basename "$shot")"
[ -n "$out" ] || out="${TMPDIR:-/tmp}/duo-compare/$screen.png"
mkdir -p "$(dirname "$out")"

size="$(sed -n 's/.*name="design-size" content="\([0-9]*x[0-9]*\)".*/\1/p' "$target" | head -1)"
w="${size%x*}"; h="${size#*x}"

ref="$root/screens/png/$screen@2x.png"
if [ ! -s "$ref" ] || [ "$target" -nt "$ref" ]; then
  mkdir -p "$(dirname "$ref")"
  shoot "file://$(urlencode_path "$target")" "$w" "$h" "$ref" 2
fi

ph=$((h - top))                       # panel height
url="file://$(urlencode_path "$here/compare.html")?ref=file://$(urlencode_path "$ref")&shot=file://$(urlencode_path "$shot")&w=$w&h=$h&top=$top&name=$screen"
shoot "$url" $((w * 3 + 40)) $((ph + 56)) "$out" 1
echo "$out"
