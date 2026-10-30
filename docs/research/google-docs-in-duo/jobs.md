# Jobs to be done: a person, Claude and remote people on one Google Doc

Phase 1A of [Google Docs in Duo](../../../tasks/google-docs-in-duo.md), 2026-10-29. Each job below is something one of these three does to a document:
- **the person:** Geoff, a PM, in Duo
- **the agent:** Claude in a Duo terminal or chat
- **remote people:** colleagues in their own browsers

Where the jobs come from:
- what Claude Docs, Google Docs with Gemini, Word with Copilot and Notion AI offer
- Duo's own Review in Markdown (DL-236, DL-237, DL-251)
- the earlier research (`docs/research/google-docs-native.md` on its branch, `docs/research/agent-docx-tooling.md`)
- the landscape survey ([agent-landscape.md](agent-landscape.md), on `research/gdocs-landscape`)

Each job has these columns:
- **Who:** P (the person), A (the agent), R (a remote person), or a mix like P+A.
- **How often:** in a working week with Docs.
  - **constant:** many times an hour
  - **daily**
  - **weekly**
  - **rare**
- **Matters:** how much it matters to Geoff's use, a PM writing with Claude and a team. **H** is high, **M** medium, **L** low. This is my call; Checkpoint 1 asks Geoff to cut it.
- **Bar:** the latency or fidelity it needs to feel right.
  - **"Live"** means under 150 ms, which feels instant.
  - **"Turn"** means within an agent turn: about a second, against a turn's 5–30 s.
  - **"Pixel"** means it looks the same as Docs in Chrome.

The test that covers each job is in [test-plan.md](test-plan.md), by its J-id.

## A. Reading and orienting

