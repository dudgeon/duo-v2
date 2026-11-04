#!/bin/zsh
# scale-all.sh <outdir>: run under scripts/timing-lock.sh (one exclusive hold). check-scale.sh on each build back to back:
# main, 0.2.22, 0.2.23, main again (noise). Records the machine's load and the busiest other processes before each run,
# so a number can be read against how quiet the Mac was. Nothing here touches Geoff's Duo (check-scale is isolated).
REPO=${REPO:-${${(%):-%x}:A:h:h:h:h:h}}
OLD=${OLD:?set OLD to the v0.2.22 Duo.app}
OLD23=${OLD23:?set OLD23 to the v0.2.23 Duo.app}
NEW=$REPO/build/Duo.app
out=$1; mkdir -p $out
cd $REPO
for pair in new:$NEW old:$OLD old23:$OLD23 new2:$NEW; do
  tag=${pair%%:*}; app=${pair#*:}
  {
    echo "== $tag $(date +%T)"
    uptime
    echo "busiest other processes:"; ps -Ao %cpu,comm -r | sed -n 2,6p | cut -c1-120
  } > $out/$tag.load.txt
  NO_BUILD=1 APP=$app SECONDS_RUN=60 scripts/check-scale.sh > $out/$tag.out 2>&1
  echo "exit $?" >> $out/$tag.out
  { echo "-- after: $(date +%T)"; uptime; } >> $out/$tag.load.txt
done
echo done
