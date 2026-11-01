---
title: Duo Decks study (b): text-first deck formats and pptx libraries
date: 2026-10-31
status: research
---

# Duo Decks study (b): text-first deck formats and pptx libraries

The question: which existing deck format and pptx engine fits Duo Decks? In Duo Decks every slide names a template and fills that template's named slots. The Markdown lives in git and Claude Code edits it. Export to .pptx must keep a corporate template's masters and layouts so the deck imports into Google Slides. The engine has to run inside Duo, with no Python, Node or scripts on the user's Mac.

Short answer: no existing format names a template per slide and fills named slots, though Slidev comes closest (`layout:` per slide, `::slot::` markers). No existing exporter fills arbitrary named layouts of a corporate .pptx either: pandoc fills seven fixed layouts by name and nothing else. Duo should define its own small Markdown convention and write its own exporter, which instantiates the template's real layouts and fills their placeholders. The details are at the end.

## What I ran

Everything ran in the scratch folder `${SCRATCH:-/tmp/duo-decks}/formats/`. The small scripts worth keeping are in `prototypes/formats/`.

| Check | Result |
|---|---|
| pandoc 3.13 (arm64) on a test deck (`pandoc-layouts.sh`) | Each slide's real layout and its `<p:ph>` refs are listed in §Pandoc. |
| **pandoc 3.13 `pandoc.wasm` (official release asset) under Node's WASI** (`wasm-pandoc.mjs`) | A 10-slide pptx came out in **~170 ms**, identical in structure to the native binary. The pptx writer runs with no native binary at all. |
| pandoc with a reference doc that lacks the 7 layout names | It warns and falls back to its own default layouts. The reference doc's own custom layout was **not carried** into the output. |
| marp-cli 4.5.1 `--pptx` and `--pptx-editable` (`marp-pptx.sh`) | Default mode: one full-slide PNG per slide plus notes. Editable mode: absolute-position text boxes, no `<p:ph>`, notes dropped, and it needs LibreOffice. |
| pptxgenjs 4.0.1 master with placeholders (`pgx.js`) | Writes real `<p:ph type="title"/"body">` in its own generated layouts, but copies the xfrm (position) onto every slide shape. It cannot load an existing .pptx/.potx. |
| pptx-automizer 0.9.4 (`automizer.js`), using the pandoc output as a stand-in corporate template | It cloned a "Title and Content" slide twice and set text by shape name ("Title 1", "Content Placeholder 2"). The clones keep `<p:ph>` and their layout relationship. |
| Token count of the same 10-slide deck in 6 encodings (`gen.py`) | See §Token cost. |

## Per-format survey

The Markdown samples show one or two slides. Token estimates are characters/4 for the same 10-slide deck, produced by `gen.py` (§Token cost).

### Marp (Marpit, marp-core, marp-cli)

- **Source.** One Markdown file with `marp: true` frontmatter. Slides are split by `---`. HTML comments carry directives (`<!-- _class: lead -->`, `<!-- paginate: true -->`); any other HTML comment becomes a presenter note.
  ```markdown
  <!-- _class: title -->
  # Q3 Platform Review
  Platform team, October 2026
  <!-- Welcome; set the agenda. -->
  ```
- **Layout model.** There are no layouts. A theme is a CSS file and `_class` adds a CSS class to the slide's `<section>`. Two columns means hand-written HTML `<div>`s plus theme CSS. Positions come from CSS. There are no slots: the content is a free Markdown flow.
- **Diff.** A one-bullet edit is a one-line diff (shown in §Diffs).
- **Tokens.** 1,209 chars ≈ 302 tokens for 10 slides.
- **pptx fidelity.**
  - Default `--pptx`: every slide is a pre-rendered PNG background. Notes are kept and nothing else is editable. Confirmed: `ppt/media/Slide-N-image-1.png`, with no text runs in slide XML.
  - `--pptx-editable` (experimental): renders to PDF, then LibreOffice Impress converts it. The result is text boxes at absolute offsets (`<a:off x="1066680" y="3514680"/>`), no placeholders and no layout linkage. Notes are dropped, and the README warns of "lower slide reproducibility".
  - Neither mode reads a .potx, so corporate masters are never used.
- **Licence / runtime.** MIT. It needs Node ≥ 18, or the standalone binary (46.8 MB macOS tar.gz, Node bundled), plus Chrome, Edge or Firefox. Editable mode also needs LibreOffice.
- **Maturity.** Active: marp-cli 4.5.1 (2026-09-06), Marpit 3.2.3, about 3.9k stars. The VS Code extension is widely used. The Obsidian "Marp Slides" plugin also exports pptx.

