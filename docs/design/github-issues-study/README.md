# Duo: GitHub issues and Projects — design study

Status: **proposed, waiting on Geoff** (Q-169 to Q-174). Every mark is [P].

Geoff, 2026-10-09: "Many projects are repos; some of these repos track issues and/or implement GitHub projects. I don't know if these are already synced/syncable via clone/push/pull — but I want to understand what options exist for duo to help visualize, edit, and otherwise manipulate issues by human and agent. To the extent duo helps manipulate projects, we should attempt to reuse/share ui elements and UX mental models with the kanban features."

The research is `docs/research/github-issues.md`. The canvas is https://claude.ai/artifact/9jwpM4HimuucECDXNhA2Aq, with the Duo design system. The decision page is https://claude.ai/artifact/9GHsANtdG8XHd1hnM8rcsb, and its source is `docs/research/github-issues-decisions.html`.

## Files

- `canvas/make.py` draws the boards as static HTML into `canvas/boards/`. It reuses the task board study's drawn components (lanes, cards, session rows, the project window, the note pane) and the GitHub study's sheet, notice and menu by executing their component sections, so a change there shows here.
- `canvas/render.sh` renders the boards to `canvas/boards/png/<name>@2x.png`. Run it with `TMPDIR` set to a short path.
- `canvas/to-canvas.py <root>` writes them as canvas artboards.

## Boards

| Board | What it shows |
|---|---|
| `00-study` | The ask; what is and isn't in a clone; who does what; what others do |
| `02-model` | A live list, B link (recommended), C mirror, D a Project as the board |
| `03-link` | `issue:` on disk; the issue row in the note's properties; Link Issue… |
| `04-lane` | W-A (recommended): the Issues lane, the issue in the right pane, the filter menu, sign-in, empty |
| `05-where` | W-B, a third segment; W-C, a picker only |
| `06-bridge` | Close #n too, closed on GitHub, "Closes #n" in the Push sheet |
| `07-cards` | The five cards (a box is a task, the round mark is GitHub's); dragging an issue into a lane, and what it writes |
| `08-projects` | Later (ENH-68): a GitHub Project as the board's source; field mapping; the scope step |
| `09-claude` | What Claude is told; Ask Claude to Triage / About It; `duo2 issue` verbs |
| `10-recommendation` | Slices: link (v1), lane (v1.1), Projects later, never mirror |

## New marks, all [P]

- The issue mark: a circle with a dot (open) or a tick (closed), in `text2`.
- `#n` in mono `text2`.
- The issue chip on a task card's line 2.
- "closed on GitHub" in `text` semibold.
- The dashed well of the Issues lane.
