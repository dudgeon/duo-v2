#!/bin/zsh
# Chat mode's performance run (F-157): an isolated Duo follows a generated long session in chat
# mode, then times the open, a scroll from the bottom up, and replies arriving while scrolled up.
#
#   scripts/perf-chat.sh [out-dir] [make-long-chat.py args…]
#
# PERF_TRANSCRIPT=<file.jsonl> follows a copy of a real transcript instead of a generated one.
# Isolated: its own support folder and Claude config folder under /tmp; never Geoff's Duo.
# Writes <out>/perf.log (the `perf:` lines), <out>/sample-*.txt (sample(1) while opening,
# scrolling and appending) and <out>/window.png. PERF_THEN replaces the actions.
set -u
root=${0:A:h:h}
cd $root
out=${1:-build/perf/run}; shift 2>/dev/null
mkdir -p $out
out=${out:A}
sid=5e55f00d-0000-4000-8000-00000000c4a7
cwd=/Users/pm/work/payments/checkout-redesign
sup=/tmp/d-perf-$$
cfg=$(mktemp -d /tmp/c-perf-XXXX)
proj=$cfg/projects/$(print -r -- $cwd | sed 's/[^A-Za-z0-9]/-/g')
mkdir -p $sup $proj
if [[ -n ${PERF_TRANSCRIPT:-} ]]; then
  # A real transcript instead (a copy, in the scratch folder; never committed): its own id and folder.
  sid=${PERF_TRANSCRIPT:t:r}
  cwd=$(python3 -c "import json,sys
for l in open(sys.argv[1]):
    c = json.loads(l).get('cwd')
    if c: print(c); break" $PERF_TRANSCRIPT)
  proj=$cfg/projects/$(print -r -- $cwd | sed 's/[^A-Za-z0-9]/-/g')
  mkdir -p $proj
  cp $PERF_TRANSCRIPT $proj/$sid.jsonl
  echo "$PERF_TRANSCRIPT: $(wc -c < $PERF_TRANSCRIPT) bytes" > $out/fixture.txt
else
  python3 scripts/make-long-chat.py $proj/$sid.jsonl "$@" | tee $out/fixture.txt
fi
# Replies that arrive during the run: more of the same turn (no prompt first), then new turns.
python3 scripts/make-long-chat.py $cfg/more.jsonl --turns 3 --tools 12 --seed 9 >/dev/null
tail -n +2 $cfg/more.jsonl > $cfg/same-turn.jsonl
t=$proj/$sid.jsonl

# PERF_PROFILE=live: only replies arriving at the bottom, four rounds.
live="perf-follow:$sid|$cwd,wait:4"
for i in 1 2 3 4; do live+=",perf-bottom,wait:1,perf-append:$cfg/same-turn.jsonl|$t|28|at-bottom-$i,wait:3"; done
full="perf-follow:$sid|$cwd,wait:4,perf-report,perf-views,+perf-sample:4|$out/sample-scroll.txt,perf-wheel:300|40,wait:14,perf-wheel:120|200,wait:7,perf-bottom,wait:4,perf-sample:3|$out/sample-append.txt,+perf-append:$cfg/same-turn.jsonl|$t|60|at-bottom,wait:5,perf-middle,wait:2,perf-report,perf-sample:3|$out/sample-up.txt,+perf-append:$cfg/more.jsonl|$t|60|scrolled-up,wait:5,perf-report"
[[ ${PERF_PROFILE:-full} == live ]] && then=$live || then=${PERF_THEN:-$full}
env -u DUO_SUPPORT_DIR ${=PERF_ENV:-} DUO_SUPPORT_DIR=$sup CLAUDE_CONFIG_DIR=$cfg DUO_AUTOCONFIRM=1 \
  build/Duo.app/Contents/MacOS/Duo --state chat-window --capture-window $out/window.png --then "$then" 2>$out/stderr.txt &
pid=$!
(sleep 0.3; sample $pid 4 -file $out/sample-open.txt >/dev/null 2>&1) &
for i in {1..180}; do kill -0 $pid 2>/dev/null || break; sleep 1; done
kill -TERM $pid 2>/dev/null
wait 2>/dev/null
grep '^perf:' $out/stderr.txt | sed 's/^perf: //' > $out/perf.log
cat $out/perf.log
rm -rf $sup $cfg
