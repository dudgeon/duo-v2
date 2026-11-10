# Native PDF viewing: viewer, the agent reading the whole PDF, portable comments

Research for ENH-339 (Geoff, 2026-11-10). Records: F-644 (what the spikes found), Q-490 to Q-493 (the four decisions). Nothing here is built into the app. The spikes are in `docs/research/pdf-viewing-spikes/`, and each one runs with `swift <file>` or `node`.

**The four decisions, recommendation first:**

| # | Decision | Recommendation | Main alternative |
|---|---|---|---|
| Q-490 | What draws the PDF | **PDFKit's `PDFView`**, native, in a new PDF viewer that takes the place of Quick Look in the editor area | PDF.js in a WKWebView, like the Word and PowerPoint viewers |
| Q-491 | Split view | **A PDF can be the reference side of a split, beside a text document** (read the paper, write the notes). It's a change to the split rules, which today take only text files. | Leave split view text-only; a PDF opens as a tab |
| Q-492 | What a Claude session gets | **`duo2 doc read` returns the whole PDF as text with page markers, and names the pages that need looking at as images.** The session reads those with Read `pages`. | The path alone (Read takes the whole PDF as images, about 6× the tokens) |
| Q-493 | Where comments live and how they're written | **In the PDF, as standard annotations** (sticky notes and highlights, replies by `/IRT`, Resolve as a `/State` reply), **appended by Duo's own incremental-update writer**. PDFKit only draws them, never saves the file. | An XFDF sidecar beside the PDF; or PDFKit's own save, which rewrites the whole file |

The look (the PDF viewer's bar, the comment margin over a page, the Resolve control) isn't drawn anywhere. Each needs a design round on a canvas before it's built (DL-26). This document doesn't design them.

---

## 1. Where Duo is today

- **A PDF opens in Quick Look.** `ProjectPanes.swift:906` sends any binary file to `BinaryFileView`: a `QLPreviewView` under the "PDF · read only" strip, with Open With ⌄ and Show in Finder (`BinaryFileView.swift:41-61`, Q-52, DL-132).
  - Quick Look draws well, but it can't tell Duo which page is showing or what's selected (F-102). So there's no Send Selection, no `duo2` page verbs and no comments.
- **PDFKit is already linked.** Search indexes a PDF's text one page per paragraph (`SearchService.swift:4,9-12`).
- **The other document viewers are web views.** The Word viewer (`DocxViewer`, `duo-docx:` scheme) and the PowerPoint viewer (`DeckViewer`, `duo-deck:`) each vendor a JS renderer into a WKWebView. They're read-only and pinned to the light appearance, so documents keep their author's colours (DL-224). They plug into `visiblePage: PageHost`, which gives Send Selection, the picker and screenshots.
  - The deck bar is the nearest pattern for a PDF: ‹ › Slide n of N, Select Shape, Open With (DL-125).
- **Split view takes two text files.** `openSplitView` refuses any binary file and any Word file (`AppModel+SplitDocs.swift:38`). `.pptx` counts as binary (`FileKind.binaryTypes` has `.presentation`), so a deck can't be in a split today either.
  - Geoff's request names "the editor and the split view" as where Markdown or PowerPoint open. For PowerPoint, only the first is true today. Q-491 is the decision this raises.
- **Comments today.**
  - **Markdown:** review threads are CriticMarkup in the file (`ReviewMarkup.swift`: add, reply, close, reopen, delete, resolve). `@claude` comments go to a session as quoted data, and their delivery state lives in Duo, never in the file (DL-236, `AppModel+ReviewSend.swift`).
  - **Word:** comments are shown read-only from `comments.xml` (Q-266).
  - **PowerPoint:** whether `@claude` comments work in the Word and PowerPoint viewers is being tested by the claude-comments-office-viewers task (F-642, not reported yet). Q-493's mapping is written to fit DL-236 either way.

## 2. The viewer (Q-490)

### Options

**A. PDFKit `PDFView` (recommended)**
- Apple's renderer, the one Preview uses.
- Free from Apple:
  - continuous scroll and the page display modes
  - zoom (`autoScales`, `scaleFactor`, pinch)
  - text selection and copy
  - find (`PDFDocument.findString`, `beginFindString` and the find bar)
  - thumbnails (`PDFThumbnailView`)
  - links and outlines (`PDFOutline`)
  - annotations drawn from their appearance streams
- It's a system framework, already linked, so it's fine under DL-30 (the toolchain rule, not a framework rule).
- Speed, measured on the 120-page fixture (F-644): opening took 0.06 s and extracting all its text 0.07 s. One page renders at 1000 px in 15 ms.
- Costs and risks:
  - `PDFView` is an `NSView`, not a web view. It doesn't fit `PageHost` (Send Selection, the picker, screenshots), so it needs a native conformer. That is roughly the work of one more `PageHost` kind.
  - Reported PDFKit troubles (forums, not tested here): slow zooming with many annotations, memory held per page in long loops, and a macOS 27 beta regression in writing link destinations. The viewer only reads, so the write bugs don't touch it (see §4).
  - Dark mode: `PDFView` has no dark page rendering. DL-224 already says documents keep their author's colours, so the page stays white on a dark chrome, as Word and decks do. An "invert pages" option would be a later ENH, done the way Skim does it (a Core Image filter on the view's layer).

