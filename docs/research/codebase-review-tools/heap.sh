#!/bin/zsh
# What holds the steady footprint with 4 long transcripts: one isolated release launch of the
# rel-idle fixture, 90 s, then `heap` (live allocations by class) and `footprint`. Same isolation as measure.sh.
# Runs under the shared GPU lock through scripts/gpu-lock.sh (set GPU_LOCK).
set -u
W=${W:-${0:A:h:h:h:h}}
M=${M:-${TMPDIR:-/tmp}/duo-review}
: ${GPU_LOCK:?set GPU_LOCK to the shared lock folder}
[[ -n ${HEAP_LOCKED:-} ]] || exec $W/scripts/gpu-lock.sh codebase-review-heap env HEAP_LOCKED=1 W=$W M=$M $0 "$@"
o=$M/runs/heap; rm -rf $o; mkdir -p $o
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
grep -E 'Footprint:' $o/footprint.txt; grep -E 'All zones|Process [0-9]+:' $o/heap.txt | head -3
sed -n '/COUNT *BYTES/,+25p' $o/heap.txt | head -30
