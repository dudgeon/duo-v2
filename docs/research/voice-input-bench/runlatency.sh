#!/bin/bash
# runlatency.sh <label>: the latency/RTF pass on a quiet Mac, holding duo-voice's GPU lock for as short
# a time as possible. 40 clips (each utterance once, voices rotated); batch then stream.
set -u
label=${1:?label}
BENCH=$(cd "$(dirname "$0")" && pwd)
CACHE=$HOME/Library/Caches/duo-voice-input
M=$CACHE/manifests/lat40.jsonl
out=$CACHE/results/$label; mkdir -p "$out"
LOCK=${GPU_LOCK:?set GPU_LOCK to the shared lock folder}
until mkdir "$LOCK" 2>/dev/null; do sleep 60; done   # wait for the voice/video jobs to release it
echo "== lock taken $(date +%H:%M:%S)" >&2
echo "duo-v2 voice-input research latency pass (pid $$, $(date))" > "$LOCK/owner"
trap 'rm -f "$LOCK/owner"; rmdir "$LOCK"' EXIT
R() { echo "== $(date +%H:%M:%S) $*" >&2; SKIP_MEMGATE=1 "$BENCH/run.sh" "$@" 2>>"$out/run.log" || echo "!! failed: $*" >&2; }
for e in apple-speechtranscriber apple-dictation fluid-parakeet-v3 fluid-parakeet-unified fluid-parakeet-redux \
         whisperkit-turbo mlx-whisper-turbo moonshine-medium-streaming; do
  R "$e" "$M" "$out/$e.batch.jsonl"
done
for e in apple-speechtranscriber apple-dictation fluid-parakeet-stream-7-1 fluid-nemotron-stream \
         moonshine-medium-streaming kyutai-stt; do
  R "$e" "$M" "$out/$e.stream.jsonl" --mode stream
done
echo "== done $(date +%H:%M:%S)" >&2
