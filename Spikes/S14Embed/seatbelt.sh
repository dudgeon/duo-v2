#!/bin/zsh
# S14 under Seatbelt: no network, writes only in a work folder (as Claude's sandbox), for each
# compute unit. Reports success, timing, and any sandbox denials from the kernel log.
set -u
here=${0:A:h}
work=$(mktemp -d); mkdir -p "$work/tmp"
vocab=$here/../S13CoreML/hf/bge-small/vocab.txt
marker=$work/.marker; touch $marker; sleep 1
for m in fp32 fp16; do for cu in cpu gpu ane all; do
  start=$(date "+%Y-%m-%d %H:%M:%S")
  out=$(cd $work && TMPDIR=$work/tmp sandbox-exec -p "(version 1)
(allow default)
(deny network*)
(deny file-write* (require-not (subpath \"$work\")))
(allow file-write* (literal \"/dev/null\") (literal \"/dev/tty\"))" $here/.build/debug/S14Embed query $here/out/bge-small-$m.mlmodelc $vocab $cu "why are there two high tides every day" 2>&1)
  code=$?
  sleep 1
  denials=$(log show --start "$start" --style compact --predicate 'eventMessage CONTAINS "S14Embed" AND eventMessage CONTAINS "deny"' 2>/dev/null | grep -c deny)
  echo "$m/$cu: exit $code · $(echo "$out" | head -1) · sandbox denials: $denials"
  [[ $denials -gt 0 ]] && log show --start "$start" --style compact --predicate 'eventMessage CONTAINS "S14Embed" AND eventMessage CONTAINS "deny"' 2>/dev/null | grep deny | sed 's/.*deny/  deny/' | sort -u | head -5
done; done
echo "files written in the work folder: $(find $work -newer $marker -type f | wc -l | tr -d ' ')"
echo "new files in ~/Library/Caches: $(find ~/Library/Caches -newer $marker -type f 2>/dev/null | grep -ci s14embed)"
rm -rf $work
