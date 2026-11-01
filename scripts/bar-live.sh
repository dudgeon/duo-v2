#!/bin/zsh
# One isolated, background Duo run on the formatting bar's fixture workspace (a Home folder holding a project with the
# documents), for live checks (DL-266). Never takes focus (F-227). Prints the run's stderr lines matching a pattern.
#   scripts/bar-live.sh <name> <actions> [grep-pattern] [extra env KEY=value ...]
# Files: /private/tmp/mdb/<name>.png and .log; support folder and Claude config are scratch.
set -u
cd "${0:A:h}/.."
name=$1 acts=$2 pat=${3:-.}; shift 3 2>/dev/null
root=${DUO_BAR_ROOT:-/private/tmp/mdb}; ws=$root/ws
[[ -d $ws/payments/refunds-api-spec ]] || python3 scripts/make-demo-workspace.py $ws >/dev/null
proj=$ws/payments/refunds-api-spec
[[ -f $proj/refunds-api.md ]] || printf '# Refunds API spec\n\n## Thresholds\n\nLimits per path.\n\n| Path | Limit |\n| ---- | ----: |\n| Card | $500 |\n\n## Open questions\n\nWho approves?\n' > $proj/refunds-api.md
[[ -f $proj/notes.md ]] || printf '# Notes\n\n- one\n- two\n\nPlain text.\n' > $proj/notes.md
chmod -R u+w $root/cc-$name $root/sup-$name 2>/dev/null; rm -rf $root/cc-$name $root/sup-$name; mkdir -p $root/cc-$name $root/sup-$name
extra="DUO_SUPPORT_DIR=$root/sup-$name CLAUDE_CONFIG_DIR=$root/cc-$name"
for kv in "$@"; do extra+=" $kv"; done
env -u DUO_SUPPORT_DIR DUO_EXTRA_ENV="$extra" DUO_TIMEOUT=${DUO_TIMEOUT:-60} \
  scripts/run-live.sh $ws $root/$name.png "open:refunds-api-spec,$acts" $root/$name.log >/dev/null
grep -E -- "$pat" $root/$name.log
