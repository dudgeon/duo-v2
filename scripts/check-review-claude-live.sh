#!/bin/zsh
# @claude end to end (DL-236 9A, 10A): an isolated Duo hosts a REAL Claude session on Haiku 5.5 with the user's own CLI
# login, in the background. A comment naming @claude is sent to it; its turn is Sent, then Claude is replying, then
# Replied, and the reply lands in the thread through the editor's buffer (the document is open in Duo's editor).
# An approved, routine real-login test: one short Haiku turn. The workspace sits under this checkout's build/ folder
# (a folder Claude already trusts), so nothing in the user's ~/.claude.json is written; the session's transcript
# is filed in ~/.claude/projects as any claude run is.
#   scripts/check-review-claude-live.sh [out-dir]
set -u
cd "${0:A:h:h}"
out=${1:-build/review-claude-live}; mkdir -p $out; out=${out:A}
root=$out/ws-root                       # under build/: trusted by its parents
sup=/private/tmp/pcf-e2e-sup            # short: the control socket's path must stay under 104 characters
chmod -R u+w $sup 2>/dev/null; rm -rf $root $sup; mkdir -p $root/Home $root/work/garden/.claude $sup
printf -- '---\ngoal: "Home"\n---\n\n# Home\n' > $root/Home/HOME.md
printf -- '---\ngoal: "Plan"\n---\n\n# garden\n' > $root/work/garden/PROJECT.md
# The session may run duo2 and edit files here without asking (a prompt would hold the turn): rules in the scratch project only.
print -r -- '{"permissions":{"allow":["Bash(duo2:*)","Read","Edit"]}}' > $root/work/garden/.claude/settings.local.json
A=$root/work/garden/offline.md
print -rn -- $'# Offline mode\n\nThe sync engine retries every {~~30~>10~~}{>>@geoff 2026-10-27 #s1<<} seconds.\n\nThe first launch needs a network. {==First launch==}{>>@geoff 2026-10-28 #c1: @claude in one short line, why does the first launch need a network?<<}\n' > $A
cp $A $out/before.md
rm -f $out/run.log
env -u DUO_SUPPORT_DIR DUO_EXTRA_ENV="DUO_SUPPORT_DIR=$sup" DUO_TIMEOUT=${DUO_TIMEOUT:-300} \
  scripts/run-live.sh $root $out/final.png \
  "open:garden,open-file:$A,wait:3,verb:session new --project garden,wait:35,open-file:$A,wait:3,review-send:c1,wait:2,verb:comment status c1,wait:6,verb:comment status c1,wait:10,verb:comment status c1,wait:20,verb:comment status c1,wait:20,verb:comment status c1,wait:20,verb:doc read,wait:8" $out/run.log
sleep 3
cp $A $out/after.md
fails=0 total=0
expect() { total=$((total+1)); local got=0; grep -qF -- "$3" "$2" && got=1
  if [[ $got == 1 ]]; then echo "ok   $1"; else fails=$((fails+1)); echo "FAIL $1 (${2:t} should have '$3')"; fi }
expect "Sent: the comment was pasted into the live session" $out/run.log "review-send: Sent to"
expect "Claude is replying: the session turned working after the send" $out/run.log "delivery: replying"
expect "Replied: Claude's comment is in the thread" $out/run.log "delivery: replied"
expect "the reply is in the file, signed @claude and numbered #c1.1" $out/after.md "{>>@claude "
expect "the reply is in the thread" $out/after.md "#c1.1:"
expect "the editor's buffer holds the reply (doc read)" $out/run.log "#c1.1:"
expect "the pending suggestion was left pending" $out/after.md "{~~30~>10~~}"
expect "Geoff's comment is untouched" $out/after.md "{>>@geoff 2026-10-28 #c1: @claude in one short line"
echo "$((total-fails)) of $total passed (log, before, after and a capture in $out)"
exit $((fails > 0))
