# Duo: LLM wikis and second brains (knowledge bases) — design study

Status: **choices decided by Geoff, 2026-10-07 (DL-152)**: an alpha power-user feature in Settings, ⇧⌘N for a new inbox note in the editor, a Knowledge base tab only where added, no processing prompt, search as today. Boards 11 to 14 are drawn to his answers and await his look; then they're exported to `docs/design/knowledge-base-handoff/` before any build. Every mark is [P] until then; boards 3 to 8 and 10 are the options as first proposed.

Geoff, 2026-10-07: "many users will have a project (or more) that contain LLM wiki and or OKF second brains … think about what features we could add (not just a pile of features but thoughtful service design) to better support these uses without getting in others' way." The study is `docs/research/second-brains.md` (research, journeys, principles, ranked candidates, the v1 slice); its sources are in `docs/research/second-brain-sources/`.

The canvas, https://claude.ai/artifact/PPh9UPgT3fd9NSvgbcEz38, holds 15 boards drawn with the Duo design system. `canvas/make.py` draws them (reusing the project & task CX study's helpers, which reuse home-evolution's), `canvas/render.sh` renders them to `canvas/boards/png/`, and `canvas/to-canvas.py <root>` writes them as canvas artboards.

| Board | What | Question |
|---|---|---|
| `00-study` | Who, what the research found, the principles | — |
| `01-blueprint` | The journeys as a service blueprint: person, Duo, Claude, files, what stays the person's | — |
| `02-ranking` | Candidates ranked, and what's dropped | — |
| `03-mark` | Use as Knowledge Base…: the menu, the sheet (what Duo found, inbox, template, index, log, schema; writes nothing), and the checkbox in DL-147's "A folder I have" | Q-129, Q-130 |
| `04-kb-in-duo` | The tile (Knowledge base · 12 in inbox, the log's newest line), the INBOX fold with Process with Claude, the Index tab | — |
| `05-capture` | A: a global panel on ⌃⌥⌘N over any app; B: a sheet in Duo only; the note it writes | Q-131 |
| `06-process` | A: the folder's `/process-inbox` drafted; B: Duo's instruction with Save as Command…; then Claude proposes and waits | Q-133 |
| `07-index-log` | A: Index and Log tabs; B: one Knowledge base tab | Q-132 |
| `08-search` | Search opens narrowed inside a knowledge base | Q-134 |
| `09-reading-a-vault` | For everyone: wikilinks drawn and followed, unresolved links, embeds (F-202) | — |
| `10-slice` | The slice as first proposed, and the questions | — |
| `11-settings` | **Decided:** Settings › Knowledge bases (alpha), and the Add/Edit sheet | DL-152 (1), (2) |
| `12-new-note` | **Decided:** ⇧⌘N makes a note in the inbox, opened in the editor; New Folder → ⌥⇧⌘N | DL-152 (3) |
| `13-kb-tab` | **Decided:** the Knowledge base tab, only where added | DL-152 (4) |
| `14-decided` | **Decided:** the v1 slice, what's out, what Claude is told | DL-152 |

## duo2 (DL-71)

`duo2 kb add|edit|remove|list|show`, `duo2 note new [--kb <p>] [--stdin]`.

## Files Duo would write

Only the notes people make with ⇧⌘N (`<inbox>/YYYY-MM-DD-HHmm.md` from `templates/new-note.md`: `type: note`, `created`). Adding a knowledge base writes nothing in the folder (DL-152 (2)). Duo never writes `index.md`, `log.md` or `.obsidian/`.
