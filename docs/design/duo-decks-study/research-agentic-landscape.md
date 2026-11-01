# Duo Decks study (a): how agentic slide tools generate and edit decks

Research for Duo Decks, 2026-10-31. Question: how do agentic slide-creation tools store, constrain, edit, brand and export decks today, and what can Duo Decks borrow?

The brief this is measured against: templates defined per project or user, mostly made by Claude from existing decks; decks written as Markdown in which every slide names a defined template; Duo parses Markdown + templates deterministically into a slide viewer/editor; Claude Code (CLI login only) writes and edits the Markdown; decks live in git with readable PR diffs; a stable deck exports to .pptx at the highest fidelity, then goes to Google Slides. Duo is Swift + WebKit; the user's Mac may have no Python or Node.

How sure each claim is: product internals are rarely documented. Where a claim comes from the vendor's own docs or code it says so; where it rests on third-party reviews it is marked *(secondary)*. Several marketing and comparison pages were written by competitors, and those are treated as weak evidence.

---

## 1. Summary table

| Tool | Canonical stored form | How the model is held to layouts | Edit round-trip | Brand / template import | PPTX / Google Slides export |
|---|---|---|---|---|---|
| Anthropic pptx skill (local copy, 2026-07) | The .pptx itself (OOXML), or a pptxgenjs JS script that builds it | Structured decks: `defineSlideMaster()` layouts with named placeholders, fill by name. Templates: thumbnails + text dump, then the model picks layouts by hand | Unzip, edit `slideN.xml`, rezip; or re-run the script | Read theme XML; duplicate template slides with `add_slide.py` | Native .pptx; validator; LibreOffice render for QA |
| Anthropic pptx skill (2025-10 original) | HTML per slide (html2pptx) or OOXML | Restricted HTML subset; for templates, a slide inventory JSON with shape ids | `rearrange.py` (clone/reorder by index), `inventory.py` → replacement JSON → `replace.py` | Clone template slides, replace text per shape | Native .pptx |
| Claude "Slides" artifact type (release 1793404536) | `project/deck.json` index + one `project/slides/<id>.html` per slide, in a closed inline-CSS subset on a 1920×1080 canvas | Closed HTML/CSS subset; build errors and lint notes; design-system tokens | Per-slide file edits by id; `sed` for repeated small changes; conflict-refused publishes | Design System artifact installed into the deck (tokens, fonts, pictures) | Downloads PPTX/PDF; "send to" Google Drive via MCP |
| Claude for PowerPoint (GA 2026-05) | The open .pptx in PowerPoint | Reads slide master, layouts, fonts, colours; builds slides on them | Pinpoint edits to selected slides/elements | Whatever template is open | Native (it is PowerPoint) |
| Gamma | Proprietary "cards" (fluid, web-first) | Themes; `cardSplit` on `\n---\n`; text modes | Agent edits in place (Gamma 3.0, 2025-09); API "from template" regenerates from one gamma | Import .pptx to make a theme; plain import loses source styling *(secondary)* | PPTX/PDF/PNG; fonts embedded; charts may become images; no direct Google Slides |
| Tome | Proprietary tiles | n/a | n/a | n/a | Product shut 2025-04-30; content deleted |
| Beautiful.ai | Proprietary "Smart Slides" (constraint layouts) | Only layouts from its catalogue; auto spacing/resize | Edit inside smart slide; AI from outline | Brand kit, fonts, import PPT content | Editable PPTX on paid plans; smart behaviour lost; font shifts |
| Pitch | Proprietary | Pitch templates | In app | PPTX import (beta, 16:9 only) | PPTX export on Plus |
| Microsoft Copilot in PowerPoint | Native .pptx | Sample slides first, then layouts/placeholders, then slide master | Prompt-driven, per slide | Brand kits, Organization Asset Library (.pptx/.potx) | Native |
| Gemini in Google Slides (2026-06-30) | Native Google Slides | Attach a deck as "style reference"; outline approved first | In Slides | Style reference deck | Native Slides; PPTX via Slides' own export |
| Canva | Proprietary design | Templates, brand kit | In editor; Magic Layers turns images into layers (2026-03) | Brand kit (partial auto-apply) *(secondary)* | PPTX export needs cleanup *(secondary)* |
| Manus | HTML slides (Standard), images (Image mode), native .pptx (PowerPoint mode, 2026-07) | Not documented | Chart/table editors in viewer | Not documented | Native .pptx in PowerPoint mode; image mode not editable |
| Genspark AI Slides | Not documented; two modes (Professional editable, Creative image) | Not documented | Click element, describe change | Import .pptx as reusable template (beta, 2025-12) | PPTX, PDF, Google Slides |
| Kimi Slides | Not documented | Uploaded .pptx as template; "document-to-skill" makes a reusable .md skill from decks/brand guides | Outline review then generate | .pptx template; skill from brand guidelines | Editable PPTX with native charts |
| Z.ai / Zhipu GLM slide agent | HTML per slide, returned with a slide position | Not documented | Edits address slides by position | n/a | PDF; PPTX "coming soon" |
| Presenton (OSS, Apache-2.0) | DB records: layouts as element JSON + JSON content schemas (Template V2) | Model picks a layout per outline item, then fills a JSON schema built from its editable elements | Slide edit/regenerate in UI; MCP | PPTX → "certified" layouts by vision passes | PPTX/PDF |
| PPTAgent (ICIP-CAS, OSS) | Reference .pptx + per-slide HTML sources | Reference slide chosen by functional type; content schema per slide | Edit actions on the HTML render (`replace_span`, `clone_paragraph`, …) with REPL self-correction | Induce functional types and schemas from reference decks | PPTX (LibreOffice/Chrome in the loop) |
| ppt-master (OSS, MIT, ~71.6k stars) | Project folder: `design_spec.md`, `spec_lock.md`, one closed-subset SVG per page | Project-canonical SVG dialect; checker blocks errors; Brand/Style/Layout/Deck template kinds | Edit Native PPTX route keeps unchanged pages byte-for-byte | "Create Template" distils templates from reference decks | Native DrawingML; optional data-backed charts/tables |
| SlideDeck AI (OSS) | JSON from a fixed schema | Pre-defined python-pptx templates | Instruction history; regenerates JSON | Pick one of a few templates | PPTX via python-pptx |
| Office-PowerPoint-MCP-Server (OSS) | The .pptx | Tools such as `populate_placeholder`, `apply_slide_template`, 25 built-in templates | Tool calls on the open file | `create_presentation_from_template` | Native (python-pptx) |
| Slidev | One Markdown file; `---` separates slides; `layout:` frontmatter; `::slot::` sugar; Vue layouts | Named layouts with named slots | Edit the Markdown | Themes/layouts as Vue components | PPTX = images; `pptx-editable` rebuilds shapes from the browser |
| Marp | One Markdown file; directives; CSS themes | Theme CSS classes | Edit the Markdown | CSS theme | PPTX = background images; `--pptx-editable` is experimental, needs LibreOffice, lower fidelity |
| pandoc | Markdown | `--reference-doc` .pptx/.potx with seven named layouts; layout chosen from content shape | Edit the Markdown | Any .pptx/.potx with those layout names | Native .pptx using the template's own layouts |

---

## 2. Anthropic

### 2.1 The pptx skill, as installed locally

