#!/bin/zsh
# Review in Markdown on the editor (DL-236, DL-237): background runs on a scratch workspace with an isolated
# support folder and config, one launch per case, the file's bytes asserted after each, and a capture of the
# window for the board comparison. No Claude turn runs (Home starts none in these cases).
#   scripts/check-review-editor.sh [out-dir]
# Cases: a verb on a file that isn't open (disk); a reply and a close through the open editor (buffer, autosave);
# Suggest Edits on (the frontmatter line, a person's typing and Claude's `doc replace` as signed marks);
# Accept All; a capture of the marks drawn (track-a, margin-suggest).
set -u
cd "${0:A:h}/.."
out=${1:-build/review-editor}; mkdir -p "$out"; out=${out:A}
root=${DUO_HOST_ROOT:-/private/tmp/pcf-review-1}
fails=0 total=0

doc=$'---\ntitle: Offline mode\n---\n\n# Offline mode: one-pager\n\nThe sync engine retries every {~~30~>10~~}{>>@geoff 2026-10-27 #s1<<} seconds{++, and gives up after an hour++}{>>@sam 2026-10-27 #s2: is this true?<<}.\n\nLaunch is {~~planned for~>set for~~}{>>@claude 2026-10-28 #s3: Shorter.<<} early November.\n\nWe store nothing in the cloud except {==crash reports==}{>>@geoff 2026-10-27 #c1: Is this true for crash reports?<<}.\n'

fresh() {
  ws=$root/ws-$1; chmod -R u+w $root/sup-$1 2>/dev/null; rm -rf $ws $root/cc-$1 $root/sup-$1
  mkdir -p $ws/Home $ws/work/garden $root/cc-$1 $root/sup-$1
  printf -- '---\ngoal: "Home"\n---\n\n# Home\n' > $ws/Home/HOME.md
  printf -- '---\ngoal: "Plan"\n---\n\n# garden\n' > $ws/work/garden/PROJECT.md
  A=$ws/work/garden/offline.md
  print -rn -- "$doc" > $A
}
run() {
  env -u DUO_SUPPORT_DIR DUO_EXTRA_ENV="DUO_SUPPORT_DIR=$root/sup-$1 CLAUDE_CONFIG_DIR=$root/cc-$1" DUO_TIMEOUT=${DUO_TIMEOUT:-60} \
    scripts/run-live.sh $ws "$out/$1.png" "$2" "$out/$1.log" >/dev/null
  sleep 2
}
expect() {
  total=$((total+1))
  local got=0; grep -qF -- "$4" "$2" && got=1
  if [[ $3 == has && $got == 1 ]] || [[ $3 == lacks && $got == 0 ]]; then echo "ok   $1"
  else fails=$((fails+1)); echo "FAIL $1: ${2:t} should $3 '$4'"; sed 's/^/       | /' "$2"; fi
}
open="open:garden,open-file:"

# 1. a verb on a file that isn't open writes to disk
fresh disk
run disk "open:garden,wait:2,verb:comment reply --file ${A} c1 I~think~so,wait:1,verb:comment close --file ${A} c1,wait:1,verb:comment add ${A} --at Launch Is~it~ready"
expect "disk: a reply is added" $A has "#c1.1: I think so<<}"
expect "disk: the thread is closed" $A has "#c1.2 closed<<}"
expect "disk: signed as Claude from a session" $A has "{>>@claude "
expect "disk: marks of others untouched" $A has "{~~30~>10~~}{>>@geoff 2026-10-27 #s1<<}"

# 2. the same on an open document: through the buffer, then autosave
fresh open
run open "${open}$A,wait:2,verb:comment reply c1 Agreed,wait:3,verb:comment list ${A}"
expect "open: the reply lands in the file after autosave" $A has "#c1.1: Agreed<<}"
expect "open: the verb listed the thread" $out/open.log has "#c1 [open]"