Sources: [marp-cli README](https://github.com/marp-team/marp-cli/blob/main/README.md), [npm](https://npmjs.com/package/@marp-team/marp-cli), local test.

### Slidev

- **Source.** Markdown with per-slide YAML frontmatter blocks between `---` lines. `layout:` names a Vue layout, and named slots are filled with `::name::` markers. Notes go in a trailing HTML comment.
  ```markdown
  ---
  layout: two-cols
  ---
  # Before and after
  - Manual session juggling
  ::right::
  - Projects group sessions
  ```
- **Layout model.** This is the closest existing match to Duo Decks. Every slide picks a **named layout** (`cover`, `section`, `two-cols`, `image-right`, …, or a theme's or project's own `layouts/*.vue`). Layouts expose **named slots** (`default`, `::right::`, or custom slots in custom layouts). But a layout is a Vue component with CSS positioning. Arbitrary Markdown, HTML and Vue components are allowed in any slot, and an unlisted layout falls back to `default`. Nothing constrains a slide to a declared slot set.
- **Diff.** One line per bullet.
- **Tokens.** 1,114 chars ≈ 278 tokens.
- **pptx fidelity.**
  - `--format pptx`: one image per slide, text not selectable, notes kept.
  - `--format pptx-editable`: new, merged 2026-08-26 (PR #2722). It measures the DOM in the browser and rebuilds shapes, falling back to an image per element or per slide. Its open bugs: notes dropped (#2755), `counter()` text (#2797), image fitting (#2757).
  - Both produce absolute-position shapes and no `<p:ph>`. No .potx is ever read.
- **Licence / runtime.** MIT. It needs Node, a Vite dev server and `playwright-chromium` for export, which is heavy.
- **Maturity.** Very active: v53.0.0 (2026-09-16), about 49k stars.

Sources: [sli.dev exporting](https://sli.dev/guide/exporting.md), [slidev PR #2722](https://github.com/slidevjs/slidev/pull/2722), [issue #2755](https://github.com/slidevjs/slidev/issues/2755).

### reveal.js, and Quarto revealjs and pptx

- **reveal.js source.** HTML `<section>` elements, or Markdown via the markdown plugin (`---` separators, `<!-- .slide: data-background="…" -->`). There are no layouts beyond CSS and classes. There is no pptx export (DeckTape gives PDF only). MIT. v6.0.2 (2026-09).
- **Quarto revealjs.** Pandoc Markdown in `.qmd`. Layout is set with classes and divs (`{.columns}`, `.smaller`, absolute `{.absolute top=…}`). Renders to HTML only.
- **Quarto pptx** (`format: pptx`, `reference-doc: corp.pptx`). This is **pandoc's pptx writer** with Quarto's front end, so it has the same seven-layout model and the same limits (next section). Quarto's docs repeat pandoc's layout list.
- **Licence / runtime.** MIT (Quarto), GPL-2+ (bundled pandoc). Quarto 1.10.20 (2026-10-30) is a 248 MB macOS pkg that bundles pandoc, Deno, Typst and dart-sass.
- **Diff and tokens.** The same as pandoc Markdown below.

Sources: [Quarto PowerPoint](https://quarto.org/docs/presentations/powerpoint), [reveal.js](https://revealjs.com), [quarto-cli releases](https://github.com/quarto-dev/quarto-cli/releases).

### Pandoc pptx writer (`--reference-doc`)

- **Source.** Pandoc Markdown. Headings at the slide level start slides; headings above it make section slides. `---` or a rule also splits slides. Columns use fenced divs, notes use `::: notes`, and the title slide is built from YAML metadata (`title`, `subtitle`, `author`, `date`, and `notes:` for its notes).
  ```markdown
  ## Before and after

  :::::: columns
  ::: column
  - Manual session juggling
  :::
  ::: column
  - Projects group sessions
  :::
  ::::::

  ::: notes
  Lead with voice.
  :::
  ```
- **Layout model.** There are seven fixed layouts, found **by name** in the reference doc. The first layout with a matching name wins, and a missing name falls back to pandoc's default with a warning. The layout is **inferred from content**; the author cannot pick one. The pandoc 3.13 manual, "PowerPoint layout choice", gives these rules:

  | Layout | Chosen when |
  |---|---|
  | Title Slide | The first slide, generated from metadata `title`/`subtitle`/`author`/`date` |
  | Section Header | A heading above the slide level ("title slide" in pandoc terms) |
  | Two Content | A `columns` div with ≥ 2 `column` divs |
  | Comparison | Two columns where at least one column has text **followed by** non-text (image, table) |
  | Content with Caption | Not two columns, and text followed by non-text |
  | Blank | Only blank content (only notes, or a non-breaking space) |
  | Title and Content | Everything else |

  Confirmed by test, with each slide's layout and `<p:ph>` refs:
  ```
  slide1 -> Title Slide       | <p:ph type="ctrTitle"/> <p:ph type="subTitle" idx="1"/>
  slide2 -> Section Header    | <p:ph type="title"/>
  slide3 -> Title and Content | <p:ph type="title"/> <p:ph idx="1"/>
  slide4 -> Two Content       | <p:ph type="title"/> <p:ph sz="half" idx="1"/> <p:ph sz="half" idx="2"/>
  slide6 -> Title and Content | (image then text: NOT Content with Caption; order matters)
  ```
  Text goes **into the layout's placeholders** (`<p:ph>` with no `xfrm` override), so it inherits the master's fonts, colours and positions. **There is no per-slide layout attribute** in 3.13. The manual lists none, and `{layout=…}` is ignored. Layouts with other names (a corporate "Agenda", "Big Number", "Quote") cannot be reached at all. In my test, a custom layout in the reference doc did not appear in the output. Pandoc takes the theme, masters and the seven named layouts from the reference doc. Per-slide backgrounds come from `{background-image=…}` on the heading.
- **Diff.** One line per bullet.
- **Tokens.** 1,054 chars ≈ 263 tokens, the leanest sampled.
- **pptx fidelity.** The best of any text-first tool for corporate templates: native placeholders, real layout linkage, real notes slides, and native tables. Images go in picture or content placeholders. Column widths can't be set, and there are no charts or SmartArt.
- **Licence / runtime.** GPL-2.0-or-later. Native arm64 binary 195 MB unpacked (43 MB zip). **The official `pandoc.wasm` (62 MB, 16 MB compressed) ships as a release asset since 3.9.** It runs in a browser or WKWebView through the `wasm/pandoc.js` bridge, with no system commands or network, and Lua filters work. Tested: Node WASI produced a correct pptx in ~170 ms. Bundling GPL pandoc.wasm as a separate asset loaded by Duo is aggregation, but Duo would have to ship pandoc's source offer. Check with Geoff whether that is acceptable.
- **Maturity.** Very active: 3.13 released 2026-10-26.

Sources: pandoc 3.13 manual (§"Templates: PowerPoint", §"PowerPoint layout choice", §"Speaker notes"), [pandoc 3.9 release notes on WASM](https://github.com/jgm/pandoc/releases/tag/3.9), local tests.

### Deckset

- **Source.** Markdown. `---` separates slides, and directives are `[.background-color: …]`, `[.column]`, `[fit]` and `^ note` lines. A theme is chosen in the app.
- **Layout model.** About a dozen fixed themes with variants, plus auto-layout (for example, an image and text placed side by side). There are no user-defined layouts or slots.
- **pptx.** No PowerPoint export. The App Store listing names PDF, PNG and JPG only.
- **Licence / runtime.** Proprietary Mac app (App Store).
- **Maturity.** Maintained, niche.

Sources: [App Store listing](https://apps.apple.com/us/app/deckset/id6476942011).

### iA Presenter

- **Source.** Markdown, where everything not indented by a tab is a speaker note and tab-indented text is shown on the slide. `---` separates slides, and `/assets/…` embeds images.
- **Layout model.** Automatic layouts (title, split, grid) chosen from the content, with per-slide overrides in the inspector. Themes are CSS. There are no user-defined slot schemas.
- **pptx.** PowerPoint export exists but is marked **beta**. Its feature table covers text styles, lists and colours. I could not confirm whether it uses placeholders, and I didn't test it (no licence).
- **Licence / runtime.** Proprietary (paid Mac/iOS app).
- **Format note.** The tab-indented convention is not readable as ordinary GFM in Obsidian.

Sources: [iA Presenter export](https://ia.net/presenter/support/action/export/export-mac).

### MDX Deck and Spectacle

- **MDX Deck.** MDX (Markdown plus JSX); layouts are React components. The last release was 4.1.1 (2023) and it is effectively dead. No pptx export.
- **Spectacle.** A React library with an MDX option. Layouts are components (`FlexBox`, `Grid`), with absolute positioning possible. v10.2.4 (2026-10) is maintained. No pptx export.
- Both are MIT and need Node or a bundler.
- **Fit.** Their slides are code, not Obsidian-friendly Markdown, so they're a poor fit.

Sources: npm metadata (`npm view`).

### Remark (gnab/remark)

- **Source.** Markdown inside an HTML page. `---` separates slides, `???` starts notes, `class: center, middle` lines set classes, and `layout: true` makes a slide a template for the following slides. It has `name:`/`template:` slide inheritance.
- **Interest for Duo.** `template: name` is an early form of "this slide uses template X". But templates are other slides in the same file and work by copying content, not by filling slots.
- **pptx.** None.
- **Maturity.** MIT. Last package release 2022, now dormant.

Sources: [remark wiki](https://github.com/gnab/remark/wiki/Markdown).

### Obsidian Advanced Slides, Slides Extended, and the core Slides plugin

- **Core Slides plugin.** It presents a note full screen, splitting on `---`. There are no layouts, no themes beyond the app's CSS, and no export.
- **Advanced Slides.** reveal.js-based. It has `<!-- slide template="[[tpl-title]]" -->`, which **names a template note per slide**, and templates hold `<% content %>`/`<% left %>` slot markers filled from `::: left` blocks. That is conceptually very close to Duo Decks. It is marked **Discontinued**, with its last push in 2024-06. The community fork **Slides Extended** continues it. Both export HTML and PDF only, with no pptx.
- **Format fit.** The slide-template comment syntax (`<!-- slide template="[[…]]" -->`) is plain HTML comments plus wikilinks, which is fully Obsidian-compatible. That is a useful precedent for Duo's convention.

Sources: [Advanced Slides repo](https://github.com/MSzturc/obsidian-advanced-slides), [Obsidian forum: Advanced Slides discontinued](https://forum.obsidian.md/t/discontinued-advanced-slides-create-markdown-based-reveal-js-presentations-in-obsidian/28243), [Slides Extended](https://forum.obsidian.md/t/slides-extended/85825), [Obsidian Help: Slides](https://help.obsidian.md/Plugins/Slides).

### Typst slides (Touying, Polylux)

- **Source.** Typst markup. Touying uses `#show: metropolis-theme.with(…)`, `= Section` and `== Slide` headings, and `#speaker-note[…]`. Polylux uses explicit `#slide[…]`.
- **Layout model.** Themes are Typst functions, and `#slide(composer: (1fr, 1fr))[…][…]` gives columns. Positions are computed by Typst, and slots are function arguments, which is typed and strict. That's good for determinism, but it is not Markdown.
- **Tokens.** About the size of pandoc Markdown, ≈ 280–320 tokens (not sampled).
- **pptx.** Touying's exporter (Python `touying` and Node `touying-exporter`) rasterizes each page to PNG and packs it into a pptx with notes. `typ2pptx` does the same. Image slides only.
- **Licence / runtime.** MIT/Apache. Typst is a single ~40 MB binary and has a WASM build.
- **Maturity.** Touying is active (about 2.4k stars, pushed 2026-10).

Sources: [touying-exporter](https://touying-typ.github.io/docs/external/touying-exporter), [PyPI touying](https://pypi.org/project/touying), [typ2pptx](https://pypi.org/project/typ2pptx/).

## pptx generation libraries

### python-pptx

- **Model.** Opens an existing .pptx and adds slides from `prs.slide_layouts`, by index or by `layout.name`. It fills `slide.placeholders[idx]`, notes go in `slide.notes_slide`, and absolute shapes are also possible. Layouts and placeholders come straight from the corporate template, so this is the canonical "instantiate a layout, fill its placeholders" API.
- **Limits.** It cannot open a `.potx` without patching the content type, a well-known workaround. It has no slide cloning API.
- **Tokens.** As code, a 10-slide deck is 2,139 chars ≈ 535 tokens, about 2× the Markdown.
- **Licence / runtime.** MIT, Python. Unusable at runtime for Duo (no Python on users' Macs).
- **Maturity.** Stable but slow-moving: v1.0.2, last push 2024-08.
- **Use for Duo.** As a reference implementation, and for check tooling on the Mac mini.

Sources: [python-pptx docs](https://python-pptx.readthedocs.io), GitHub API.

### pptxgenjs

- **Model.** JS, MIT. `defineSlideMaster({ title, objects: [{ placeholder: { options: { name, type, x, y, w, h } } }] })`, then `addSlide({ masterName })` and `addText(…, { placeholder: 'body' })`. Tested: it emits real `<p:ph type="title" idx="100">` in a generated layout, but it also writes the xfrm onto the slide shape, so moving the layout later doesn't move existing slides.
- **Key limit.** It **cannot load an existing pptx or potx**. Masters are re-declared in code, so a corporate theme, fonts, master decorations and its exact layouts are approximated, not reused.
- **Runtime.** Runs in a browser, so it would run in WKWebView.
- **Tokens.** 3,093 chars ≈ 773 tokens plus the masters file, as an agent-written format.
- **Maturity.** v4.0.1, last release 2025-06, about 6.3k stars. Maintained but slowing.

Sources: [pptxgenjs masters docs](https://gitbrent.github.io/PptxGenJS/docs/masters/), local test.

### pptx-automizer

- **Model.** Node, MIT. Load a root pptx and one or more template pptx files, `addSlide(templateName, slideNumber, cb)` to **clone** a template slide (with its layout and master), then modify elements by **shape name**: `setText`, `replaceText` with `{{tag}}`, images, charts and tables. It can also add a slide from a layout and fill its placeholders (`addSlide` with `useSlideLayout` in newer versions).
- **Test.** Two clones of "Title and Content" kept `<p:ph type="title"/>` and `<p:ph idx="1"/>` and the `slideLayout2` relationship. `setText` replaced the whole body. `removeExistingSlides` as I passed it did not drop the root's slides. `replaceText` expects `{{…}}` tags, which my test lacked, so it changed nothing.
- **Runtime.** It depends on Node `fs` and `jszip`. Running it in WKWebView would mean shimming file I/O; in practice it is a Node tool.
- **Maturity.** v0.9.4 (2026-09), about 250 stars, a single main maintainer.
- **Fit.** The best fit for "the corporate deck is the template": it reuses real masters, layouts and decorated sample slides exactly.

Sources: [pptx-automizer README](https://github.com/singerla/pptx-automizer), local test.

### docxtemplater (pptx) and "pptx-templater"

- **docxtemplater.** MIT core. It fills `{tag}`, `{#loop}` and `{?cond}` written in a pptx's text in place, so authors keep the corporate file. The **Slides module** (create slides from a loop), **Html-Pptx** and **Subtemplate-pptx** are **paid** modules. JS, browser-capable. v3.71.1 (2026-10), very active.
- **"pptx-templater".** No maintained npm package by that name exists (`npm view` returns nothing). The nearby Python projects (`pptx-template` and others) are small python-pptx wrappers.
- **Fit.** Weak for Duo, because the deck structure (which slides, in what order) is what Duo needs to generate. Without the paid Slides module, docxtemplater only fills a fixed slide list.

Sources: [docxtemplater](https://github.com/open-xml-templating/docxtemplater), npm.

### Aspose.Slides (commercial; note only)

Full PowerPoint object model: clone slides, add slides from layouts, fill placeholders, render. Bindings exist for .NET, Java, C++, Python, Node via Java, and a REST "Cloud SDK for Swift" (cloud, so a non-starter for privacy). Per-developer licences cost thousands of USD. Not suitable for a free OSS app.

### ONLYOFFICE Document Builder

A C++ engine scripted with JS (`builder.OpenFile("corp.pptx")`, `Api.CreateSlide()`, set layouts and fill placeholders). It can open existing pptx, has a real layout and placeholder API, and can render. AGPL-3.0 (commercial licence otherwise), with the repo pushed 2026-10. It's a several-hundred-MB native install with its own runtime, and AGPL makes bundling it in Duo awkward. Note only.

Sources: [ONLYOFFICE DocBuilder blog](https://onlyoffice.com/blog/2019/08/script-to-docs-use-free-onlyoffice-docbuilder-to-generate-docx-xlsx-pptx-and-pdf-files), GitHub API.

### LibreOffice headless

`soffice --headless --convert-to pptx` converts ODP, PDF or HTML to pptx, and Marp's editable mode uses it. The output is absolute-position shapes, and its master and layout mapping is generic. It is useful for rendering checks: pptx to PNG to compare. MPL-2.0, a ~1 GB app. It can't be a Duo dependency.

### Swift and native OOXML writers

- **No mature Swift pptx writer exists.** The nearest is `osaurus-pptx` (Swift, create, read and modify, about 2 stars, no licence file, 2026-07), a plugin for one tool; don't depend on it. CoreXLSX and similar cover xlsx reading only, and PPTXKit is a viewer.
- **A native route is practical, though.** A pptx is a ZIP of about 20 XML parts. The operations Duo needs:
  - read layouts and their `<p:ph>` (type, idx, name) from the template
  - write `slideN.xml` with `<p:sp><p:nvSpPr>…<p:nvPr><p:ph idx="1"/></p:nvPr></p:nvSpPr><p:spPr/><p:txBody>…</p:txBody></p:sp>`
  - add the slide relationship to its layout and add notes slides
  - update `presentation.xml`, its rels and `[Content_Types].xml`
- In Swift that's roughly 1–2k lines with ZIPFoundation (MIT) or Apple's own `Compression` plus a small zip writer. pandoc's `Text.Pandoc.Writers.Powerpoint.Output` and python-pptx are clear references.

Sources: [osaurus-pptx](https://github.com/osaurus-ai/osaurus-pptx), ECMA-376 Part 1 §19 (PresentationML).

## Diffs: a one-word edit

The edit changes the slide-6 bullet "212 weekly users" to "230 weekly users". These are real `diff -u` outputs.

Marp, Slidev, pandoc and the Duo sketch all give the same diff:

```diff
@@ -58,7 +58,7 @@
 ## Adoption

-- 212 weekly users
+- 230 weekly users
 - 38% use voice weekly
```

pptxgenjs, where the agent writes code, gives a whole-line change on a long JSON line:

```diff
-s.addText([{"text": "212 weekly users", "options": {"bullet": true}}, {"text": "38% use voice weekly", ...}], { placeholder: 'body' });
+s.addText([{"text": "230 weekly users", "options": {"bullet": true}}, {"text": "38% use voice weekly", ...}], { placeholder: 'body' });
```

A .pptx committed to git shows only `Binary files a/deck.pptx and b/deck.pptx differ`. Unzipped, `slide6.xml` is a single 1,285-byte line, so the diff is one whole-file line.

Every Markdown format gives a reviewer-readable one-line diff, and the format choice barely matters here. What matters is that the **exported .pptx stays out of review**: it should be a build output, or committed only on release.

## Token cost (10-slide deck)

The same 10-slide content is used in each encoding: a title slide, 2 section slides, 6 bullet slides with 2–3 bullets, 1 two-column slide, and notes on 5 slides. `gen.py` produces them.

| Encoding | chars | ≈ tokens (chars/4) |
|---|---:|---:|
| Pandoc Markdown | 1,054 | 263 |
| Slidev | 1,114 | 278 |
| Marp | 1,209 | 302 |
| Duo sketch (`<!-- slide: X -->` + headings + `> [!note]`) | 1,424 | 356 |
| python-pptx script | 2,139 | 535 |
| pptxgenjs script (excluding masters file) | 3,093 | 773 |
| pptx slide XML, pandoc's minimal output (10 slides) | 12,448 | 3,112 |
| …plus notes slides | 20,087 | 5,022 |

Arithmetic: 1,424 / 4 = 356. Roughly, a slide costs 25–35 tokens of Markdown against 300–500 tokens of minimal XML. PowerPoint-saved XML is typically several times larger again (an estimate; not measured here).

The agent also has to read the template definitions once per session. A 10-template manifest with slot names and limits is about 1–2k chars, or 300–500 tokens. An agent writing a whole deck in Markdown costs under 1k tokens of output. Editing a pptx directly costs 10–20× more and gives worse diffs. The cost difference between the Markdown dialects (±20%) is noise; legibility and strictness matter more.

## Comparison

| | Per-slide template named | Named slots | Strict (only declared layouts) | pptx: native placeholders | Honours corporate .potx/reference pptx | Notes in pptx | Runs inside Duo with no Python/Node | Licence | 2026 activity |
|---|---|---|---|---|---|---|---|---|---|
| Marp | no (CSS class) | no | no | no: image per slide; editable = abs. text boxes | no | yes (image mode); no (editable) | no (Chromium + Node; LibreOffice for editable) | MIT | active |
| Slidev | **yes** (`layout:`) | **yes** (`::right::`) | no | no: image, or abs. shapes (pptx-editable, new) | no | yes / buggy | no (Node + Playwright) | MIT | very active |
| reveal.js | no | no | no | no pptx | — | — | n/a | MIT | active |
| Quarto pptx | no (inferred) | no | 7 fixed | **yes** | **yes** (7 named layouts) | yes | no (248 MB, Deno) | MIT/GPL | very active |
| Pandoc pptx | no (inferred) | no | 7 fixed | **yes** | **yes**, 7 named layouts only; others unreachable | yes | **yes, via pandoc.wasm in WKWebView** (tested under WASI) | GPL-2+ | very active |
| Deckset | no | no | n/a | no pptx | — | — | n/a | proprietary | maintained |
| iA Presenter | auto/inspector | no | no | beta export, unverified | no | ? | n/a | proprietary | active |
| MDX Deck / Spectacle | component | props | no | no pptx | — | — | n/a | MIT | dead / active |
| Remark | `template:` (copy) | no | no | no pptx | — | — | n/a | MIT | dormant |
| Adv. Slides / Slides Extended | **yes** (`template="[[…]]"`) | **yes** (`<% left %>`) | no | no pptx | — | — | n/a | MIT | discontinued / fork |
| Typst Touying/Polylux | theme fn | fn args | yes (typed) | no: image per slide | no | yes | Typst has WASM | MIT/Apache | active |
| python-pptx | layout by name | placeholder idx | yes (API) | **yes** | **yes**, all layouts | yes | no (Python) | MIT | stable/slow |
| pptxgenjs | master by name | placeholder name | yes (API) | yes, but in its own masters | **no** (can't load pptx) | yes | yes (JS in WKWebView) | MIT | slowing |
| pptx-automizer | template slide | shape name | yes (API) | **yes** (cloned) | **yes**, exact | kept from template | Node fs; needs shims | MIT | active, small |
| docxtemplater | fixed slides (loops paid) | `{tags}` | — | yes (in place) | yes | — | yes (JS) | MIT + paid | very active |
| ONLYOFFICE DocBuilder | layout API | placeholders | yes | yes | yes | yes | no (big native, AGPL) | AGPL | active |
| Aspose.Slides | full | full | yes | yes | yes | yes | no / cloud | commercial | active |
| Own Swift writer | Duo's choice | Duo's choice | yes | **yes** | **yes**, all layouts | yes | **yes, native** | Duo's | — |

## Export strategies

### 1. Reference-pptx placeholder fill (pandoc model, generalised)

Open the user's template (.potx or .pptx). For each Markdown slide, create a new slide on **the layout it names**, and put each slot's content into **the layout placeholder it maps to** (`<p:ph idx="…">` with no xfrm, so position, font and colour are inherited).

- **Pros.** The output is what a PowerPoint user would have made by hand. Every text is editable in its placeholder, "Reset slide" works, and theme changes apply. The deck stays light. In Google Slides, imported placeholders become placeholders and layouts appear under Slide → Apply layout. This is the most "native" result and the one Google has the best chance of keeping.
- **Cons.** Only what placeholders can hold: text, picture, table, chart. Anything decorative must already be in the layout.
- **Pandoc's version** fixes the layout set at seven and infers the layout from content. Duo needs any layout, chosen explicitly, so pandoc can't be used as-is. A Lua filter can't add a layout choice, because the choice happens inside the writer.

### 2. Render HTML, then convert (Marp/Slidev model)

Render with WebKit, then either screenshot each slide into a pptx or measure the DOM and rebuild it as absolute shapes.

- **Image mode.** Pixel-perfect and uneditable. Google Slides imports it as a full-slide picture plus notes.
- **Editable mode.** Text boxes at absolute positions with fonts named but not embedded. Wrapping differs, decorations drop, and there is no layout or placeholder linkage. Re-theming in PowerPoint or Google does nothing.
- **Verdict.** Fails "honours the corporate master", and the result looks hand-made by a tool. It is fine only for a "share a picture-perfect copy" export.

### 3. Clone a template slide and replace shape text (pptx-automizer model)

The template is a real deck of sample slides. Each Duo template is a sample slide, its slots are shape names, and export clones that slide and rewrites text in the named shapes.

- **Pros.** Keeps everything the designer put on the sample slide, even non-placeholder decorations, icons and positioned callouts. If the template's shapes are placeholders, the clones keep that linkage (tested).
- **Cons.**
  - Shape names ("Content Placeholder 2") are fragile and invisible in PowerPoint's UI unless the designer uses the Selection Pane.
  - Cloning carries leftover sample content and per-slide overrides (xfrm, local formatting). Those survive into Google, but they're no longer "layout-driven".
  - Bullet-level text replacement must preserve run formatting.
  - Relationship and ID bookkeeping when cloning across files is the bug-prone part.

### Recommended hybrid for Duo

Use strategy 1 as the default, with an opt-in strategy 3. A Duo template is defined by **a layout in the corporate .potx/.pptx plus a slot map** (slot name → placeholder `idx` or `type`, with optional limits such as max bullets or max chars). Export instantiates that layout and fills its placeholders. A template may instead point to a **sample slide**: export then clones it and fills named shapes, for layouts whose look depends on non-placeholder art. Both run in a Swift OOXML writer in the app. pandoc.wasm is a good **fallback or reference** for the Markdown-to-DrawingML text conversion (bullets, levels, bold, links, tables), but it is not the main engine.

Google Slides consequences, per the sources (another agent is testing): Google imports masters and layouts into its theme, but custom masters can shift. SmartArt can become an image, animations and transitions are only partly kept, embedded media may not play, and non-Google fonts get substituted. Strategy 1's output is the most Google-friendly, because it uses only plain text in placeholders, pictures and tables. Strategy 2's image mode survives only as pictures. Strategy 3 is as good as the template's own shapes. Sources: [SlideModel, PowerPoint to Google Slides compatibility](https://slidemodel.com/fix-compatibility-powerpoint-google-slides/), [SlideModel, editing a PPTX in Google Slides](https://slidemodel.com/how-to-convert-powerpoint-presentations-to-google-slides/10-editing-a-pptx-presentation-in-google-slides).

## Recommendation

**Define Duo's own convention, as a strict, small Markdown profile that stays readable as GFM in Obsidian, and keep it pandoc-compatible where that's free.** Don't adopt Marp or Slidev, and don't make Duo a Marp/Pandoc superset:

- Marp has no templates or slots, and its pptx path is images or LibreOffice text boxes.
- Slidev has the right idea (a named layout per slide, `::slot::` markers), but it's Vue and CSS-positioned, unconstrained, and Node/Playwright-bound. Its exports don't touch a corporate master.
- Pandoc has the right *export* model but infers layouts and caps them at seven.
- The tools that name a template per slide (Slidev, Advanced Slides) prove the authoring idea works and is pleasant. None of them exports to native pptx placeholders.

A sketch (full file: `prototypes/formats/duo-sketch.md`, 1,424 chars ≈ 356 tokens for 10 slides):

```markdown
---
deck: Q3 Platform Review
templates: "[[Acme corporate]]"
---

<!-- slide: Two Column -->

# Before and after

## Left

- Manual session juggling

## Right

- Projects group sessions

> [!note]
> Lead with voice.

---
```

- Slides are split by `---`, as in Marp, pandoc, Slidev, Obsidian Slides and Advanced Slides.
- `<!-- slide: <template> -->` names the template. It's an HTML comment, invisible in Obsidian's reading view and close to Advanced Slides' precedent. It could equally be `template:` in a per-slide fence; keep one form.
- Slots are headings or other clear markers matched to the template's declared slot names. Body text under the title is the default slot.
- Notes go in an Obsidian callout (`> [!note]`), which renders in Obsidian and survives GFM. Pandoc's `::: notes` is another option, but fenced divs show as literal text in Obsidian.
- A template manifest (YAML in a `.md` note, or JSON beside the .potx) lists each template's slots, types and limits, and the layout or placeholder each one maps to. Duo validates every slide against it ("unknown template", "unknown slot", "4 bullets > max 3") so Claude gets deterministic errors.
- **Export.** A Swift OOXML writer instantiates the template's real layouts and fills placeholders (strategy 1), with clone-and-fill (strategy 3) for templates that need it. pandoc.wasm in a WKWebView is the fallback or oracle for inline Markdown → DrawingML, already shown to run headless in ~170 ms.
- **Keep it diff-friendly.** One bullet per line, no hard wrapping, and the .pptx kept out of PR review.

## Open items to verify

- Whether Google Slides keeps placeholder linkage for strategy-1 output. Another agent is testing this.
- pandoc.wasm inside WKWebView (memory, start-up time; Node's WASI took 170 ms per run), and GPL source-offer obligations if bundled.
- Advanced Slides' exact slot syntax, from its docs, if Duo copies the precedent.
- The `useSlideLayout` behaviour in pptx-automizer ≥ 0.9, a possible Node-only prototype for a strategy-1 test on the Mac mini.
