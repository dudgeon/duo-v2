# Spike: opening a Word document as Markdown (ENH-14)

Status: **research done, awaiting Geoff (DL-123)** · 2026-10-06 · F-114, F-115

**The ask (Geoff, 2026-10-06):** a minimally destructive .docx → .md open path. Opening a .docx asks for consent to convert it. Duo then does its best to produce clean Markdown, repairing structure Word only implies: headings set by font size, typed bullets, and so on. The goal is Markdown that imports well into Google Docs.

**Recommendation:**
- **Converter:** our own, in Swift. It is about 750 lines (`Spikes/DocxToMarkdown/Docx.swift`) on the zip and XML reader that `Pptx.swift` already has. It adds nothing to the app's size, has no licence to carry, works offline and on the work Mac, and is the only option of those tested that repairs messy documents.
- **Output:** pinned to the Markdown subset that Google Docs imports cleanly (tested, below). That is headings, bold, italic, strikethrough, links, tight nested lists, GFM tables, block quotes, footnotes and images. There is no raw HTML anywhere.
- **Minimally destructive:**
  - the .docx is never written;
  - `<name>.md` goes beside it, and if that name is taken Duo asks;
  - images go in `<name>-images/`;
  - a short summary says what was inferred, cleaned or left out;
  - Undo removes the new files.
- **Tracked changes:** accept them, as Word shows the document in its default view, and say how many in the summary.
- **Comments:** leave them out and say how many. The .docx keeps them. Turning them into footnotes would put review chatter into the text a reader sees in Google Docs.

## How the converters compare

Nine synthetic documents (`Spikes/DocxToMarkdown/make_docs.py`, python-docx) were run through pandoc 3.12, mammoth 1.13 and the Swift prototype. The outputs are in `Spikes/DocxToMarkdown/out/{pandoc,mammoth,duo}/`.

