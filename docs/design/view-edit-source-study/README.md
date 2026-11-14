# View and edit source, Markdown and HTML: study

Status: research and a design round, 2026-11-01, for `tasks/view-edit-source.md`. Nothing here is decided yet. The canvas is https://claude.ai/artifact/5gfPPr8uFxfypxLZXazeJh, and Geoff's picks become DL-299 and DL-300. No build is in this branch.

Geoff (2026-11-01, through split-view-build): "so your markdown preview feature sounds half-baked; please have director start a full feature exploration for view/edit source, and get rid of markdown preview". split-view-build is taking the Markdown preview out of split view's slice 1.

Paths are relative to the repo root. `JS` means `Vendor/codemirror/src/duo-editor.js`. Line numbers are from `origin/main` at 9f5b18e2.

## The short version

- **Today a Markdown file has a source view and an HTML file doesn't.**
  - **Markdown:** Source Mode (DL-167 Q3, View › Source Mode, `duo2 doc mode`) swaps the live preview for raw text in place, per document, with no chord.
  - **HTML:** an `.html` file opens only in the viewer, read-only. Its one source view is split view's pair, where the source side is the Markdown editor reading HTML as Markdown.
- **Neither source view is highlighted** (F-515). The editor has no `HighlightStyle`, no line numbers and no HTML language. Source Mode is plain text in the document font, and HTML in the pair is drawn as a Markdown paragraph.
- **The HTML, CSS and JavaScript parsers are already in the bundle** (F-514). `@codemirror/lang-markdown` depends on `lang-html`, which brings `lang-css` and `lang-javascript`, so esbuild already ships all three in `dist/cm6.js` (690,427 bytes). Adding `html()` as a language grew a test bundle by 5 bytes. HTML highlighting therefore costs code (a highlight style, new tokens and wiring), not size.
- **Nothing syncs between source and page** (F-516). The HTML viewer isn't a `PreviewProvider`: it has no anchor map, no caret-follow, and polls the disk every second.
- **What mature apps do** (§3): apps that render in place use one pane and a toggle (Obsidian, Typora). Side by side belongs to editors whose text is plain (VS Code, iA Writer, Nova). Browsers show HTML source read-only, at ⌥⌘U.
- **Three options on the canvas** (§6), from a toggle, through the split's second side, to source inline per block.
  - **Recommended: A, one Source toggle for every document, highlighted, editable, ⌥⌘U.** The split pair reuses the same highlighted source editor, so the page beside its source comes free.

## Since the round was drawn (2026-11-14)

