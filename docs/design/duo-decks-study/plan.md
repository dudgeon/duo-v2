# Duo Decks: the plan

Status: **proposed, waiting on Geoff** (Q-348 to Q-356; DL-267 to DL-270 are kept for his answers). Every mark on the canvases is [P]. Nothing here is built, and none of it is for 0.2.22.

The research is in four reports beside this file:
- `research-agentic-landscape.md`: how other tools and agents make decks.
- `research-formats.md`: text-first formats and pptx libraries.
- `research-pptx-google-and-templates.md`: pptx through Google Slides, and template extraction.
- `research-duo-context.md`: what Duo already has.

The prototype is `prototypes/compile/deck.py`, run on `samples/`.

## 1. The idea in one paragraph

A deck is a Markdown file. Every slide names a template and fills that template's slots, and nothing else is allowed. A template is a real layout in a real PowerPoint file, and its slots are that layout's placeholders. A short definition beside the pptx gives each template a name, a purpose and limits. Duo checks a deck against its templates deterministically. It writes the deck as a pptx by filling those placeholders, and shows you that same pptx in its existing slide viewer. Claude writes and edits the Markdown, and asks Duo to check it, the way a programmer runs a compiler. Templates come from your existing decks: Claude reads a deck with Duo's help, proposes templates, and Duo builds them. You never draw a template in Duo, and you never edit slides in Duo; you edit the text.

## 2. What the research says, briefly

1. **Nobody ships this whole combination, but every piece exists** (landscape §9).
   - pandoc fills a corporate reference.pptx's real placeholders, but picks among only 7 layouts and infers which itself.
   - Slidev and Obsidian Advanced Slides name a layout per slide and fill named slots, but export pictures or loose text boxes.
   - Presenton and PPTAgent turn existing decks into slot schemas with limits.
   - ppt-master and Claude's own Slides artifact type constrain the model with a closed vocabulary and a checker that names the fix.
   - Claude's Slides type also keeps slide ids stable and says "nothing shrinks; split the slide".
   - Anthropic's pptx skill dropped html2pptx in February 2026 for masters plus placeholder filling.
2. **Markdown is cheap and diffs cleanly.**
   - A 10-slide deck is 260–430 tokens of Markdown, against about 3,100 for pandoc's minimal slide XML (formats, "Token cost"). The sample deck is 1,726 characters; its exported slide XML is 22,911.
   - A one-word edit is a one-line diff in every Markdown dialect. The format barely matters; keeping the pptx out of review does (F-464).
3. **Google Slides keeps the structure that matters** (tested, F-460):
   - It keeps the layout link, placeholder type and idx, exact geometry, and theme colour references.
   - It renames layouts and shapes, flattens inherited formatting into every run, and rewrites theme fonts to resolved ones.
   - A placeholder-filled deck stays editable and can be mapped back onto its template. Absolute text boxes look the same but can't.
4. **No Swift pptx writer exists, and Duo has none** (F-463).
   - Duo already reads OOXML (`Pptx.Zip` and `Pptx.swift` in DuoSearch, which `duo2` links) and draws any pptx with the vendored `@aiden0z/pptx-renderer`.
   - A writer is about 1–2k lines of Swift: placeholder fill on a template package, plus a small zip writer.
5. **The work Mac** (research-duo-context §7):
   - Can't count on Python, Node or LibreOffice there.
   - `duo2` verbs are allowed by record: they ship inside the signed app.
   - A `local` verb runs in the CLI with Duo closed, and inside Claude's sandbox.
   - Claude Code 2.1.284 reads skills.

## 3. The system in three layers

The rule for placing a piece: **anything that must give the same answer every time is the application's**. Anything that needs judgement or language is the agent's. Anything that has to survive both, and be read by people and other tools, is context on disk.

### 3.1 Context: files on disk

| File | What it is | Who writes it |
|---|---|---|
| `decks/<name>.md` (anywhere in a project) | The deck. Frontmatter `type: deck` (first key, OKF), `title`, `template: <pack>`, optional `footer`. Then slides. | People and Claude |
| `decks/assets/…` | Images the deck links to, with relative Markdown links (DL-17). | People and Claude |
| `templates/decks/<pack>/<pack>.pptx` | The template package: theme, masters and layouts, with no slides. It's a copy of a real deck or a .potx, with slides removed and "promoted" layouts added. | `duo2 deck template build` |
| `templates/decks/<pack>/<pack>.md` | The definition: `type: deck-template` frontmatter, then one `## <template>` section per template, each a purpose sentence and a `yaml` block of slots. Lines marked `# duo` are written and checked by Duo; names, purposes and limits are Claude's or yours. | Both (sample: `samples/templates/decks/northwind/northwind.md`) |
| `<deck>.pptx` | The export. Deterministic bytes (fixed zip times and part order), so committing it doesn't churn. Whether it's committed at all is Q-354. | `duo2 deck export` |

