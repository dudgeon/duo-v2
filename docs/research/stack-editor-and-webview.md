# Stack research: markdown editor and embedded web view

**Status:** research / decision input. Research date 2026-10-03.
**Scope:** the two "web-ish" surfaces of Duo v2 — the rendered-markdown editor and the embedded browser — and how they fit in a native Swift (SwiftUI/AppKit) shell. Terminal hosting and Claude Code process management are covered separately in `stack-terminal-and-claude-hosting.md`.
**Legend:** facts are cited inline with a URL and the date fetched (all 2026-10-03 unless noted). Numbers or claims I could not verify are marked **[unverified]** or **[estimate]**.

---

## 0. TL;DR

| Question | Recommendation |
|---|---|
| Editor engine | **CodeMirror 6 "live preview" in a WKWebView.** Markdown text stays the single source of truth; rendering is done with CM6 decorations/widgets in place. This removes the serialize-on-save step entirely, which is where the legacy app spent roughly a year of bug-fixing (BUG-085 → BUG-166 arc, see §1). |
| Why not ProseMirror/TipTap/Milkdown | They are document-model editors; markdown is an import/export format. Every save is a lossy AST → text serialization (list markers, escapes, HTML passthrough, blank lines, frontmatter). The legacy app proved this hurts in practice. |
| Why not fully native | No mature native rendered-markdown editor exists with tables + task lists. The closest (`swift-markdown-engine`, Apache-2.0, pre-1.0, single author, 0 stars) is worth a 2-day hedge spike, but betting the product on it or on a from-scratch TextKit 2 editor is a 3–6 engineer-month risk with TextKit 2 bug exposure. |
| Browser | **WKWebView** (AppKit, via `NSViewRepresentable`) with one shared `WKProcessPool`, a persistent `WKWebsiteDataStore` for login/OAuth cookie persistence, `WKURLSchemeHandler` for local folders/images, `isInspectable` for DevTools, `WKDownload` for downloads, `createPDF`/`printOperation` for print. Adopt the macOS 26 `WebPage`/`WebView` SwiftUI API only if the deployment target is macOS 26+. CEF and Tauri are not worth it. |
| Web views at runtime | 1 editor web view (documents swap in/out of a single CM6 instance) + N browser tabs (one WKWebView each, share one process pool) + optionally 1 HTML-preview view. Idle app target ≈ 80–150 MB **[estimate]**; each loaded browser tab adds 30–200 MB depending on site **[estimate]**. |
| First spikes | (1) CM6 live preview on the legacy 1.2 MB `tasks.md`, (2) external-edit → CM6 transaction with cursor preservation, (3) `swift-markdown-engine` hedge, (4) WKWebView login/OAuth/localhost/folder/download/PDF, (5) native menu → JS command bridge. See §7.4. |

---

## 1. What the legacy Electron app actually built (and what hurt)

Source: `~/repos/duo` (read-only inspection of `package.json`, `renderer/components/editor/**`, `CHANGELOG.md`, `docs/DECISIONS.md`, `docs/RELEASES.md`, `renderer/hooks/useDiskReconciliation.ts`).

**Stack.** TipTap 2.27 (`@tiptap/react`, `starter-kit`, `extension-table/-row/-cell/-header`, `extension-task-list/-item`, `extension-link`, `extension-image`, `extension-mention`, `extension-code-block-lowlight`, `extension-placeholder`, `extension-underline`, `@tiptap/suggestion`) + `tiptap-markdown` 0.8.10 (the community `aguingand/tiptap-markdown` package, MIT, 525 stars, last push 2025-10-22) for parse/serialize. CodeMirror 6 (`@uiw/react-codemirror`, `lang-yaml`, `lang-json`, `lint`) for YAML/JSON sidecars. `react-markdown` + `remark-gfm` + `rehype-sanitize` for read-only rendering.

**Custom editor extensions (31 files in `renderer/components/editor/extensions/`):** `AtMention`, `BulletListWithMarker`, `CodeBlockCopyButton`, `CommentMark`/`InsertionMark`/`DeletionMark`/`HighlightMark` (CriticMarkup track-changes), `DuoImage` (block-only images), `FencedCodeBlockEnter`, `FindHighlight`, `JustAdded` (change highlight on reload), `LineNumbers` (true source line per block, computed by serializing through the save path), `ListIndentShortcuts`, `MarkdownLinkShortcuts`, `MarkdownPaste`, `PersistentSelection`, `SuggestingMode`, `TableCellCopy`, `TableMarkdownRoundtrip`, `TableShortcuts`, `WikilinkDecorations`, `WikilinkSuggestion`. Plus a frontmatter panel (YAML preserved verbatim and stitched back on save — `markdown-io.ts`), a find bar, a history modal, an annotation rail.

**Pain points recorded in the legacy docs (all attributable to AST ↔ markdown round-tripping):**

- `docs/RELEASES.md` §"BUG-166": "Five months of growing `normalizeForEchoCompare` regex-by-regex to cancel TipTap round-trip artifacts (BUG-107 trailing whitespace, BUG-122 hypothesis 4 soft-break, hypothesis 6 HTML-entity escape, BUG-155 autolinks) hit a wall … `tasks.md` (1.2MB) surfaced two more gaps (`****X**` → `\*\***X**` bold-marker escape, relative-path `[X](X)` autolink stripping)."
- CHANGELOG: HTML comments rewritten to `&lt;!--` on serialize (BUG-122 h6); autolink turning `prd.md` into a link on parse (ENH-174, BUG-155); multi-line table cells "shatter on save" (BUG-210, fixed by a custom `TableMarkdownRoundtrip` serializer plus a save-path backstop "that refuses any row-losing serialize"); inline images mid-sentence dropped as a trade-off (FOLLOWUP-024); `duo doc edit` re-serialization churn (BUG-199: "when the safe path silently corrupts formatting, agents must choose between fighting autosave … and lossy edits — both wrong").
- The conflict/echo detection had to be split into two refs (dirty check vs byte-exact disk check) because the serialized view never matched disk bytes (BUG-166; `useDiskReconciliation.ts` header comment calls it "the ~11-bug BUG-085 → BUG-166 conflict arc").

**Takeaway for v2:** the legacy feature set (tables, task lists, images, links, fenced code with highlighting, mentions/wikilinks, frontmatter panel, find, line numbers, change-highlight on reload, CriticMarkup) is a fine target list. The architecture — a rich-text document model with markdown as an import/export format — is the thing to change. Everything in the pain list disappears if the editor's state *is* the markdown text.

---

## 2. Requirements restated

