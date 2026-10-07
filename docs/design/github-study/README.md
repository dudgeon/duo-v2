# Duo: GitHub in a project — design study

Status: **decided, DL-149** (Geoff, 2026-10-07, by buttons). Every mark on these boards was a proposal [P]; the approved boards are exported to `docs/design/github-handoff/screens/`, whose README names which option on each board to build.

Geoff, 2026-10-07: "we should incorporate github primitives in many places; eg we should make it easy to add a project from remote (gh), as a new or existing branch, and make it easy to push and/or open a pr (anticipating that many users will not be admin)". The research, the options and the rules are in `docs/research/github-primitives.md`. The boards are drawn on the Design canvas https://claude.ai/artifact/76ZGzopVk1eLx9d2pnWA2i with the Duo design system.

## Files

- `canvas/make.py` draws the 14 boards as static HTML into `canvas/boards/`. `canvas/render.sh` renders them to `canvas/boards/png/<name>@2x.png`. `canvas/to-canvas.py <root>` writes them as canvas artboards.
- The shared CSS and glyphs come from `home-evolution-handoff/canvas/make.py`; the New project sheet's CSS is copied from the project & task CX study's `make.py`. Colours are tokens by value.

## Boards

| Board | What it shows |
|---|---|
| `00-study` | The ask, what changes from the legacy call, principles, legacy and the landscape in short |
| `01-new-from-github` | The CX study's New project sheet with From GitHub: the repo field, Choose… (gh), the Found box, the exclude checkbox |
| `02-branch` | A new branch or one that's there: A, two choices (recommended); B, one combined field |
| `03-landing` | A clone per project in Home (recommended) vs worktrees; progress; the done notice |
| `04-status` | The repo's state on a project: A under the status line (recommended), B in Files, C a toolbar chip |
| `05-states` | The repo line's twelve states |
| `06-push-pr` | Push… and Open PR with write access |
| `07-fork` | No write access: said in the sheet (A, recommended) or asked after a refused push (B) |
| `08-no-gh` | Without the GitHub CLI: push with git, the PR on GitHub's compare page |
| `09-get-latest` | Get Latest, Bring In Changes from main, a conflict |
| `10-failures` | Every failure in Duo's question look |
| `11-duo-and-claude` | Who does what; what Claude is told; the drafted instructions |
| `12-duo2` | The `duo2 repo` verbs |
| `13-recommendation` | The recommendation and a first slice |

## Owned elsewhere

- **The New project sheet**, its Start from segment (A new folder | A folder I have | From GitHub) and its Name, Goal, In and Will write rows belong to the project & task CX study (DL-147, theirs). This study owns what shows under From GitHub. Agreed with that session (duo-v2-5d) on 2026-10-07.
- **`_PROJECT.md`** is the CX study's name for a new project's note (DL-147).
- The notice pattern (rises at the foot of the pane, with Undo where possible) is the CX study's R10.
