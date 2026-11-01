#!/bin/zsh
# Split view, slice 1 (DL-275 to DL-278): live background runs on a scratch workspace with an
# isolated support folder and config. No Claude turn runs. One launch per case: it captures the
# window and prints the split's report, which is asserted. The captures are what gets compared with
# docs/design/split-view-handoff/screens/ (docs/design/build-handoff/tools/compare.sh).
#   scripts/check-split.sh [out-dir]
set -u
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
  env -u DUO_SUPPORT_DIR DUO_SUPPORT_DIR=$root/sup-$1 CLAUDE_CONFIG_DIR=$root/cc-$1 ANTHROPIC_MODEL=claude-haiku-5-5 DUO_APPEARANCE=${APPEARANCE:-light} \
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
for size in 1440x900 1280x800; do
  fresh m$size
  run m$size $size "$open,split:page.html,wait:3,split-report"
  expect "$size: a split is made" $out/m$size.log "active: left"
  expect "$size: the sidebar folded to its rail" $out/m$size.log "sidebar folded by the split: true"
  expect "$size: not folded to one side" $out/m$size.log "folded: false"
done
fresh html
run html 1440x900 "$open,split:page.html,wait:3,split-report"
expect "html: a page beside its source" $out/html.log "right: Page"
fresh swap
run swap 1440x900 "$open,split:page.html,wait:2,split-swap,split-focus:left,wait:1,split-report"
expect "swap: the page is on the left" $out/swap.log "left: Page"
fresh peek
run peek 1440x900 "$open,split:page.html,wait:2,sidebar-peek:on,wait:2,split-report"
fresh narrow
run narrow 1280x800 "$open,split:page.html,wait:2,right-width:600,wait:2,split-report"
expect "narrow: under two sides the split folds" $out/narrow.log "folded: true"
fresh unfold
run unfold 1280x800 "$open,split:page.html,wait:2,right-width:600,wait:2,split-unfold,wait:2,split-report"
expect "unfold: the console narrows for two sides" $out/unfold.log "folded: false"
fresh close
run close 1440x900 "$open,split:page.html,wait:2,split-close,wait:2,split-report"
expect "close: the split is gone" $out/close.log "no split view showing"

# split-themes: the same split in Dark and Classic (Light is the runs above)
for theme in dark classic; do
  fresh theme-$theme
  APPEARANCE=$theme run theme-$theme 1440x900 "$open,split:page.html,wait:3,split-report"
  expect "$theme: a split is made" $out/theme-$theme.log "active: left"
done

echo "$((total-fails))/$total passed"
exit $((fails > 0))
