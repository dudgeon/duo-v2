# Duo Decks: research on comments

Research for `comments.md` (Q-394 to Q-397). Q-394 is already decided (DL-284: a deck's comments are Review in Markdown's CriticMarkup, an element comment on its own line at the end of its slot, a slide comment under the slide marker). This page is the evidence for what's still open: Q-397 (comments in the export) and, for Q-395, how other tools draw comments on slides.

Sources are listed per section. **[primary]** is a spec, the vendor's own help, or a test run here. **[secondary]** is a third-party page or forum. **[unverified]** is from general product knowledge, with no source found in this round.

Summary:
- PowerPoint has **two comment formats**, and a file holds one or the other, never both. **Legacy** comments are slide-level points with flat text; replies are an extension. **Modern** comments are threads anchored to a slide, a shape or a text range, with GUID authors, replies and a resolved status.
- **LibreOffice 26.8.1 (tested here):** it imports legacy comments as annotations at the right author, date and place, but flattens a reply into a second comment. It **ignores modern comments silently**: they're not drawn, not in the ODP, and gone from its own pptx export. Its pptx export writes legacy comments.
- **Google Slides:** no Google help page says what happens to pptx comments on import or export, and third-party sources disagree. The lead's test with the two files below settles it.
- **Keynote:** no source found either way. A local test needs Keynote on screen, which needs Geoff's OK.
- **For Duo:** stripping comments stays the v1 answer (E1). If they're ever exported, **legacy** comments are the portable choice (LibreOffice reads them, and they're the older, simpler format any importer is most likely to handle). **Modern** comments are the only ones that anchor to the placeholder and carry replies and resolution, but only Microsoft 365 PowerPoint reads them.

## 1. How PowerPoint stores comments

### 1.1 Legacy ("classic") comments

- **Parts:** `ppt/commentAuthors.xml`, one per presentation, and `ppt/comments/commentN.xml`, one per slide that has comments.
- **Relationships:**
  - `presentation.xml.rels` → `commentAuthors.xml`, type `http://schemas.openxmlformats.org/officeDocument/2006/relationships/commentAuthors`;
  - `slideN.xml.rels` → `../comments/commentN.xml`, type `http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments`.
- **Content types:**
  - `application/vnd.openxmlformats-officedocument.presentationml.commentAuthors+xml`;
  - `application/vnd.openxmlformats-officedocument.presentationml.comments+xml`.
- **Anchor:** none. A comment belongs to its slide and has a point, `p:pos`, which is the upper-left corner of its marker. The spec gives no unit in the parts we read. PHPPresentation's writer uses 1/8 pt (576 per inch) [secondary], and LibreOffice's import matches that: it put `x="2519"` at 11.108 cm, which is 4.37 in × 576 [primary, tested].
- **Authors:** integer `id`, `name`, `initials`, `lastIdx` (the highest comment index used by that author) and `clrIdx`. A comment's identity is the pair (`authorId`, `idx`).
- **Text:** plain text in `p:text`, with no formatting.
- **Replies:** a comment with a `p15:threadingInfo` extension (PowerPoint 2013+) naming its parent by `authorId` and `idx`. Readers that don't know the extension show the reply as a separate comment.
- **Resolved:** not in the format.

Minimal XML (from `dd-comment-legacy.pptx`):

```xml
<!-- ppt/commentAuthors.xml -->
<p:cmAuthorLst xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cmAuthor id="0" name="geoff" initials="G" lastIdx="2" clrIdx="0"/>
  <p:cmAuthor id="1" name="sam" initials="S" lastIdx="1" clrIdx="1"/>
</p:cmAuthorLst>

<!-- ppt/comments/comment1.xml -->
<p:cmLst xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cm authorId="0" dt="2026-10-31T10:00:00.000" idx="1">
    <p:pos x="2600" y="1100"/>
    <p:text>Is 86% the right headline, or the 412 rows?</p:text>
  </p:cm>
  <p:cm authorId="1" dt="2026-10-31T10:05:00.000" idx="1">
    <p:pos x="2700" y="1200"/>
    <p:text>Keep 86%; move 412 rows to context.</p:text>
    <p:extLst><p:ext uri="{C676402C-5697-4E1C-873F-D02D1690AC5C}">
      <p15:threadingInfo xmlns:p15="http://schemas.microsoft.com/office/powerpoint/2012/main" timeZoneBias="0">
        <p15:parentCm authorId="0" idx="1"/>
      </p15:threadingInfo>
    </p:ext></p:extLst>
  </p:cm>
</p:cmLst>
```

