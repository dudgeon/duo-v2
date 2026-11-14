#!/bin/zsh
# perf-hold.sh <rawdir>: everything timing-sensitive, run inside ONE exclusive hold (scripts/timing-lock.sh).
here=${0:A:h}
raw=$1; mkdir -p $raw
$here/scale-all.sh $raw/scale
$here/idle.sh new 3 $raw/idle-new-3win.txt 300
$here/idle.sh new 1 $raw/idle-new-1win.txt 300
$here/idle.sh old 1 $raw/idle-old-1win.txt 300
echo perf-hold done
