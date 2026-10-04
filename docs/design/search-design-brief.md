# Duo — Search: design request for Claude Design

Version 1 · 2026-10-03 · Owner: Geoff

This asks Claude Design to design **cross-project search** for Duo, inside the design Duo already has. It is an extension of the existing project, not a fresh start: the design system, the two altitudes, the toolbar and the components are settled and built (`docs/design/build-handoff/`). Search must look and behave like it always belonged there.

It contains **no mock-ups**. The back end is built and working, so this brief is precise about what each result can show and what each action does; how it looks is the design's job.

---

## 0. How to use this

1. Open the existing **Duo** project in Claude Design (the one that produced `build-handoff`). Its design system and screens are the starting point. If it isn't to hand, attach `docs/design/build-handoff/README.md`, `tokens.json` and the PNGs in `screens/png/`.
2. Attach this brief. Optional background: `docs/prd/cross-project-search.md` (the PRD, on the `claude/cross-project-search-prd-1c4761` branch).
3. Run the prompts in § 8 in order, short and one at a time, refining on the canvas with comments.
4. Export the handoff to Claude Code in the same shape as `build-handoff/` (§ 9).

---

## 1. What search is for

A PM's knowledge is spread across many project folders and many Claude Code conversations. Search finds it again, by meaning and by exact words, across **every project at once**, so the person doesn't have to remember where something was written or which session discussed it.

