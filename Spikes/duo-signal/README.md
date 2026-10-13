# duo-signal spike (ENH-70, DL-183, F-297)

A sensor-only Claude Code mod and the Duo side that reads it, behind `DUO_SIGNAL=1` (off by default). The mod is `Mods/duo-signal`; Duo's side is `Sources/DuoKit/Chat/ChatSignal.swift`; the checks are `Sources/DuoChecks/DuoSignalChecks.swift`. Findings and the recommendation are F-297.

Nothing here spends tokens: every run is the real `claude` TUI against the chat-mode spike's mock API, with a scratch config.

| File | What |
|---|---|
| `run.sh` | The mod alone: `claude` on a PTY (`time.mjs`), the mod passed by `--plugin-dir` as a read-only copy. `--no-mod` for the baseline; `MOD_SRC=<dir>` for a broken copy; `CLAUDE_BIN=<claude>` for another CLI (2.1.219). |
| `time.mjs` | `drive.mjs` plus a 10 ms sampler: when the screen and the signal file each change their mind about busy, the dialog and the mode (`timeline.log`). |
| `steps.json` | A long reply, a Bash permission (answered), an AskUserQuestion (declined), two mode changes. |
| `same-screens.sh` | Two runs' screen dumps compared, with times, spinner words and paths masked. |
| `live.sh` | Duo itself, isolated and in the background: a warm-up launch (copies and validates the mod), then the run; chat sends the same three turns. `FLAG=0` for the flag off, `CLAUDE=<path>` for another CLI, `APP=` for another build. |
| `analyze.py` | The numbers from `live.sh` runs: card-up after the dialog draws, and the signal's lead over the screen. |

`run.sh` needs a copy of `Spikes/chat-mode` with its `node_modules` (`npm install` there) for the PTY; `live.sh` runs the mock from `Spikes/chat-mode` as it is.
