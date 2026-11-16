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

- `scripts/check-view-source-live.sh`: an isolated background Duo opens a Markdown and an HTML file, flips Source with `duo2 doc mode`, edits the HTML in source, goes back to the page (saved first) and reads the file on disk. 16 steps pass.
- `scripts/check-editor-view-source.mjs` (Chromium and WebKit; `DUO_SCHEME=dark|classic`): each token's computed colour, no bold frontmatter key.
- `proof/source-{q3,review}-{light,dark,classic}.png`: `check-view-source-live.sh --captures`, the right pane looked at against the Highlighting board's three columns: tag, attribute, string, comment and mark colours match in all three; the formatting bar shows over Markdown source and not over HTML. Window captures draw the page from WebKit's snapshot (F-120).
- Found and fixed in this pass: review marks weren't coloured in the app (the web variables are `--duo-review-1` and `-3`), and frontmatter keys came out bold (the setext-heading style sat inside the mark).

Not done: keeping your place across Page and Source (Q-580).
