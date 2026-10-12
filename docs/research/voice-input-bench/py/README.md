# Python ASR runners and scorer

Spec: `../SPEC.md`. `CACHE` = `~/Library/Caches/duo-voice-input`.

## Setup (uv, one venv per family, nothing system-wide)

```
export UV_CACHE_DIR=$CACHE/uv-cache
cd $CACHE
uv venv --python 3.12 venv-mlxwhisper && uv pip install -p venv-mlxwhisper/bin/python mlx-whisper soundfile soxr numpy huggingface_hub
uv venv --python 3.12 venv-parakeet   && uv pip install -p venv-parakeet/bin/python parakeet-mlx soundfile soxr numpy
uv venv --python 3.12 venv-moonshine  && uv pip install -p venv-moonshine/bin/python moonshine-voice soundfile soxr numpy
uv venv --python 3.12 venv-kyutai     && uv pip install -p venv-kyutai/bin/python moshi_mlx soundfile soxr numpy huggingface_hub sentencepiece rustymimi
uv venv --python 3.12 venv-voxtral    && uv pip install -p venv-voxtral/bin/python mlx-audio soundfile soxr numpy huggingface_hub torch mistral-common
```

Versions: mlx-whisper 0.4.3, parakeet-mlx 0.5.3, moonshine-voice 0.1.5, moshi-mlx 0.3.0 (pins mlx 0.26.5, hence its own venv), mlx-audio 0.5.8 (+ torch 2.14.1, transformers 5.19.0, needed only by `voxtral-mini`'s processor). Models download on first run into `$CACHE/models/<engine>/` (the runner sets `HF_HUB_CACHE` there; Moonshine uses its own cache_root).

## Run

```
BENCH/run.sh <engine> <manifest> <out.jsonl> [--mode batch|stream] [--context BENCH/context-terms.txt] [--chunk-ms N]
BENCH/py/venv python: $CACHE/venv-<family>/bin/python -I BENCH/py/asrbench.py --engine ... (run.sh does this)
python3 BENCH/py/score.py --manifest M.jsonl [--set NAME] [--summary-dir DIR] results1.jsonl name=results2.jsonl ...
```

`run.sh` waits for `/tmp/duo-memgate.sh` (`SKIP_MEMGATE=1` to skip), runs `python -I` from `$TMPDIR`, writes `<out>.time` (`/usr/bin/time -l`), and sends engines it does not know to `$CACHE/swift-build/release/asrbench`. `score.py` accepts Swift-runner results (same JSONL), reads `<results>.time` for peak RSS, and takes model size from `$CACHE/models/<name>` (name = file stem, trailing `.tag` parts dropped).

Stream mode: audio paced at real time; Parakeet defaults to 480 ms chunks (100 ms chunks give garbled text and RTF > 1), Kyutai 80 ms frames, others 100 ms. `proc_ms` in stream mode = time inside engine calls only. Kyutai: 1.0 s silence prefix is fed before the clock starts (unpaced); at the end the remaining audio plus (delay + 1.0 s) of silence is flushed unpaced, so `final_ms` is flush compute time (an app injects silence at key release).

## Engines

| engine | model | revision | disk | batch | stream | biasing |
|---|---|---|---|---|---|---|
| `mlx-whisper-turbo` | mlx-community/whisper-large-v3-turbo (fp16) | a4aaeec | 1.5 GB | yes | no | `initial_prompt` = terms joined by ", " |
| `mlx-distil-whisper` | mlx-community/distil-whisper-large-v3 | e1c3c15 | 1.4 GB | yes | no | same |
| `mlx-distil-whisper-v35` | wbell7/distil-whisper-large-v3.5-mlx (third-party conversion of distil-large-v3.5; no mlx-community build exists) | 31357b4 | 1.4 GB | yes | no | same |
| `parakeet-mlx-v3` | mlx-community/parakeet-tdt-0.6b-v3 (fp32 weights, bf16 compute) | ed2b7e8 | 2.3 GB | yes | yes (`transcribe_stream`, local attention, 480 ms) | none |
| `parakeet-mlx-v2` | mlx-community/parakeet-tdt-0.6b-v2 | 8ae1553 | 2.3 GB | yes | yes | none |
| `moonshine` = `moonshine-medium-streaming` | Moonshine Voice medium-streaming-en, quantized_26_08_21 (download.moonshine.ai) | n/a | 258 MB | yes | yes | `set_keyterms` (streaming archs only) |
| `moonshine-small-streaming` | small-streaming-en | n/a | 137 MB | yes | yes | same |
| `moonshine-base` | base-en (non-streaming) | n/a | 136 MB | yes | no | none |
| `kyutai-stt` | kyutai/stt-1b-en_fr-mlx (bf16) | 2b99572 | 2.3 GB | yes (unpaced) | yes, native | none |
| `kyutai-stt-2.6b` | kyutai/stt-2.6b-en-mlx | 5ccfc8f | 5.4 GB | yes | yes, native | none |
| `voxtral-realtime` | mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit | fdebf7b | 2.9 GB | yes | yes (`create_streaming_session`) | none |
| `voxtral-mini` | mzbac/voxtral-mini-3b-4bit-mixed (Voxtral-Mini-3B-2507, 4-bit mixed) | d5803d1 | 3.0 GB | yes | no | none wired (LLM could take a prompt) |
| `granite-speech` | mlx-community/granite-4.0-1b-speech-8bit (1B, not the 2B) | 5ed3098 | 2.7 GB | yes | no | none wired |

Disk sizes are `du` of the model folder (includes the HF blob store). Moonshine's alphanumeric "spelling" model downloads alongside.

## Status (8-clip smoke, `results/smoke/`)

Worked: all of the above except as noted. Not working / untested:
- `voxtral-mini`: first run failed in transformers' processor (needs `format=` for arrays, and torch). Fixed in code (wrapper passes `format="wav"`, in-memory BytesIO), torch installed, but **not re-run** (stopped for memory).
- `voxtral-realtime --mode stream`: output is correct but timings were 80-130 s per 4 s clip in the two full smoke runs (first run: clips 1-3 were 5.6 s, then degraded) while batch mode was 3.5 s at the same moment. A debug script (3 chunk sizes, single clip) later showed ~4-8 s total, so the slow runs coincided with GPU/memory contention from the other job; re-measure when the machine is quiet. Treat its stream timings in the smoke files as invalid.
- Moonshine `--context` produced no visible change on the 8 clips; effect unmeasured.
- Kyutai batch `final_ms` is full compute (~RTF 0.66), stream `final_ms` is only the end flush.
- Parakeet stream at 100 ms is bad; use the default 480 ms.
