# The intro video, built like software

Research and plan, 2026-10-10. It supersedes ENH-17: one walkthrough video, and a way to keep it current.

**The ask (Geoff, 2026-10-10):**
- An intro video for Duo v2: half on why Duo exists, half a walkthrough of a few features.
- Built like a software project with CI. The script lives as a Claude Doc.
- Each build re-voices the script with the best open-weights TTS that runs on the Mac mini (M6, 32 GB).
- Each build re-animates the video from fresh captures of the real app: flyovers and zoom-ins at very high fidelity, so the video stays true as the app changes.
- Style references that the pipeline reads, so the look can evolve.
- Start small and iterate.

This page covers the research (§1–§3), the pipeline (§4–§8), the plan (§9) and the decisions for Geoff (§10).

---

## 1. Motion graphics with Opus 5.5: what works

**Opus writes a program that paints frames; it doesn't make video.** Every serious pipeline makes the film a pure function of time: give it `t` and it draws that exact frame. A headless browser calls it for every frame and ffmpeg encodes the result. Nothing animates on a wall clock: no CSS transitions, no timers, no state carried from one frame to the next. Then a fix to one scene is a one-line edit and a re-render of only those seconds. [A1][V6][V10]

**What makes the difference** (practitioner reports, chiefly A1, the "claude-motion-design" pipeline, and V5):
- **A fixed order of work.** Inputs, then a beat map (the timing skeleton), then about four stills Geoff approves, then the full render, then a frame-by-frame check, then audio. Approving stills first catches problems in minutes that a full render would take ten minutes to show. [A1]
- **Keep content apart from code.** Copy, timings and assets go in data files that the scene code reads, so a new variant is a new data file. [V5]
- **One change per pass,** looked at before the next one. [V5][V12]
- **The framework's own agent skills.** Without them Claude invents API calls. Remotion ships official skills. [V1][V14]
- **Start from a reference.** Take its grammar (pacing, type, transitions), never its content. With no reference, Opus falls back on its own taste: centred text, a gradient, everything fading in. [A1]
- **Springs make motion look expensive,** as long as they stay closed-form: a damped spring computed from `t`, never a physics simulation, so frame 812 renders without frames 0 to 811. [A1]
- **Motion blur from extra frames.** Render 8 subframes per output frame, average them in ffmpeg (`tmix`), never across a hard cut. Four subframes leave ghost copies on fast moves. It costs about 1 to 1.5 minutes of rendering per second of film. [A1]
- **Make it watch its own frames.** Each pass renders a contact sheet at 2 frames per second, a 12-frame strip around each fast move, and a 360 px phone-size sheet. Score each 1 to 10 on: hook in the first 2 s, readability at phone size, motion quality, variety (something new every 2 to 4 s), composition, accuracy and sound sync. List the three worst problems with timestamps, fix them, re-render only those seconds, and repeat until every score is 8 or more. [A1]
- **Real data or a label,** and no claims the product can't back up. [A1]

**Typical failures:**
- Wall-clock animation that flickers or vanishes in a frame-by-frame render. This is the most common LLM bug. [V6][V10][V11]
- Thinking in minutes rather than frames.
- Voiceover and scene lengths that don't match, leaving dead air or cut-offs. [V5]
- More than about 15 overlapping layers. [V5]
- Fonts not loaded at frame 0.
- Motion that looks smooth in preview but choppy at 30 fps with no blur. [V5]
- Overlapping labels. [V15]

**What this means for us:** a fixed time grid, data-driven scenes, a lint step, and a render-and-look loop. That is Duo's existing habit of building to a screen and comparing a capture.

## 2. Code-driven video tools

