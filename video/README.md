# The intro video

The Duo v2 intro video, rebuilt like software (DL-169). The plan and its research are in [`docs/research/intro-video.md`](../docs/research/intro-video.md).

The script's source of truth is the [Claude Doc, script v2](https://claude.ai/code/artifact/38f24d8b-a41f-4ca4-86fe-c20fd8e4cd78). `script.md` is its copy in the repo; the build reads only `script.md`. Edit the Doc, never `script.md`.

**Syncing the Doc.** Export the Doc's tab as Markdown (Claude Docs `export`, format `markdown`) to a file, then run `node pipeline/sync.mjs <file> --rev <n>`. It shows what changed, line by line, and the Shot: notes that changed as diffs. With `--write`, it writes `script.md` and renumbers the beats, events and pauses in `shots.json` that name a line which moved. A ref to a line the Doc no longer has stops it. A changed Shot: note keeps stopping the build until you re-read it and sync again with `--accept-notes S7`. `script.md`'s second line records the Doc revision it came from, so the next sync can read only what changed since then.

**Making a video for another project.** The pipeline is reusable: the code stays, and the script, fixtures, shots, style and narrator are per film. The skill `.claude/skills/product-video/SKILL.md` is the procedure, from the brief to review rounds, including the voice: if `gh repo view dudgeon/geoff-voice` fails, you don't have access to Geoff's, so build with `DUO_VOICE_JSON=house` (or design a voice of your own) and don't look for copies of his.

**Remotion's licence (DL-177).** Remotion, which renders the film, isn't open source. It's free for individuals and for companies of up to 3 people; a larger company needs Remotion's Company License, and its terms change at Remotion 5.0 (see `node_modules/remotion/LICENSE.md`). Duo itself doesn't ship Remotion, so this binds only whoever renders the film. Duo is a personal project by one developer (the main [README](../README.md)), who renders it as an individual. If you fork Duo and render the film for a larger company, you need that licence.

## Build

```bash
scripts/bundle.sh              # the app the captures come from
cd video && npm install        # Remotion, project-local
node build.mjs --check         # seconds: the script and shots, before anything is voiced
node build.mjs                 # check → voice → capture → timeline → render (by scene, cached) → out/
node build.mjs --scene S7      # one scene, for a quick look
```

**The check stage** runs first in every build, and alone with `--check`. It needs no app, voice or GPU, and it reports every problem at once:
- a state VideoTargets can't draw;
- a beat, event or pause on a line the scene doesn't have, or on a word its line doesn't say;
- a way in that isn't in `TRANSITIONS`, or doesn't fit the scenes either side;
- a changed Shot: note, shown as a diff;
- a `requires` item that names nothing that builds it;
- a voice file that isn't there.

It also lists the lines changed since the last build. When every line is voiced and every state captured already, `--check` plans the film too (anchors, the words as heard, stale framing), in about 2 s. In `shots.json`, each `requires` item has `by`: the beats (`#id`), events, states, `transition` or `src:` files that build it. An item that isn't built yet says `built: false` instead, and the report names it.

