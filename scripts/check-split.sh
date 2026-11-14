#!/bin/zsh
# Split view, slice 1 (DL-275 to DL-278): live background runs on a scratch workspace with an
# isolated support folder and config. No Claude turn runs. One launch per case: it captures the
# window and prints the split's report, which is asserted. The captures are what gets compared with
# docs/design/split-view-handoff/screens/ (docs/design/build-handoff/tools/compare.sh).
#   scripts/check-split.sh [out-dir]
set -u
export DUO_ISOLATED=1   # every duo2 here reaches only the test instance; refuses, never the user's Duo (F-529)
cd "${0:A:h}/.."
out=${1:-build/split}; mkdir -p "$out"; out=${out:A}
root=${DUO_SPLIT_ROOT:-/private/tmp/pcf-split-1}
app=${DUO_APP:-build/Duo.app}
fails=0 total=0

fresh() {
  ws=$root/ws-$1; rm -rf $ws $root/cc-$1 $root/sup-$1
  mkdir -p $ws/Home $ws/work/garden $root/cc-$1 $root/sup-$1
  printf -- '---\ngoal: "Home"\n---\n\n# Home\n' > $ws/Home/HOME.md
  printf -- '---\ngoal: "Plan"\n---\n\n# garden\n' > $ws/work/garden/PROJECT.md
  printf -- '# Field trial review\n\nThe first paragraph, with **bold** and `code`.\n\n## Findings\n\n- one\n- two\n\n## Next\n\nDone.\n' > $ws/work/garden/review.md
  printf -- '<h1>Page</h1><p id="a">hello</p>\n' > $ws/work/garden/page.html
}
# run <name> <size> <actions>
run() {
  local png=$out/$1.png err=$out/$1.log
  rm -f $png
  env -u DUO_SUPPORT_DIR -u DUO_SOCKET -u DUO_TOKEN DUO_ISOLATED=1 DUO_SUPPORT_DIR=$root/sup-$1 CLAUDE_CONFIG_DIR=$root/cc-$1 ANTHROPIC_MODEL=claude-haiku-5-5 DUO_APPEARANCE=${APPEARANCE:-light} \
    $app/Contents/MacOS/Duo --workspace $ws --window $2 --capture-window $png --then "$3" 2>$err &
  local pid=$!
  for i in {1..${DUO_TIMEOUT:-60}}; do [[ -f $png ]] && break; sleep 1; done
  sleep 2; kill -TERM $pid 2>/dev/null; for i in {1..10}; do kill -0 $pid 2>/dev/null || break; sleep 1; done
}
expect() {
  total=$((total+1))
  if grep -qF -- "$3" "$2"; then echo "ok   $1"; else fails=$((fails+1)); echo "FAIL $1: ${2:t} should have '$3'"; sed 's/^/       | /' "$2" | tail -12; fi
}

open="open:garden"
# DL-306: 1440 keeps all three panes (sidebar, console at 400, two sides); 1280 is under about 1,300, so the sidebar folds.
fresh m1440x900
run m1440x900 1440x900 "$open,split:page.html,wait:3,split-report"
expect "1440x900: a split is made" $out/m1440x900.log "active: left"
expect "1440x900: the sidebar stays" $out/m1440x900.log "sidebar folded by the split: false"
expect "1440x900: not folded to one side" $out/m1440x900.log "folded: false"
fresh m1310x800
run m1310x800 1310x800 "$open,split:page.html,wait:3,split-report"
expect "1310x800: the sidebar stays just over the edge (it folds under 1,303)" $out/m1310x800.log "sidebar folded by the split: false"
fresh m1280x800
run m1280x800 1280x800 "$open,split:page.html,wait:3,split-report"
expect "1280x800: a split is made" $out/m1280x800.log "active: left"
expect "1280x800: the sidebar folded to its rail" $out/m1280x800.log "sidebar folded by the split: true"
expect "1280x800: not folded to one side" $out/m1280x800.log "folded: false"
fresh html
run html 1440x900 "$open,split:page.html,wait:3,split-report"
expect "html: a page beside its source" $out/html.log "right: Page"
fresh swap
run swap 1440x900 "$open,split:page.html,wait:2,split-swap,split-focus:left,wait:1,split-report"
expect "swap: the page is on the left" $out/swap.log "left: Page"
fresh peek
run peek 1280x800 "$open,split:page.html,wait:2,sidebar-peek:on,wait:2,split-report"
fresh narrow
run narrow 1280x800 "$open,split:page.html,wait:2,right-width:600,wait:2,split-report"
expect "narrow: under two sides the split folds" $out/narrow.log "folded: true"
fresh unfold
run unfold 1280x800 "$open,split:page.html,wait:2,right-width:600,wait:2,split-unfold,wait:2,split-report"
expect "unfold: the console narrows for two sides" $out/unfold.log "folded: false"
fresh close
run close 1440x900 "$open,split:page.html,wait:2,split-close,wait:2,split-report"
expect "close: the split is gone" $out/close.log "no split view showing"

