#!/bin/bash
# runnov.sh <label> <phase> <engine[:stream]>...: one phase of the November pass for the given engines (run it under
# scripts/gpu-lock.sh --shared, or scripts/timing-lock.sh for the latency phase). Phases:
#   firstload  one clip, batch (or stream for *-stream engines): load_ms is the first load after the download
#   batch | stream | ctx   160 synthetic clips -> $CACHE/results/<label>/
#   takes      Geoff's takes, batch -> $CLAUDE_JOB_DIR/tmp/private/<label>/ (aggregates only leave that folder)
#   lat        lat40 manifest, batch (and stream for stream engines) -> $CACHE/results/<label>/lat/
# MAXMIN=<n> kills a run that is still going after n minutes (records it in run.log).
set -u
label=${1:?label}; phase=${2:?phase}; shift 2
BENCH=$(cd "$(dirname "$0")" && pwd)
CACHE=$HOME/Library/Caches/duo-voice-input
out=$CACHE/results/$label; priv=${CLAUDE_JOB_DIR:-/nonexistent}/tmp/private/$label
mkdir -p "$out/firstload" "$out/lat"; log=$out/run${LOGTAG:+.$LOGTAG}.log
SYN=$CACHE/manifests/synth.jsonl; LAT=$CACHE/manifests/lat40.jsonl
R() { # R <engine> <manifest> <outfile> [args]
  echo "== $(date +%H:%M:%S) $*" | tee -a "$log" >&2
  SKIP_MEMGATE=1 "$BENCH/run.sh" "$@" 2>>"$log" &
  pid=$!
  ( sleep $(( ${MAXMIN:-40} * 60 )); kill -TERM $pid 2>/dev/null && echo "!! killed after ${MAXMIN:-40} min: $*" >>"$log" ) &
  wd=$!
  wait $pid || echo "!! failed: $*" >>"$log"
  kill $wd 2>/dev/null
}
for spec in "$@"; do   # engine or engine:stream
  memory_pressure | tail -1 >>"$log"
  e=${spec%:stream}; sm=0; [ "$e" != "$spec" ] && sm=1
  case $e in *-stream*) sm=1;; esac
  case $phase in
    firstload) if [ $sm = 1 ]; then R $e $SYN "$out/firstload/$e.stream.jsonl" --mode stream --limit 1
               else R $e $SYN "$out/firstload/$e.batch.jsonl" --limit 1; fi ;;
    batch)  R $e $SYN "$out/$e.batch.jsonl" ;;
    stream) R $e $SYN "$out/$e.stream.jsonl" --mode stream ;;
    ctx)    R $e $SYN "$out/$e.ctx.jsonl" --context "$BENCH/context-terms.txt" ;;
    takes)  mkdir -p "$priv"
            if [ $sm = 1 ]; then R $e "${priv%/*}/takes.jsonl" "$priv/$e.takes-stream.jsonl" --mode stream
            else R $e "${priv%/*}/takes.jsonl" "$priv/$e.takes.jsonl"; fi ;;
    lat)    if [ $sm = 1 ]; then R $e $LAT "$out/lat/$e.stream.jsonl" --mode stream; else R $e $LAT "$out/lat/$e.batch.jsonl"; fi ;;
  esac
done
