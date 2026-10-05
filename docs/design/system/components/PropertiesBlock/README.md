A note's frontmatter, decorated in place above its text: the YAML itself, with help around it.

**Status:** Designed and built (DB-16, `docs/design/frontmatter-handoff/`, F-77; one look everywhere, task notes adding their status popup and session lines, DL-102). Not built: natural-language dates typed in place, Format › Add Properties. **In code:** `Vendor/codemirror/src/duo-editor.js` (`propertiesField`, `propertyCompletions`), `Live/PropertyCorpus.swift` (suggestions), `Model/AppModel+Tasks.swift` (`propertyAction`: status, + Add, type menu, date picker). `duo2 doc prop` reads and sets properties.

**Anatomy (from the handoff):** a `ground` block inset `propertiesBlockMargin` (16), `propertiesBlockRadius` (6), padding 8 12, under a `sectionLabel` heading; lines at least `propertiesLineMinHeight` (22): a type icon (`assets/Icons/property*.svg`), the name in `text2`, the value in `text`; the active line on `pane`; Claude's changes on `selected` with "changed by Claude"; an invalid value outlined 1.5 `text`. Suggestions popover `propertiesSuggestionsWidth` (300), radius 10, `shadowPopover`; dates use the system picker.

**Matters for tasks:** status and the `sessions:` links (DL-93) read best here. Build from the handoff's screens.
