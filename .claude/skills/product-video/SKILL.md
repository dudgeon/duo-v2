---
name: product-video
description: Make a narrated product film (an intro video, demo video, launch film or walkthrough) for Duo or any other project, by reusing Duo's video pipeline (`video/`, Remotion + local TTS + a generated score). Covers the brief, the script Doc, Shot notes, captures, cameras, the narrator (Geoff's own voice if you have access to dudgeon/geoff-voice, an open designed voice if not), the score, renders under the GPU lock, and review rounds with Geoff. Use when asked to "make a video", "intro video", "product film", "demo video" or "walkthrough video" for a project, or to start a new film with the pipeline.
---

# Product video

Duo's 7-minute intro film was built like software: a script in a Claude Doc, a `shots.json` of specs, captures of the real app on sample data, a cloned narrator checked by speech recognition, a generated score, and a Remotion render, all content-addressed so a change redoes only what it touches. This skill is how to make another film like it, for Duo or for another project.

**Read first, every time** (this skill links to them rather than repeating them):
- `video/README.md`: the build, its flags, the check stage, the voice and score setup, the rules.
- `video/style/taste.md`: what Geoff has rejected and chosen, in his words. It applies to every film he reviews, not only Duo's.
- `video/style/shot-grammar.md`: cameras, transitions, beats and anchors as the code implements them.
- `video/style/reference-analysis.md`: a worked example of analysing references before choosing a look.

**Who reviews.** Geoff, unless your brief names someone else; "Geoff" below means whoever reviews the film. His taste (taste.md) is the starting point for any film he reviews.

## Four rules that cost the most rework when broken

1. **No cuts, and a crossfade counts as a cut.** Every scene change is navigation in the product (pull back, the cursor clicks, push in) or a motion graphic where something on screen carries across. The build refuses a scene without a `transitionIn`.
2. **A Shot: note is a spec.** Build every item in it. If one can't be built, say so up front and put a labelled stand-in in its place; a quiet substitute reads as ignoring what Geoff wrote.
3. **No generic or low-effort visuals.** Analyse references before proposing a look, use real assets (the real product on sample data, real wallpapers), and show two or three crafted options as real frames or motion, never quick variations. Geoff rejected nine looks on the first film for being "low effort".
4. **Test runs stay in the background.** Captures, voicing, scores and renders never show a window or take focus. Anything visible needs Geoff's OK first, by button.

## What to reuse and what to replace

- **Reuse as is:** `build.mjs`, `lint.mjs`, `pipeline/` (except the two files under Rewrite), `src/lib/` (camera, desk, paper, topic list, outline trace, marks), `src/scenes/App.tsx` and `Film.tsx`, `voice/tts.py` and `asr_check.py`, `score/`, and from the repo's own `scripts/`: `gpu-lock.sh` and `gen-video-tokens.py`.
- **Rewrite for the product:** `pipeline/capture.mjs` and `pipeline/check.mjs`'s `appStates` (they drive Duo's app; see step 4), and the `TRANSITIONS` table in `pipeline/plan.mjs` (its entries are named for Duo's scenes; see step 5).
- **Write new for the film:** `script.md` (only ever by syncing your Doc), `shots.json`, `fixture/`, `style/video-tokens.json` (then `python3 scripts/gen-video-tokens.py` writes `style/tokens.json`), `style/taste.md` additions, `voice/heard-as.json`, and `voice/house/voice.json`'s `external` and `geoff` block (The voice, below).
- **Delete:** `archive/`; `fixture/`'s contents (Little Shared Library is Duo's world; keep the `make-*.py` scripts open as examples until yours exist); `voice/experiments/`; Duo's rejected options (`src/scenes/*Study*`, `*Variants*`, `StyleFrames.tsx`); and the Duo-only scenes (`Logo.tsx`, `Morph.tsx`, `Conclusion.tsx`, `DuoIcon.tsx`; for a CLI film, keep `ProjectsBg.tsx` as the model for drawing terminals until your own terminal scene works). `Film.tsx` and `Root.tsx` import them by name, so remove those imports and their branches in the same change (`plan.mjs`'s `scene ===` branches for them can stay unused). Keep `Clutter.tsx` and `ClutterApps.tsx`: `App.tsx` takes its menu bar and Dock from them.

