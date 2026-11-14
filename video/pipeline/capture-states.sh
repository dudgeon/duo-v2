#!/bin/bash
# Captures fixture states (window PNG + anchors JSON) in the background, isolated, the way pipeline/capture.mjs does.
#   video/pipeline/capture-states.sh <outdir> <scale> <state>...      (run from a work tree with build/Duo.app)
set -u
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$1"; scale="$2"; shift 2
mkdir -p "$out"
for st in "$@"; do
  support="$(mktemp -d /tmp/dvid.XXXXXX)"
  env -u DUO_SOCKET -u DUO_TOKEN -u DUO_SUPPORT_DIR /usr/bin/open -g -W -n --env "DUO_SUPPORT_DIR=$support" --env DUO_ISOLATED=1 --env DUO_APPEARANCE=light \
    "$root/build/Duo.app" --args --state "$st" --capture-scale "$scale" --fixture "$root/video/fixture/fixture.json" \
    --then "anchors:$out/$st.anchors.json" --capture-window "$out/$st.png"
  rm -rf "$support"
  [ -f "$out/$st.png" ] && echo "ok $st" || echo "FAILED $st"
done