| | Remotion 4 | Plain HTML `seek(t)` + Playwright (A1's way) | HyperFrames | Motion Canvas / Revideo | Manim |
|---|---|---|---|---|---|
| Language | React/TS | HTML/JS + Python | HTML/CSS/JS, GSAP/Lottie adapters | TS, canvas | Python |
| Licence | Source-available; **free for individuals and companies of up to 3 people**, automation included [V17][V18] | MIT, our own code | Apache-2.0 [V2] | MIT | MIT |
| Headless CLI | `remotion render`, `renderMedia()` | Our own script | `render`, `lint`, `check` | Revideo: `renderVideo()` | Yes |
| Deterministic on macOS | Yes: every frame is a pure function of `useCurrentFrame()` | Yes, as long as we follow its rules | Byte-exact only on Linux; screenshot fallback on macOS [V3] | Yes | Yes |
| Preview for Geoff | **Studio**: a scrubbable timeline in the browser, live reload | Stills and drafts only | Preview server | Editor | None |
| Audio | `<Audio>` per sequence, muxed | ffmpeg, our own | Mixer, ducking | Basic | Basic |
| Agent fit | Best: official skills, lots of training data | Good (plain web code) | Built for agents | Moderate | Layout bugs |
| Motion blur | `@remotion/motion-blur` (subframes) | `tmix` over subframes | n/a | n/a | n/a |

**Large images.** All browser renderers draw through Chrome's GPU compositor. Most Macs report a maximum texture size of 16384 px. Chrome tiles big layers, but there are known failure paths for images over that limit that are also scaled down by more than half [V25][V26]. No source measures blur when you zoom into a 6000 px capture, so milestone 0 tests it (§9).

**Recommendation: Remotion 4,** with its official agent skills. Geoff qualifies for the free licence. It is deterministic on macOS without Linux-only flags. Studio gives Geoff a real preview with scrubbing. `<Audio>` sequencing and its captions tools fit a voiceover. We still borrow A1's rules: springs, subframe blur, stills first, the critique loop.

**Fallback: plain HTML with a `seek(t)` engine, rendered by Playwright.** It is all MIT and our own code, at the cost of building the preview and audio ourselves. It's the exit if Remotion's licence or behaviour ever gets in the way. The scene data files would carry over.

## 3. Open-weights text to speech on the Mac mini

The open-weights models at the top of the arenas (Breeze TTS 2, Fish S2 Pro, Voxtral, Higgs TTS 3) all have **non-commercial weights**, so they're out for a product video [T2][T5][T6].

| Model | Quality evidence | Licence | Voice | On Apple Silicon | Notes |
|---|---|---|---|---|---|
| **Qwen3-TTS 12Hz 1.7B** (Jan 2026) | English WER 1.24 and speaker similarity 0.775, the best in its own table (self-reported) [T7][T8]. Reviewer: "flat intonation… good enough to ship" [T10] | Apache-2.0, code and weights | 9 presets with style instructions; **design a voice from a description, then reuse it as a clone prompt**; cloning from a 3 s+ clip | mlx-audio, bf16 or 8-bit, 3–6 GB [T3][T9][T11] | Sampled, so pin the seed. A reference clip over ~15 s can make it loop |
| **Kokoro-82M v1.0** | Elo 1064 on Artificial Analysis, above Chatterbox and Zonos [T2] | Apache-2.0 | 54 preset voices; **phoneme overrides per word** | mlx-audio, tiny and fast | Deterministic; can't skip or invent words; less expressive; no cloning |
| VoxCPM2 (2B) | English WER 1.84 (self-reported) | Apache-2.0 | Voice design and cloning, 48 kHz | mlx-audio | Repo warns results vary between runs [T12] |
| Chatterbox | Elo 1026 | MIT | Cloning; exaggeration control | mlx-audio | **Every output carries a watermark** [T13] |
| Higgs, Fish, Voxtral, F5, XTTS, IndexTTS2 | | Non-commercial or restricted | | | Out on licence |

**Recommendation: Qwen3-TTS 1.7B through mlx-audio.** We design one house voice from a written description, commit its reference clip and transcript, and clone it for every line. **Fallback: Kokoro**, deterministic with preset voices. Both run comfortably in 32 GB. If Qwen sounds flat, Kokoro's best voices are a real alternative, not just a safety net.

**Keeping the voice the same for weeks:**
- Each line is synthesised alone.
- The cache key covers the line's text, the pronunciation dictionary, the voice reference, the model revision, mlx-audio's version, the decoding settings and the seed.
- An unchanged line is never re-voiced.
- An upgrade re-voices everything and gets a listening pass.

**Pronunciation:** a dictionary in the repo turns "duo2" into "duo two" and "⌘K" into "command K". Kokoro also takes phonemes.

**Checking the voice automatically:**
- Every line goes back through speech recognition (parakeet-mlx, Apache-2.0, with word timestamps) [T15]. The build fails on any missing or invented content word, or a word error rate over 5%.
- It also fails on speed outside 2 to 3.5 words per second, which catches looping or truncation, and on silence over 1.5 s.
- A failed line is re-tried with the next seed, up to N times, and the passing seed is recorded.
- The word timestamps also time the shots (§5).

## 4. Pictures of the real app

**What exists today** (from reading the code):
- `--state <fixture state>` with `--capture` or `--capture-window` draws the window into a PNG through `cacheDisplay`. That needs no permissions, runs in the background, and takes about 3 s per launch (F-227).
- `--window WxH` sets the size.
- `--then` runs about 200 harness actions: `open:`, `doc:`, `chat:on`, `search:`, `session-state:`, `sheet-new`, …
- `film:<prefix>:<ms>|<ms>…` writes a timed sequence of frames from one launch. `DUO_MOTION_SCALE` slows the app's own animations.
- Web views (the editor, HTML pages, browser tabs) are painted from WebKit's own snapshot (F-120).

**Gaps for the video:**

1. **Scale is fixed at 2x** (`WindowCapture.swift:77`, `:115`): it resamples to `rect × 2`. A 1440 × 900 window gives 2880 × 1800. A 1080p frame that zooms into a 480 pt-wide region needs 4x to stay sharp, and 4K needs 8x.
2. **Web views are snapshotted at point width (1x)** and then drawn into the 2x bitmap. Editor and HTML text is softer than native text.
3. **The terminal is blank** in captures: SwiftTerm draws in a layer (F-25). The fixture project's middle pane is an empty dark rectangle today, and its document shows only headings. Chat mode is native SwiftUI and captures fine.
4. **No anchors.** Nothing records where a given element is. A zoom to "the Needs you row" would need hand-written coordinates, which break when the layout changes.

**Proposed harness additions** (all debug-only, in `FixtureHarness` and `WindowCapture`; no UI, so DL-71 adds no `duo2` verb):

| # | Addition | Why | Milestone |
|---|---|---|---|
| H1 | **`--capture-scale N`** (and `DUO_CAPTURE_SCALE`): allocate the bitmap at N× and let `cacheDisplay` draw into it, so text and vectors are drawn at N×, not upsampled. Web snapshots get `snapshotWidth = width × N / backingScale`. Default 2, so every existing check is unchanged. | Sharp zooms. 4x on 1440 × 900 is 5760 × 3600, under Chrome's 16384 limit. | M0 |
| H2 | **`anchors:<json>`**: walk the window's accessibility tree in-process (no permission needed) and write every element's identifier, label, role and frame in points. Add `.accessibilityIdentifier("video.…")` where an element has no stable label. | Camera targets and callouts are named ("sidebar.needsYou.row0"), not coordinates. When the layout moves, the camera follows. When an anchor disappears, the build fails. | M1 |
| H3 | **A video fixture** (`video/fixture.json`, through the existing `--fixture`): sample projects with real document text, real session titles and real chat transcripts. | The video shows real-looking work on sample data, never Geoff's. | M2 |
| H4 | **Terminal replay and capture**: `term-play:<cast>` feeds a recorded ANSI stream (a `.cast`, recorded once from a real Claude Code run on sample data) into SwiftTerm on a fixed schedule, and the capture draws the terminal's layer (`layer.render(in:)`). | The terminal is the heart of the app, and today it draws blank. Replays are deterministic and cost no tokens. | M2 |
| H5 | **`film-fps:<prefix>:<fps>:<seconds>`**: frames at a fixed rate, with `DUO_MOTION_SCALE` to slow the app down while filming. The pipeline re-times the frames to normal speed. | The app's real animations (sheets, rows moving, highlight fades) in the video, not imitations. | M3 |
| H6 | **`layers:<dir>`**: one PNG per pane (sidebar, console, right pane, toolbar) with its frame. | Parallax and "exploded" flyovers that pull the window apart. | M4, if wanted |

**Considered and set aside:**
- **Vector output** (`dataWithPDF`): SwiftUI's layer-backed content rasterises in PDFs, so 4–8x bitmaps get the same result more reliably.
- **Recording the live app with Claude driving it:** not deterministic, spends tokens, and could touch real data.
- **ScreenCaptureKit:** needs Screen Recording permission, which blocks unattended runs (F-54).

**Isolation** (CLAUDE.md, "Running the app"):
- Every capture run gets its own short `DUO_SUPPORT_DIR` (`/tmp/dvid.XXXX`) and runs on fixtures.
- Live-workspace shots, if any, use a scratch `CLAUDE_CONFIG_DIR` copied from `~/DuoAcceptance`'s buckets.
- `duo2` is never pointed at an instance without both `DUO_SOCKET` and `DUO_TOKEN`.
- Never Geoff's own Duo or data.

## 5. The pipeline

```
Claude Doc (script)  ──export──▶ video/script.md ─┐
video/shots.json  (shot specs, keyed by scene id) ─┼─▶ plan ─▶ timeline.json
video/style/*     (tokens, motion, type, grammar)  ─┘            │
                                                   ┌──────────────┼───────────────┐
                                                   ▼              ▼               ▼
                                           voice (per line)   capture (per spec)   style tokens
                                           Qwen3-TTS → WAV    Duo.app --capture    gen from DS
                                           ASR check, words   at 4x + anchors
                                                   └──────────────┬───────────────┘
                                                                  ▼
                                                   Remotion render (seek(t) scenes)
                                                   stills → draft 540p → master
                                                                  ▼
                                                   mix (VO + music later), loudnorm,
                                                   mux → out/intro.mp4 + report
```

**The script.**
- **Where it lives:** a Claude Doc is the source of truth. One section per scene, each with a stable scene id (`S3`), the voiceover lines, and a plain-English shot note.
- **Export:** each build exports the Doc to `video/script.md` and commits it, so the script's history is in git.
- **Who exports:** only a Claude session can export (it's a connector call). A CI runner without Claude builds from the committed `script.md`.

**Shot specs** (`video/shots.json`) are the machine side of each shot note: the fixture state and `--then` actions to capture, the camera path (keyframes on named anchors), the callouts and the transition. Claude writes and maintains them; Geoff writes the notes in the Doc. The build fails if a scene in the script has no spec.

**The timeline.** Voiceover timing is our beat map:
- Each line's word timestamps give its length.
- A shot holds until its line ends, plus a breath set by the style.
- A camera move is pinned to a word: `"land": "needs you"` means the zoom settles as that phrase is spoken.
- The planner writes `build/timeline.json`, the only thing the renderer reads.

**Caching and incremental builds.** Every product is content-addressed in `video/.cache/`:
- **A voiced line** is keyed on its text, pronunciations, voice reference, model revision, mlx-audio version, decoding settings and seed. Re-voice only what changed.
- **A capture** is keyed on the Duo binary's hash, the fixture's hash, the spec, the scale and the window size. When the app is rebuilt, every capture is retaken: they're cheap, about 3 s each, and that is the point. Then each new capture is compared with the last approved one.
- **A render** is keyed on the timeline, the captures, the style and the scene code.
- **Master renders only re-render scenes whose inputs changed,** then join the segments.

**Proof at each build.** The build writes `out/`:
- `intro.mp4`;
- `contact-sheet.png` at 2 frames per second;
- one still per scene at its key frame;
- a 360 px phone-size sheet;
- `report.md`: which lines were re-voiced, which captures changed (with before and after thumbnails, and the pixel count from `scripts/pixels.py`), the speech-recognition results, and the timings.

**The critique loop** (A1's, on Opus):
- A review step reads the sheets and scores them on the rubric in `video/style/critique.md`.
- It lists the three worst problems with timestamps.
- That loop runs when we change style or scenes, not on every rebuild.

## 6. The style references (`video/style/`)

The renderer reads the JSON files; the Markdown files are the rules, for Geoff and for Claude.

| File | What |
|---|---|
| `tokens.json` | Generated by `scripts/gen-video-tokens.py` from `docs/design/build-handoff/tokens.json` (colours, type sizes, radii), plus tokens only the video uses: frame size, safe areas, title and lower-third sizes, caption style. Never edited by hand, the same rule as the app's tokens. |
| `motion.json` + `motion.md` | Camera easing (closed-form springs with frequency and damping per move type), hold times, transition lengths, and the subframe count for blur. The rule: **the app's own UI moves exactly as the app does** (DL-130: ease-out, no springs; filmed with H5). **The camera and the graphics may use springs**, because they are the video's own motion. |
| `typography.md` | SF Pro and SF Mono to match the app (Q below), the type scale for titles, lower thirds and captions, and the minimum size readable on a phone. |
| `shot-grammar.md` | The vocabulary and its rules. Moves: wide, push-in, pan, rack (dim everything but the subject), callout, highlight, cursor, cut, dissolve. Rules: one camera move per voiceover clause; the move lands before the words that name it; hold at least 1.2 s on a landed shot; never zoom past the capture's resolution (the build checks this); something new every 2 to 4 s. |
| `critique.md` | The scoring rubric and the "harsh director" prompt for the review step. |
| `references/` | Stills or links to films whose grammar we want, never their content. |

**Approval.** The video's look is a new design, so it follows CLAUDE.md: style frames go on a Design canvas with the Duo design system, Geoff approves them, and then they become the style files.

## 7. What fails the build

| Check | Fails when |
|---|---|
| Script | A scene has no shot spec, a spec names a scene that isn't in the script, or the Doc export is older than `script.md` |
| Voice | Speech recognition finds missing or invented words, word error rate is over 5%, speed is outside 2–3.5 words/s, or there is clipping or a long silence. Retries with a new seed first |
| Capture | A fixture state or action is unknown (the harness logs it), the PNG is missing, or a capture is blank: a region that should hold text is uniform, which catches the terminal and web-view failures of F-25 and F-120 |
| Anchors | A named anchor is missing, or has moved out of its shot's frame |
| Zoom | A camera keyframe would magnify the capture past 1:1 at the output resolution |
| Render | A wall-clock API is used (lint: no CSS `transition`/`animation`, `Date.now`, `setTimeout` or unseeded `Math.random` in scenes), or a frame is pure black or white, or one frame flashes (A1's pop check) |
| Timing | The total runs over the target length, or voiceover overlaps between scenes |

A capture that **changed** doesn't fail the build. It's reported with before and after images, because a changed app is why we rebuild. A change can be marked approved in the report.

## 8. Where it runs, and how Geoff previews

- **Now: this Mac mini.** `video/build` (a Node script) runs every stage. Python runs only inside the voice step (a project-local `uv` venv with mlx-audio pinned). Downloaded models live outside the repo in `~/Library/Caches/duo-video/models/<name>/`, each in its own folder. Their code is never run, and nothing with `trust_remote_code` or pickled weights is used.
- **Later: CI.** A self-hosted GitHub Actions runner on the same Mac, or a Claude routine, rebuilds the video on each release tag and publishes the report. It must be macOS, because the captures need the app. Linux isn't an option.
- **Preview:**
  - **Remotion Studio** is a scrubbable timeline in the browser, for live work together. It opens a browser window, so it's started only when Geoff asks.
  - Each build sends Geoff `out/intro.mp4` and the contact sheet with SendUserFile, so they reach his phone.
  - Later, a build page as a private Artifact: a preview of 15 MB or less, the contact sheet and the report.

## 9. Milestones

**M0: the smallest thing end to end** (about 20 s).
- One scene: a title card, then the `project` fixture state captured at 4x (H1), with one push-in to the Needs you row on hand-picked coordinates. Anchors come in M1.
- One voiceover line, from Qwen3-TTS through mlx-audio, checked by speech recognition.
- Rendered with Remotion and muxed to `out/m0.mp4`.
- **It proves four things:**
  - **Fidelity:** the deepest-zoom frame compared with the same crop of the source capture is sharp, measured against an unscaled crop with no visible softening.
  - **Caching:** a second build re-voices nothing and re-captures nothing.
  - **Isolation:** the run never touches Geoff's Duo.
  - **Determinism:** the same inputs give the same frames.
- **About:** half a day. One small Swift change (H1) on the branch; the rest is under `video/`.

**M1: the script drives it.**
- The Claude Doc and its export.
- The script parser and `shots.json`.
- A timeline built from word timestamps.
- Anchors (H2).
- The build report and its checks.
- The whole outline as stand-ins: real voiceover, simple shots.

**M2: real-looking content.** The video fixture (H3), and the terminal replayed and captured (H4).

**M3: the look.**
- Style frames on a Design canvas, for Geoff's approval.
- Then `video/style/` v1: callouts, lower thirds, transitions, subframe blur.
- The app's real animations filmed (H5).
- The critique loop.

**M4: first full cut.** Iterate with Geoff on script and picture. Music and sound, if wanted. Optional layered flyovers (H6).

**M5: CI.** The rebuild on release, the build page artifact, and a `video` skill in `.claude/skills/` that says how to build, review and change the video.

## 10. Decisions for Geoff

1. **Renderer:** Remotion (recommended), or plain HTML with `seek(t)` and Playwright.
2. **Voice:** Qwen3-TTS with a house voice we design (recommended), Qwen3-TTS cloned from a clip of Geoff, or Kokoro preset voices.
3. **Where the code lives:** `video/` in this repo, so app and video change together and a build can use `build/Duo.app` (recommended). Or a separate repo.
4. **The outline below.** Agreeing it lets me make the script Doc.

### Proposed outline (about 2:30)

**Why Duo exists (about 70 s)**
- **S1 · Cold open.** You started with one Claude session. Now there are eleven, across six folders. Terminal windows multiply on screen.
- **S2 · The pain.** Which one is waiting for you? Which one finished? The document Claude wrote is somewhere in a scrollback.
- **S3 · The turn.** Duo is a Mac app for working with Claude Code across many pieces of work at once. Reveal: a wide flyover of All projects.

**A walk through (about 80 s)**
- **S4 · Every session, found.** Duo lists every Claude Code session on your Mac and keeps them. Push in on the session list.
- **S5 · Projects.** A project is something you're trying to finish, in its own folder: its sessions on the left, the conversation in the middle, documents beside it.
- **S6 · What needs you.** The states, and the Needs you count. Answer a question without hunting for the terminal (chat mode).
- **S7 · Documents.** What Claude writes opens beside the conversation, with its additions highlighted ("added by Claude").
- **S8 · Search and getting around.** ⌘K, and search across every project.
- **S9 · Claude drives Duo.** Plain files and `duo2`: Claude can open the document it just wrote.
- **S10 · Close.** Duo v2 is an early beta preview. Where to get it, and how to report issues.

### Open questions (to log as Q-n when the records land)

- **Typeface for titles:** SF Pro, to match the app (it renders through Chrome's system font on macOS), or a free typeface such as Inter for the video's own graphics. SF Pro's licence covers mock-ups of Apple-platform apps; a promo video is probably fine, but this needs Geoff's call.
- **Music:** none in M0 to M3. Later, a royalty-free track with a known licence, or none at all.
- **Output:** 1080p at 30 fps first; 4K and 60 fps later if wanted (8x captures, slower renders).

---

## Sources

**Motion graphics and video tools**
- [A1] Raphael Aubry, "i made 10+ motion videos with opus 5.5 in 3 days", X article, https://x.com/raphaelaubryy/status/2104502744010629269: the `seek(t)` engine; inputs, beat map, 4 stills, render, audio; closed-form springs; 8 subframes with `tmix`; self-critique with a rubric. Code at https://github.com/howseen-ai/claude-motion-design (MIT; HTML, Playwright, ffmpeg, Python).
- [V1] https://www.remotion.dev/docs/ai/skills: Remotion's official agent skills.
- [V2] https://github.com/heygen-com/hyperframes: Apache-2.0, frame seeking in headless Chrome, lint/check commands.
- [V3] https://www.heygen.com/research/html-to-video: byte-exact `beginFrame` is Linux only; macOS falls back to screenshots.
- [V5] https://www.mejba.me/fr/blog/remotion-video-workflow-claude-code: Claude Code + Remotion; a first draft is about 80% usable; frame, font, audio and codec pitfalls.
- [V6] Remotion best-practices rule mirror (search summary): drive everything from `useCurrentFrame()`; no CSS or Tailwind animation.
- [V10] https://www.remotion.dev/docs/gsap/use-gsap-timeline: Remotion owns the clock; stray tweens are rejected.
- [V11] timecut README (search summary): it overrides JS time only, so CSS animation isn't captured.
- [V12] https://www.reclip.io/claude-opus-5-5-video-prompts: storyboard first, one fix per pass.
- [V14] growwstacks.com (search summary): without the skill, Claude invents Remotion APIs.
- [V15] manimkit on PyPI (search summary): LLM Manim failures.
- [V17] https://github.com/remotion-dev/remotion/blob/main/LICENSE.md and [V18] https://www.remotion.dev/docs/license-pricing-compliance/faq: free for individuals and up to 3 employees, automation included.
- [V25] web3dsurvey MAX_TEXTURE_SIZE (search summary): 16384 on about 94% of Macs. [V26] codereview.chromium.org/2952923002 (search summary): the failure path for over-size, down-scaled images.

**Text to speech**
- [T2] https://artificialanalysis.ai/text-to-speech/leaderboard: open-weights Elo (Breeze 1222, Fish S2 Pro 1116, Step EditX 1096, Voxtral 1086, Kokoro 1064, Chatterbox 1026).
- [T3] https://github.com/Blaizzy/mlx-audio: the models it supports and their quantisations.
- [T5] https://localaimaster.com/blog/best-local-tts-models and [T6] https://localaimaster.com/blog/higgs-tts-3-licence-and-vram: licences.
- [T7] https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-Base and [T8] https://github.com/QwenLM/Qwen3-TTS: Apache-2.0, WER and similarity tables, reusable clone prompt, voice design.
- [T9] https://simonwillison.net/b/9255: Qwen3-TTS through mlx-audio.
- [T10] https://akitaonrails.com/en/2026/04/09/how-elevenlabs-was-not-killed-by-qwen3-tts: flat prosody, clipped first syllable.
- [T11] https://www.sourcepulse.org/projects/24974041: Qwen3-TTS on MLX in 2–6 GB.
- [T12] https://github.com/OpenBMB/VoxCPM: VoxCPM2, seed flag, run-to-run variation.
- [T13] https://huggingface.co/ResembleAI/chatterbox: MIT, watermark.
- [T14] https://huggingface.co/hexgrad/Kokoro-82M: Apache-2.0, 54 voices, phoneme overrides.
- [T15] https://github.com/senstella/parakeet-mlx: speech recognition with word timestamps on MLX.

**The codebase:** `Sources/DuoKit/Debug/WindowCapture.swift` (the capture path, 2x), `Sources/DuoKit/Debug/FixtureHarness.swift` (`--then` actions, `film:`), `Sources/DuoKit/Debug/LaunchOptions.swift` (flags), `scripts/check-ui.sh`, `scripts/run-live.sh`, `scripts/check-motion.sh`, `scripts/acceptance/fixtures.py`, `docs/design/build-handoff/tokens.json` (motion tokens), and findings F-25, F-120 and F-227. A background capture of the `project` state on 2026-10-10 showed the blank terminal and the headings-only document (§4, gap 3).
