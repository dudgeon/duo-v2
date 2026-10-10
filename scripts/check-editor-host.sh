#!/bin/zsh
# The editor host's document lifecycle (DL-167 step 5, F-44, F-52, F-263): background runs on a
# scratch workspace with an isolated support folder and config, one app launch per case, and the
# bytes on disk asserted after each: open and type, an outside write merged, a fast switch with an
# outside write in flight, a round trip A to B to A, a conflict resolved both ways, and a quit
# right after typing. Haiku is never called: no Claude turn runs (Home starts none in these cases).
#   scripts/check-editor-host.sh [out-dir]
set -u
cd "${0:A:h}/.."
out=${1:-build/editor-host}; mkdir -p "$out"; out=${out:A}
root=/private/tmp/pcf-host-1
fails=0 total=0

# fresh <name>: a workspace with A.md and B.md in the garden project; prints nothing, sets $ws and $A, $B
fresh() {
  ws=$root/ws-$1; rm -rf $ws $root/cc-$1 $root/sup-$1
  mkdir -p $ws/Home $ws/work/garden $root/cc-$1 $root/sup-$1
  printf -- '---\ngoal: "Home"\n---\n\n# Home\n' > $ws/Home/HOME.md
  printf -- '---\ngoal: "Plan"\n---\n\n# garden\n' > $ws/work/garden/PROJECT.md
  A=$ws/work/garden/A.md; B=$ws/work/garden/B.md
  printf '# A\n\nalpha\n\nmiddle\n\ntick 0\n' > $A
  printf '# B\n\nbravo\n' > $B
}
# run <name> <actions>: one background launch (run-live.sh never hangs)
run() {
  env -u DUO_SUPPORT_DIR DUO_EXTRA_ENV="DUO_SUPPORT_DIR=$root/sup-$1 CLAUDE_CONFIG_DIR=$root/cc-$1" DUO_TIMEOUT=${DUO_TIMEOUT:-60} \
    scripts/run-live.sh $ws "$out/$1.png" "$2" "$out/$1.log" >/dev/null
  sleep 2
}
# expect <label> <file> <has|lacks> <text>
expect() {
  total=$((total+1))
  local got=0; grep -qF -- "$4" "$2" && got=1
  if [[ $3 == has && $got == 1 ]] || [[ $3 == lacks && $got == 0 ]]; then echo "ok   $1"
  else fails=$((fails+1)); echo "FAIL $1: ${2:t} should $3 '$4'"; sed 's/^/       | /' "$2"; fi
}

open="open:garden,open-file:"

# 1. open, type, autosave
fresh type
run type "${open}$A,wait:2,user-type:alpha=>alpha EDITED,wait:3,editor-state"
expect "type: the typing is saved" $A has "alpha EDITED"
expect "type: nothing else changed" $A has "tick 0"
expect "type: B untouched" $B has "bravo"

# 2. an outside write while the document is open and unsaved: merged by line, both on disk
fresh outside
run outside "${open}$A,wait:2,user-type:alpha=>alpha EDITED,disk-write:tick 0=>tick 1,wait:4,editor-state"
expect "outside: the typing is saved" $A has "alpha EDITED"
expect "outside: the outside write is kept" $A has "tick 1"

# 3. fast switch: an outside write lands, the user leaves within the watcher's 150 ms (F-263)
fresh switch
run switch "${open}$A,wait:2,user-type:alpha=>alpha EDITED,disk-write:tick 0=>tick 1,+open-file:$B,wait:3,editor-state"
expect "switch: A has the typing" $A has "alpha EDITED"
expect "switch: A has the outside write" $A has "tick 1"
expect "switch: B untouched" $B has "bravo"
expect "switch: B has nothing of A" $B lacks "alpha"

# 4. A to B to A at once: the late replies of the first A must not decide for the second (generation)
fresh roundtrip
run roundtrip "${open}$A,wait:2,user-type:alpha=>alpha EDITED,disk-write:tick 0=>tick 1,+open-file:$B,+open-file:$A,wait:4,editor-state"
expect "roundtrip: A has the typing" $A has "alpha EDITED"
expect "roundtrip: A has the outside write" $A has "tick 1"
expect "roundtrip: B untouched" $B has "bravo"