Everything the build makes (voiced lines, captures, renders) lives in `video/.cache/`, `video/build/` and `video/out/`, all gitignored. Models live in `~/Library/Caches/duo-video/models/` (or `$DUO_VIDEO_MODELS`), shared by every project on the Mac, never in a repo.

## Starting a new project's film

A film for Duo itself works in place in `video/`; skip to The procedure.

1. **Read Duo's `video/script.md` and `shots.json` first**, then copy the tracked files only: `git -C <duo-v2> archive HEAD video scripts/gpu-lock.sh scripts/gen-video-tokens.py | tar -x -C <new repo>` (no `node_modules/`, `.cache/`, `build/`, `out/` or venvs). Add `.gitignore` lines for `video/node_modules/ video/.cache/ video/build/ video/out/ video/voice/.venv/ video/score/.venv/ video/score/.cache/`.
2. **Delete** what the list says, and `shots.json`. Replace `script.md` with Duo's header only (its title, the "How to write it" rules, the brief table and one Example scene): that is the template for your Doc.
3. **Rename** `package.json`'s `name` and, if you like, the output (`out/intro.mp4`, set in `build.mjs`).
4. **Pick the voice now** (The voice, below), and set `voice/house/voice.json` to match.
5. **Rewrite the capture step and the transitions** (steps 4 and 5 of the procedure), then `npm install`. `node build.mjs --check` stops with "no scenes in script.md" until the first sync of the Doc (procedure step 2) brings a scene in; from then on it is your loop. These steps can run while the brief (procedure step 1) is with Geoff.
6. **Check Remotion's licence** (`video/README.md`): free for individuals and companies of up to 3; a bigger company needs its Company License.
7. **Public repo?** Nothing of Geoff's voice may enter it (The voice, below).

**Sizing.** Narration runs about 3 words a second, so a 2-minute film is about 350 words: 6 to 8 scenes of 2 to 4 lines. A full render takes about 3 seconds per second of film (the 7:14 film took ~23 minutes), so iterate on `--stills`.

## The procedure

### 1. Brief and references
Before a word of script: fill the brief's four rows (one sentence to remember, who it's for, length, how it should feel and must not feel) with Geoff, by buttons where he's choosing. Ask him for two or three reference films, study them (download for private study only, contact sheets at 2 fps), and write a `style/reference-analysis.md` like Duo's: what each does for ground, UI, type, colour, pointing and motion, and what you take. Take grammar, never content. Then propose the look as two or three real frames on a Design canvas, using the project's design system. A project without one gets a small one first (palette, type, the accent), taken from the product's own UI and the reference analysis, and Geoff approves it before any frames.

### 2. The script Doc and sync
The script's source of truth is a Claude Doc that Geoff edits; `script.md` is its synced copy and the build reads only that. Create the Doc from the template `script.md` you kept (Starting, step 2): its "How to write it" rules are what the parser understands (`### S1 · Title (about 20 s)`, one voiced bullet per line, `Topic:`, `Shot:`, *italics* as callout cues, a Written | Said table under `## The voice`, scenes titled "Example…" skipped). Sync with `node pipeline/sync.mjs <exported.md> --rev <n> [--write] [--accept-notes S7]` (README, "Syncing the Doc"). Never edit `script.md` by hand.

### 3. Shot: notes into `shots.json`
For each scene, turn the Shot: note into `requires` items (each one thing the note asks for) and say what builds each (`by`: `#beat`, `state:…`, `transition`, `src:…`) or mark it `built: false`. Record the note's `shotSha`. When Geoff changes a note, the build stops until you re-read it and sync with `--accept-notes`. Check his notes against the real product: the first film's notes got five facts about Duo wrong, found only at capture (F-285).

### 4. Fixtures and captures
**Sample data only**, never anyone's real data. Build one demo world in one data file (`fixture/world.json`, agreed with Geoff in a short interview and written up as `fixture/SCENARIO.md`) and generate every artefact from it with scripts, so two shots of the same thing can't drift (F-283). Generated Office files need fixed zip timestamps or the capture cache never hits.

