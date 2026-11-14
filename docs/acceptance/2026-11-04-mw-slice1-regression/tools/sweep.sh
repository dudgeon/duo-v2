#!/bin/zsh
# sweep.sh <old|new> <outdir>: launch that Duo on a fresh isolated fixture, run a fixed sequence of duo2 verbs,
# save each one's stdout, stderr and exit code in <outdir>, then quit. Same sequence for both apps; diff the dirs.
export MWR=/tmp/mwr-$1
. ${0:A:h}/lib.sh
which=$1; OUT=$2
APPP=$(appfor $which)
sup_reset; rm -rf $OUT; mkdir -p $OUT; fx_build
app_start $APPP
d2 settings-claude settings claude-path $STUB
n=0
r() {   # r <name> <duo2 args...>
  n=$((n+1)); local nm=$(printf '%03d-%s' $n $1); shift; d2 $nm "$@"
}
# --- Duo / on screen
r ping ping
r status status --json
r needs-you needs-you --json
r help help
r help-markdown help --markdown
r settings settings
r doctor doctor
r hangs hangs --json
r go-all go all
r status-all status --json
r view-home-list view home list
r view-home-board view home board
r view-sort-name view sort name
r view-sort-recent view sort recent
r view-filter view filter check
r view-filter-clear view filter
r view-sidebar-hide view sidebar hide
r view-sidebar-show view sidebar show
r view-right-hide view right hide
r view-right-show view right show
r view-format-bar view format-bar toggle
r view-format-bar2 view format-bar toggle
r view-hidden-on view hidden on
r view-hidden-off view hidden off
r peek-open peek open
r peek-close peek close
r view-select view select --list
# --- projects & sessions
r projects projects --json
r inventory inventory --json
r migrations migrations
r project-show-checkout project show checkout --json
r project-show-reading project show reading --json
r evidence evidence checkout
r sessions sessions --json
r sessions-checkout sessions --project checkout --json
r tasks tasks --json
r groups groups --json
r idle idle --json
r template-show-project template show project
r template-show-task template show task --project checkout
r template-preview template preview project
r files files --project checkout
r files-hidden files --project checkout --hidden
r files-docs files docs --project checkout
r file-templates file templates
r open-checkout open checkout
r status-checkout status --json
r files-open files
r doc-open doc open docs/prd.md --project checkout
r doc-tabs doc tabs
r doc-read doc read docs/prd.md
r doc-status doc status docs/prd.md
r doc-mode-source doc mode source
r doc-mode-preview doc mode preview
r doc-find doc find the
r doc-prop-list doc prop list
r doc-history doc history docs/prd.md
r doc-insert doc insert "regression line" --line 1
r doc-save doc save
r doc-read-after doc read docs/prd.md
r doc-revert doc revert --all
r doc-open-win doc open docs/windows-notes.md
r doc-open-mixed doc open docs/mixed-endings.md
r doc-open-deck doc open decks/field-trial-review.md
r deck-status deck
r deck-check deck check decks/field-trial-review.md
r deck-templates deck templates
r split-report split
r split-open split docs/research.md
r split-report2 split
r split-focus split focus right
r split-close split close
r doc-open-html doc open prototypes/checkout.html
r doc-tabs2 doc tabs
r view-tab-next view tab next
r view-tab-prev view tab previous
r view-pane-next view pane next
r view-pane-left view pane left
r doc-close-others doc close --others
r doc-close doc close
r comment-add comment add docs/prd.md --at 1 --as regress "regression comment"
r comment-list comment list docs/prd.md
r suggestion-list suggestion list docs/prd.md
r doc-comments doc comments
r task-board task board --project checkout
r task-new task new "Regression task" --project checkout --no-open
r tasks-after tasks --project checkout --json
r task-status task status "Regression task" in-progress --project checkout
r task-rename task rename "Regression task" "Regression task 2" --project checkout
r group-new group new "Regression group" $($D2 sessions --project checkout --json 2>/dev/null | python3 -I -c "import json,sys;d=json.load(sys.stdin);print(' '.join(s['id'] for s in (d if isinstance(d,list) else d.get('sessions',[]))[:1]))")
r groups-after groups --json
r file-new file new --in docs --name regress-note
r file-rename file rename docs/regress-note.md regress-renamed
r file-duplicate file duplicate docs/regress-renamed.md
r file-trash file trash docs/regress-renamed.md
r file-path file path docs/prd.md --relative
r session-new session new --project checkout --name "Regress session"
sleep 3
r sessions-after sessions --project checkout --json
r session-chat session chat --default last
r shell-new shell new
r search search billing --json
r search-status search-status
r deck-export-show deck export show
r send-text send text "hello" --to none
r voice-status voice status
r voice-start voice start
r voice-stop voice stop
r selection selection
r settings-notify settings notify off
r settings-appearance-dark settings appearance dark
r settings-appearance-classic settings appearance classic
r settings-appearance-system settings appearance system
r settings-explainers settings explainers reset
r go-home go home
r status-home status --json
r project-archive project archive reading
r project-unarchive project unarchive reading
r undo undo
r browser-sites browser sites
r browser-tabs browser tabs
r unknown-verb nonsense-verb
r bad-arg open no-such-project
r window-list window list
r window-colour window colour
sleep 1
app_stop
echo done $n verbs
