# Duo Decks: design study

Status: **proposed, waiting on Geoff** (Q-348 to Q-356). Every mark on the canvas is [P]. Research and planning only; nothing is built.

Geoff, 2026-10-31 (the full request is in `tasks/duo-decks.md`): templates for PowerPoint slide styles, scoped to a project or to the user; decks written in Markdown that may only use defined templates; a rendered viewer and editor in Duo; export to PowerPoint that survives Google Slides; Claude knowing the standard; and as little application and UI as will do.

## For Geoff

- **The walk-through page**: https://claude.ai/artifact/7H6wxTs26LW1DvAfSZCsyi (source `narrative.html`). The decisions are buttons; answers are saved in the page's `answers` collection.
- **The canvas**: https://claude.ai/artifact/Sk28K1tkHgwk6gHs7RFGqQ, with the Duo design system and 8 boards (sources in `canvas/`). The boards are: 1 the three layers, 2 a deck in Duo, 3 problems, 4 a template pack, 5 extraction, 6 export and Google, 7 a PR, 8 the viewer options.

## Read in this order

| File | What it holds |
|---|---|
| `plan.md` | The plan: the three layers, extraction, path dependencies, phases, the PR story, risks, the decisions |
| `research-agentic-landscape.md` | How about 25 tools and agents make and edit decks, 14 patterns, 14 anti-patterns |
| `research-formats.md` | Marp, Slidev, Quarto/pandoc, Deckset, iA Presenter, MDX, Typst, python-pptx, pptxgenjs, pptx-automizer…: source, layouts, diffs, tokens, pptx fidelity |
| `research-pptx-google-and-templates.md` | The Google Slides round trip, the fidelity matrix, template extraction (deterministic vs inferred), a draft definition |
| `research-duo-context.md` | What Duo already has: Markdown handling, templates scope (DL-146), the pptx viewer and reader, duo2, the skill, Google Docs status, the work Mac |

## Samples and prototypes (synthetic content only)

- `samples/decks/field-trial-review.md`: a 9-slide deck in the proposed convention; `samples/decks/assets/row-map.png`.
- `samples/templates/decks/northwind/`: a template pack, `northwind.pptx` (synthetic, 10 layouts) and its definition `northwind.md`.
- `samples/pr/field-trial-review.diff`: what a reviewer sees in a PR; `samples/pr/check-output.txt`: the checker's errors on a broken copy.
- `img/sample-deck/`: the sample deck exported by the prototype and drawn by LibreOffice.
- `prototypes/compile/deck.py`: the stand-in for `duo2 deck templates|check|export` (Python with python-pptx; the real one is Swift). Run from `samples/`: `python deck.py check decks/field-trial-review.md`.
- `prototypes/pptx/`: the synthetic template generator, the two test decks (placeholder vs absolute), the OOXML inventory.
- `prototypes/formats/`: the format comparisons (pandoc, pandoc.wasm, Marp, pptxgenjs, pptx-automizer).

## Records

F-460 to F-466 (findings), Q-348 to Q-356 (questions; Q-348 to Q-351 become DL-267 to DL-270), C-130 to C-132, ENH-296 to ENH-299.
