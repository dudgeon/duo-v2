# Duo: LLM wikis and second brains (knowledge bases) — design study

Status: **study, every mark [P]**; awaiting Geoff's choices (Q-129 to Q-134), then DL-152. Not exported as a handoff and not built: once Geoff picks, the boards are redrawn to his answers and exported to `docs/design/knowledge-base-handoff/` before any build.

Geoff, 2026-10-07: "many users will have a project (or more) that contain LLM wiki and or OKF second brains … think about what features we could add (not just a pile of features but thoughtful service design) to better support these uses without getting in others' way." The study is `docs/research/second-brains.md` (research, journeys, principles, ranked candidates, the v1 slice); its sources are in `docs/research/second-brain-sources/`.

The canvas, https://claude.ai/artifact/PPh9UPgT3fd9NSvgbcEz38, holds 11 boards drawn with the Duo design system. `canvas/make.py` draws them (reusing the project & task CX study's helpers, which reuse home-evolution's), `canvas/render.sh` renders them to `canvas/boards/png/`, and `canvas/to-canvas.py <root>` writes them as canvas artboards.

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
| `10-slice` | The v1 slice, what Claude is told, duo2 verbs, the questions | — |

## duo2 (DL-71), proposed

`duo2 kb use|off|show <project> [--inbox <folder>]`, `duo2 capture [--kb <p>] [--title …] [--source <url>] [--stdin | text]`, `duo2 inbox [<kb>]`, `duo2 inbox process [<kb>]`, `duo2 kb index|log [<kb>]`. Search narrowing already has `duo2 search --project`.

## Files Duo would write

Only a captured note (`<inbox>/<date>-<slug>.md` from `templates/new-note.md`: `type: note`, `title`, `created`, `source` when given) and, on Save as Command…, `.claude/commands/process-inbox.md`. Marking a knowledge base writes nothing in the folder (Q-130 A). Duo never writes `index.md`, `log.md` or `.obsidian/`.
