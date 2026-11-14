#!/bin/zsh
# The editor's text column follows its pane when only the pane changes width (F-692): a note with review comments
# (the margin takes 184 of the column from 420 wide, 24 under it) is opened, then the right pane's divider moves
# narrow, wide, narrow, wide; after each move the editor page is measured. Every long line must be the pane's width
# less the margin's share (inline marginRight) and the content's 2 × 28 padding. Before the fix a note kept the margin
# of its first layout: 119 wide in a 359 pane. An isolated run on a scratch workspace; no Claude turn runs.
#   scripts/check-editor-widen.sh [out-dir]       DUO_APP=<Duo.app> to check another build (default build/Duo.app)
# A window that isn't shown gets no resize notifications from WebKit, so set DUO_TEST_FOREGROUND=1 (Geoff's OK first) to prove it.
set -u
cd "${0:A:h}/.."
out=${1:-build/editor-widen}; mkdir -p $out; out=${out:A}; rm -f $out/widen.log
root=$(mktemp -d /private/tmp/pcf-widen-XXXXXX)   # fresh each run: the app leaves read-only folders in its support dir
mkdir -p $root/ws/Home $root/ws/work/garden $root/cc $root/sup
printf -- '---\ngoal: "Home"\n---\n\n# Home\n' > $root/ws/Home/HOME.md
printf -- '---\ngoal: "Plan"\n---\n\n# garden\n' > $root/ws/work/garden/PROJECT.md
A=$root/ws/work/garden/A.md
P="This is a long paragraph of ordinary prose that should wrap to whatever width the pane currently offers and keep doing so when the pane is widened or narrowed again, word after word after word."
printf -- "---\ntype: task\ntitle: T\nstatus: open\nreferences:\n  - [docs](../docs/design/)\n---\n\n# A\n\n$P It is {==cheap enough==}{>>@geoff 2026-10-27 #c1: really?<<} and goes on.\n\n- $P\n\n> $P\n\n| a | b |\n|---|---|\n| one | two |\n\n$P\n" > $A
# ⸴ stands for a comma inside a script (--then splits on commas)
M="editor-js:var out=[...document.querySelectorAll('.cm-line')].filter(l=>l.textContent.length>60).map(l=>Math.round(l.getBoundingClientRect().width));return JSON.stringify({vw:innerWidth⸴mr:document.querySelector('.cm-content').style.marginRight⸴w:out})"
then="open:garden,open-file:$A,wait:2,right-width:300,wait:2,$M,right-width:800,wait:2,$M,right-width:300,wait:2,$M,right-width:800,wait:2,$M,wait:1"
DUO_AUTOCONFIRM=1 DUO_TIMEOUT=70 DUO_RUN_SUPPORT=$root/sup DUO_CLAUDE_CONFIG_DIR=$root/cc \
  DUO_APP=${DUO_APP:-build/Duo.app} scripts/run-live.sh $root/ws $out/widen.png "$then" $out/widen.log > /dev/null
sleep 2
fails=0 n=0
while IFS= read -r line; do
  n=$((n+1))
  json=${line#editor-js: }
  vw=$(print -r -- $json | sed -E 's/.*"vw":([0-9]+).*/\1/')
  mr=$(print -r -- $json | sed -E 's/.*"mr":"([0-9]*)px".*/\1/')
  ws=$(print -r -- $json | sed -E 's/.*"w":\[([0-9,]*)\].*/\1/')
  want_mr=24; (( vw >= 420 )) && want_mr=184
  want=$(( vw - want_mr - 56 ))
  bad=0; [[ $mr == $want_mr ]] || bad=1
  for w in ${(s:,:)ws}; do (( w == want )) || bad=1; done
  if (( bad )); then fails=$((fails+1)); echo "FAIL pane ${vw}: margin ${mr}px (want ${want_mr}), lines [$ws] (want ${want})"; else echo "ok   pane ${vw}: margin ${mr}px, lines ${want}"; fi
done < <(grep '^editor-js:' $out/widen.log)
(( n == 4 )) || { fails=$((fails+1)); echo "FAIL expected 4 measurements, got $n (see $out/widen.log)"; }
echo "editor widen: $((fails == 0 ? 4 : 0)) of 4 ok (capture $out/widen.png)"
exit $(( fails > 0 ))
