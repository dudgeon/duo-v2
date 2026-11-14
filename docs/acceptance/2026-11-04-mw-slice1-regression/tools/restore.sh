#!/bin/zsh
# restore.sh <first-app> <second-app> <outdir>: the upgrade path. Run <first-app> on a fresh fixture, open a project,
# documents and a second session, let it save its restore state, quit (SIGTERM, as ⌘Q); then start <second-app>
# on the SAME support folder and workspace. Records duo2 status/doc tabs/sessions after each launch and the saved
# restore files, plus a control: <first-app> relaunched on its own state (the "before" for a same-version relaunch).
# apps: old | old23 | new
export MWR=/tmp/mwr-restore-$1-$2
. ${0:A:h}/lib.sh
A=$(appfor $1); B=$(appfor $2); OUT=$3
sup_reset; rm -rf $OUT; mkdir -p $OUT; fx_build
snap() {   # snap <stem>
  d2 $1-status status --json; d2 $1-tabs doc tabs; d2 $1-sessions sessions --json; d2 $1-projects projects --json
  d2 $1-split split; d2 $1-tasks tasks --json
}
app_start $A
d2 s0-claude settings claude-path $STUB
d2 s0-open open checkout
d2 s0-doc1 doc open docs/prd.md --project checkout
d2 s0-doc2 doc open docs/research.md
d2 s0-doc3 doc open prototypes/checkout.html
d2 s0-sess session new --project checkout --name "Restore session"
sleep 3
d2 s0-view view home list
d2 s0-view2 view sidebar hide
d2 s0-open2 open checkout
d2 s0-doc4 doc open docs/windows-notes.md
snap first
sleep 3
app_stop
cp -R $SUP $OUT/support-after-first
find $SUP -name 'state.json' -o -name 'restore*' | head > $OUT/restore-files.txt
# second app on the same state
app_start $B
snap second
d2 second-window window list
sleep 2
CAP_ERR=/dev/null
app_stop
cp -R $SUP $OUT/support-after-second
# third launch: the second app again, on the state it saved itself
app_start $B
snap third
d2 third-window window list
app_stop
echo done