- **The Markdown preview is gone** from split view (F-503's note, 2026-11-01). `PreviewKind.markdown` stays in the enum, but nothing offers it.
- **The formatting bar is built** (DL-301), still kept out of Source mode, and **Review's controls are now in it** (DL-317). So Q-410 now also decides whether Suggest and Add Comment show in Markdown source.
- **⌥⌘U is still unused in Duo** (checked on main at 8934b5d1). The record numbers reserved for this round are still free.
- The questions are written as console cards in `console-cards.json`, for the director to post.

## 1. What Duo does today

### Source Mode (Markdown only)

- **Menu:** View › Source Mode, a Toggle (`Sources/DuoKit/Navigation/Commands.swift:428`).
  - Enabled only with an editor document loaded and terminals live.
  - No chord, and no `DuoCommand` case.
- **Verb:** `duo2 doc mode [source|preview|toggle]` (`Sources/DuoControl/Actions.swift:381`). With no argument it reports "Source mode." or "Preview.".
- **Harness:** `source:on|off`, at `FixtureHarness.swift:485`. Check: `scripts/check-editor-source.mjs`. Shipped in 0.2.11.
- **State:** `AppModel.sourceDocuments`, a set of standardized paths kept in `DuoState` (`AppModel+Source.swift:10-19`). The mode is per document and is remembered.
- **In the page** (JS:1796-1813): three compartments (`previewLive`, `previewProps`, `previewBlocks`) are reconfigured to empty.
  - This removes `livePreview`, `codeHover`, `reviewDrawing`, the margin, the properties block, the table and image keymaps, and block widgets.
  - Undo, caret and scroll survive.
  - The comment calls it "Obsidian's escape hatch when a rendering case is wrong".
- **What you see:** raw text in the document's font with line wrapping. There are no line numbers, no current-line mark and no syntax colours (F-515).
- **Review in Markdown in source** (DL-236, DL-237):
  - `reviewCore` stays, but drawing and the margin go.
  - `{++ ++}`, `{-- --}`, `{~~ ~> ~~}`, `{== ==}` and `{>>@name date #id: … <<}` show as typed text, with no author colour and no threads.
  - Suggest Edits still signs your typing (the `suggestTyping` filter stays on), so in source you see your own marks appear as raw CriticMarkup.
- **Frontmatter in source:** plain YAML lines between `---` fences (the properties block is gone).
- **Saving:** unchanged. The same editor autosaves 1 s after typing (`DocumentEditor.swift:530-535`) through DL-77's merge-first `saveNow`.
- **Formatting bar (DL-266):** decided "not on read-only files, a template's preview or Source mode". It isn't built on main yet (only `SplitRouting.swift` names it).

### The Markdown editor's live rendering

- The live preview (DL-167) keeps every line one height. The caret's line shows its marks, and other lines draw them away.
- A table shows its source with the table bar while the caret is in it (DL-182). Frontmatter is the properties block (DL-102).
- A deck's slide marker becomes a header chip (DL-296, not built).
- So **Markdown already shows its source a line at a time**. A whole-file view is wanted:
  - to read all the marks at once;
  - to see frontmatter as YAML;
  - to see review marks as typed;
  - when a rendering case is wrong.

### The HTML viewer

- **What it is:** a `.html`/`.htm` file opens in `HTMLViewer`, a WKWebView loaded with `loadFileURL` (`ProjectPanes.swift:882-890`, `HTMLViewer.swift:72`).
  - Remote loads are blocked (DL-175). It is always light (DL-224: a page keeps its own colours).
- **It is read-only.** The picker (`HTMLPicker.swift`, DL-67 to DL-70) picks an element or a selection to send to Claude.
- **Reloading:** every 1 s it checks the modification date of the page and its folder's html/css/js/image files, and reloads unless the picker is active (`HTMLViewer.swift:111-141`). It doesn't use file events.
- **Verbs:** `html reload|pick|stop|element|selection`, plus `doc pick|element`. There is no source verb, which is ENH-66: "View source of an HTML page… Needs a duo2 verb and a small design. Geoff: fix later (2026-10-09)".

### Split view's pair (slice 1) and doc beside doc (slice 2)

- **DL-275 (C, a split tab):** a tab holds two sides, `name ⫼ name`, each at least 340, folding to a 16 pt rail. ⌥⌘P toggles it (DL-277), and ⇧⌘[ / ⇧⌘] switch sides.
  - Slice 1: a file beside its own preview (deck, Markdown, HTML), one buffer, the preview redrawn 250 ms after typing pauses through `PreviewProvider`.
  - Slice 2 (DL-278): two documents, each editable. One file in two editable views is ENH-301, not built.
- **The HTML pair:** the page side is `HTMLViewer.renderBuffer`, which runs `loadHTMLString` from the unsaved buffer with the folder as base (`AppModel+Split.swift:105-120`).
  - Relative images may be missing until autosave (Q-400).
  - The source side is `DocumentStack(file:, ref: .main)`: **the Markdown editor in live preview**. HTML is parsed as Markdown, so tags may be styled as Markdown HTML blocks or as paragraphs, with no highlighting (F-515).
- **No scroll or caret sync.** `PreviewPolicy` has `caretFollow = true`, `scrollFollow = false`.
  - Caret-follow needs the caret's line, which the page doesn't report (Q-399).
  - Only the Markdown preview had an anchor map, and that is being removed.
- **The Markdown preview pair** (`Split/MarkdownPreview.swift`, a hand-written renderer) is what Geoff called half-baked, and it is going. With it goes the only `PreviewProvider` that isn't a deck's.
- **Verbs:** `duo2 split [<file>] [--side] [--with]`, `split close|focus|swap|unfold|ratio|separate`.

### Duo Decks

- **DL-267:** a deck is one Markdown file.
- **DL-269:** it opens as a split tab, `deck.md ⫼ Slides`: the source (the ordinary Markdown editor) on one side, the slides (the pptx-renderer) on the other.
  - Folded, the tab's two names are a Source/Slides toggle.
- **DL-296:** the slide marker is drawn as a chip. **DL-284:** comments are Review in Markdown's.
- **Not built:** the `.deck` preview side is an empty pane (`SideSplit.swift:211`), due in Decks' P3.
- **What this means for decks:** the deck's "source" is the live Markdown editor, so a whole-file source view of a deck is Source Mode on that side. In it the slide chip becomes `<!-- slide: kpi -->` again.

### Saving and disk (DL-77)

- **The editor** merges by line with the disk before every save, watches the file and its folder, keeps your text on a real overlap and asks Keep Mine / Use Theirs (`doc resolve`).
  - A removed file keeps its text with Save to Recreate (`DocumentEditor.swift:545-760`, `docs/design/collisions.md`).
- **An HTML file edited in the editor gets all of that for free.** The editor doesn't care what language the text is.
- **What is new is the page.**
  - The viewer polls and reloads from disk, so it can reload while you type in source.
  - A reload loses the page's own state: scroll, form input, script state.
  - See C-142.

### Chords (DL-34)

- **Taken:** see the registry in `Commands.swift:135-179`.
- **Free:** ⌘/ (CodeMirror's default keymap binds it to toggle comment, but Duo's Markdown editor has no comment syntax), ⌥⌘U and ⌘E.
- **On other apps:**
  - ⌥⌘U is View Source in Safari and Chrome. On this Mac it isn't a macOS default, and isn't in 1Password, Raycast or Rectangle as installed: checked against their documented defaults, not tested.
  - ⌘E is "Use Selection for Find" in macOS's standard Edit menu, and Duo's chat composer uses it for code (DL-188).
  - ⌘/ is Typora's Source Code Mode, and in many apps the menu key for Help search (⇧⌘/).

### Records that bear on it

| Record | What it says |
|---|---|
| DL-34 | The chord map is locked; a new chord needs a DL. |
| DL-71 | Every UI action has a `duo2` verb. |
| DL-77 | Never lose either side; merge before asking. |
| DL-167 | Keep CM6 live preview; Q3, a Source mode per document; Q4, "a calmer per-node reveal is a design study later". |
| DL-175 | Local HTML pages load nothing remote. |
| DL-224 | An HTML page keeps its own colours in Dark. |
| DL-236, DL-237 | Review in Markdown: CriticMarkup inline, the margin, Suggest Edits in frontmatter. |
| DL-266 | The formatting bar, not in Source mode (not built). |
| DL-267, DL-269, DL-284, DL-296 | Decks: one Markdown file, `deck.md ⫼ Slides`, Review's comments, the slide chip. |
| DL-275 to DL-278 | Split view: the split tab, room, ⌥⌘P and ⇧⌘[ ], doc beside doc; one file in two editable views is ENH-301. |
| ENH-66 | View source of an HTML page, "fix later". |
| ENH-301 | Two editable views of one file. |
| Q-399, Q-400 | Caret line not reported; relative images from the buffer. |
| C-136 | Live preview cost: a second WebContent process, the 250 ms render off the main thread. |

## 2. What Geoff likely wants source for

Ranked by how often it comes up in his use. This is a guess from the request and from how Duo is used (Claude writes the files; Geoff reads and corrects them):

1. **Checking exact Markdown.** What Claude actually wrote: a list that renders right but is indented oddly, a heading level, a link target, hard wraps, a stray `<br>`, an HTML block. The live preview shows one line at a time, which is too narrow to see a file's shape.
2. **Editing HTML that Claude wrote.** Claude makes pages, decks of HTML, prototypes and reports in HTML. Today a one-word fix means asking Claude or leaving Duo. This is the big gap: the file is text, Duo has a text editor, but the viewer won't open it as text.
3. **Seeing frontmatter and review marks as they are.** The YAML before the properties block, `suggest-edits: true`, closed comments, signatures, `#id`s. This matters when a merge, a convention or Claude's edit goes wrong.
4. **Copying exact text.** Copying from the HTML viewer gives rendered text. Copying from the live editor already gives the Markdown, so this is mostly HTML: a snippet, a style, a script.
5. **Debugging a rendering case.** Source Mode's original reason (DL-167).

These point at **a whole-file view, in place, editable, highlighted enough to read structure**, for HTML above all. Live side-by-side sync matters less for these jobs than reading and fixing the text.

## 3. How mature apps handle it

From each product's own documentation and behaviour as of mid-2026. Nothing here was measured on this Mac.

| App | What you see | How you switch | Edit in source? | Sync between the two |
|---|---|---|---|---|
| **Obsidian** | Three modes per note: **Live Preview** (rendered; the line or block under the caret shows its marks), **Source mode** (raw text with light syntax styling, no widgets, the same font) and **Reading view** (rendered, read-only). | Editing ⇄ Reading: the book/pencil button at the top right, ⌘E. Live Preview ⇄ Source mode: a setting, or the command "Toggle Live Preview/Source mode" (no default chord). | Yes in both editing modes; Reading view is read-only. | One pane switches in place and keeps the scroll position. A linked second pane can show the note in another mode, with scroll sync. |
| **iA Writer** | Raw Markdown always, styled in place (marks dimmed, headings bold), plus a separate **Preview** of the rendered page. | The preview opens in a second column on wide windows and swaps in place on narrow ones. | Source only; the preview is read-only. | The preview follows the editor's scroll. |
| **Typora** | Fully rendered: a block's marks show only while the caret is in it. **Source Code Mode** shows the whole file raw. | View › Source Code Mode, ⌘/. | Yes in both. | One pane, in place; the caret's position is kept across the switch. |
| **Bear** | Styled raw Markdown (marks visible but dimmed); no fully rendered view in the editor. "Hide Markdown" is a setting. | A setting, not per note. | Yes. | — |
| **VS Code** | Source is the document. **Open Preview** (⇧⌘V, same tab) or **Open Preview to the Side** (⌘K V, a split). For HTML there is no built-in preview: an extension (Live Preview) opens the page beside it. | Command palette, a title-bar button, the chords above. | Source only; previews are read-only. Double-clicking the Markdown preview jumps to that line. | Two-way scroll sync between the editor and the Markdown preview; the caret's line is marked in the preview. |
| **Xcode, Nova** | HTML is a highlighted text file. Nova has a **Preview** tab (WebKit), refreshed on save or as you type; Xcode has none. | Nova: Editor › Preview, or the tab bar's preview button. | Source only. | No line sync. |
| **Safari, Chrome** | **View Source** (⌥⌘U in both): the page's bytes, highlighted, read-only, in a tab of its own. **Web Inspector/DevTools** (⌥⌘I) shows the live DOM, not the file: "Edit as HTML" changes the DOM, lost on reload and never written to the file (Chrome's Workspaces can map edits to local files if set up). | ⌥⌘U; right-click › View Page Source / Inspect Element. | View Source: no. DevTools: the DOM only. | Inspect Element jumps from a point on the page to its node, and hovering a node outlines it. Nothing maps back to the file's lines. |
| **Google Docs, Word, Pages, Notion** | No source. "Exact text" means copying with formatting stripped. Word's Reveal Formatting and Show ¶ are the nearest thing. | — | — | — |

