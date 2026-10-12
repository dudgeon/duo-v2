#!/bin/zsh
# The measurement matrix: isolated background runs of measure.sh, one at a time, under the shared lock.
#   matrix.sh [run names…]      (default: all, in order)
M=${M:-${TMPDIR:-/tmp}/duo-review}   # holds Duo-release.app and Duo-debug.app (copies of build/Duo.app)
L=${GPU_LOCK:?set GPU_LOCK to the shared lock folder}
REL=$M/Duo-release.app DBG=$M/Duo-debug.app
small=(--projects 6 --sessions 42 --tabs 0)
typeset -A runs
runs=(
  rel-idle      "$REL|180||${small[*]}"
  rel-short     "$REL|120||${small[*]} --long 0"
  rel-events    "$REL|180|--events 40|${small[*]}"
  rel-churn     "$REL|240|--churn 500|${small[*]}"
  rel-scale16   "$REL|120||--projects 6 --sessions 42 --long 3 --tabs 16 --chat --modes-chat --on-home --home-view board"
  rel-term16    "$REL|120||--projects 6 --sessions 42 --long 3 --tabs 16 --on-home"
  rel-many      "$REL|180||--projects 40 --sessions 600 --tabs 0"
  rel-docs      "$REL|120|--docs 4 --html 4|${small[*]}"
  dbg-events    "$DBG|180|--events 40|${small[*]}"
  dbg-churn     "$DBG|240|--churn 500|${small[*]}"
)
order=(rel-idle rel-short rel-events rel-churn rel-scale16 rel-term16 rel-many rel-docs dbg-events dbg-churn)
(( $# )) && order=("$@")
for name in $order; do
  IFS='|' read -r app secs opts fx <<< "${runs[$name]}"
  # Take the shared lock (wait while anyone holds it; retry if another session wins the race).
  until mkdir $L 2>/dev/null; do sleep 2; done
  echo "codebase-review-measure $$" > $L/owner
  echo "=== $name ($(date +%H:%M:%S)) swap used: $(sysctl -n vm.swapusage | awk '{print $6}')"
  APP=$app OUT=$M/runs ${0:A:h}/measure.sh $name $secs ${=opts} -- ${=fx}
  rm -f $L/owner; rmdir $L
  sleep 10
done
echo "=== matrix done $(date +%H:%M:%S)"
