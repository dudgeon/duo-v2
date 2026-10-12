# asrbench (Swift runners)

One executable, `asrbench`, runs the on-device engines for the voice-input benchmark (see `../SPEC.md`). It is research tooling, not part of Duo.

## Build

```
cd docs/research/voice-input-bench/swift
swift build -c release --scratch-path ~/Library/Caches/duo-voice-input/swift-build
```

Command Line Tools only (Swift 6.4, macOS 27 SDK). The package is `swift-tools-version: 6.2`, platform macOS 26, Swift 5 language mode. First build fetches FluidAudio and WhisperKit and takes a couple of minutes.

Dependencies:

- FluidAudio, revision `e560c6445ffdc42e60c7b282d162aae271f18e2a` (newest `main` on 2026-10-12), `traits: []`. The mini-meeting-minutes pin (`20d4f0bd...`) was NOT used because the lead asked for Unified, Nemotron and CustomVocabulary, which are on current main; `AsrModelVersion.redux` and `AsrModels.loadLocal(from:version:encoderComputeUnits:)` are still there, so Redux loads exactly as in `ModelLoader.swift`.
- WhisperKit `1.1.1` (latest tag).

## Run

```
asrbench --engine <name> --manifest <m.jsonl> --out <results.jsonl> [--mode batch|stream] [--context terms.txt] [--chunk-ms 100] [--limit N]
../run.sh <engine> <manifest> <out.jsonl> [same flags]      # waits for /tmp/duo-memgate.sh, records peak RSS to <out>.time
```

Output lines: `{"id","engine","mode","hyp","audio_ms","proc_ms","first_partial_ms","final_ms","partials"}`, plus `load_ms` on the first line. An `"error"` field replaces `hyp` when a clip or the whole engine fails (exit code is still 0). stderr carries `load_ms`, the warm-up time and engine notes. The warm-up is the first manifest clip, run once unscored before the timed pass.

Rules built in: audio is read with `AVAudioFile` and converted in memory (`AVAudioConverter`) to 16 kHz mono Float32, never written; nothing records from the microphone; no authorization is ever requested; a manifest path containing `takes` is refused unless `--out` is under `$CLAUDE_JOB_DIR/tmp/private/`.

Batch timing: `proc_ms` = `final_ms` = wall time for the whole clip from audio in memory (for the Apple analyzer engines it includes creating the `SpeechAnalyzer`). Stream timing: 100 ms chunks, each handed over only once it has "been spoken" (paced against a monotonic clock); `first_partial_ms` is from the start of audio to the first non-empty partial; `final_ms` is from the last chunk to the final text.

## Engines

| engine | model | modes | `--context` |
|---|---|---|---|
| `apple-speechtranscriber` | `SpeechTranscriber` en-US (system asset) | batch, stream | accepted, no effect observed |
| `apple-dictation` | `DictationTranscriber` en-US, `.punctuation` (system asset) | batch, stream | accepted, see notes |
| `apple-sfspeech` | `SFSpeechRecognizer` en-US, on-device only | batch, stream | `contextualStrings` (untested: needs authorization) |
| `fluid-parakeet-v3` | `FluidInference/parakeet-tdt-0.6b-v3-coreml` | batch | CustomVocabulary (CTC 110M rescoring) |
| `fluid-parakeet-v2` | `FluidInference/parakeet-tdt-0.6b-v2-coreml` | batch | same |
| `fluid-parakeet-redux` | `/Users/geoff/repos/mini-meeting-minutes/Models/parakeet-redux` (read in place) | batch | same |
| `fluid-parakeet-unified` | `FluidInference/parakeet-unified-en-0.6b-coreml` (offline encoder, int8) | batch | same |
| `fluid-parakeet-stream` | same repo, streaming encoder 70_13_13 (2.08 s theoretical latency) | stream (batch too) | not supported (see notes) |
| `fluid-parakeet-stream-7-1` | streaming encoder 70_7_1 (chunk 560 ms + 80 ms right, 0.64 s) | stream | not supported |
| `fluid-parakeet-stream-2-2` | streaming encoder 70_2_2 (chunk 160 ms + 160 ms right, 0.32 s) | stream | not supported |
| `fluid-nemotron-stream` | `FluidInference/nemotron-speech-streaming-en-0.6b-coreml`, 560 ms | stream (batch too) | not wired (`setCustomVocabulary` exists, takes CustomVocabularyTerm) |
| `whisperkit-turbo` | `argmaxinc/whisperkit-coreml` `openai_whisper-large-v3-v20240930_turbo` | batch | `DecodingOptions.promptTokens` |
| `whisperkit-small-en` | `openai_whisper-small.en` | batch | same |