**What `node build.mjs` writes:**
- `out/intro.mp4`, its soundtrack normalised to -16 LUFS;
- `out/review.json` and `out/review/<scene>.mp4` for the scenes it re-rendered;
- stills at the key frames and `out/thumbnail.png`;
- `out/report.md` (scenes, lengths, anything a Shot: note asks for that isn't built, and any stale framing);
- `out/LISTEN.md` and `out/score-qa.png`: five timecodes and a waveform for checking the score by ear.

**Flags:** `--stills` (no video), `--draft` (half scale), `--no-score`, `--accept-anchors`, `--scene S7` (one scene, or `S7,S8`, to `out/scene-S7.mp4`; with `--draft`, half size), `--whole` (one pass, no scene cache), `--gc`.

**Rendering a scene at a time** (`pipeline/render.mjs`). Each scene's frames are kept in `.cache/render/` under a key of everything that draws them, so a build renders only the scenes that changed and joins the rest with `ffmpeg -c copy`. The key covers:
- the scene's slice of the timeline (its start only as a sub-frame phase, so a scene that only moved later keeps its key);
- the topic list and the topic changes near it;
- the scene before it, when that scene's last frame spills into its range;
- the pixels of the captures it shows, not the app build that took them;
- the shared pictures, the source and the render settings.
The soundtrack is rendered once for the whole film, so the score and its ducking run on across scene edges, then it's normalised to -16 LUFS and muxed. It's cached too, keyed on what it plays: each scene's span, each line's timing and voice file, the score bed and its gain settings, the topic changes and the source. A change to the pictures only (a camera, a mark, a capture) keeps it. An edit to one scene re-renders that scene, and sometimes the one after it.

**The poster.** The film's frame 0 is S0's settled title card (the icon, "Duo" and its line), so a player that shows the video before play shows the title; on play it gives way to the logo building. Film.tsx draws frame 0 at the first scene's `poster` time, which build.mjs sets from S0's `thumbnail`; `out/thumbnail.png` is the same frame and goes into the file as its cover art. The build fails if frame 0 isn't the title card.

**What Geoff reviews.** `out/review.json` lists each scene's start, end and still, and whether this build re-rendered it. It also lists what its Shot: note asks for, with the timecodes where each item is on screen. Each re-rendered scene also gets a 480p clip in `out/review/`.

**The score bed** is reused when a cached bed is at least as long as the film; the film fades it out itself. A new one is made at least 8 minutes long, in whole minutes, so a change in the film's length doesn't make new music.

**`--gc`** removes captures and scene renders the current build doesn't use, and leftover voicing jobs. Voiced lines and score beds stay, because another narrator's lines cost a GPU run to redo.

**Framing that follows the app.** Cameras and marks name anchors (`style/shot-grammar.md`, App scenes), so a change to Duo's layout moves them with it. Each build notes every rect it reads in `.cache/anchors-used.json` and logs the framing that moved. A rect in window points whose anchors moved is reported as `STALE` in the log and in `report.md`, and stays reported until it is fixed or the build runs with `--accept-anchors`.

**What it reuses:** voiced lines and captures, from `.cache/`, until their inputs change. The flags `--force-voice` and `--force-capture` redo them anyway.

**The score step** needs `score/.venv` (`uv venv --python 3.12 score/.venv`, then `uv pip install --python score/.venv/bin/python -r score/requirements.txt`) and ACE-Step 1.5's weights from `score/fetch.py` in `~/Library/Caches/duo-video/models/ACE-Step-1.5`. `score/score.json` holds the prompt, seed and levels; `pipeline/score.mjs` generates the bed for the film's length, checks it has no words in it, and the film ducks it under the voice (`src/scenes/Film.tsx`).

**Heavy runs share the Mac's GPU** with the voice-clone work. Run them under the lock: `GPU_LOCK=<the lock dir> <main checkout>/scripts/gpu-lock.sh <your name> node build.mjs` (call the main checkout's copy by its full path, since a work tree's copy may be older). A render, voicing or the score is **exclusive**, the default: it waits for every other holder, then runs alone. A `--stills` or `--check` build that only reuses cached voice and renders can run `--shared` (`gpu-lock.sh --shared <name> node build.mjs --stills`): up to two shared jobs run at once (`GPU_LOCK_SHARED_SLOTS`), and none starts while an exclusive job holds the lock or waits at the front of the queue. Waiters queue in order and each prints its place, so a long render isn't starved by short jobs. It waits for a live holder (one it can't signal still counts as live) and clears one whose process is gone, a hold with no owner after a minute, and a queued waiter that died. It releases only a hold that is still its own, and warns if the hold is taken from under its job. It passes a TERM on to the job and releases the hold however the job ends. Don't take the lock with a bare `mkdir`: that doesn't wait for the shared jobs already running. `scripts/check-gpu-lock.sh` proves it on a scratch lock. The lock's path is machine-local, so it comes from `$GPU_LOCK`, never the repo.

**The voice step** needs `voice/.venv`, made with `uv venv --python 3.12 voice/.venv` and `uv pip install --python voice/.venv/bin/python -r voice/requirements.txt`. It also needs the models in `~/Library/Caches/duo-video/models/`; `voice/models.lock.json` lists them and their commits. Models are never in the repo.

## Films

The pipeline builds more than one film. `node build.mjs` builds the intro, with the paths above (`script.md`, `shots.json`, `out/`, `build/public`). `node build.mjs --film <name>` builds the film in `films/<name>/`:

- `films/<name>/script.md` and `shots.json`, in the same formats as the intro's, and an optional `style/tokens.json` merged over `style/tokens.json` (only what the build reads: the frame, the voice timings, the capture; scenes import the shared tokens).
- It builds to `out/<name>/`, with its own public dir `build/<name>/public` (every `remotion` call passes `--public-dir`, because `remotion.config.ts` sets the intro's) and its own `.cache/last-build-script-<name>.json` and `anchors-used-<name>.json`.
- `.cache/` itself is shared and content-addressed: voiced lines, captures and scene renders are reused across films. `--gc` keeps what any film uses (each build leaves `.cache/live-<film>.json`); it stops if a film that has been built has no such record yet, so build it once first.
- `node pipeline/sync.mjs <export.md> --rev <n> --film <name>` writes that film's `script.md`; `pipeline/voice-only.mjs --film <name>` voices it.
- The wallpaper and the intro's prototype page are prepared only when a film has desk scenes; a film with no `thumbnail` on its first shot gets no poster check.
- A film's own scenes are registered in `src/scenes/registry.ts` (scene kind to component) and live in `src/scenes/<name>/`. Film.tsx consults the registry before its own branches. A film's render keys leave out the other films' scene folders (and the intro's leave out the registry), so adding a film re-renders nothing of another's; the hook lines in Film.tsx carry `@film-hook` and are left out of the hash for the same reason.
- `films/release-0-2-21/` is the 0.2.21 release film (DL-245): Review in Markdown on the intro's world, under a minute, in Geoff's voice. Its states are `video-rv-*` (`Sources/DuoKit/Debug/VideoTargets+Review.swift`) from `fixture/make-review.py`; its scenes (`rel-title`, `rel-app` with captions, `rel-end`) are in `src/scenes/release-0-2-21/`.
- `films/director/` is a placeholder: two `paper-card` scenes (paper ground, the scene's title in ink) joined by the `paper-carry` transition, so the film builds end to end before its real scenes exist.

## Rules

- **Captures:** fixtures only, with a throwaway `DUO_SUPPORT_DIR`. They run in the background and never touch your own Duo.
- **Scenes:** pure functions of the frame. `lint.mjs` fails a build that uses a timer, `Date`, `Math.random` or CSS animation.
- **Taste:** `style/taste.md` lists what Geoff has rejected and chosen, in his words. Read it before proposing any look, transition, callout or voice.
- **Tokens:** `style/tokens.json` is generated: edit `style/video-tokens.json` and run `python3 scripts/gen-video-tokens.py`.
- **The voice:** Geoff's voice is the fine-tuned VoxCPM2 clone (DL-173) and lives in his **private** repo `dudgeon/geoff-voice` (DL-179), not here and not as a submodule (a public clone or CI can't fetch a private one). `voice/house/voice.json` says how Duo uses it (`geoff`: the voice folder, seed, tempo, and the `said` spellings only this voice needs). Where the checkout is comes from, in order:
  1. `DUO_VOICE_JSON=house` → the house voice (below), never Geoff's;
  2. `GEOFF_VOICE_DIR`, the path of a geoff-voice checkout (set up with its `setup.sh`);
  3. else the machine-local card `external` names (`~/Library/Caches/duo-video/voices/geoff-voice.json`, outside the repo): `{"engine": "voxcpm", "root": "<checkout>"}`; any other field in it overrides `geoff`.

  Nothing found, or a checkout without its venv, stops the build with the fix named, because another narrator would change every timing. On a machine without geoff-voice, such as a clean public checkout, build with `DUO_VOICE_JSON=house`. The build runs the checkout's own `.venv/bin/python geoff_voice/speak.py` with `--ref-wav --ref-text --lines --out --seed --lora`. A line's cache key is made of what the voice is, never where it lives: the LoRA's, `speak.py`'s and the reference clip's sha, the reference text, seed, tempo and `said`. Moving or re-cloning geoff-voice re-voices nothing. Keys made before DL-179 (the whole voice file, paths included) are converted once with `node pipeline/migrate-voice-keys.mjs <the old voice file>`. The zero-shot Qwen clone (DL-171) stays one switch away: `DUO_VOICE_JSON=~/Library/Caches/duo-video/voices/geoff-zeroshot.json node build.mjs`. VoxCPM voices at RTF ~1.4, so a full re-voice takes about 10 minutes, under the GPU lock. His reference audio, weights and anything voiced in his voice never enter this repo: voiced lines live only in the gitignored `.cache/`, `build/` and `out/`. Check `git status` for audio before every commit.

## Script history

- **v1** (the M0–M3 cuts) is archived. The Doc is renamed "[Archived] … script v1" and its last export is `archive/script-v1.md`.
- **v2** is a from-scratch rewrite (Geoff, 2026-10-10). In its Doc:
  - a `###` scene titled "Example…" and empty `(line)` slots are skipped;
  - an *italic* phrase in a line is a callout cue.
- Until v2 has scenes, `node build.mjs` stops with "no scenes in script.md".
