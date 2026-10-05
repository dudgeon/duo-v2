# Duo properties (frontmatter) — design handoff

Status: designed · 2026-10-04 · Owner: Geoff · Covers DB-16 of `design-brief-2026-10-04.md` and ENH-1. Written by the design session (Claude).

> **Designed, not built (2026-10-05).** The editor still shows frontmatter as raw YAML. Its tokens are merged into `build-handoff/tokens.json` (`size.propertiesBlock`, the property icons).

Same shape as the other handoffs, and the same rule: the files in `screens/` are the target. This document explains them and covers what a picture cannot show.

| File | What it is |
|---|---|
| `screens/frontmatter*.html` | 12 targets, 460×900: **the right pane alone**, tab strip included. One sheet, 1440×720. Exported unchanged from the canvas (page "Frontmatter", rows B). |
| `screens/manifest.json` | Every screen, its size and what it shows. |
| `tokens-additions.json` | Sizes and eight icons. No new colours, no new type sizes. |
| `fixture-frontmatter.json` | The sample files and every suggestion list on the screens. |
| `tools/render-references.sh` | Renders the PNGs with build-handoff's renderer. Run on the Mac. |

The targets are the pane alone because the rest of the window has moved on since the first handoff (the session list, tasks). Nothing outside the pane is specified here. PNGs are not included: they need the Mac's system faces. I rendered every screen in a Linux browser with fallback fonts to check layout; nothing overflowed or collided.

## How to read this

- **[G]** Geoff decided it.
- **[B]** A brief, an LR or a DL requires it.
- **[P]** My proposal. Change freely.

---

## 1. What Geoff decided [G]

1. **The frontmatter is shown as the YAML itself, with help around it** (treatment A2 on the canvas), not as a table of fields or a designed header.
2. Tab moves between fields, and **Tab from the last one makes a new one**.
3. Names and values **autocomplete**.
4. Each field has a **type picker**.
5. Dates use a **date picker, the Mac's own if possible**.

Everything else below is [P] unless marked.

## 2. The block

Reference: `frontmatter.html`, and the sheet `frontmatter-look.html`.

The block is the document's own first lines, decorated in place. It is not a separate form with its own copy of the data. That is what makes saves byte-faithful [B: LR-30]: the text in the block is the text in the file, and undo is the document's undo.

| Part | Spec |
|---|---|
| Where | The top of any Markdown document that has frontmatter: `PROJECT.md` in the Project tab [B: DL-60], `HOME.md`, task notes [B: DL-87], anything else. |
| Heading | Fold chevron, `PROPERTIES · n` in the section-label style, and a `+` on the right that adds a property. Padding 14 20 6. |
| Block | 16 in from the pane's edges. `ground` fill, radius 6, padding 8 12. Mono 12/19. Both `---` fences are shown, in `text2`. |
| Line | At least 22 high. A 14-wide gutter with the type's icon, then the name and colon in `text2`, then the value in `text`. A control follows the value when the type has one. |
| The line with the caret | `pane` (white) fill, radius 4, reaching 6 past the text on each side. It reads as a field. |
| Under the block | A 1 `rule` line 14 below, then the document. |
| Folded | The heading alone, chevron pointing right. Unfolded by default [B: LR-37]; the choice is remembered per document. |
| No frontmatter | No heading and no block. |

Only the name and the value are in the file. The icon, the controls and the fill are Duo's.

## 3. Types

The type is read from how the value is written, so nothing is stored outside the file and nothing is written to `.obsidian/` [B: DL-20].

| Type | Written as | Control on the line |
|---|---|---|
| Text | `on-track`, quoted only when YAML needs it | |
| List | `[a, b]`, or one `- item` per line | |
| Number | `15` | |
| Checkbox | `true` / `false` | A checkbox before the word. Clicking it rewrites the word. |
| Date | `2026-10-14` | A calendar button. |
| Date and time | `2026-10-14T09:30` | A calendar button. |
| Link | `"[PRD v2](docs/prd-v2.md)"` [B: DL-17] | A button that opens it. |