Five moments it must serve (from the PRD's scenarios):

| Moment | What happens |
|---|---|
| **Recall** | "Where did we land on saved cards?" The answer is a paragraph in `checkout-redesign/docs/prd-v2.md` and a back-and-forth in a session in another project. Both appear near the top of one list, each labelled with its project and kind. |
| **Paraphrase** | They type "customers charged twice"; the notes say "duplicate billing". The notes are found. |
| **Exact** | They paste `ERR_REFUND_409` or a quoted phrase. Every literal occurrence comes first, across projects. |
| **More like this** | One result is right; they want related files and sessions from every project. |
| **First run** | Months of history, index still building. Search works on what's indexed, most recent first, and says plainly what isn't covered yet. |

Claude uses the same search from its terminal (`duo2 search`); that path is built and needs no design.

## 2. Where it lives

- **`⇧⌘A` opens search** from anywhere in Duo (DL-46, like Chrome's tab search). It searches **all projects** by default, with a quick way to narrow to the current project.
- **`⌘K` is the Jump picker** (projects, groups, sessions by name), the toolbar field "Jump to a project, group or session". It's also not designed yet (handoff § 13). Geoff wants the two to **share UI** (DL-38): one surface that can jump or search. How they relate is question Q1 in § 7.
- **`⌘F` stays find-in-document** in the editor. Search must not take it.
- Both altitudes (All projects, inside a project) need it. Inside a project, results from that project get a modest boost but don't crowd out strong matches elsewhere.

## 3. What a result carries

Everything below exists in the built index today. Design for these fields; don't invent others without saying so.

| Field | Example | Notes |
|---|---|---|
| Project | `checkout-redesign`, or **Unfiled** | Unfiled: a session from a folder that isn't a project. Must be visibly labelled (PRD S-UNSORTED). |
| Kind | file · session · memory | Memory is Claude's own notes about a project. |
| Title | `docs/prd-v2.md` · "PRD v2 edits" | Files: path within the project. Sessions: their title. |
| Where | `L40–58` · `turn 7` | Lines for files; the conversational turn for sessions. |
| Snippet | ~200 characters around the match | Secrets are already redacted (`[REDACTED]`). |
| Matched by | meaning · words · exact | One or more. Exact matches always rank first. |
| Date | file modified, session last active | |
| Also in | `research-notes/docs/prd-v2-copy.md` | The same passage in other places, shown once with the others listed. |
| Archived | yes/no | Hidden unless "include archived" is on. |
| Score | relative only | **Never shown as a percentage or a confidence** (PRD FR-7.4.7). Order is the signal. |

Results are **grouped one per file or session** (its best passage), with a way to see every matching passage in that item.

## 4. What the person can do

| Action | Result |
|---|---|
| **Open** | A file opens in the project's right pane at the matched lines (the document view from flow-zoom-2). A session opens **read-only** at the matched turn. |
| **Resume** | A session result is resumed in its project's console (the existing console tabs). |
| **Send to Claude** | One or several selected results go to the active Claude session as **references** (paths with line ranges, session and turn), not pasted text. Which session is "active" needs the design's answer (Q4). |
| **Find similar** | From a result (or a file or session anywhere in Duo), show related content from every project with the same filters and layout. |

Filters: **project** (including Unfiled), **kind**, **date range**, **include archived** (off by default). Same filters as the CLI.

## 5. States to design

- Empty (nothing typed): what's useful here? Recent searches? Nothing? (Q3)
- Typing, results streaming in.
- Results, grouped; one item expanded to all its passages.
- Exact mode (a quoted phrase or identifier): how the person knows they're in it and leaves it.
- Find-similar mode, pivoted from a result: how it reads, how to go back.
- No results, with the filters that might be hiding them.
- **Coverage incomplete**: "Indexing: refunds-api-spec 212 of 340 files; sessions before Aug 12 not yet indexed." Visible near the results, not alarming.
- **First run**: index building from nothing.
- Index being rebuilt (the model changed): search unavailable for a few minutes.
- Error: the index can't be read.
- Keyboard focus everywhere; the whole thing must be usable without a mouse (FR-7.5.5).

## 6. Sample content

Use the fixture's world (`build-handoff/fixture.json`): topics Payments, Growth, Platform; projects `checkout-redesign`, `refunds-api-spec`, `fraud-rules-review`, `onboarding-v3`, `pricing-experiment-q4`, `api-deprecations`, Home. Real searches to show:

**"where did we land on saved cards"** (current project: `checkout-redesign`)

1. `checkout-redesign` · file · `docs/prd-v2.md` L40–58 · meaning, words · today: "…two interviewees said saved cards are the main reason they abandon guest checkout. Decision: keep saved cards out of v2 scope; log as open question Q3…"
2. `checkout-redesign` · session · "PRD v2 edits" · turn 6 · meaning · 4m ago: "You: Move saved cards into scope, or keep it out and log an open question? Claude: Keeping it out is consistent with non-goal #2…"
3. `checkout-redesign` · session · "Interview synth" · turn 11 · meaning · 2d ago: "…P4 and P7 both mention re-typing card details on mobile as the moment they gave up…"
4. `refunds-api-spec` · file · `docs/edge-cases.md` L112–130 · words · 3d ago: "…refunds to a saved card versus the original payment method…"
5. **Unfiled** · session · "quick q about card vaulting" · turn 2 · meaning · 3w ago: "…PCI scope for storing card tokens…"

**"customers charged twice"** → `refunds-api-spec` · file · `data/tickets.jsonl` record 418 ("duplicate billing after retry, two captures on one order"); `refunds-api-spec` · session · "Edge-case matrix" · turn 3; `fraud-rules-review` · file · `notes/velocity-rules.md` L9–20.

**`ERR_REFUND_409`** (exact) → `refunds-api-spec` · file · `spec/errors.md` L77; `refunds-api-spec` · session · "Edge-case matrix" · turn 9; `api-deprecations` · file · `comms/v1-sunset.md` L31.

**Coverage line:** "Indexing: refunds-api-spec 212 of 340 files · sessions before Aug 12 not yet indexed."

## 7. Open questions for the design to answer

- **Q1. One surface or two?** ⌘K jumps by name, ⇧⌘A searches content, and they share UI. Options: one field with two modes; ⌘K results with a "search contents" section at the bottom; separate surfaces built from the same parts. Show what you recommend.
- **Q2. Where results appear.** A floating panel over the window (like the peek, `⇧⌘P`), a sheet, or a mode of the right pane? It must work at both altitudes and not hide the terminal the person may need.
- **Q3. The empty state.** Recent searches, suggested scopes, or nothing at all?
- **Q4. "Send to Claude": to which session?** The console's selected session, the Home session, or a picker?
- **Q5. Facets.** Inline chips, a filter row, or typed syntax (`kind:session`)? The CLI uses flags; the UI shouldn't need syntax.
- **Q6. How "matched by" shows.** It helps people trust a meaning-only match, but it shouldn't clutter the row.

## 8. Prompts

**Prompt A: three concepts for search.** Using the Duo design system and the sample content in § 6, show three different answers to Q1 and Q2, each at the All projects altitude with "where did we land on saved cards" typed and results showing. One screen each at 1440×900, light appearance.

**Prompt B: the chosen concept, inside a project.** Same search from inside `checkout-redesign`, with its results boosted, and the project filter narrowed and widened.

**Prompt C: states.** § 5's states for the chosen concept: empty, exact, find similar, no results, coverage incomplete, first run, rebuilding, error.

**Prompt D: actions.** Open (file at lines; session read-only at a turn), resume, send to Claude (one and several), find similar, all from the keyboard. Show the focus path.

**Prompt E: components.** The result row at every state (default, hover, focused, selected, expanded, archived, Unfiled, exact), the filter controls and the coverage line, on a sheet like `look.html`.

## 9. What we want back

The same shape as `build-handoff/`, so it can be built and checked pixel for pixel:

- **Screens** at 1440×900, light, as HTML in the canvas, one per state, named like the existing ones (`search-overview`, `search-project`, `search-exact`, …), with PNG renders.
- **Fixture additions:** the queries and results above as a `search` section for `fixture.json`, so each screen renders from data.
- **Tokens:** reuse `tokens.json`. Any new token is an addition with its name, value and use; nothing existing changes. The accent (`needsYou`) still means "needs you" only, so it must not mark search matches.
- **Notes** in the style of the handoff README: sizes, spacing, states and interactions per screen, keyboard map (all chords carry ⌘; avoid ⌘\, ⌘⌥L, ⌘⌥;, ⌘⌥'), and anything left undecided.

## 10. Constraints

- **Typography:** SF Pro for UI, SF Mono for code and terminals (DL-36), the handoff's type scale.
- **Native macOS feel**, light only for now; a dark appearance comes later, so colours must be tokens.
- **No percentages, gauges or confidence bars** for relevance.
- **The accent is reserved** for "needs you".
- **Out of scope:** similarity analysis (clusters, duplicates reports, outliers), the curation view's use of search (that view isn't designed yet), settings for indexing (exclusions, throttling), anything about Claude's CLI output.
