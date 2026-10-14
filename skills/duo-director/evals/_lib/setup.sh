#!/bin/sh
# Sourced by each case's scaffold (which runs as you, in the case's sandboxed folder, with a clean
# environment). Copies this branch's duo2 into the case folder: the case's sandbox can read neither
# /tmp nor the repo, and run-evals.sh puts the relative `.director-bin` first on PATH (F-314).
# `lib` is this folder, set by the caller.
root=$(cd "$lib/../../../.." && pwd)
mkdir -p .director-bin
cp "$root/.build/debug/duo2" .director-bin/duo2
