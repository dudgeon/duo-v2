# Duo Decks, end to end: the key moments

Status: **proposed** (every new mark [P]). Geoff asked for this on 2026-10-31:
- an explainer film, "kind of like a PRFAQ", that walks the whole Duo Decks life cycle in one shot, with real or simulated UI;
- real errors along the way;
- a feature definition updated for the issues the walk-through surfaces, such as a layout change that breaks the content mapping;
- things not yet discussed but likely needed, such as quick selection or autocomplete of template names.

This document is the source for that film. It also extends `plan.md`: each moment below says what is on screen, who does what (you, Claude, Duo), what goes wrong, and how it resolves. New questions are Q-377 to Q-386. Decided so far: DL-267 (format), DL-268 (templates), DL-270 (writer, verbs, always commit the pptx). The viewer is open (Q-350) and waits for split view. Here it is drawn as S1, source and slides side by side, because that's the leaning.

## The world (synthetic)

- **Northwind Labs**, an orchard-robotics company, and its field team's Duo project `orchard-robotics`.
- **The person** is a product lead on that team (unnamed in the film; "you").
- **The source deck** is `northwind-q2-review.pptx`, a 14-slide company deck made by hand in PowerPoint. Some slides sit on proper layouts; others are loose text boxes on Blank.
- **The notes** are `notes/autumn-trial-log.md`, field notes from the autumn trial.
- **The new deck** is `decks/autumn-trial.md`.
- **A teammate** sends a pull request later. Shown by role, never named.