Models live in `~/Library/Caches/duo-voice-input/models/` (FluidAudio picks its own folder names under the base we give it): `parakeet-tdt-0.6b-v3/`, `parakeet-tdt-0.6b-v2/`, `fluid/{parakeet-unified-en-0.6b, nemotron-streaming/560ms, parakeet-ctc-110m-coreml}/`, `whisperkit/`.

## Sizes and load times (this Mac, Apple M6, smoke runs)

First load includes download and CoreML/ANE compilation; second load is warm.

| engine | on disk | first load | warm load |
|---|---|---|---|
| apple-speechtranscriber / apple-dictation | system asset (not in our cache) | 0.4 s after a one-time system install | 0.06-0.12 s |
| fluid-parakeet-v3 | 469 MB | 62.7 s | 0.4-0.6 s |
| fluid-parakeet-v2 | 443 MB | 59.0 s | not measured |
| fluid-parakeet-redux | 384 MB (mini-meeting-minutes, read in place) | 1.0 s | 1.0 s |
| fluid-parakeet-unified (offline, int8) | 2.3 GB folder (holds all streaming tiers and the int8 offline encoder) | 135.8 s | not measured |
| fluid-parakeet-stream (13_13 / 7_1 / 2_2) | same folder | 51.2 / 50.1 / 49.0 s | not measured |
| fluid-nemotron-stream (560 ms) | 612 MB | 73.2 s (batch rerun 0.18 s warm) | 0.18 s |
| CTC 110M (CustomVocabulary) | 98 MB | included | +0.2 s |
| whisperkit-turbo (`openai_whisper-large-v3-v20240930_turbo`, unquantised, not the `_632MB` one) | 1.5 GB | 1057 s (download plus ANE compile) | 2.2 s |

## Smoke results (8 synth clips; 3 shown, Samantha / Daniel / Karen of u01, "...why it times out?")

All engines got these right except where noted. Batch `proc_ms` for a ~4.2 s clip:

- apple-speechtranscriber: 100-120 ms; correct with "?" ; Karen: "time's out".
- apple-dictation: 145-324 ms; Samantha: "the times out", no "?" on most clips; `.punctuation` adds some commas ("package, swift").
- fluid-parakeet-v3: 35-40 ms; correct with "?"; "package.swift" kept as written text.
- fluid-parakeet-v2: 52-74 ms; correct, lowercase-dropped "?" on 3 of 4.
- fluid-parakeet-redux: 42-101 ms; correct.
- fluid-parakeet-unified: 36-38 ms; correct (Rishi lost the "?").
- whisperkit-turbo: 380-430 ms; correct, writes "package.swift" and `makeTerminalView` as code.
- fluid-nemotron-stream: no capitalisation or punctuation at all ("Open package swift and bump fluid audio...").

Streaming first partial (100 ms chunks, real-time pace): apple-speechtranscriber ~1.1 s; apple-dictation 0.62-0.85 s; fluid-parakeet-stream 13_13 ~2.1 s; 7_1 0.73-1.2 s; 2_2 ~0.82 s; nemotron 560 ms 0.62-1.2 s. Final after end of audio: 14-165 ms everywhere. Batch of the whole clip with one call: Parakeet 35-100 ms.

