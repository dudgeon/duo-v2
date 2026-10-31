# Markdown editor: a formatting bar with the voice mic — study

Status: research, 2026-10-31, for Geoff's request in `tasks/markdown-toolbar-voice.md`. Nothing here is decided; the design round follows on a Design canvas, and Geoff's pick becomes DL-266. Nothing ships in 0.2.22.

Paths are relative to the repo root. `JS` is `Vendor/codemirror/src/duo-editor.js`. Line numbers are from `origin/main` at 4e809942.

## The short version

- **Duo has no formatting bar today, and no record has ever proposed or turned one down.** Formatting is the **Format menu** plus chords (DL-108, DL-189). The only controls drawn over a document are the **table bar**, shown only while the caret is in a table (DL-113), and the **review bar**, shown only when a document has marks or comments or has Suggest Edits on (DL-237, Q-265).
- **Every format command is a Markdown rewrite** of one undo step (`wrap`, `lineMark`, the table helpers). A bar is a new front end for commands that mostly exist already. What's missing: quote, bullet and numbered list, code block, body text (clear a heading), headings 4–6, underline, and any link UI beyond `[sel]()`.
- **Underline isn't Markdown.** Duo has no underline command, and nothing writes `<u>`. In Duo an underline already means a link (JS:1882) and a suggested insertion (`critic.js:402`). See Q-345.
- **Voice can't reach a document yet.** `VoiceTarget` is `.chat` or `.terminal` only, and `voiceFocusTarget` never returns the editor. The pieces needed are small, though: `duo.insertAtCaret` exists, ⇧⌘D already reaches the menu while the editor has focus, and Suggest Edits would sign dictated words with no extra code.
- **The bar's biggest constraint is height.** The editor usually lives in the right pane: 460 wide by default and 360 at the narrowest (DL-129). Up to three bars can already stack over it (notice, template, review at 44). A fourth always-on bar costs a line of text on every document, so the options weigh merging with the review bar, showing on focus only, or living inside the document.

## 1. How text is formatted today

### Commands (the one table)

`JS:2287-2311`, `commands`, run from Swift as `duo.exec(name)` (`Sources/DuoKit/Navigation/Commands.swift:258-262`):

| Command | What it writes | Chord | Menu | duo2 |
|---|---|---|---|---|
| bold | `wrap("**")` | ⌘B | Format › Bold | `doc format bold` |
| italic | `wrap("*")` | ⌘I | Format › Italic | `doc format italic` |
| strikethrough | `wrap("~~")` (DL-189) | ⇧⌘X | Format › Strikethrough | `doc format strikethrough` |
| code | `wrap("`")` | — | Format › Code | `doc format code` |
| link | `insertLink` (JS:2252-2258): `[sel]()`, caret in the parentheses; `[]()` with nothing selected | ⌘K (DL-108, amends DL-34) | Format › Link… | `doc format link` |
| heading1–3 | `lineMark("# "…)` (JS:2261-2276), replaces a line's heading mark; the same one again removes it | — | Format › Heading ▸ | `doc format heading1…3` |
| task | `lineMark("- [ ] ")` | — | Format › Task | `doc format task` |
| properties | `addProperties` (JS:2280-2285) | — | Format › Add Properties | `doc format properties` |
| table… | see §2 | none (DL-113) | Format › Table ▸ | `doc table …` |

- `wrap` (JS:2231-2249) toggles: wrapped text, or a caret inside or just outside the marks, unwraps. With no selection it puts the pair at the caret, caret between. One range only (`selection.main`). userEvent `input.format`.
- Chords are the menu's, not CodeMirror's. `Sources/DuoKit/Editor/EditorChords.swift:7-48` turns every registry ⌘ chord into a CodeMirror key name. The page gets them as `window.__duoChords` and filters them out of its keymaps (JS:2001, JS:2211-2215). `Sources/DuoChecks/EditorChordChecks.swift` guards this. Format items are enabled when `model.webFocus == .editor` (Commands.swift:186).
- The Format menu replaces `.textFormatting` (Commands.swift:~325-362). `TextEditingCommands()` adds Find, Spelling, Substitutions, Transformations and Speech. View › Source Mode (DL-167 Q3; Commands.swift:409, JS `setSource` :1805) shows plain source with no widgets.

### What doesn't exist