### What the pattern says

- **Editors that render in place keep one pane and a toggle** (Obsidian, Typora).
  - It is per document or app-wide, has a menu item and a chord, and keeps the caret and scroll across the switch.
  - **Nobody puts a rendered preview beside an editor that already renders**, which is Geoff's point about the Markdown preview.
- **Side by side comes from tools whose editor is plain text** (iA Writer, VS Code, Nova): the preview is the second view because the editor isn't one. There, people expect scroll sync and a jump from the preview back to the line.
- **HTML source is a developer feature everywhere**, and read-only in browsers. The apps that edit an HTML file and show its page together are code editors, with the page beside the source.
- **Exact text is the main reason people want source in apps that hide it.** Reveal codes exist because the rendered view hides what will be saved.
- **⌥⌘U is "view source" on the Mac** (Safari, Chrome). ⌘/ is Typora's.

## 4. The cost of a source view for HTML

| Piece | Cost | Notes |
|---|---|---|
| **The language** | ~0 bytes | `html()` from `@codemirror/lang-html` (with CSS in `<style>` and JS in `<script>`) is already bundled (F-514). Wiring: a language compartment chosen by file kind; the Markdown-only extensions (live preview, lists, tables, review, the properties block, title-follows-heading) left out for HTML. About 1 day in JS, plus a `dist/cm6.js` rebuild. |
| **Highlighting** | ~1 day + a design | A `HighlightStyle` for both languages with new tokens (`syntaxTag`, `syntaxAttr`, `syntaxString`, `syntaxComment`, `syntaxMark`) in Light, Dark and Classic. Nothing exists today. The tokens go through `tokens.json` and `gen-tokens.py` like any other. |
| **Opening HTML as text** | ~1 day | Today `.html` is routed to `HTMLViewer` only (`ProjectPanes.swift:882`). The editor must accept it: `DocumentStack` on an HTML file, with the mode remembered per document as `sourceDocuments` already is. |
| **Saving, disk** | ~0 | DL-77's editor path is language-blind: merge, conflicts and history work as for Markdown. **New:** the viewer must not reload from disk under an open, dirty source (it polls every 1 s), and must reload from the buffer when you go back to the page. |
| **Page ⇄ source sync** | 2–4 days | (a) Keep your place on the switch: the page reports the element at the top of the viewport and the editor scrolls to its tag (and back). (b) In a split, caret-follow (Q-399 adds the caret line) and scroll-follow. Mapping needs element ↔ source offsets: walk the lezer HTML tree and the DOM in document order and match the nth element. That works without touching the page and degrades when scripts rewrite the DOM. The alternative is injecting `data-duo-src` attributes into the buffer before `loadHTMLString`: exact, but it changes the DOM a page's CSS and scripts see. |
| **The pair** | ~0.5 day once the above exists | Split's HTML source side gets the HTML language and highlighting by the same compartment. |
| **Picker ⇄ source** | ~1 day | Picking an element on the page can offer "Show in Source". |
| **Risk** | C-142 | Claude rewrites the file while you edit its source: DL-77 merges by line, but HTML from Claude is often rewritten whole, so overlaps (Keep Mine / Use Theirs) will be commoner than for Markdown. A page reload loses page state. |