**Scope** follows DL-146's file templates:
- **Lookup:** a project's `templates/decks/<pack>/`, then Home's, then Duo's built-in pack.
- **User level** means Home's folder, which is in git, as file templates are. It doesn't mean the support folder, which holds machine state only (DL-53).
- **A project pack** with the same name wins.
- **Built-in pack:** one plain pack (Google Fonts, about 8 templates, original artwork) so a deck can be made before any import.

**The deck convention** (sample: `samples/decks/field-trial-review.md`):

```markdown
---
type: deck
title: Field trial review, Q3
template: northwind
---

<!-- slide: kpi -->
# Unattended rows

## value
86%

## label
of rows finished with no one stepping in

## context
Up from 61% in the spring trial, over 412 rows on three farms.

> [!note]
> Pause here.

---
```

- `<!-- slide: <template> -->` **starts a slide**. It's an HTML comment, so Obsidian's and GitHub's rendered views hide it.
  - `---` between slides is a convention for people reading the file: in Obsidian it draws a rule. Separators never decide where a slide ends, so a setext heading or a frontmatter fence can't be mistaken for one.
- The slide's first `# ` heading fills the `title` slot.
- `## <slot>` starts a named slot, which runs until the next `##`, note or slide. The checker caught exactly this mistake in the sample (`samples/pr/check-output.txt`).
- Text with no slot heading fills the template's `default` slot. A lone image line fills its single image slot.
- `> [!note]` is the speaker notes: an Obsidian callout, which reads properly in GitHub too.
- Each slot kind takes one kind of Markdown:
  - **text** and **number:** a sentence, with `**bold**`, `*italic*` and links;
  - **bullets:** a list, nested to the template's `levels`;
  - **image:** `![alt](path)`;
  - **table:** a GFM table, one line per row (DL-113).
  - Anything else is an error, not a guess.
- **Diff discipline:** one bullet per line and no hard wrapping. Then a changed word changes one line.