### 1.2 Modern (threaded) comments

- **Parts:**
  - `ppt/authors.xml`, one per presentation;
  - `ppt/comments/modernComment_<sldId hex>_<slide creationId hex>.xml`, one per slide. PowerPoint uses this name pattern; the name isn't normative [unverified]. The test file uses `modernComment_102_BB40E64D.xml`.
- **Relationships:**
  - `presentation.xml.rels` → `authors.xml`, type `http://schemas.microsoft.com/office/2018/10/relationships/authors`;
  - `slideN.xml.rels` → the comment part, type `http://schemas.microsoft.com/office/2018/10/relationships/comments`.
  - The slide also names that relationship in its own `p:extLst`: `<p:ext uri="{6950BFC3-D8DA-4A85-94F7-54DA5524770B}"><p188:commentRel r:id="…"/></p:ext>` (Microsoft's sample adds it with the first comment).
- **Content types:** `application/vnd.ms-powerpoint.authors+xml`, `application/vnd.ms-powerpoint.comments+xml`. Early files used `…threadedComments+xml`.
- **Namespaces:**
  - `p188` = `http://schemas.microsoft.com/office/powerpoint/2018/8/main`;
  - `pc` = `http://schemas.microsoft.com/office/powerpoint/2013/main/command`;
  - `ac` = `http://schemas.microsoft.com/office/drawing/2013/main/command`.
- **Anchor:** exactly one of these (`EG_CommentAnchor`):
  - `pc:sldMkLst`, the slide: `pc:docMk` then `pc:sldMk cId sldId`;
  - `ac:deMkLst`, a drawing element: the slide monikers, then `ac:spMk id creationId` for a shape (or `picMk`, `graphicFrameMk`, `grpSpMk`, `cxnSpMk`, `inkMk`);
  - `ac:txMkLst`, a text range: the element monikers, then `ac:txMk` with a character position and length;
  - `unknownAnchor`.
  - `sldMk cId` is the slide's `p14:creationId`, and `spMk creationId` is the shape's `a16:creationId` GUID. So the writer must give the slide and the placeholder creation ids. Duo can derive them deterministically from the deck and slot names.
- **`pos`:** optional, an `a:CT_Point2D` relative to the top-left of the anchored object.
- **Child order matters:** anchor, `pos`, `replyLst`, then `txBody`, then `extLst`. A python-pptx fork found that PowerPoint silently drops replies when `replyLst` comes after `txBody`, and drops the comment when `txBody` lacks `a:bodyPr` [secondary].
- **Attributes:** `id` (GUID), `authorId` (GUID), `created` (dateTime), and `status` = `active` (default) | `resolved` | `closed`. Also task fields: `startDate`, `dueDate`, `assignedTo`, `complete`, `title`.
- **Replies:** `p188:replyLst/p188:reply`, each with the same id, author, created and status attributes and its own `txBody`.
- **Authors:** `p188:author` with `id` (GUID), `name`, `initials`, `userId` and `providerId`. `userId` and `providerId` are both required; PowerPoint writes `providerId="AD"` for Microsoft accounts, and `None` is common in files from other tools [unverified].
- **Text:** a DrawingML text body.

Minimal XML (from `dd-comment-modern.pptx`; GUIDs shortened):

```xml
<!-- ppt/authors.xml -->
<p188:authorLst xmlns:p188="http://schemas.microsoft.com/office/powerpoint/2018/8/main">
  <p188:author id="{6B1F…}" name="geoff" initials="G" userId="geoff" providerId="None"/>
  <p188:author id="{7C2A…}" name="sam" initials="S" userId="sam" providerId="None"/>
</p188:authorLst>

<!-- ppt/comments/modernComment_102_BB40E64D.xml -->
<p188:cmLst xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
            xmlns:p188="http://schemas.microsoft.com/office/powerpoint/2018/8/main">
  <p188:cm id="{A1B2…}" authorId="{6B1F…}" created="2026-10-31T10:00:00.000">
    <ac:deMkLst xmlns:ac="http://schemas.microsoft.com/office/drawing/2013/main/command">
      <pc:docMk xmlns:pc="http://schemas.microsoft.com/office/powerpoint/2013/main/command"/>
      <pc:sldMk xmlns:pc="http://schemas.microsoft.com/office/powerpoint/2013/main/command" cId="3141592653" sldId="258"/>
      <ac:spMk id="3" creationId="{4E9A1C2B-…}"/>
    </ac:deMkLst>
    <p188:pos x="228600" y="114300"/>
    <p188:replyLst>
      <p188:reply id="{B2C3…}" authorId="{7C2A…}" created="2026-10-31T10:05:00.000">
        <p188:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>Keep 86%; move 412 rows to context.</a:t></a:r></a:p></p188:txBody>
      </p188:reply>
    </p188:replyLst>
    <p188:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>Is 86% the right headline, or the 412 rows?</a:t></a:r></a:p></p188:txBody>
  </p188:cm>
</p188:cmLst>
```

Plus on the slide: `<a16:creationId id="{4E9A1C2B-…}"/>` in the value placeholder's `p:cNvPr/a:extLst` (uri `{FF2B5EF4-FFF2-40B4-BE49-F238E27FC236}`), and in `p:sld/p:extLst` both `p14:creationId val="3141592653"` (uri `{BB962C8B-B14F-4D97-AF65-F5344CB8AC3E}`) and `p188:commentRel r:id="rId2"`.

### 1.3 The two side by side

| | Legacy | Modern |
|---|---|---|
| Anchor | The slide, plus a marker point | The slide, a shape, or a text range; marker offset from the object |
| Moves with the object | No | Yes ("if you move the object, the comment goes with it") |
| Threads | `p15` extension, parent by (author, idx) | `replyLst` inside the comment |
| Resolved | No | `status="resolved"` (also `closed`) |
| Authors | Integer ids, name and initials | GUID ids, name, initials, `userId`, `providerId` |
| Read by | PowerPoint (all versions), LibreOffice; Google and Keynote untested | Microsoft 365 PowerPoint (Windows, Mac, web, mobile). PowerPoint 2016 and 2019 can't read them. LibreOffice ignores them |
| In one file | One kind only: "PowerPoint files can only show either modern comments or classic comments, not both" | |

**Sources:**
- [primary] MS-PPTX: [CT_Comment](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-pptx/161bc2c9-98fc-46b7-852b-ba7ee77e2e54), [ST_CommentStatus](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-pptx/bd806e3a-96cf-43aa-9618-81b317c34c61), [the full 2018/8/main schema](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-pptx/af0dc8d7-ee58-435b-80fb-72f2b351b689) (authors, replies, anchors, `commentRel`), [threadingInfo](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-pptx/c9f006dd-b166-4699-a3e6-074ccbe441ca).
- [primary] MS-ODRAWXML: [CT_DrawingElementMonikerList](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-odrawxml/145d263b-da8a-4cad-b076-1e51a9d149bf), [CT_ShapeMoniker](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-odrawxml/496f12c8-6363-42cb-b75c-90b7c2d9c37f), [CT_TextCharRangeMonikerList](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-odrawxml/7ac2b0dc-426e-4c42-a3f1-7be68542dbbe), and [the slide-base moniker list](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-odrawxml/84f185a0-60cc-482c-a3bc-0fe8f77e1ba3).
- [primary] Open XML SDK, [Add a comment to a slide](https://learn.microsoft.com/en-us/office/open-xml/presentation/how-to-add-a-comment-to-a-slide-in-a-presentation): modern comments, the authors part, the slide extension `{6950BFC3-…}`. Its [archived classic sample](https://github.com/OfficeDev/open-xml-docs/blob/7002d692ab4abc629d617ef6a0214fc2bf2910c8/docs/how-to-add-a-comment-to-a-slide-in-a-presentation.md) covers legacy comments.
- [primary] Microsoft Support, [Modern comments in PowerPoint](https://support.microsoft.com/en-us/office/modern-comments-in-powerpoint-c0aa37bb-82cb-414c-872d-178946ff60ec).
- [secondary] [python-pptx fork PR 55](https://github.com/MHoroszowski/python-pptx/pull/55): content and relationship types, child order. [PHPPresentation PptComments.php](https://codeclimate.com/github/PHPOffice/PHPPresentation/src/PhpPresentation/Writer/PowerPoint2007/PptComments.php/source): legacy `pos` in 1/8 pt.

## 2. What other apps do with pptx comments

### 2.1 LibreOffice Impress 26.8.1 (tested here)

The two test files were converted headless (pptx → pdf, → odp, → pptx), and the ODP and pptx results were read with `inspect.py`. All conversions exited 0.

| | Legacy file | Modern file |
|---|---|---|
| Import | 2 `officeooo:annotation`s on slide 3, with the right creator, initials, date, text and position | **0 annotations.** The comment and its reply are ignored, with no warning |
| Reply | Becomes a second, separate annotation; the `p15` thread link is lost | n/a |
| LibreOffice's own pptx export | Legacy `commentAuthors.xml` + `comments/comment3.xml`; both comments kept, no `threadingInfo` | **No comment parts at all**: the comments are gone |
| PDF | Converts; comments aren't drawn (the default PDF filter doesn't print them) | Converts |

Release notes for 26.2.6 and 26.8.1 mention crash fixes for "malformed comment data" in PPTX import, all on the legacy `p:cm` path. No release note mentions modern comments [primary, search of whatsnew.libreoffice.org].

### 2.2 Google Slides

- **No Google help page answers it.** [Use Office files](https://support.google.com/docs/answer/6055139) and [Comments](https://support.google.com/docs/answer/65129) don't mention pptx comments on upload, conversion or download [primary, checked].
- **Third-party claims conflict:**
  - PitchWorx says comments "transfer over quite well" on conversion;
  - chatslide.ai says comments are stripped from a Slides → pptx download;
  - slidesai.io says the download includes them [all secondary, unverified].
- **Google's model, for the mapping:** the [Slides API](https://developers.google.com/workspace/slides/api/guides/comments) anchors a comment to "a slide page or a page element (such as a shape or table)", or to a text range, and replies can resolve or reopen. So Google could map a modern comment's `deMkLst` to an element-anchored comment, and a legacy comment to a slide-anchored one. Whether its importer does is what the test shows.
- **Lead's test:** import `dd-comment-legacy.pptx` and `dd-comment-modern.pptx`, both by opening the file (Office mode) and by Save as Google Slides. Note for each file:
  - whether the comments appear;
  - whether the author is "geoff"/"sam" or the importer's account;
  - whether the reply stays threaded;
  - whether the modern one is attached to the 86% box.
  - Then add a comment in Google, download as pptx, and look for `ppt/comments/*`.

### 2.3 Keynote

- Apple's help covers Keynote's own comments, and PDF export "with comments", but not pptx comments on import or export [primary for what it covers: [Add and manage comments](https://support.apple.com/guide/keynote/tan076c382d1/mac), [Export to PowerPoint](https://support.apple.com/guide/keynote/tana0d19882a/mac)].
- No secondary source either way.
- A test opens Keynote on screen, so it needs Geoff's OK. Not run.

**Sources:** the two Google help pages and the Slides API guide above; PitchWorx, [chatslide.ai](https://www.chatslide.ai/guides/how-to-convert-google-slides-to-powerpoint) and [slidesai.io](https://www.slidesai.io/blog/how-to-add-comments-on-google-slides) [secondary]; [LibreOffice what's new 26.8.1](https://whatsnew.libreoffice.org/26.8.1/) and [26.2.6](https://whatsnew.libreoffice.org/26.2.6/); the test run here.

## 3. How slide tools show comments

| Tool | What a comment attaches to | What's drawn on the slide | Where the thread is read | When the element goes or the layout changes |
|---|---|---|---|---|
| **PowerPoint (modern)** | An object or a text range (slide-level by selecting nothing) | A comment bubble at the object; only the selected comment's marker shows unless Show Comments › Advanced Markup is on. Anchored text is highlighted | The Comments pane on the right. The web app dropped margin comments | Moves with the object. On deletion, the thread stays in the pane [unverified]. Resolved threads leave the margin and stay in the pane |
| **PowerPoint (legacy)** | The slide | A small square marker with initials at a point, which can be dragged | The Comments pane | Doesn't follow objects; stays at its point |
| **Google Slides** | Text, images, cells, slides (Help) and page elements (API) | A comment icon beside the anchor when the slide is selected [unverified] | The right-hand panel ("Show all comments") and a card beside the canvas | On deletion the comment keeps its original quote and shows as detached in the panel [unverified] |
| **Keynote** | Text, objects, charts, table cells, slides | A small square by the object, highlighted text, a triangle in a cell's corner. A slide-background comment is an open sticky note that can't be replied to | A popover opened from the marker; the help names no sidebar | Not documented. Deleting the first comment deletes the conversation |
| **Figma / FigJam** | A point, attached to the top-level frame under it ("won't attach to any nested frames… or layers") | An avatar pin | A popover on the canvas, plus a comments sidebar | Moves with its frame. Users report pins left "unattached" when frames are moved, with no way to reattach [secondary] |
| **Canva** | An element, text or page | A badge with the commenter's initials or photo | A popover, plus a comments panel | Not documented |
| **Pitch** | A slide, at a point [unverified] | A pin with the author's avatar [unverified] | A comments panel per slide; resolve per slide [secondary: G2] | Not documented |
| **Gamma** | A card or a block within it [unverified] | A comment count on the block [unverified] | A side panel [unverified] | Not documented |

What it means for Q-395:
- Every tool draws a small mark at the element (an initials badge, a bubble or a square) and reads the thread somewhere else: a pane, a panel or a popover.
- Only Figma and Keynote put the whole thread in a popover at the mark.
- The weak point everywhere is the orphan, a comment whose object has gone. Duo avoids most of it because the comment is text in the slot: it goes wherever the slot's text goes (DL-284).

**Sources:**
- [primary] [PowerPoint modern comments](https://support.microsoft.com/en-us/office/modern-comments-in-powerpoint-c0aa37bb-82cb-414c-872d-178946ff60ec); [Google Docs Editors, comments](https://support.google.com/docs/answer/65129); [Slides API comments](https://developers.google.com/workspace/slides/api/guides/comments); [Keynote comments](https://support.apple.com/guide/keynote/tan076c382d1/mac); Figma, [Change the location of a comment](https://help.figma.com/hc/en-us/articles/360041068574-Change-the-location-of-a-comment) and [Guide to comments](https://help.figma.com/hc/en-us/articles/360039825314-Guide-to-comments-in-Figma).
- [secondary] [Figma forum, reattaching comments](https://forum.figma.com/t/make-it-possible-to-reattach-unattached-comments/4931); [Canva comments help](https://www.canva.com/help/comments/) (quoted from search results; the page refused a direct fetch); [Pitch reviews, G2](https://g2.com/products/pitch-pitch/reviews?page=2).

## 4. The test files

In `/Users/geoff/.claude/jobs/6a39b999/tmp/comments/`, built from `field-trial-review.pptx` by `build.py`, which hand-edits the XML:
- **`dd-comment-legacy.pptx`:** two legacy comments on slide 3 ("Unattended rows"), by geoff then sam. The second is a `p15` reply to the first. The text carries `[#c1 on value]` and `[#c1.1]`, so a reader can tell whether the order and the link survive.
- **`dd-comment-modern.pptx`:** one modern thread on slide 3, anchored by `ac:deMkLst` to the value placeholder (`spMk id="3"`, the "86%" box, `ph idx=13`), with sam's reply in `replyLst`. Status is active.
- **Checks:**
  - both open in python-pptx (9 slides; slide 3 has a `comments` relationship);
  - every XML part parses, and the zip tests clean;
  - LibreOffice converts both to PDF, ODP and pptx without error (results in §2.1, in `lo/`).
- **Not checked:** opening in PowerPoint (needs a visible app). The modern file follows MS-PPTX and Microsoft's SDK sample, but it hasn't been confirmed in PowerPoint itself.
- Also there: `inspect.py` (prints the comment markup of a pptx or odp) and `lo-run.sh` (the conversions).

## 5. Mapping options for Duo

DL-284 has decided where comments live (option A′ below). This section compares the options anyway, as asked, with how each would export (Q-397), how it survives a template change (DL-281), and how it diffs.

### The options in Markdown

**A′. CriticMarkup on its own line at the end of the slot (DL-284).** An element comment, a reply and a slide comment:

```markdown
<!-- slide: kpi -->
{>>@sam 2026-10-31 #c2: Cut this slide if the 412 rows land on slide 2?<<}
# Unattended rows

## value
86%
{>>@geoff 2026-10-31 #c1: Is 86% the right headline, or the 412 rows?<<}
{>>@sam 2026-10-31 #c1.1: Keep 86%; move 412 rows to context.<<}

## context
Up from 61% in the spring trial, over 412 rows on three farms.
```

**A. CriticMarkup inline** (a span, typed in the source; still allowed by DL-284):

```markdown
## context
Up from 61% in the spring trial, over {==412 rows==}{>>@geoff 2026-10-31 #c3: 412 or 410?<<} on three farms.
```

**B. A `> [!comment]` callout per slide** (not chosen):

```markdown
> [!comment]
> @geoff 2026-10-31 #c1 · value: Is 86% the right headline, or the 412 rows?
> @sam 2026-10-31 #c1.1 · value: Keep 86%; move 412 rows to context.
```

**D. Comments inside the notes callout** (a variant, so the slide text stays clean; not proposed):

```markdown
> [!note]
> Pause here.
> {>>@geoff 2026-10-31 #c1: Is 86% the right headline?<<}
```

**E. A frontmatter list** (`comments:` with slide, slot and text; not proposed).

### How they compare

| | Export to pptx | After a template change (DL-281) | Git diff |
|---|---|---|---|
| **A′ own line in slot** | Each thread maps to one comment on that slot's placeholder: modern `deMkLst` → `spMk`, or legacy at the placeholder's top-right. A slide comment maps to `sldMkLst` or a legacy point at the slide's corner | Goes with the slot's text. If the slot carries over, it stays on it. If the text moves to notes, it moves with it, and the export can only anchor it to the slide | Best. Adding a comment is a one-line insertion, and content lines don't change. A reply is the next line |
| **A inline span** | Modern can use `txMkLst` (char offset and length within the placeholder), but Duo would have to count characters after inline Markdown is stripped. Simpler: drop to the placeholder, and quote the span in the text ("On "412 rows": …") | Goes with the text, even through a rename | The content line changes, so the diff shows the sentence as changed. `git diff --word-diff` isolates it |
| **B callout** | Needs the slot name to find the placeholder | **Breaks on rename:** "value" in the callout points nowhere when the new template calls it `figure`. Duo would have to rewrite callouts in the remap | Good: appends inside one block. But a second convention, not read by the margin, routing or verbs |
| **D in notes** | Would be exported as notes text unless stripped. Confuses notes with discussion | Survives, because notes always survive | Fine, but it's in the speaker's script |
| **E frontmatter** | Easy to read | Breaks on rename, like B | Far from the text it's about, and Obsidian shows it as properties |

### Export choices for Q-397

| | What the pptx gets | Who sees it | Cost |
|---|---|---|---|
| **E1. Strip (v1, recommended)** | Nothing. The parser already strips comments for checks and the writer (DL-284) | No one outside Duo and git | None |
| **E2a. Legacy comments** | Open threads only. Root and replies are flat comments, with replies linked by `p15:threadingInfo`. Text is `value: Is 86%…`, and the author is the signature's name. Marker point at the placeholder's top-right, from the layout's geometry (a comment marker, not text placement, so no conflict with "no layout logic") | Every PowerPoint, LibreOffice (reply flattened), and probably Google and Keynote (to test) | Small: two parts, two relationships. Closed threads can't be marked, so they're left out |
| **E2b. Modern comments** | Threads anchored to the placeholder, replies in `replyLst`, `status="resolved"` for closed-and-kept threads | Microsoft 365 PowerPoint only. **Dropped by LibreOffice, including its re-export**; Google untested | More: deterministic GUIDs for authors and comments, plus `a16:creationId` on every commented placeholder and `p14:creationId` on its slide |
| **E3. A choice at export** | E1, or E2a/E2b when ticked | — | E2's cost, plus a setting |

Points that hold whichever is chosen:
- **Attribution:**
  - the signature's `@name` becomes the author's name, with the initials as its first letter;
  - modern comments need a `userId`; Duo would use the same name with `providerId="None"`, never an email;
  - `@claude` exports as "claude".
- **Determinism:**
  - legacy dates come from the signature (no time, so `T00:00:00`);
  - modern GUIDs are derived from the deck path and the comment `#id`, so the bytes stay fixed (the plan's deterministic-export rule).
- **The way back:** if Duo ever reads a pptx review back (Convert to Markdown for decks), legacy comments map back to `#cN` threads by `idx` and `parentCm`. Modern ones map back with their anchor. That's the same shape as Word's Convert to Markdown (DL-236 12, Q-283).
- **Recommendation:** keep E1 for v1. If Google's import keeps legacy comments with their author names, E2a is the cheap, portable later step. E2b only pays off for teams on Microsoft 365, and it costs every LibreOffice user their comments.
