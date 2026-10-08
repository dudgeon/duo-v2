#!/bin/bash
# The PowerPoint viewer's states as live captures of an isolated Duo on a scratch workspace (the way F-121's
# proofs were made), cropped to the right pane, so two builds can be compared byte for byte.
#
#   scripts/check-deck.sh                       this checkout's build/Duo.app, into build/deck/
#   DUO_APP=/path/Duo.app OUT=/tmp/x scripts/check-deck.sh      another build (e.g. one of origin/main) into /tmp/x
#   scripts/check-deck.sh compare <dirA> <dirB> byte-compare two runs, state by state
#
# States: viewer (slide 3), picking (the dashed outline on a shape), picked (a shape picked, the picker bar),
# fallback (a password-protected deck: Quick Look under the notice). Each is cropped to the pane at 460 wide,
# and, for the picker bar, to the pane's bottom 800.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
if [ "${1:-}" = compare ]; then
  same=0; diff=0
  for f in "$2"/*-pane.png; do
    n=$(basename "$f")
    if cmp -s "$f" "$3/$n"; then same=$((same + 1)); echo "same       $n"; else diff=$((diff + 1)); echo "DIFFERENT  $n"; fi
  done
  echo "$same identical, $diff different"; [ "$diff" = 0 ]; exit
fi
out="${OUT:-$root/build/deck}"
ws=/tmp/d-dx-wsdeck
mkdir -p "$out" $ws/Home $ws/work/garden /tmp/d-dx /tmp/d-dx-cc
printf -- '---\ngoal: "Home"\n---\n\n# Home\n' > $ws/Home/HOME.md
printf -- '---\ngoal: "Plan the garden"\n---\n\n# garden\n' > $ws/work/garden/PROJECT.md
cp Spikes/PptxViewer/decks/garden.pptx "$ws/work/garden/Garden plan.pptx"
printf '\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1' > "$ws/work/garden/Board pack.pptx"; head -c 2048 /dev/zero >> "$ws/work/garden/Board pack.pptx"
export DUO_EXTRA_ENV="DUO_SUPPORT_DIR=/tmp/d-dx CLAUDE_CONFIG_DIR=/tmp/d-dx-cc"
export DUO_APP="${DUO_APP:-build/Duo.app}"
states=("$@"); [ ${#states[@]} -gt 0 ] || states=(viewer picking picked fallback)
for s in "${states[@]}"; do
  case "$s" in
    viewer) file="Garden plan.pptx"; acts="slide-go:3,freeze:3" ;;
    picking) file="Garden plan.pptx"; acts="slide-picking,slide-hover:2/7,freeze:3" ;;
    picked) file="Garden plan.pptx"; acts="slide-pick:2/7,freeze:3" ;;
    fallback) file="Board pack.pptx"; acts="freeze:3" ;;
    *) echo "no state $s" >&2; exit 1 ;;
  esac
  env -u DUO_SUPPORT_DIR DUO_TIMEOUT=60 scripts/run-live.sh $ws "$out/$s.png" "open:garden,open-file:$ws/work/garden/$file,right-width:460,$acts" "$out/$s.log" >/dev/null
  python3 scripts/chat-crop.py "$out/$s.png" "$out/$s-pane.png" 980 40 460 860 >/dev/null
  echo "$s  →  $out/$s-pane.png"
done
