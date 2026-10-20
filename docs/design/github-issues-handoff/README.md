# Duo: GitHub issues, slice 1 (a task links an issue) — design handoff

Status: approved by Geoff (DL-226). Slice 1 is v1; the Issues lane (boards 04, 05, the issue cards and the drag on 07) is v1.1 and is **not** in this handoff. The canvas is https://claude.ai/artifact/9jwpM4HimuucECDXNhA2Aq; the full study, its other boards and sources are in `../github-issues-study/`. The screens here are unchanged copies of the canvas boards (static HTML, `png/` at 2x).

## Targets

| Screen | Build | Not in slice 1 |
|---|---|---|
| `03-link` | `issue:` with one quoted URL in the task's frontmatter; the **issue row** in the note's properties (mark, `#n title`, state and labels in `text2`, open arrow); Link Issue… (a search field over the repo's open issues, paste a link or `#number`); right-click: Open on GitHub, Copy Link, Change Issue…, Unlink | Opening the issue in the right pane (board 4, v1.1) |
| `06-bridge` | Mark Complete's notice gains **Close #n too** (`gh issue close`; Undo reopens); line 2 **#n closed on GitHub** (`text` semibold); the note's issue row offers Mark Done / Reopen Task; Push's drafted PR body ends with one `Closes #n` per open task that tracks an issue in the repo, as ticked rows (in-progress ticked, others not) | — |
| `07-cards` | Cards 1 to 3 only: a task; a task that tracks an issue (the issue chip leads line 2: mark, `#n` in `text2`); closed on GitHub | Cards 4, 5 and the drag (lane) |
| `09-claude` | Context. New Issue from Task and the `duo2 issue` verbs | Ask Claude to Triage / About It |

## Rules

- Duo writes to GitHub only: Close/Reopen, New Issue from Task, and `Closes #n` in Push's PR. Nothing creates a task from an issue.
- `gh` is the path to GitHub. Without gh or access, the state it can show is shown and the row says why.
- Every action has a `duo2` verb (DL-71).
- Anything the boards don't draw is a stand-in and a question (Q-231).
