# Duo: source links for downloaded files — design study

Status: **study; Geoff's choices pending** (DL-163 is reserved for them). Every mark on these boards is a proposal [P]. Once Geoff approves, the chosen boards are exported to `docs/design/source-links-handoff/screens/`.

Geoff, 2026-10-08: work runs on Google Docs and Slides, which neither Duo nor Claude can reach. He downloads a .pptx or .docx and wants Duo to know the canonical link, open it in the browser, replace a snapshot with a newer download, and perhaps watch Downloads and offer a side-by-side compare. The research is in `docs/research/source-links.md` (F-238 to F-241). The boards are on the Design canvas https://claude.ai/artifact/Xi3FfJt9ALcxLMNC3WK5rM, drawn with the Duo design system.

## Files

- `canvas/make.py` draws the 13 boards as static HTML into `canvas/boards/`. It reuses the GitHub study's helpers, which reuse the home-evolution study's tokens, CSS and glyphs.
- `canvas/render.sh` renders them to `canvas/boards/png/<name>@2x.png`. Run it with a short `TMPDIR` (board-compare tooling).
- `canvas/to-canvas.py <root>` writes them as canvas artboards.
- The deck viewer's bar is copied from the approved `pptx-handoff/screens/pptx-viewer.html` (DL-125).

## Boards

| Board | What it shows |
|---|---|
| `00-study` | The ask, what the research found, the principles |
| `01-journey` | A service blueprint: Geoff, Duo on screen, Duo behind, macOS and the browser, Claude, across seven moments |
| `02-arrival` | A file arrives (Q-157): A, recorded at once with Undo (recommended); B, offered in the bar |
| `03-bar` | The source in the viewer: A, a line under the bar (recommended); B, a button opening the popover |
| `04-popover` | The source popover (open, copy, Get Latest, snapshots, the slide in Slides); Set Source… |
| `05-files` | The link mark in Files, with the note folded away; the Source group in the right-click menu |
| `06-get-latest` | Get Latest through the browser and Spotlight: waiting, arrived, no changes, nothing seen (Choose File…) |
| `07-compare-deck` | Compare a deck: A, two columns paired by Google slide id (recommended); B, one slide, flicking |
| `08-compare-doc` | Compare a document: a redline with Mine \| Changes \| Download |
| `09-replace` | Replace with Undo; what's kept (Q-156): Trash only (recommended), dated copies, ask |
| `10-where-kept` | Where the link lives (Q-154): A, a note beside the file, shown in Obsidian too (recommended); B, one list; C, Duo only; not inside the file |
| `11-claude` | What Claude is told; the `duo2 file source/latest/compare/replace/snapshots` verbs (DL-71) |
| `12-recommendation` | The recommendation, the v1 slice, later |

## Owned elsewhere

- **The docx viewer and its bar** (DL-162) belong to the docx viewer session (`design/docx-viewer`). Board 8 and the docx half of board 3 follow whatever that bar becomes; this study adds only the source line under it.
- **The deck viewer's bar** is DL-125's, unchanged.
