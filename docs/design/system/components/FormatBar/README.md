# FormatBar

The Markdown formatting bar (DL-266, DL-301; target `markdown-toolbar-handoff/screens/bar.html`): 24 high (`formatBarHeight`) on `pane` with a `rule` below, laid over the top of the editor, never pushing it. The document's top padding is 24 so the bar sits in it.

- **Shows** while a Markdown document has the keyboard (the pane's focus rule, DL-165), and while one of its menus is open or a dictation runs. Not on read-only files, a template's preview or Source mode. View › Hide Formatting Bar turns it off.
- **Contents:** Style ⌄ (names the paragraph at the caret), Bold, Italic, Link, Insert Table, ⋯ (Strikethrough, Code); the mic at the trailing end. No underline.
- **Glyph controls** are 24 × 20, radius 5, marks in `text2`; on (Bold at the caret) or under the pointer, a `selected` fill with the mark in `text`, never the accent. Style ⌄ and the table buttons are 12/16, 20 high. Separators are 12 high. The mic is 20 round with a small glyph. The bar starts 22 in from the left. Clicks never take the keyboard from the text.
- **In a table:** + Row, + Column, Align ⌄ and Delete ⌄ take Style's place after B, I and Link; under 420, Align and Delete fold into ⋯. The in-document 28 bar is gone.
- **Listening:** the controls give way to chat's hint row (the level bars, "Listening", "· ⇧⌘D or the mic finishes · esc ends"); the mic fills with `text`, its glyph `pane`. **No microphone:** DL-265's faint `mic.slash` in `controlEdge`, tooltip "No mic detected · connect one to use transcription".
- **Menus** (Style, ⋯, Align, Delete) are the system's, popped under their buttons.

**In code:** `Project/MarkdownFormatBar.swift` (`FormatBarLogic` holds the rules the checks read), laid over the editor in `Project/DocumentStack.swift`; the page keeps a 24 scroll margin (`duo.setFormatBar`) and reports the caret's marks and paragraph with every selection. Verbs: `duo2 doc format body|quote|bullet|numbered|codeblock`, `doc table …`, `view format-bar`, `voice start --doc`.
