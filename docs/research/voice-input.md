# Voice input for Duo: on-device dictation into chat and the terminal

Status: research, 2026-10-12. Research session for the director; Geoff asked for it on 2026-10-12. Records: ENH-71; Q-178 to Q-182.

## Summary for Geoff

**Recommendation: build voice input on Parakeet TDT 0.6B v3, running on device through FluidAudio (Core ML). Duo downloads the model on first use from our own GitHub release, pinned by hash. Until it arrives, Apple's built-in SpeechTranscriber does the job.**

1. **Open weights vs macOS: yes, meaningfully better on technical prompts. On plain English it's a tie.**
   - On 160 Duo-style prompts, Apple's best on-device recognizer (SpeechTranscriber, macOS 26) got 13.5 % of words wrong. Parakeet v3 got 10.2 %, and 8.3 % with a custom-vocabulary boost that Apple's new API ignores.
   - Parakeet found 89 % of the technical terms (`duo2`, `SheetCenter`, `ENOENT` …) against Apple's 74 %.
   - Whisper turbo is a little more accurate (7.4 %) but 10× slower and 3× bigger.
   - On Geoff's own voice reading plain sentences, Apple and Parakeet both scored 2.2 %.
   - No engine writes `--model` or `scripts/release.sh` from speech. That's a separate formatting step (Q-179); for chat prompts it barely matters, since Claude understands "dash dash model".
2. **Speed is fine for every candidate on an M3-or-later Mac.**
   - Parakeet returns text **28 ms** after you let go of the key; Apple takes 65–105 ms.
   - Streaming partials start ~0.65–1.2 s into speech for every engine that has them.
   - Measured on an M6 Mac mini. An M3 MacBook Air might be 3–4× slower and would still be well under human notice.
3. **Vendoring: don't put the model in git or in the app.**
   - MMM's split-file trick works: 45 MiB parts, rejoined and SHA-checked in 0.5 s, a 209 MB shallow clone in 5 s. But Duo is installed from a DMG, so a model in git doesn't reach users.
   - Inside Duo.app, every Sparkle update would re-download ~450 MB, because Duo has no delta updates.
   - Git LFS is metered, and the owner pays for every clone.
   - A **pre-release GitHub asset** has no bandwidth limit, comes from the same host the work Mac already downloads Duo's DMG from, and keeps the Sparkle feed untouched.
   - Hugging Face may be blocked on managed networks.
4. **Licences are easy.** Parakeet and its Core ML conversion are CC-BY-4.0 (credit NVIDIA and Fluid Inference, say it was converted). FluidAudio is Apache-2.0 and adds ~10 MB to the app.
5. **Integration needs:**
   - one entitlement (`com.apple.security.device.audio-input`), since release builds sign with none today, plus a usage string;
   - the mic prompt only on the user's first press, after a Duo sheet explains it;
   - text pasted into the terminal as a bracketed paste (never pressing Return), and inserted at the caret in chat.

**Needs Geoff:**
- Q-178: confirm the engine and how it ships;
- Q-180: a one-minute check on the work Mac once a build has it;
- Q-181: try fn-fn system Dictation in Duo today; it may already work as a baseline;
- Q-182: the hold-to-talk key.

Before building, re-run the bench (`docs/research/voice-input-bench/`) on ~40 of Geoff's real dictated prompts, recorded with his OK.

---

## 1. Shipping a model: the options and their numbers

### 1.1 What mini-meeting-minutes does

MMM vendors every model in git, so a clone is all it needs and it downloads nothing at runtime (`Models/README.md`):

| Model | Folder | On disk | Licence |
|---|---|---|---|
| Parakeet Redux (2-bit/ternary retrain of Parakeet TDT 0.6B v3, Core ML by FluidInference) | `parakeet-redux/` | 202 MB of model (the encoder `weight.bin` is 182,389,312 B), stored twice: once as parts, once reassembled | CC-BY-4.0 |
| pyannote community-1 diarization (Core ML) | `speaker-diarization/` | 21 MB | CC-BY-4.0 |
| Silero VAD v6.2.1 | `silero-vad/` | 1 MB | MIT |
| LocalVQE v1.3 (echo cancellation) | `localvqe/` | 19 MB | Apache-2.0 |

**The split.** `scripts/vendor_models.py` downloads pinned Hugging Face revisions. It cuts any file over `PART_SIZE = 45 * 1024 * 1024` ("below GitHub's 50 MiB warning threshold") into `weight.bin.part-000…003`: three parts of 47,185,920 B and one of 40,831,552 B. Each part is committed. It writes `manifest.json` with a SHA-256 for every file and the part list for split ones, and adds the reassembled path to `.gitignore`.