## Biasing (`--context`), tested on 4 term-heavy clips (u02-u05, Samantha)

- SpeechTranscriber: `AnalysisContext.contextualStrings[.general] = terms` then `analyzer.setContext(ctx)` succeeds (no error) but the output was identical with and without it ("clod code", "fluid audio", "make terminal view"). Not honoured for this transcriber in this test (the `.general` tag is the only public tag). Caveat: 26 terms, one voice.
- DictationTranscriber: same API; not separately tested for effect. Its documented route to custom vocabulary is `ContentHint.customizedLanguage(modelConfiguration:)` with an `SFCustomLanguageModelData` model, which needs a built language model; not tried.
- SFSpeechRecognizer: `request.contextualStrings` is wired, untested (no authorization).
- FluidAudio Parakeet (v2/v3/redux, unified batch): CustomVocabulary exists (CTC 110M keyword spotting plus rescoring, `VocabularyRescorer`). Wired for the TDT engines and the offline unified engine. With terms: "FluidAudio" and "Claude Code" fixed, but "Claude sonnet" was overcorrected to "Claude Code" (u04: "Start Claude Code dash dash model Claude Code 55"), and "duo2" was not fixed. Runtime cost +120 ms per clip. At this pin `VocabularyBoostingSession` insists on the CTC tokenizer in `~/Library/Application Support/FluidAudio/` (outside the allowed folders), so the runner re-implements the session's `rescore()` with the public pieces and our own folder. The streaming unified manager's `configureVocabularyBoosting` has the same problem, so `--context` on `fluid-parakeet-stream*` is refused with an error. Nemotron has `setCustomVocabulary`, not wired.
- WhisperKit: `promptTokens` from the tokenizer-encoded `" term, term, ..."` prompt (109 tokens for 26 terms) works: "Claude Code", "Duo2", "makeTerminalView" improved or stayed right; the cost is large, `proc_ms` went from ~300 ms to ~1300 ms because the prompt is prefilled for every window.

## Streaming

- Apple: SpeechTranscriber and DictationTranscriber stream through `SpeechAnalyzer` with `.volatileResults`; volatile results appear 0.6-1.1 s in. No authorization needed.
- FluidAudio: `StreamingUnifiedAsrManager` (one Unified 0.6B checkpoint for batch and stream, tiers 70_13_13 / 70_7_1 / 70_2_2 / 70_7_7), `StreamingNemotronAsrManager` (2240 / 1120 / 560 ms, 560 ms used), `StreamingEouAsrManager` (parakeet-realtime-eou-120m) and `SlidingWindowAsrManager` exist. The EOU and sliding-window managers are not wired. `fluid-parakeet-stream` is the Unified engine.
- WhisperKit and the TDT Parakeets have no partial results here (batch only).

## Authorization and assets

- `SpeechTranscriber` / `DictationTranscriber` need NO speech-recognition authorization: `SFSpeechRecognizer.authorizationStatus()` stayed at 0 (notDetermined) throughout and analysis ran. They do need the en-US asset: `AssetInventory.status` was `supported` (not installed), `assetInstallationRequest(supporting:)` then `downloadAndInstall()` installed it silently (no UI), after which the status was `installed`. DictationTranscriber's asset was already installed.
- `apple-sfspeech` was not run: status is notDetermined, so the runner writes one `{"error": ...}` line and exits 0 without asking.

## Not tested (stopped on request because the Mac was swapping)

- `whisperkit-small-en` (wired, never downloaded).
- `apple-sfspeech` with authorization (cannot run), `apple-dictation --context`.
- Warm load for v2 and unified; `--context` for `fluid-parakeet-unified`.
- `--mode stream` and `--context` through `../run.sh` (the RSS wrapper); peak RSS numbers.
- Full 160-clip batches; all smoke output is in `~/Library/Caches/duo-voice-input/results/smoke/`.

