# Duo: the Markdown formatting bar, with the mic — design handoff

Status: approved by Geoff, 2026-10-31 (DL-266). Build after 0.2.22.

The boards were drawn on the Design canvas https://claude.ai/artifact/2DqVdN1cA1P6Hv1MW5T8Sb with the Duo design system; every new mark is a [P]. Geoff chose option A, "but much slimmer; only while editing/carat is in the editor", then said yes to the redrawn board. They're exported here as static HTML (`screens/`, listed in `screens/manifest.json`), with PNGs at 2x in `screens/png/`.

Before building, read the research: `docs/design/markdown-toolbar-study/README.md`. It covers how Duo formats text today, what the bundle supports, the voice code, and the records. Its `canvas/` folder holds every board's source, including the options not chosen (B, C, and A at 32).

**Build:** `bar` (the target), `dictation` (behaviour only: its strip is drawn as A's 32 one; the look and size are `bar`'s), `underline` (U1 chosen: nothing to build except leaving it out). On each board, the blocks under a small capitals label are the spec, not UI. Names and documents are illustrative.

## The bar (`bar`)

- **Size and look.** 24 high (new token `formatBarHeight`), on `pane`, with a `rule` below.
  - Glyph controls are 24 × 20, radius 5, marks 13 in `text2`. On, or under the pointer, they get a `selected` fill with the mark in `text`. Never the accent.
  - Style ⌄ and the table buttons are 12/16, 20 high.
  - Separators are 12 high.
  - The mic is 20 round with a 12 glyph.
  - The bar starts 22 in from the left, so Style's word lines up with the text at 28.
  - Tooltips give the menu name and chord: Bold ⌘B, Italic ⌘I, Link ⌘K, Start Voice Input ⇧⌘D.
- **Contents.**
  - Style ⌄ names the paragraph at the caret and offers Body, Heading 1–3, Quote, Bulleted List, Numbered List, Task and Code Block.
  - Then Bold, Italic, Link, Insert Table and ⋯ (Strikethrough ⇧⌘X, Code).
  - The mic sits at the trailing end.
  - No underline (Q-345).
  - Clicks never take focus from the text.
- **When it shows.** While a Markdown document has the keyboard (`webFocus == .editor`; the pane's focus rule, DL-165, is on). It stays while one of its menus is open and while a dictation runs.
  - It isn't shown on read-only files, a template's preview, or Source mode.
  - It appears and goes at once, with no motion.
  - View › Hide Formatting Bar turns it off (`duo2 view format-bar show|hide`).
- **Over the editor, never pushing it.** The bar is laid over the top of the editor's viewport.
  - The document's top padding goes from 22 to 24, so at the top the bar sits in the padding and no line moves between "not editing" and "editing".
  - Scrolled, the text passes under the opaque bar.
  - CodeMirror gets a 24 top scroll margin (`EditorView.scrollMargins`), so the caret, a find match or a review step never stops under it.
  - The review bar (DL-237) keeps its place in the pane's stack above the editor. This bar overlays the editor below it.
- **In a table.** + Row, + Column, Align ⌄ and Delete ⌄ (Format › Table's commands) take Style's place after Bold, Italic and Link.
  - Under 420, Align and Delete fold into ⋯.
  - **The 28 `TableBarWidget` inside the document goes** (amends DL-113 and DL-182). The table keeps its drawn height (DL-167), with the 28 the in-document bar took now going to the source rows.
- **Narrow.** At 360 everything fits at rest (about 270). The mic never folds.
- **Listening.** The controls give way to chat's hint row: the meter, "Listening", then "· ⇧⌘D or the mic finishes · esc ends" (shortened from the right when narrow). The mic fills with `text` and its glyph turns `pane`.
- **No microphone.** DL-265's faint `mic.slash` in `controlEdge`, with no fill even under the pointer. Its tooltip reads "No mic detected · connect one to use transcription". A press says "No microphone found." in the bar.
- **Appearances.** Tokens only, so Light, Dark and Classic come free (Classic: New York 16/27, orange focus rule).

## Dictating into a document (`dictation`, DL-266 item 6)

- **Where words go.** At the caret, a phrase at a time; over a selection, they replace it. Words still changing are drawn in `text2` by the page and replaced in place.
- **Undo.** One ⌘Z takes out the whole dictation. Join its changes into one history event (`isolateHistory` at its start and end), with a JS test.
- **Suggest Edits on.** The phrases extend one signed insertion (`suggestTyping` catches `input.type`). Off, they're plain text and clear Claude's green, as typing does.
- **Keys.**
  - ⇧⌘D goes to the document once it has the keyboard, ahead of the visible session (tap toggles, hold to talk).
  - Esc ends and keeps the words.
  - Return finishes, lets the last phrase land, then is the editor's Return (Q-346). It never sends.
  - Typing or clicking in the document finishes the dictation first.
- **Edge cases.**
  - Read-only: the mic is dimmed.
  - A page reload or crash ends the dictation and keeps what landed.
  - Claude's edits merge as today.
- **At rest nothing shows that a document takes dictation.** Geoff chose this with the "only while editing" bar.
- **Code.** A `VoiceTarget.document` beside chat and terminal (about 12 switch sites; `voiceFocusTarget` checks `editorIfLoaded?.hasFocus` and `showingMarkdownDocument` first). `VoiceChecks` gains the target.
- **Before building:** answer Q-181 (does the system's own Dictation already work in the editor's WKWebView?).

## Also in the build

- **New commands**, each one line on `lineMark` except Code Block (fence the selected lines): body, quote, bullet, numbered, codeblock. They go in Format and `duo2 doc format`.
- **A caret-state report from the page**, so Bold shows on and Style names the paragraph. Extend the `selection` message with the marks and the block type at the caret.
- **Tracked formatting** (C-129): a multi-line style change passes through Suggest Edits untracked. Test it and decide.
- **F-457:** the table bar's buttons sit 1 apart. The controls move into this bar anyway.

## Verbs (DL-71)

- `duo2 doc format body|quote|bullet|numbered|codeblock` (new; bold, italic, strikethrough, code, link and heading1–3 exist).
- `duo2 doc table …` (exists).
- `duo2 voice start --doc` (or a plain `start` when a document has the keyboard). `voice status` names the document, and `voice file <audio> --doc` is for tests.
- `duo2 view format-bar show|hide`.
- Regenerate `docs/cli/duo2.md`.

## Not drawn

- The Style ⌄ and ⋯ menus, which are the system's.
- The bar on a document in Home's pane, which works as in the right pane.
- The "No microphone found." notice, which is the hint row's words in the bar.
- The first-press sheet, which is chat's (DL-260).
