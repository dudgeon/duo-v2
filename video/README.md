# The intro video

The Duo v2 intro video, rebuilt like software (DL-169). The plan and its research are in [`docs/research/intro-video.md`](../docs/research/intro-video.md).

The script's source of truth is the [Claude Doc, script v2](https://claude.ai/code/artifact/38f24d8b-a41f-4ca4-86fe-c20fd8e4cd78). `script.md` is its copy in the repo; the build reads only `script.md`. Edit the Doc, never `script.md`.

**Syncing the Doc.** Export the Doc's tab as Markdown (Claude Docs `export`, format `markdown`) to a file, then run `node pipeline/sync.mjs <file> --rev <n>`. It shows what changed, line by line, and the Shot: notes that changed as diffs. With `--write`, it writes `script.md` and renumbers the beats, events and pauses in `shots.json` that name a line which moved. A ref to a line the Doc no longer has stops it. A changed Shot: note keeps stopping the build until you re-read it and sync again with `--accept-notes S7`. `script.md`'s second line records the Doc revision it came from, so the next sync can read only what changed since then.

## Build

```bash
scripts/bundle.sh              # the app the captures come from
cd video && npm install        # Remotion, project-local
node build.mjs --check         # seconds: the script and shots, before anything is voiced
node build.mjs                 # check → voice → capture → timeline → render → out/
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
- stills at the key frames and `out/thumbnail.png`;
- `out/report.md` (scenes, lengths, anything a Shot: note asks for that isn't built, and any stale framing);
- `out/LISTEN.md` and `out/score-qa.png`: five timecodes and a waveform for checking the score by ear.

**Flags:** `--stills` (no video), `--draft` (half scale), `--no-score`, `--accept-anchors`.

**Framing that follows the app.** Cameras and marks name anchors (`style/shot-grammar.md`, App scenes), so a change to Duo's layout moves them with it. Each build notes every rect it reads in `.cache/anchors-used.json` and logs the framing that moved. A rect in window points whose anchors moved is reported as `STALE` in the log and in `report.md`, and stays reported until it is fixed or the build runs with `--accept-anchors`.

**What it reuses:** voiced lines and captures, from `.cache/`, until their inputs change. The flags `--force-voice` and `--force-capture` redo them anyway.

**The score step** needs `score/.venv` (`uv venv --python 3.12 score/.venv`, then `uv pip install --python score/.venv/bin/python -r score/requirements.txt`) and ACE-Step 1.5's weights from `score/fetch.py` in `~/Library/Caches/duo-video/models/ACE-Step-1.5`. `score/score.json` holds the prompt, seed and levels; `pipeline/score.mjs` generates the bed for the film's length, checks it has no words in it, and the film ducks it under the voice (`src/scenes/Film.tsx`).

**Heavy runs share the Mac's GPU** with the voice-clone work. Run them under the lock: `GPU_LOCK=<the lock dir> scripts/gpu-lock.sh <your name> node build.mjs`. It waits for a live owner, clears one whose process is gone, passes a TERM on to the job, and releases the lock however the job ends. The lock's path is machine-local, so it comes from `$GPU_LOCK`, never the repo.

**The voice step** needs `voice/.venv`, made with `uv venv --python 3.12 voice/.venv` and `uv pip install --python voice/.venv/bin/python -r voice/requirements.txt`. It also needs the models in `~/Library/Caches/duo-video/models/`; `voice/models.lock.json` lists them and their commits. Models are never in the repo.

## Rules

- **Captures:** fixtures only, with a throwaway `DUO_SUPPORT_DIR`. They run in the background and never touch your own Duo.
- **Scenes:** pure functions of the frame. `lint.mjs` fails a build that uses a timer, `Date`, `Math.random` or CSS animation.
- **Taste:** `style/taste.md` lists what Geoff has rejected and chosen, in his words. Read it before proposing any look, transition, callout or voice.
- **Tokens:** `style/tokens.json` is generated: edit `style/video-tokens.json` and run `python3 scripts/gen-video-tokens.py`.
- **The voice:** `voice/house/voice.json`. Its `external` names Geoff's voice file outside the repo. A named voice file that isn't there stops the build, because another narrator would change every timing. On a machine without it, such as a clean checkout, the cut can't be reproduced in his voice: build with `DUO_VOICE_JSON=house` for the house voice. Since DL-173 that's the fine-tuned VoxCPM2 clone (`voxcpm-lora100.json`, `engine: "voxcpm"`: duo-voice's own venv, script and LoRA run it; its `said` map holds spellings only it needs). The zero-shot Qwen clone (DL-171) stays one switch away: `DUO_VOICE_JSON=~/Library/Caches/duo-video/voices/geoff-zeroshot.json node build.mjs`. VoxCPM voices at RTF ~1.4, so a full re-voice takes about 10 minutes, under the GPU lock. His reference audio and anything voiced in his voice never enter this repo: voiced lines live only in the gitignored `.cache/`, `build/` and `out/`. Check `git status` for audio before every commit.

## Script history

- **v1** (the M0–M3 cuts) is archived. The Doc is renamed "[Archived] … script v1" and its last export is `archive/script-v1.md`.
- **v2** is a from-scratch rewrite (Geoff, 2026-10-10). In its Doc:
  - a `###` scene titled "Example…" and empty `(line)` slots are skipped;
  - an *italic* phrase in a line is a callout cue.
- Until v2 has scenes, `node build.mjs` stops with "no scenes in script.md".
