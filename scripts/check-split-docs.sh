#!/bin/zsh
# Split view slice 2 (DL-278, split-docs): two documents side by side, both editable, captured in
# Light, Dark and Classic for comparison with docs/design/split-view-handoff/screens/split-docs.html.
# Background runs (F-227) on a scratch workspace with an isolated support folder and config; the
# board's illustrative files (interview notes beside the synthesis). Home starts its session on Haiku.
#   scripts/check-split-docs.sh [out-dir] [appearances…]   (default: light dark classic)
set -u
cd "${0:A:h}/.."
out=${1:-build/split-docs}; mkdir -p "$out"; out=${out:A}
shift $(( $# > 0 ? 1 : 0 ))
if (( $# )); then looks=($@); else looks=(light dark classic); fi
root=${DUO_SPLIT_ROOT:-/private/tmp/svs2-$$}   # fresh per run: a support folder keeps read-only mod files
for look in $looks; do
  ws=$root/ws-$look; rm -rf $ws $root/cc-$look $root/sup-$look
  mkdir -p $ws/Home $ws/research/buyer-interviews $root/cc-$look $root/sup-$look
  printf -- '---\ngoal: "Home"\n---\n\n# Home\n' > $ws/Home/HOME.md
  printf -- '---\ngoal: "Synthesis"\n---\n\n# buyer-interviews\n' > $ws/research/buyer-interviews/PROJECT.md
  printf '# Interview 4: Dana, ops lead\n\n“We stopped trusting the dashboard after the March outage.” Rebuilds the weekly report by hand, about 3 hours.\n' > $ws/research/buyer-interviews/interview-notes.md
  printf '# What we heard\n\nTrust broke at the March outage; three of six rebuild reports by hand.\n' > $ws/research/buyer-interviews/synthesis.md
  then=${DUO_SPLIT_THEN:-"open:buyer-interviews,open-file:$ws/research/buyer-interviews/interview-notes.md,wait:2,verb:split interview-notes.md --with synthesis.md,wait:2,right-width:944,wait:2,verb:split"}   # 944: the right pane DL-276 plans at 1440 (slice 1 makes it; see the report)
  env -u DUO_SUPPORT_DIR DUO_EXTRA_ENV="DUO_SUPPORT_DIR=$root/sup-$look CLAUDE_CONFIG_DIR=$root/cc-$look DUO_APPEARANCE=$look" DUO_TIMEOUT=${DUO_TIMEOUT:-90} \
    scripts/run-live.sh $ws "$out/split-docs-$look.png" "$then" "$out/split-docs-$look.log"
  grep -a "^verb split" "$out/split-docs-$look.log" | sed 's/^/  /'
done