| | **Our own (Swift, prototype)** | pandoc 3.12 | mammoth 1.13 (JS) |
|---|---|---|---|
| **Clean document (01)** | Title → `#` with the headings shifted under it; nested list; GFM table; link; quote | Drops the Title paragraph (it goes to metadata); loose lists; the "List Bullet 2" item becomes a separate list split by `<!-- -->` | Title becomes plain text; **the table is lost** (one cell per paragraph); escapes every `.`; nesting flattened |
| **Fake headings (02)** | `#`/`##`/`###` from font size, `###` from bold at body size; the long bold sentence and the italic pull quote stay text | Bold paragraphs, no headings | Bold paragraphs (`__x__`), no headings |
| **Typed lists (03)** | `•`, `-`, `*`, `1.`, `3)`, `a)` become real lists; `1.1 Planning` and "2026 was…" stay text | Escaped text (`1\.`, `\-`) | Escaped text |
| **Layout table (04)** | One-row table unwrapped to paragraphs; data table kept; merged cell split | **Raw HTML `<table>`** for both the layout table and the merged one | All tables lost |
| **Tracked changes (05)** | Accepted (or rejected, as an option); counted | Accepted (`--track-changes=accept`) | Accepted |
| **Comments (06)** | Left out and counted (footnotes as an option) | Dropped silently | Dropped silently |
| **Images (07)** | `<name>-images/image-1.png` with alt text, relative links | **Raw HTML `<img>`** with sizes, under `media/` | Base64 data URIs inline (a 40 KB photo is a 54 KB line) |
| **Footnotes, fields (08)** | `[^1]`; HYPERLINK field → link; PAGE → its text; two soft breaks → a new paragraph | `[^1]`; field link kept; `\` hard breaks | Raw `<a id>` anchors and an ordered list for notes; no field link |
| **Mixed (09)** | Outline-level paragraph → heading; custom style based on Heading 2 → heading; "List Bullet 2/3" nested by indent; `H₂O` | Outline paragraph as text; `<u>`, `<sub>` raw HTML; list split three times | Custom heading style lost; underline/sub dropped |
| **Raw HTML in output** | Never | Tables, images, underline, sub/superscript | Footnote anchors |
| **Licence** | Ours | GPL-2.0-or-later | BSD-2-Clause |
| **Size** | ≈0 (Swift, on code we have) | **192 MB** arm64 binary (Duo.app is 94 MB) | 405 KB browser bundle, run in a JSContext |
| **Offline / work Mac (C-1)** | Built in | Built in if bundled; otherwise the user installs it, which needs a download through the proxy, and Homebrew wants admin | Built in |
| **Effort to production** | M: prototype done; port to `Sources/DuoSearch`, DuoChecks, the edge cases below | S to wire, but the clean-up has to be written anyway, as a Lua filter or a post-pass on its AST (JSON) | M: mammoth gives HTML; we'd add an HTML → Markdown step (Turndown) *and* still write the clean-up |

**pandoc and the GPL.** Shipping pandoc inside Duo.app as a separate program we call is "mere aggregation". The GPL allows it, but Duo would have to carry pandoc's licence and offer its source (or a written offer) with every release, for pandoc and its Haskell dependencies. It would also triple the download. Requiring the user to install it instead is a non-starter on the work Mac. Either way pandoc only does the easy half. It converts structure that is already semantic very well, but it infers nothing, and its GFM writer falls back to raw HTML for anything a pipe table or `![]()` can't hold. We'd still write the clean-up.

**Others looked at, not run:**
- `markitdown` (Microsoft, MIT): Python; it is mammoth → HTML → markdownify, so the same limits plus a Python runtime.
- `docx2md`-style Go and Python tools: thin wrappers over python-docx or pandoc, with no inference.
- LibreOffice headless: about 1 GB, and its Markdown export is new and thin.
- Aspose: commercial.
- Apple's own `NSAttributedString(docFormat:)`: reads .docx into attributed text (fonts and sizes, no styles, lists as text), and its Markdown support goes the other way only. That's a possible fallback for the run-level look, but not needed.

## What Google Docs imports cleanly

Tested 2026-10-06 by importing Markdown into a Google Doc through Drive (File → Open does the same), viewing it in Duo's browser, and exporting it back as Markdown and HTML. Screens: `docs/plan/spikes/docx-to-markdown/gdocs-*.png`.

| Markdown | In Google Docs |
|---|---|
| `#`…`######` | Heading 1–6 (Docs styles them, e.g. H3 bold, H4 italic) |
| `**b**`, `*i*`, `***bi***`, `~~s~~` | Yes |
| `` `code` `` | Yes, as green monospace |
| `[text](url)`, `<url>`, bare URLs | Yes |
| `\` or two-space hard break | Yes |
| Tight `-` lists nested 2 and 4 spaces; `1.` lists nested 3 spaces | Yes. **Loose lists (blank lines between items) get an empty paragraph between items.** |
| An ordered list's first number (`3.`) | Kept after a paragraph. **Two lists with only a blank line or `<!-- -->` between them merge**, and numbering continues. |
| `- [ ]` / `- [x]` | Checklist |
| GFM tables, with alignment | Yes; `\|` in a cell is kept |
| `> quote` | Indented paragraph |
| `---` | Horizontal line |
| `[^1]` + `[^1]: …` | **Real Docs footnotes** |
| `![alt](https://…)` and `![alt](data:image/png;base64,…)` | Embedded images |
| `![alt](relative/path.png)` | **Not imported** (Docs can't reach the file) |
| Fenced or indented code | **Plain body text**: fences and monospace lost |
| `~x~`, `^x^` (pandoc sub/sup) | Wrong: `~2~` becomes strikethrough |
| `<sub>`, `<sup>` | Work, but are raw HTML |
| `<u>` and other raw HTML | Tags dropped, text kept; `<br>` becomes a new paragraph |
| Escapes `\*`, `\#`, `1\.` | Kept literally, as intended |

So the output is GFM without raw HTML, with these rules:
- tight lists;
- never two different lists back to back;
- sub/superscript digits as Unicode (H₂O, x²);
- no `~` except for strikethrough;
- code blocks fenced. They read fine in Duo, and in Docs they become plain paragraphs, which is the best Markdown can do there.

Our prototype's output for all nine documents went through Docs and came back the same, apart from trailing spaces, alignment markers and Docs' heading emphasis (`out/duo-google-docs-roundtrip.md`).

**Images and Google Docs.** Relative image links are right for Duo and for any Markdown tool, but Docs can't follow them. A follow-up (ENH-14, part 2) could add "Copy for Google Docs" or "Export for Google Docs", which inlines images as data URIs (Docs embeds those) in a copy and never in the .md itself.

## Inferring structure: the rules and how sure each is

Body size is the size most characters are set in, outside styled headings (character-weighted), after resolving run → run style → paragraph style → document defaults.

| Rule | Confidence | Notes |
|---|---|---|
| Heading style (`heading 1–9`, or a style based on one, by name through `basedOn`) | **Certain** | Word's own semantics. A custom "Section Head" based on Heading 2 is a heading. |
| `Title` style → the single `#`, every heading shifted one level down | High | This is how Docs and most Markdown expect one H1. Normalized afterwards (next rule). |
| Levels renumbered from 1 with no gaps, and never more than one deeper than the previous heading | High | A clean outline: a document using Heading 1 and 3 only gets 1 and 2. |
| `w:outlineLvl` 0–8 on a non-list paragraph → heading level n+1 | **High** | It's what Word's navigator shows as a heading. |
| Larger than the body by ≥15%, ≤12 words, no `.,;:!` at the end (closing quotes ignored), not in a list, table or code → heading | **Medium-high** | Catches the "made it big and bold" heading. The punctuation rule keeps pull quotes and large intro sentences out. Sizes are clustered (rounded to 0.5 pt): the biggest is the highest level. When the document also has real headings, a fake one takes the level of the real heading nearest its size. |
| Bold throughout at body size, short, no end punctuation, **and followed by body text** → the lowest heading level | **Medium** | "Tools" and "DISPUTES" become headings; a bold sentence ending in "." doesn't; a run of bold lines stays a run of bold lines. This is the rule most likely to be wrong on a given document, so the summary names it ("…inferred from bold text"). |
| Real lists: `w:numPr` on the paragraph or its style → the numbering definition's format (`bullet` → `-`, anything else → `1.`), start and `startOverride`, numbers counted per list and level | **Certain** | Letter and roman numbering become `1.`, since Markdown has no other kind. |
| Nesting by indent: within a run of list items, the distinct left indents, smallest first, are the levels | High | Word's "List Bullet 2/3" are separate lists at ilvl 0 with a bigger indent. pandoc and mammoth both get this wrong. |
| Typed bullets (`• ● ○ ▪ – — - * ·` and Symbol-font U+F0B7, then a space or tab) → `-` | **High** | One is enough. |
| Typed numbers (`1.`, `2)`, `a)`) → a numbered list only in a run of two or more counting up by one | High | A lone "1." or "2026 was…" stays text (escaped `1\.`). `1.1 Planning` isn't a list marker and stays text. |
| Layout table: one row, or one column, or holding a nested table or a heading → its cells' contents, in reading order | Medium-high | A one-row data table would be unwrapped too; rare. Borderless multi-row layout grids are not detected yet (see open issues). |
| Data tables → GFM, the first row as header; merged cells split (blank cells); several paragraphs in a cell joined with a space | High (lossy) | Markdown tables can't merge or hold blocks. Counted in the summary. |
| Two or more line breaks in a row → a new paragraph; one → a hard break `\`; empty paragraphs dropped; page and column breaks dropped | High | Spacing done with Enter or Shift-Enter. |
| Monospace font throughout (Consolas, Courier, Menlo…) or a Code/Preformatted/"Plain Text" style → fenced code; monospace runs → `` `code` `` | High | |
| Bold, italic, strikethrough kept; underline dropped and counted; sub/superscript as Unicode where it exists, else plain | High | |
| Smart quotes, dashes and ellipses kept as they are | Certain | They're the author's text, and they survive Docs. |
| Hyperlinks (`w:hyperlink` and HYPERLINK fields) → links; internal bookmarks → plain text | High | |
| Other fields (PAGE, DATE, REF…) → their last shown result | High | |
| Table of contents (a TOC field or "toc n" styles) → left out, counted | High | Docs makes its own. |
| Footnotes and endnotes → `[^n]` at the end | Certain | Docs turns them back into footnotes. |
| Images → `<name>-images/image-n.<ext>`, alt text from `wp:docPr/@descr` (or the title); EMF/WMF are saved but counted as not viewable; linked (not embedded) images counted | High | |
| Text boxes → their paragraphs after the paragraph that anchors them | Medium | Their position on the page is lost. |
| Equations → their text, counted | Low | OMML → LaTeX is a later job. |
| Headers and footers → left out, counted | — | |

**Tracked changes and comments: the options.**
- *Tracked changes.* **Accept** (recommended): the text Word shows by default, and what a reader expects. **Reject**: the text before review. **Refuse to convert until resolved**: safe but annoying. Keeping both versions isn't possible: Markdown has no insert or delete marks except strikethrough, and Docs would show them as real text.
- *Comments.* **Leave out and count** (recommended; the .docx still has them). **Footnotes**: `[^c1]: Comment. Reviewer A: …`, but they become real footnotes in Google Docs. **A "Comments" section at the end**. HTML comments are invisible in Docs but are raw HTML.

## Minimally destructive: what Duo does

1. Opening a .docx (tree, ⌘P, `duo2 doc open`) shows the consent with three choices: Convert to Markdown, Open in Word / Pages (Open With), and Not now (Quick Look, as today, C-26).
2. On Convert, Duo writes `<name>.md` and `<name>-images/` beside the .docx and never touches the .docx. If `<name>.md` exists, Duo asks: open the existing one, replace it, or keep both as `<name> 2.md`.
3. The new .md opens in the editor, with the summary in the notice bar ("Converted from Report.docx: 4 headings inferred from font size, 2 tracked changes accepted, 1 comment left out…").
4. Undo (⌘Z in the file list, or `duo2 undo`) removes the .md and the images folder, provided neither has been edited since.
5. `duo2 file convert <docx> [--tracked accept|reject] [--comments leave-out|footnotes] [--replace]` does the same from the command line. It prints the paths and the summary (`--json` too).

## Open issues found in the spike
- Multi-row borderless layout grids, such as a two-column CV, are kept as tables. Detecting them needs border and shading reading (`tblBorders`, table style). Proposed: unwrap a table with no borders whose cells average more than 25 words.
- Fake headings inside a document that also has real ones are matched to the nearest real size. That's fine when sizes differ by about 1 pt or more, and ambiguous otherwise.
- A heading typed with its number ("3. Plot care") keeps the number in its text. It reads fine in Docs; Docs' own numbering isn't used.
- Big documents: the prototype holds the XML tree in memory. A 300-page report is about 15 MB of XML, which is fine; the zip reader caps each part at 64 MB.
- `.doc` (the old binary format) isn't covered: it stays Quick Look plus Open With.

## Browser notes (for the director)
Duo's browser was used for the visual checks (allow list: docs.google.com and accounts.google.com, on this Mac only):
- Google Docs shows "This browser version is no longer supported" (the user agent has no Safari token; claude/browser-engine is fixing it, so this branch leaves it alone).
- The tab needed its own Google sign-in: the cookies are separate from Chrome's, and accounts.google.com had to be allowed as well.
- The editor is too wide for the pane, so pages were cut off.
- `duo2 browser click` on Docs' "Hide tabs & outlines" reported success but changed nothing, because Docs ignores synthetic clicks.
- The `/mobilebasic` view rendered cleanly and was what made visual checking possible.
