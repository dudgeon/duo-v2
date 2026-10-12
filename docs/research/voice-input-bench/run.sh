#!/bin/bash
# run.sh <engine> <manifest> <out.jsonl> [runner args, e.g. --mode stream --context terms.txt]
# Wraps one runner in /usr/bin/time -l and writes its report (peak RSS: "maximum resident set
# size", in bytes on macOS) to <out>.time. Peak RSS misses ANE/GPU memory held outside the process.
# Python engines run in their family venv with `python -I`; anything else is a Swift engine run
# through the built asrbench binary (swift build --scratch-path $CACHE/swift-build -c release).
# Waits for /tmp/duo-memgate.sh first (set SKIP_MEMGATE=1 to skip).
set -u
engine=${1:?engine}; manifest=${2:?manifest}; out=${3:?out}; shift 3
BENCH=$(cd "$(dirname "$0")" && pwd)
CACHE=$HOME/Library/Caches/duo-voice-input

case "$engine" in
  mlx-whisper-turbo|mlx-distil-whisper|mlx-distil-whisper-v35) venv=mlxwhisper ;;
  parakeet-mlx-v2|parakeet-mlx-v3) venv=parakeet ;;
  moonshine|moonshine-*) venv=moonshine ;;
  kyutai-stt|kyutai-stt-2.6b) venv=kyutai ;;
  voxtral-mini|voxtral-mini-8bit|voxtral-realtime|granite-speech) venv=voxtral ;;
  *) venv= ;;
esac

if [ -z "${SKIP_MEMGATE:-}" ] && [ -x /tmp/duo-memgate.sh ]; then /tmp/duo-memgate.sh; fi

mkdir -p "$(dirname "$out")"
cd "$TMPDIR" 2>/dev/null || cd /tmp   # never run from a download or source folder
if [ -n "$venv" ]; then
  /usr/bin/time -l -o "$out.time" "$CACHE/venv-$venv/bin/python" -I "$BENCH/py/asrbench.py" \
    --engine "$engine" --manifest "$manifest" --out "$out" "$@"
else
  /usr/bin/time -l -o "$out.time" "$CACHE/swift-build/release/asrbench" \
    --engine "$engine" --manifest "$manifest" --out "$out" "$@"
fi
rc=$?
echo "run.sh: $engine rc=$rc ($(grep 'maximum resident' "$out.time" 2>/dev/null | awk '{printf "%.0f MB", $1/1048576}') peak RSS)" >&2
exit $rc
