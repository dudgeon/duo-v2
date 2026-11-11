#!/bin/zsh
# @claude end to end on a Word and a PowerPoint file (DL-331): an isolated Duo hosts a REAL Claude session on Haiku 5.5 with
# the user's own CLI login, in the background. A comment naming @claude is written into the .docx / .pptx, sent to the session
# with `duo2 comment send`, and Claude's reply (`duo2 comment reply … --file`) is read back from the file's comment parts.
# An approved, routine real-login test: two short Haiku turns (one per file). Same set-up as check-review-claude-live.sh.
#   scripts/check-review-office-live.sh [out-dir]
set -u
export DUO_ISOLATED=1   # every duo2 here reaches only the test instance; refuses, never the user's Duo (F-529)
cd "${0:A:h:h}"
out=${1:-build/review-office-live}; mkdir -p $out; out=${out:A}
root=$out/ws-root                       # under build/: trusted by its parents
sup=/private/tmp/pcf-oe-sup             # short: the control socket's path must stay under 104 characters
chmod -R u+w $sup 2>/dev/null; rm -rf $root $sup; mkdir -p $root/Home $root/work/garden/.claude $sup
printf -- '---\ngoal: "Home"\n---\n\n# Home\n' > $root/Home/HOME.md
printf -- '---\ngoal: "Plan"\n---\n\n# garden\n' > $root/work/garden/PROJECT.md
print -r -- '{"permissions":{"allow":["Bash(duo2:*)","Read","Edit"]}}' > $root/work/garden/.claude/settings.local.json
D=$root/work/garden/Review.docx; P=$root/work/garden/Deck.pptx
cp "docs/design/docx-viewer-handoff/fixture/markup/Word markup.docx" $D
cp docs/design/duo-decks-study/samples/import/grower-update.pptx $P
rm -f $out/run.log
# Commas separate actions, so none appear in the verbs' words; ~ stands for a space.
acts="open:garden,open-file:$D,wait:10,verb:session new --project garden,wait:35"
# Post goes through the margin's own path (DL-337): select, Add Comment (⌥⌘M), type, Post. An @claude comment is sent as it is posted.
acts+=",office-select:forty,wait:1,office-compose,wait:2,office-type:@claude~in~one~short~line:~is~forty~right?,wait:1,office-post:@claude~in~one~short~line:~is~forty~right?"
acts+=",wait:6,verb:comment status c9 --file $D,wait:20,verb:comment status c9 --file $D,wait:25,verb:comment status c9 --file $D,wait:20,verb:comment list $D"
acts+=",open-file:$P,wait:8,office-compose,wait:2,office-post:@claude~in~one~short~line:~what~is~this~slide~for?"
acts+=",wait:6,verb:comment status s2c1 --file $P,wait:25,verb:comment status s2c1 --file $P,wait:25,verb:comment status s2c1 --file $P,wait:20,verb:comment list $P,wait:3"
env -u DUO_SUPPORT_DIR DUO_CLAUDE_CONFIG_DIR=${DUO_CLAUDE_CONFIG_DIR:-$HOME/.claude} DUO_EXTRA_ENV="DUO_SUPPORT_DIR=$sup" DUO_TIMEOUT=${DUO_TIMEOUT:-400} \
  scripts/run-live.sh $root $out/final.png "$acts" $out/run.log
sleep 3
fails=0 total=0
expect() { total=$((total+1)); local got=0; grep -qF -- "$3" "$2" && got=1
  if [[ $got == 1 ]]; then echo "ok   $1"; else fails=$((fails+1)); echo "FAIL $1 (${2:t} should have '$3')"; fi }
expect "Word: Post wrote the comment into the file" $out/run.log "office-post: c9"
expect "Word: it was sent to the live session" $out/run.log "delivery: sent"
expect "Word: Claude's reply is in the file's thread" $out/run.log "↳ #c9.1 @claude"
expect "PowerPoint: Post wrote the comment into the file" $out/run.log "office-post: s2c1"
expect "PowerPoint: it was sent to the live session" $out/run.log "delivery: sent"
expect "PowerPoint: Claude's reply is in the file's thread" $out/run.log "↳ #s2c1.1 @claude"
python3 -I - "$D" "$P" > $out/parts.txt <<'PY'
import sys, zipfile, re
d = zipfile.ZipFile(sys.argv[1]).read("word/comments.xml").decode()
print("docx comment authors:", re.findall(r'w:author="([^"]+)"', d))
z = zipfile.ZipFile(sys.argv[2])
for n in z.namelist():
    if "modernComment" in n: print(n, re.findall(r"<a:t>(.*?)</a:t>", z.read(n).decode()))
PY
cat $out/parts.txt
echo "$((total-fails)) of $total passed (log, parts and a capture in $out)"
exit $((fails > 0))
