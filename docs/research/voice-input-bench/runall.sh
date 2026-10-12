#!/bin/bash
# runall.sh <label> [phase…]: the full benchmark, one engine at a time (each waits for the memory gate).
# Synthetic results go to $CACHE/results/<label>/; results for Geoff's takes go only to
# $CLAUDE_JOB_DIR/tmp/private/<label>/ (deleted after scoring). Phases: batch stream context takes.
set -u
label=${1:?label}; shift
phases=${*:-batch stream context takes}
BENCH=$(cd "$(dirname "$0")" && pwd)
CACHE=$HOME/Library/Caches/duo-voice-input
SYN=$CACHE/manifests/synth.jsonl
TAKES=$CLAUDE_JOB_DIR/tmp/private/takes.jsonl
out=$CACHE/results/$label; priv=$CLAUDE_JOB_DIR/tmp/private/$label
mkdir -p "$out" "$priv"
R() { echo "== $(date +%H:%M:%S) $*" >&2; "$BENCH/run.sh" "$@" 2>>"$out/run.log" || echo "!! failed: $*" >&2; }

for phase in $phases; do case $phase in
batch)
  for e in apple-speechtranscriber apple-dictation fluid-parakeet-v3 fluid-parakeet-v2 fluid-parakeet-redux \
           fluid-parakeet-unified whisperkit-turbo mlx-whisper-turbo mlx-distil-whisper-v35 \
           moonshine-medium-streaming moonshine-base; do
    R "$e" "$SYN" "$out/$e.batch.jsonl"
  done ;;
stream)
  for e in apple-speechtranscriber apple-dictation fluid-parakeet-stream-7-1 fluid-nemotron-stream \
           moonshine-medium-streaming kyutai-stt parakeet-mlx-v3; do
    R "$e" "$SYN" "$out/$e.stream.jsonl" --mode stream
  done ;;
context)
  for e in apple-speechtranscriber apple-dictation fluid-parakeet-v3 whisperkit-turbo mlx-whisper-turbo; do
    R "$e" "$SYN" "$out/$e.ctx.jsonl" --context "$BENCH/context-terms.txt"
  done ;;
takes)
  for e in apple-speechtranscriber apple-dictation fluid-parakeet-v3 fluid-parakeet-unified whisperkit-turbo \
           mlx-whisper-turbo moonshine-medium-streaming; do
    R "$e" "$TAKES" "$priv/$e.takes.jsonl"
  done ;;
esac; done
echo "== done $(date +%H:%M:%S)" >&2