**B. PDF.js in a WKWebView**
- Mozilla's renderer, Apache 2.0. It would load through a `duo-pdf:` scheme, like the Word and PowerPoint viewers, so `PageHost`, the picker and screenshots come almost free.
- `pdfjs-dist` 4.10.38 is 37 MB installed, with 13 MB in `build/` (measured).
- It has a text layer for selection and search, an annotation editor (FreeText, Ink, Highlight, Stamp; Firefox 145 added text comments), and forced page colours for dark mode (`forcePageColors`).
- Its save is an incremental update (tested, F-644), which matters for §4.
- Costs and risks:
  - A second PDF engine beside the PDFKit that search already uses.
  - Canvas memory in WKWebView on long documents (reported, not measured).
  - It doesn't show review state: a hidden Acrobat-style state reply isn't returned by `getAnnotations` (tested).
  - Its comment UI is its own, not Duo's margin.

**C. Keep Quick Look and add a bar**
- Cheapest, but it stays blind to the page and the selection (F-102). It can't host comments.

**D. Commercial SDKs (Nutrient/PSPDFKit, Apryse) and MuPDF**
- Nutrient and Apryse have everything, including replies, review state, XFDF and incremental save, but they're paid and closed. Duo is open source.
- MuPDF is AGPL, which doesn't fit.

### Recommendation

**A, PDFKit.** It draws the way Preview does, it's already linked, and it adds nothing to the bundle. It's fast on long files. The parts it lacks for comments (reading and writing threads) are small and native (§4).

The web-view route (B) buys the `PageHost` plumbing, but at the cost of a second engine and 13 MB. It wouldn't solve review state either.

**Effort:** about 3 to 4 days after the design round.
- A `PdfViewer` surface before `ProjectPanes.swift:906`
- A bar like the deck's (page n of N, zoom, find, Open With)
- Send Selection with page and quote, and a `PageHost` conformer
- `duo2 pdf` verbs (DL-71): `pdf page`, `pdf go`, `pdf find`, `pdf selection`, `pdf screenshot`
- DuoChecks, and Quick Look as the fallback when PDFKit can't open a file

## 3. Split view (Q-491)

Split view is a source and its preview, or two text documents side by side. No viewer takes part today. The useful split for a PDF is **a PDF on one side and the Markdown you're writing about it on the other.** Examples: notes on a paper, a review of a contract, a spec drafted from a reference.

**Recommendation:** let a PDF be one side of a split beside a text document. It's view-only, and the text side keeps the editor. The same rule would then admit decks and Word documents later, and that's worth deciding together.

