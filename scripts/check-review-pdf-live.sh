#!/bin/zsh
# @claude end to end on a PDF (DL-335): an isolated Duo hosts a REAL Claude session on Haiku 5.5 with the user's own CLI
# login, in the background. A comment naming @claude is appended to the PDF as a highlight, sent to the session with
# `duo2 comment send`, and Claude's reply (`duo2 comment reply … --file`) is read back from the PDF's annotations (/IRT).
# An approved, routine real-login test: one short Haiku turn. Same set-up as check-review-office-live.sh.
#   scripts/check-review-pdf-live.sh [out-dir]
set -u
export DUO_ISOLATED=1   # every duo2 here reaches only the test instance; refuses, never the user's Duo (F-529)
cd "${0:A:h:h}"
out=${1:-build/review-pdf-live}; mkdir -p $out; out=${out:A}
root=$out/ws-root                       # under build/: trusted by its parents
sup=/private/tmp/pcf-pdf-sup            # short: the control socket's path must stay under 104 characters
chmod -R u+w $sup 2>/dev/null; rm -rf $root $sup; mkdir -p $root/Home $root/work/pdfgarden/.claude $sup
printf -- '---\ngoal: "Home"\n---\n\n# Home\n' > $root/Home/HOME.md
printf -- '---\ngoal: "Plan"\n---\n\n# pdfgarden\n' > $root/work/pdfgarden/PROJECT.md
print -r -- '{"permissions":{"allow":["Bash(duo2:*)","Read","Edit"]}}' > $root/work/pdfgarden/.claude/settings.local.json
F=$root/work/pdfgarden/Paper.pdf
cp Fixtures/pdf/quartz-mono.pdf $F
cp $F $out/original.pdf
rm -f $out/run.log
# Commas separate actions, so none appear in the verbs' words; ~ stands for a space.
acts="open:pdfgarden,open-file:$F,wait:10,verb:session new --project pdfgarden,wait:35"
acts+=",verb:comment add $F --at walrus~study @claude~in~one~short~line:~what~animal~is~studied? --as geoff-q"
acts+=",verb:comment send --all --file $F,wait:6,verb:comment status c1 --file $F,wait:20,verb:comment status c1 --file $F,wait:25,verb:comment status c1 --file $F,wait:20,verb:comment list $F,wait:3"
env -u DUO_SUPPORT_DIR DUO_CLAUDE_CONFIG_DIR=${DUO_CLAUDE_CONFIG_DIR:-$HOME/.claude} DUO_EXTRA_ENV="DUO_SUPPORT_DIR=$sup" DUO_TIMEOUT=${DUO_TIMEOUT:-300} \
  scripts/run-live.sh $root $out/final.png "$acts" $out/run.log
sleep 3
fails=0 total=0
expect() { total=$((total+1)); local got=0; grep -qF -- "$3" "$2" && got=1
  if [[ $got == 1 ]]; then echo "ok   $1"; else fails=$((fails+1)); echo "FAIL $1 (${2:t} should have '$3')"; fi }
expect "the comment was appended to the PDF" $out/run.log "Commented on page 1 as c1."
expect "it was sent to the live session" $out/run.log "#c1: Sent to"
expect "Claude's reply is in the PDF's thread" $out/run.log "↳ #c1."
# The original bytes are still the start of the file (an incremental update), and Claude's reply is an /IRT annotation.
total=$((total+1)); o=$(stat -f%z $out/original.pdf)
if head -c $o $F | cmp -s - $out/original.pdf; then echo "ok   the original bytes are untouched"; else fails=$((fails+1)); echo "FAIL the original bytes changed"; fi
total=$((total+1))
if LC_ALL=C grep -a -q "/IRT" $F && LC_ALL=C grep -a -q "(Claude)\|(claude)" $F; then echo "ok   the reply is an /IRT annotation by Claude"; else fails=$((fails+1)); echo "FAIL no /IRT reply by Claude in the file"; fi
cp $F $out/after.pdf
echo "$((total-fails)) of $total passed (log, the PDF before and after, and a capture in $out)"
exit $((fails > 0))
