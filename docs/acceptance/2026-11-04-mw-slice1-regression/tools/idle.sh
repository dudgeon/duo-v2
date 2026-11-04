#!/bin/zsh
# idle.sh <old|new> <windows 1|3> <outfile> [seconds=300]: an isolated Duo left idle at All projects with 1 or 3 windows;
# CPU (ps %cpu, plus exact CPU-seconds used per interval from cputime) and RSS every 10 s. Run under scripts/timing-lock.sh.
export MWR=/tmp/mwr-idle-$1-$2
. ${0:A:h}/lib.sh
APPP=$(appfor $1); n=$2; OUTF=$3; secs=${4:-300}
sup_reset; fx_build
app_start $APPP
d2x() { $D2 "$@" >/dev/null 2>&1; }
d2x settings claude-path $STUB
if (( n >= 2 )); then d2x window new refunds; fi
if (( n >= 3 )); then d2x window new onboarding; fi
sleep 20   # settle
cpusec() { ps -o cputime= -p $PID | awk -F: '{ s=0; for (i=1;i<=NF;i++) s=s*60+$i; print s }'; }
{
  echo "# $1 $n window(s), idle $secs s; windows: $($D2 window list 2>/dev/null | tr '\n' ';' )"
  echo "# t pscpu rssMB cpusec_total"
  start=$(cpusec); t0=$SECONDS
  for ((t = 10; t <= secs; t += 10)); do
    sleep 10
    echo "$t $(ps -o %cpu= -p $PID | tr -d ' ') $(( $(ps -o rss= -p $PID) / 1024 )) $(cpusec)"
  done
  end=$(cpusec)
  echo "# average CPU over $secs s from cputime: $(python3 -c "print(round(($end-$start)/$secs*100,2))")%"
  echo "# load: $(uptime)"
} > $OUTF
app_stop
echo done $OUTF