**Effort:** about 1 day of policy and plumbing (`openSplitView`, `splitCandidates`, `canOpenInSplitView`, a `SplitBody` side that hosts the viewer), once Q-490 is built. How a split with a viewer side looks isn't drawn.

**Alternative:** leave split view text-only and open the PDF as its own tab. The window's two panes already let you put a session beside it.

## 4. The agent reads the whole PDF (Q-492)

### What was measured (F-644)

The fixture is 120 pages of invented text (`make-fixture.swift`). Ten pages hold a bar chart whose values exist only as bar heights. Page 33 has two columns, page 57 a table, and page 88 is an image-only "scan" with no text layer.

| Route | Time | Size | What's lost |
|---|---|---|---|
| Claude Code's Read on the path, no `pages` (Claude Code 2.1.316) | one call | every page as text plus a page image. Anthropic's PDF docs put this at about 1,500 to 3,000 tokens a page, so **about 180k to 360k tokens** for 120 pages. A 1M-token context fits it, a 200k one may not. | nothing: the images show the charts and the scan |
| PDFKit `PDFPage.string`, all pages, with `--- page N ---` markers (`extract.swift`) | 0.07 s | 133,894 characters, **about 33k tokens** (chars/4) | the chart values (12 charts) and the scanned page's words. Columns and table rows came through in order. |
| One page rendered to PNG at 1000 px (`extract.swift`) | 15 ms | about 70 KB, about 1,600 tokens as an image | nothing on that page |

**Read's limits, observed.** The brief's "max 20 pages per request" is a limit on the `pages` parameter. With no `pages`, this build read all 120 pages of a 300 KB file in one call; a larger file may be refused, which isn't tested. Page-range reads use poppler's `pdftoppm`, which isn't installed on this Mac. That route is reported to fail without it (claudeissues 84860) and wasn't tested here. The API's own limits are 32 MB and 100 pages per request (600 with a 1M context).

### Options

- **A. The path only.** The session uses Read itself. It's the most faithful, but it costs about 6× the tokens of text, can overflow a 200k context, and depends on Read's limits.
- **B. Text with page markers, plus the pages to look at (recommended).** `duo2 doc read <file.pdf>` returns PDFKit's text, one `--- page N ---` block a page. It ends with a list of the pages that need eyes:
  - a page with no text layer (a scan)
  - a page whose images or vector drawings cover much of it while it carries little text (figures, charts)

  The session reads only those with Read `pages` (or `duo2 pdf screenshot <page>`).
  - On the fixture that's 13 pages: about 33k tokens of text plus 13 × about 1,600 tokens of images, so about 54k in all, against about 180k to 360k.
  - The text is cut from the same PDFKit Duo shows, so page numbers match the viewer.
  - Effort about 1 day, plus a line in the session guidance.
- **C. Convert to Markdown** (docling, MarkItDown, PyMuPDF4LLM). Better headings and tables, but docling brings PyTorch, PyMuPDF is AGPL and MarkItDown has no layout. It's heavy for what B gives. It could be an ENH for structured documents.
- **D. A cached sidecar** (`<name>.pdf.txt` beside the file). It's quick to reread, but it's a file nobody asked for in the user's folder. B's output can be cached in Duo's support folder instead.

**Recommendation: B**, with the path in the payload too, so the session can always fall back to A.

The same text feeds Send Selection: "From paper.pdf, page 12:" then the quote, the shape `SendFormat.documentSelection` already has.

## 5. Portable comments (Q-493)

### The standard (ISO 32000-1 §12.5.6, -2)