Read in full: `SKILL.md` and the scripts in `~/.claude/skills/synced/…/pptx/` (this copy matches the public repo's July 2026 update, `fa0fa64`, "Update docx, pptx, and xlsx skills (#1447)", plus a small preamble that steers bare "make me a deck" requests to a Slides artifact type when one exists).

**What it stores.** Nothing of its own. The deliverable is the .pptx. For new decks the source of truth is a throwaway `pptxgenjs` script; for edits it is the unzipped OOXML.

**Three workflows, chosen by task:**

| Task | Approach |
|---|---|
| Create | Write a `pptxgenjs` script; build it as a "structured deck" |
| Edit an existing deck, or build from a template | Unzip → edit `ppt/slides/slideN.xml` → zip |
| Read | `slide_text.py` (markdown per slide, with `<!-- Slide number: N -->` markers) and `thumbnail.py` (labelled grid) |

**How it constrains layout.** Two different mechanisms:

1. *Structured decks* (new): the theme comes first (`THEME = {name, headFontFace, bodyFontFace, colors: {dk1 … folHlink}}`), every colour is a scheme colour (`pres.SchemeColor`), sections are declared, and there is "one layout per slide frame" via `defineSlideMaster()`, which really makes a `slideLayoutN.xml`. Text regions are named placeholders carrying position, size, weight and colour; slides are filled by name (`addText("…", { placeholder: "title" })`) with no position or colour on the slide. Footer, logo and slide number live on the layout. After `writeFile()`, `apply_theme.js` writes the twelve theme colours into `ppt/theme/theme1.xml`, because pptxgenjs hard-codes Office's palette. This is the skill's version of "every slide uses a defined template": a deck built this way can be restyled in one place and edited in PowerPoint without a fight.
2. *Templates* (existing decks): `thumbnail.py template.pptx <prefix>` renders a labelled grid; the model maps each section of content onto a template slide, duplicates it with `add_slide.py` (which does the registration bookkeeping: content types, rels, `<p:sldId>`), reorders by editing `<p:sldIdLst>`, deletes with `clean.py`, then edits text in the XML. The rules are explicit: do every structural change before any content edit; "Template slots ≠ source items" (with three team members on a four-member slide, delete the fourth group, not only its text); one `<a:p>` per list item; let bullets inherit from the layout.

**How it validates.**
- `scripts/office/validate.py deck.pptx [--original src.pptx]`: XSD schema checks per part, relationships, content types, master/theme uniqueness, slide-layout ids, duplicate layouts, notes references, and chart checks that catch the pptxgenjs faults PowerPoint refuses (stacked bar `outEnd` labels; secondary axes declared without both `valAxes` and `catAxes`). `--original` baselines against a template so the template's own XSD errors aren't reported as yours. Every failure names its fix.
- Content QA: `slide_text.py | grep -iE "\bx{3,}\b|lorem|ipsum|\bTODO|\[insert|…"` for leftover placeholder text.
- Visual QA: LibreOffice (`soffice.py --headless --convert-to pdf`) then `pdftoppm -r 150` to JPEGs, inspected "fresh" (a subagent is suggested), with a checklist that leads with text overflow. The skill also knows its renderer is not PowerPoint: it lists fonts whose LibreOffice substitutes have different widths (Georgia, Trebuchet, Garamond, Consolas…), says not to trust text-fit on them, and says never to default to Aptos.
- "Your first render usually has a few real issues… Find and fix those, re-render only the slides you changed, and stop."

**Design guidance baked in** (relevant because templates will carry it): one message per slide; no accent lines under titles and no decorative edge stripes ("hallmarks of AI-generated slides"); minimum sizes (body 14pt, captions 10pt) with "cut words, enlarge the container, or split" once at the floor; titles in the same place on every slide of a type.

### 2.2 How the skill changed (public repo history)

`github.com/anthropics/skills`, `skills/pptx/` (earlier `office-examples/pptx/`, then `document-skills/pptx/`):

| Date | Commit | Change |
|---|---|---|
| 2025-10-15 | `37292f3` init | `html2pptx.md` + `scripts/html2pptx.js`, `ooxml.md`, `inventory.py`, `replace.py`, `rearrange.py`, `thumbnail.py` |
| 2026-02-03 | `4e6907a` (#330) | SKILL.md streamlined, `editing.md` and `pptxgenjs.md` added, html2pptx.md and ooxml.md removed, html2pptx bundled as a tgz |
| 2026-02-03 | `a5bcdd7` (#331) | "Delete legacy html2pptx.tgz dependency" |
| 2026-07-16 | `fa0fa64` (#1447) | Current form: structured decks, `apply_theme.js`, `slide_text.py`, chart validators |

The 2025 workflows are worth knowing because they are the clearest published versions of two patterns:

- **html2pptx.** One HTML file per slide with `body` sized to the slide (720pt × 405pt for 16:9). A strict subset: all text must be in `<p>`, `<h1>`–`<h6>`, `<ul>`, `<ol>` ("Text in `<div>` or `<span>` without a text tag will be silently ignored"); backgrounds, borders and shadows only on `<div>`; no CSS gradients (rasterise them first with Sharp); web-safe fonts only; `class="placeholder"` reserves a box for a chart that pptxgenjs then fills. The converter opens each file in Playwright/Chromium, measures every element's computed box and writes pptxgenjs shapes at those coordinates. It throws if the body size doesn't match the deck layout or content overflows the body, and lists unsupported inline margins. Anthropic dropped it in February 2026: the converter needed Playwright and Chromium, and a browser's layout is not PowerPoint's.
- **Template fill by inventory.** `rearrange.py template.pptx working.pptx 0,34,34,50,52` builds the deck by cloning template slides by index (the same index twice duplicates it). `inventory.py` dumps every text shape as JSON (`slide-N` → `shape-N` with placeholder type, position in inches, paragraphs with bullet/level/alignment/font/colour, only non-default values). The model writes a replacement JSON keyed by those ids; `replace.py` validates that every referenced shape exists ("Shape 'shape-99' not found on 'slide-0'. Available shapes: shape-0, shape-1, shape-4"), clears every inventoried shape not given new paragraphs, and applies formatting. The workflow also required a written `template-inventory.md` and an `outline.md` with an explicit `template_mapping = [0, 34, 34, 50, 54]`, plus rules such as "Never use layouts with more placeholders than you have content" and "Quote layouts: use ONLY for actual quotes".

### 2.3 Claude "Slides" artifact type

The Slides type, read through the Artifact tool, release `1793404536-d7a0`, contract `0.2.47`.

- **Storage:** `project/deck.json` (`{"v":4, "title", "order":[ids], "sections":{key:{description,start}}, "cover", "faces", "designSystems":[]}`) plus **one file per slide**, `project/slides/<id>.html`, each exactly one `<section id="<id>">`. Speaker notes are an `<aside>` as the section's last child. A slide shows while its file exists; `order` places it.
- **Constraint:** a *closed* subset, generated from code (`scripts/gen-subset-table.ts`): fixed 1920×1080 canvas, every style inline, px only (no em/rem/%/var()), a whitelist of properties with value ranges per element (e.g. `font-size: 8–400`, `gap 0–512`, `≤24` pinned children per host, `≤200` elements per slide, `≤15` nested divs), custom elements `<x-shape kind>`, `<x-icon name>` from a fixed list of 31 icons, `<x-connector>`, `<x-embed>`. "Anything else is a build error naming the slide, the element and the closest supported change." Visible heals are warnings that block; equivalent heals (`pt`→`px`) are notes. Layout lints (overlapping text boxes, box narrower than its longest word, fixed-height overflow) are non-blocking estimates.
- **Layout guidance is arithmetic, not taste:** 824px of vertical space inside the margins; heading ≈ size × lines × 1.1; table row ≈ 2.1 × font-size; "size boxes to their longest word (about 0.6 × font-size per character)"; "Too much? Split the slide; nothing shrinks."
- **Edits:** read the index, read only the slide files you change, edit them, publish only those files. Slide ids stay stable because "comments and links key on them". Repeated small changes may use `sed 's/old/new/g'` with tight character rules. A publish over someone's unread edit is refused; the agent re-reads and redoes the change.
- **Brand:** a Design System artifact is "installed" by copying its `tokens.json`, fonts and pictures into `project/ds/<folder>/` and recording it in `designSystems`, so the editor's Theme and colour menus offer the system's tokens, not bare hexes.
- **Validation stance:** the opposite of the pptx skill. "NEVER VERIFY UNLESS THE USER ASKED… Do NOT read it or your files back to check, re-check layout or sizes, render, screenshot or open it." Correctness is pushed into the format, the build and the lints, so the agent spends no tokens looking.
- **Export:** PPTX and PDF downloads ("PPTX/PDF flatten" live embeds); the deck can be sent to Google Drive through its `mcp` capability (`create_file`, `gdrive_upload`).

This is the closest existing thing to Duo Decks: per-slide addressable source, closed vocabulary, deterministic renderer, design-system tokens, pptx export. The differences: HTML+inline CSS is the authoring language (verbose, coordinate-ish, noisy diffs), and there is no notion of a template the slide must name; layout is composed per slide.

### 2.4 Claude for PowerPoint

Office add-in, GA to Pro/Max/Team/Enterprise (May 2026 per secondary reports; the doc page says GA). Per Anthropic's docs: "Claude reads the slide master, layouts, fonts, and color scheme in your deck and uses them when generating or editing slides"; "Make pinpoint edits to specific slides without regenerating entire decks"; native charts and diagrams, "not static images"; persistent Instructions for brand rules; Skills supported. Best practice: "Start with your template already applied before asking Claude to generate content." The page warns about prompt injection from downloaded templates and vendor files. Its representation is PowerPoint's own object model via the add-in API, so it says nothing about storage, but it shows the bar for template compliance and targeted edits.

**Sources (§2):** local skill files listed above; https://github.com/anthropics/skills (commits `37292f3`, `4e6907a`, `a5bcdd7`, `fa0fa64`); Slides type https://claude.ai/artifact/8jTsAFQMFDb2oA8MsPJ2eL (`SKILL.md`, `reference/format.md`, `reference/deck-files.md`); https://claude.com/docs/office-agents/powerpoint ; https://support.claude.com/en/articles/13521390-use-claude-in-powerpoint

---

## 3. Commercial products

### 3.1 Gamma

- **Stored form:** proprietary "cards", fluid web pages first, slides second. The API takes text and splits it into cards: `cardSplit: inputTextBreaks` splits on `\n---\n` ("One \n---\n = one break… two cards"); `auto` ignores breaks and uses `numCards`. `textMode` is `generate | condense | preserve`. `format` is `presentation | document | social | webpage`; `cardOptions.dimensions` is `fluid | 16x9 | 4x3`.
- **Layout constraint:** themes (colours and fonts, `themeId`) plus Gamma's own layout engine; `additionalInstructions` (≤5000 chars) steers layout loosely. No layout catalogue is exposed to callers.
- **Edits:** Gamma 3.0 (Sept 2025) added an agent that edits across the canvas in natural language; select an image and "Edit with Agent" *(secondary)*. The API's `POST /v1.0/generations/from-template` takes a `gammaId` and a prompt and keeps "an existing Gamma's layout and card count" by default. That is template-by-example at whole-deck level, still regeneration rather than a patch.
- **Brand import:** import a PowerPoint to create a theme (200 MB cap); plain import puts text into cards, one per slide, and per one guide "the original file's styling is replaced by Gamma's design system" *(secondary, and contradicted by another Gamma guide)*.
- **Export:** PDF/PPTX/PNG, one format per API call, URLs expire in about a week. Gamma's help: exports reflect Present mode; theme fonts (including uploads) are embedded in the .pptx, but "Google Slides ignores fonts embedded in an uploaded PowerPoint file"; tables export as real tables but lose rounded corners; solid page backgrounds can go missing ("set a background on each card"); 150+ card gammas can fail to export; charts export as images per a user feature request *(unconfirmed officially)*. No direct Google Slides export: the route is PPTX then import.
- **What fails:** the fluid-card model doesn't map to fixed 16:9 slides; aspect and scaling differ between edit, present and export.

Sources: https://developers.gamma.app/docs/generate-api-parameters-explained ; https://developers.gamma.app/generations/create-from-template.md ; https://help.gamma.app/en/articles/8022861-how-do-i-export-my-gamma ; https://help.gamma.app/en/articles/15939201-why-doesnt-my-exported-pdf-or-powerpoint-match-what-i-see-in-gamma ; https://help.gamma.app/en/articles/11047840-how-can-i-import-slides-or-documents-into-gamma ; https://ideas.gamma.app/ideas/p/improve-powerpoint-export-behavior

### 3.2 Tome

Tome's presentation product closed on 2025-04-30; the team went on to Lightfield, an AI CRM (Series A from a16z reported). Reports say remaining user content was deleted after export windows; pivot timing is reported inconsistently (2024 to March 2025). The lesson for Duo is about storage, not generation: a proprietary hosted format with weak export lost its users' decks. Text files in the user's own git repo don't have that failure mode.

Sources *(secondary)*: https://www.chatslide.ai/articles/tome-ai-shut-down-what-happened ; https://deckary.com/blog/tome-review ; https://dealroom.co/news/149823-ai-crm-startup-lightfield-raises-47m-series-a-led-by-a16z/

### 3.3 Beautiful.ai

- **Stored form:** proprietary "Smart Slides": layouts governed by arrangement rules that re-space and resize as content changes.
- **Constraint:** the strongest of the commercial tools. You can only use its catalogue of smart layouts, and content is placed into them; "Create with AI" generates an outline first, then fills smart slides.
- **Export:** editable PPTX on Pro/Team/Enterprise, speaker notes kept; missing fonts change the look; animations don't survive; smart behaviour is lost (it becomes fixed text boxes) *(partly secondary)*. Their own blog post is titled "How to export to PPT and why you shouldn't".
- **Brand:** brand kit with locked colours, fonts and logos on Team; import PowerPoint *content*. No evidence found that a customer .potx becomes the smart-slide master.
- **Lesson:** a constraint-based layout engine gives consistency, but the constraints live in their runtime, so they disappear on export. Duo's export must carry the template's own master and layouts, not a rendering of them.

Sources: https://beautiful.ai/smart-slides ; https://support.beautiful.ai/hc/en-us/articles/30629528652685-Exporting-your-slides-and-presentations ; https://www.beautiful.ai/blog/how-to-export-to-ppt-and-why-you-shouldnt ; https://mktg.beautiful.ai/team-upgrade

### 3.4 Pitch

Proprietary format. PPTX import is beta, "works best with simple presentations", 16:9 only; PPTX export on the Plus plan. Competitors claim animations, transitions and some fonts don't survive and that you can't bring your own PowerPoint template *(secondary, unverified)*.

Sources: https://help.pitch.com/en/articles/4615453-import-a-presentation ; https://www.pitch.com/integrations/ppt-export ; https://www.pitch.com/integrations/ppt-import

### 3.5 Microsoft Copilot in PowerPoint

- **Stored form:** native .pptx.
- **Constraint, in priority order (Microsoft's own words):** "primarily uses your sample slides, and secondarily your template's structure and layouts"; "If your template does not contain enough sample slides, Copilot falls back to the Slide Master." It uses placeholder *type, position and size*, and "does not rely on placeholder text wording to understand layout intent". Microsoft recommends sample slides for each slide type (Title, Agenda, Section Header, Content, Data Visualization, Timeline, Process, Quote, Q&A, Summary, Thank You) at light, medium and heavy density, and "complete end-to-end examples rather than loose element libraries".
- **Brand:** Brand kits hold approved templates (.pptx/.potx), colours, fonts, assets, voice; templates come from upload or the Organization Asset Library; templates "must be created in PowerPoint for Windows or Mac (not Web)". Branded generation needs a Microsoft 365 Copilot licence.
- **Limits:** "Copilot does not change font size or placeholder size" and "may instead add additional design elements to accommodate the content"; overlapping text boxes and decoration over text areas hurt; with too few sample slides output is generic.
- **Create from file:** open a deck that already has your theme, then "Create presentation from file" from a Word document (under 24 MB per a Microsoft community post).
- **Agent Mode / Office Agent:** Microsoft's Copilot chat Office Agent and PowerPoint Agent Mode run on Anthropic's Claude models (admins must connect Claude; Microsoft's DPA and other terms don't cover the Anthropic processing). Rollout from January 2026 per the message centre; GA dates vary in secondary reports.
- **Lesson:** Microsoft's own template guidance amounts to "give the model reference slides, not only layouts". Sample slides carry density, intent and visual examples that bare layouts don't.

Sources: https://support.microsoft.com/en-US/PowerPoint/copilot/keep-your-presentation-on-brand-with-copilot ; https://support.microsoft.com/en-us/PowerPoint/copilot-tutorial-create-a-branded-presentation-from-a-file ; https://support.microsoft.com/en-gb/office/frequently-asked-questions-about-copilot-in-powerpoint-3e229188-9086-4f4c-9f9f-824cd25ae84f ; https://techcommunity.microsoft.com/t5/microsoft-365-insider-blog/create-on-brand-presentations-using-templates-with-microsoft-365/ba-p/4409135 ; https://mc.merill.net/message/MC1267867

### 3.6 Gemini in Google Slides

Workspace Updates, 2026-06-30: "You can now create a full, multi-slide presentation using Gemini in Google Slides"; ground it in any number of Drive files; "Attach an existing deck to use as a style reference"; "You will also have the chance to edit or approve the presentation outline before the actual slides are created"; output is "fully editable slides". English (US) only at launch; Business/Enterprise Standard and Plus, Google AI Pro/Ultra. Storage is native Slides, so Google-side fidelity is perfect, and the route to PowerPoint is Slides' own export.

For Duo this matters at the far end: once a Duo deck reaches Google Slides, Gemini can edit it there with a style reference. Duo's job is to arrive with clean layouts and placeholders, which survive Google's PPTX import better than free-floating shapes.

Source: https://workspaceupdates.googleblog.com/2026/06/create-fully-native-and-editable-presentations-with-Gemini-in-Google-Slides.html

### 3.7 Canva

Proprietary designs; Magic Design builds decks from a short prompt (≈100 characters per one review); the brand kit auto-applies colours but logos and fonts need manual work *(secondary)*. Magic Layers (March 2026, Canva Design Model) turns flat AI images into layered, editable designs. PPTX export routinely needs cleanup: missing fonts get replaced with Calibri or Arial, animations are dropped, and elements shift *(secondary)*. Not a model for Duo beyond confirming that image-first generation needs a de-flattening step to become editable.

Sources: https://www.canva.com/newsroom/news/magic-layers ; https://secure.businesswire.com/news/home/20260311951174/en/Canva-Introduces-Magic-Layers-Turning-Static-AI-Outputs-Into-Editable-Designs ; https://buildfastwithai.com/ai-tools/canva-magic-design *(secondary)*

### 3.8 Manus, Genspark, Kimi, Z.ai/Zhipu

- **Manus.** Three modes (blog, July 2026): Standard (earlier decks were "generated in a web-based format", i.e. HTML), Image (GPT Image 2), and PowerPoint, which "authors a native .pptx from the first slide to the last" with editable charts (Elements toggles, Edit Data spreadsheet overlay). Its docs say Nano Banana Pro slides "are complete images with text rendered directly into the visual"; for editable decks, use HTML slides. No template upload is documented.
- **Genspark AI Slides.** Professional (structured, editable) vs Creative (Nano Banana Pro, image-heavy), chosen up front. Click an element and describe the change. Import .pptx and save as a reusable template (beta, 2025-12-01 changelog). Exports PPTX, PDF, Google Slides; a 2026-03-21 changelog entry fixed font-styling and image problems in PPTX export *(changelog seen through search; the page itself returned 403)*.
- **Kimi Slides.** Outline review, then generation; Adaptive/Visual modes; "editable native PowerPoint charts and SmartArt" *(secondary)*. Takes an uploaded .pptx as the visual template, and advises cleaning the slide master and removing confidential layouts first. Kimi's "document-to-skill" (文档转技能) turns uploaded decks, documents or brand guidelines into a reusable skill you can edit and export as a `.md`: the skill encodes layouts, colour schemes, typography and formats. That is the Kimi-side version of Duo's "feed decks to Claude to make templates", stored as prose instructions rather than a schema. Kimi's 2026-10-08 resource page also lists 12 open-source agent PPT skills, most of which use HTML as the source and export PPTX.
- **Z.ai / Zhipu GLM slide agent.** Beta. Per the Chinese API docs, each slide's HTML comes back in an output field and a position field says which slides an edit touched. Export is PDF; "PPTX and other formats coming soon". It is HTML-per-slide with addressable positions, without a PowerPoint path.

Sources: https://manus.im/blog/manus-ppt-slides ; https://www.manus.im/docs/integrations/nano-banana-pro ; https://genspark.ai/tools/ai-powerpoint-generator ; https://www.genspark.ai/docs/ai_slides_changelog ; https://www.kimi.com/resources/ppt-skills-for-agents ; https://pasqualepillitteri.it/en/news/9713/kimi-slides-prompt-to-editable-pptx-k3 *(secondary)* ; https://docs.z.ai/guides/agents/slide.md ; https://docs.bigmodel.cn/cn/guide/agents/glm-ppt.md

---

## 4. Open-source agents and libraries

### 4.1 Presenton (Template V2)

Apache-2.0, ~11.6k stars, pushed 2026-10-30. Its `docs/template-v2.md` is the most explicit public design for **template induction plus schema-constrained filling**:

- **Template creation** (needs a vision model): convert the PPTX to raw element JSON; require one rendered preview per slide; per slide, in parallel, run focused schema-validated passes: visual-data detection (charts, tables, lists, gauges), semantic analysis (group elements into components, mark each `decorative` or editable), flexible-region analysis (repeatable card grids, sequences), **text-capacity analysis** ("safe length and growth constraints for editable text"), then compile and "certify" a `SlideLayout`, retrying with fewer optional decisions if validation fails. Editable images and icons become placeholders; logos, frames and backgrounds stay fixed. Then de-duplicate interchangeable components and derive theme roles (colours and fonts) with a deterministic fallback. Stored: `raw_layouts`, `layouts`, `merged_components`, `theme`, `assets` (source PPTX, previews, fonts).
- **Generation:** outline → load layouts → "Every layout is converted into a JSON content schema. Only elements marked `decorative=false` become generated content fields" → select a compatible layout per outline slide → generate schema-conforming content → deep-copy the layout and hydrate fields, expanding or contracting repeated groups "within their certified limits" → images → export. A text-only model is enough once the template exists.
- **Markdown input:** the LLM "select[s] suitable layouts and map[s] each Markdown item into the template's structured fields, so text may be rephrased to fit".
- **MCP:** a Streamable HTTP endpoint; `upload_template_assets` takes one PPTX and its fonts, then `start_template_generation`; jobs are polled.

Sources: https://github.com/presenton/presenton ; `docs/template-v2.md` in that repo.

### 4.2 PPTAgent (ICIP-CAS)

EMNLP 2025 paper (arXiv 2501.03936); repo ~5.2k stars, active (2026-09: PPTAgent skill for Claude Code, Codex, OpenCode; DeepPresenter accepted to ACL 2026).

- **Stage I, analysis:** split slides into structural slides (opening, sections, ending, found by an LLM reading the deck) and content slides (rendered, text replaced by a placeholder glyph and images by solid colour, ViT-embedded, hierarchically clustered at cosine 0.65, each cluster's layout described by an MLLM). Then a **content schema** per slide: each element's category, description and content.
- **Stage II, generation:** an outline in which each entry names a reference slide and the source content; then the model edits the reference slide through an API over an **HTML rendering of the slide**, because raw XML is too verbose ("1,006 lines" for one example). The API: `del_span`, `del_image`, `clone_paragraph`, `replace_span`, `replace_image`. Actions run in a REPL; errors go back to the model, with up to two correction rounds.
- **Measured:** removing the HTML rendering drops success from 95.0% to 74.6%; removing schema guidance drops it to 78.8%. Weaknesses: output quality depends on the reference chosen, and overlaps happen because visual information is under-used.
- **PPTEval:** MLLM-as-judge on Content, Design, Coherence (1–5); Pearson with humans 0.70/0.90/0.55.
- **Current skill:** "Get an editable PPTX and HTML slide sources that your agent can revise in follow-up requests"; needs Python 3.11+, uv, npm, LibreOffice and (on macOS) Chrome; an optional external vision model reviews renders in `mode: text`.

Sources: https://arxiv.org/abs/2501.03936 (v3 HTML read) ; https://github.com/icip-cas/PPTAgent ; `skills/pptagent/README.md`

### 4.3 ppt-master

MIT, ~71.6k stars, pushed 2026-10-30: by far the most-used open agent deck workflow. It runs as a skill inside any agent host (Claude Code included) and needs Python 3.10–3.14.

- **Stored form:** a project folder with `design_spec.md` + `spec_lock.md` (written by the "Strategist" role after two confirmation stages) and one SVG per page in `svg_output/`. The SVG is a **project-canonical intermediate language**: "it borrows SVG's XML syntax and two-dimensional graphics model, while the project contract closes the allowed elements, attributes, units, metadata, structural contracts, and DrawingML mappings… SVG adapts to PPT Master; PPT Master does not expand to follow the entire SVG standard." Inputs are canonical, compatible (one deterministic normalisation, warned), or invalid (blocked).
- **Gates:** `svg_quality_checker.py --stage early` after the first five pages (fix the whole class of issues before writing the rest), then `--stage final` with zero errors required; `svg_to_pptx.py` compiles to native DrawingML and refuses to release without a matching final quality report. Visual self-review is opt-in only.
- **Templates, four kinds:** Brand (identity: colour, type, logo, voice, icon style), Style (method and visual defaults), Layout (brand-neutral canvas, page structure, semantic text roles, slot groups), Deck (a recurring family: Brand + Layout + context). Each compiles to native objects: Brand → theme colours and fonts; Layout → master/layout/placeholder topology; Deck → both plus prototypes. "Create Template" workflows distil each kind from reference decks.
- **Edit Native PPTX route:** import an existing deck into a "source-preserving round-trip workspace"; "keeps the design and unchanged pages byte-for-byte, edits chosen pages".
- **Export:** "natively editable DrawingML"; charts and tables are editable shapes by default, data-backed Chart/Table objects with `--native-charts-and-tables`.

Sources: https://github.com/hugohe3/ppt-master ; `docs/technical-design.md` ; `docs/templates-architecture.md`

### 4.4 Smaller tools

- **SlideDeck AI** (MIT, active 2026-10): the LLM writes JSON against a fixed schema, python-pptx assembles it over one of a few templates, and refinement keeps an instruction history and regenerates. https://github.com/barun-saha/slide-deck-ai
- **Office-PowerPoint-MCP-Server** (GongRzhe, ~1.9k stars, last push 2025-12-31): python-pptx behind 32–34 MCP tools, including `create_presentation_from_template`, `get_template_file_info`, `populate_placeholder`, `list_slide_templates`, `apply_slide_template`, and 25 built-in "slide templates" with dynamic font sizing. The model drives the file by imperative tool calls, so there is no source document to diff. https://github.com/GongRzhe/Office-PowerPoint-MCP-Server
- **ChatPPT** (Chinese commercial product) and the many "AI PPT" skills listed by Kimi follow the HTML-source, PPTX-export shape; nothing new for Duo was found there.

### 4.5 Markdown deck tools (the closest prior art to Duo's source format)

- **Slidev.** One Markdown file, slides split by `---`, per-slide frontmatter `layout: two-cols`, named slots with `::right::` sugar, layouts as Vue components loaded in order (built-in, theme, addon, local `layouts/`, last wins). This is Duo's model almost exactly: every slide names a layout, and the content goes into named regions. Export: "all the slides in the PPTX file will be exported as images, so the text will not be selectable"; `--format pptx-editable` measures the browser layout and rebuilds shapes, with SVG, canvas, KaTeX and so on staying pictures. An official agent skill exists (`npx skills add slidevjs/slidev`). https://sli.dev/guide/layout ; https://sli.dev/features/slot-sugar ; https://sli.dev/guide/exporting
- **Marp.** One Markdown file, directives, CSS themes. PPTX is pre-rendered background images; `--pptx-editable` is experimental, needs LibreOffice, "results in lower slide reproducibility", drops presenter notes, and the maintainers don't recommend it when appearance matters. Third-party `MarpToPptx` builds shapes directly from the Markdown. https://github.com/marp-team/marp-cli ; https://www.nuget.org/packages/MarpToPptx
- **pandoc.** Markdown → .pptx using `--reference-doc` (any .pptx/.potx). It requires layouts named Title Slide, Title and Content, Section Header, Two Content, Comparison, Content with Caption, Blank ("the first layout found with that name will be used"), and picks a layout from the slide's content shape: a `::: columns` div selects Two Content. Speaker notes come from `::: notes`. Column widths don't carry to PowerPoint. This is the existing proof that **deterministic Markdown → placeholder fill over a customer's own .potx** works and stays editable; its limit is a fixed set of seven layouts chosen by inference, not by name. https://pandoc.org/MANUAL.html (sections "PowerPoint layout choice", `--reference-doc`)

---

## 5. Research papers

| Paper | Representation | Template handling | Finding that matters for Duo |
|---|---|---|---|
| PPTAgent (arXiv 2501.03936, EMNLP 2025) | Reference .pptx; HTML view for editing | Induced functional types + content schemas; edit by reference slide | HTML view beats raw XML (95.0% vs 74.6% success); schema guidance worth +16 points |
| AutoPresent / SlidesBench (arXiv 2501.00912, CVPR 2025) | Python programs (python-pptx, or the higher-level SlidesLib) | None (from scratch); reference-based and reference-free eval | An 8B model on ~7k instruction→code pairs comes close to GPT-4o; a higher-level API helps but limits flexibility (critiqued by SlideCoder) |
| SlideCoder (arXiv 2506.07964, EMNLP 2025) | python-pptx code from a reference *image* | Colour-gradient segmentation + layout-aware prompt + hierarchical RAG of API patterns | Retrieving syntax patterns cuts code errors; reports up to +40.5 over baselines on layout fidelity/execution/visual consistency |
| DocPres (arXiv 2406.06556) | Text pipeline: hierarchical summary → outline → slide-section mapping → text → images | No layout selection | Outline-first decomposition beats single-shot LLM on coverage |
| SlideTailor (arXiv 2512.20292) | Paper → slides | "Template selector" assigns a template per planned slide from an aesthetic schema taken from a user template | Per-slide template choice as an explicit step |
| SlideGen (arXiv 2512.04529) | Paper → slides | 19 hand-curated layout templates chosen by each slide's assets | A small curated catalogue, chosen by content type |
| PPTBench (arXiv 2512.02624) | Benchmark, 4,439 samples (detect/understand/modify/generate) | n/a | Template-guided generation "significantly improves structural coherence" |
| SeaSlides (arXiv 2608.03298, Aug 2026) | **Semantic abstraction layer**: the model writes structured content with reusable components; templates own layout, styling, rendering; HTML and Typst backends | Template-defined DOM components / Typst functions | More readable, content-focused source than SVG-heavy generation across four models; curated templates beat task-generated templates in several settings; three feedback stages (build errors, constraint violations, visual defects) |

Sources: https://arxiv.org/abs/2501.03936 ; https://arxiv.org/abs/2501.00912 ; https://arxiv.org/abs/2506.07964 ; https://arxiv.org/abs/2406.06556 ; https://arxiv.org/abs/2512.20292 ; https://arxiv.org/abs/2512.04529 ; https://arxiv.org/abs/2512.02624 ; https://arxiv.org/abs/2608.03298

---

## 6. Export to PowerPoint and Google Slides: what breaks

Gathered from the tools above:

- **Image slides** (Marp/Slidev default PPTX, Nano Banana / GPT-Image modes) are not editable. Every "editable" retrofit (Slidev `pptx-editable`, Marp `--pptx-editable`, html2pptx, Canva Magic Layers, image-to-pptx skills) measures or re-detects boxes after the fact and loses fidelity.
- **Fonts:** Google Slides ignores fonts embedded in an uploaded .pptx and substitutes its own (Gamma help). Custom fonts are only safe in Google Slides if they are Google Fonts. PowerPoint without the font substitutes Calibri or Arial (Canva, Beautiful.ai). LibreOffice QA renders mislead on Georgia, Trebuchet, Garamond, Consolas, Calibri Light; Aptos is risky everywhere (Anthropic skill).
- **Masters and layouts into Google Slides:** custom masters and placeholders may be changed or lost; SmartArt becomes grouped shapes or a picture; complex animations simplify *(secondary)*.
- **Charts:** Gamma reportedly exports charts as images; pptxgenjs writes chart XML that PowerPoint rejects in two known cases (stacked `outEnd` labels, half-declared secondary axes), which other tools accept, so only PowerPoint itself is a true check (Anthropic validator).
- **Runtime-only behaviour** (Beautiful.ai smart layout, Gamma fluid cards, embeds) flattens on export.
- **Size:** Gamma fails on 150+ card exports; heavy images fail exports.

The tools with the best reported fidelity either *are* the native editor (Copilot, Claude for PowerPoint, Gemini) or **compile a closed vocabulary into DrawingML over the template's own master/layouts** (ppt-master, pandoc, Anthropic structured decks).

Sources: as cited in §3–§4; plus https://slidemodel.com/fix-compatibility-powerpoint-google-slides/ and https://www.brightcarbon.com/blog/convert-powerpoint-google-slides/ *(secondary)*.

---

## 7. Patterns

Each pattern: what it is, who uses it, pros and cons, and fit for Duo Decks (Markdown in git, Claude Code only, maybe no Python/Node, Swift + WebKit).

### P1. Outline-then-fill
Plan the deck (sections, one message per slide, which layout each slide uses), get approval, then write slides.
**Used by:** Gemini in Slides (approve outline first), Beautiful.ai, Kimi, Presenton, PPTAgent, ppt-master (Strategist with two confirmation stages), DocPres, SlideTailor, Claude Slides (`sections` written before slides), Anthropic 2025 skill (`outline.md` with `template_mapping`).
**Pros:** cheap to change direction; layout choice becomes a reviewable step; good for token use.
**Cons:** the outline can drift from the slides unless one is derived from the other.
**Fit: high.** In Duo the outline needn't be a separate artifact: a deck's Markdown with headings and `template:` lines *is* the outline, and Claude can write that skeleton first (each slide with its template and a one-line intent) before filling slots.

### P2. Layout catalogue with slot schemas
Each template declares named slots with types and limits (title: text ≤ N chars; bullets: list 2–5 items; image: picture, aspect; chart: data). The model picks a template per slide and fills a schema; validation rejects what doesn't fit.
**Used by:** Presenton Template V2 (JSON schema from non-decorative elements, repeat limits), SeaSlides (template components), SlideDeck AI (fixed JSON schema), Office-PowerPoint-MCP (`list_slide_templates`), Slidev (named layouts and slots), pandoc (seven implicit layouts), Copilot (placeholder type, size and position).
**Pros:** deterministic rendering; easy validation; small token footprint (the model writes content, not geometry); this is what PPTBench and SeaSlides find helps.
**Cons:** rigid; the catalogue needs enough variety, or every slide looks the same (the Anthropic skill warns against repeating layouts).
**Fit: core.** This is Duo Decks' central idea. The catalogue should be a text file Claude reads (template name, purpose, when to use it, slots with type, min/max, char budget), so Claude Code can choose without seeing pictures, and Duo's parser can reject a slide that names an unknown template or slot.

### P3. Template induction from existing decks
Feed real decks; derive reusable templates (structure, editable vs decorative, capacities, theme roles).
**Used by:** Presenton (vision passes plus certification), PPTAgent (clustering, functional types, content schemas), ppt-master Create Template (Brand/Style/Layout/Deck), Genspark and Kimi (.pptx as template; Kimi "document-to-skill"), Gamma (PPTX → theme), Copilot (sample slides as the main signal).
**Pros:** matches how Duo users will make templates ("turn these slides into templates"); keeps the customer's real master.
**Cons:** needs vision and many structured passes; the output must be *certified* (validated and capped), or templates are wrong in ways only seen later.
**Fit: high, as a Claude-run procedure with a Duo-side checker.** Claude Code can read a .pptx (it's XML) and look at thumbnails Duo renders; Duo should then validate the template definition deterministically (every slot maps to a real placeholder or shape in the source; capacities set; decorative elements marked) before the template is usable. Copy Presenton's split: one pass per concern, then a deterministic compile step.

### P4. Reference-slide cloning
Pick a real slide from the template deck, duplicate it with full package bookkeeping, then replace its content.
**Used by:** PPTAgent (core method), Anthropic skill (`add_slide.py`, 2025 `rearrange.py`), Copilot (sample slides first), ppt-master Edit Native PPTX, Gamma from-template.
**Pros:** highest visual fidelity (the slide *is* the brand's own artwork); handles decoration that isn't in layouts.
**Cons:** slots ≠ content (delete unused groups, not only their text); duplicated slides share chart/SmartArt parts unless cloned; heavy if done by the model in raw XML.
**Fit: high, but for the exporter, not for Claude.** In Duo a template can be "layout X of the .potx" *or* "sample slide N of the source deck". The exporter clones that slide and fills named shapes deterministically. Claude never touches OOXML.

### P5. Deterministic placeholder fill over a .potx
The template's slide master and layouts are the output's master and layouts; slide content goes into placeholders by name or idx; no positions on slides.
**Used by:** pandoc `--reference-doc`, Anthropic structured decks (`placeholder: "title"`), python-pptx tools, Copilot and Claude for PowerPoint (reading masters), ppt-master (Layout → master/layout/placeholder topology).
**Pros:** the exported deck stays a proper template-based deck in PowerPoint *and* in Google Slides (masters → Slides themes); restyle in one place; smallest possible diff between the source and the export.
**Cons:** placeholders can't express everything (cards, icon rows, stat callouts); PowerPoint autofit and wrap differ from any other renderer.
**Fit: core for export.** Swift can write OOXML directly (zip + XML), so no Python or Node is needed. The rule from Copilot applies: placeholders over text boxes, and don't shrink fonts (split instead).

### P6. Closed authoring vocabulary with a compiler
The model writes in a small, closed dialect; a compiler maps it deterministically to the renderer and to DrawingML; anything outside it is an error with a named fix.
**Used by:** Claude Slides (generated CSS subset table, build errors, lints), ppt-master (canonical SVG, checker, compatible-input normalisation), html2pptx (supported elements, overflow errors), SeaSlides, Slidev/Marp (Markdown + layouts).
**Pros:** errors caught before render; one source drives preview and export identically; diffs are meaningful.
**Cons:** the vocabulary must grow carefully; "compatible" spellings must not leak back into prompts (ppt-master's rule).
**Fit: core.** Duo's Markdown convention is this dialect. Copy ppt-master's three states (canonical / compatible with warning / invalid) and Claude Slides' style of error ("names the slide, the element and the closest supported change").

### P7. Semantic content, not coordinates
The model says *what* (title, claim, three cards, a chart of X), templates say *where and how*.
**Used by:** SeaSlides (central claim), Presenton, Slidev, pandoc; the opposite of html2pptx, AutoPresent and SlideCoder (code/coordinates).
**Pros:** short, readable, diffable source; rebrand without rewriting; fewer tokens.
**Cons:** less expressive per slide; one-off designs need a new template.
**Fit: core**, and it is the reason for Markdown over HTML. Geometry belongs in the template definition, never in the deck file.

### P8. Per-slide addressable units with stable ids
Each slide has an id that edits, comments and links key on; edits touch only named slides.
**Used by:** Claude Slides (`slides/<id>.html` + `order`), GLM agent (position field), Claude for PowerPoint ("pinpoint edits… without regenerating entire decks"), ppt-master (unchanged pages byte-for-byte), PPTAgent (per-slide actions).
**Pros:** targeted edits, small diffs, comments survive reordering, cheap context (read one slide).
**Cons:** a single-file deck needs ids written into it; per-file decks scatter the narrative in PRs.
**Fit: high.** For git diffs either works if ids are explicit. A single Markdown file with a stable `id` per slide keeps the narrative readable in one PR diff; per-slide files give cleaner conflicts. This is a decision for Duo (see open questions).

### P9. Targeted edit operations instead of regeneration
Edits are small, named operations (replace a span, clone a paragraph, delete an image, swap a template) or file-level patches; the rest of the deck is untouched.
**Used by:** PPTAgent edit API, Claude Code's own Edit tool on files (Claude Slides relies on it), Anthropic `replace.py` (by shape id), Office-PowerPoint-MCP tools. Counter-examples: SlideDeck AI, Gamma API from-template (regenerate).
**Pros:** preserves human edits; reviewable diffs; cheap.
**Cons:** needs good addressing (P8).
**Fit: free with Markdown.** Claude Code's Edit tool is already a patch engine. Duo needn't invent an edit API; it needs the format to be line-stable (one slot per line or block, no reflow on save).

### P10. Render-and-look validation loop
Render slides to images, have the model (ideally a fresh one) inspect them against a defect checklist, fix, re-render only changed slides.
**Used by:** Anthropic pptx skill (required; soffice → pdftoppm; subagent suggested), PPTAgent (external vision reviewer), ppt-master (opt-in), Presenton (`previewSlide`), SeaSlides (visual-defect stage). Deliberately rejected by Claude Slides ("NEVER VERIFY").
**Pros:** catches overflow, overlap and contrast that rules miss.
**Cons:** costly in tokens and time; renderer ≠ PowerPoint (LibreOffice font substitution), so a pass can lie.
**Fit: medium, as a Duo verb rather than a habit.** Duo can render a slide to PNG in WebKit (and maybe a second, OOXML-faithful render) and expose it through `duo2`, so Claude looks when asked or when a deterministic check flags risk. Default to P11 and use looking as the exception, as Claude Slides does.

### P11. Deterministic pre-render checks with named fixes
Validators that run without a model: schema, unknown templates/slots, text over capacity, missing assets, leftover placeholder text, package integrity.
**Used by:** Anthropic `validate.py` (every failure names its fix; `--original` baseline), html2pptx overflow errors, Claude Slides build errors and lints, ppt-master checker (early stage after 5 pages), Presenton certification, PPTAgent REPL errors.
**Pros:** cheap, reliable, scriptable in DuoChecks; good for PR review ("deck builds clean").
**Cons:** only as good as the capacity model.
**Fit: core.** Duo's parser should emit errors with line:col and a fix ("slot `bullets` on template `two-col` takes ≤5 items; 7 given: split the slide or use `three-col`"), and Claude reads them from `duo2`.

### P12. Text-capacity budgets per slot
Each slot carries a measured capacity (chars, lines, items) derived from its box, font and size; content over budget is an error, not a shrink.
**Used by:** Presenton text-capacity pass, Claude Slides (0.6 × font-size per char; "nothing shrinks"), Copilot (won't change font or placeholder size), Anthropic skill (floor sizes; split or cut), Beautiful.ai (auto-fit in runtime).
**Pros:** prevents the commonest defect (overflow) before any render.
**Cons:** estimates differ by renderer; PowerPoint autofit may disagree.
**Fit: high.** Duo can measure with CoreText against the template's real font and box (more accurate than a 0.6 rule), store the budget in the template definition, and check it in the parser. Template creation should compute it once.

### P13. Separate identity, structure and direction
Keep brand (colours, fonts, logo, voice), layout structure (masters, layouts, slots) and style guidance (how to write slides) in separate, combinable pieces.
**Used by:** ppt-master Brand/Style/Layout/Deck, Copilot brand kits (templates + colours + voice), Claude design systems (tokens installed into decks), Gamma themes, Kimi skills (prose rules).
**Pros:** one layout set across brands, one brand across layout sets; guidance for Claude lives in text it reads.
**Cons:** more concepts for users.
**Fit: medium-high.** Duo's project-vs-user template scoping maps onto this: a user's brand plus a project's layouts. At minimum, a template pack should have a machine part (slots, capacities, source .potx) and a prose part for Claude (when to use each template, voice).

### P14. Native objects over pictures
Charts, tables and diagrams export as native, data-backed PowerPoint objects; images only for what PowerPoint can't draw.
**Used by:** Anthropic skill ("Keep charts native"), ppt-master (`--native-charts-and-tables`), Kimi (native charts, SmartArt), Manus PowerPoint mode, Claude for PowerPoint, Gamma (editable tables, not charts).
**Fit: high for export, later for v1.** Charts as data in Markdown (a fenced table or CSV) map naturally to a chart slot and to `c:chart` XML; worth scheduling after text and picture slots.

---

## 8. Anti-patterns seen

1. **Slides as images.** Marp/Slidev default PPTX; Nano Banana and GPT-Image slide modes (Manus, Genspark Creative, Kimi Visual). Not editable, not diffable, not brand-compliant; every fix is a lossy re-detection.
2. **Free-form HTML/CSS converted to PPTX by measuring a browser.** html2pptx (dropped by Anthropic, Feb 2026), Slidev `pptx-editable`, Marp `--pptx-editable`. Browser layout ≠ PowerPoint layout; text outside the right tags silently vanishes; gradients and effects need rasterising; needs Chromium/Playwright.
3. **The model editing raw OOXML.** Verbose (one slide = 1,006 lines in PPTAgent's example), namespace-fragile (`ElementTree` rewrites prefixes and corrupts decks), and order-sensitive (`<p:presentation>` children). Fine as a last resort with validators; wrong as the editing surface.
4. **Regenerating the whole deck for every change.** SlideDeck AI's instruction history, Gamma's from-template API. Loses human edits; diffs are total.
5. **A runtime-only layout engine.** Beautiful.ai smart slides and Gamma fluid cards look right only inside the app; export flattens them.
6. **A proprietary hosted store.** Tome closed and deleted content. Text in the user's git repo avoids this.
7. **Imperative tool-call editing with no source document.** Office-PowerPoint-MCP style: there is nothing to review in a PR except a binary.
8. **Placeholder text as instructions / leftover sample text.** Copilot explicitly ignores placeholder wording; the Anthropic skill greps for lorem/XXX/[insert]. Template slots should carry their guidance in metadata, not in sample text that can leak.
9. **Shrinking text to fit.** Defeats brand type scales; Copilot, Claude Slides and the Anthropic skill all refuse it (split or cut instead).
10. **Layouts with more slots than content.** Filling a 4-up with 3 items, using a quote layout for emphasis (Anthropic 2025 rules); "Template slots ≠ source items".
11. **Trusting a substitute renderer for fit.** LibreOffice QA with fonts it substitutes; Google Slides ignoring embedded fonts. A preview that disagrees with PowerPoint is worse than no preview.
12. **Repeating one layout.** Every slide on title-and-bullets; a catalogue with too few templates produces this.
13. **Decorative AI tells.** Accent lines under titles, edge stripes, cream backgrounds, default blue (Anthropic skill's Avoid list). Relevant when Claude makes templates from scratch.
14. **Unverified "editable" claims.** "Editable PPTX" where charts are shapes or pictures, or text boxes stand in for placeholders. Measure the export, not the marketing.

---

## 9. What this means for Duo Decks

The landscape divides into three camps:

- **The native editors** (Copilot, Claude for PowerPoint, Gemini) are perfectly faithful but keep no text source and no PR diffs.
- **The hosted apps** (Gamma, Beautiful.ai, Pitch, Canva, Tome, Manus, Genspark) use proprietary storage and export with losses.
- **The agent workflows** (Anthropic skill, Claude Slides, ppt-master, PPTAgent, Presenton, pandoc, Slidev) keep a text source and compile it.

Duo Decks belongs in the third camp. Its specific bet, *Markdown that names templates, plus template definitions, compiled deterministically*, is a combination no tool ships as a whole. The pieces exist separately: pandoc for Markdown → .potx placeholders, Slidev for Markdown that names layouts and slots, Presenton for slot schemas and capacities induced from a PPTX, ppt-master for a closed dialect plus a checker plus a native compiler, Claude Slides for per-slide ids and "nothing shrinks".

Constraints that shape the choices:
- **No Python/Node on the user's Mac** rules out the pptx skill's toolchain (pptxgenjs, python-pptx, LibreOffice, pdftoppm) as a *runtime* dependency. Duo must parse, render, check and export in Swift. OOXML is zip + XML, and Duo can clone layouts and sample slides and fill placeholders itself. Claude Code can still *read* .pptx files (unzip and XML) when building templates.
- **WebKit preview vs PowerPoint output** is the main fidelity risk, the same one that sank html2pptx. Drive both from the same template geometry (EMU boxes from the source .potx/.pptx) and the same CoreText measurements, and treat the WebKit view as a preview of placeholders, not as the layout authority.
- **Claude Code only, CLI login:** no vision API calls from Duo. Claude Code can view PNGs Duo writes, so template induction (P3) and opt-in looking (P10) run inside the user's Claude session, driven by `duo2` verbs.
- **Google Slides last hop:** use placeholders and layouts (they become a Slides theme), Google Fonts or safe fonts, native tables; avoid SmartArt and effects.

Questions this raises for the design (not decided here):
1. One Markdown file per deck with explicit slide ids, or one file per slide plus an index (Claude Slides' choice)?
2. Is a template a *layout of the .potx*, a *sample slide of the source deck*, or either? (Copilot and PPTAgent say sample slides carry the most signal.)
3. Where do capacities come from: measured by Duo at template creation (CoreText), declared by Claude, or both with Duo checking?
4. How much free composition (cards, icon rows) is allowed inside a slot, if any, without breaking "every slide uses a defined template"?
5. Does Duo ship a render-and-look verb (`duo2 deck render <slide>`), and is looking ever the default?

---

## 10. All sources

Anthropic: local pptx skill (path in §2.1); https://github.com/anthropics/skills ; https://claude.ai/artifact/8jTsAFQMFDb2oA8MsPJ2eL ; https://claude.com/docs/office-agents/powerpoint ; https://support.claude.com/en/articles/13521390-use-claude-in-powerpoint

Products: https://developers.gamma.app/docs/generate-api-parameters-explained ; https://developers.gamma.app/generations/create-from-template.md ; https://help.gamma.app/en/articles/8022861-how-do-i-export-my-gamma ; https://help.gamma.app/en/articles/15939201-why-doesnt-my-exported-pdf-or-powerpoint-match-what-i-see-in-gamma ; https://help.gamma.app/en/articles/11047840-how-can-i-import-slides-or-documents-into-gamma ; https://www.chatslide.ai/articles/tome-ai-shut-down-what-happened ; https://beautiful.ai/smart-slides ; https://support.beautiful.ai/hc/en-us/articles/30629528652685-Exporting-your-slides-and-presentations ; https://www.beautiful.ai/blog/how-to-export-to-ppt-and-why-you-shouldnt ; https://help.pitch.com/en/articles/4615453-import-a-presentation ; https://www.pitch.com/integrations/ppt-export ; https://support.microsoft.com/en-US/PowerPoint/copilot/keep-your-presentation-on-brand-with-copilot ; https://support.microsoft.com/en-us/PowerPoint/copilot-tutorial-create-a-branded-presentation-from-a-file ; https://support.microsoft.com/en-gb/office/frequently-asked-questions-about-copilot-in-powerpoint-3e229188-9086-4f4c-9f9f-824cd25ae84f ; https://mc.merill.net/message/MC1267867 ; https://workspaceupdates.googleblog.com/2026/06/create-fully-native-and-editable-presentations-with-Gemini-in-Google-Slides.html ; https://www.canva.com/newsroom/news/magic-layers ; https://manus.im/blog/manus-ppt-slides ; https://www.manus.im/docs/integrations/nano-banana-pro ; https://genspark.ai/tools/ai-powerpoint-generator ; https://www.genspark.ai/docs/ai_slides_changelog ; https://www.kimi.com/resources/ppt-skills-for-agents ; https://docs.z.ai/guides/agents/slide.md ; https://docs.bigmodel.cn/cn/guide/agents/glm-ppt.md

Open source: https://github.com/presenton/presenton (docs/template-v2.md) ; https://github.com/icip-cas/PPTAgent ; https://github.com/hugohe3/ppt-master (docs/technical-design.md, docs/templates-architecture.md) ; https://github.com/barun-saha/slide-deck-ai ; https://github.com/GongRzhe/Office-PowerPoint-MCP-Server ; https://sli.dev/guide/layout ; https://sli.dev/features/slot-sugar ; https://sli.dev/guide/exporting ; https://github.com/marp-team/marp-cli ; https://www.nuget.org/packages/MarpToPptx ; https://pandoc.org/MANUAL.html

Papers: https://arxiv.org/abs/2501.03936 ; https://arxiv.org/abs/2501.00912 ; https://arxiv.org/abs/2506.07964 ; https://arxiv.org/abs/2406.06556 ; https://arxiv.org/abs/2512.20292 ; https://arxiv.org/abs/2512.04529 ; https://arxiv.org/abs/2512.02624 ; https://arxiv.org/abs/2608.03298

Secondary (weak evidence, used only where marked): https://deckary.com/blog/tome-review ; https://dealroom.co/news/149823-ai-crm-startup-lightfield-raises-47m-series-a-led-by-a16z/ ; https://buildfastwithai.com/ai-tools/canva-magic-design ; https://pasqualepillitteri.it/en/news/9713/kimi-slides-prompt-to-editable-pptx-k3 ; https://slidemodel.com/fix-compatibility-powerpoint-google-slides/ ; https://www.brightcarbon.com/blog/convert-powerpoint-google-slides/