# 3. accept and reject through the verbs
fresh accept
run accept "${open}$A,wait:2,verb:suggestion accept s1,verb:suggestion reject s3,wait:3"
expect "accept: 30 became 10" $A has "retries every 10 seconds"
expect "accept: the mark went" $A lacks "#s1"
expect "reject: the old text is back" $A has "Launch is planned for early November."

# 4. Suggest Edits on: the frontmatter line, a person's typing and Claude's replacement as signed marks
fresh suggest
run suggest "${open}$A,wait:2,verb:doc review on,wait:2,user-type:early November=>mid November,verb:doc replace nothing~in~the~cloud nothing~at~all~in~the~cloud,wait:3,verb:doc review"
expect "suggest: the switch is in the frontmatter" $A has "suggest-edits: true"
expect "suggest: typing became a signed substitution" $A has "{~~early November~>mid November~~}"
expect "suggest: Claude's doc replace became a signed mark" $A has "{~~nothing in the cloud~>nothing at all in the cloud~~}{>>@claude "
expect "suggest: the switch is reported on" $out/suggest.log has "Suggest Edits is on"

# 4b. Suggest Edits on: a comment-thread verb is a change to the thread, never a suggestion (F-398)
fresh sug-reply
run sug-reply "${open}$A,wait:2,verb:doc review on,wait:2,verb:comment reply c1 Done,wait:1,verb:comment close c1,wait:3"
expect "suggest on: a reply is a thread comment" $A has "#c1.1: Done<<}"
expect "suggest on: a reply is not a tracked insertion" $A lacks "{++{>>"
expect "suggest on: close writes the closing line" $A has "#c1.2 closed<<}"
expect "suggest on: close is not a suggestion either" $A lacks "{++{>>"
fresh sug-delete
run sug-delete "${open}$A,wait:2,verb:doc review on,wait:2,verb:comment delete c1,wait:3"
expect "suggest on: delete takes the thread out" $A lacks "#c1"
expect "suggest on: delete is not a tracked deletion" $A lacks "{--"
fresh sug-accept
run sug-accept "${open}$A,wait:2,verb:doc review on,wait:2,verb:suggestion accept s1,wait:3"
expect "suggest on: accept resolves the mark" $A has "retries every 10 seconds"
expect "suggest on: and is not itself a suggestion" $A lacks "{~~30~>10~~}"
fresh sug-add
run sug-add "${open}$A,wait:2,verb:doc review on,wait:2,verb:comment add ${A} --at Launch Is~it~ready,wait:3"
expect "suggest on: a new comment is a comment" $A has "{==Launch"
expect "suggest on: not wrapped as an insertion" $A lacks "{++{==Launch"

fresh suggest-off
run suggest-off "${open}$A,wait:2,verb:doc review on,wait:2,verb:doc review off,wait:3"
expect "suggest off: the line is gone" $A lacks "suggest-edits"
expect "suggest off: the document is as it was" $A has "title: Offline mode"

# 5. the capture: marks drawn on the board's document
fresh draw
run draw "${open}$A,wait:3"
fresh menu-markup
run menu-markup "${open}$A,wait:3,review-menu:markup,wait:1"
fresh menu-all
run menu-all "${open}$A,wait:3,review-menu:all,wait:1"

