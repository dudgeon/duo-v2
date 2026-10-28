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
echo "$((total-fails)) of $total passed (captures and logs in $out)"
exit $((fails > 0))