- Seven types: the brief's five (text, list, date, checkbox, link) plus number and date-and-time, which Obsidian has.
- `aliases` and `tags` are always lists [B: Obsidian's own rule].
- **A link shows as its title, underlined, until the caret is on its line. Then it is the raw text.** This matches how links behave in the document body. It differs from the exploration board, which showed the raw link at rest; I changed it after reading DL-93, because a session link is over 70 characters and a list of them would wrap on every line. See Questions.

**Changing a type** (`frontmatter-type.html`). Click the gutter icon; a native menu lists the seven, with a tick on the current one. Choosing one rewrites the value to match when it can: text to a one-item list, a list to text joined by commas, text that reads as a date to the ISO form. When it can't ("Exec review Oct 14" is not a date), choosing Date opens the calendar and nothing changes until a date is picked.

## 4. Typing, Tab and suggestions

| Key | Does | |
|---|---|---|
| `tab` | Selects the next value. Past the last one: a new line, ready for a name. | G |
| `⇧tab` | Selects the previous value. | P |
| `↩` | At the end of a line: a new line under it. Elsewhere, what Return does in text. | P |
| `⌥esc` | Offers suggestions here; on a date, opens the calendar. The Mac's own completion key. | P |
| `esc` | Hides the suggestions and keeps what is typed. | P |
| `⌘↩` | Opens the link on this line. | P |
| `⌥↑` `⌥↓` | Moves the line up or down. | P |
| `⌘Z` | Undo, as anywhere in the document. | B: LR-37 |

- Tab on a new line that was left empty removes the line and carries on into the document.
- `↑` from the first line of the document goes into the last property, since the block is part of the same text.
- Arrow keys, selection, copy and paste are ordinary text editing.
- None of these is a new app-wide chord; they apply only while the caret is in the block. `⌘↩` already means "jump into the selected card's project" while the peek is open; the two never overlap.

**A new property** (`frontmatter-new.html`). Typing a name offers names used elsewhere: this project's first, then every project's, most used first, leaving out names this document already has. Each shows its type and how many documents use it. The last row is always `New property "…"`. Tab or Return takes the highlighted row, writes `name: `, and sets up the value for its type: the calendar opens for a date, `false` appears with its checkbox, a list starts.

**Values** (`frontmatter-value.html`, `-list`, `-link`).

| For | Offers |
|---|---|
| A text value | What other documents put under the same name, most used first. It never limits what can be typed. |
| A list item | Items other documents have under the same name. |
| A link | Files in the project, by title or path. Choosing one writes the quoted Markdown link. A web address typed or pasted is kept as it is. |

**Suggestions panel.** 300 wide for names, 280 for values, hung under the caret's line. `pane` fill, 1 `rule` border, radius 10, the popover shadow. Rows 26 high: type icon, text with the typed part semibold, and a count right-aligned in 12 `text2`. The chosen row has `selected` fill. A last line of key hints.

**Dates** (`frontmatter-date.html`) [G: the Mac's own]. The calendar button, or `⌥esc`, opens the system date picker in a popover; the screen's calendar is my drawing of it, and the system's wins. A date can also be typed: "oct 14", "tomorrow", "next fri" are turned into the ISO form when the caret leaves the line. The file always gets `2026-10-14`.

**Lists.** Whichever style the file uses is kept. Tab moves from item to item. In a one-per-line list, Return at the end of an item starts another, and Return on an empty item ends the list. A list Duo starts is written one per line, as Obsidian writes them.

## 5. States

| Screen | Shows | Notes |
|---|---|---|
| `frontmatter` | At rest, caret in a value | |
| `frontmatter-new` | Tab past the last one | §4 |
| `frontmatter-value` · `-list` · `-link` | Suggestions for a value | §4 |
| `frontmatter-type` | The type menu | §3 |
| `frontmatter-date` | The calendar | §4 |
| `frontmatter-task` | A task note | `sessions:` is a list of links, one per line [B: DL-93]. Each shows as the session's title with a button that opens the session [B: DL-87]. |
| `frontmatter-claude` | A line Claude changed | `selected` fill and the words `changed by Claude`, right-aligned in the UI face. Clears on the next edit [B: LR-33, DL-5]. |
| `frontmatter-invalid` | Text that doesn't parse | The first offending line gets a 1.5 `text` outline. The heading reads `Not valid YAML · line 4`. A line under the block says what is wrong. Lines from the error on lose their icons and controls. Nothing is rewritten, and typing is saved as it is [B: shown, not thrown away]. |
| `frontmatter-folded` | Folded | §2 |
| `frontmatter-none` | A document that had none | Typing `---` on the first line, or Format › Add Properties, starts the block with the most-used names on offer. |
| `frontmatter-look` | The parts | A line and its states, the types, the controls, lists over several lines, a long value, the keys. |

**What Duo never does.** It never reorders lines, changes quoting, removes comments or touches a line that wasn't edited [B: LR-30, LR-37]. A new property goes on the end, before the closing fence. Keys Duo doesn't know, nested values and Obsidian's own keys are ordinary lines here: shown, editable as text, never dropped.

**Narrow pane.** At the pane's 360 minimum, a long value wraps under itself and stays one property, with its icon on its first line (`frontmatter-look`).

**VoiceOver.** A line reads "health, text, on-track". The gutter icon is a button: "Type: text. Change type." The controls are labelled for what they do: "Pick a date", "Open PRD v2".

**From Claude.** Everything here needs a `duo2` verb [B: DL-71]. I'd suggest `duo2 doc prop list | get | set | remove | type`.

## 6. Changed since the exploration board

- No `Show as fields` button: the table of fields (A1) is not part of this design.
- Links fold to their titles away from the caret (§3).
- A `+` in the heading.
- The line with the caret is white, not grey, so it can't be confused with the grey that marks Claude's changes.

## 7. Questions for Geoff

| Question | My default |
|---|---|
| Should a link show as its title until the caret is on its line? | Yes. Raw session links would wrap on every line of a task note. |
| When Duo starts a new list, one item per line or inline in brackets? | One per line, as Obsidian writes them. |
| In a task note, should `status` offer the six fixed statuses or whatever has been used before? | The six, in their order. |

## 8. Not designed

- The time part of a date-and-time value.
- Dragging a line to reorder it (the keys cover it).
- Multi-line text values written with `|` or `>`. They are plain text lines here.
- A right-click menu for a line. Suggest the editor's own, plus `Change Type ▸` and `Delete Property`.
- Hover states. Dark appearance.