**Reassembly.** On first run, `ModelStore.prepare()` (`Sources/MinutesCore/Models/ModelStore.swift`) does this:
1. Memory-maps each part and joins the parts into `weight.bin.reassembling`, hashing as it goes.
2. Checks the result against the manifest's SHA-256.
3. Renames the file into place and writes a `weight.bin.sha256` stamp, so the join isn't repeated.
4. `mmm doctor --full` re-verifies every file.

**What it costs**, measured tonight on this Mac and network (GitHub, 2026-10-12):

| | Number |
|---|---|
| Shallow clone (`git clone --depth 1`, what `install.sh` does) | **5.1 s**; `.git` 209 MB; checkout 461 MB on disk (`install.sh` says "about 270 MB") |
| Full clone (27 commits) | 5.8 s; `.git` 225 MB |
| Packed size of the four encoder parts | 143.6 MB for 182.4 MB: ternary weights compress to about 79 % |
| Join plus SHA-256 of the 182 MB encoder | **0.5 s** |
| On-disk cost after first run | the encoder exists twice (parts and joined): +182 MB |
| Each model update | adds its full packed size to history forever ("update deliberately", `Models/README.md`) |

Duo is in a different position from MMM. MMM is installed *by cloning*. Duo is installed from a DMG, so a model in Duo's repo still has to reach users some other way (inside the app or as a download). Committing it only serves builds.

### 1.2 GitHub's limits (docs opened 2026-10-12)

