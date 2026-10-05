A note's frontmatter shown as typed fields above its text, instead of raw YAML.

**Status:** Designed, not built (DB-16, `docs/design/frontmatter-handoff/`, 13 screens). Today the editor shows raw YAML.

**Anatomy (from the handoff):** a `ground` block inset `propertiesBlockMargin` (16), `propertiesBlockRadius` (6), padding 8 12, under a `sectionLabel` heading; lines at least `propertiesLineMinHeight` (22): a type icon (`assets/Icons/property*.svg`), the name in `text2`, the value in `text`; the active line on `pane`; Claude's changes on `selected` with "changed by Claude"; an invalid value outlined 1.5 `text`. Suggestions popover `propertiesSuggestionsWidth` (300), radius 10, `shadowPopover`; dates use the system picker.

**Matters for tasks:** status and the `sessions:` links (DL-93) read best here. Build from the handoff's screens.
