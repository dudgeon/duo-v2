# Duo: source links for downloaded files — design study

Status: **decided, DL-163** (Geoff, 2026-10-08). Every mark on these boards is a proposal [P]. Boards 2, 10, 12 and 13 were redrawn to his choices. The approved boards go to `docs/design/source-links-handoff/screens/` when he has looked at them.

Geoff, 2026-10-08: work runs on Google Docs and Slides, which neither Duo nor Claude can reach. He downloads a .pptx or .docx and wants Duo to know the canonical link, open it in the browser, replace a snapshot with a newer download, and perhaps watch Downloads and offer a side-by-side compare. The research is in `docs/research/source-links.md` (F-238 to F-241). The boards are on the Design canvas https://claude.ai/artifact/Xi3FfJt9ALcxLMNC3WK5rM, drawn with the Duo design system.

## Files

- `canvas/make.py` draws the 14 boards as static HTML into `canvas/boards/`. It reuses the GitHub study's helpers, which reuse the home-evolution study's tokens, CSS and glyphs.
- `canvas/render.sh` renders them to `canvas/boards/png/<name>@2x.png`. Run it with a short `TMPDIR` (board-compare tooling).
- `canvas/to-canvas.py <root>` writes them as canvas artboards.
- The deck viewer's bar is copied from the approved `pptx-handoff/screens/pptx-viewer.html` (DL-125).

## Boards

| Board | What it shows |
|---|---|
| `00-study` | The ask, what the research found, the principles |
| `01-journey` | A service blueprint: Geoff, Duo on screen, Duo behind, macOS and the browser, Claude, across seven moments |
| `02-thin-bar` | The thin bar (DL-163): the link offered in one click, no link known, source added, a newer download with no source |
| `03-bar` | The source in the viewer: A, a line under the bar (chosen); B, a button opening the popover |
| `04-popover` | The source popover (open, copy, Get Latest, snapshots, the slide in Slides); Add Source… |
| `05-files` | The link mark in Files; `_sources.md` as an ordinary file; the Source, compare and replace items in the right-click menu |
| `06-newer` | Newer downloads with or without a source; Get Latest for Google links; no changes; nothing seen (Choose File…) |
| `07-compare-deck` | Compare a deck: A, two columns paired by Google slide id (recommended); B, one slide, flicking |
| `08-compare-doc` | Compare a document: a redline with Mine \| Changes \| Download |
| `09-replace` | Replace with Undo; what's kept: Trash only (chosen), dated copies, ask |
| `10-where-kept` | `_sources.md` (DL-163): the file, as Obsidian shows it, and its rules |
| `11-claude` | What Claude is told; the `duo2 file source/latest/compare/replace/snapshots` verbs (DL-71) |
| `12-recommendation` | What's decided, slice 1, slice 2, later |
| `13-matching` | How a download is matched as a newer copy, with no source needed |

## Owned elsewhere

- **The docx viewer and its bar** (DL-162) belong to the docx viewer session (`design/docx-viewer`). Board 8 and the docx half of board 3 follow whatever that bar becomes; this study adds only the source line under it.
- **The deck viewer's bar** is DL-125's, unchanged.