**A source view for HTML costs about a week, not a new library.** The bundle doesn't grow. The work is wiring, the highlight tokens, the viewer's reload rules and keeping your place.

## 5. Design constraints from the system

- **The right pane** is 460 by default and 360 at the narrowest (DL-129). A source line at 460 has room for about 50 mono characters at 12/19, so HTML wraps a lot; line wrapping stays on, with wrapped lines indented under their first.
- **One accent, needs you only.** Syntax colours must not use `needsYou`, and must stay 4.5:1 on `pane` in every scheme. Classic needs its own set (paper ground).
- **The document font vs mono.** Markdown source in the document font keeps one height per line with live preview (DL-167 Q1), so switching never reflows the page. HTML source is code: mono 12/19.
- **Up to three bars over a document already** (notice, template, review): a fourth always-on bar is unwelcome (markdown-toolbar study §5).
- **Every action has a verb** (DL-71). `doc mode` exists and extends to HTML.

## 6. The options (on the canvas)

- **A · One Source toggle, everywhere (recommended).** View › Source (⌥⌘U, a new chord under DL-34), per document, in place, for Markdown and HTML.
  - Source is highlighted and editable. HTML gets the page back on the same chord, reloaded from the buffer at the same place.
  - A Page | Source switch at the tab strip's trailing end shows which you're in and takes a click.
  - The split pair's source side uses the same highlighted editor.
  - Cost about a week.
