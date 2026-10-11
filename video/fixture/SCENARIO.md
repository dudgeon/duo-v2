# The demo world: scenario bible

The intro video films Duo on this world. Every fixture under `video/fixture/` follows it: names, numbers and dates come from here. Its data is in `world.json`, which every `make-*.py` script reads; change both together, then rebuild.

Agreed with Geoff on 2026-10-11 (interview rounds 1–3). Everything here is invented; no real companies or people.

## The company

**Little Shared Library** is a seed-stage consumer startup with five people. Its iPhone app is a shared catalog of the book-sharing boxes on your neighbourhood's streets: what's on each shelf right now, and how fresh that is.

- **Neighbours** browse the map and see what's in nearby boxes.
- **Stewards** look after a box and keep its catalog current.
- **The beta** runs on TestFlight: 212 testers in three neighbourhoods (Elm Park, Northgate and Riverside), 340 boxes catalogued.
- **The money:** seed round closed in June; runway to next autumn.

## The cast

| Who | Role | Shows up in |
| --- | --- | --- |
| **Sam** | First PM hire, the demo user. Works almost entirely through Claude Code. | Sidebar user; bylines ("Sam"); every session |
| **Jo Whitfield** | Co-founder and CEO. Runs the Thursday team review. | Deck audience; PRD approver |
| **Ravi Menon** | Co-founder and CTO. Owns the spine-recognition model. | Eval notes; the accuracy numbers; PRD reviewer |
| **Lena Park** | Designer. Made the scan screens Sam prototypes from. | Prototype credits; the review step design |
| **Tomás Ruiz** | iOS engineer. Builds the scan flow. | Beta crash notes; the effort estimates |
| **Testers P1–P8** | Beta testers interviewed in late September. Quoted by first name and P-number. | Interview synthesis; pasted feedback |

The testers:

- **P1 Aisha**, a commuter who scans on the way to the train.
- **P2 Gerald**, a retired teacher and the steward of the Elm Park box.
- **P3 Denise**, a steward with a glass-door box: glare. Her pasted feedback is S5's.
- **P4 Marco**, a parent who borrows picture books.
- **P5 Priya**, a heavy reader who uses the map daily.
- **P6 Hal**, a new steward.
- **P7 June**, a student.
- **P8 Owen**, who stopped scanning after two wrong books.

## Time

