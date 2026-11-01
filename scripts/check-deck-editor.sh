#!/bin/zsh
# Duo Decks' editor pieces (DL-295, DL-296, DL-303): background captures of the slide chip, the ⌃⌘N picker with "k"
# typed and the anchor mark, in Light, Dark and Classic, on a scratch workspace (a Home holding a project with
# decks/field-trial-review.md and templates/decks/northwind). Isolated support folder and Claude config; no Claude turn runs;
# nothing takes focus (F-227), and no duo2 verb is sent: the run is the instance's own --then actions.
#   scripts/check-deck-editor.sh [out-dir]    → <out>/<state>-<appearance>.png
# States: chip (the caret in slide 3, so its anchor mark shows), picker (New Slide with "k" typed), change (a chip clicked).
set -u
cd "${0:A:h}/.."
out=${1:-build/deck-editor}; mkdir -p "$out"; out=${out:A}
root=${DUO_DECK_ROOT:-/private/tmp/p3c}
ws=$root/ws; proj=$ws/work/orchard-robotics
study=docs/design/duo-decks-study/samples
if [[ ! -f $proj/decks/field-trial-review.md ]]; then
  mkdir -p $proj/decks $proj/templates/decks
  printf -- '---\ntype: home\n---\n# Home\n' > $ws/_HOME.md
  printf -- '---\ntype: project\n---\n# orchard-robotics\n\nField trial review.\n' > $proj/_PROJECT.md
  cp -R $study/decks/. $proj/decks/
  cp -R $study/templates/decks/. $proj/templates/decks/
fi
doc=$proj/decks/field-trial-review.md
open="open:orchard-robotics,open-file:$doc,wait:2"
run() {   # run <state> <appearance> <width> <actions>
  local n="$1-$2"
  chmod -R u+w $root/cc-$n $root/sup-$n 2>/dev/null; rm -rf $root/cc-$n $root/sup-$n; mkdir -p $root/cc-$n $root/sup-$n
  env -u DUO_SUPPORT_DIR DUO_APPEARANCE=$2 DUO_EXTRA_ENV="DUO_SUPPORT_DIR=$root/sup-$n CLAUDE_CONFIG_DIR=$root/cc-$n DUO_APPEARANCE=$2" DUO_TIMEOUT=${DUO_TIMEOUT:-60} \
    scripts/run-live.sh $ws "$out/$n.png" "$open,right-width:470,$4" "$out/$n.log" >/dev/null
  sleep 1
  [[ -f $out/$n.png ]] && echo "captured $n" || echo "FAILED $n"
}
for a in ${=DUO_APPEARANCES:-light dark classic}; do
  run chip $a 470 "editor-js:duo.deckGo(3),wait:1"
  run picker $a 470 "editor-js:duo.deckGo(4),wait:1,editor-js:duo.deckNewSlide(),editor-js:duo.deckType('k'),wait:1"
done