1. Edit the rendered document directly (Typora/Bear/Obsidian-live-preview feel). No split pane.
2. GFM: tables, task lists, nested lists, fenced code with highlighting, images (local paths), links, strikethrough. Also: YAML frontmatter, raw HTML passthrough (HTML comments are common in Claude-authored docs), footnotes (nice-to-have), wikilinks (legacy vault feature).
3. **Round-trip safety:** saving a file the user didn't touch must be byte-identical; saving after an edit must change only the edited region. Claude Code (and git diffs) must not see spurious churn.
4. Files are edited concurrently by Claude Code on disk; the editor must reload/merge without losing cursor or unsaved typing.
5. Native feel: system spellcheck, dictation, Writing Tools where possible, Cmd-B/I/K from the menu bar, native find bar, standard macOS selection/caret behaviour, low memory.
6. HTML viewing (local files/folders, localhost dev servers, general web incl. OAuth logins). HTML editing is out of scope.

Requirement 3 is the discriminator. There are only two architectures that satisfy it cheaply: (a) text-is-source-of-truth editors that *decorate* the text (CodeMirror 6 live preview; `swift-markdown-engine`/Bear-style native engines), and (b) document-model editors with a *lossless* concrete-syntax round trip, which none of the surveyed ProseMirror/Lexical stacks provide out of the box.

---

## 3. Native (Swift / AppKit / TextKit 2) options

### 3.1 Survey

