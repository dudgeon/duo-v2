# The intro video

The Duo v2 intro video, rebuilt like software (DL-169). The plan and its research are in [`docs/research/intro-video.md`](../docs/research/intro-video.md).

The script's source of truth is the [Claude Doc, script v2](https://claude.ai/code/artifact/38f24d8b-a41f-4ca4-86fe-c20fd8e4cd78). From M1, each build exports it to `script.md`.

## Build

```bash
scripts/bundle.sh              # the app the captures come from
cd video && npm install        # Remotion, project-local
node build.mjs                 # voice → capture → timeline → render → out/
```

**What `node build.mjs` writes:**
- `out/intro.mp4`, its soundtrack normalised to -16 LUFS;
- stills at the key frames and `out/thumbnail.png`;
- `out/report.md` (scenes, lengths, and anything a Shot: note asks for that isn't built);
- `out/LISTEN.md` and `out/score-qa.png`: five timecodes and a waveform for checking the score by ear.

**Flags:** `--stills` (no video), `--draft` (half scale), `--no-score`.

**What it reuses:** voiced lines and captures, from `.cache/`, until their inputs change. The flags `--force-voice` and `--force-capture` redo them anyway.

**The score step** needs `score/.venv` (`uv venv --python 3.12 score/.venv`, then `uv pip install --python score/.venv/bin/python -r score/requirements.txt`) and ACE-Step 1.5's weights from `score/fetch.py` in `~/Library/Caches/duo-video/models/ACE-Step-1.5`. `score/score.json` holds the prompt, seed and levels; `pipeline/score.mjs` generates the bed for the film's length, checks it has no words in it, and the film ducks it under the voice (`src/scenes/Film.tsx`).

**Heavy runs share the Mac's GPU** with the voice-clone work: take the lock first (`mkdir ~/repos/duo-voice/.gpu.lock`, wait while it exists, `rmdir` when done), and never render Mon 2026-10-12 10:00–18:00.

**The voice step** needs `voice/.venv`, made with `uv venv --python 3.12 voice/.venv` and `uv pip install --python voice/.venv/bin/python -r voice/requirements.txt`. It also needs the models in `~/Library/Caches/duo-video/models/`; `voice/models.lock.json` lists them and their commits. Models are never in the repo.

## Rules

- **Captures:** fixtures only, with a throwaway `DUO_SUPPORT_DIR`. They run in the background and never touch your own Duo.
- **Scenes:** pure functions of the frame. `lint.mjs` fails a build that uses a timer, `Date`, `Math.random` or CSS animation.
- **Tokens:** `style/tokens.json` is generated: edit `style/video-tokens.json` and run `python3 scripts/gen-video-tokens.py`.
- **The voice:** `voice/house/voice.json`. Its `external` names Geoff's voice file outside the repo, used when it exists; otherwise the house voice there. Since DL-173 that's the fine-tuned VoxCPM2 clone (`voxcpm-lora100.json`, `engine: "voxcpm"`: duo-voice's own venv, script and LoRA run it; its `said` map holds spellings only it needs). The zero-shot Qwen clone (DL-171) stays one switch away: `DUO_VOICE_JSON=~/Library/Caches/duo-video/voices/geoff-zeroshot.json node build.mjs`. VoxCPM voices at RTF ~1.4, so a full re-voice takes about 10 minutes, under the GPU lock. His reference audio and anything voiced in his voice never enter this repo: voiced lines live only in the gitignored `.cache/`, `build/` and `out/`. Check `git status` for audio before every commit.

## Script history

- **v1** (the M0–M3 cuts) is archived. The Doc is renamed "[Archived] … script v1" and its last export is `archive/script-v1.md`.
- **v2** is a from-scratch rewrite (Geoff, 2026-10-10). In its Doc:
  - a `###` scene titled "Example…" and empty `(line)` slots are skipped;
  - an *italic* phrase in a line is a callout cue.
- Until v2 has scenes, `node build.mjs` stops with "no scenes in script.md".
