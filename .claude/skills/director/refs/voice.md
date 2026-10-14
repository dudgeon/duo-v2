# Dependencies: geoff-voice

*Part of Duo's own director (`../SKILL.md`): Duo dev's habits on top of the shared duo-director core. Moved here unchanged from the single SKILL.md on 2026-10-14.*

## 8. Dependencies: geoff-voice

Geoff treats **`dudgeon/geoff-voice`** (private, created 2026-10-12) as a dependency of Duo, and the director directs it as it directs duo-v2. The repo is Geoff's own voice: VoxCPM2 plus a LoRA trained on his takes. It narrates the intro video (DL-173) and is meant to be reused by other projects.

- **What lives there:**
  - `voices/<name>/`: a LoRA, its reference clip, and a `voice.json` card with relative paths;
  - `bin/speak`;
  - `setup.sh` (a pinned VoxCPM2 fetch);
  - `takes/` and `script/` (the reading script);
  - `train/`, `eval/` and `CHANGELOG.md` (the versions and their scores).
  - The other engines Geoff tried are in `archive/`.
  - Its README is the procedure for new takes, training, evaluation and packaging ("Train a new version").
- **A recording session with Geoff.** He records takes from `script/reading-script.md` as Voice Memos. A session then:
  1. checks each take with `tools/check_take.py`;
  2. trains under the GPU lock;
  3. scores the checkpoints and makes a listening page;
  4. packages the one Geoff picks as a new `voices/` version.

  Geoff picks by listening, so ask him with buttons. When he adopts a new version as the narrator, record it as a DL-n in duo-v2, re-voice the film, and keep the old version folder so it can be pinned.
- **Delegating.** Delegate the work the same way: a background session, its cwd the geoff-voice checkout. The session commits there, and the director reviews the commit and pushes it; check `tools/check_repo.sh` first, since nothing over 95 MB and no training state may be committed. The repo must stay private: check `gh repo view dudgeon/geoff-voice --json visibility` before a push.
- **The link to duo-v2.** No submodule: duo-v2 is public, and its public clones can't fetch a private repo. `video/voice/house/voice.json`'s `external` names a machine-local card that points at the geoff-voice checkout, and the voice cache key is content-based. Without the card (a clean clone, or an agent without access), the build stops with a clear error until `DUO_VOICE_JSON=house` selects the house voice. After any change to geoff-voice's voice or `bin/speak`, prove the film's lines still come from the cache (or re-voice them deliberately), as `video/README.md` describes.
- **Privacy.** None of Geoff's audio, weights, voice cards, transcripts of his takes or local paths ever enter duo-v2. Check `git status` and the diff for audio and paths before every duo-v2 commit that touches `video/`.
- **Compute.** Training, voicing and evaluation take the GPU lock **exclusive** (§5a). On this Mac, geoff-voice's own `GPU_LOCK` must point at the machine's shared lock, not its repo default.
