# Voice-input benchmark harness: spec

Research harness for `docs/research/voice-input.md`. It is not part of Duo and is not built by Duo's scripts.

## Layout

- `BENCH` = `docs/research/voice-input-bench/` (this folder, in git).
- `CACHE` = `~/Library/Caches/duo-voice-input/` (outside git). Models go in `CACHE/models/<name>/`, synthetic audio in `CACHE/audio/synth/`, and venvs in `CACHE/venv-<name>/`. SwiftPM build products go in `CACHE/swift-build/` (`swift build --scratch-path`).
- `PRIVATE` = `$CLAUDE_JOB_DIR/tmp/private/` holds per-clip results for Geoff's takes. It never enters git and is deleted at the end.

## Rules

- Downloaded code and weights are untrusted. Never run code from inside a download folder, and run Python that reads them with `python -I`. Install packages with `uv` into `CACHE` venvs, never system-wide, and never with Homebrew.
- Before any heavy step (a model load, a batch, a big build), run `/tmp/duo-memgate.sh`. Never take the shared GPU lock (`$GPU_LOCK`) outside the latency pass.
- Never record from the microphone, and never call anything that shows a permission prompt (`SFSpeechRecognizer.requestAuthorization`, `AVCaptureDevice.requestAccess`). Check status only; if an API is refused for lack of authorization, record that as the result.
- The private takes (`$TAKES_DIR`, a folder outside this repo: `<name>.wav` with its text in the matching `.json` `"text"`) are read in place: no copying, no derived audio files (resample in memory), and nothing written under `duo-voice`. Hypotheses for them go only to `PRIVATE`.

## Test sets (manifests are JSONL)

- `synth`: `BENCH/utterances.jsonl` × voices {Samantha (en_US), Daniel (en_GB), Karen (en_AU), Rishi (en_IN)}, made with `say -v <voice> --data-format=LEI16@16000 -o CACHE/audio/synth/<id>_<voice>.wav "<spoken>"`. That's 160 clips. Manifest at `CACHE/manifests/synth.jsonl`: `{"id":"u01_Samantha","wav":"…","ref":"<spoken>","written":"<written or spoken>","terms":[…]}`.
- `takes`: manifest at `PRIVATE/takes.jsonl`, built by `make_manifests.py`, with `ref` = the json `"text"` and `terms` = [].

## Runner interface (every engine)

```
<runner> --engine <name> --manifest <m.jsonl> --out <results.jsonl> [--mode batch|stream] [--context <terms.txt>]
```

- Load the model once, then run one warm-up clip that isn't scored. For each clip, write one JSON line: `{"id", "hyp", "audio_ms", "load_ms" (first line only), "proc_ms", "first_partial_ms", "final_ms", "partials"}`.
- **batch**: `proc_ms` is the wall time to transcribe the whole clip, from audio already in memory, with the model already loaded. `final_ms` = `proc_ms`; it is the push-to-talk latency after key release.
- **stream** (only for engines with partial results): feed 16 kHz audio in chunks of 100 ms (or the engine's native chunk), paced at real time. `first_partial_ms` is from the start of the audio to the first non-empty partial. `final_ms` is from the end of the audio to the final result. `partials` is a count.
- `--context` is a file of biasing terms, one per line, for engines that support biasing (Apple `AnalysisContext.contextualStrings`, Whisper `prompt`/`initial_prompt`, FluidAudio vocabulary boosting if it exists). The terms file is `BENCH/context-terms.txt`.
- `run.sh <engine> <manifest> <out> [args]` wraps a runner in `/usr/bin/time -l` and records peak RSS (`maximum resident set size`) to `<out>.time`. Peak RSS misses ANE/GPU memory that's held outside the process; note that caveat.

## Scoring (`score.py`)

- Normalise with lowercase, curly quotes to straight, punctuation stripped except inside tokens (`.`, `/`, `-`, `_`, `@` between alphanumerics are kept), and whitespace collapsed. Number words are not converted.
- **WER (spoken form)**: Levenshtein over words, hyp against `ref`, normalised. Report corpus WER (total edits / total ref words).
- **Term accuracy (written form)**: for each term in `terms`, a hit if `compact(term)` appears in `compact(hyp)`, where compact = lowercase, keep only `[a-z0-9]`. This is lenient on symbols: `duo2` matches "Duo 2" but not "duo two". Also report the strict version, which keeps the symbols `.-/_@` and drops whitespace.
- **Written-form WER**: the same Levenshtein against `written`. It shows the gap that only a spoken-to-code formatter would close.
- Output `summary.json` per engine and set: n clips, WER, written-WER, term-hit lenient/strict, median and p90 `final_ms`, median `first_partial_ms`, RTF = Σproc/Σaudio, `load_ms`, peak RSS MB, and model size on disk (`du` of its folder).