# Geoff's four (2026-11-01): a wide window keeps its sidebar; widening brings a folded sidebar back and
# narrowing folds it again; closing gives the sidebar back; the window keeps its 1280 x 800 minimum.
fresh wide
run wide 2400x1200 "$open,split:page.html,wait:3,split-report"
expect "wide: a wide window keeps the sidebar" $out/wide.log "sidebar folded by the split: false"
fresh widen
run widen 1280x800 "$open,split:page.html,wait:2,window-width:2200,wait:2,split-report"
expect "widen: the sidebar comes back when the window is wide enough" $out/widen.log "sidebar folded by the split: false"
fresh renarrow
run renarrow 1280x800 "$open,split:page.html,wait:2,window-width:2200,wait:2,window-width:1280,wait:2,split-report"
expect "renarrow: and folds again when it's narrow" $out/renarrow.log "sidebar folded by the split: true"
fresh giveback
run giveback 1280x800 "$open,split:page.html,wait:2,split-close,wait:2,split-report"
expect "giveback: closing brings the sidebar back" $out/giveback.log "sidebar hidden: false"
fresh widenclose
run widenclose 1280x800 "$open,split:page.html,wait:2,window-width:2200,wait:2,window-width:1280,wait:2,split-close,wait:2,split-report"
expect "widenclose: after resizes, closing still brings the sidebar back" $out/widenclose.log "sidebar hidden: false"
expect "minimum: the window can't be made smaller than 1280 x 800" $out/giveback.log "min 1280x800"

# A split restored in a wider window than it was made in comes back with its sidebar and two sides (F-531):
# launch at 1280 (the sidebar folds), quit, relaunch at 1810.
relaunch() {   # relaunch <name> <size> <actions>: like run, on the same support folder, restoring
  local png=$out/$1.png err=$out/$1.log
  rm -f $png
  env -u DUO_SUPPORT_DIR -u DUO_SOCKET -u DUO_TOKEN DUO_ISOLATED=1 DUO_SUPPORT_DIR=$root/sup-rl CLAUDE_CONFIG_DIR=$root/cc-rl ANTHROPIC_MODEL=claude-haiku-5-5 DUO_APPEARANCE=${APPEARANCE:-light} DUO_RESTORE=1 \
    $app/Contents/MacOS/Duo --workspace $ws --window $2 --capture-window $png --then "$3" 2>$err &
  local pid=$!
  for i in {1..${DUO_TIMEOUT:-60}}; do [[ -f $png ]] && break; sleep 1; done
  sleep 6; kill -TERM $pid 2>/dev/null; for i in {1..15}; do kill -0 $pid 2>/dev/null || break; sleep 1; done
}
fresh rl; rm -rf $root/sup-rl $root/cc-rl; mkdir -p $root/sup-rl $root/cc-rl
relaunch rl-1280 1280x800 "$open,split:page.html,wait:3,split-report,wait:6"
expect "relaunch: at 1280 the sidebar folds" $out/rl-1280.log "sidebar folded by the split: true"
relaunch rl-1810 1810x1000 "wait:5,split-report"
expect "relaunch at 1810: the split comes back unfolded" $out/rl-1810.log "folded: false"
expect "relaunch at 1810: with the sidebar" $out/rl-1810.log "sidebar folded by the split: false"

# split-themes: the same split in Dark and Classic (Light is the runs above)
for theme in dark classic; do
  fresh theme-$theme
  APPEARANCE=$theme run theme-$theme 1440x900 "$open,split:page.html,wait:3,split-report"
  expect "$theme: a split is made" $out/theme-$theme.log "active: left"
done

echo "$((total-fails))/$total passed"
exit $((fails > 0))
