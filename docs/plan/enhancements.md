# Enhancements

Ideas Geoff wants that aren't scheduled yet (ENH-n). Each says what and why; when one is picked up it moves into the build plan with a phase.

| # | Enhancement | Why / notes | Logged |
|---|---|---|---|
| ENH-1 | **Frontmatter editing in the markdown editor**: Obsidian-compatible, but elegant and useful. Properties shown and edited as typed fields (text, list, date, checkbox, link) instead of raw YAML, with the YAML staying byte-faithful (LR-30) and readable by Obsidian (DL-6, `docs/research/obsidian-compatible-task-format.md`). | Builds on LR-37 (properties panel, expanded by default, typed one-click edits with undo, body untouched by property edits) and the task format research. Needs a design pass (Q-20 covers editor internals). | 2026-10-03 |
| ENH-2 | **Editing modes for JSON files**: a JSON-aware view in the right pane (syntax colouring, folding, validation; perhaps a structured view for JSONL records). | Projects carry JSON and JSONL (data, configs, Claude records). Today the editor treats them as plain text. Not urgent. | 2026-10-03 |
| ENH-3 | **`@` autocomplete for files and folders in a Claude session, from Duo**: type `@` and keep typing in a session's prompt; Duo offers matching file and folder names and, on choosing one, puts its path in the prompt. | Claude Code's own prompt already completes `@` paths inside the session's folder (it draws the list itself in the TUI). Duo's version earns its place by reaching further: other projects, Home, anything Duo indexes (search M1). Feasibility: SwiftTerm doesn't parse Claude's prompt; Duo would watch keystrokes it forwards (it sees every key typed into the terminal view) and show a native popover anchored at the caret cell, then send the chosen path as typed text. Needs a design pass (popover look) and a decision on clashing with Claude's own `@` list. **On hold: Geoff tries Claude Code's own `@` first (G-5).** | 2026-10-04 |
| ENH-4 | **Revert Claude's changes from the editor**: on text highlighted as added or changed by Claude, a way to undo that one change (per highlight) and to revert all of Claude's changes since you last looked, restoring the exact previous text. | Claude's edits now arrive through the editor (`duo2 doc replace|insert`) highlighted, but the only way back is ⌘Z, which also walks back your own typing. Builds toward DL-5's tracked suggestions and version history. Needs a design pass (the affordance on a highlight, and where "revert all" lives). | 2026-10-04 |

## Geoff's to-dos

| # | To do | Logged |
|---|---|---|
| G-1 | Write a `PROJECT.md` template (DL-60): the fields and sections a project should start with. Duo will offer it for new projects and as the Project tab's content. | 2026-10-03 |
| G-2 | Try Writing Tools (select text in a document, right-click) and dictation (Edit › Start Dictation) in the editor (F-43). | 2026-10-03 |
| G-3 | Run the search design brief through Claude Design (`docs/design/search-design-brief.md`). | 2026-10-03 |
| G-4 | Test Duo on the work Mac (DL-31, C-1). | 2026-10-03 |
| G-5 | Try Claude Code's own `@` autocomplete in a Duo session (type `@` then part of a file name in the prompt) before deciding on ENH-3. | 2026-10-04 |
