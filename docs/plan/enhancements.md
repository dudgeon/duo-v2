# Enhancements

Ideas Geoff wants that aren't scheduled yet (ENH-n). Each says what and why; when one is picked up it moves into the build plan with a phase.

| # | Enhancement | Why / notes | Logged |
|---|---|---|---|
| ENH-1 | **Frontmatter editing in the markdown editor**: Obsidian-compatible, but elegant and useful. Properties shown and edited as typed fields (text, list, date, checkbox, link) instead of raw YAML, with the YAML staying byte-faithful (LR-30) and readable by Obsidian (DL-6, `docs/research/obsidian-compatible-task-format.md`). | Builds on LR-37 (properties panel, expanded by default, typed one-click edits with undo, body untouched by property edits) and the task format research. Needs a design pass (Q-20 covers editor internals). | 2026-10-03 |
| ENH-2 | **Editing modes for JSON files**: a JSON-aware view in the right pane (syntax colouring, folding, validation; perhaps a structured view for JSONL records). | Projects carry JSON and JSONL (data, configs, Claude records). Today the editor treats them as plain text. Not urgent. | 2026-10-03 |
