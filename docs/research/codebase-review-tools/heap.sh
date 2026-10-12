#!/bin/zsh
# What holds the steady footprint with 4 long transcripts: one isolated release launch of the
# rel-idle fixture, 90 s, then `heap` (live allocations by class) and `footprint`. Same isolation as measure.sh.
set -u
W=${W:-${0:A:h:h:h:h}}
M=${M:-${TMPDIR:-/tmp}/duo-review}
L=${GPU_LOCK:?set GPU_LOCK to the shared lock folder}
o=$M/runs/heap; rm -rf $o; mkdir -p $o
until mkdir $L 2>/dev/null; do sleep 2; done
echo "codebase-review-heap $$" > $L/owner
fx=$(mktemp -d /tmp/d-rv-XXXX); fx=${fx:A}
printf '#!/bin/sh\nexec /usr/bin/python3 -I %s "$@"\n' "$W/scripts/scale-tui.py" > $fx/claude; chmod +x $fx/claude
python3 $W/scripts/make-scale-fixture.py $fx --projects 6 --sessions 42 --tabs 0 --claude $fx/claude > /dev/null
env -u DUO_SUPPORT_DIR -u DUO_SOCKET -u DUO_TOKEN DUO_SUPPORT_DIR=$fx/sup CLAUDE_CONFIG_DIR=$fx/cfg DUO_AUTOCONFIRM=1 \
  $M/Duo-release.app/Contents/MacOS/Duo --workspace $fx/ws 2>$o/stderr.txt &
pid=$!
sleep 90
footprint -p $pid > $o/footprint.txt 2>&1
heap -s $pid > $o/heap.txt 2>&1
kill -TERM $pid; for i in {1..20}; do kill -0 $pid 2>/dev/null || break; sleep 1; done
pkill -f "$fx/claude" 2>/dev/null
rm -rf $fx
[[ "$(cat $L/owner 2>/dev/null)" == "codebase-review-heap $$" ]] && { rm -f $L/owner; rmdir $L }   # only our own lock (F-296)
grep -E 'Footprint:' $o/footprint.txt; grep -E 'All zones|Process [0-9]+:' $o/heap.txt | head -3
sed -n '/COUNT *BYTES/,+25p' $o/heap.txt | head -30