# 6. the margin: its operations through the same functions as its buttons, then a capture with it drawn
mdoc=$'---\ntitle: Offline mode\n---\n\n# Offline mode: one-pager\n\nDuo keeps working when the network drops. {==Running sessions keep their place==}{>>@sam 2026-10-27 #c1: "Place" or "scrollback"? New readers won\'t know...<<} new turns {==wait until you\'re back online==}{>>@geoff 2026-10-27 #c2: What does the person see while it waits?<<}{>>@sam 2026-10-27 #c2.1: A spinner?<<}. The sync engine retries every 10 seconds, and {==gives up after an hour==}{>>@sam 2026-10-27 #c3: An hour feels long. Fifteen minutes?<<}, then asks.\n\nWe store nothing in the cloud except {==crash reports==}{>>@geoff 2026-10-27 #c4: Is this true for crash reports?<<}{>>@claude 2026-10-28 #c4.1: It is 10, not 30: the code changed in F-301.<<}.\n\nLaunch is planned for early November.\n'
fresh_m() { fresh $1; print -rn -- "$mdoc" > $A; }
fresh_m mg-close
run mg-close "${open}$A,wait:3,review-op:close=c1,review-op:reply=c4=Agreed,wait:3"
expect "margin: Close and Keep wrote the closing line after the last comment" $A has "#c1.1 closed<<}"
expect "margin: the thread's text and comment are kept" $A has "{==Running sessions keep their place==}"
expect "margin: a reply is signed and numbered after the last comment" $A has "#c4.2: Agreed<<}"
fresh_m mg-delete
run mg-delete "${open}$A,wait:3,review-op:delete=c3,wait:3"
expect "margin: Delete took the markers and the comment" $A lacks "#c3"
expect "margin: and kept the text" $A has "gives up after an hour, then asks."
fresh_m mg-compose
run mg-compose "${open}$A,wait:3,review-comment:Launch~is~planned=>Which~year,wait:3"
expect "margin: a new comment is a highlight and a signed thread" $A has "{==Launch is planned==}{>>@"
expect "margin: with the next free id" $A has "#c5: Which year<<}"
fresh_m mg-draw
run mg-draw "${open}$A,wait:3"
fresh_m mg-active
run mg-active "${open}$A,wait:3,review-active:c2,wait:2"
fresh_m mg-closed
run mg-closed "${open}$A,wait:3,review-op:close=c1,wait:2,review-op:close=c3,wait:2"
fresh_m mg-460
run mg-460 "${open}$A,wait:3,review-width:460,wait:1,review-active:c2,wait:2"
fresh_m mg-360
run mg-360 "${open}$A,wait:3,review-width:360,wait:1,review-active:c2,wait:2"
fresh_m mg-360-closed
run mg-360-closed "${open}$A,wait:3,review-width:360,wait:2"
# 7. @claude: the turn goes through the idle-and-empty-prompt guard; it queues when the session is busy or has a draft;
#    a comment from the file is never sent on its own (C-112). A scripted screen stands in for the session's terminal.
cdoc=$'---\ntitle: Offline mode\n---\n\n# Offline mode\n\nLaunch is {==planned for early November==}{>>@geoff 2026-10-28 #c1: @claude can you tighten this? It reads long.<<}\n'
fresh_c() { fresh $1; print -rn -- "$cdoc" > $A; }
fresh_c cl-sent
run cl-sent "${open}$A,wait:3,verb:session new --project garden,wait:2,review-io:idle,review-send:c1,wait:2,verb:comment status c1"
expect "@claude: a comment from the file is not sent on its own" $out/cl-sent.log lacks "review-typed: <paste>@claude comment in offline.md, line 5"
expect "@claude: Send pastes the turn, with the thread and how to reply" $out/cl-sent.log has "review-typed: <paste>@claude comment in"
expect "@claude: the turn names the anchor text" $out/cl-sent.log has "On: “planned for early November”"
expect "@claude: the turn quotes the comment as data" $out/cl-sent.log has "> @geoff: @claude can you tighten this?"
expect "@claude: the turn says how to answer" $out/cl-sent.log has "duo2 comment reply c1"
expect "@claude: Return is pressed after the paste" $out/cl-sent.log has "review-typed: <Return>"
expect "@claude: status says sent" $out/cl-sent.log has "delivery: sent"
fresh_c cl-busy
run cl-busy "${open}$A,wait:3,verb:session new --project garden,wait:2,review-io:busy,review-send:c1,wait:2,verb:comment status c1"
expect "@claude: a busy session gets nothing typed" $out/cl-busy.log lacks "review-typed:"
expect "@claude: and the comment queues" $out/cl-busy.log has "delivery: queued"
fresh_c cl-draft
run cl-draft "${open}$A,wait:3,verb:session new --project garden,wait:2,review-io:draft,review-send:c1,wait:2,verb:comment status c1"
expect "@claude: a draft in the prompt is never typed into" $out/cl-draft.log lacks "review-typed:"
expect "@claude: the comment waits" $out/cl-draft.log has "delivery: queued"
fresh_c cl-later
run cl-later "${open}$A,wait:3,verb:session new --project garden,wait:2,review-io:busy,review-send:c1,wait:1,review-io:idle,wait:6,verb:comment status c1"
expect "@claude: sent at the next idle with an empty prompt" $out/cl-later.log has "review-typed: <Return>"
fresh_c cl-draw
run cl-draw "${open}$A,wait:3"
fresh_c cl-draw-sent
run cl-draw-sent "${open}$A,wait:3,verb:session new --project garden,wait:2,review-io:idle,review-send:c1,wait:2"
# 7b. @ in the composer (comment-at): the menu opens with Claude first, filters, and Tab/↓/Esc work; a comment chosen
#     from the menu is posted and reaches the stand-in session as an @claude turn.
fresh_c at-open
run at-open "${open}$A,wait:3,review-at:planned~for~early~November=>Please~@cl=>"
expect "@ menu: typing @cl opens the menu with Claude" $out/at-open.log has "menu=claude"
expect "@ menu: the field keeps what was typed" $out/at-open.log has 'field="Please @cl"'
expect "@ menu: it floats, not a part of the card" $out/at-open.log has "popover=true"
fresh at-look
run at-look "${open}$A,wait:3,review-at:early~November=>Please~@cl=>"
expect "@ menu: on a clean margin too" $out/at-look.log has "menu=claude"
fresh_c at-tab
run at-tab "${open}$A,wait:3,review-at:planned~for~early~November=>Please~@=>down+tab"
expect "@ menu: Tab inserts @claude" $out/at-tab.log has 'field="Please @claude " menu=closed'
fresh_c at-esc
run at-esc "${open}$A,wait:3,review-at:planned~for~early~November=>Please~@c=>esc"
expect "@ menu: Esc closes it and leaves the text" $out/at-esc.log has 'field="Please @c" menu=closed'
fresh_c at-none
run at-none "${open}$A,wait:3,review-at:planned~for~early~November=>Please~@zz=>"
expect "@ menu: a name that matches nothing shows no menu" $out/at-none.log has 'menu=closed'
fresh_c at-post
run at-post "${open}$A,wait:3,verb:session new --project garden,wait:2,review-io:idle,review-at:planned~for~early~November=>Please~@cl=>return+post,wait:4,verb:comment status c2"
expect "@ menu: Return inserts, then Post writes the signed @claude comment" $A has "Please @claude<<}"
expect "@ menu: and the turn reaches the session" $out/at-post.log has "review-typed: <paste>@claude comment in"
expect "@ menu: with the comment as data" $out/at-post.log has "Please @claude"
# 8. what the Word converter writes (Q-283): a deletion inside a highlight, a comment over two paragraphs
vdoc=$'---\ntitle: Converted\n---\n\nSome {=={--some old words--}{>>@morgan-editor 2026-09-06 #s2: <<}==}{>>@riley-reviewer 2026-09-06 #c3: Why cut these?<<} here.\n\n{==This paragraph is commented along with the next one.==}\n\n{==It carries the end of the comment.==}{>>@riley-reviewer 2026-09-05 #c5: Both paragraphs need a source.<<}{>>@dana-writer 2026-09-05 #c5.1: Added.<<}\n'
fresh cv-draw; print -rn -- "$vdoc" > $A
run cv-draw "${open}$A,wait:3,review-active:c5,wait:2"
echo "$((total-fails)) of $total passed (captures and logs in $out)"
exit $((fails > 0))