| Limit | Value | Source |
|---|---|---|
| Per-file hard limit | "GitHub blocks files larger than 100 MiB" | [About large files on GitHub](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github) |
| Warning | "larger than 50 MiB, you will receive a warning from Git" | same |
| Browser upload | 25 MiB | same |
| Repo size | "ideally less than 1 GB, and less than 5 GB is strongly recommended"; 10 GB on disk is the hard ceiling | same; [Repository limits](https://docs.github.com/en/repositories/creating-and-managing-repositories/repository-limits) |
| Push | 2 GB per push | Repository limits |
| LFS quota (Free/Pro) | 10 GiB storage and 10 GiB bandwidth a month, then metered; the repo owner pays for everyone's downloads ("Forking and pulling a repository counts against the parent repository's bandwidth usage") | [Git LFS billing](https://docs.github.com/en/billing/concepts/product-billing/git-lfs) |
| LFS per-file limit | 2 GB (Free/Pro) | [About Git LFS](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-git-large-file-storage) |
| LFS in source zips | "By default, Git LFS objects are not included in these archives" | [LFS objects in archives](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/managing-git-lfs-objects-in-archives-of-your-repository) |
| Release asset | "Each file included in a release must be under 2 GiB"; up to 1000 assets; "There is no limit on the total size of a release, nor bandwidth usage" | [About releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) |

The LFS per-GiB overage price ($0.07 a GiB-month for storage, $0.0875 a GiB for bandwidth) came only from a search summary of GitHub's billing pages. I couldn't open a page that shows it.

### 1.3 The options compared

Sizes assume one English model. The Parakeet TDT 0.6B v3 Core ML set is 461–469 MB on disk (FluidAudio's 6-bit encoder, measured). Parakeet Redux is 202 MB. The Unified streaming model is about 0.6 GB per encoder variant.

| Option | Users get it how | Size cost | Update cost | Work Mac | Verdict |
|---|---|---|---|---|---|
| **A. In duo-v2's git, split (MMM's way)** | Not at all by itself: Duo ships as a DMG, so it still needs B, D or E | +~0.4 GB packed per model version, forever. Duo's history passes GitHub's 1 GB "ideal" after two versions. Every contributor and worktree checkout carries it, and Duo has ~10 worktrees at a time | every model update adds its full size | n/a | **No.** It costs the most and doesn't reach users. |
| **B. Git LFS** | Same as A: LFS is for builders, not users | Free tier is 10 GiB bandwidth a month. A ~0.45 GB model clone uses ~2 % of that, so ~20 fresh clones or CI runs a month exhaust it; then metered | same as A | n/a | **No.** It's metered and the owner pays for every clone. |
| **C. GitHub release asset** | The app downloads it (see E) | 2 GiB per asset, no bandwidth limit, no repo growth | upload a new asset only when the model changes | Same host as Duo's DMG and Sparkle feed (`objects.githubusercontent.com`), which the work Mac reaches today | **Yes**, as the host for E. |
| **D. Inside Duo.app** | Every DMG and every Sparkle update | DMG 74 MB → ~450 MB (6-bit weights hardly compress; the ternary encoder packs at 79 %). Notarization uploads the whole DMG | **Every update re-downloads it.** `release.sh` writes no Sparkle deltas today. Deltas would make unchanged files nearly free, but they need the old app kept per release and fall back to the full download | Works, but each manual update on the work Mac (admin password, DL-114) is a ~450 MB DMG | **No**, unless the model is tiny. |
| **E. Downloaded on first use** | Duo fetches a pinned, SHA-256-checked archive on the first mic press, into `~/Library/Application Support/Duo/Models/<name>@<sha>/` | 0 in the app; ~0.45 GB once per Mac | none, until Duo pins a new model | From **our GitHub release** (C): yes, same host as the DMG. From **Hugging Face**: unknown. Managed networks often block it, and allowing `huggingface.co` isn't enough, because files redirect to `cas-server.xethub.hf.co`, `cdn-lfs-us-1.hf.co` and others ([HF downloading docs](https://huggingface.co/docs/hub/en/models-downloading)) | **Yes: E from C.** |
| *Native (Apple SpeechTranscriber)* | macOS downloads Apple's model through `AssetInventory`, with no UI (seen tonight) | 0 for Duo; Apple's model "does not increase the download or storage size of your application, nor … the run-time memory size" ([WWDC25-277](https://developer.apple.com/videos/play/wwdc2025/277/)) | Apple updates it | Unknown: the asset comes from Apple's servers, and management could block it (Q-180) | Zero shipping cost. |

**Details that matter for E from C:**

- **Don't let a model release become "latest".** Duo's Sparkle feed is `releases/latest/download/appcast.xml`, and "latest" is the newest non-prerelease. Publish models as a **pre-release** with a tag like `models/parakeet-v3-r1`, or in a separate repo (`dudgeon/duo-models`), so the app feed never moves. A separate repo also keeps model releases out of the app's release list.
- **Pin by hash in the app.** Duo carries the URL, byte size and SHA-256 of one zip (the `.mlmodelc` folders plus vocab and licence). It downloads to `*.download`, checks the hash, unzips into a versioned folder, then swaps it in. That's MMM's `ModelStore` check, with a download instead of a git clone.
- **Signing and notarization.** A downloaded `.mlmodelc` is data: Core ML loads it with `MLModel(contentsOf:)` with no code signature, and Duo's Hardened Runtime doesn't sign data files. A model inside the bundle would be sealed as resources by the app's signature. Code signing "seal[s] all files in a bundle" ([TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)), so the bundle option needs nothing special either. Just don't write into the bundle after signing. Core ML compiles for the device on first load: measured tonight, v3's first load took 63 s with download and compile, and a warm load takes 0.4–0.6 s. Duo should warm it in the background after download, not on the first key press.
- **Background Assets** (macOS 26) would be Apple's way to do this, but Apple-hosted packs are for "apps distributed through TestFlight and the App Store" ([App Store Connect Help](https://developer.apple.com/help/app-store-connect/manage-asset-packs/overview-of-apple-hosted-asset-packs)). Duo is Developer ID, and self-hosted Background Assets needs an extension. That's more moving parts than a URLSession download for one file.
- **Offline and isolated runs.** Scripted and isolated Duos use their own `DUO_SUPPORT_DIR`, so they'd download their own copy. For checks, set a `DUO_MODELS_DIR` pointing at a shared, already-verified cache, like `~/Library/Caches/duo-voice-input/`. No test should depend on the network.

### 1.4 Licences and attribution

| Model / code | Licence | What Duo must do |
|---|---|---|
| Parakeet TDT 0.6B v2, v3 (NVIDIA) | CC-BY-4.0 ([v3 card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)) | Credit NVIDIA, link the licence, and say it was converted (to Core ML), in About/Acknowledgements and in the model folder |
| FluidInference Core ML conversions | v2: CC-BY-4.0. The v3 card's metadata says CC-BY-4.0 but its text says Apache 2.0 ([card](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml)) | Treat it as CC-BY-4.0 (the stricter reading) and credit Fluid Inference |
| Parakeet Redux (moondream) | CC-BY-4.0 (MMM `Models/README.md`) | As MMM does |
| FluidAudio SDK | Apache-2.0 ([repo](https://github.com/FluidInference/FluidAudio)) | Ship its LICENSE/NOTICE text |
| Whisper large-v3-turbo / WhisperKit | MIT / MIT | Licence text |
| Moonshine (English and streaming) | MIT. Only legacy non-English models are under the non-commercial Community License ([LICENSE](https://raw.githubusercontent.com/moonshine-ai/moonshine/main/LICENSE)) | Licence text |
| Kyutai STT | CC-BY-4.0 | Credit |
| Voxtral Mini, Granite Speech | Apache-2.0 | Licence text |
| Canary 1B flash / Canary-Qwen 2.5B | CC-BY-4.0 | Credit |
| Silero VAD | MIT | Licence text |
| Apple SpeechTranscriber | System framework | Nothing |

Everything here is usable in a free OSS app (and see the NC-licences note in memory: even NC would be acceptable). CC-BY's only real cost is an acknowledgements screen.

**Recommendation for §1: E from C.**
- Duo pins one zip per model: URL, size and SHA-256.
- The zip is published as a pre-release asset (`models/parakeet-v3-r1`, in duo-v2 or a `duo-models` repo) so it can't become "latest".
- It downloads on the first mic press (or from Settings), into `~/Library/Application Support/Duo/Models/`, and is verified, unzipped and compiled in the background.
- Apple's SpeechTranscriber covers the minute before it's ready, and any Mac where the download is blocked.
- Nothing large goes into git, the DMG or Sparkle updates. A model change is a new asset plus a new pin in a normal release.

---

## 2. Native versus open weights, for dictation into a prompt

### 2.1 Candidates

| | Engine | How it runs on a Mac | Size on disk | Streaming partials | Custom vocabulary |
|---|---|---|---|---|---|
| Native | **SpeechAnalyzer + SpeechTranscriber** (macOS 26) | System model, out of process, downloaded silently by `AssetInventory` | 0 for Duo | yes (volatile results) | `contextualStrings` accepted but **no effect** (measured, §2.3) |
| Native | **DictationTranscriber** (macOS 26) | The older on-device dictation model | 0 | yes | `contextualStrings` (works a little, §2.3); custom language model |
| Native | SFSpeechRecognizer, on-device | Same model as DictationTranscriber | 0 | yes | `contextualStrings` |
| Native | System Dictation (fn fn) | Any `NSTextView` | 0 | yes (system UI) | none |
| Open | **Parakeet TDT 0.6B v3** (NVIDIA; Core ML by FluidAudio) | ANE, Swift | 461 MB | no (batch) | FluidAudio CTC keyword boosting (+98 MB CTC model) |
| Open | Parakeet TDT 0.6B v2 (English only) | same | 443 MB | no | same |
| Open | Parakeet Redux (2-bit v3, MMM's) | GPU | 202 MB | no | same |
| Open | **Parakeet Unified en 0.6B** (FluidAudio) | ANE | ~0.6 GB per encoder variant | **yes**, same weights | batch only at this pin |
| Open | Nemotron Speech Streaming 0.6B | ANE | 612 MB | yes | library has it; not wired |
| Open | **Whisper large-v3-turbo** (WhisperKit, Core ML) | ANE | 1.5 GB (632 MB quantised build exists) | via re-decoding | prompt tokens |
| Open | Whisper large-v3-turbo (mlx-whisper), distil-large-v3.5 | GPU, Python only | 1.5 / 1.4 GB | no | `initial_prompt` |
| Open | Moonshine medium / small streaming, base | ONNX, Python (C++ core) | 258 / 137 / 136 MB | yes | keyterms (streaming only) |
| Open | Kyutai STT 1B en/fr | MLX, Python | 2.3 GB | yes (0.5 s delay by design) | none |
| Open | Voxtral Mini 4B Realtime, Granite Speech | MLX, Python | 2.7–3 GB | Voxtral yes | — |

Python-only engines (MLX, ONNX) were measured to compare model quality. Shipping one in Duo would mean a Swift port. Only the FluidAudio, WhisperKit and Apple engines are drop-in Swift.

### 2.2 What's published

The **Open ASR Leaderboard** (version 09-10-2026; CSV [`english_short_latest.csv`](https://huggingface.co/datasets/hf-audio/open-asr-leaderboard-results/resolve/d3c0e9a07b475a64afb56254e8c35b584905af32/english_short_latest.csv), source [init.py](https://huggingface.co/spaces/hf-audio/open_asr_leaderboard/raw/main/init.py)) reports average WER in % over its public English sets. Its RTFx is measured on an H200 GPU, so use it only for ranking.

| Model | Avg WER | Earnings22 (numbers, jargon) | LS clean / other | Params |
|---|---|---|---|---|
| Parakeet TDT 0.6B v2 | 6.43 | 6.76 | 1.28 / 2.73 | 0.6 B |
| Parakeet TDT 0.6B v3 | 6.51 | 5.85 | 1.52 / 3.13 | 0.6 B |
| Canary-Qwen 2.5B | 6.37 | 6.41 | 1.23 / 2.63 | 2.5 B |
| Qwen3-ASR 1.7B | 5.75 | 5.84 | 1.26 / 2.94 | 2.0 B |
| distil-large-v3.5 | 7.02 | 7.70 | 1.94 / 4.52 | 0.8 B |
| Whisper large-v3 | 7.84 | 7.99 | 1.56 / 3.52 | 2 B |
| Whisper large-v3-turbo | 8.39 | 8.09 | 2.13 / 3.71 | 0.8 B |
| Voxtral Mini 3B | 7.84 | 7.66 | 1.48 / 3.63 | 5 B |
| Nemotron streaming 0.6B | 6.89 | 9.45 | 1.89 / 4.35 | 0.6 B |
| Moonshine streaming medium (its own card) | 6.65 | 11.90 | 2.08 / 5.00 | 0.25 B |

Apple's models are not on the leaderboard. Independent comparisons:

- [Argmax (June 2025)](https://www.argmaxinc.com/blog/apple-and-argmax), Earnings22 subset, M4 Mac mini, macOS 26 beta 1: **SpeechAnalyzer 14.0 % WER** vs Parakeet v2 (Argmax Pro) 11.7 %. Whisper small.en scored 12.8 % and base.en 15.2 %. Their verdict: Apple "matches the speed and accuracy of mid-tier OpenAI Whisper models."
- [Inscribe via GIGAZINE (July 2026)](https://www.gigazine.net/gsc_news/en/20260714-apple-speech-analyzer-benchmark/), LibriSpeech on an M2 Pro: SpeechAnalyzer 2.12 % clean / 4.56 % other; legacy SFSpeechRecognizer 9.02 / 16.25.
- FluidAudio's own [benchmarks](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md): Parakeet v2 2.1 % and v3 2.5 % on LibriSpeech clean.
- [MacStories (June 2025)](https://www.macstories.net/stories/hands-on-how-apples-new-speech-apis-outpace-whisper-for-lightning-fast-transcription/): SpeechAnalyzer was 2.2× faster than MacWhisper large-v3-turbo on a 34-minute file, "with no noticeable difference in transcription quality."

So on clean read speech, Apple's new model is level with Parakeet. On harder, jargon-heavy audio, the published gap is ~2–3 WER points.

### 2.3 Local benchmark: Duo-style dictation

**Method** (harness in `docs/research/voice-input-bench/`, spec in its `SPEC.md`):
- 40 short prompts like Geoff's (`utterances.jsonl`). 23 are technical: file names, flags, identifiers, "duo2", "Claude Code", env vars. 17 are plain English.
- Each prompt was spoken by four macOS `say` voices (Samantha US, Daniel UK, Karen AU, Rishi IN), giving **160 clips and 1,680 words** at 16 kHz.
- Separately, **58 of Geoff's own recorded takes** (Harvard sentences, 505 words) were read in place from the voice project. Only aggregate numbers are reported, by agreement with that session.
- Every engine was run as it would be in Duo: model loaded and warmed once, then each clip transcribed from memory.

**Scoring:**
- **WER\*** compares each clip with both its spoken form ("package dot swift") and its written form ("Package.swift") and counts the fewer errors. That way neither a model that formats nor one that doesn't is penalised for it.
- **Terms** is the share of 92 technical terms (×4 voices) found in the output, ignoring case, spaces and symbols. So "duo 2" counts for `duo2`, but "duo two" does not.
- **wWER** is the WER against the written form only: what the user would actually have to fix.

Mac: **Apple M6, 32 GB, Mac mini, macOS 27.0**. WER and terms don't depend on load. Section 2.4 gives the speed numbers taken on a quiet machine.

**Synthetic dictation set (160 clips):**

| Engine | WER\* (95 % CI) | Plain | Technical | Terms | wWER |
|---|---|---|---|---|---|
| Apple SpeechTranscriber | **13.5 %** (11.0–16.1) | 6.3 % | 18.2 % | 73.7 % | 24.0 % |
| Apple DictationTranscriber | 16.1 % (14.0–18.2) | 10.5 % | 19.7 % | 59.2 % | 25.7 % |
| Parakeet v3 (FluidAudio) | **10.2 %** (8.1–12.6) | 2.4 % | 15.4 % | 83.3 % | 21.3 % |
| Parakeet v2 (FluidAudio) | 9.9 % (8.0–11.8) | 2.4 % | 14.8 % | 81.6 % | 19.1 % |
| Parakeet Unified, batch (FluidAudio) | **9.5 %** (7.5–11.5) | 2.6 % | 14.0 % | 83.8 % | 18.4 % |
| Parakeet Redux (2-bit) | 13.0 % (10.6–15.4) | 6.2 % | 17.4 % | 73.2 % | 22.0 % |
| Whisper large-v3-turbo (WhisperKit) | **7.4 %** (5.7–9.3) | 2.0 % | 11.0 % | 86.4 % | 16.0 % |
| Whisper large-v3-turbo (mlx-whisper) | 9.1 % (7.0–11.3) | 2.0 % | 13.8 % | 83.8 % | 18.8 % |
| distil-large-v3.5 (MLX) | 9.9 % (7.7–12.2) | 3.2 % | 14.3 % | 83.3 % | 19.0 % |
| Moonshine medium streaming | 13.1 % (10.8–15.5) | 6.2 % | 17.6 % | 71.9 % | 22.0 % |
| Moonshine base | 13.3 % (10.9–15.8) | 5.6 % | 18.4 % | 69.3 % | 22.6 % |

**With custom vocabulary** (the 26 terms in `context-terms.txt`):

| Engine + biasing | WER\* | Terms | Cost |
|---|---|---|---|
| SpeechTranscriber + `contextualStrings` | 13.5 % (no change, identical output) | 73.7 % | none |
| DictationTranscriber + `contextualStrings` | 13.8 % (from 16.1) | 64.9 % (from 59.2) | latency ×2 |
| **Parakeet v3 + FluidAudio CTC keyword boosting** | **8.3 %** (from 10.2) | **88.6 %** (from 83.3) | +98 MB model, +~120 ms |
| Whisper turbo (WhisperKit) + prompt | 7.7 % | 91.7 % | latency ×4 (to ~1.3 s) |
| Whisper turbo (MLX) + `initial_prompt` | 7.8 % | 89.5 % | +50 % latency |

**Geoff's own voice** (58 takes, 505 words; plain sentences):

| Engine | WER |
|---|---|
| Apple SpeechTranscriber | 2.2 % |
| Apple DictationTranscriber | 4.0 % |
| Parakeet v3 | 2.2 % |
| Parakeet Unified | 1.2 % |
| Whisper turbo (WhisperKit / MLX) | 1.8 % / 1.2 % |
| Moonshine medium | 3.2 % |

At 505 words one error is 0.2 points, so on plain speech in a real voice every engine except DictationTranscriber is within noise of every other.

**What failed for every engine** is formatting:
- `scripts/release.sh`, `kill -9`, `en-US`, `.claude/worktrees` and `DUO_AUTOCONFIRM` were missed by all of them in nearly every voice, and so were `symbolicate` and `palettization`.
- No engine turns "dash dash model" into `--model`, so written-form WER stays at 16–26 % for all of them.
- Closing that gap is a job for a spoken-to-code formatter after recognition (Q-179), plus vocabulary taken from the project: file names, symbols and session names. ASR choice doesn't close it.

### 2.4 Speed, latency and memory (quiet machine)

Measured 04:36–04:52 on 2026-10-12, holding duo-voice's GPU lock with nothing else running: 40 clips, each prompt once, voices rotated. The §2.3 WER pass ran while a Duo merge check was building, and its timings were 10–75 % slower: Parakeet v3 34 ms vs 28, WhisperKit 308 vs 272, SpeechTranscriber 113 vs 65. Use only these quiet numbers for speed.
- **Batch (push-to-talk):** "after release" is the time from the end of audio to the text, with the model warm.
- **Stream:** audio is fed in real time in 100 ms chunks. "First partial" is the time from the start of speech to the first words on screen; "after release" is the time from the end of speech to the final text.

| Engine | Mode | After release, median (p90) | First partial | RTF | Warm load | Peak RSS | Disk |
|---|---|---|---|---|---|---|---|
| Apple SpeechTranscriber | batch | 65 ms (78) | — | 0.019 | 0.06 s | 21 MB\* | 0 |
| Apple SpeechTranscriber | stream | 105 ms (134) | **1.13 s** | — | | 21 MB\* | 0 |
| Apple DictationTranscriber | stream | 109 ms (204) | 0.83 s | — | | 21 MB\* | 0 |
| **Parakeet v3** (FluidAudio) | batch | **28 ms** (30) | — | 0.008 | 0.17 s | 84 MB\* | 461 MB |
| **Parakeet Unified** (FluidAudio) | batch | **28 ms** (30) | — | 0.008 | 0.22 s | 65 MB\* | ~0.6 GB |
| Parakeet Unified, low-latency stream tier | stream | 35 ms (44) | 1.24 s | — | 0.40 s | 60 MB\* | (same weights) |
| Nemotron streaming 0.6B (FluidAudio) | stream | 29 ms (35) | **0.65 s** | — | 0.19 s | 114 MB\* | 612 MB |
| Parakeet Redux (2-bit, GPU) | batch | 41 ms (43) | — | 0.012 | 0.13 s | 407 MB | 202 MB |
| Whisper turbo (WhisperKit) | batch | 272 ms (339) | — | 0.094 | 2.0 s | 247 MB\* | 1.5 GB |
| Whisper turbo (mlx-whisper) | batch | 314 ms (337) | — | 0.093 | 1.3 s | 1.76 GB | 1.5 GB |
| Moonshine medium streaming | stream | 126 ms (171) | 0.69 s | 0.21 | 0.7 s | 1.6 GB | 258 MB |
| Kyutai STT 1B | stream | 676 ms (702) | 0.94 s | 0.77 | 1.4 s | 2.45 GB | 2.3 GB |

\* RSS doesn't include Neural Engine memory, or Apple's model, which runs in a system process.

**First load matters more than warm load.**
- v3's first load took 63 s: download plus the ANE compile for this Mac.
- WhisperKit turbo's first load took **17 minutes** of ANE compile, under load. Core ML caches it afterwards.
- So Duo should compile the model in the background right after download, never on the first press.

Accuracy in streaming mode on these 40 clips:
- SpeechTranscriber: 14.3 % WER\* (11.2 % in batch);
- Nemotron: 12.1 %;
- Parakeet Unified stream: 11.7 % (9.0 % batch);
- Moonshine: 12.6 %;
- Kyutai: 15.7 %.

**Mac mini M6 to an M3-or-later MacBook.**
- The workload is tiny: Parakeet does a 4-second prompt in ~28 ms, ~150× faster than real time.
- Apple's published ANE throughput went from M3's 18 TOPS (search-only figure) to M4's 38 TOPS ([Apple](https://www.apple.com/newsroom/2024/05/apple-introduces-m4-chip/)); M5 and M6 are faster again.
- Even at 3–4× slower on an M3 MacBook Air, push-to-talk stays under ~120 ms after release, well below what a person notices. Streaming first-partial times are set by each model's chunking, not the chip.
- A fanless Air won't throttle on one-second bursts. Memory is a non-issue: under ~0.6 GB of model, and Apple's model sits outside Duo.
- What does scale with the chip is the one-off first-load compile. Expect a minute or more on an M3 for Parakeet, and much more for Whisper.

### 2.5 The answer

**Yes, open weights meaningfully beat native on technical dictation, but not on plain English.**
- On Duo-style technical prompts, Parakeet v3 makes **~25 % fewer word errors** than Apple's SpeechTranscriber: 10.2 % vs 13.5 %, with overlapping 95 % intervals.
- Parakeet with vocabulary boosting makes **~40 % fewer**: 8.3 %, terms 89 % vs 74 %.
- Whisper turbo makes ~45 % fewer (7.4 %), at 10× the latency and 3× the size.
- Apple's custom vocabulary had **no effect** on SpeechTranscriber. That is the lever that matters for project names, so the gap grows with how much jargon a project has.
- On plain sentences in Geoff's real voice, they're level: SpeechTranscriber and Parakeet v3 both scored 2.2 %.
- Parakeet is also 2–4× quicker after release (28 ms vs 65–105 ms). Both are fast enough.
- Neither formats code (`--model`, `scripts/release.sh`). That needs a separate step (Q-179). For chat prompts it barely matters: Claude reads "package dot swift" fine.

Caveat: the technical set is synthetic (macOS voices, clean audio). Real microphones add noise and reverb. Every engine gets worse with them, and Apple's own WWDC claim is that its new model is strong on "distant audio". Before building, re-run the bench on ~40 of Geoff's real dictated prompts (Q-178).

---

## 3. Integration sketch (no design yet)

**Capture.**
- `AVAudioEngine` input node tap converted to 16 kHz mono Float32 (`AVAudioConverter`), fed straight to the recognizer.
- Hold-to-talk on a key (fn or a chosen chord) plus a toggle (click the mic, or press the key twice).
- Hold-to-talk suits short prompts: Parakeet's batch path finishes in tens of ms after release (§2). The toggle suits longer dictation, with streaming partials shown in the composer as provisional text.
- No audio is ever written to disk, matching MMM's rule.

**Where text goes.**
- **Chat composer:** the composer is a native text view, so insert at the caret with `insertText` (one undo group per utterance). Partials can show as marked (provisional) text that the final result replaces.
- **Terminal:** write the final text to the PTY as a **bracketed paste**. That's `TerminalSession.bracketed()` (`ESC[200~…ESC[201~`), which Duo already uses for `duo2 send text`. It sanitises the text so a paste can't end itself early or press Return.
  - Claude Code's TUI treats a bracketed paste as one insertion: no per-key autocompletion, slash menus or `@` pickers firing mid-text, and newlines don't submit.
  - Typing it as keystrokes would trigger those, and is slower for long text.
  - Partials shouldn't go to the PTY: you can't un-type them cleanly. Show them in an overlay above the terminal's prompt, and paste only the final text.
  - **Never press Return for the user.** Dictation fills the prompt; the user sends it. Voice commands like "send it" come later.
- **System Dictation already exists.** The composer is a native `NSTextView`, so Edit › Start Dictation (fn fn) should already work there with no code (G-2 was still to check by hand). SwiftTerm's view implements `NSTextInputClient`, so it may work in the terminal too. Both are untested (Q-181). That's the zero-work baseline any Duo feature must beat.

**Microphone permission.**
- `NSMicrophoneUsageDescription` in `scripts/bundle.sh`'s Info.plist. Without it, the process is killed on first mic access.
- Hardened Runtime (`--options runtime`, which `release.sh` signs with) blocks audio input unless the app is signed with the `com.apple.security.device.audio-input` entitlement. Release builds sign with **no entitlements file** today, so `release.sh` needs a minimal `Duo.entitlements` with that one key. That's a signing change; test it with a notarized build.
- The prompt is macOS's TCC dialog. It's a system dialog, which F-54 forbids Duo from *showing on its own*. The rule should be: Duo asks only when the user presses the mic for the first time, after a Duo sheet explains it. `AVCaptureDevice.authorizationStatus(for: .audio)` is checked silently first. When denied, a Duo sheet points to System Settings.
- Apple's SpeechTranscriber needed **no speech-recognition authorization** tonight: `SFSpeechRecognizer.authorizationStatus()` stayed `notDetermined` and analysis ran. Only the mic prompt is needed. The older SFSpeechRecognizer would add a second prompt.

**Scripted and isolated runs.**
- Never touch the mic.
- A `--state` fixture can drive the pipeline from a file. A harness action like `dictate:<wav>` feeds file audio through the same path, so captures and DuoChecks test it without TCC.
- `duo2` verb (DL-71): `duo2 dictate --file <wav> [--to <id>]` transcribes a file into a session's prompt. It's the scripted twin of the mic button. A live `duo2 dictate start|stop` would need the mic, so it's UI-only with the reason noted in `Parity.uiOnly`, or allowed only when Duo is frontmost.
- Isolated Duos (F-113) never prompt, so they report "microphone not authorized" in the sheet path instead.

**FluidAudio as a dependency.**
- Apache-2.0, pure Swift plus Core ML. MMM pins a commit with `traits: []`, which leaves out its text-normalization binary.
- The bench needed current main (`e560c64…`) for Unified streaming, Nemotron and CustomVocabulary. Pin a commit, not a tag, and re-check on bumps.
- Watch two things:
  - its default downloader writes to `~/Library/Application Support/FluidAudio/` and fetches from Hugging Face. Duo must load models only from its own folder (`AsrModels.loadLocal`) and never call FluidAudio's downloader, as MMM does.
  - streaming vocabulary boosting reads its CTC tokenizer from that folder at this pin (bench finding).
- Binary-size cost: measured in the bench build, its release object is 12.5 MB, plus a 1.0 MB resource bundle. The whole bench binary, with WhisperKit linked too, is 12.8 MB after linking. So FluidAudio adds **~10 MB to Duo's 116 MB app**. Most of that is TTS, diarization and other code Duo wouldn't call.
- The alternative for the native route is no dependency at all.

**Push-to-talk first, streaming later.**
- Parakeet v3 returns the whole prompt 28 ms after release, so short prompts don't need partials. A level meter while held is enough feedback.
- For long dictation, FluidAudio's Unified model streams partials from the same family of weights (9.0 % batch / 11.7 % streaming here). Nemotron is quickest to its first partial (0.65 s). Either can come later behind the same recognizer interface.

---

## 4. Evidence index

- **Benchmark harness:** `docs/research/voice-input-bench/`.
  - `SPEC.md` is the method.
  - `utterances.jsonl` is the test set and `context-terms.txt` the biasing list.
  - `make_manifests.py` makes the audio with `say`.
  - The runners are `swift/` (Apple, FluidAudio, WhisperKit) and `py/` (MLX, Moonshine, Kyutai, Voxtral, Granite).
  - `py/score.py` scores; `runall.sh` and `runlatency.sh` are the passes.
- **Raw aggregate numbers:** `voice-input-bench/results/summary-synth-wer-pass.json` (160 clips, under load) and `summary-lat40-quiet.json` (40 clips, quiet).
- **Not committed:** per-clip transcripts (in `~/Library/Caches/duo-voice-input/results/`), and anything for Geoff's takes. Those were scored in a scratch folder and deleted, by agreement with the voice session.
- **Models and venvs:** outside the repo, in `~/Library/Caches/duo-voice-input/` (37 GB; delete it when done with the research).
- **Pins:**
  - FluidAudio `e560c6445ffdc42e60c7b282d162aae271f18e2a` (`traits: []`);
  - WhisperKit 1.1.1 with `openai_whisper-large-v3-v20240930_turbo`;
  - Redux read in place from mini-meeting-minutes at its pinned revision.
- **Not measured:**
  - SFSpeechRecognizer (it needs a speech-recognition prompt we won't trigger);
  - Voxtral Mini 3B (it didn't run cleanly);
  - Canary (needs NeMo/CUDA);
  - Qwen3-ASR and Cohere Transcribe (no Mac build checked; leaderboard only);
  - real microphone audio.
- **Pages opened** are linked inline in each section. Facts found only through search summaries are marked as such: the LFS overage price and M3's TOPS.