**The capture contract** the planner needs, whatever the product: for each named state, a PNG at `capture.scale` times the window's size in points, and an anchors JSON, `{"anchors": [{"identifier": "video.x", "frame": {"x", "y", "width", "height"}}]}`, in window points from the top left. `captureStates()` returns `{src, png, widthPt, heightPt, anchors, key}` per state; key it on the product's build and the fixture's bytes.
- **Duo:** fixture states in `Sources/DuoKit/Debug/VideoTargets*.swift`, captured by `pipeline/capture.mjs` in the background with a throwaway support folder; anchors from `video.*` accessibility ids.
- **A web product:** headless Chrome or Playwright at a fixed viewport, `deviceScaleFactor` as the scale, anchors from `getBoundingClientRect()` of `data-video` elements.
- **A CLI or TUI:** run it on the sample world in a pty at a fixed size (Python's `pty` module, or `script -q`), and save each screen you need as ANSI text in `fixture/terms/`, as Duo's `fixture/terms/make-terms.py` does for Claude Code. Then either:
  - **draw it in Remotion** (simplest; Duo's S8 does this in `ProjectsBg.tsx`): a terminal window component that renders the saved text, with anchors computed from row and column; or
  - **capture it**: render each screen to HTML in a terminal frame (for example with `xterm.js` or `ansi_up` in a static page) and capture it as for the web, with `data-video` spans as anchors.

  Typing is a `wipe` between two states: the screen before and after a command.

Rewrite `check.mjs`'s `appStates` to list your states, so the check stage catches a renamed one. Wide shots put the window on a desk (`Desk.tsx`); the camera never magnifies a capture past 1:1, so capture at 4x if you push in close.

**`capture.mjs`'s shape:** export `captureStates(states, {repo, cache, pub, scale, fixture, force, cachedOnly, log})`. For each state, make or reuse `<cache>/capture/<key>.png` and `<key>.anchors.json`, copy the PNG to `<pub>/capture/<state>.png`, and return the object above. Keep its `cachedOnly` behaviour (launch nothing; return `null` if any state isn't cached): the check stage relies on it. Duo's version is 50 lines: keep its structure and swap the launch.

### 5. Anchors and cameras
Frame every camera, mark and click on anchors (`cam: "video.x"`, `{on, x0, x1, y0, y1}`, `{rel, …}`, `{fit: […], pad}`; shot-grammar.md, App scenes), never bare window rects: the product will change under the film, and anchored framing moves with it. The build logs framing that moved and reports `STALE` rects; fix them or accept with `--accept-anchors` once you've looked.

**Transitions.** Every scene after the first names a `transitionIn` from `TRANSITIONS` (`pipeline/plan.mjs`): `{kind: 'app' | 'graphic', from, to, in, out}`, where `from` and `to` are scene types. `click-through` (the cursor clicks, the next state comes up) and `carry-on` (the same picture carries on) are generic; the rest are drawn for Duo's scenes. For a CLI, "navigating" is typing the next command in the same terminal (`carry-on` plus a typing `wipe`), or switching panes or tabs with a visible keystroke (`key`). A new idea needs a motion graphic you design and add, drawn in `Film.tsx` or the scene; show it to Geoff as motion before building it into the film.

### 6. Voice
See **The voice**, below. Each line is voiced on its own, checked by speech recognition (Parakeet: WER ≤ 0.05, pace inside 2 to `voice.maxWps` words/s, no long gap), and re-rolled with the next seed if it fails. Beats land on words by the recognised timings, so voice before you fit beats.

### 7. Score
An instrumental bed from ACE-Step 1.5 (`score/`; setup in the README), prompt, seed and levels in `score/score.json`, checked for words, ducked under the voice. Offer Geoff two or three beds as short clips under one real scene; don't swap the score after he picks.

### 8. The check stage
`node build.mjs --check` runs in seconds with no voice, capture or GPU and reports every problem at once (states, words, transitions, changed notes, `requires`). Run it after every script sync and shots edit; fix everything it says before any heavy run.

### 9. Renders under the GPU lock
Voicing, the score and renders are heavy and share the Mac's GPU with voice fine-tunes. Run them under the lock: `GPU_LOCK=<the machine's lock dir> scripts/gpu-lock.sh <your name> node build.mjs`. The lock's path is machine-local: use `$GPU_LOCK` if your environment sets it, or else ask whoever runs you for it (on Geoff's Mac, the director). Never write it into a repo. Run without it only when you know the machine has no shared lock; if you can't tell, ask (by button) before the first heavy run. Prefer `--stills` (seconds when cached) and `--draft` while iterating, and render one scene if the build supports it (`--scene`, in progress for Duo). A full 7-minute render is ~23 minutes.

### 10. Review rounds with Geoff
- **What he wants to see:** real frames or motion from the film, not descriptions. Send the build's `out/` mp4 (a 720p copy for his phone), the contact sheet and `out/report.md` with `SendUserFile`. Point to the scenes that changed with timecodes, so he doesn't have to watch the whole film for one change.
- **Up front, in every round:** what each Shot: note asked for that isn't built yet, and any stand-in.
- **Choices are buttons** (`AskUserQuestion`), recommendation first; looks are shown on a Design canvas, two or three crafted options. He may answer by Doc or canvas comments instead, so read those before asking.
- **Voices:** short samples of real script lines, with their pitch and pace measured; he reacts in words ("somber", "too deep", "10% quicker"), so turn each reaction into a concrete change and say which.
- **Record his calls** as decisions, and add his rejections, in his words, to `style/taste.md`.

## The voice

The narrator sets every line's length, and so the whole cut: pick it before fitting beats, and never fall back to another narrator silently. The build stops instead.

**First, decide whose film it is.** Geoff's voice is for Geoff's projects. If you're not sure a project is his, or that he wants his voice on it, ask him (by button) before using it. The default for anyone else's project is an open voice.

**Then check access:**

```sh
gh auth status      # not logged in: ask Geoff whether to log in; that alone doesn't mean "no access"
gh repo view dudgeon/geoff-voice --json visibility,viewerPermission
```

If it prints `PRIVATE` with any permission (`READ` is enough), you have access. If you're logged in and it fails for any reason other than the network ("Could not resolve", 404, 403), you have no access. On a network error, retry later.

**It succeeds: Geoff's own voice.** `dudgeon/geoff-voice` is his private repo: a fine-tuned VoxCPM2 clone of his voice (Apple silicon, ~13 GB of GPU memory, ~1.4× real time). Its README's "Narrate a video from another project" section is the procedure; follow it rather than this summary:
1. `gh repo clone dudgeon/geoff-voice <a folder outside any project repo>`, then run its `setup.sh` once (about 10 minutes and a 4.6 GB download the first time).
2. Point the pipeline at it from outside the repo: set `GEOFF_VOICE_DIR` to the checkout, or write the machine-local card that `voice/house/voice.json`'s `external` names, `{"engine": "voxcpm", "root": "<checkout>"}`. Your project's choices for the voice (`voice` folder, `seed`, `tempo`, `said` spellings) go in `voice.json`'s `geoff` block or in the card.
3. `node build.mjs --check` should name the external voice; then voice under the GPU lock.

Use it for Geoff's own projects. It is his voice: don't use it for anyone else's without his say-so.

**No access, or the film isn't Geoff's: an open designed voice.** This is a switch you make on purpose and report, not a silent fallback. Don't ask for the weights or look for copies.
- **The house voice:** `DUO_VOICE_JSON=house node build.mjs`. It is a warm baritone designed with Qwen3-TTS VoiceDesign and frozen as a reference clip (`video/voice/house/reference.wav`); every line is cloned from it with the Qwen3-TTS Base model and played at `tempo` 1.1. Setup, once per Mac (Apple silicon; `brew install uv ffmpeg`):
  ```sh
  cd video
  uv venv --python 3.12 voice/.venv
  uv pip install --python voice/.venv/bin/python -r voice/requirements.txt
  # each model voice/models.lock.json pins, at its commit (public on Hugging Face, no token):
  voice/.venv/bin/hf download mlx-community/<model> --revision <commit> --local-dir ~/Library/Caches/duo-video/models/<model>
  ```
  All of them are `mlx-community/` models; the commits are in `voice/models.lock.json`. Every build needs `Qwen3-TTS-12Hz-1.7B-Base-bf16` and `parakeet-tdt-0.6b-v3`. `…-VoiceDesign-bf16` is only for designing a voice, and `…-CustomVoice-bf16` isn't used. Then `DUO_VOICE_JSON=house node build.mjs --check` should pass and name no external voice.
- **Or design a new voice** for a project that wants its own: write a VoiceDesign description (`voice.json`'s `designed_from` has the house voice's, its seed and model), and generate a reference clip of a neutral sentence for a few seeds with `tts.py` in `design` mode (a job `{"lines": [{"id", "text"}], "voice": {"mode": "design", "description", "seed"}, "out_dir"}`, run as `voice/.venv/bin/python -I voice/tts.py job.json`). Clone two or three real script lines from each candidate, measure pitch (median F0) and pace, and let the reviewer pick by ear. Freeze the pick as the new `voice/house/reference.wav`, and update `ref_text`, `seed`, `tempo` and `designed_from` in `voice/house/voice.json`.
- With `voice.json`'s `external` set and no card on the machine, the build stops: that's why `DUO_VOICE_JSON=house` is needed. In a new project that will never use Geoff's voice, remove `external` and the `geoff` block, and plain `node build.mjs` uses the house voice.
- Say in your report which voice narrated.

**Privacy, for any film in Geoff's voice:**
- Nothing of it enters a public repo: no audio, no weights, no reference clip, no voice card, no voiced lines, no paths into his checkout. Voiced lines stay in the gitignored `.cache/`, `build/` and `out/`. Never add geoff-voice as a submodule, and never copy from it.
- Before every commit: `git status --porcelain | grep -Ei '\.(wav|mp3|m4a|aac|flac|ogg|safetensors|pt|bin)$'` must print nothing. The one exception is a designed voice's own `voice/house/reference.wav`: it is synthetic, nobody's real voice, so commit it, but only on purpose.
- A finished film in his voice is published only where he says.

## Common failures

| Symptom | Cause and fix |
|---|---|
| `voice: … names ~/Library/Caches/…geoff-voice.json, which isn't there` | No card and no `GEOFF_VOICE_DIR`. Set one up (above) or build with `DUO_VOICE_JSON=house`. |
| `the geoff-voice venv python … isn't there` | Run the checkout's `setup.sh`. |
| A correct line fails the speech check | The recogniser spells it its own way ("cloud" for Claude, "you're" for "you are"). Map the name in `voice/heard-as.json`; don't respell the line. |
| A name is said wrong | Add a Written \| Said row to the script's voice table. Respelling can backfire ("DOO-oh" made the voice stumble on "Duo"); try plain first. A spelling only one voice needs goes in that voice's `said`. |
| A line is rushed or loops | The check catches it and re-rolls; raise `DUO_VOICE_RETRIES`, or split the line. |
| `transition: S<n> has no way in from …` | Give the scene a `transitionIn` from `TRANSITIONS`, or add one there (navigation or a motion graphic). |
| `… lands on "…", which S<n>-<k> doesn't say` | A beat is on a word the line doesn't say; fix the beat or the line. Run `--check` after every sync. |
| A changed Shot: note stops the build | Re-read the note, build what changed, then sync with `--accept-notes S<n>`. |
| `STALE` framing | The product moved under a rect in window points. Re-frame it on an anchor. |
| Every state recaptures | The capture key includes the product build and fixture bytes. Unstable bytes (zip timestamps, dates) or a rebuilt app cause it. |
| The render crashes on `interpolate` | Two waypoints at the same time; the range must strictly increase. |
| A scene uses a timer, `Date`, `Math.random` or CSS animation | `lint.mjs` fails it: scenes must be pure functions of the frame. |
| The soundtrack is quiet | TTS comes out near -28 LUFS; the build normalises to -16. Don't boost the voice by hand. |
| The Mac swaps and everything crawls | Two heavy jobs at once: run every voicing, score and render under the GPU lock. |

## Before you report

- `node build.mjs --check` passes, and the last build's `out/report.md` lists nothing unexpectedly not built.
- `git status` shows no audio, weights or private paths.
- The report says which voice narrated, what isn't built yet, and what Geoff should look at, with timecodes.