**Why not frontmatter per slide** (Slidev's form): Obsidian shows a YAML block between `---` lines as body text and a rule. The checker would also have to tell those blocks apart from the file's real frontmatter. **Why not inline fields** (`value:: 86%`): they're shorter, but they're a second slot syntax to learn, and they render as plain text. Q-352 asks Geoff to choose between headings and inline fields.

### 3.2 Application: deterministic, in Swift, small

| Piece | Where | Notes |
|---|---|---|
| **Parser** | DuoSearch (shared by app and `duo2`) | The deck becomes slides, and each slide becomes slots with source line ranges. About 300 lines. The ranges are what let a click on a slide find its line. |
| **Checker** | DuoSearch | Unknown template or slot, wrong kind, over a limit, missing image, more nesting than allowed. Every error names `file:line`, the slide, the slot and a fix (`samples/pr/check-output.txt`). Slot limits are characters, items and lines from the definition. Later, a CoreText fit check against the placeholder's real box (P2). |
| **Writer** | DuoSearch | Opens the pack's pptx and adds one slide per Markdown slide on the named layout. It fills placeholders by idx only, with no geometry of its own, and clones the footer and slide-number placeholders, which python-pptx leaves off (F-466). It writes notes, puts pictures into picture placeholders (crop to fill) and tables into table placeholders, and emits scheme colours, not RGB. The zip writer sits beside `Pptx.Zip`: deflate through Compression, CRC-32 from libz, fixed timestamps. About 1–2k lines with tests. |
| **Viewer** | App | A `type: deck` Markdown file gets a **Slides** view: the writer's pptx drawn by the existing `pptx-renderer` web view (DL-121, DL-125). So **what you see is the export**, byte for byte. Source and slides sit side by side. |
| **Verbs** (DL-71) | `duo2 deck …`, mostly `local` | `deck templates [<deck>]`: the compact catalogue Claude reads instead of any pptx. `deck check <deck>`. `deck export <deck> [--out]`. `deck render <deck> [<n>]`: a PNG, to look on request. `deck template inventory <pptx>`, `deck template build <pack>` and `deck template specimen <pack>`. Viewer verbs mirror `slide`: `deck`, `deck go <n>`, `deck pick`. |

**Not in the application:**
- **No WYSIWYG slide editor and no template editor.** Text is edited in the source. Layouts are edited in PowerPoint, Keynote or Google Slides, wherever the template came from, then rebuilt with `deck template build`. Nothing in the research says a template editor is needed: every tool that induces templates (Presenton, PPTAgent, ppt-master, Copilot's brand kits) does it from existing decks.
- **No layout logic.** Geometry lives only in the template pptx. Duo never positions text.
- **No model calls.** CLI login only, so judgement stays with Claude.

### 3.3 Agent: what Claude is taught

**A "Decks" section in the generated duo2 skill** (`Installer.skill()`, beside "Checking documents"; about 250 words; it reaches Claude Code 2.1.284), saying:
- A deck is a `.md` with `type: deck`. Before writing, run `duo2 deck templates <deck>` and use only those templates and slots. Never open the template's pptx.
- Write one bullet per line, no hard wrapping, and no Markdown a slot doesn't take.
- When content doesn't fit, split the slide or cut words. Never ask for a smaller font, and never add a template.
- After every edit, run `duo2 deck check <deck>` and fix every problem it names before you stop.
- Don't run python-pptx, pptxgenjs or `soffice`. Look only when asked, with `duo2 deck render`.
- **Making templates:**
  1. `duo2 deck template inventory <pptx>`.
  2. With the user, pick the slides that become templates. Name each one and its slots, write the purpose and the limits, and mark which shapes are decoration.
  3. `duo2 deck template build`, then `duo2 deck template specimen`, and show the user the specimen deck.
  4. Never invent a template the user hasn't approved.

**What stays in judgement:**
- Choosing a template per slide.
- Splitting and compressing content.
- Naming slots, and estimating limits when making templates.
- Deciding which shapes are decoration.
- Writing for a slide's job.

These are exactly the parts the research shows models do well (Presenton's semantic passes; PPTAgent's schemas). They're also the parts a deterministic tool can't do.

**What the agent is not trusted with:**
- Geometry.
- Placeholder ids.
- Theme values.
- The bytes of the pptx.

PPTAgent's ablations show schemas carry a large share of the quality (95.0% success falls to 78.8% without them). The Slides artifact's "never verify unless asked" works because its checker is strict. Duo's checker gives Claude the same footing.

## 4. Template extraction, step by step

1. **Inventory (Duo, deterministic).** `duo2 deck template inventory Q2.pptx` lists:
   - every layout: placeholders with type, idx, box, font size and autofit; decoration shapes;
   - every slide: its layout and shapes, with name, box and text;
   - the theme's colours and fonts;
   - fonts Google lacks, flagged.
   - Prototype: `prototypes/pptx/inventory.py`.
2. **Proposal (Claude, with you).** Claude reads the inventory, and the slide pictures if you ask. It proposes templates: which layout or slide becomes which template, slot names, kinds, purposes and limits. It writes the definition `.md`.
3. **Build (Duo, deterministic).** `duo2 deck template build <pack>`:
   - copies theme, masters and the chosen layouts into `<pack>.pptx` and removes the slides;
   - **promotes** a template that came from an ordinary slide (free text boxes on a Blank layout, common in real decks) into a new layout. The slot boxes become placeholders (idx 13 and up; 10–12 are date, footer and number), with the slot's type style, and the decoration moves onto the layout;
   - fills the `# duo` lines (layout name, fingerprint, idx) and checks Claude's lines against the pptx.
4. **Specimen (Duo).** `duo2 deck template specimen <pack>` writes a deck that uses every template once, with sample text at each slot's limit. You look at it in the viewer and say what's wrong. Claude edits the definition, and step 3 runs again.

What Claude can't see from a picture, and Duo must read from the XML (research-pptx §4.2):
- idx;
- `buNone` versus bulleted bodies;
- inherited sizes;
- autofit;
- `showMasterSp`;
- layout backgrounds.

What the XML doesn't say, and Claude adds:
- which three body boxes are value, label and context;
- that a quote mark is ornament;
- how much text a caption takes;
- when to use each template.

## 5. Path dependencies

Earlier choices fix later ones. In order of how hard they are to undo:

1. **What a template is (Q-349).** *A layout in a real pptx* means:
   - the exporter must be a placeholder-fill writer over that pptx;
   - Google fidelity is as good as it gets (F-460);
   - there's no template editor in Duo, because PowerPoint, Keynote or Google is the editor;
   - extraction includes promotion.

   *Duo-native geometry* (templates in YAML or CSS) would instead mean:
   - an HTML renderer;
   - building every pptx from nothing;
   - losing the corporate master in PowerPoint and Google;
   - and a template editor would follow, because nothing else could edit them.

   This is the most binding choice. Every product that chose native geometry (Gamma, Beautiful.ai, Pitch) loses fidelity on export.
2. **The renderer (Q-350).** *Draw the export* (the writer plus the existing pptx-renderer):
   - needs the writer in the first slice;
   - in return, there's one engine and no drift between preview and file. That drift is what sank html2pptx.

   *A separate HTML renderer:*
   - ships a preview sooner;
   - then every template feature has to be built twice and kept in step;
   - the preview lies wherever the two differ.
3. **The export engine (Q-351).**
   - *Own Swift writer:* a `local` verb that runs on the work Mac, with no licence burden and deterministic bytes.
   - *pandoc.wasm:* 62 MB and GPL, and stuck on 7 inferred layouts.
   - *pptxgenjs:* can't open a template.
   - *Claude running python-pptx:* breaks on the work Mac and gives non-deterministic output.

   Once the writer exists, the viewer, the checker's fit test and Google upload all build on it.
4. **The source format (Q-348, Q-352).**
   - It fixes the parser, the skill's wording, the diff story and how decks read in Obsidian and GitHub.
   - It's the easiest to change later: the parser is deterministic, so a converter between two conventions is a small job.
   - But every deck written before a change needs that conversion, so choose before phase 1 ships.
5. **Google upload** depends on the Google Docs work's Checkpoint 1: one Duo Google app with the `drive.file` scope (Q-309 to Q-316, open). Until then the user uploads the pptx by hand. Deciding Duo Decks doesn't wait on it.

```
template model ──► export engine ──► viewer ──► picker, slot errors on slides, inline edit (later)
      │                  │
      │                  └──► Google upload (after gdocs Checkpoint 1) ──► import back (later)
      └──► extraction (inventory, promote, specimen)
source format ──► parser/checker ──► skill text, diff story, Obsidian
```

## 6. Phases, each usable on its own

**P0, spike (Sonnet, about S; nothing visible).**
- The Swift writer: the Northwind pack plus the sample deck gives a pptx, drawn by pptx-renderer and opened by LibreOffice.
- The Google test finished over a byte-exact upload path (Q-355): template, both decks, a table, a chart and a gradient, then the re-export diffed.
- Settles C-130 and the font policy (Q-356).

**P1, "write a deck, see it, export it" (Sonnet build, about M; first useful slice).**
- The convention, parser and checker.
- `duo2 deck templates|check|export`, all local.
- The skill section and the built-in plain pack.
- A deck file opens as source beside its slides, drawn from the export.
- A hand-written definition works for any pptx whose layouts already have placeholders.
- You can write a deck with Claude, read it as slides, review it in a PR, and hand a pptx to Google.

**P2, "templates from your decks" (about M).**
- `deck template inventory|build|specimen`, including promotion of slide-based templates.
- The fit check measured with CoreText.
- The skill's template steps.
- The way most templates will arrive, per Geoff's request.

**P3, "the viewer earns its keep" (about M; design first, DL-26).**
- Click a slide's text to go to its line.
- Select Shape names the slot, and Send to Claude says `slide 3 (kpi), slot value`.
- Problems shown on their slides.
- The `deck`, `deck go` and `deck pick` verbs.
- Assets dropped onto a slide land in `assets/`.

**P4, "to Google" (after gdocs Checkpoint 1).**
- Export to Google Slides through Duo's Google app.
- A deck that was exported before updates the same presentation if Drive allows it (Q-353 asks whether to replace or make new).

**Later (ENH):**
- Typing on a rendered slide (ENH-296).
- Bringing a Google or PowerPoint deck back into Markdown by template fingerprint (ENH-297).
- Sample-slide cloning for art that won't promote (ENH-298).
- Charts from a table (ENH-299).
- SmartArt is never emitted; groups of shapes instead.

## 7. The diff and PR story

**What a reviewer sees.** A teammate's PR changes a number, adds a slide and adds an ask. GitHub's diff (`samples/pr/field-trial-review.diff`):

```diff
@@ -29,13 +29,13 @@
 # Unattended rows

 ## value
-86%
+88%
 ...
+<!-- slide: bullets -->
+# What still breaks
+
+- Mud on the camera after heavy rain
+- Rows narrower than 2.4 m
+
+---
```

- Each hunk carries the slide's `# ` title and slot heading in its context lines, so a reviewer knows which slide and which slot.
- GitHub's "rich diff" for Markdown renders the same change as headings and bullets (the comment marker is hidden).

**What a reviewer can't see on GitHub:** the slides. Geoff's rule is no CI for builds, so there is no rendering Action. Instead:
- The author runs `duo2 deck export` before merging, and can paste `duo2 deck render` images into the PR.
- In Duo, opening the PR's branch shows the slides.
- `duo2 deck diff <base>` (P3) lists slides changed, added and moved, by title.
- A template change is reviewed in its definition `.md` and its specimen. The pack's pptx is binary and changes rarely.

**Reordering slides** shows as one block removed and the same block added. That's readable, but long. Moves stay legible because each slide is one contiguous block that starts with its marker.

## 8. Risks

| Risk | How bad | What we do |
|---|---|---|
| **The viewer and PowerPoint or Google disagree** (fonts: Calibri isn't on a Mac without Office; pptx-renderer falls back) | Medium | C-130. Templates record a Google-safe font. Inventory flags fonts Google lacks. The viewer says which font it substituted. |
| **Google fidelity on tables, charts and gradients is unproven** | Medium | Q-355: finish the test in P0. Charts are out of v1; emit native tables. Never emit SmartArt. |
| **Corporate templates and decks in git repos** (a work pack in a public repo) | Medium | C-131. Packs live in the project, or in Home, which is the user's own repo. Duo never ships or uploads them. The built-in pack is original. |
| **Template limits are guesses** (characters aren't space) | Low | Limits are guidance, and P2 adds a CoreText fit check against the real box. Overflow is an error to split, never a font shrink. |
| **Token cost** | Low | Claude reads `deck templates` (about 400 tokens for 8 templates), never a pptx. The sample 9-slide deck is about 430 tokens. |
| **Diff readability** | Low | One bullet per line, no wrapping, slides as contiguous blocks, the pptx kept out of review. |
| **Work Mac** | Low | Everything Claude runs is a `duo2` verb in the signed app. No Python, Node or LibreOffice. The skill reaches 2.1.284. |
| **Licences** | Low | Own writer; pptx-renderer is Apache-2.0 and already shipped. No pandoc (GPL). The user's pack is their own. |
| **The writer grows into an Office clone** | Medium | C-132. Only what placeholders take: text runs, bullets, pictures, tables, notes. Anything else is ENH, case by case. |
| **The Markdown rules feel strict** | Low | Strictness is the point (Geoff: "can't make arbitrary slide layouts without making it a template"). Errors always name the fix. |

## 9. The decisions for Geoff

Each lists the recommendation first. The narrative page sets out the trade-offs, and the canvas draws them.

- **Q-348 → DL-267. The source format.**
  - (A) One Markdown file per deck, `<!-- slide: t -->` markers, `## slot` headings, notes as a callout [recommended].
  - (B) One file per slide, plus an index.
  - (C) Slidev-style per-slide frontmatter.
  - (D) YAML or JSON slot data.
- **Q-349 → DL-268. What a template is.**
  - (A) A layout in a real pptx, plus a definition `.md`; slide-based templates promoted to layouts [recommended].
  - (B) A sample slide that is cloned.
  - (C) Duo-native geometry.
  - (D) A and B both, from the start.
- **Q-350 → DL-269. The viewer and editor.**
  - (A) Source beside slides, where the slides are the export drawn by the existing renderer [recommended].
  - (B) A separate HTML preview, live per keystroke.
  - (C) Slides only, with text edited on the slide.
  - (D) Source only, plus Export.
- **Q-351 → DL-270. Export and Google.**
  - (A) Own Swift writer as a local `duo2` verb; upload by hand until Duo's Google app exists [recommended].
  - (B) The same, but wait for Google upload before shipping.
  - (C) Bundle pandoc.wasm.
  - (D) Teach Claude to run python-pptx.

Smaller questions:
- **Q-352:** slot syntax: headings or inline fields.
- **Q-353:** re-export to Google: replace or make new.
- **Q-354:** commit the exported pptx: no / on release / always.
- **Q-355:** finish the Google test with Claude in Chrome's file upload in Geoff's Chrome.
- **Q-356:** fonts: Google Fonts required in packs, or a recorded substitute.