# 5. a conflict: the same line typed and rewritten outside. Nothing is saved over the outside version.
fresh conflict-mine
run conflict-mine "${open}$A,wait:2,user-type:alpha=>alpha MINE,disk-write:alpha=>alpha THEIRS,wait:4,editor-state,resolve:mine,wait:3,editor-state"
expect "conflict/mine: Keep Mine saves my line" $A has "alpha MINE"
expect "conflict/mine: and not theirs" $A lacks "THEIRS"
fresh conflict-theirs
run conflict-theirs "${open}$A,wait:2,user-type:alpha=>alpha MINE,disk-write:alpha=>alpha THEIRS,wait:4,resolve:theirs,wait:3,editor-state"
expect "conflict/theirs: Use Theirs leaves their line" $A has "alpha THEIRS"
expect "conflict/theirs: and not mine" $A lacks "MINE"
fresh conflict-wait
run conflict-wait "${open}$A,wait:2,user-type:alpha=>alpha MINE,disk-write:alpha=>alpha THEIRS,wait:5,editor-state"
expect "conflict/paused: autosave never overwrites the outside version" $A has "alpha THEIRS"
expect "conflict/paused: nor does it merge the two" $A lacks "MINE"

# 6. quit right after typing: the last word is saved (F-52)
fresh quit
run quit "${open}$A,wait:2,user-type:alpha=>alpha EDITED,quit"
expect "quit: the typing is saved" $A has "alpha EDITED"

# 7. A property edit on an open task note: Swift's writer, applied to the buffer as one plain change
# beside unsaved typing. The saved bytes are exactly what the writer makes of the typed text.
fresh note
T=$ws/work/garden/tasks/t.md; mkdir -p ${T:h}
printf -- '---\ntitle: "T"\nstatus: open\nsessions: []\n---\n\n# T\n\nalpha\n' > $T
run note "open:garden,open-file:$T,wait:2,user-type:alpha=>alpha EDITED,note-edit:status=done@2026-10-09,note-edit:session=[Draft](duo2://session/bbbbbbbb-1111-4222-8333-444444444444),note-edit:addref=[Plan](../docs/plan.md),wait:4,note-edit:rmref=../docs/plan.md,wait:3,editor-state"
printf -- '---\ntitle: "T"\nstatus: done\nsessions:\n  - "[Draft](duo2://session/bbbbbbbb-1111-4222-8333-444444444444)"\ncompleted: 2026-10-09\n---\n\n# T\n\nalpha EDITED\n' > $out/note-expected.md
total=$((total+1))
if cmp -s $T $out/note-expected.md; then echo "ok   note: the open note's bytes are the writer's, with the typing kept"
else fails=$((fails+1)); echo "FAIL note: bytes differ from the writer's"; diff $T $out/note-expected.md | sed 's/^/       | /'; fi

# 8. The page is handed the registry's chords at document start (DL-167 step 6)
fresh chords
run chords "${open}$A,wait:2,editor-js:return JSON.stringify(window.__duoChords)"
total=$((total+1))
if grep -q 'Mod-s' $out/chords.log && grep -q 'Shift-Mod-n' $out/chords.log; then echo "ok   chords: the page has window.__duoChords"
else fails=$((fails+1)); echo "FAIL chords: no window.__duoChords in the page"; grep editor-js $out/chords.log | sed 's/^/       | /'; fi

# 9. One editor state per document (DL-167 step 3): leave A for B and come back; the caret, the undo
# history are still there, and the page held A's state while B showed.
fresh held
run held "${open}$A,wait:2,user-type:alpha=>alpha EDITED,editor-js:duo.select(7)⸴1,wait:1,+open-file:$B,wait:3,editor-js:return JSON.stringify({held:duo.heldIds()⸴text:duo.text()}),+open-file:$A,wait:3,editor-js:return JSON.stringify({caret:duo.caret()⸴depth:duo.undoDepth()⸴held:duo.heldIds()}),editor-js:duo.undo()⸴1,wait:1,editor-js:return duo.text(),wait:2"
expect "held: the page held A's state while B showed" $out/held.log has "garden/A.md"
expect "held: back in A, the caret is where it was" $out/held.log has '"caret":7'
expect "held: back in A, the undo history is there" $out/held.log lacks '"depth":0'
expect "held: Undo after coming back takes the typing out" $out/held.log has "editor-js: # A"

