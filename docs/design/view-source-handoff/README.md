# View › Source: handoff (DL-346)

Exported from the canvas https://claude.ai/artifact/5gfPPr8uFxfypxLZXazeJh (study: `../view-edit-source-study/`). `screens/` holds board A (`OptionA.dc.html`) and Highlighting (`Syntax.dc.html`) as drawn, plus the study's captures. Don't edit them.

**Amended by DL-346 (Geoff, 2026-11-16): no visible Page | Source switch.** Board A draws one at the tab strip's trailing end; it is not built. Source is reached only by **View › Source (⌥⌘U)** and `duo2 doc mode`. Where the screens and DL-346 disagree, DL-346 wins.

## What is built

- **View › Source (⌥⌘U)** toggles the Markdown or HTML document on screen between its page and its highlighted, editable source, in place, remembered per document. Disabled in a split tab's HTML side (always source there).
- **HTML source** is the editor in `kind: "html"`: HTML, CSS and JavaScript highlighted, mono 12/19, wrapped lines hung 24, none of the Markdown extensions. The page comes back by the same item; typing is flushed to disk first.
- **Markdown source** keeps the document's face and size; marks, links, code, comments, frontmatter keys and values and CriticMarkup take the tokens.
- **Split view's source side** (an HTML file) is the same highlighted source.
- **The formatting bar** shows in Markdown source (amends DL-266 3) and never on HTML source.
- **Tokens** (`tokens.json`, Light, Dark, Classic): `syntaxTag`, `syntaxAttr`, `syntaxString`, `syntaxComment`, `syntaxMark`. Values from the Highlighting board.
- **Verb:** `duo2 doc mode [source|page|toggle]`.

## Proof

`scripts/check-editor-view-source.mjs` (Chromium and WebKit; `DUO_SCHEME=dark|classic` for the others) checks each token's computed colour. `source-html-light-webkit.png` and `source-md-light-webkit.png` are its captures, to put beside the Highlighting board's Light column.

Not done: a live-app capture compared region by region in Dark and Classic, and keeping your place across Page and Source (Q-580).
