#!/bin/bash
# Captures the demo fixture the way the video does (video/pipeline/capture.mjs): background, a throwaway
# support folder, never on screen (F-227, F-113). Usage: video/fixture/check-captures.sh <out-dir> [state …]
# Default states: every video-s2 state. Look at the PNGs before calling a fixture ready.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
out=${1:?out dir}; shift || true
states=("$@")
[ ${#states[@]} -eq 0 ] && states=(video-s2-middle-0 video-s2-middle-1 video-s2-middle-2 video-s2-chat video-s2-right-1 video-s2-right-2 video-s2-right-3 video-s2-right-4)
mkdir -p "$out"
for s in "${states[@]}"; do
  support=$(mktemp -d /tmp/dfx.XXXX)
  env -u DUO_SOCKET -u DUO_TOKEN -u DUO_SUPPORT_DIR /usr/bin/open -g -W -n --env "DUO_SUPPORT_DIR=$support" "$repo/build/Duo.app" \
    --args --state "$s" --capture-scale 1 --fixture "$repo/video/fixture/fixture.json" --capture-window "$out/$s.png"
  rm -rf "$support"
  [ -f "$out/$s.png" ] && echo "ok $s" || echo "FAILED $s"
done