**Today is Tuesday 13 October 2026, 9:41** (the menu bar's "Tue 9:41"). The team review is **Thursday 15 October**. The terminals' `Last login:` is Tue Oct 13.

| When | What happened |
| --- | --- |
| Aug 24 | Shelf scan v1 ships to the beta: point the camera at a box, and every spine it reads is added to the catalog automatically. |
| Sep 14–25 | Sam interviews eight beta testers (P1–P8). |
| Sep 28 | Ravi's eval: 81% of spines read correctly on 1,240 spine photos from 96 shelves. |
| Oct 5 | Beta digest: a third of testers who saw a wrong book stopped scanning. |
| Oct 9 | Sam starts PRD v2: scan with a review step. |
| Oct 12 | Prototype test of the review step with P1, P4, P6 and P7: 97% right, median 18 s a shelf. |
| **Oct 13 (today)** | Sam tightens the PRD, prototypes the review screen, finishes the synthesis, and decides on auto-add. |
| Oct 15 | Team review: Jo decides whether scan v2 goes into the November build. |
| Nov 2 | Target: scan v2 in TestFlight. |

## The story the video catches

Shelf scan misses about one spine in five, and every miss is added to the catalog anyway. So neighbours walk to a box for a book that isn't there, and that breaks trust in the whole catalog.

Sam's plan for v2:

- show what the scan found and let you **review** it before anything is added;
- make **fixing a missed book** one tap;
- keep **auto-add** off until accuracy reaches 95%.

Today Sam is getting all of that ready for Thursday, with several Claude sessions at once.

**The decision a session is waiting on** (Needs you): Claude has found three testers (P3, P6 and P8) who say a wrong auto-added book is why they stopped scanning. That conflicts with goal 2 of the v1 PRD ("every scanned spine lands in the catalog with no extra taps"). Claude asks Sam to choose: *put auto-add behind the review step*, or *keep it and log an open question*.

## The numbers (use these and only these)

**The beta**

| Fact | Value |
| --- | --- |
| Testers | 212 |
| Boxes catalogued | 340 |
| Scans in Sep | 1,870 |
| Scans that end with a saved shelf | 64% |
| Testers who saw a wrong book and stopped scanning | 46 of 148 (31%) |

**The model**

| Fact | Value |
| --- | --- |
| Spine read accuracy, v1 model | 81% (1,240 spine photos, 96 shelves) |
| Accuracy with the review step (the user fixes a miss) | 97% in the prototype test (P1, P4, P6 and P7; 5 shelves) |
| Auto-add threshold | 95% |

**Where misses come from** (share of the 236 wrong reads)

| Cause | Share |
| --- | --- |
| Tilted or leaning spines | 34% |
| Glare (glass or plastic doors) | 27% |
| Thin spines (under 1 cm) | 21% |
| Stacked or sideways books | 12% |
| Other (non-Latin titles, worn print) | 6% |

**v2 targets**

| Metric | Today | Target |
| --- | --- | --- |
| Scans that end with a saved shelf | 64% | 80% |
| Wrong books in the catalog | 19% | under 3% |
| Median time to review a shelf | — | 20 s |

**The other projects**

| Fact | Value |
| --- | --- |
| Beta reports, week of Oct 5 | 41 (29 the week before); 14 about wrong books |
| Tester emails, Oct 12 | 23, in 5 themes |
| Stale boxes (no scan in 7 days) | 61 of 340 |
| New stewards who catalog in week 1 | 31% today, goal 50% |

**Books on shelves:** public-domain classics, plus invented titles. No real living authors.

- Classics: *Middlemarch*, *Moby-Dick*, *Little Women*, *The Secret Garden*, *Persuasion*, *Bleak House*.
- Invented: *The Lantern Keeper*, *Salt Roads*, *A Field Guide to Small Birds*.

The scan misread the screenshot shows: *Persuasion* read as **"Pervasion"**, then matched to a different book.

## Projects

Folders live under `~/work/little-shared-library/`. Topics: **App** and **Community**.

| Project | Topic | Goal | Health | Next |
| --- | --- | --- | --- | --- |
| **shelf-scan** (hero) | App | Scan v2: fewer than 3% wrong books in the catalog | On track | Team review Thu Oct 15 |
| beta-feedback | Community | A weekly digest of what testers report | On track | Digest due Fri |
| neighborhood-map | App | Show how fresh each box's catalog is | At risk | Map pins spec, Oct 20 |
| steward-onboarding | Community | Half of new stewards catalog their box in week 1 | On track | — |
| home | — | Triage, status, personal ops | — | Weekly status due 4pm |

**shelf-scan**, the only deep project, as files:

| File | What it is | Scenes |
| --- | --- | --- |
| `PROJECT.md` | Goal, health, next step; links to the PRD and the deck | S2 left pane, S5 |
| `docs/prd-v2.md` | PRD v2: Problem, Goals, What we heard (added by Claude), Requirements, Non-goals, Open questions | S1 editor window, S2 right tab 1, later the documents scene |
| `prototype/scan-review.html` | The polished prototype: an iPhone-sized review screen. A shelf photo with a box on each detected spine; "14 found · 2 need a look"; tap a spine to fix it; "Add 14 books to Elm Park box" | S1 browser window, S2 right tab 2, S5 screenshot |
| `docs/team-review-oct15.pptx` | The deck for Thursday, 5–6 slides in an in-house template. Slide 2 is the chart "Where scans go wrong" | S1 PowerPoint window, S2 right tab 3 |
| `docs/beta-interview-synthesis.docx` | The synthesis of the eight interviews: Summary, What we heard, Themes, Recommendations | S1 Word window, S2 right tab 4 |
| `eval/spine-eval-2026-09-28.md` | Ravi's eval notes: method, the confusion cases, the scrappy bits ("glare set is only 140 photos from 9 shelves, needs more") | S5 tool calls |
| `eval/results.csv` | One row per spine photo: shelf, truth, read, correct, cause | S5 tool calls |
| `eval/score.py` | The script that scores `results.csv` and prints the miss table | S5's command |
| `research/interviews/p1.md … p8.md` | Interview notes, about a page each | The synthesis session reads them |
| `research/feedback/denise-p3.txt` | Denise's long beta feedback (over 12 lines, in her voice): glare from her box's glass door, *Persuasion* added as the wrong book, a neighbour came for it | S5 paste (folds to "Pasted text · n lines") |
| `research/feedback/denise-p3-screenshot.png` | Her screenshot: the prototype on a phone viewport, showing the wrong match | S5 image paste |
| `research/feedback/owen-p8.txt` | Owen's short email: two wrong books in two scans, then he stopped | S5 turn 2 (the skill reads it) |
| `research/feedback/triage.md` | The feedback backlog, one line per report by eval cause (Gerald, Hal before S5; Denise and Owen added in S5) | S5 turns |
| `.claude/skills/triage-feedback/SKILL.md` | Sam's project skill: "Sort tester feedback into the backlog by eval cause". The `/` menu lists it first for `/tri` | S5 slash menu, turns |

The other projects are thin but real. `make-projects.py` writes them under `projects/<name>/`: each gets a `PROJECT.md` (Home gets `HOME.md`) and 1–3 documents with believable content. Their sessions have titles and states.

## Sessions

The sidebar and All projects show **18 sessions**: 15 live and 3 archived. Wait times are as of Tue 9:41.

| Session | Project | State | Notes |
| --- | --- | --- | --- |
| **Tighten PRD goals** | shelf-scan | working · now | S2 middle tab 0 (terminal) |
| **Prototype scan review** | shelf-scan | idle · 12m | S2 middle tab 1 (terminal). Renamed from "Prototype express pay" (needs the intro-video session's OK) |
| **Synthesis from interviews** | shelf-scan | idle · 1h | S2 middle tab 2, flips to chat |
| **Auto-add decision** | shelf-scan | **needs you** (question) · 4m | The decision above. S3 Needs you; S4 resumes it with history; S5 chat mode, tool calls, paste |
| Spine eval: glare cases | shelf-scan | working · 9m | Running `score.py` on the glare subset |
| Deck for Thursday | shelf-scan | ready for review | "team-review-oct15.pptx, 6 slides" |
| quick q: TestFlight build size | shelf-scan | idle · 3d | To archive (S4) |
| Old v1 notes cleanup | shelf-scan | idle · 6d, not running | To delete (S4) |
| Weekly digest draft | beta-feedback | working · 2m | |
| Tag crash reports | beta-feedback | **needs you** (permission) · 7m | Wants to run `xcrun` on crash logs |
| Tester emails, Oct 12 | beta-feedback | ready for review | "Sorted 23 emails into 5 themes" |
| Freshness badge spec | neighborhood-map | working · 14m | |
| Map pins: stale boxes | neighborhood-map | idle · 2d | |
| Steward welcome email | steward-onboarding | ready for review | |
| Morning triage | home | **needs you** (question) · 1h | "4 new asks: route 3 to projects?" |
| *(archived)* Scan v1 launch notes | shelf-scan | archived | |
| *(archived)* Interview guide | shelf-scan | archived | |
| *(archived)* Map tile costs | neighborhood-map | archived | |

**Needs you: 3** (two questions and one permission). Working 4, ready for review 3, idle 5. Archived sessions are in fixture.json's `archivedSessions`.

## Scenes and what they use

| Scene | What it films | Uses |
| --- | --- | --- |
| S0 | Logo | — |
| S1 | The messy desk | `content.json`: Terminal windows on the three shelf-scan sessions; Finder on `little-shared-library` (sidebar: the other projects); the PRD in an editor; the prototype in a browser; the deck; the doc |
| S2 | The pile becomes Duo | `fixture.json` `videoS2`; the shelf-scan folder; the three sessions; tabs prd-v2.md · scan-review.html · .pptx · .docx |
| S3 | All projects, List | All 5 projects, the 18 sessions, Needs you 3 |
| S4 | Sessions | "Auto-add decision" resumes with history; archive "quick q: TestFlight build size"; delete "Old v1 notes cleanup"; the archived list |
| S5 | Chat mode | "Auto-add decision" in chat: a turn with Read `eval/results.csv`, Bash `python3 eval/score.py`, Edit `docs/prd-v2.md`; Denise's feedback pasted; her screenshot pasted; then (Geoff, 2026-10-11) a few short turns and "most slash commands work in chat": Sam answers the question, sends Denise's email (Claude loads `/triage-feedback` itself), runs `/triage-feedback research/feedback/owen-p8.txt` from the `/` menu (`/tri`), asks "How many glare reports so far?"; then `/model`, the picker card with Opus in use |

## Rules for fixture content

- **Legible at video scale.** Use short sections, clear headings and real sentences.
- **Polish where the video wants it, grit where it's real.**
  - The prototype UI is polished: a real iOS look, in Lena's design.
  - The eval notes, the CSV and the crash logs are scrappy: TODOs, a rerun, a caveat.
  - Tester feedback is in each tester's own voice: typos are fine, lorem ipsum never is.
- **Numbers come from the tables above.** If a document needs a new number, add it here first.
- **Generated, not hand-made.** Every artefact comes from a `make-*.py` script reading this world's data, so a name change rebuilds everywhere.