| J | Job | Who | How often | Matters | Bar |
|---|---|---|---|---|---|
| J-A1 | Open a Doc from a link (chat, email, Drive, a task's references) and see it as Docs draws it | P | constant | H | Pixel; open in < 3 s |
| J-A2 | Find your way in a long doc: outline, headings, tabs, jump to a heading | P | daily | H | Live |
| J-A3 | Read at a comfortable size in Duo's right pane, which is narrower than a browser window | P | constant | H | No sideways scroll at 460–900 pt; zoom remembered |
| J-A4 | Claude reads the whole doc as text with structure: headings, lists, tables, links and chips | A | constant | H | Turn; exact text; structure kept |
| J-A5 | Claude reads one part (a heading's section, a table, a tab) without pulling the whole doc | A | daily | M | Turn |
| J-A6 | Claude reads the doc *as the person sees it now*, with others' unsaved-looking edits, suggestions and comments in place | A | daily | H | Lag behind the screen under 2 s |
| J-A7 | Read a doc you can only view, or one published to the web | P+A | weekly | M | As J-A1 and J-A4 |
| J-A8 | Multiple Docs open as tabs beside sessions and Markdown docs, and come back as they were | P | daily | M | Restore keeps place |

## B. The agent knows what I'm looking at and what I've selected

| J | Job | Who | How often | Matters | Bar |
|---|---|---|---|---|---|
| J-B1 | Claude knows which Doc (and tab) is on screen | A | constant | H | Turn |
| J-B2 | Claude knows what I've selected, as text **and** as a position it can act on | A | constant | **H, Geoff's own ask** | Under 250 ms from my mouse-up; exact |
| J-B3 | Claude knows where my caret is, with no selection ("here", "below this") | A | daily | H | As J-B2 |
| J-B4 | Claude knows what part of the doc is in view ("this page", "what I'm reading") | A | weekly | M | Turn |
| J-B5 | Send a selection to Claude in one move, as Send to Claude does for Markdown (LR-44) | P | constant | H | One key or click; arrives quoted with its place |
| J-B6 | Claude points me at a passage: it selects or scrolls to it in my Doc | A | daily | M | Live once asked |

## C. Asking about a passage

| J | Job | Who | How often | Matters | Bar |
|---|---|---|---|---|---|
| J-C1 | "What does this mean / is this right / what's missing?" about a selection | P→A | constant | H | Needs J-B2 and J-A4 |
| J-C2 | "Is this consistent with the rest / with that other doc?" | P→A | daily | H | Needs whole-doc read and cross-doc reads |
| J-C3 | Ask about a table, a chip (a person, a file, a date), an image | P→A | weekly | M | Structure kept, chip values readable |
| J-C4 | Ask about history: "who wrote this, when did it change?" | P→A | weekly | M | Needs revisions and authorship |

## D. The agent drafting

| J | Job | Who | How often | Matters | Bar |
|---|---|---|---|---|---|
| J-D1 | Claude writes a new section or a first draft into the doc, with real headings, lists and tables, not Markdown symbols | A | daily | H | Styles as Docs' own; arrives in < 5 s for a page |
| J-D2 | Claude makes a new Doc (from a brief, a Markdown file, a template) in the right Drive folder | A | weekly | H | Turn; native Docs formatting |
| J-D3 | Claude drafts *beside* the doc, and I place it (a draft I copy or drag in) | A→P | daily | M | Rich paste keeps formatting |
| J-D4 | Claude continues writing at my caret | A | daily | M | Needs J-B3 |

## E. The agent suggesting edits as tracked changes

| J | Job | Who | How often | Matters | Bar |
|---|---|---|---|---|---|
| J-E1 | Claude's edits arrive as **Docs suggestions** that I and others see, credited clearly, never as silent edits | A | constant | **H, Geoff's own ask** | Visible in my tab < 2 s after the write; real Docs suggestions |
| J-E2 | Claude rewrites my selection as a suggestion | A | constant | H | Exactly that range; no stray changes |
| J-E3 | Claude suggests many small edits across the doc (a copy edit pass) | A | weekly | H | All land, none clobber a collaborator's typing |
| J-E4 | Claude suggests formatting and structure changes (a heading level, a list, a table row) | A | weekly | M | Where Docs supports suggesting them |
| J-E5 | Claude's suggestions don't collide with someone typing nearby | A+R | daily in shared docs | H | Merge or fail safely; never lose text |
| J-E6 | It's clear which suggestions are Claude's and which are mine | P+R | constant | H | An identity or label others can see |

## F. Accepting and rejecting

| J | Job | Who | How often | Matters | Bar |
|---|---|---|---|---|---|
| J-F1 | I accept or reject Claude's suggestions one by one, in the doc, as Docs does | P | constant | H | Docs' own UI, live |
| J-F2 | Accept or reject all of Claude's (and only Claude's) | P | weekly | M | One action |
| J-F3 | Claude accepts or rejects suggestions on my say-so ("take Maria's edits in section 2") | A | weekly | M | Turn |
| J-F4 | Claude reads the open suggestions and summarises or argues them | A | weekly | M | Needs suggestions in the read (J-A6) |

## G. Comments and replies, @-mentions and assignment

| J | Job | Who | How often | Matters | Bar |
|---|---|---|---|---|---|
| J-G1 | Comment on a passage, reply, resolve, reopen | P+R | constant | H | Docs' own UI, live |
| J-G2 | @-mention a colleague; assign a comment as an action item | P+R | daily | H | Notifies them by Google's own email |
| J-G3 | Claude reads all open threads with what they're anchored to | A | daily | H | Turn; anchor text exact |
| J-G4 | Claude leaves anchored comments (a review pass), credited clearly | A | weekly | H | Anchored, not doc-level |
| J-G5 | Find comments assigned to me, or unresolved, across docs | P+A | weekly | M | Turn |

## H. The agent answering comments

| J | Job | Who | How often | Matters | Bar |
|---|---|---|---|---|---|
| J-H1 | I @claude in a Docs comment (or tag it some other way) and Claude replies in the thread, as Review in Markdown does (DL-236/237/251) | P→A | daily | **H** | Picked up < 1 min (< 10 s when Duo is open); reply in the thread |
| J-H2 | A remote colleague's comment gets Claude's draft reply for me to approve | R→A→P | weekly | M | Draft held until I send it |
| J-H3 | Claude makes the edit a comment asks for, as a suggestion, and replies with what it did | A | daily | H | J-E1 + J-G4 |
| J-H4 | Claude resolves threads it has dealt with, when I say so | A | weekly | M | Turn |

## I. Restructuring, styles, headings, lists, tables

| J | Job | Who | How often | Matters | Bar |
|---|---|---|---|---|---|
| J-I1 | Apply and fix heading levels, named styles, list nesting | P+A | daily | M | Docs' styles, not direct formatting |
| J-I2 | Move sections around | P+A | weekly | M | As a suggestion where possible |
| J-I3 | Build and edit tables (rows, columns, merges) | P+A | weekly | M | Native tables |
| J-I4 | Tabs: add, rename, move content between doc tabs | P+A | rare | L | — |
| J-I5 | Page setup, headers and footers, page numbers, pageless mode | P | rare | L | — |

## J. Smart chips and links

| J | Job | Who | How often | Matters | Bar |
|---|---|---|---|---|---|
| J-J1 | Insert a person, file, date or dropdown chip; @-insert in text | P+A | weekly | M | Real chips |
| J-J2 | Claude reads chips as values (who, which file, what date), not as "@Name" text | A | weekly | M | Value and display both |
| J-J3 | Links: follow a link to another Doc in Duo; Claude follows it too | P+A | daily | M | Opens in a Duo tab when allowed |
| J-J4 | Building blocks (meeting notes, decision log, project roadmap) | P | rare | L | — |

## K. Images

| J | Job | Who | How often | Matters | Bar |
|---|---|---|---|---|---|
| J-K1 | See images, drawings and charts as drawn | P | weekly | M | Pixel |
| J-K2 | Claude sees an image (as a picture) when asked about it | A | weekly | M | Turn |
| J-K3 | Claude inserts an image (a diagram it made, a screenshot) | A | rare | L | Native inline image |

## L. Version history and naming versions

| J | Job | Who | How often | Matters | Bar |
|---|---|---|---|---|---|
| J-L1 | Look at version history; restore a version | P | weekly | M | Docs' own UI |
| J-L2 | Name a version ("sent to execs") | P | weekly | M | Docs' own UI |
| J-L3 | Claude names a version before a big pass, as a checkpoint | A | weekly | M | — |
| J-L4 | Claude compares two versions | A | weekly | M | Needs revision export |

## M. Sharing and permissions

| J | Job | Who | How often | Matters | Bar |
|---|---|---|---|---|---|
| J-M1 | Share with people, change access, copy the link | P | weekly | M | Docs' own Share dialog |
| J-M2 | Claude shares only on explicit say-so, and says who can see what | A | rare | M | Never unasked (an outward action) |
| J-M3 | Request access, or open a doc you can't see, and get a sensible message | P | weekly | M | — |

## N. Live co-editing with remote people

| J | Job | Who | How often | Matters | Bar |
|---|---|---|---|---|---|
| J-N1 | See others' edits as they type | P+R | constant in meetings | **H, Geoff's own ask** | Docs' own latency (typically under 1 s keystroke to screen); same as Chrome |
| J-N2 | See who's here (avatars) and where (their cursors and selections) | P+R | constant in meetings | H | Live |
| J-N3 | Type while others type, with no lost characters and no conflict dialogs | P+R | constant in meetings | H | Docs' own OT; nothing lost |
| J-N4 | Comment and suggest while others do, with live updates | P+R | constant in meetings | H | Live |
| J-N5 | Claude works on the doc during a live session without disrupting people (no cursor jumps, no lost text) | A+R | weekly | H | Zero lost edits |
| J-N6 | Follow a presenter, or jump to a collaborator | P | rare | L | — |
| J-N7 | Doc chat with viewers | P+R | rare | L | — |

## O. Offline

| J | Job | Who | How often | Matters | Bar |
|---|---|---|---|---|---|
| J-O1 | Read and edit on a plane, sync after | P | rare | L | Docs offline (Chrome or Edge only) |
| J-O2 | Claude can still read the last copy offline | A | rare | L | A cached export |

## P. Export and import

| J | Job | Who | How often | Matters | Bar |
|---|---|---|---|---|---|
| J-P1 | Download as docx, PDF or Markdown | P | weekly | M | File in Downloads; Docs' own export |
| J-P2 | Claude gets a Markdown copy into the project (for git, for search) | A | daily | H | Turn; links kept |
| J-P3 | Turn a Markdown doc in the project into a Google Doc to share (and back) | P+A | weekly | H | Formatting kept; comments carried (DL-236's convert) |
| J-P4 | Print | P | rare | L | Docs' own print (a PDF with text) |

## Q. Templates

| J | Job | Who | How often | Matters | Bar |
|---|---|---|---|---|---|
| J-Q1 | Start from a template (PRD, one-pager) and have Claude fill it from a brief | P+A | weekly | M | Template's styles kept |

## R. Find and replace

| J | Job | Who | How often | Matters | Bar |
|---|---|---|---|---|---|
| J-R1 | Find in the doc (⌘F); find and replace (⌘⇧H) | P | daily | M | Docs' own, not the page's find |
| J-R2 | Claude replaces a term everywhere, as suggestions | A | weekly | M | Every match, nothing else |

## S. Citations

| J | Job | Who | How often | Matters | Bar |
|---|---|---|---|---|---|
| J-S1 | Claude adds sources: links on claims, footnotes | A | weekly | M | Real footnotes and links |
| J-S2 | Claude checks the links and claims in a doc | A | rare | L | — |

## T. Summaries of change

| J | Job | Who | How often | Matters | Bar |
|---|---|---|---|---|---|
| J-T1 | "What changed since I last looked?" (edits, suggestions, comments, by whom) | P→A | daily | **H** | Turn; needs a remembered "last looked" point |
| J-T2 | Claude notices a change (a new comment, an @claude, an edit in a section it owns) without being asked | A | daily | H | < 1 min |
| J-T3 | A digest across docs for a project | A | weekly | M | — |

## How the jobs fall

- **Geoff's own asks** are J-A1, J-B2, J-E1 and J-N1:
  - near-perfect rendering
  - Claude aware of my selection
  - Claude editing with tracked changes
  - low-latency collaboration with people
- **Docs' own UI already does well for people:** J-A1–A3, F, G1–G2, L1–L2, M, N, R1. Every person-only job is "does Docs work properly in Duo's browser?". That's a fidelity test, not a build.
- **The agent jobs** (A4–A6, B, D, E, G3–G4, H, T) are where Duo has to add something. They split into two kinds:
  - **reading the live session:** what's on screen, the selection, the caret, others' edits
  - **writing durable changes:** suggestions, comments, versions
- **Low for Geoff's use** (my call): offline, page setup, building blocks, doc chat, follow-the-presenter, citations checks.
