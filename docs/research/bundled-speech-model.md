# A speech model shipped inside Duo.app

Status: research, 2026-11-14. Worker `research-bundled-speech-model` for director-duo-v2, from Geoff's request of 2026-11-14. Builds on `docs/research/voice-input.md` (2026-10-12); the bench is `docs/research/voice-input-bench/`. Records: F-694 to F-697, Q-556 to Q-560, ENH-354. Research only: nothing is built.

Geoff, 2026-11-14: *"the operating system level voice model is mediocre. I would like to include a more powerful local inference model … I don't want anyone to have to download additional model weights … Accuracy and outperformance of the macOS default model is a consideration, so is latency, so is memory requirement, and so is total file size of the weights."*

A bundled model would supersede DL-260 ("Apple's on-device transcription, and no model of Duo's own").

## Summary for Geoff

**Recommendation: ship Parakeet Ultra (NVIDIA's Parakeet v3, int8, run by FluidAudio on the Neural Engine) inside Duo.app. Keep Apple's recognizer for the live words while you speak, and replace them with Parakeet's text when you let go. Add Sparkle delta updates to `release.sh` in the same release, so the model costs a download once and nothing on later updates.**

1. **Accuracy: about 30 % fewer errors than macOS on technical prompts, and 25 % fewer on your own voice.**
   - On 160 Duo-style prompts (four synthetic voices), Apple's recognizer, set up exactly as Duo sets it up, got **13.5 %** of words wrong. Parakeet Ultra got **9.6 %**.
   - Ultra found 82 % of technical terms such as `duo2` and `SheetCenter`. Apple found 74 %.
   - On 170 of your own recorded takes (1,835 words of plain sentences), Apple got **5.7 %** wrong and Ultra **4.3 %**.
   - With a custom vocabulary (another 87 MB), Ultra drops to **7.3 %** on the technical prompts: **46 % fewer errors** than Apple, with 89 % of terms found. Apple's own vocabulary option still does nothing.
2. **Size: about 530 MB more to download.**
   - The DMG grows from 77 MB to about 610 MB, and Duo.app from 117 MB to about 720 MB.
   - Every first install and every manual DMG update pays that once.
3. **Updates: 2.8 MB, if we add Sparkle deltas.**
   - I measured a real 0.2.28 → 0.2.29 delta with the model bundled in both: **2.8 MB, the same as without the model**. Sparkle skips files that haven't changed.
   - Today `release.sh` writes no deltas, so without them every in-app update would be a 610 MB download.
   - Deltas don't help anyone who installs from the releases page (DL-114: everyone without admin rights, including your work Mac), anyone more than three versions behind, or the release that changes the model.
4. **Speed: faster than Apple once it's loaded.**
   - Parakeet returns text **44–62 ms** after you let go. Apple, as Duo runs it, takes **81–123 ms**. Both were measured under heavy load.
   - **Live words are the catch.** Parakeet Ultra doesn't stream: it gives text only after you let go. Apple's live words, as Duo configures it today, first appear **3.5 s** into speech. That lag is the one you noticed in DL-271.
   - The hybrid fixes both. Apple gives the live words, switched to its fast mode, which shows the first words at **1.1 s** but makes more errors (14.3 % vs 11.2 %). Parakeet then supplies the accurate final text, 50 ms after release.
5. **First use: about 1½ minutes of setup, once per Mac and again after each macOS update.**
   - Core ML compiles the model for the Mac's Neural Engine the first time it loads. A same-sized Parakeet took 97 s on this M6, and older Macs will take longer.
   - Apple's recognizer covers that window, so the mic works from the first press.
6. **Memory is small:** about 42 MB of footprint plus the 600 MB of weights, which macOS maps from disk on demand. An 8 GB M1 is fine. Nothing loads until the first mic press.
7. **Licences are easy.** The weights are CC-BY-4.0 (credit NVIDIA and Fluid Inference, and say they were converted). FluidAudio is Apache-2.0 and adds about 10 MB of code.

**What I would not ship:**
- **Whisper turbo** (632 MB build): best on the synthetic technical set at 7.1 %, but no better than Apple on your voice (5.9 %), ~0.5 s after release, and a **12-minute** first compile.
- **Small models** such as Whisper small.en (+167 MB): worse than Apple on your voice (6.7 %).
- **Redux** (2-bit, +311 MB): no better than Apple (13.0 %).
- **Phonon-2 and Bark 3**: find fewer terms than Apple.

**Decisions (cards at the end, recommendation first):**
- Q-556: which model, if any;
- Q-557: what you see while speaking;
- Q-558: Sparkle deltas;
- Q-559: custom vocabulary now or later;
- Q-560: Apple's fast live words.

---

## 1. What Duo runs today

`Sources/DuoKit/Voice/AppleRecognizer.swift` (DL-260):
- Duo uses `SpeechAnalyzer` with `SpeechTranscriber(locale:, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])`, fed live microphone buffers.
- It falls back to `SFSpeechRecognizer` (on device) only for languages SpeechTranscriber lacks.
- It passes no contextual strings, and macOS fetches the model itself through `AssetInventory`.

The bench's `apple-speechtranscriber` engine now uses exactly this configuration (stream mode for the headline number). October's stream runs used the `.progressiveTranscription` preset, which adds `.fastResults`. That one is kept as `apple-speechtranscriber-progressive`, and it behaves differently (F-696).

## 2. Candidates (November 2026)

Only engines Duo can run from Swift in-process, on the Neural Engine or GPU, count. Survey sources are linked in §7. New since October:
- **Parakeet Ultra:** FluidAudio's recommended v3, int8.
- **fluid-speech-pro:** a Parakeet v3 retrain from FluidVoice-Labs. Its Core ML build was published on 2026-11-13. It ranks 11th on the Open ASR Leaderboard v1.16.0 (6.06 average), the best open model under 1B there.
- **Phonon-2** and **Bark 3.0 Clean:** Parakeet retrains.
- **Nemotron Unified ASR 0.6B:** streaming plus batch, OpenMDW-1.1.
- **WhisperKit's quantised builds.** WhisperKit itself is still 1.1.1.
- **Moonshine** now has a Swift package, but it runs ONNX on the CPU, not Core ML. I didn't bench it again: it was 13.1 % in October.
- Nothing open-weight from OpenAI, Meta, Google or Kyutai since October. The big new models (Nemotron 3.5 Transcribe 34B, Granite 5 2B, Cohere, Qwen3-ASR 1.7B at 3–5 GB) are far too large to bundle.

| Engine | Runs on | Streams | Licence | Ships as |
|---|---|---|---|---|
| Apple SpeechTranscriber | system process | yes | system | 0 MB |
| Parakeet v3 / v2 (FluidAudio) | ANE | no | CC-BY-4.0 | 461 / 443 MB |
| **Parakeet Ultra** (int8 v3) | ANE | no | CC-BY-4.0 | 603 MB |
| fluid-speech-pro | ANE | no | CC-BY-4.0 | 622 MB |
| Parakeet Unified en (int8 offline / 7_1 stream) | ANE | stream encoder separate | CC-BY-4.0 | 586 / 580 MB |
| Nemotron Unified 0.6B (batch / 0.56 s stream) | ANE | yes | OpenMDW-1.1 | 598 / 592 MB |
| Nemotron streaming en 0.6B | ANE | yes | OpenMDW-1.1 | 598 MB |
| Parakeet Redux (2-bit) | GPU | no | CC-BY-4.0 | 384 MB |
| Phonon-2 (English) | ANE | no | CC-BY-4.0 | 361 MB |
| Bark 3.0 Clean | ANE | no | port says CC-BY-4.0; upstream card unreadable (gated), the survey saw CC-BY-NC | 427 MB |
| Whisper large-v3 turbo (WhisperKit) full / 632 MB build | ANE | no | MIT | 1,565 / 619 MB |
| distil-large-v3 594 MB / small.en 217 MB / base.en | ANE | no | MIT | 570 / 210 / 142 MB |
| CTC-110M (custom vocabulary for the Parakeets) | ANE | — | CC-BY-4.0 | +98 MB |

## 3. Measurements

**Bench:** the October harness, extended rather than rebuilt.
- FluidAudio is bumped to v0.18.3 (`c8b41f98`), and October's numbers for Apple, v3, v2, Redux and Unified reproduce exactly. WhisperKit is 1.1.1.
- New engines, aggregate results and the method changes are in `voice-input-bench/` (`swift/README.md`, `SPEC.md`, `runnov.sh`, `results/summary-nov-*.json`).
- WER\* counts the fewer errors of the spoken form ("package dot swift") and the written form (`Package.swift`). wWER counts against the written form only. The 95 % CI is a clip bootstrap.

**Machine:** Apple M6 Mac mini, 32 GB, macOS 27.0. **Load averages were 13–57 during every timing hold**: other projects' VMs, browsers and links were running outside the lock. Treat the milliseconds as upper bounds. The ratios between engines held across two passes. Accuracy doesn't depend on load.

### 3.1 Accuracy: 160 synthetic Duo-style prompts

40 prompts × 4 `say` voices; 23 prompts technical, 17 plain.

| Engine (mode) | WER\* | 95 % CI | Plain | Technical | Terms found | wWER |
|---|---|---|---|---|---|---|
| **Apple, as Duo runs it (stream)** | **13.5 %** | 11.3–15.9 | 6.3 % | 18.2 % | 73.7 % | 24.0 % |
| Parakeet v3 | 10.2 % | 8.1–12.5 | 2.4 % | 15.4 % | 83.3 % | 21.3 % |
| Parakeet v2 | 9.9 % | 8.0–11.8 | 2.4 % | 14.8 % | 81.6 % | 19.1 % |
| **Parakeet Ultra** | **9.6 %** | 7.7–11.6 | 2.0 % | 14.6 % | 81.6 % | 18.7 % |
| fluid-speech-pro | 9.9 % | 7.7–12.1 | 2.1 % | 15.0 % | 82.5 % | 19.4 % |
| Parakeet Unified (batch) | 9.5 % | 7.5–11.4 | 2.6 % | 14.0 % | 83.8 % | 18.4 % |
| Nemotron Unified (batch) | 10.4 % | 8.4–12.4 | 2.6 % | 15.5 % | 80.7 % | 19.0 % |
| Parakeet Redux | 13.0 % | 10.7–15.4 | 6.2 % | 17.4 % | 73.2 % | 22.0 % |
| Phonon-2 | 11.8 % | 9.6–14.1 | 6.0 % | 15.6 % | 69.3 % | 27.7 % |
| Bark 3.0 Clean | 11.8 % | 9.6–14.4 | 6.6 % | 15.3 % | 65.4 % | 30.9 % |
| Whisper turbo (1.5 GB) | 7.6 % | 5.7–9.5 | 2.0 % | 11.2 % | 86.0 % | 15.9 % |
| **Whisper turbo 632 MB** | **7.1 %** | 5.4–9.1 | 1.8 % | 10.6 % | 85.1 % | 15.3 % |
| Whisper distil-large-v3 594 MB | 12.6 % | 10.4–14.9 | 6.2 % | 16.8 % | 74.6 % | 22.6 % |
| Whisper small.en 217 MB | 9.9 % | 7.9–12.0 | 2.6 % | 14.7 % | 79.4 % | 16.0 % |
| Whisper base.en | 10.9 % | 8.9–13.2 | 5.9 % | 14.2 % | 80.3 % | 18.4 % |
| *Streaming engines* | | | | | | |
| Parakeet Unified 7_1 (stream) | 11.5 % | 9.5–13.5 | 3.5 % | 16.7 % | 82.0 % | 20.9 % |
| Nemotron Unified 0.56 s (stream) | 11.9 % | 9.7–14.1 | 3.9 % | 17.1 % | 79.8 % | 22.0 % |
| Nemotron streaming en (stream) | 12.4 % | 10.2–14.7 | 4.7 % | 17.4 % | 68.9 % | 27.9 % |

**Custom vocabulary** (the 26 terms in `context-terms.txt`; FluidAudio's CTC-110M rescoring, +98 MB on disk, +87 MB in the DMG):

| Engine + vocabulary | WER\* | Terms found |
|---|---|---|
| Apple (`contextualStrings`) | 13.5 %, no change (October) | 73.7 % |
| Parakeet v3 | 7.4 % | 89.0 % |
| Parakeet Ultra | 7.3 % | 88.6 % |
| fluid-speech-pro | 7.1 % | 89.0 % |

### 3.2 Accuracy: your own voice, plain speech

These are 170 clips of your recorded takes (1,835 words), read in place from geoff-voice and never copied. Only these aggregates leave the scratch folder, and the per-clip text has been deleted. The set differs from October's 58 takes, so the numbers don't compare with that table.

| Engine | WER |
|---|---|
| fluid-speech-pro | 4.1 % |
| **Parakeet Ultra** | **4.3 %** |
| Nemotron Unified (batch) | 4.3 % |
| Parakeet v3 | 4.4 % |
| Phonon-2 | 5.0 % |
| Parakeet Redux | 5.6 % |
| **Apple, as Duo runs it** | **5.7 %** |
| Whisper turbo 632 MB | 5.9 % |
| Whisper small.en 217 MB | 6.7 % |

One error is 0.05 points here. Ultra's gap to Apple (1.4 points) is about 26 fewer wrong words in 1,835. The Parakeets are within a word or two of each other.

The caveat from October still holds: the technical set is synthetic, clean audio. Your takes are real but plain sentences. No set here is your real dictated prompts through a real mic in a real room.

### 3.3 Latency

The lat40 set: each prompt once, voices rotated. Values are from two passes under the exclusive lock: median / p90 time from the end of speech to the final text.

| Engine | Pass 1 | Pass 2 | First live words | Warm load |
|---|---|---|---|---|
| **Apple, as Duo runs it (stream)** | 123 / 202 ms | 81 / 102 ms | **3.49 s** | 0.08 s |
| Apple with fast results (progressive preset) | — | 126 / 219 ms | **1.14 s** | 0.07 s |
| Apple batch | 127 / 159 | 109 / 150 | — | 0.10 s |
| Parakeet v3 | 60 / 79 | 48 / 76 | — | 0.39 s |
| **Parakeet Ultra** | **62 / 83** | **44 / 50** | — | 0.37 s |
| fluid-speech-pro | 56 / 78 | 42 / 48 | — | 0.37 s |
| Nemotron Unified (batch) | 87 / 109 | 56 / 67 | — | 0.38 s |
| Parakeet Unified 7_1 (stream) | 55 / 69 | 54 / 68 | 1.25 s | 0.46 s |
| Nemotron Unified 0.56 s (stream) | 41 / 62 | 42 / 55 | 1.15 s | 0.63 s |
| Nemotron streaming en (stream) | 35 / 65 | 55 / 81 | 0.66 s | 1.34 s |
| Whisper turbo 632 MB | 450 / 515 | 483 / 537 | — | 4.0 s |
| Whisper small.en 217 MB | 335 / 416 | 248 / 304 | — | 1.9 s |
| Whisper base.en | 173 / 226 | 88 / 104 | — | 1.1 s |

In October, on a quiet Mac, Parakeet v3 took 28 ms and Apple batch 65 ms. Today's numbers are about twice that for both, from the load.

**First load (Core ML compile for this Mac), after download** (F-697):

| Engine | First load |
|---|---|
| fluid-speech-pro | 97 s |
| Nemotron Unified batch / stream | 192 s / 38 s |
| Phonon-2 | 245 s |
| Whisper turbo 632 MB | **716 s** (12 min) |
| Whisper distil / small.en / base.en | 79 s / 60 s / 41 s |
| Parakeet v3 (October, with download) | 63 s |

Parakeet Ultra and Bark loaded in under a second because this Mac had already compiled those weights for another session. Their cold compile isn't measured. Ultra is the same architecture and size as fluid-speech-pro, so expect about 1½ minutes on an M6 under load, and more on an M1–M3.

### 3.4 Memory

Peak footprint and RSS of the bench process (pass 2). Neither includes Neural Engine memory, or Apple's model, which runs in a system process.

| Engine | Footprint | RSS |
|---|---|---|
| Apple (in Duo's process) | 7.5 MB | 20 MB |
| Parakeet v3 / Ultra / speech-pro | 41 / 42 / 63 MB | 81 / 87 / 88 MB |
| Parakeet Redux (GPU) | 201 MB | 404 MB |
| Whisper turbo 632 MB | 237 MB | 267 MB |
| Whisper small.en | 150 MB | 136 MB |

The weights (about 600 MB) are memory-mapped from the bundle and paged by macOS. On an 8 GB M1 this is comfortable. The model should load at the first mic press and unload after a few idle minutes.

### 3.5 Size of what would ship

These are only the files the engine loads (`du`), and the same folder compressed in a UDZO DMG, as `release.sh` makes them.

| Engine | On disk | Adds to the DMG |
|---|---|---|
| Parakeet v3 | 461 MB | 453 MB |
| Parakeet v2 | 443 MB | 438 MB |
| **Parakeet Ultra** | **603 MB** | **534 MB** |
| fluid-speech-pro | 622 MB | 555 MB |
| Parakeet Unified offline / 7_1 stream | 586 / 580 MB | 523 / 521 MB |
| Nemotron Unified batch / stream | 598 / 592 MB | 528 / 526 MB |
| Parakeet Redux | 384 MB | 311 MB |
| Phonon-2 | 361 MB | 253 MB |
| Bark 3.0 Clean | 427 MB | 297 MB |
| Whisper turbo full / 632 MB | 1,565 / 619 MB | 1,439 / 465 MB |
| Whisper distil 594 / small.en 217 / base.en | 570 / 210 / 142 MB | 491 / 167 / 129 MB |
| + CTC-110M vocabulary | 98 MB | 87 MB |
| + FluidAudio code | ~10 MB | ~4 MB |

The 6-bit and 8-bit weights hardly compress. The 2-bit Redux and the sparse Phonon/Bark builds compress to 70–80 %.

## 4. What bundling costs

### 4.1 App and DMG

Measured by building Duo 0.2.29 with each model folder in `Contents/Resources/Models/`:

| | Duo.app | DMG |
|---|---|---|
| Today (0.2.29) | 116.8 MB | 77.3 MB (81 MB as released) |
| + Parakeet v3 | 577.8 MB | 529.4 MB |
| + Parakeet Ultra (from §3.5) | ~720 MB | ~610 MB |
| + Ultra + vocabulary | ~820 MB | ~700 MB |
| + Redux | 327.0 MB | 248.6 MB |

### 4.2 Sparkle full and delta updates (F-695)

- **Today:** `release.sh` writes an appcast with one enclosure, the DMG. Every in-app update downloads the whole DMG, so with Ultra each update is about 610 MB. This was the old research's reason not to bundle.
- **Deltas remove it for in-app updates.** I built Duo 0.2.28 and 0.2.29 from their released DMGs, both with Parakeet v3 inside, and ran Sparkle 2.10.0's `BinaryDelta create` (the official tarball, hash-checked against `Vendor/Sparkle/README.md`). **The delta was 2.80 MB with the model and 2.80 MB without it.**
  - `SUBinaryDeltaCreate` skips any file whose contents are unchanged.
  - Re-signing doesn't touch the model's bytes: the signature only lists their hashes in `CodeResources`.
  - Sparkle applies a delta to the installed app whatever the full enclosure is (DMG included). If the delta fails, it falls back to the full download.
- **Who still downloads the full 610 MB:**
  - every new install;
  - every manual update from the releases page. Under DL-114 that's every Mac where Sparkle would ask for an admin password, including your work Mac;
  - anyone further behind than the deltas we publish;
  - everyone on the release that changes the model. A changed weight file is bsdiffed whole, and the Neural Engine compile reruns.
- **What `release.sh` needs** (about 40 lines; no CI):
  1. Keep Sparkle's `BinaryDelta` in `~/.duo-signing/sparkle-bin/` beside `sign_update`.
  2. After notarizing, for each of the last 3 releases: download its DMG with `gh release download`, mount it, copy the app out, and run `BinaryDelta create --version=4 old.app new.app Duo-<build>-from-<oldbuild>.delta`. Format 4 needs Sparkle 2.7 or later, and every Duo since Sparkle went in has 2.10. Then check it with `BinaryDelta apply` into a scratch copy and compare the result to the new app.
  3. Sign each delta with `sign_update`, and add a `<sparkle:deltas>` block to the item, one `<enclosure sparkle:deltaFrom="<oldbuild>" …>` per delta. `<oldbuild>` is that release's `sparkle:version`, the `git rev-list --count` of its tag.
  4. Upload the `.delta` files with the DMG.
  - `generate_appcast` can do steps 2 and 3, but it wants every old archive in one folder and writes its own appcast. Calling `BinaryDelta` directly fits the hand-written appcast `release.sh` already has.

### 4.3 Signing, notarization, Gatekeeper

- **A `.mlmodelc` is data.** It contains no Mach-O files (checked), so `codesign` seals it as a resource and Hardened Runtime has no say over it. Core ML loads it with `MLModel(contentsOf:)` like any file. Duo must never write into the bundle; the compiled cache lives in Core ML's own cache folder.
- **Signing time:** ad-hoc signing went from 0.46 s to 1.50 s with v3 inside, and `codesign --verify --deep --strict` from 0.18 s to 0.61 s, warm. Gatekeeper's first-launch check of a downloaded app hashes the whole bundle the same way, so expect roughly half a second to a few seconds more on a first launch from a cold disk.
- **Notarization uploads more.** `release.sh` notarizes twice, the app as a zip and then the DMG. For 0.2.29 each took about 50 s at about 80 MB. With Ultra, each upload is about 610 MB. I didn't submit a test, so the extra time isn't measured; it's mostly upload time, likely a few minutes per release.
- **Licences and attribution:**
  - Parakeet / Ultra / speech-pro: CC-BY-4.0. Credit NVIDIA (and Fluid Inference or FluidVoice-Labs for the conversion), link the licence, and say the weights were converted.
  - FluidAudio: Apache-2.0. Ship its LICENSE and NOTICE.
  - Nemotron: OpenMDW-1.1. Attribution, permissive.
  - Whisper and WhisperKit: MIT.
  - This means an Acknowledgements entry in About and a LICENSE file in `Resources/Models/<model>/`. Bark's upstream licence is unclear, one more reason not to pick it.

### 4.4 Older Macs

- Every Mac Duo runs on (macOS 26+, Apple silicon) has a Neural Engine. M1's is about 11 TOPS, against far more on this M6. Parakeet does a 4-second prompt about 80× faster than real time here, so even several times slower it stays well under human notice after release.
- **Not measured on an M1.** The one-off compile grows the most on older chips: minutes, not seconds.
- No smaller fallback model is needed. Apple's recognizer is the fallback, at zero size. Nothing smaller than Parakeet beats Apple on your voice: small.en and base.en lose, and Redux ties.

### 4.5 Launch and first use

- Model files in `Resources` cost nothing at launch. Duo should load the model only at the first mic press, never at launch, and never in a scripted or isolated run unless a test asks for it.
- The first load compiles for the Neural Engine (§3.3: about 1½ min), and so does the first load after every macOS update, because the OS update invalidates Core ML's cache.
  - With the hybrid (Q-557 A), the mic works at once on Apple's recognizer while Parakeet compiles in the background, and takes over when it's ready. A small "better recognition ready" moment is optional.
  - macOS 27's Core AI can compile ahead of time (`AIModel.specialize`, AOT at build time), and FluidInference already publishes `.aimodel` builds for some models. That could shorten the first use; it's ENH-354's second part, not v1.

## 5. Ranking

| Rank | Option | Size (DMG) | Errors vs Apple: technical / your voice | After release | Live words | Verdict |
|---|---|---|---|---|---|---|
| **1** | **Parakeet Ultra + Apple's live words** | **+534 MB** | **−29 % / −25 %** | ~50 ms | Apple's, 1.1 s with fast results | **Recommended.** FluidAudio's first-party, recommended model. |
| 1b | + custom vocabulary | +621 MB | −46 % / (not measured) | +~120 ms | same | Later, with a project vocabulary (Q-559, ENH-354) |
| 2 | Parakeet v3 + Apple's live words | +453 MB | −24 % / −23 % | ~50 ms | same | Within noise of Ultra, 80 MB smaller. The pick if size matters more. |
| 3 | fluid-speech-pro | +555 MB | −27 % / −28 % | ~45 ms | same | A hair better on your voice; published two days ago by a third party. Revisit in a month. |
| 4 | Nemotron Unified streaming only | +526 MB | −12 % / (batch −25 %) | ~45 ms | its own, 1.15 s | Only if Apple's live words must go too. |
| 5 | Whisper turbo 632 MB | +465 MB | −47 % / +4 % | ~470 ms | none | Best on synthetic jargon, no gain on your voice, slow, 12-min compile |
| 6 | Whisper small.en 217 MB | +167 MB | −27 % / +18 % | ~250–330 ms | none | Smallest real gain on jargon, worse on your voice |
| — | Redux, Phonon-2, Bark 3, distil | +250–490 MB | ~Apple or worse on terms | | | No |
| — | Apple only (today) | 0 | — | 81–123 ms | 3.5 s (1.1 s with fast results) | The baseline, and the fallback in every option |

The trade-off in one line: **about +530 MB once, 2.8 MB per update with deltas: a quarter to a third fewer wrong words than macOS, almost half with a vocabulary, and the final text a little faster.**

## 6. Decisions for Geoff (console-ready)

**Q-556: Ship a speech model inside Duo?**
- **A (recommended): Yes, Parakeet Ultra.** About 530 MB more to download, about 30 % fewer errors than macOS on technical prompts and 25 % fewer on your voice. Supersedes DL-260.
- B: Yes, Parakeet v3. 450 MB more, the same accuracy within noise.
- C: Yes, Whisper small.en. Only 170 MB more and better on jargon, but worse than macOS on your voice and slower.
- D: No. Keep Apple's recognizer and only make its live words faster (Q-560).

**Q-557: What you see while speaking, with a bundled model**
- **A (recommended): Apple's live words while you speak, replaced by Parakeet's text when you let go** (+~50 ms). The mic works on first press while Parakeet compiles, and Apple remains the fallback.
- B: Parakeet only. No live words, just the level bars (DL-271), with the text appearing on release.
- C: A streaming bundled model (Nemotron Unified) for both. Its own live words from 1.15 s, 11.9 % errors, no Apple at all.

**Q-558: Sparkle delta updates**
- **A (recommended): Add deltas to `release.sh` in the release that bundles the model,** from the last 3 releases. In-app updates stay about 3 MB; new installs and releases-page updates still download the full DMG.
- B: Add them now, before any model. Smaller updates today (3 MB vs 81 MB).
- C: No deltas. Every update is the full DMG, about 610 MB with a model.

**Q-559: Custom vocabulary (another 87 MB)**
- **A (recommended): Later, when Duo can take the vocabulary from the project** (file names, symbols, session names; ENH-354). It cuts errors from 9.6 % to 7.3 % on the test prompts.
- B: Ship it now with a fixed list (Duo and Claude terms).
- C: Not at all.

**Q-560: Apple's live words appear 3.5 s into speech**
- **A (recommended): Turn on Apple's fast results for the live words whenever Parakeet gives the final text.** Words appear from 1.1 s. Keep today's slower, more accurate setting when Apple gives the final text (the fallback, or if Q-556 is D).
- B: Fast results always. Words from 1.1 s, but Apple-only text has more errors (14.3 % vs 11.2 % on 40 prompts).
- C: Leave it as it is.

## 7. Evidence

- **Records:** F-694 (the November bench), F-695 (Sparkle delta measured), F-696 (Duo's Apple configuration: 3.5 s to first words), F-697 (first-load compile and the Core ML cache); Q-556 to Q-560 (§6); ENH-354 (project vocabulary and ahead-of-time compile).
- **Bench:** `voice-input-bench/` at FluidAudio `c8b41f98eae668794dd0083bbe028fe7e6585051` (v0.18.3, `traits: []`), WhisperKit 1.1.1.
  - Aggregates: `results/summary-nov-synth.json`, `summary-nov-lat40.json` (both passes, with `uptime` per hold), `summary-nov-sizes.json`, `summary-nov-loads.json`, and `summary-nov-takes.json` (aggregates only).
  - Per-clip synthetic results: `~/Library/Caches/duo-voice-input/results/nov*/`, outside git.
  - Takes per-clip output was deleted after scoring.
- **Models:**
  - `FluidInference/parakeet-ultra-coreml`;
  - `FluidVoice-Labs/fluid-speech-pro-coreml` (main as of 2026-11-14; needs a `JointDecisionv3.mlmodelc` symlink to load through FluidAudio);
  - `FluidInference/phonon-2-coreml`;
  - `FluidInference/bark-3.0-coreml` (bark-3.0-clean);
  - `FluidInference/nemotron-labs-unified-asr-0.6b-coreml` (en, int8; stream encoder 70_2_5);
  - `argmaxinc/whisperkit-coreml` folders `openai_whisper-large-v3-v20240930_turbo_632MB`, `distil-whisper_distil-large-v3_594MB`, `openai_whisper-small.en_217MB`, `openai_whisper-base.en`.
  - Licences read from each Hugging Face card's metadata (API, 2026-11-14).
- **Bundling measurements:**
  - 0.2.28 and 0.2.29 DMGs from GitHub releases;
  - Sparkle 2.10.0 tarball, SHA-256 `c2bf58aa…6da0c` (matches Vendor);
  - `hdiutil create -format UDZO -fs HFS+` as in `release.sh`;
  - scratch folders under the job's tmp, outside the repo.
- **Sources** (opened by the survey unless marked):
  - [Open ASR Leaderboard config v1.16.0, 2026-11-13](https://hf-audio-open-asr-leaderboard.hf.space/config). Its averages changed method since October, so October's leaderboard numbers don't compare.
  - [FluidAudio releases](https://github.com/FluidInference/FluidAudio/releases) and [CustomVocabulary.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/CustomVocabulary.md)
  - [fluid-speech-pro card](https://huggingface.co/FluidVoice-Labs/fluid-speech-pro)
  - [Phonon-2.5 English card](https://huggingface.co/FermionResearch/Phonon-2.5-English)
  - [Nemotron Unified Core ML](https://huggingface.co/FluidInference/nemotron-labs-unified-asr-0.6b-coreml)
  - [WhisperKit releases](https://github.com/argmaxinc/WhisperKit/releases)
  - [moonshine](https://github.com/moonshine-ai/moonshine)
  - [Core AI: model specialization and caching](https://developer.apple.com/documentation/coreai/managing-model-specialization-and-caching.md)
  - [TypeWhisper benchmark PR #13](https://github.com/TypeWhisper/typewhisper-benchmark/pull/13): an independent M5 Pro run with Apple at 7.5 % vs Ultra 5.5 % in English, and 15.4 vs 7.4 on hard terms. It agrees with this bench.
  - Sparkle [delta updates](https://sparkle-project.org/documentation/delta-updates/) and [SUBinaryDeltaCreate.m](https://github.com/sparkle-project/Sparkle/blob/2.10.1/Autoupdate/SUBinaryDeltaCreate.m)
- **Not measured:**
  - Ultra's and Bark's cold compile (cache already warm);
  - any M1–M3 Mac;
  - real microphone audio, and your real dictated prompts;
  - notarization time with a model inside (no test submission);
  - quiet-machine latency (load 13–57 throughout);
  - Moonshine's Swift package (CPU/ONNX, 13.1 % in October);
  - the 34B, 2B and 1.7B models (too large to bundle).
