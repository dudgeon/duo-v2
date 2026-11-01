#!/bin/zsh
# The Markdown formatting bar (DL-266): background captures of each state in Light, Dark and Classic, on a scratch
# workspace with an isolated support folder and config. No Claude turn runs; nothing takes focus (F-227).
#   scripts/check-format-bar.sh [out-dir]       → <out>/<state>-<appearance>.png, each compared by eye with
#   docs/design/markdown-toolbar-handoff/screens/png/bar@2x.png (region by region)
# States: rest (not editing), top (editing, at the top), scrolled, table, table-narrow (360), listening, nomic, review.
set -u
cd "${0:A:h}/.."
out=${1:-build/format-bar}; mkdir -p "$out"; out=${out:A}
root=${DUO_BAR_ROOT:-/private/tmp/mdb}
ws=$root/ws
[[ -d $ws/payments/refunds-api-spec ]] || python3 scripts/make-demo-workspace.py $ws >/dev/null
doc=$ws/payments/refunds-api-spec/refunds-api.md
[[ -f $doc ]] || cat > $doc <<'EOF'
# Refunds API spec

## Thresholds

Limits per path, as finance confirmed on Oct 3.

| Path | Limit | Approvers |
| ----- | ----- | --------: |
| Card | $500 | 2 |
| Async | $250 | 1 |

## Open questions

Who approves async refunds over $1,000? Finance signs off above two thousand.

Does a partial refund reset the limit?
EOF
open="open:refunds-api-spec,open-file:$doc,wait:2"
# run <state> <appearance> <width> <actions>
run() {
  local n="$1-$2"
  rm -rf $root/cc-$n $root/sup-$n; mkdir -p $root/cc-$n $root/sup-$n
  env -u DUO_SUPPORT_DIR DUO_APPEARANCE=$2 DUO_EXTRA_ENV="DUO_SUPPORT_DIR=$root/sup-$n CLAUDE_CONFIG_DIR=$root/cc-$n DUO_APPEARANCE=$2" DUO_TIMEOUT=${DUO_TIMEOUT:-60} \
    scripts/run-live.sh $ws "$out/$n.png" "$open,right-width:$3,$4" "$out/$n.log" >/dev/null
  sleep 1
  [[ -f $out/$n.png ]] && echo "captured $n" || echo "FAILED $n"
}
for a in light dark classic; do
  run rest $a 460 "wait:1"
  run top $a 460 "bar-focus,bar-select:30,wait:2"
  run table $a 460 "bar-focus,bar-select:120,wait:2"
  run table-narrow $a 360 "bar-focus,bar-select:120,wait:2"
done
run listening dark 460 "bar-focus,bar-select:30,bar-mic,bar-listen,wait:2"
run nomic classic 460 "bar-focus,bar-select:30,bar-nomic,wait:2"