# 10. Scroll position across A to B to A (DL-167 step 3)
fresh scroll
{ print '# A\n'; for i in {1..160}; do print "line $i of a long paragraph that wraps well past a short pane, to make the page tall\n"; done } > $A
run scroll "${open}$A,wait:2,editor-js:const s=document.querySelector('.cm-scroller'); s.scrollTop=1500; return 'scrolled '+s.scrollTop+' vis='+document.visibilityState,wait:1,+open-file:$B,wait:3,+open-file:$A,freeze:3,editor-js:return 'back '+document.querySelector('.cm-scroller').scrollTop"
sc=$(grep -o 'scrolled [0-9]*' $out/scroll.log | head -1 | grep -o '[0-9]*$'); bk=$(grep -o 'back [0-9]*' $out/scroll.log | head -1 | grep -o '[0-9]*$')
total=$((total+1))
if grep -q 'vis=hidden' $out/scroll.log; then
  # A background window is hidden to the page: no animation frames, so CodeMirror never re-measures and
  # a restored scroll cannot land. It is proved in a visible run (DUO_TEST_FOREGROUND=1, Geoff's OK first).
  total=$((total-1)); echo "skip scroll: the page is hidden in a background run (needs DUO_TEST_FOREGROUND=1)"
elif [[ -n $sc && -n $bk && $sc -gt 500 && $((bk - sc)) -ge -2 && $((bk - sc)) -le 2 ]]; then echo "ok   scroll: A is back at $bk (left at $sc)"
else fails=$((fails+1)); echo "FAIL scroll: left at '$sc', back at '$bk'"; grep editor-js $out/scroll.log | sed 's/^/       | /'; fi

# 11. Source mode per document, held across switches: on in A, off in B
fresh source
run source "${open}$A,wait:2,source:on,wait:1,editor-js:return 'A '+duo.source(),+open-file:$B,wait:3,editor-js:return 'B '+duo.source(),+open-file:$A,wait:3,editor-js:return 'A again '+duo.source(),+open-file:$B,wait:3,editor-js:return 'B again '+duo.source()"
expect "source: A is in Source mode when turned on" $out/source.log has "editor-js: A true"
expect "source: B is not" $out/source.log has "editor-js: B false"
expect "source: A is still in Source mode when shown again" $out/source.log has "editor-js: A again true"
expect "source: B is still not" $out/source.log has "editor-js: B again false"

# 12. A tab closed while its held state has unsaved text (a conflict left behind): nothing is lost
fresh closeheld
run closeheld "${open}$A,wait:2,user-type:alpha=>alpha MINE,disk-write:alpha=>alpha THEIRS,wait:4,+open-file:$B,wait:3,close-doc:A.md,wait:2,+open-file:$A,wait:4,editor-js:return 'buffer '+JSON.stringify(duo.text()),doc-status"
expect "closeheld: the file keeps the outside version" $A has "alpha THEIRS"
expect "closeheld: and nothing of mine was written over it" $A lacks "MINE"
expect "closeheld: my text is back in the buffer after closing the tab" $out/closeheld.log has "alpha MINE"
expect "closeheld: still a conflict" $out/closeheld.log has "in conflict"

# 13. A file renamed while its held state has unsaved text: the text follows the new name
fresh renameheld
run renameheld "${open}$A,wait:2,user-type:alpha=>alpha MINE,disk-write:alpha=>alpha THEIRS,wait:4,+open-file:$B,wait:3,rename:A.md=A2.md,wait:2,+open-file:$ws/work/garden/A2.md,wait:4,editor-js:return 'buffer '+JSON.stringify(duo.text()),doc-status"
expect "renameheld: the renamed file has the outside version" $ws/work/garden/A2.md has "alpha THEIRS"
expect "renameheld: and nothing of mine was written over it" $ws/work/garden/A2.md lacks "MINE"
expect "renameheld: my text is in the buffer under the new name" $out/renameheld.log has "alpha MINE"

echo "$((total-fails)) of $total checks passed (logs and captures in $out)"
[[ $fails == 0 ]]