- **A comment is a markup annotation.** Each type has standard keys:
  - **Text (sticky note):** anchored at a point.
  - **Highlight, Underline, StrikeOut, Squiggly:** anchored to text by `/QuadPoints`.
  - **FreeText:** typed on the page.
  - **Ink:** drawn.
  - **Shared markup keys:** `/T` (author, a plain string), `/Contents`, `/M` (modified), `/CreationDate`, `/NM` (a unique name), `/Subj`, `/RC` (rich text) and `/Popup` (the note's pop-up window).
- **A reply** is another Text annotation with `/IRT` (in reply to, a reference to the parent) and `/RT /R`. Viewers should show replies threaded, not one by one.
- **Review state** (Accepted, Rejected, Cancelled, Completed, None) is a Text annotation too: `/IRT` to the comment, with `/StateModel (Review)` and `/State (Completed)`. Acrobat writes it hidden (`/F 32`). The state belongs to the user named in its `/T`, so "resolved" is per person; the latest state reply wins.
- **Incremental update** (§7.5.6): changes are appended after the original bytes with a new xref and trailer pointing back (`/Prev`). A signature covers a byte range, so it stays valid.
  - A certification signature with DocMDP `P=3` allows adding, changing and deleting annotations.
  - A full rewrite breaks any signature.
- **XFDF** (ISO 19444-1) is the same comments as an XML sidecar. Acrobat imports and exports it, and so do Nutrient and Apryse.

Sources are linked in §8.

### What the spikes showed (F-644)

| Question | Result | Spike |
|---|---|---|
| Can PDFKit write a sticky note, a highlight, author, modified date and NM? | **Yes**, and they read back | `annotate.swift` |
| Can PDFKit write `/IRT` (a reply)? | **No.** `setValue(_:forAnnotationKey: "/IRT")` with an annotation fails, and nothing is written. The highlight's `/Popup` wasn't written either. | `annotate.swift` |
| Can PDFKit write `/State`, `/StateModel`, `/RT`? | **Yes.** They are written as the spec wants (text strings and the name `/R`), but **PDFKit's API won't read them back**. `annotationKeyValues` hides `/IRT`, `/RT`, `/State`, `/StateModel` and `/CreationDate`. | `annotate.swift`, `readback.swift` |
| Is PDFKit's save incremental? | **No.** It rewrites the whole file (300,382 B to 317,047 B, original bytes not a prefix). Apple's forums report signatures lost on save and no incremental option. | `annotate.swift` |
| If a PDF already holds a thread (as Acrobat would write it) and PDFKit saves, is the thread kept? | **Yes.** `/IRT` is renumbered to the right parent, and `/State`, `/RT` and `/CreationDate` are kept. But the whole file is rewritten. | `readback.swift` |
| Can Duo read threads natively? | **Yes, with Core Graphics' `CGPDF`.** The page's `/Annots` dictionaries expose every key. A dictionary reached through `/IRT` is the same `CGPDFDictionaryRef` as the one in `/Annots`, so pointer identity rebuilds the tree. This works before and after a PDFKit save. | `cgpdf-threads.swift` |
| Can Duo append a reply and a state change without touching the original bytes? | **Yes.** 756 bytes appended (two annotations, the page's `/Annots` array, an xref section, a trailer with `/Prev`), and the original is an exact prefix. PDFKit, CGPDF and PDF.js all open the result. | `append-reply.swift` |
| What does PDF.js see? | The reply with `inReplyTo` and `replyType: "R"`. **The hidden state replies aren't returned**, so no review state. Its `saveDocument()` **is incremental** (original bytes a prefix, FreeText appended). | `pdfjs-check.mjs` |
| Does macOS draw the comments? | Quick Look's renderer (the one Preview uses) draws the highlight and the note icon, rendered headless with `qlmanage -t`. | — |

**Not tested (needs a window or an app this Mac lacks):**
- Whether Preview's sidebar shows the `/IRT` replies as a thread and the review state.
- Whether Acrobat Reader shows the thread and the Completed/Accepted status (it isn't installed).
- Chrome's PDF viewer.
- Google Drive's preview (Drive comments are Drive's own and aren't stored in the PDF; unconfirmed).

The threaded file can be opened by hand to check: `threaded.pdf` from `append-reply.swift` (see §7).

### Options

- **A. In the PDF, appended by Duo (recommended).**
  - Comments are standard annotations.
  - Duo reads them with CGPDF, draws them with PDFView, and writes each change as an incremental update with its own small writer. PDFKit never saves the user's file.
  - Portable to Acrobat (threads and status), PDF.js/Firefox (threads) and Preview (notes and highlights at least).
  - Signatures and the original bytes are never disturbed.
  - Costs:
    - A real writer must also handle xref streams, compressed object streams, an inline `/Annots` array, and encrypted files (refuse those).
    - Each edit grows the file a little.
    - Deleting a comment is an update that drops it from `/Annots`; the old bytes stay in the file's history, as they do for Acrobat.
  - Effort: about 3 to 5 days for the reader and writer, with checks over a corpus of real-world PDFs. About 3 to 4 more for the margin UI after its design round.
- **B. An XFDF sidecar** (`<name>.xfdf` beside the PDF). The PDF is never touched, and Acrobat can import it. But comments are lost when the PDF is sent alone, and no other viewer reads it unasked. That fails "portable in the PDF standard" as Geoff put it. It's good as an **export** (`duo2 pdf comments --xfdf`), an ENH.
- **C. PDFKit's own save.** The least code. But it rewrites the whole file, breaks signatures, can't write replies at all (`/IRT`), and has open regressions in macOS 27's writer.
- **D. PDF.js's save** (incremental, tested). Only if Q-490 picks PDF.js. It still has no review state, which Duo would add itself.
- **E. Duo-only comments** (Duo's state, not in the file, like the send status). Not portable. Rejected by the request.

### How Duo's comment actions map to the standard (option A)

| Duo action (DL-236, `duo2 comment …`) | In the PDF |
|---|---|
| View | CGPDF reads every markup annotation. Threads are rebuilt by `/IRT`. Status is the latest `/State` reply by `/M`. Drawn in Duo's margin, with the annotation's own appearance on the page. |
| Add (on a selection) | A Highlight with `/QuadPoints` over the selection and `/Contents`. On a spot: a Text note. Each gets `/T` (your name, DL-236 11), `/M`, `/CreationDate` and `/NM` (Duo's comment id, e.g. `c1`, so `duo2 comment reply c1` works). |
| Edit | The same object number rewritten in a new incremental section, with a new `/M`. |
| Reply | A Text annotation with `/IRT` to the root, `/RT /R`, the same `/Rect`, `/T` and `/NM c1.2`. |
| Resolve (Close and Keep) | A hidden Text annotation with `/IRT`, `/StateModel (Review)`, `/State (Completed)`, `/T` your name. Acrobat shows it as Completed. |
| Reopen | Another state reply, `/State (None)`. |
| Delete | An update that drops the thread's objects from the page's `/Annots`. |
| @claude to a session | Unchanged from DL-236. `@claude` in `/Contents` routes it, and the send state lives in Duo. Claude replies with `duo2 comment reply`, written as a reply with `/T (Claude)`. A reviewer named Claude in another app counts as `@claude`, as Q-266 does for Word. |
| Accept or reject (a suggestion) | Not mapped. PDFs carry no tracked changes. A StrikeOut or Caret annotation can *propose* a change, but can't apply one, so Duo shows it as a comment. |

Consistency: Markdown keeps comments in its own syntax inside the file (CriticMarkup). Word's are shown from `comments.xml` and never written. A PDF's would be read and written in the PDF's own standard form. In all three the comment lives in the document, and only Duo's delivery state lives outside it.

## 6. Risks

- **Real-world PDFs are messier than the fixture.** Expect xref streams, object streams, broken xref tables (which PDFKit repairs silently and a byte appender can't), encryption, and linearised files.
  - Mitigation: the writer refuses what it can't append to safely and says so in the viewer. A corpus check in DuoChecks.
- **Two readers of one file.** PDFView shows the annotations from its own parse, while Duo's margin reads CGPDF. After an append, the view must reload.
- **Per-user review state.** Acrobat's status is per author. Duo's "closed" is per thread (DL-236 4). Mapping "latest state reply wins" is a choice; it's noted in the Q row.
- **Preview edits the same file.** It may later rewrite it in full. The thread survives (tested for PDFKit's save, which Preview shares by inference), but signatures don't.
- **Read's PDF behaviour can change between Claude Code releases.** That is why B returns text itself rather than relying on Read.

## 7. Reproducing the spikes

```
cd docs/research/pdf-viewing-spikes
swift make-fixture.swift /tmp/f.pdf               # 120 pages; chart values to stderr
swift extract.swift /tmp/f.pdf /tmp/f.txt         # timings, size, what's lost
swift annotate.swift /tmp/f.pdf /tmp/a.pdf        # PDFKit comments; /IRT fails; full rewrite
swift append-reply.swift /tmp/a.pdf /tmp/t.pdf 4 395   # incremental reply + Accepted state
swift cgpdf-threads.swift /tmp/t.pdf              # threads rebuilt natively
swift readback.swift /tmp/t.pdf /tmp/r.pdf        # what PDFKit hides; resave keeps threads
node pdfjs-check.mjs <pdfjs-dist dir> /tmp/t.pdf /tmp/j.pdf   # pdfjs-dist 4.10.38
```

`append-reply.swift`'s `4 395` are the object numbers of page 1's `/Annots` array and the first note in PDFKit's output for this fixture. A real writer finds them itself.

## 8. Sources

- ISO 32000-2 (PDF 2.0) at no cost, from the PDF Association: https://pdfa.org/announcing-no-cost-access-to-iso-32000-2-pdf-2-0/
- ISO 32000-1 and Adobe PDF Reference 1.7: https://pdfa.org/resource/iso-32000-1-pdf-1-7/
- IRT and RT (spec text copy): https://verypdf.com/document/pdf-format-reference/txtidx0617.htm
- State and StateModel: https://www.verypdf.com/document/pdf-format-reference/txtidx0618.htm, https://www.verypdf.com/document/pdf-format-reference/txtidx0619.htm
- DocMDP P=3 allows annotations: https://community.adobe.com/t/acrobat-discussions/allow-certain-changes-after-digital-signing/m-p/14586632
- A non-incremental save invalidates signatures: https://community.pdftron.com/t/why-does-saving-invalidate-an-existing-digital-signature/3131
- PDFKit:
  - No incremental save: https://developer.apple.com/forums/thread/761229
  - Signatures dropped: https://developer.apple.com/forums/thread/759627
  - macOS 27 beta write regression: https://developer.apple.com/forums/thread/844399
  - Zoom slow with many annotations: https://developer.apple.com/forums/thread/802728
  - Dark pages: https://developer.apple.com/forums/thread/120756
- Acrobat comment import/export (XFDF/FDF): https://helpx.adobe.com/acrobat/current/importing-exporting-comments.html
- Nutrient XFDF, replies, incremental save:
  - https://www.nutrient.io/guides/react-native/annotations/import-and-export/xfdf/
  - https://www.nutrient.io/guides/ios/annotations/replies
  - https://www.nutrient.io/guides/web/annotations/save/overview.md
- Apryse annotation state: https://docs.apryse.com/web/guides/annotation/annotation-state
- PDF.js:
  - Viewer options (forcePageColors, enableComment): https://raw.githubusercontent.com/mozilla/pdf.js/master/web/app_options.js
  - Firefox 145 PDF comments: https://www.firefox.com/firefox/145.0/releasenotes/
- Chrome PDF annotate mode: https://windowsreport.com/google-chrome-will-soon-let-you-annotate-pdfs-with-ink-signatures/
- Claude API PDF support: https://platform.claude.com/docs/en/build-with-claude/pdf-support.md
- Claude Code Read `pages` (v2.1.30): https://newreleases.io/project/github/anthropics/claude-code/release/v2.1.30
- Read's `pdftoppm` dependency: https://claudeissues.com/issue/84860-read-tool-pages-reroutes-pdf-reading-through-pdftoppm-hard-fails-without-poppler
- MuPDF licence: https://mupdf.readthedocs.io/en/1.27.0/license.html
- PDF-to-Markdown comparison (vendor-written, indicative): https://yage.ai/share/markitdown-survey-en-20260412.html
