#!/bin/zsh
# Review in Markdown, the convention paragraph with a real Haiku turn (DL-236 7, research §3.3): a fresh `claude -p`
# on Haiku 5.5, given Review.convention as Duo's context hook gives it, is asked to "deal with the review" in a document
# with pending suggestions and a question. It must keep every suggestion pending, answer in the thread with a
# correctly formed reply, and never delete anyone's comment. Uses the user's own CLI login (an approved real-login test);
# the document is a scratch file, nothing of Duo's or the user's is touched.
#   scripts/check-review-claude.sh [out-dir]
set -u
cd "${0:A:h:h}"
out=${1:-build/review-claude}; mkdir -p $out; out=${out:A}
work=$(mktemp -d /tmp/rvclaude.XXXX)
doc=$work/offline.md
print -rn -- $'# Offline mode\n\nThe sync engine retries every {~~30~>10~~}{>>@geoff 2026-10-27 #s1<<} seconds.\n\nWe store nothing in the cloud except {==crash reports==}{>>@geoff 2026-10-27 #c1: Is this true for crash reports?<<}{>>@sam 2026-10-27 #c1.1: I think yes, they are sent once a day.<<}\n\nThe first launch needs a network. {==First launch==}{>>@geoff 2026-10-28 #c2: @claude can you say in one line why?<<}\n' > $doc
cp $doc $out/before.md

# The paragraph, read from the source so the check can't drift from what Duo says.
para=$(python3 -I - <<'EOF'
import re
src = open("Sources/DuoControl/ReviewMarkup.swift").read()
print(re.search(r'public static let convention = """\n(.*?)\n    """', src, re.S).group(1).strip())
EOF
)
prompt="I've reviewed the doc at $doc. Please go through the review and deal with it, then save the file."
(cd $work && ANTHROPIC_MODEL=claude-haiku-5-5 claude -p "$prompt" --model claude-haiku-5-5 --append-system-prompt "$para" \
    --permission-mode acceptEdits --allowedTools "Read Edit Write" > $out/claude.txt 2>&1)
cp $doc $out/after.md

fails=0 total=0
expect() { total=$((total+1)); local got=0; grep -qF -- "$3" "$out/after.md" && got=1
  if [[ $2 == has && $got == 1 ]] || [[ $2 == lacks && $got == 0 ]]; then echo "ok   $1"; else fails=$((fails+1)); echo "FAIL $1 (after.md should $2 '$3')"; fi }
expect "the suggestion stays pending" has "{~~30~>10~~}"
expect "Geoff's signature is kept" has "@geoff 2026-10-27 #s1"
expect "Geoff's comment is kept" has "Is this true for crash reports?"
expect "Sam's reply is kept" has "I think yes, they are sent once a day."
expect "the highlight is kept" has "{==crash reports==}"
expect "nothing is closed" lacks "closed<<}"
total=$((total+1))
if grep -qE '\{>>@claude [0-9]{4}-[0-9]{2}-[0-9]{2} #c2\.[0-9]+:' $out/after.md; then echo "ok   Claude replied in the thread it was asked in, signed and numbered"; else fails=$((fails+1)); echo "FAIL no well-formed @claude reply in thread c2"; fi
echo "$((total-fails)) of $total passed (before, after and Claude's words in $out)"
rm -rf $work
exit $((fails > 0))
