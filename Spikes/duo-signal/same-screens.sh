#!/bin/zsh
# Compares two runs' screen dumps (run.sh with and without the mod), times and durations masked.
#   Spikes/duo-signal/same-screens.sh <run-a> <run-b>
a=${1:A} b=${2:A} bad=0
for f in $a/0*.txt; do
  n=${f:t}
  if diff -q <(sed -E -e 's/[0-9]+:[0-9]+ (AM|PM)//' -e 's/[^ ]+ed for [0-9]+s/V for Ns/' -e 's#/tmp/[^/]+/scratch#/tmp/R/scratch#' -e 's/Try "[^"]*"/Try "…"/' -e 's/ +$//' -- "$f") \
             <(sed -E -e 's/[0-9]+:[0-9]+ (AM|PM)//' -e 's/[^ ]+ed for [0-9]+s/V for Ns/' -e 's#/tmp/[^/]+/scratch#/tmp/R/scratch#' -e 's/Try "[^"]*"/Try "…"/' -e 's/ +$//' -- "$b/$n") >/dev/null; then
    echo "same      $n"
  else
    echo "DIFFERENT $n"; bad=1
    diff <(sed -E -e 's/[0-9]+:[0-9]+ (AM|PM)//' -e 's/[^ ]+ed for [0-9]+s/V for Ns/' -e 's#/tmp/[^/]+/scratch#/tmp/R/scratch#' -e 's/Try "[^"]*"/Try "…"/' -e 's/ +$//' -- "$f") \
         <(sed -E -e 's/[0-9]+:[0-9]+ (AM|PM)//' -e 's/[^ ]+ed for [0-9]+s/V for Ns/' -e 's#/tmp/[^/]+/scratch#/tmp/R/scratch#' -e 's/Try "[^"]*"/Try "…"/' -e 's/ +$//' -- "$b/$n") | head -8
  fi
done
exit $bad
