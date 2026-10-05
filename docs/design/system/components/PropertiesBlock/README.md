A note's frontmatter, decorated in place above its text: the YAML itself, with help around it.

**Status:** Built in part (DL-100, slice2 `task-note.html`): the heading, the block, muted names, the active line, a task note's `status:` popup and `+ Add`, and `sessions:` lines with each session's live state glyph and wait. Still designed, not built (DB-16, `docs/design/frontmatter-handoff/`): type icons, suggestions, Tab between values, the type menu, the date picker, the invalid and folded states. **In code:** `Vendor/codemirror/src/duo-editor.js` (`propertiesField`), Swift side `Model/AppModel+Tasks.swift` (`pushNoteContext`, `propertyAction`).

**Anatomy (from the handoff):** a `ground` block inset `propertiesBlockMargin` (16), `propertiesBlockRadius` (6), padding 8 12, under a `sectionLabel` heading; lines at least `propertiesLineMinHeight` (22): a type icon (`assets/Icons/property*.svg`), the name in `text2`, the value in `text`; the active line on `pane`; Claude's changes on `selected` with "changed by Claude"; an invalid value outlined 1.5 `text`. Suggestions popover `propertiesSuggestionsWidth` (300), radius 10, `shadowPopover`; dates use the system picker.

**Matters for tasks:** status and the `sessions:` links (DL-93) read best here. Build from the handoff's screens.