- **B · Source beside, always.** Source lives in the split's other side.
  - ⌥⌘P becomes Show Source in Split View: page ⫼ source for HTML, live ⫼ source for Markdown (one buffer in two editable views, which amends DL-278 and builds ENH-301).
  - Scroll sync both ways. Folded under two 340 sides, the tab's names toggle, as decks do.
  - No in-place mode, so Source Mode is retired.
  - Cost about two weeks.
- **C · Source in place, block by block.** Obsidian's live preview carried further.
  - In Markdown, putting the caret in (or ⌥-clicking) a block reveals the whole block's source: frontmatter as YAML, a table, a comment's raw mark, a slide marker.
  - In HTML, hovering an element on the page shows a `</>` tag; clicking it opens that element's source in a small editor under it, applied to the file on Return.
  - Whole-file Source Mode stays for the rest.
  - Cost three weeks or more, and the HTML half is a research risk (DL-167 Q4's calmer reveal is the Markdown half).

### Recommendation: A

- **It fits what Geoff wants source for** (§2): a whole file, in place, editable, readable. It closes ENH-66 and needs no new surface.
- **It's what mature apps that render in place do** (Obsidian, Typora), on the Mac's view-source key.
- **It costs the least**: the parsers are bundled, the compartments exist, DL-77's saving is language-blind.
- **It works at 360** with nothing to fold.
- **The page beside its source stays possible**: split's pair gets A's highlighted source side, and ⌥⌘P stays the way to have both on screen.
- **Decks are unchanged**: their source side gets A's toggle for whole-file source.

## Records opened

- F-514, F-515, F-516: `docs/plan/findings.md`.
- Q-407 to Q-410, C-142: `docs/plan/concerns-and-questions.md`.
- ENH-311: `docs/plan/enhancements.md`.
- DL-299 and DL-300 are reserved for Geoff's picks.