- **No underline**: no ⌘U, no `<u>`, no highlight command.
- **No paragraph commands** beyond H1–3 and Task: nothing for quote, bullet, numbered list, code block, horizontal rule, body (clear) or H4–6. Typing `> `, `- `, `1. ` or a fence just works, because live preview styles them (`buildDecorations`, JS:141-275, `.duo-quote` :1841, `.duo-li` :1838, `.duo-codeblock` :1842).
- **No right-click menu** of Duo's in the editor: `EditorWebView` (`Sources/DuoKit/Editor/DocumentEditor.swift:~862-893`) only overrides Find. The page's one `contextmenu` handler is on frontmatter reference chips (JS:678).
- **No slash menu or input rules.** Autocomplete is for property names and values only (`propertyCompletions`, JS:1000).
- **No selection-state report.** The `selection` message (JS:2109) sends `{from, to, empty, dirty, claudeChanges, atClaudeChange, inTable}`, with no "bold here" or "this line is H2". A bar that shows pressed buttons or names the current style needs that added.

### Automatic behaviour a bar must not fight

- Return continues a list or quote and Backspace removes its mark (lang-markdown's default keymap, `markdown({base: markdownLanguage})`, JS:2197). Pasting a URL over a selection makes a link (`pasteURLAsLink`, the library's default; read from the bundle, not tested).
- Tab / ⇧Tab and ⌘] / ⌘[ indent and outdent list items (DL-244, `src/lists.js:179-185`). Ordered lists renumber (`renumberLists`, lists.js:85).
- `titleFollowsHeading` keeps frontmatter `title:` and the `# ` heading in step (JS:2073). A paragraph-style change on the first heading moves the title too.
- A spreadsheet paste becomes a table (DL-181, JS:1553-1576). An image paste or drop is saved beside the document (JS:1538-1625).

### The comment composer and Review in Markdown

- Built (0.2.21, DL-236, DL-237). Note that `docs/design/README.md` and `system/surfaces.md:70` still say "not built"; Q-347 asks for that to be put right.
- **The comment composer** (`src/margin.js:268-291`) is a plain `<textarea>`: ⌘Return posts, Esc cancels, and the `@` menu (`src/atmenu.js`, DL-251) is its only aid. Newlines become spaces (`addThread`, margin.js:26-33). **It has no formatting**, and a bar shouldn't reach it: comments are single-line CriticMarkup.
- **Tracked changes** are CriticMarkup. The `suggestTyping` transaction filter (`critic.js:384-396`) wraps any single-hunk `input`/`delete` transaction in a signed mark while `suggest-edits: true`. Formatting is caught by the same prefix match (`input.format`, `input.table`):
  - bold on a selection becomes an insertion of `**`…`**`;
  - a one-line heading change becomes a suggestion;
  - a multi-line `lineMark` (several hunks) **passes through untracked**, read from the code, not tested (C-129);
  - a table command rewrites the whole table as one hunk, so it shows as one big substitution.

  A bar inherits all of this; nothing about formatting is tracked as "formatting".
- **The review bar** (`Sources/DuoKit/Project/MarkdownReviewBar.swift`): 44 high (`deckBarHeight`) under the tabs, a `rule` below, Duo's one button style. It holds Markup ⌄, Suggest Edits, ‹ ›, Review All ⌄. Under 420 wide it drops ‹ › and Review All becomes Review ⌄. It shows only when `review.showsBar` (`MarkdownReviewSlot`, :68-78).

## 2. Tables

- **Bundle:** CodeMirror 6 (`Vendor/codemirror/package.json`: `@codemirror/view` 6.43.13, `state` 6.7.6, `commands` 6.11.1, `lang-markdown` 6.5.2, `@lezer/markdown` 1.7.2), built by esbuild to `dist/cm6.js` (`build.sh`). GFM tables come from `markdownLanguage` (JS:2197). Duo has no table extension of its own beyond the code below. Tests: `Vendor/codemirror/test/run.sh` covers critic, lists and atmenu.
- **Drawn** away from the caret as an HTML table (`TableWidget`, JS:1331-1356; `parseTable` :1357). Cells are plain text: `<br>` splits lines, alignment applies, and inline Markdown isn't rendered.
- **Edited as Markdown.** With the caret inside, the source lines show (`duo-table-src`) with the **table bar** above them: `TableBarWidget` (JS:1611-1631), **+ Row, + Column, Align ▾, Delete ▾**, 28 high (`TABLE_BAR`, JS:1327). The bar and source together keep the table's drawn height (DL-167, DL-182).
  - Align ▾ and Delete ▾ post `tableMenu`, and Swift pops an NSMenu (`DocumentEditor.swift:925-934`).
  - The bar is a CodeMirror block widget inside the document, not SwiftUI.
- **Inserted** by Format › Table › Insert Table, `duo2 doc table insert` or a spreadsheet paste. Insert writes three columns, a header and two empty rows, with blank lines around it and `Column 1` selected (`insertTable`, JS:1445; DL-113 t2).
- **Commands** (JS:1368-1500): add row above/below, add column before/after, delete row (the header row is protected), delete column (deleting the last column removes the table), align column. Each rewrites the whole table padded (`writeTable`, `putTable`) as one undo step, userEvent `input.table`.
- **Navigation** (`tableKeymap`, JS:1510-1514, high precedence):
  - Tab / ⇧Tab move to the next/previous cell, selecting it; Tab in the last cell adds a row.
  - Return moves to the same column in the next row, adding a row from the last one.
  - A paste into a cell is made one line, with `|` escaped and newlines turned into `<br>` (JS:1516).
- **Not supported:** column resize, drag handles, rich cells, merged cells (GFM has none).
- **Decided:** DL-113 chose Markdown with commands plus the bar **only while the caret is in the table**. **"C's bar always shown" was turned down**, as were editing in the drawn table (B) and picking a size first. There is no ⌘ chord.
- **Swift knows** the caret is in a table from the `selection` report's `inTable` (JS:2109-2113; `DocumentEditor.swift:~504, ~842`). It drives the Table ▸ items' enabled state (Commands.swift:187-188).
- duo2: `doc table insert|row-above|row-below|column-before|column-after|delete-row|delete-column|align-left|align-center|align-right|next|previous` (`Sources/DuoControl/Actions.swift:358-361`).

## 3. Paragraph styles and links

- **Rendered live:** H1–6 (JS:130-133), lists with hanging indent, quotes, fenced code with a hover Copy (DL-220; `codeHover`, JS:104-128), rules, task boxes (clickable, JS:19-35).
- **Commands exist only for H1–3 and Task** (above). `lineMark` (JS:2261) already does the hard part (every selected line, replaces an existing mark, removes on repeat). Quote, bullet, numbered and body are each one line in `commands`. A code block needs a small new helper: fence the selected lines.
- **Links:**
  - ⌘K / Link… gives `[sel]()` with the caret waiting for the address (DL-108). There's **no link popover**, and no way to edit a link except as text.
  - Live preview hides `[`, `](url)` off the caret's line (JS:228-241) and styles `.duo-link`.
  - A click opens a link; in a raw line it's a ⌘-click (`linkClicks`, JS:2013-2027) → `openLink` → Swift `onOpenLink` (DocumentEditor.swift:~461). Session links get a state glyph (JS:231).
- The chat composer took **"light styling, no WYSIWYG"** (DL-188): the same ⌘B ⌘I ⇧⌘X ⌘E ⌘K keys, with marks kept visible. That's a precedent for keeping Markdown as Markdown.

## 4. Records that bear on a bar

| Record | Gist | Where |
|---|---|---|
| DL-34 | One chord table; a change to it needs a log entry (LR-60) | decisions.md:71 |
| DL-108 | Format gains Code, Link… (⌘K, amending DL-34), Heading ▸ 1–3, Task, Add Properties; `duo2 doc format` | decisions.md:185 |
| DL-113 | Tables: Markdown + Format › Table ▸ + the bar only while the caret is in a table; always-shown bar **not chosen**; no chord | decisions.md:200 |
| DL-167 | Keep CM6 live preview; stable line heights; Source mode; "a calmer per-node reveal is a design study later" | decisions.md:357 |
| DL-182 | The table bar is in the flow (doesn't float); small tables keep one height | decisions.md:376 |
| DL-188 | Chat composer: light styling, no WYSIWYG | decisions.md:387 |
| DL-189 | Strikethrough drawn; ⇧⌘X; ⌘B ⌘I toggle | decisions.md:383 |
| DL-236, DL-237 | Review in Markdown; one Suggest Edits switch; the review bar; the margin and its 420 cut | decisions.md:430, 434 |
| DL-244 | Tab, ⌘] indent and ⇧Tab, ⌘[ outdent list items | decisions.md:440 |
| DL-248 | ⇧⌘E Suggest Edits, ⌥⌘M Add Comment | decisions.md:442 |
| DL-129 | Narrow windows: the right pane gives way to 360 first | decisions.md:265 |
| DL-71 | Every UI action has a duo2 verb | decisions.md |
| DL-260–265 | Voice (§6) | decisions.md:453-458 |
| Q-265 | When the review bar shows (stand-in: marks, comments or Suggest Edits on) | concerns-and-questions.md:328 |
| Q-181 | Does macOS Dictation (fn fn) already work in Duo's text views? Still open | concerns-and-questions.md:159 |
| C-12, F-34, F-43 | WKWebView editor vs native; dictation, Writing Tools and spellcheck were criteria, and their checks are still to do | concerns-and-questions.md:191; findings.md:547, 676 |
| ENH-65, ENH-66 | Line-number gutter deferred; no view-source needed | enhancements.md:71-72 |
| ENH-71, ENH-292 | Voice input; a dictation surviving a switch | enhancements.md:77, 88 |
| LR-30, LR-155 | Byte-faithful saves; TipTap/ProseMirror rejected as not byte-faithful | legacy-requirements.md:94, 155 |
| build plan §3a | v1 Documents: CM6 live preview, no formatting UI listed | build-plan.md:236 |

**Turned down, nearest to a bar:** an always-shown table bar (DL-113), WYSIWYG in chat (DL-188), ProseMirror/TipTap (DL-167, LR-155), and an Editing/Suggesting/Viewing chip (DL-237 2B/2C).

## 5. Design rules for chrome around the editor

- **Stacking under the right pane's tabs** (`Sources/DuoKit/Project/ProjectPanes.swift:902-909`, and :913-920 for the Project tab), top to bottom:
  1. `DocumentStateBar`: ground, padding 10 20, rule below;
  2. `TemplateBar`: ground, padding 10 16;
  3. `MarkdownReviewSlot`: 44;
  4. the editor.

  Any bar joins this stack, or lives inside the page.
- **One button** (`system/components/Button`): 26 high, 12/16, padding 4 10, 1 `controlEdge`, radius 6, `pane`; `selected` when pressed. "Don't invent primary or filled variants."
  - **There is no icon-button component.** Icon controls are per surface: the toolbar's `sidebar.right` in `text2`; the chat mode toggle's 26 × 20 segments; the strip's `+` and pill segments 26 × 20 with a `consoleRule` / `selected` hover; the task line's 18 hover `+`.
  - A bar of glyph buttons needs a new pattern, marked [P].
- **Iconography** (`system/README.md` §Iconography): SF Symbols where they fit; single-weight strokes in `text2`; no filled pictograms.
- **One accent**, and it means needs you. A pressed Bold is `selected`, never `needsYou`.
- **No shadows** except popovers Duo draws (`shadowPopover`). Separate with `rule`.
- **Motion:** a bar that arrives with its view doesn't slide; notices slide with `motionNotice*`. Hover marks are instant.
- **The window's toolbar is closed:** "Don't put actions in the toolbar beyond these" (`components/Toolbar`). The bar can't go up there.
- **Widths:** the right pane is 460 by default and 360 at the narrowest (DL-129). The editor is also the Project tab's document. The review bar and the margin both cut at 420. Inside the page the content has `--duo-document-padding-x`. No other breakpoints exist.
- **Appearances:** Light, Dark (Ink) and Classic (paper, New York 16/27). Use tokens only; `StyleLiteralChecks` fails a hex.
- **Approved editor screens:**
  - `slice3-handoff/screens/editor-document.html`, `editor-states.html`, `editor-notices.html`;
  - `tables-handoff/screens/tables-bar.html` (the 28 bar: 12/16, padding 2 8, gap 6, 6 above the table);
  - `markdown-review-handoff/screens/track-a.html` (the review bar), `margin-narrow.html`;
  - `frontmatter-handoff/` (Properties block);
  - `templates-handoff/template-task.html` (TemplateBar);
  - `voice-input-handoff/screens/composer*.html` and `proof/dl264-*`, `dl265-*` (the mic).

## 6. Voice into the editor

**Today** (DL-260 Apple on-device; DL-261 design; DL-263 Return and Esc; DL-264 terminal mic; DL-265 faint struck mic):

- **Engine:** `Sources/DuoKit/Voice/AppleRecognizer.swift`. SpeechTranscriber with volatile results (:33), SFSpeechRecognizer on-device as the fallback (:53, :90-91). Results arrive as `onResult(text, isFinal)`. `VoiceTranscript.apply` (`VoiceLogic.swift:76`) replaces the volatile tail and returns a phrase when it settles. A phrase is whatever the recognizer finalises; Duo doesn't segment.
- **Targets:** `VoiceTarget` is `.chat(key)` or `.terminal(key)` (`VoiceInput.swift:8-12`). The `Host` (:72-84) has `update` (chat: every result), `paste` (terminal: each settled phrase as a bracketed paste) and `ended`.
- **Chat insertion:** `ComposerTextView.dictate` (`Chat/ChatVoiceDictation.swift:8-38`) inserts at the caret and replaces its own range in place. Still-changing words are in `text2`. The whole dictation is **one undo group** (:17-18, closed :42-60), and Esc discards it by undoing.
- **The look Geoff chose** (`Chat/ChatVoiceViews.swift:20-43`; `voice-input-handoff/`):
  - at rest, `mic` in `text2`, no fill;
  - hover, a `selected` fill with the glyph in `text`;
  - **listening**, a `text` fill with a `pane` glyph, and a hint row with a level meter: "Listening · ⇧⌘D or the mic finishes · esc discards";
  - **no microphone** (DL-265), `mic.slash` in `controlEdge`, no fill even under the pointer, tooltip **"No mic detected · connect one to use transcription"**; a press says "No microphone found."; Edit › "Start Voice Input · no microphone" is disabled.
- **⇧⌘D** is `DuoCommand.voiceInput` (`Navigation/Commands.swift:62, 154, 206, 291, 382`). A tap toggles; holding past 0.3 s is hold-to-talk, through a key-down/up monitor (`Model/AppModel+Voice.swift:68-91`). The target is `voiceFocusTarget` (:9-15), which **never returns a document**, so today ⇧⌘D with the editor focused does nothing.
- **duo2:** `voice start|stop|status|file` (`Sources/DuoControl/Actions.swift:478-482`; `voiceVerb`, AppModel+Voice.swift:152-203), for sessions only.
- Q-181 (does fn-fn system Dictation already work in the editor's WKWebView?) is still open. It's worth answering before the build: if it does, Duo's mic must not fight it.

**What feeding the editor takes** (read from the code, not tried):

| Need | How | Cost |
|---|---|---|
| Insert at the caret | `duo.insertAtCaret` exists (JS:2558-2563; `EditorController.insertAtCaret`, DocumentEditor.swift:694). It replaces the selection, moves the caret and refocuses | none |
| A phrase at a time | the terminal's model: deliver on each settled phrase, space-joined. Optional later: a volatile tail drawn in `text2` as a CodeMirror decoration over a tracked `{from, len}` (the analogue of chat's `dictation` range) | small; the tail is medium |
| Undo as one step | **not free.** Separate `input.type` dispatches merge only by `history()`'s time grouping (JS:2193). Needs a JS helper that keeps the dictation's range and joins its changes into one history event (`isolateHistory` at start and end), with a JS test | small–medium |
| Tracked changes on | free by prefix: `input.type` is caught by `suggestTyping`, and later phrases extend the same signed insertion (`ownInsertionAt`). Dictating over a selection becomes a substitution. A volatile replace would be multi-hunk and skipped, so a tail needs care | small; test it |
| Tracked changes off | plain text, and it clears Claude's green highlight like typing (`clearOnUserEdit`, JS:1308) | none |
| ⇧⌘D routing | a `VoiceTarget.document(path)` returned first when `editorIfLoaded?.hasFocus` and `showingMarkdownDocument` (the test `AppModel+Send.swift:350` already uses), then a case at every `switch target` (~12 sites) | small |
| Return and Esc | Esc ends and keeps the words (DL-263's rule outside chat). **Return in a document shouldn't send anything**: it should finish the dictation and then be the editor's Return. DL-263 doesn't cover documents (Q-346) | small |
| Typing mid-dictation | chat finishes the dictation on a key; the editor needs a JS hook that reports a user edit or caret move back to Swift, or the two interleave | small |
| Read-only, crashed page, outside change | refuse on `setReadOnly`; end on `webViewWebContentProcessDidTerminate` (DocumentEditor.swift:195); `external` merges must keep the dictation's range | small |
| duo2 | `duo2 voice start --doc` (or `start` defaulting to the focused document), `status` naming the document | small |
| Checks | `Sources/DuoChecks/VoiceChecks.swift` gains the document target; `Vendor/codemirror/test/` gains a dictation test | small |

## 7. What this means for the bar

1. **The set.** Geoff's list, mapped to what exists:

   | Geoff asked for | What exists | What's needed |
   |---|---|---|
   | paragraph style | H1–3 and Task commands | Body, Quote, Bullet, Numbered (each one line on `lineMark`); Code block (a small helper); a selection-state report so the control can name the current style |
   | bold | ⌘B, `wrap("**")` | — |
   | italic | ⌘I | — |
   | underline | **nothing** (Q-345) | — |
   | link | ⌘K, `[sel]()` | the same command; a popover is optional and new |
   | insert table | Insert Table | — |
   | table controls | the in-document 28 bar (DL-113) | whether the bar takes them over or leaves them in the document is the main fork between options |
   | transcription | the mic look, ⇧⌘D | the document target (§6) |

   Strikethrough and code are cheap extras, already in Format; whether they earn a place on a minimal bar is a design call.
2. **Height is the cost.** The review bar is already 44. Options to weigh:
   - one bar that carries both formatting and review;
   - a bar only while the document has focus;
   - a bar inside the page (like the table bar);
   - a slim always-on bar.
3. **Table controls:**
   - keep DL-113's in-document bar and give the new bar only Insert Table (no decision changes); or
   - move the four controls into the bar while the caret is in a table, and drop the 28 in-doc bar. That amends DL-113 and DL-182, and changes DL-167's table height arithmetic.
4. **The mic** uses the chat composer's look as is (rest, hover, listening fill, `mic.slash` with DL-265's tooltip), at the bar's trailing end, with the hint row's "Listening · …" moved somewhere the bar can hold it.
5. **Narrow:** at 360 a full set of glyph buttons (~10 at 28 each) only just fits. Options need an overflow (`⋯`) or a fold order; the mic and paragraph style should never fold.
6. **duo2 (DL-71):**
   - `doc format` gains `body|quote|bullet|numbered|codeblock` (and `heading4…6` if offered);
   - `voice start` gains a document target;
   - a bar that can be shown or hidden needs `duo2 view format-bar show|hide|toggle` (or `settings editor format-bar …`).

## Records opened

- **Q-345:** Underline. Markdown has none. `<u>` renders in Obsidian and most viewers, but in Duo an underline already means a link and a suggested insertion. Proposed: leave underline off the bar and out of Format.
- **Q-346:** Return while dictating into a document. Proposed: finish the dictation, then the editor's own Return (a new line); never "send".
- **Q-347:** `docs/design/README.md` and `system/surfaces.md` still list Review in Markdown and voice input as not built. Review shipped in 0.2.21 and voice is merged on main (91e05fcf).
- **C-129:** Formatting under Suggest Edits is uneven. A one-line format change becomes a suggestion, but a multi-line `lineMark` (several hunks) passes through untracked. A bar makes multi-line paragraph changes one click, so this will show. Read from the code (critic.js:384-396), not tested.

## The design round

Canvas: https://claude.ai/artifact/2DqVdN1cA1P6Hv1MW5T8Sb. The boards' source is kept in `canvas/`, and today's captures in `captures/`. The first captures (`today-*`) are Light only, because they came from the main checkout's stale build (v0.2.12-31, 12 Oct), which predates Dark, Classic and Review in Markdown. A fresh build of this branch (code identical to origin/main) draws all of them: `fresh-*` in Dark and Classic, with plain, table and review states. It's not a bug on main.

- **A · a slim strip, always shown** (recommended):
  - 32 under the tabs;
  - table controls take the style menu's place while the caret is in a table (amends DL-113, DL-182);
  - about 5 days.
- **B · one document bar**:
  - the review bar becomes the document's one bar, 44, always shown;
  - Markup and ‹ › fold into Review ⌄ (amends DL-237's bar, Q-265);
  - about 5 days.
- **C · a foot bar while you edit**:
  - 36 at the pane's foot, only while the document has the keyboard;
  - no mic in sight at rest;
  - amends nothing;
  - about 4½ days.
- **Dictating into a document** (every option) and **Q-345, underline**, have their own boards. For underline, U1 (leave it out) is recommended; U2 is `<u>` with ⌘U.
