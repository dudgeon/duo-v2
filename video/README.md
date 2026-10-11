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
- `out/m0.mp4`;
- stills at the key frames;
- `out/m0-report.md`.

**What it reuses:** voiced lines and captures, from `.cache/`, until their inputs change. The flags `--force-voice` and `--force-capture` redo them anyway.

**The voice step** needs `voice/.venv`, made with `uv venv --python 3.12 voice/.venv` and `uv pip install --python voice/.venv/bin/python -r voice/requirements.txt`. It also needs the models in `~/Library/Caches/duo-video/models/`; `voice/models.lock.json` lists them and their commits. Models are never in the repo.

## Rules

- **Captures:** fixtures only, with a throwaway `DUO_SUPPORT_DIR`. They run in the background and never touch your own Duo.
- **Scenes:** pure functions of the frame. `lint.mjs` fails a build that uses a timer, `Date`, `Math.random` or CSS animation.
- **Tokens:** `style/tokens.json` is generated: edit `style/video-tokens.json` and run `python3 scripts/gen-video-tokens.py`.
- **The voice:** the house voice is `voice/house/`. Geoff's own voice (ENH-69) lives in a separate private project, never here.

## Script history

- **v1** (the M0–M3 cuts) is archived. The Doc is renamed "[Archived] … script v1" and its last export is `archive/script-v1.md`.
- **v2** is a from-scratch rewrite (Geoff, 2026-10-10). In its Doc:
  - a `###` scene titled "Example…" and empty `(line)` slots are skipped;
  - an *italic* phrase in a line is a callout cue.
- Until v2 has scenes, `node build.mjs` stops with "no scenes in script.md".
