#!/bin/zsh
# Does a no-op build recompile after the tree sits idle? Builds back to back, then after 30 s, 90 s and 180 s idle.
#   idle-rebuild.sh <tag> [extra swift build args…]   (e.g. --build-system native --scratch-path <dir>)
cd ${W:-${0:A:h:h:h:h}} || exit 1
zmodload zsh/datetime
O=${O:-${TMPDIR:-/tmp}/duo-review}; mkdir -p $O
tag=${1:-default}; shift
extra=("$@")
b() { local label=$1 s=$EPOCHREALTIME; swift build -c debug "${extra[@]}" > $O/idle-$tag-$label.log 2>&1; local rc=$? e=$EPOCHREALTIME
      printf '%s: rc %d, %.1f s, last step %s\n' $label $rc $(( e - s )) "$(grep -oE '^\[[0-9]+ / [0-9]+\]' $O/idle-$tag-$label.log | tail -1)"; }
b warm; b again
sleep 30; b after30
sleep 90; b after90
sleep 180; b after180