| Package | What it is | GFM tables | Task lists | Images / code | Model | License | Activity (GitHub API, 2026-10-03) | Verdict |
|---|---|---|---|---|---|---|---|---|
| [swift-markdown-engine](https://github.com/Jon-Schneider/swift-markdown-engine) | AppKit markdown editor on TextKit 2, bridged to SwiftUI. "Live styling" that hides syntax; wiki-links; fenced code with embedder-supplied highlighting + copy buttons; LaTeX; Obsidian `![[img]]` and standard images; GitHub-style task checkboxes; "GFM table support … wide tables break out to the full window width"; viewport virtualization; Writing Tools on 15.1+. macOS 14+. | Yes | Yes | Yes / Yes | Text is source of truth (styled in place) | Apache-2.0 | 0 stars, last push 2026-09-20, 321 commits, "pre-1.0 … pin a specific version" | **Only credible native candidate.** Single author, unproven. Hedge spike. |
| [LapermEditor](https://github.com/k-ymmt/LapermEditor) | TextKit 2 markdown editor lib, Swift 6; syntax highlighting driven by swift-markdown; "Live Preview mode that hides syntax markers when the editor isn't active"; GFM tables "drawn as a grid"; inline images; folding; list continuation; task toggling. Requires **macOS 26+ / Swift 6.4**. | Yes (grid in preview mode) | Yes | Yes / styled blocks | Text | **No license file** | 0 stars, last push 2026-09-29 | Interesting but preview-only-when-inactive, no license, macOS 26 floor. Watch. |
| [MacDown 2](https://github.com/Joncallim/macdown_2) | SwiftUI/TextKit 2 rewrite of MacDown; tree-sitter highlighting + separate native Textual preview with scroll sync. | n/a | n/a | — | Source + preview (split) | MIT | 2 stars, pushed 2026-10-03 | Not WYSIWYG. Skip. |
| [MarkupEditor](https://github.com/stevengharris/MarkupEditor) | "WYSIWYG for SwiftUI/UIKit" — actually **ProseMirror inside a WKWebView**, HTML model, `getHtml()`; tables/images/lists. | Yes | No | Yes / basic | HTML | MIT | 478 stars, pushed 2026-09-16 | Not markdown. Skip (but proves the Swift↔ProseMirror bridge pattern). |
| [STTextView](https://github.com/krzyzanowskim/STTextView) | TextKit 2 NSTextView replacement; line numbers, plugins (tree-sitter, Neon), multi-cursor. macOS 14+. | — | — | — | Code editor | **GPL-3.0 or commercial** | 1.6k stars, pushed 2026-09-26 | Building block only; license cost. Author has filed 20+ TextKit 2 radars — a useful signal about TextKit 2 maturity. |
| [CodeEditSourceEditor](https://github.com/CodeEditApp/CodeEditSourceEditor) / [CodeEditTextView](https://github.com/CodeEditApp/CodeEditTextView) | Xcode-like code editor on a custom TextKit-2-ish layout; tree-sitter highlighting, minimap, find/replace. May 2026 added "line block layout … reserving view-backed space between text lines". | — | — | — | Code editor | MIT | 724 / 185 stars, pushed 2026-04-20 / 2026-09-20 | Good **source-mode** editor for YAML/JSON/raw-markdown; not a rendered editor. |
| [Runestone](https://github.com/simonbs/Runestone) | iOS-first code editor with tree-sitter. | — | — | — | Code editor | MIT | 3.2k, pushed 2026-03-25 | iOS-centric; skip for macOS. |
| [swift-markdown](https://github.com/swiftlang/swift-markdown) | Apple's cmark-gfm-based parser with source ranges. | parse | parse | parse | Parser | Apache-2.0 | 3.4k, pushed 2026-10-03 | The right parser for any native approach (and for Textual). |
| [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) → [Textual](https://github.com/gonzalezreal/textual) | Read-only SwiftUI renderers. MarkdownUI "is in maintenance mode. New development is happening in Textual". Textual: SwiftUI-native, tables/lists/code/blockquotes, selectable text. | render | render | render | Read-only | MIT | 3.9k (pushed 2025-12-28) / 893 (pushed 2026-06-15) | Use **Textual** for native read-only markdown (chat transcripts, previews). |
| [Down](https://github.com/johnxnguyen/Down) | cmark wrapper → NSAttributedString/HTML. | render | no | — | Read-only | MIT-ish | 2.5k, last push 2023-07-15 | Effectively unmaintained. |
| [Ink](https://github.com/JohnSundell/Ink) | Markdown → HTML parser. | no | no | — | Parser | MIT | 2.5k, last push 2024-03-27 | No GFM tables; dormant. |
| [HighlightedTextEditor](https://github.com/kyle-n/HighlightedTextEditor) | Regex-based syntax highlighting over NSTextView/UITextView. | — | — | — | Source mode | MIT | 761, last push 2024-06-13 | Source-mode only; dormant. |

### 3.2 How the commercial apps do it

- **Bear 2** — custom native engine code-named **Panda**, built by Shiny Frog for Bear 2 (July 2023); Bear is "written in C++, Objective-C, and Swift" ([Wikipedia](https://en.wikipedia.org/wiki/Bear_(app))). The Panda posts on [blog.bear.app/tag/panda](https://blog.bear.app/tag/panda/) describe features (tables, hidden markdown, folding) but **do not disclose** whether it is TextKit or a custom layout engine **[unverified]**. The point: a well-funded team built a bespoke engine over multiple years.
- **iA Writer** — native AppKit app; widely reported as NSTextView-based **[unverified — no primary source found]**.
- **Typora** — Electron; "core dependencies include Electron, MathJax, Mermaid.js, and Pandoc" ([rywalker.com/research/typora](https://rywalker.com/research/typora)). Its WYSIWYG is a bespoke contenteditable engine, not ProseMirror.
- **Craft** — native per-platform apps with shared logic (third-party write-up: [blakecrosley.com/guides/design/craft](https://blakecrosley.com/guides/design/craft)) **[weakly sourced]**. Craft's model is blocks, not markdown files.
- **Obsidian** — Electron + CodeMirror 6; "Obsidian uses CodeMirror (CM) as the underlying text editor" ([docs.obsidian.md](https://docs.obsidian.md/Plugins/Editor/Editor)). Live Preview renders tables as editable widgets since v1.5 (Feb 2024 changelog: tables "automatically formatted as you type", click links/tags inside cells, backspace-to-select-table — [obsidian.md/changelog v1.5.8](https://obsidian.md/changelog/2024-02-22-desktop-v1.5.8/)).
- **Editorio** — a new free native macOS markdown editor on "AppKit + NSTextView … custom incremental tokenizer … no web view" ([editorio.crncevic.org](https://editorio.crncevic.org/)); closed source, but evidence that a solo native build is feasible for *source-styled* editing.

Pattern: the native apps that render in place (Bear, iA Writer, Editorio) all keep **text as the source of truth and style/hide syntax in the text view** — the native analogue of Obsidian's live preview. None of them use a ProseMirror-style document model with markdown serialization.

### 3.3 Realistic effort to build a TextKit 2 rendered-markdown editor from scratch

Scope: NSTextView/TextKit 2 with `swift-markdown` incremental parse → attributed-string styling that hides syntax except near the caret; task-list checkboxes (attachment or `NSTextLayoutFragment` subclass); images as attachments loaded from relative paths; fenced code blocks with a highlighter (tree-sitter/Neon); **tables** as custom `NSTextLayoutFragment`s or embedded NSTableView-like views with cell editing; links; lists with proper hanging indent; frontmatter folding; find; undo. Round-trip is free (text is the file), so the serialization problem vanishes — but the layout problem replaces it.

| Milestone | Effort **[estimate]** |
|---|---|
| Inline styling + syntax hiding near caret, headings, emphasis, code spans, links | 2–3 weeks |
| Lists (bullets, numbers, nesting, task checkboxes with click toggle) | 2 weeks |
| Fenced code blocks (block background, highlighting, copy) | 1 week |
| Images (inline attachments, sizing, async load) | 1 week |
| **Tables** (grid rendering, in-cell editing, column resize, tab navigation, add/remove row/col) | 4–8 weeks — TextKit 2 has no table primitive; this is custom layout fragments or a hybrid view, and it's where every prior attempt stalls |
| Find/replace, undo coalescing, perf on 1 MB files, accessibility, Writing Tools, dictation | 2–3 weeks |
| TextKit 2 bug workarounds (see STTextView author's 20+ radars) | ongoing tax |
| **Total** | **~3–5 engineer-months to parity with legacy**, higher variance than any other option |

Native wins: zero bridge, best spellcheck/dictation/Writing Tools, lowest memory (no WebContent process for the editor), perfect menu integration. Native loses: tables, time-to-first-usable, single-vendor TextKit 2 risk, and no fallback community.

---

## 4. Web-based editors hosted in WKWebView

### 4.1 Survey

| Editor | Model | Markdown round trip | GFM tables / tasks | Frontmatter / raw HTML / footnotes / wikilinks | License & tiers | Activity | Notes |
|---|---|---|---|---|---|---|---|
| **TipTap** (+ official `@tiptap/markdown` 3.30.3, or community `tiptap-markdown`) | ProseMirror doc | Lossy AST round trip. Official docs: "early release … may have edge cases"; tables "only one child node per cell"; "Comments are not supported yet". Changelog shows fixes for blank-line preservation, backslash escapes, unknown HTML tags, mixed task/bullet lists ([changelog](https://tiptap.dev/docs/resources/changelog/markdown)). Uses MarkedJS. | Yes / Yes | FM: no (handle outside) · HTML: parsed into doc (lossy) · footnotes: no · wikilinks: custom | Core MIT; Cloud from $49/mo; free plan removed June 2025; AI Toolkit & Tracked Changes paid; "some PRO extensions require an active subscription for verification" ([dev.to pricing explainer](https://dev.to/eddyter/tiptap-pricing-explained-2026-free-vs-pro-vs-cloud-cost-breakdown-3l5g), [tiptap.dev/open-source-to-cloud](https://tiptap.dev/open-source-to-cloud)) | 38.6k stars, pushed 2026-10-02 | Legacy app's stack (v2 + community package). Mature UX; the round-trip is the known problem. |
| **Milkdown / Crepe** | ProseMirror doc, remark (mdast) parse/serialize | Lossy AST round trip via `remark-stringify` (normalizes list markers, emphasis chars, escapes). Better than marked-based because mdast is CommonMark/GFM-exact, but still rewrites untouched text. | Crepe `Table` feature: "row and column management, alignment, drag-and-drop"; `ListItem`: bullet/ordered/todo ([feature/index.ts](https://raw.githubusercontent.com/Milkdown/milkdown/main/packages/crepe/src/feature/index.ts)) | FM: remark-frontmatter plugin available · HTML: remark `html` nodes (passthrough as raw blocks, editing limited) · footnotes: plugin · wikilinks: custom | MIT | 12k stars, pushed 2026-10-01 | Crepe bundles CodeMirror for code blocks, LinkTooltip, ImageBlock, BlockEdit (slash + drag), Toolbar, Placeholder, Latex, Cursor; TopBar and AI opt-in. Best "batteries included" WYSIWYG if you accept lossy saves. |
| **Lexical** (+ `@lexical/markdown` or experimental `@lexical/mdast`) | Lexical doc | `@lexical/markdown` regex transformers: no tables. `@lexical/mdast` (micromark/mdast): GFM tables, tasks, strikethrough, autolinks; "preserves original syntax … minimally different Markdown" (bullet char, fence style) — the closest a doc-model editor gets to fidelity — but "everything in this package is marked `@experimental` and may change between any two releases" ([lexical.dev/docs/packages/lexical-mdast](https://lexical.dev/docs/packages/lexical-mdast)). | mdast: Yes / Yes | FM: no · HTML: no · footnotes: no · wikilinks: custom | MIT | 23.9k, pushed 2026-10-03 | Meta-backed; React-centric; table UX is DIY. |
| **Editor.js** | JSON blocks | Markdown only via community `editorjs-md-parser` (inline strong/em/link "WIP"). | partial | no | Apache-2.0 | 32k, pushed 2026-09-17 | Wrong shape for markdown files. Skip. |
| **Toast UI Editor** | dual (markdown + WYSIWYG, ProseMirror under WYSIWYG) | Claims full GFM round trip. | Yes / Yes | FM: partial · HTML: partial | MIT | **Archived** (GitHub shows archived 2026-09-02; last push 2024-08-01) | Dead. Skip. |
| **Vditor** | three modes: WYSIWYG, **IR ("instant rendering", Typora-like)**, SV (split) | Lute engine; "supports all CommonMark … all GFM", YAML front matter, footnotes, math/mermaid/graphviz ([github](https://github.com/Vanessa219/vditor)). IR mode keeps markdown text and renders in place — conceptually like CM6 live preview. | Yes / Yes | FM: Yes · footnotes: Yes · HTML: Yes · wikilinks: no | MIT | 11.4k, pushed 2026-10-02 | Heavy (Lute is Go compiled to JS **[unverified]**), docs mostly Chinese, monolithic UI hard to re-skin natively. Fallback candidate, not first choice. |
| **CodeMirror 6 live preview** (see §5) | **Text** | Not applicable — there is no serialization. Saves are byte-identical except the edited range. | via decorations/widgets | FM: fold/decorate the block · HTML: shown as-is · footnotes: decorate · wikilinks: decorate | MIT | CM6 core: GitHub repos archived 2026-04-15, "moved to https://code.haverbeke.berlin/codemirror/dev" ([github](https://github.com/codemirror/dev)); npm releases continue **[verify cadence]** | Recommended. |

Also noted: `prosemirror-markdown` GitHub repo archived 2026-04-01, moved to code.haverbeke.berlin (same author migration); known issue class: "Backslashes preceding escaped characters grow with each round-trip" ([search result, GitLab issue 607833](https://gitlab.com/gitlab-org/gitlab/-/issues/607833)).

### 4.2 Round-trip fidelity matrix (what a *save* does to text the user didn't touch)

| Construct | TipTap + markdown | Milkdown/Crepe (remark) | Lexical mdast | CM6 live preview |
|---|---|---|---|---|
| YAML frontmatter | Must be stripped and re-stitched by host (legacy did this) | Plugin; re-serialized by YAML lib (key order/quotes may change) | Not supported | Untouched (it's text) |
| GFM table with multi-line/`<br>` cells | Legacy needed a custom serializer + "row-losing" backstop | Normalized column padding; cell content re-escaped | Normalized | Untouched |
| Task list `- [ ]` vs `* [ ]`, `[X]` | Normalized | Normalized | Bullet char preserved | Untouched |
| Nested lists, 2- vs 4-space indent, `1.` vs `1)` | Normalized | Normalized | Partially preserved | Untouched |
| Raw HTML / HTML comments | Entity-escaped or parsed into doc (legacy BUG-122 h6) | Kept as `html` node; edits inside are raw | Dropped/escaped | Untouched (optionally rendered as widget when caret is outside) |
| Footnotes | No | Plugin | No | Decorate or leave raw |
| `[[wikilinks]]` | Custom node + serializer | Custom | Custom | Decoration only |
| Hard line breaks / trailing spaces / soft wraps | Collapsed (legacy BUG-107/122 h4) | Collapsed | Mostly preserved | Untouched |
| Escapes (`\*`, `\_`, `#` at line start) | Re-escaped (bold-marker bug) | Re-escaped | Preserved where possible | Untouched |

### 4.3 Bundle size / memory in WKWebView **[estimates, measure in spike]**

- CM6 + `@lezer/markdown` + search + a decoration layer: roughly 300–500 KB minified JS, well under 1 MB with a highlighter.
- TipTap starter-kit + tables + tasks + lowlight + markdown: 0.8–1.5 MB.
- Milkdown Crepe (ProseMirror + remark + CodeMirror for code blocks + KaTeX if Latex enabled): 1.5–3 MB.
- Vditor: several MB (Lute + CDN assets).
- In all cases the dominating cost is the WebContent process itself, not the JS bundle. On this Mac on 2026-10-03, `ps` shows an idle `com.apple.WebKit.WebContent` at ~2 MB RSS (a prewarmed, suspended process), `WebKit.Networking` ~17 MB and `WebKit.GPU` ~15 MB (shared, one each). A WebContent process with a loaded editor page and a 1 MB document is more plausibly 40–120 MB **[estimate]**. Measure with Instruments in spike 1.

### 4.4 The Swift ↔ JS bridge (applies to any web editor)

- **Native → JS:** `WKWebView.callAsyncJavaScript(_:arguments:in:contentWorld:)` (async/await, structured arguments, runs in a `WKContentWorld` so page scripts can't tamper) — [WKWebView docs](https://developer.apple.com/documentation/webkit/wkwebview). Use it for `setDocument(text, path)`, `applyExternalChange(diff)`, `exec("bold")`, `getText()`, `getSelection()`.
- **JS → native:** `WKScriptMessageHandlerWithReply` (reply-capable; `window.webkit.messageHandlers.duo.postMessage(...)` returns a promise) registered on `WKUserContentController` for `docChanged` (debounced, send diff or full text), `selectionChanged` (for menu validation), `openLink`, `requestImage`, `dirty`.
- **File loading:** load the editor shell via `loadFileURL(_:allowingReadAccessTo:)` scoped to the bundled editor folder, *or* serve everything through a custom scheme (`duo-editor://`) so the document origin is stable and `allowingReadAccessTo` doesn't have to widen to the user's whole repo.
- **Local images:** register a `WKURLSchemeHandler` for `duo-file://` that resolves relative paths against the document's directory and streams bytes (with MIME). This avoids `file://` origin restrictions and lets us gate what the page can read. On macOS 26 the SwiftUI `URLSchemeHandler` protocol returns an `AsyncSequence<URLSchemeTaskResult>` ([Apple WebPage docs](https://developer.apple.com/documentation/webkit/webpage)).
- **Keyboard / menus:** NSMenu key equivalents are matched by the menu bar *before* the web view sees the key event, so Cmd-B/I/K/F/Z must either (a) exist as menu items that call `callAsyncJavaScript("duo.exec('bold')")`, with `validateMenuItem` driven by the last `selectionChanged` message, or (b) be absent from menus so CM6's keymap handles them. (a) is the native-feeling choice and also gives discoverability. `WKWebView` conforms to `NSUserInterfaceValidations` and `NSStandardKeyBindingResponding` so Edit-menu basics (cut/copy/paste/select all) already work.
- **Spellcheck / dictation / Writing Tools:** CM6 edits a `contenteditable`, so macOS spellcheck underlines, correction popovers, dictation and (macOS 15.1+) Writing Tools work inside WKWebView; `WebPage.isWritingToolsActive` / `WKWebView.isWritingToolsActive` exist in the API. CM6's `EditorView.contentAttributes` can set `spellcheck="true"`, `autocorrect`. Verify Writing Tools interaction with decorations in spike 1 **[unverified]**.
- **Find:** `WKWebView` conforms to `NSTextFinderClient` and has `find(_:configuration:)` (native find bar usable for browser tabs). For the editor, prefer CM6's `@codemirror/search` driven from a *native* find bar (SwiftUI text field → `callAsyncJavaScript("duo.find(q)")`) so the UI matches the rest of the app.
- **Selection / caret appearance:** contenteditable uses the system accent for `::selection` by default and the native I-beam/caret; CM6 draws its own cursor layer by default (`drawSelection`) — disable it to keep the native caret and selection if desired.

---

## 5. The "Obsidian live preview" approach (CodeMirror 6 decorations)

**Mechanism.** `@codemirror/lang-markdown` (Lezer, GFM extensions) yields an incremental syntax tree. A `ViewPlugin` walks the visible tree and emits `Decoration.mark` (styling: headings, emphasis, inline code), `Decoration.replace` (hide `**`, `#`, `[`…`](…)`, show a rendered image/checkbox widget), and `Decoration.widget` / block `replace` (render a fenced code block, a table, an HTML block, a frontmatter block as a widget). When the selection enters a node's range, its decorations are dropped so the raw syntax reappears for editing. Obsidian, SilverBullet ("heavily inspired by Obsidian's live preview mode" — [silverbullet.md Live Preview](https://silverbullet.md/Live%20Preview)), and the packages below all work this way.

**Fidelity.** Perfect by construction: the file content *is* the editor state. Saves emit `state.doc.toString()`. Untouched regions are byte-identical. External edits are applied as `ChangeSet`s (see §7.5). Frontmatter, HTML comments, footnotes, wikilinks, odd escapes — all preserved whether or not we render them.

**Feel vs ProseMirror WYSIWYG.** Honest trade-offs:

- Syntax flashes into view on the active line/node. Obsidian users accept this; Typora/Bear hide it more aggressively (Bear 2 shows markers only near the caret, same idea). Tunable: reveal per-node (inline) rather than per-line.
- Tables are the hard case. Options: (1) Obsidian-style editable table widget — a block widget rendering `<table>` with contenteditable cells whose edits are mapped back to the source range (atomic-editor does this: "Click a cell to edit in place; wide tables scroll horizontally" — [atomic-editor](https://github.com/kenforthewin/atomic-editor)); (2) HyperMD/rich-markdoc style — render widget until caret enters, then show raw pipes with auto-alignment (Obsidian 1.5 also auto-formats pipes). (1) is the better UX and about 1–2 weeks of work **[estimate]**.
- Lists: bullets render as glyphs, checkboxes are clickable widgets that toggle `[ ]`↔`[x]` via a transaction. Indent/outdent are plain text commands.
- Images: inline widget below/instead of `![alt](path)`, loaded through `duo-file://`.
- Block-level drag handles / slash menus (Notion-like) are harder than in ProseMirror but doable (`@codemirror/autocomplete` for `/` commands; Obsidian has both).
- Undo/redo, find/replace, multi-cursor, large files, virtualized rendering: CM6 strengths; the legacy 1.2 MB `tasks.md` would be fine.

**Existing open-source implementations (GitHub API, 2026-10-03):**

| Project | Stars / last push | Framework | Renders inline | Tables | Tasks | License | Fit |
|---|---|---|---|---|---|---|---|
| [kenforthewin/atomic-editor](https://github.com/kenforthewin/atomic-editor) | 149 / 2026-09-28 | React (peer dep) + CM6 | headings, bold/em, highlights, links, images, tables, task lists, wikilinks | **editable in place** | Yes | MIT | **Best reference**; extracted from a production app. React peer dep is a con for a bare WKWebView page (could still use React, or lift the decoration code). |
| [davidmyersdev/ink-mde](https://github.com/davidmyersdev/ink-mde) | 304 / 2026-07-31 | framework-agnostic (Vue/Svelte wrappers) | "hybrid plain-text markdown rendering", inline image previews, GFM, highlighting, vim, search | no widget | styled | MIT | Lighter-touch styling (does not hide syntax as fully). Good scaffolding. |
| [tiagosimoes/codemirror-markdown-hybrid](https://cdn.jsdelivr.net/npm/codemirror-markdown-hybrid@1.2.2/README.md) | — | CM6 ext, peer deps only | "rendered preview for unfocused lines and raw markdown for the line or block being edited"; tables, task lists, KaTeX, mermaid | rendered (edit via raw) | Yes | MIT | Worth reading; maturity unknown **[unverified]**. |
| [segphault/codemirror-rich-markdoc](https://github.com/segphault/codemirror-rich-markdoc) | 122 / 2024-11-20 | CM6 | hides syntax near cursor; tables as block widget that reveals source on entry | rendered (edit via raw) | no | MIT | Stale; known perf issue ("recomputes all replaced regions on every operation"). Reference only. |
| [Type-32/codemirror-rich-obsidian](https://github.com/Type-32/codemirror-rich-obsidian) | 10 / 2026-04-28 | Vue/Nuxt | links, callouts, partial tasks/code | **no** (deferred) | partial | MIT | Too early, Vue-bound. |
| [silverbulletmd/silverbullet](https://github.com/silverbulletmd/silverbullet) | 6.2k / 2026-10-03 | Deno app, CM6 | full live preview incl. widgets | yes | yes | MIT | Not packaged as a library; mine for techniques. |
| [laobubu/HyperMD](https://github.com/laobubu/HyperMD) | 1.6k / 2021-01-05 | **CodeMirror 5** | tables, tasks, images, math, footnotes | yes | yes | MIT | Dead (CM5). Historical reference. |
| Obsidian | — | Electron, CM6 | everything | editable widget (1.5+) | yes | proprietary | The UX bar. |

**Does this better satisfy "edit the rendered markdown"?** Yes, with the caveat that it is *rendered-with-reveal* rather than *rendered-always*. It satisfies requirement 3 (round-trip) absolutely, requirement 4 (concurrent edits) elegantly (external changes become transactions), and requirements 1–2 to Obsidian's standard. ProseMirror satisfies 1–2 slightly better (never shows syntax) and fails 3 structurally.

---

## 6. Embedded browser

### 6.1 WKWebView capabilities (AppKit; availability per Apple docs fetched 2026-10-03)

| Need | API | Availability | Notes |
|---|---|---|---|
| Local HTML file/folder | `loadFileURL(_:allowingReadAccessTo:)`, `loadFileRequest(_:allowingReadAccessTo:)` — "to read additional files related to the content file, specify a directory" | macOS 10.11+ | Scope read access to the project folder, not `/`. For files that reference siblings via relative paths this is enough; for `file://` pages that fetch() you'll hit origin rules → use a custom scheme. |
| Custom origin / virtual files | `WKURLSchemeHandler` on `WKWebViewConfiguration.setURLSchemeHandler(_:forURLScheme:)` | 10.13+ | Serve `duo-app://project/…` from disk; gives a stable origin, lets you inject headers, block paths, rewrite. |
| localhost dev servers | plain `load(URLRequest)` | — | Works; `http://localhost` is treated as a secure context by WebKit. Service workers OK. Add `NSAllowsLocalNetworking`/ATS exception only if loading http:// non-localhost. |
| General web, logins, OAuth | `WKWebsiteDataStore.default()` (persistent), `.nonPersistent()` (private), `init(forIdentifier:)` (named profiles), `httpCookieStore`, `removeData(ofTypes:…)`, `proxyConfigurations` | class 10.11+; `forIdentifier:` is the newer profile API (introduced with macOS 14 **[unverified exact version]**) | Cookies/localStorage persist across launches with the default store. Google-style OAuth works in WKWebView (it is a real browser UA); some IdPs block "embedded" UAs — set `customUserAgent` to a Safari UA if needed **[verify per provider]**. Popups (`window.open`) need `WKUIDelegate.createWebViewWith` to return a new WKWebView (same config) or they silently fail — required for OAuth popups. |
| DevTools | `isInspectable = true`; then Safari ▸ Develop ▸ <Mac name> | macOS 13.3+ ([webkit.org, 2023-03-20](https://webkit.org/blog/13936/enabling-the-inspection-of-web-content-in-apps/)) | Full Web Inspector (DOM, console, network, timelines). No in-app docked DevTools like Electron. |
| Downloads | `WKNavigationDelegate … decisionHandler(.download)`, `WKDownload` + `WKDownloadDelegate`, `startDownload(using:)`, `resumeDownload(fromResumeData:)` | macOS 11.3+ | You implement destination picking and progress UI. |
| Print / PDF | `printOperation(with: NSPrintInfo)`, `createPDF(configuration:)` / `pdf(configuration:) async`, `takeSnapshot`, `createWebArchiveData` | 11.0+ | Fine for "export to PDF". |
| Content blocking | `WKContentRuleListStore.compileContentRuleList` with Safari-style JSON rules, added to `userContentController` | 10.13+ **[not re-verified today]** | Can block trackers/ads in the general browser. |
| Find | `find(_:configuration:)`, `NSTextFinderClient` conformance | 11.0+ | Native find bar works out of the box on browser tabs. |
| JS bridge | `evaluateJavaScript`, `callAsyncJavaScript`, `WKContentWorld`, `WKScriptMessageHandlerWithReply`, `WKUserScript` | 11.0+ for async/world APIs | — |
| Zoom | `pageZoom`, `magnification`, `allowsMagnification` | — | — |
| Screen Time / Writing Tools / media capture / fullscreen | `isBlockedByScreenTime`, `isWritingToolsActive`, `cameraCaptureState`, `fullscreenState` | 15+/varies | Useful for Meet/Slack-style pages. |
| Web extensions | `WKWebExtensionController` (also on `WebPage.Configuration.webExtensionController`) | macOS 15.4+ **[unverified]** | Could host user extensions later. |

**Process model.** WebKit2 runs the UI process (your app), one shared Networking process, one GPU process, and WebContent processes. "By default, WebKit gives each web view its own process space until it reaches an implementation-defined process limit, after which web views with the same `WKProcessPool` object share the same web content process" (Apple `WKProcessPool` docs via search, 2026-10-03). Practical consequences: use **one `WKProcessPool`** across all Duo web views (also required if you want shared `WKUserContentController` script injection across tabs); expect ≈ one WebContent process per *visible* browser tab plus the editor; a crashed page only kills its own process (`webViewWebContentProcessDidTerminate` → reload). Memory per WebContent process: tiny when idle/suspended (observed ~2 MB RSS on this Mac today) and 30–200 MB with a real site loaded **[estimate — measure]**. WebKit also aggressively suspends background tabs' processes under memory pressure.

**Limits / gotchas.**
- No docked DevTools; no Chrome extensions; no CDP (the legacy app used a `cdp-bridge.ts` against Electron's Chromium — any "Claude can drive the browser" feature must be rebuilt on `evaluateJavaScript`/`WKUserScript` or on Safari's WebDriver, not CDP).
- Rendering parity: WebKit ≠ Chromium. Internal tools built for Chrome may differ slightly; this is Safari-level compatibility, which is fine for Google Workspace/Slack/Jira.
- `file://` pages have tighter origin rules than Chromium; use a scheme handler for app-served content.
- Popup windows, `beforeunload`, JS dialogs, file inputs, and auth challenges all require delegate implementations (`WKUIDelegate`, `WKNavigationDelegate`); nothing is free, but each is a few dozen lines.

### 6.2 macOS 26: WebKit for SwiftUI (`WebView` + `WebPage`)

Introduced at WWDC25 (session 231, "Meet WebKit for SwiftUI" — [developer.apple.com/videos/play/wwdc2025/231](https://developer.apple.com/videos/play/wwdc2025/231)). Availability per Apple docs: **macOS 26.0+, iOS 26+, visionOS 26+** ([WebPage](https://developer.apple.com/documentation/webkit/webpage), [WebPage.Configuration](https://developer.apple.com/documentation/webkit/webpage/configuration)).

- `WebPage` is `@Observable`; `load(_:)` returns an `AsyncSequence<NavigationEvent>`; `callJavaScript(_:arguments:in:contentWorld:) async throws`; `NavigationDeciding` and `DialogPresenting` protocols replace the delegate soup; `backForwardList` is observable; `isInspectable`; `customUserAgent`; `exported(as:)` for PDF/web-archive via `Transferable`; media/camera/fullscreen state.
- `WebPage.Configuration`: `websiteDataStore`, `urlSchemeHandlers: [URLScheme: URLSchemeHandler]` (handler returns `AsyncSequence<URLSchemeTaskResult>`), `userContentController`, `loadsSubresources`, `defaultNavigationPreferences`, `applicationNameForUserAgent`, `webExtensionController`, `limitsNavigationsToAppBoundDomains`.
- `WebView` SwiftUI modifiers: `findNavigator(isPresented:)`, `webViewScrollPosition`, `webViewScrollInputBehavior`, `onScrollGeometryChange`, plus content-background/magnification/link-preview modifiers ([wwdcnotes](https://wwdcnotes.com/documentation/wwdc25-231-meet-webkit-for-swiftui/), [dev.to summary](https://dev.to/arshtechpro/wwdc-2025-webkit-for-swiftui-2igc)).
- **Not visible in the `WebPage` API surface fetched today:** downloads (`WKDownload`), print operations, `takeSnapshot` equivalents beyond `exported(as:)`, and a way to reach the underlying `WKWebView` **[unverified — check headers]**. If any of those matter, the AppKit `WKWebView` in an `NSViewRepresentable` remains the safer base and is what Apple's own API is built on.

**Decision rule:** if Duo v2's deployment target is macOS 26+, use `WebView`/`WebPage` for the *browser* (cleaner SwiftUI integration, async navigation, observable state) and still consider `WKWebView` for the *editor* (needs `callAsyncJavaScript` in a content world — available on both — and possibly `NSTextFinderClient`). If the target is macOS 15, wrap `WKWebView`; the API gap is small and the wrapper is ~200 lines.

### 6.3 Alternatives

| Option | Verdict |
|---|---|
| **CEF / Chromium embedding** (e.g. [lvsti/CEF.swift](https://github.com/lvsti/CEF.swift), BSD-3, last push 2021-11-01) | Not recommended. Adds a ~150–250 MB `Chromium Embedded Framework.framework` plus helper apps (GPU/Renderer/Plugin) to the bundle **[estimate]**, Chromium-level memory per renderer, a C++ build pipeline, monthly security rebases, and the only Swift binding is abandoned. The only reason to do this is CDP/Chrome-extension parity, which Duo v2 doesn't need as a hard requirement. |
| **Tauri v2** (Rust core + WKWebView on macOS) | Not a fit for a Swift-first app: it *is* WKWebView underneath, so it gives no rendering advantage, and it adds a Rust toolchain and a second UI framework. Memory claims vary by benchmark: 2026 write-ups show Tauri idle ≈ 42–80 MB vs Electron ≈ 160 MB ([rustify.rs](https://rustify.rs/articles/rust-tauri-vs-electron-2026), [buildmvpfast](https://www.buildmvpfast.com/blog/tauri-v2-vs-electron-desktop-apps-2026)), but an older Tauri issue measured WKWebView *higher* than Electron for a heavy web app on macOS 12 ([tauri#5889](https://github.com/tauri-apps/tauri/issues/5889)). Lesson: WKWebView is cheap when the page is light; the editor page should be light. |
| **Electron (status quo)** | Rejected by brief: ~96 MB bundle, 160 MB+ idle, non-native feel. |

---

## 7. Recommendation

### 7.1 Editor: CodeMirror 6 live preview in a WKWebView

Build a small, framework-free editor page (`editor/index.html` + ESM bundle, Vite or esbuild) around:

- `@codemirror/state`, `view`, `commands`, `search`, `autocomplete`, `language`, `lang-markdown` with `@lezer/markdown` GFM + Task + Strikethrough + Table + a tiny Wikilink/Frontmatter extension;
- a decoration layer modelled on `atomic-editor` (MIT) — evaluate forking its decoration code vs adopting it with React. If we adopt React we pay ~45 KB and a build step; acceptable but a plain CM6 `ViewPlugin` is preferable for a single-page host;
- widgets: checkbox, image (via `duo-file://`), fenced code (highlight with `@lezer/highlight` or Shiki-in-worker), editable table, frontmatter (collapsed chip that expands to raw YAML, with the native Properties panel reading the same text), HTML block (raw, monospace tint), horizontal rule, blockquote/callout;
- commands exposed on `window.duo` for the native menu bridge: `exec(cmd)`, `setDoc`, `applyChanges(changes)`, `getDoc`, `find`, `selectionInfo`.

What we give up vs TipTap: Notion-style drag handles out of the box, "never see syntax" purity. What we gain: zero serialization bugs, byte-faithful saves, trivially correct external-change merging, lower memory, an MIT stack with no pro tier.

**Fallbacks, in order:** (1) Milkdown Crepe (MIT, batteries-included) if the live-preview feel is rejected in the spike — accept lossy saves and port the legacy frontmatter/echo machinery; (2) Vditor IR mode; (3) native `swift-markdown-engine` if its hedge spike surprises on the upside.

### 7.2 Browser: WKWebView

- One `WKProcessPool`, one persistent `WKWebsiteDataStore` (default) for the "signed-in" browser; an optional `init(forIdentifier:)` profile per workspace if users want isolation; `.nonPersistent()` for a private tab.
- `WKUIDelegate.createWebViewWith` to support OAuth popups; `customUserAgent` configurable.
- `isInspectable` toggle in a Developer menu; `WKDownload` → `~/Downloads` with a progress row; `createPDF` + `printOperation` for Print/Export.
- Local folders via a `duo-app://` scheme handler (stable origin; path allow-list) rather than widening `allowingReadAccessTo`.
- Content rule list for tracker blocking is optional polish.
- Prefer `WebPage`/`WebView` only with a macOS 26 floor.

### 7.3 How many web views, and memory

| Surface | Web views | Memory **[estimate — measure in spikes]** |
|---|---|---|
| Native shell (SwiftUI/AppKit, terminal, file tree, chat) | 0 | 40–80 MB |
| Editor | 1 (documents swap in; keep per-doc `EditorState` in JS memory for instant tab switching, or serialize to native on tab change) | 40–120 MB for the WebContent process |
| Browser tabs | 1 WKWebView per tab; WebKit coalesces into shared WebContent processes past its limit and suspends background tabs | 30–200 MB per *active* tab; near zero when suspended |
| HTML preview of a project file | reuse a browser tab | — |
| Shared WebKit Networking + GPU processes | — | ~15–20 MB each (observed today) |

Idle app with one document and no browser tabs: ≈ 100–200 MB total vs the legacy Electron app's higher baseline. Three logged-in browser tabs: add 150–400 MB. This is the expected shape; the spike should produce real numbers.

### 7.4 Spikes to run first (ordered)

1. **CM6 live preview feasibility (3–4 days).** Static HTML page in a WKWebView; load the legacy `~/repos/duo/tasks.md` (1.2 MB) and `docs/about-duo.md` (HTML comments). Implement headings/emphasis/links/images/task lists/code fences via decorations; measure typing latency and WebContent RSS; check spellcheck squiggles, dictation, and Writing Tools inside the editor; check selection/caret appearance with `drawSelection` on and off. Exit criterion: byte-identical save of an untouched file; sub-16 ms keystroke on the 1.2 MB file.
2. **External-change merge (1–2 days).** Watch the file with `DispatchSource`/FSEvents; have Claude Code edit it while the editor has unsaved changes; implement §7.5; verify cursor and undo survive.
3. **Native hedge: `swift-markdown-engine` (2 days).** Same two files; tables and task lists; Writing Tools; memory. If it is within striking distance, it becomes the long-term "phase 2" option and informs the abstraction boundary (an `EditorSurface` protocol with web and native implementations).
4. **Browser essentials (2 days).** Google/Atlassian/Slack login with persistent cookies across relaunch; OAuth popup via `createWebViewWith`; `localhost:5173` Vite app; a project folder via `duo-app://`; `isInspectable`; a download; PDF export; per-tab RSS with 5 tabs.
5. **Menu/keyboard bridge (1 day).** Cmd-B/I/K/F/Shift-Cmd-F routed through NSMenu → `callAsyncJavaScript`; `validateMenuItem` fed by `selectionChanged`; confirm Cmd-Z goes to the editor when focused (legacy ENH-221 bug class).
6. **Editable table widget (1–2 weeks, after 1 passes).** This is the single biggest UX item; budget it explicitly.

### 7.5 Concurrent edits by Claude Code (external change handling)

The legacy app's `useDiskReconciliation` hook is a good spec of the *problem*; the CM6 architecture makes the *solution* much smaller:

1. **Watch** the open file's directory with FSEvents/`DispatchSource` (Claude Code's `Edit`/`Write` and most editors write temp-then-rename, which appears as delete+create; debounce ~100 ms and treat a delete that is followed by a create as a modify; only after ~1.5 s with no re-create treat it as "removed on disk", as the legacy ENH-216 logic did).
2. **Echo suppression by content, not regex:** before each save compute SHA-256 of the exact bytes written and remember (hash, mtime, size). A watcher event whose file hashes to a remembered value is our own echo → ignore. No normalization layer is needed because the editor's text *is* what we wrote.
3. **Clean buffer:** read the new bytes, compute a minimal diff against the current doc (e.g. `diff-match-patch`/`fast-diff` → list of `{from, to, insert}`), and dispatch it as one CM6 transaction annotated `external: true`. CM6 maps the selection, scroll anchor, folds and decorations through the `ChangeSet`, so the cursor stays on the same logical text; the transaction can be excluded from the user's undo history (`addToHistory: false`) or kept, by policy. Paint "changed" gutter marks from the change set (the legacy `JustAdded` behaviour comes for free).
4. **Dirty buffer:** three-way merge with base = last-loaded disk text, ours = buffer, theirs = new disk text (line-level diff3; `node-diff3` or a 150-line Swift port). Non-overlapping hunks apply as in step 3; overlapping hunks raise a non-modal banner with "Keep mine / Take theirs / Show diff", exactly like a git conflict. Because both sides are plain text, the merge is deterministic — the legacy app could not do this because its "ours" was a re-serialized document that differed from base even with no edits.
5. **Save path:** write temp + rename, then record the hash (step 2). Autosave on a 1–2 s idle timer, plus explicit Cmd-S. Never save a buffer that has not changed (hash compare) so git never sees churn.
6. **Agent-initiated edits through Duo** (legacy `duo doc edit`): accept them as the same `applyChanges` transaction path instead of disk writes when the file is open; this is just step 3 with a different source.

---

## 8. Sources

Fetched 2026-10-03 unless noted.

- Legacy app: `~/repos/duo` — `package.json`, `renderer/components/editor/**`, `renderer/hooks/useDiskReconciliation.ts`, `CHANGELOG.md`, `docs/DECISIONS.md`, `docs/RELEASES.md`, `tasks.md`.
- GitHub repository metadata (stars, last push, license, archived) via `gh api repos/<owner>/<repo>`.
- Apple: [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview), [WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore), [WKDownload](https://developer.apple.com/documentation/webkit/wkdownload), [WebPage](https://developer.apple.com/documentation/webkit/webpage), [WebPage.Configuration](https://developer.apple.com/documentation/webkit/webpage/configuration), [loadFileURL(_:allowingReadAccessTo:)](https://developer.apple.com/documentation/webkit/wkwebview/loadfileurl(_:allowingreadaccessto:)), WWDC25 session 231 via [wwdcnotes](https://wwdcnotes.com/documentation/wwdc25-231-meet-webkit-for-swiftui/) and [dev.to](https://dev.to/arshtechpro/wwdc-2025-webkit-for-swiftui-2igc).
- WebKit blog: [Enabling the Inspection of Web Content in Apps](https://webkit.org/blog/13936/enabling-the-inspection-of-web-content-in-apps/) (2023-03-20).
- Editors: [TipTap markdown docs](https://tiptap.dev/docs/editor/markdown), [@tiptap/markdown changelog](https://tiptap.dev/docs/resources/changelog/markdown), [TipTap OSS commitment](https://tiptap.dev/open-source-to-cloud), [TipTap pricing explainer (dev.to)](https://dev.to/eddyter/tiptap-pricing-explained-2026-free-vs-pro-vs-cloud-cost-breakdown-3l5g), [Milkdown](https://github.com/Milkdown/milkdown) and [Crepe features source](https://raw.githubusercontent.com/Milkdown/milkdown/main/packages/crepe/src/feature/index.ts), [@lexical/mdast](https://lexical.dev/docs/packages/lexical-mdast), [tui.editor](https://github.com/nhn/tui.editor), [Vditor](https://github.com/Vanessa219/vditor), [prosemirror-markdown](https://github.com/ProseMirror/prosemirror-markdown), [codemirror/dev archive notice](https://github.com/codemirror/dev).
- CM6 live preview: [atomic-editor](https://github.com/kenforthewin/atomic-editor), [ink-mde](https://github.com/davidmyersdev/ink-mde), [codemirror-markdown-hybrid README](https://cdn.jsdelivr.net/npm/codemirror-markdown-hybrid@1.2.2/README.md), [codemirror-rich-markdoc](https://github.com/segphault/codemirror-rich-markdoc), [codemirror-rich-obsidian](https://github.com/Type-32/codemirror-rich-obsidian), [HyperMD](https://github.com/laobubu/HyperMD), [SilverBullet Live Preview](https://silverbullet.md/Live%20Preview), [Obsidian editor docs](https://docs.obsidian.md/Plugins/Editor/Editor), [Obsidian 1.5.8 changelog](https://obsidian.md/changelog/2024-02-22-desktop-v1.5.8/).
- Native: [swift-markdown-engine](https://github.com/Jon-Schneider/swift-markdown-engine), [LapermEditor](https://github.com/k-ymmt/LapermEditor), [MacDown 2](https://github.com/Joncallim/macdown_2), [MarkupEditor](https://github.com/stevengharris/MarkupEditor), [STTextView](https://github.com/krzyzanowskim/STTextView), [CodeEditSourceEditor](https://github.com/CodeEditApp/CodeEditSourceEditor), [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui), [Textual](https://github.com/gonzalezreal/textual), [Editorio](https://editorio.crncevic.org/).
- Commercial apps: [Bear (Wikipedia)](https://en.wikipedia.org/wiki/Bear_(app)), [Bear blog: Panda](https://blog.bear.app/tag/panda/), [Typora dependencies](https://rywalker.com/research/typora), [Craft write-up](https://blakecrosley.com/guides/design/craft).
- Alternatives: [CEF.swift](https://github.com/lvsti/CEF.swift), [Tauri vs Electron 2026 (rustify)](https://rustify.rs/articles/rust-tauri-vs-electron-2026), [Tauri v2 vs Electron (buildmvpfast)](https://www.buildmvpfast.com/blog/tauri-v2-vs-electron-desktop-apps-2026), [tauri#5889 memory benchmark](https://github.com/tauri-apps/tauri/issues/5889).
- Local measurement: `ps -axo rss=,comm= | grep WebKit` on this Mac, 2026-10-03.