All of it is generated from one data file (`video/fixture/world.json`, made by the film's worker). Nothing is real work content.

## The press release (the film's opening, about 15 s)

> **Duo Decks.** Write slide decks with Claude in plain Markdown, held to your own company templates, reviewed in pull requests like code, and shipped as a PowerPoint file that opens properly in Google Slides. You never draw a template, and Claude never draws a slide.

The FAQ is the rest of the film. Each moment answers one question a sceptical reader would ask.

## The moments

### M1 · "Where do templates come from?" Pick a template deck

**On screen.** The project, with `northwind-q2-review.pptx` in Files. You open it: the existing deck viewer (DL-125), slides down the pane.

**New [P]: Make Templates…** in the deck viewer's bar, next to Select Shape. It turns on **slide selection**:
- each slide gets a check box at its top left;
- the bar reads "Pick the slides to make into templates · 3 picked";
- the buttons are **Make Templates with Claude** (default), Cancel.

You tick slides 3 (bullets), 7 (a quote) and 12 (a big number).

**What happens.** Make Templates with Claude pastes into Claude's prompt, without Return, as Select Shape does:
- the file and the picked slides;
- the line `duo2 deck template inventory "northwind-q2-review.pptx" --slides 3,7,12`.

You add "call the pack northwind" and press Return.

**Verbs.** `duo2 deck template pick` turns selection on. `duo2 deck template picked` lists the picked slides. (DL-71)

**Q-377.** Is Make Templates… a deck-viewer action (proposed), a Files context-menu item, or only something you ask Claude for? Proposed: the viewer action, because you choose slides by seeing them.

### M2 · "How does a slide become a template?" Inventory and mapping

**On screen.** Claude's session beside the deck. Claude runs the inventory. The output scrolls: layouts, slide 3 on "Title and Content" with placeholders, slides 7 and 12 on Blank with loose boxes, fonts.

**Error 1: a font Google lacks.** The inventory flags `Avenir Next (heading): not in Google Fonts`.
- Claude asks you, by its own question card in chat, with buttons: Nunito Sans (closest, recommended), Montserrat, or keep Avenir Next and accept substitution.
- You pick Nunito Sans. This is DL-268's recorded substitute.

**Error 2: an ambiguous slide.** On slide 12, two text boxes are the same size and the same 18 pt: "of rows finished…" and "Up from 61%…". The XML can't say which is the label and which is the context.
- Claude says which it thinks is which, from position and wording, and asks to confirm.
- The rule: **Claude never guesses silently. Anything it can't decide from the XML or the words is a question to you.**

**What happens.** Claude writes `templates/decks/northwind/northwind.md`, three sections, each with a purpose line, slot names, kinds and limits.

**Q-378.** When the mapping is ambiguous, does Claude always ask, or decide and list its guesses for review? Proposed: ask when two readings would change what goes where; list when it's naming only.

### M3 · "What does Duo do that Claude doesn't?" Build and specimen

**On screen.** Claude runs `duo2 deck template build northwind`. Duo:
- copies the theme and masters;
- promotes slides 7 and 12 to real layouts ("Quote", "Big Number");
- removes the 14 original slides;
- fills the `# duo` lines.

Then `duo2 deck template specimen northwind` opens a three-slide specimen deck in the viewer, every slot filled to its limit.

**Error 3: a limit that doesn't fit.** Duo's fit check measures each slot's limit text against the placeholder's real box (CoreText, in the template's font):

```
northwind.md:41: kpi.label: 45 characters at 18 pt takes 2 lines; the box holds 1. Largest that fits: 34.
```

The specimen shows the label wrapping into the context line. Claude sets `max: 34`, and build and specimen run again clean.

**New [P]:**
- **The fit check** (plan.md P2) runs at build and at `deck check`. Its finding names the largest value that fits.
- **The specimen tab** carries a bar: "Specimen for northwind · 3 templates · Rebuild".

**Q-379.** Are limits only characters (DL-268's definition), or does the checker measure every slot's real text against its box on every check? Proposed: both. Limits are for Claude to plan with; the measured fit is what the checker enforces, and what it reports.

### M3b · "I already have the deck. Can it become a Duo deck?" Converting a pptx, and merging look-alike layouts

Geoff, 2026-10-31: "taking an existing pptx, converting it into a duo deck, either using/amending an existing template, or creating a new one; using claude to coalesce similar but non identical layouts into one, and then editing the deck as a duo deck".

**The case.** `grower-update-sept.pptx` is a 16-slide deck a colleague made by hand. It came from the Northwind master, but over time people nudged things:
- three "big number" slides whose boxes sit a few points apart;
- one of them has an extra footnote box;
- two "two column" slides, one with headings over its columns;
- a timeline slide the northwind pack has no template for;
- a chart;
- speaker notes, and two review comments left in PowerPoint.

**On screen.** The pptx open in the deck viewer.

**New [P]: Convert to Duo Deck…** in the bar, as Word documents have Convert to Markdown… (DL-123, DL-162). It opens a Duo sheet:
- **Template pack:** northwind (this project), another pack, or **a new pack from this deck**.
- **Into:** `decks/grower-update-sept.md`.
- Buttons: Cancel, **Convert with Claude** (default).

The same from Claude: `duo2 deck import grower-update-sept.pptx --pack northwind`.

**1. Duo groups the slides (deterministic).** The import inventory gives every slide a **layout fingerprint**:
- for a slide on a real layout, its placeholders' type and idx;
- for loose boxes, the boxes' kinds and positions rounded to a coarse grid.

Duo groups identical fingerprints and lists near ones with how far apart they are ("slides 5, 9, 12: same three boxes; 9 has a fourth box; positions differ by up to 6 pt"). It then compares each group with the pack's templates.

**2. Claude proposes the mapping (judgement, with you).** In the session, Claude lays out a plan. It reads as a table:

| Slides | Becomes | Why |
|---|---|---|
| 1 | title | an exact match |
| 2, 3, 7, 14 | bullets | the same layout |
| 5, 9, 12 | **kpi, amended**: a new optional slot `footnote` | three look-alikes coalesced; 9's extra box becomes the optional slot, and the 6 pt drift is ignored |
| 6, 10 | two-column (10's column headings move into the bullets' first line) | near-identical; headings aren't worth a new template |
| 11 | **timeline, new** | nothing in the pack fits |
| 13 | image, the chart as a picture | charts aren't slide content in v1 |
| 15, 16 | section, quote | exact matches |

**Error 9: a merge that would lose something.** Claude flags slide 10: merging it into two-column drops its column headings as headings. It asks with a question card:
- (a) Fold the headings into the first bullet. Recommended.
- (b) Amend two-column with optional `left-title` and `right-title` slots.
- (c) Make a new template.

The rule, as in M2: **Claude coalesces only what you approve, and any merge that changes how content appears is a question.**

**3. Duo amends and builds the pack (deterministic).** `duo2 deck template build northwind`:
- adds kpi's optional `footnote` placeholder (idx 16);
- promotes slide 11 into a new "Timeline" layout;
- adds both to `northwind.md`, the new template's purpose and limits written by Claude.

Existing decks are untouched. An optional slot doesn't break them, and nothing was renamed (Q-385's rename map isn't needed).

**4. Duo converts the content.**
- Where a slide's layout maps by fingerprint, text moves from placeholder to slot by idx, deterministically.
- For loose boxes, Claude's mapping from step 2 says which box feeds which slot.
- Speaker notes become `> [!note]`.
- **The PowerPoint comments become Review in Markdown comments** (DL-284), signed with their authors and dates (Geoff's Q-397 answer: comments come into the Markdown and git).
- The chart on slide 13 is drawn by Duo's own renderer and saved as `assets/grower-update-sept-13.png` in an image slot.
- Anything that maps nowhere goes to that slide's notes (DL-281), with the import report saying so.

**Error 10: what doesn't convert.** The import ends with a report in the sheet's place, and as text for Claude:

```
grower-update-sept.md: 16 slides from 16. 1 chart became a picture (slide 13). 1 text box went to notes (slide 4: "Draft - not for circulation"). 2 PowerPoint comments imported. Fonts: Avenir Next → Nunito Sans for Google (northwind's substitute).
```

**5. Compare with the original [P].** The deck's bar offers **Compare with Original**. The slides side shows the original pptx and the new deck slide by slide, original on the left and Duo Deck on the right, and differences are listed as numbers (moved boxes, changed sizes). You see that slides 5, 9 and 12 now line up exactly, and that slide 10's headings are bullets now.

**6. It's a Duo deck.** From here everything in M5–M10 applies: the checker, the picker, Change Template, comments, PRs, dated exports. The original pptx is never written (as with Word documents, DL-123).

**Verbs.**
- `duo2 deck import <pptx> [--pack <p> | --new-pack <name>] [--plan <file>]`: run without `--plan`, it prints the grouping and fingerprints for Claude; run with Claude's plan, it converts.
- `duo2 deck compare <deck> <pptx>`.

**Q-398.** How far may Claude coalesce look-alike layouts?
- (a) **Into one template with optional slots, each merge approved in one plan.** Recommended.
- (b) Only exact fingerprint matches; every variant becomes its own template.
- (c) Freely, listing what it merged afterwards.

### M4 · "How do I start a deck?" A new deck from a pack

**On screen.** **New [P]: New Deck…** in File › New and in Files' **+** menu (⇧⌘N stays "new folder"; no new shortcut, DL-34). It opens a Duo sheet:
- **Name:** `autumn-trial`.
- **Folder:** `decks/`.
- **Template pack:** a pop-up listing packs by scope. "northwind (this project)", then Home's packs, then "Duo Plain (built in)". Each has a strip of its templates' thumbnails.
- **Start with:** the title slide only (default), or one slide of every template (a specimen to edit).
- Buttons: Cancel, **Create**.

Duo writes `decks/autumn-trial.md` with the frontmatter and a title slide, and opens it as source beside slides. The same thing from Claude: `duo2 deck new decks/autumn-trial.md --template northwind`.

**Q-380.** Should New Deck be a sheet (proposed), or a file template under DL-146's `templates/new-deck.md` (no new UI, but no pack picker)? Proposed: the sheet. Picking the pack is the one choice that matters, and it's visual.

### M5 · "Can Claude write it for me?" Drafting from notes

**On screen.** You ask, in the session: "draft the autumn trial review from notes/autumn-trial-log.md, about 8 slides". Claude:
1. runs `duo2 deck templates decks/autumn-trial.md` (the catalogue, about 300 tokens);
2. reads the notes;
3. writes the deck.

The slides fill in beside the source as the file changes: split view's live redraw, R2.

**Error 4: too much for a slide.** Claude runs `duo2 deck check`:

```
decks/autumn-trial.md:31: slide 4 (bullets), body: has 8 points; the template allows 6. Split the slide; never shrink the text
```

Claude splits slide 4 into "What worked" and "What didn't". The check comes back clean. You watch the extra slide appear.

**What it shows.** Claude never looks at the slides to stay inside the template. The checker tells it what's wrong, in words it can act on.

### M6 · "Can I edit it myself?" Typing, with autocomplete

**On screen.** You click into the source between two slides and start a new one.

**New [P]: template autocomplete.** Typing `<!-- slide:` (or `/slide` at the start of a line, the slash-command habit from chat) opens a completion list at the caret, as the editor's other pop-ups do. Each row has:
- the template's thumbnail;
- its name in mono;
- its purpose line in `text2`.

Typing filters (`k` → kpi). Return inserts the marker **and a skeleton**:

```markdown
<!-- slide: kpi -->
# |

## value


## label


## context

```

The caret sits in the title. Tab moves slot to slot. Empty slots are allowed while you work, and the checker counts them as one notice, not errors.

**New [P]: slot autocomplete.** Typing `## ` inside a slide lists that template's slots not yet used.

**New [P]: + between slides** in the slides side. Hover a gap and a small + appears. It opens the same template list as a pop-over gallery of thumbnails, and inserts the skeleton at that point in the source.

**Error 5: a typo.** You type `<!-- slide: kip -->` by hand, past the list. The checker:

```
autumn-trial.md:58: slide 6: no template "kip" in northwind; did you mean "kpi"?
```

The slide draws as a dashed frame with the message and a **Use kpi** button (a fix with exactly one answer, applied by Duo).

**Decided (DL-281):** nobody types the marker. A shortcut opens the template list at the caret (the key is Q-391), and the + gallery opens it from the slides. The marker line shows in the editor as a slide header chip, "Slide 6 · kpi ⌄" (Q-392, recommended).

**Verbs.** `duo2 deck insert <deck> <template> [--after <n>]` writes the skeleton. Autocomplete itself is UI-only (`Parity.uiOnly`), because Claude has `deck templates`.

**Q-381.** The trigger. Is it `<!-- slide:` only, `/slide` too, or the + in the slides only? Proposed: all three, one list.
**Q-382.** Should a fix with exactly one answer ("did you mean kpi") be a button Duo applies? Proposed: yes, only for unambiguous fixes. Anything that needs judgement goes to Claude.

### M7 · "What if I change a slide's layout?" Remapping, and when it breaks

The issue Geoff named.

**On screen.** Slide 5 is `bullets` (title, body with 5 points). You want it as two columns. You put the caret on its marker and use **Change Template…**:
- **New [P]:** this is in the slide's context menu on the slides side, and in the editor's context menu on a marker line;
- it opens the same autocomplete list;
- or you just retype the name.

**What Duo does, deterministically: the remap rules [P].**
1. `title` stays `title`.
2. A slot whose **name** exists in the new template keeps its content.
3. The **default slot** moves to the new template's default slot, if both have one and the kinds match.
4. Otherwise a slot moves to the new template's **only** unused slot of the same kind, if there's exactly one.
5. Anything left over moves to the slide's **speaker notes**, under a line naming where it came from. It is never deleted (**DL-281**).

`bullets` → `two-column`:
- `title` stays;
- `body` (bullets) has no same-named slot;
- `two-column` has no default;
- there are two bullet slots (`left`, `right`), so rule 4 doesn't apply;
- so `body` is **not placed**.

**The break, on screen (DL-281).**
- `body` has nowhere to go, so Duo moves it into slide 5's speaker notes:
  ```
  > [!note]
  > Not placed after changing to two-column: body
  > - Stopped at every ladder
  > - …
  ```
- The slide is clean at once, with its title and two empty columns. The notes panel under the slide shows the five points, and a strip reads "5 points moved to notes".
- The strip's buttons:
  - **Move to left**, **Move to right**: deterministic, they move the points into that slot;
  - **Split with Claude**: Claude spreads them across both columns, only when you ask;
  - **Undo Change** (⌘Z also works).
- The checker reports an empty slot as a notice, not an error, so the deck exports.

You press Split with Claude. Claude splits the five points into left ("Spring") and right ("Autumn") by meaning, and clears the note.

**A worse break: the kinds don't match.** `kpi` → `bullets`: `value`, `label` and `context` have no home, so all three move to the notes. The strip offers Split with Claude and Undo Change, since no single move would make sense.

**Q-383.** Who defines the carry-over rules, and should the same-kind rule apply? Geoff asked "who defines these fixed rules?" Duo does, one set for every pack. The proposal adds an override in a pack's definition. Still open.
**Q-384.** Decided, DL-281: it moves to the speaker notes.

### M8 · "What happens when the template changes?" A pack update under live decks

**On screen.** A month later someone improves the pack: kpi's `context` slot is renamed `note`, and a new template `timeline` is added. They rebuild. Every deck in the project that uses kpi now fails the check. The project's Files show a problem badge on `autumn-trial.md` [P].

**Error 6:**

```
autumn-trial.md:23: slide 3 (kpi): no slot "context"; northwind renamed it "note" (northwind.md). Rename the heading.
```

**New [P]: a rename map in the definition.** `renamed: {context: note}` under kpi's yaml. Duo uses it:
- to say "renamed", not "unknown";
- to offer **Rename in All Decks**: one edit per deck, shown as a diff before it's applied.

Claude can do the same with `duo2 deck migrate --pack northwind`.

**Q-385.** Does a pack carry a rename map (proposed), or a version number decks pin (`template: northwind@3`), or neither, so decks just break and get fixed? Proposed: the rename map. Pinning versions means keeping old layouts around, and decks in one project should move together.
**Q-385.** Does a pack change in Home (user level) warn every project that uses it? Proposed: each project's check reports its own decks. Duo doesn't scan other projects.

### M9 · "How do others change it?" A pull request

**On screen.** A teammate's PR on GitHub: "Autumn numbers and a slide on what still breaks". The reviewer sees:
- the Markdown diff, as on board 7;
- the exported pptx as a binary change, because the pptx is always committed (DL-270).

**Exports carry their date (DL-282).** Export writes `autumn-trial 2026-10-31 1642.pptx`, named with its date and time.
- A stale export shows its age in its name.
- Two branches that both export never fight over one binary file.
- Only the newest is kept in the folder, and git history has the rest (Q-393, recommended).

The bytes are still the same for the same source, and the pptx carries its source's hash, so `duo2 deck check` can say "the newest export is older than the deck".

**Comments on slides [P] (Q-394 to Q-397, `comments.md`).** The reviewer comments on slide 3's value in Duo:
- Select Shape, then Add Comment;
- the comment is written into the Markdown, signed, on its own line in the `value` slot;
- a pin shows at the value's corner;
- clicking it opens the thread in the source's margin;
- the author answers, or asks @claude, as Review in Markdown already does.

**Q-386.** Decided, DL-282: exports are dated, which removes the merge conflicts. Which exports git keeps is Q-393.
- export on commit plus `.gitattributes` (proposed);
- a check that only warns;
- or to revisit Q-354 ("never commit" makes both problems vanish)?

### M10 · "And then it's PowerPoint?" Export and Google Slides

**On screen.** Export ⌄ › Export as PowerPoint… The notice: "Exported autumn-trial.pptx · 9 slides".

You open the pptx in the deck viewer, then (by hand, v1) upload it to Google Drive and open it in Slides:
- Slides' Layout menu lists Title, Bullets, Quote, Big Number…, the pack's own layouts (tested, F-460);
- the headings are in Nunito Sans, the substitute from M2;
- every slide is editable text in its placeholder.

**What it shows.** The deck didn't become a picture of a deck. It is a real presentation on your company's master.

**Later [P]:** Upload to Google Slides… (P4), making a new dated presentation each time (DL-270).

### M11 · The FAQ card (the film's close, about 20 s)

A motion graphic listing the questions the film answered, each with its moment's frame as a thumbnail:
- where templates come from;
- what Duo does and what Claude does;
- how to start;
- how to edit;
- what happens when a layout changes;
- what happens when a template changes;
- how others contribute;
- what Google keeps.

The final line: "Decks as text. Templates as PowerPoint. Claude in between."

## What this adds to the feature definition

| Area | Addition [P] | Layer | Phase |
|---|---|---|---|
| Templates from a deck | Make Templates… slide selection in the deck viewer; `deck template pick/picked` | Application (viewer) | P2 |
| Extraction questions | Claude asks when a mapping is ambiguous (Q-378); a font substitute question | Agent (skill text) | P2 |
| Fit | Measured fit at build and check; findings name the largest value that fits (Q-379) | Application | P2 |
| Converting a deck | Convert to Duo Deck…; fingerprint grouping; Claude coalesces look-alikes into one template with optional slots (Q-398); comments and notes imported; charts as pictures; Compare with Original; `duo2 deck import`, `deck compare` | Application plus agent | P2 |
| New deck | New Deck… sheet with a pack picker; `duo2 deck new` (Q-380) | Application | P1 (verb), P3 (sheet) |
| Editing | Template autocomplete with skeletons; slot autocomplete; + between slides; `duo2 deck insert` (Q-381) | Application (editor) | P3 |
| One-answer fixes | "Use kpi", "Move to left": Duo applies them (Q-382) | Application | P3 |
| Changing a layout | Change Template…; deterministic remap rules; leftovers move to speaker notes (DL-281, Q-383) | Application (rules, checker) plus the agent (Split with Claude) | P1 (rules in the checker), P3 (UI) |
| Pack changes | Rename map in definitions; Rename in All Decks; `duo2 deck migrate` (Q-385) | Context plus application | P2 |
| Git | Dated exports, the newest kept; `duoSourceSha` in the pptx (DL-282, Q-393) | Application | P1 |
| Comments | Pins on slides; Add Comment from the preview; stored as Review in Markdown comments (Q-394..Q-397, comments.md) | Application plus context | P3 |
| Problems in Files | A problem badge on a deck that fails its check | Application | P3 |

**The rule these share.** Duo applies a fix itself only when it has exactly one right answer. Anything that needs judgement goes to Claude, and only when you ask. Content is never dropped.

## For the film's worker

- **Length:** about 4 minutes; 11 moments; about 650 to 700 words of narration.
- **Look:** the intro film's grammar (`video/style/`, shot-grammar.md, taste.md):
  - no cuts;
  - every change of scene is navigation in the app or a motion graphic;
  - real-looking UI on sample data.
- **Simulated UI:** Duo Decks isn't built. Each state is an HTML page drawn with the Duo design system's tokens (the canvas boards in `canvas/` are the starting point), captured headless at a fixed size with anchors from `data-video` elements. That's the skill's "web product" capture path.
  - Real Duo chrome where it exists (sidebar, console, tabs, the deck viewer bar) is copied from the design system's previews.
  - Slides are real renders of the fixture decks: the prototype `prototypes/compile/deck.py` exports them, LibreOffice draws them.
- **Errors** are the real messages above, produced by running the prototype checker on the fixture decks wherever it can make them. Errors 1 to 3 and 6 to 8 need P2/P3 features the prototype doesn't have; their text is from this document.
- **Voice:** Geoff's own (his project; access confirmed by `gh repo view dudgeon/geoff-voice`). Renders run under the exclusive GPU lock.
- **A Shot: note is a spec.** The script Doc is the source of truth once Geoff edits it.
