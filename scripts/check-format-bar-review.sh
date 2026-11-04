#!/bin/zsh
# Review in the Markdown formatting bar (DL-317): background captures of each state at 460, 420 and 360 in Light, Dark and
# Classic, on a scratch workspace with an isolated support folder and config. No Claude turn runs; nothing takes focus (F-227).
#   scripts/check-format-bar-review.sh [out-dir]   → <out>/<state>-<appearance>-<width>.png, each compared by eye with
#   docs/design/markdown-toolbar-handoff/screens/png/review-in-bar@2x.png (region by region; scripts/compare-format-bar-review.py)
# States: clean (editing, nothing to review), marks (not editing, the document has marks), suggest (editing, marks, Suggesting),
# table (caret in a table, Suggesting), listening (dark, Suggesting), menu (the mode menu open), menu-markup (Markup open too).
set -u
cd "${0:A:h}/.."
out=${1:-build/format-bar-review}; mkdir -p "$out"; out=${out:A}
root=${DUO_BAR_ROOT:-/private/tmp/mdbr}
ws=$root/ws
rm -rf $ws; mkdir -p $ws/Home $ws/work/garden
printf -- '---\ngoal: "Home"\n---\n\n# Home\n' > $ws/Home/HOME.md
printf -- '---\ngoal: "Plan"\n---\n\n# garden\n' > $ws/work/garden/PROJECT.md
marks=$'---\ntitle: Offline mode\n---\n\n# Offline mode\n\nThe sync engine retries every {~~30~>10~~}{>>@geoff 2026-10-27 #s1<<} seconds{++, and gives up after an hour++}{>>@sam 2026-10-27 #s2: is this true?<<}.\n\nWe store nothing in the cloud except {==crash reports==}{>>@sam 2026-10-27 #c1: Is this true for crash reports?<<}.\n'
clean=$'# Offline mode\n\nThe sync engine retries every 30 seconds.\n\nWe store nothing in the cloud except crash reports.\n'
table=$'# Thresholds\n\nLimits per path, as finance confirmed on Oct 3.\n\n| Path | Limit | Approvers |\n| ----- | ----- | --------: |\n| Card | $500 | 2 |\n| Async | $250 | 1 |\n'
# run <state> <appearance> <width> <file> <actions>
run() {
  local n="$1-$2-$3"
  # each run starts from the same files: Suggest Edits writes a line into the file it is turned on for
  print -rn -- "$marks" > $ws/work/garden/marks.md; print -rn -- "$clean" > $ws/work/garden/clean.md; print -rn -- "$table" > $ws/work/garden/table.md
  chmod -R u+w $root/cc-$n $root/sup-$n 2>/dev/null; rm -rf $root/cc-$n $root/sup-$n; mkdir -p $root/cc-$n $root/sup-$n
  env -u DUO_SUPPORT_DIR DUO_APPEARANCE=$2 DUO_EXTRA_ENV="DUO_SUPPORT_DIR=$root/sup-$n CLAUDE_CONFIG_DIR=$root/cc-$n DUO_APPEARANCE=$2" DUO_TIMEOUT=${DUO_TIMEOUT:-60} \
    scripts/run-live.sh $ws "$out/$n.png" "open:garden,open-file:$ws/work/garden/$4,wait:2,right-width:$3,$5" "$out/$n.log" >/dev/null
  sleep 1
  [[ -f $out/$n.png ]] && echo "captured $n" || echo "FAILED $n"
}
for w in 460 420 360; do
  for a in light dark; do
    run clean $a $w clean.md "bar-focus,bar-select:30,bar-mic,wait:2"
    run marks $a $w marks.md "bar-mic,wait:2"
    run suggest $a $w marks.md "verb:doc review on,bar-focus,bar-select:60,bar-mic,wait:3"
    run table $a $w table.md "bar-focus,bar-select:130,bar-mic,wait:3"
  done
done
run listening dark 460 marks.md "verb:doc review on,bar-focus,bar-select:60,bar-mic,bar-listen,wait:3"
run listening dark 360 marks.md "verb:doc review on,bar-focus,bar-select:60,bar-mic,bar-listen,wait:3"
run menu classic 460 marks.md "verb:doc review on,bar-focus,bar-select:60,bar-nomic,review-menu:mode,wait:3"
run menu-markup light 460 marks.md "verb:doc review on,bar-focus,bar-select:60,bar-mic,review-menu:markup,wait:3"
run menu light 460 marks.md "bar-mic,review-menu:mode,wait:3"
