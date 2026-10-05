# Duo search — design handoff

Status: designed · 2026-10-04 · Owner: Geoff · Answers `docs/design/search-design-brief.md`. Written by the design session (Claude).

> **Since this handoff (2026-10-05):**
> - Jump merged into search and `⌘K` is free (DL-80): ignore the Jump scope and `⌘K` lines, and `screens/search-jump.html`.
> - The empty-state and error copy that replaced them is DL-81.
> - The [P] chords were accepted (DL-79), with Send to Claude as `⌘D`.
>
> Built as designed otherwise.

Same shape as `docs/design/build-handoff/`, and the same rule: the files in `screens/` are the target. This document explains them and covers what a picture cannot show.

| File | What it is |
|---|---|
| `screens/search-*.html` | 18 targets, exported unchanged from the canvas (page "Search", rows C to F). 1440×900 except the sheet. |
| `screens/manifest.json` | Every screen, its size, what it shows, and its canvas board. |
| `fixture-search.json` | A `search` section to merge into the fixture: queries, results, coverage, recents. |
| `tokens-additions.json` | One colour, one type size, and the modal's sizes. Nothing existing changes. |
| `tools/render-references.sh` | Renders the PNGs with build-handoff's renderer. Run on the Mac. |

PNGs are not included: they need the Mac's system faces. I rendered every screen in a Linux browser with fallback fonts to check layout, and nothing overflowed or collided there.

`build-handoff/tools/compare.sh` looks for targets in its own `screens/` folder, so it needs pointing at this one.

## How to read this

- **[G]** Geoff decided it on the canvas.
- **[B]** The brief requires it.
- **[P]** My proposal. Not reviewed beyond Geoff seeing the screens. Change freely.

---

## 1. What Geoff decided [G]

1. **One modal, Spotlight-style, with a preview of the selected result**, over a dimmed window. Chosen over a panel under the toolbar field, a tab in the right pane, and a full search view (canvas rows A and B).
2. **Search is the default; Jump is the second scope of the same modal.** `⇧⌘A` opens Search, `⌘K` opens Jump. The toolbar field now reads `Search all projects ⇧⌘A`.
3. **The flow:** `⇧⌘A`, type, arrow down to a result, **Return runs the main action** (open the file, resume the session), **Tab shows the other actions**.
4. **Other actions he named:** open in split view (not built yet), copy path, send to Claude, plus whatever else makes sense.

Everything below that is not marked [G] or [B] is [P].

## 2. Answers to the brief's questions

| Q | Answer |
|---|---|
| Q1 One surface or two? | One. A scope switch in the field row: `Search ⇧⌘A` · `Jump ⌘K`. Jump's list ends with `Search contents for "…"`. [G] for one modal with Search first; the rest [P]. |
| Q2 Where results appear | A modal centred in the window, with the window dimmed behind it. Same position at both altitudes. It covers the console while open; Geoff chose it knowing that. [G] |
| Q3 Empty state | Recent searches, and three lines of help. No suggestions. [P] |
| Q4 Send to Claude: which session? | The session in the dark pane at the current altitude: Home's selected session at All projects, the console's selected session inside a project. The action names it (`Send to Claude in Morning triage`). [P] |
| Q5 Facets | A filter row of pop-up buttons (project, kind, date) and an `Include archived` checkbox. No typed syntax. [P] |
| Q6 Matched by | Matched words are semibold in the snippet. A meaning-only match gets `by meaning` at the end of its meta line. An exact match gets an `exact` pill. No colour. [P] |

## 3. The modal

Reference: `search-overview.html`. Sizes in points.

| Part | Spec |
|---|---|
| Position | Centred horizontally, 92 from the top of the window. 960 wide at 1440 (left 240). Height follows content. |
| Scrim | The whole window, toolbar included, under `scrim` (`#1F2328` at 32%). [G: dimmed; value P] |
| Panel | `pane` fill, 1 `rule` border, radius 10, the popover shadow. |
| Field row | 52 high, padding 0 16. Search icon 16. Input 17/24, the one new type size. Scope switch on the right. |
| Scope switch | Segmented, 1 `controlEdge` border, radius 6. Active segment: `selected` fill, semibold. Each segment shows its chord in `text2`. |
| Filter row | Padding 0 16 10, then a 1 `rule` line. Pop-up buttons are the standard button with a chevron; one that is set has `selected` fill and a semibold label. A trailing hint may sit on the right in 12/16 `text2`. |
| Body | Two columns, minimum 440 high. List: 420 wide, padding 6 8 8, rows 2 apart. Preview: the rest, 1 `rule` on its left, padding 14 20 16. |
| Coverage line | Its own row under the body: padding 8 18 10, 1 `rule` above, working ring, 12/16 `text2`. Shown only while coverage is incomplete. [B] |
| Footer | 34 high, `ground` fill, 1 `rule` above, 12/16. Left, in `text`: what Return will do. Right, in `text2`: the other keys. |

**Result row.** Padding 8 10 10, radius 6.

1. Kind icon (12, `text2`), title, pills, date right-aligned in `text2`. File titles are the path in the mono face, 12, weight 500. Session titles are 13 semibold.
2. Meta, 12 `text2`, indented 20: project (in `text`) · kind · where · `by meaning` when it applies. An Unfiled session shows an `Unfiled` pill where the project goes [B].
3. Snippet, 13/20 `text2`, at most two lines, matched words semibold in `text`.

States, on `search-look.html`: default; hover (`ground` fill); selected, one or several (`selected` fill); exact (pill); Unfiled (pill); archived (pill, [B: labelled archived, DL-49]).

**Preview.** For a file: path, project and lines, then the passage in a `selected` block with its heading above, `MORE IN THIS FILE · n` listing every other matching passage, and `ALSO IN · n` for the same passage elsewhere. This is where "one result per item, with a way to see every passage" lives [B]. For a session: the matched turn in a `selected` block, the turns either side as context. For several selected: what is selected and what Return will send. For Jump: the project or group.

**Action menu.** 300 wide, hung off the selected row (8 from its right edge, 30 below its top). Rows 24 high, the chosen one in `selected` fill, chords right-aligned in `text2`, groups separated by a 1 `rule` line. If it is built as a native menu, the system draws its chrome; match the items, their order and their chords.

**Relevance is never shown as a number.** Order is the only signal [B].

## 4. Actions

Return runs the first row. Tab opens the menu. [G]

| | File result | Session result |
|---|---|---|
| **Return** | **Open**, in its project's right pane at the matched lines | **Resume**, in its project's console |
| Open another way | Open in split view `⌥⌘↩` (not built) · Go to the project | Open read-only at the turn `⇧⌘↩` · Resume as a fork · Open in split view `⌥⌘↩` · Go to the project |
| Claude | Send to Claude in ‹session› `⌘↩` · Find similar · Show all n passages | Send to Claude in ‹session› `⌘↩` · Find similar |
| Copy | Copy path `⌥⌘C` · Copy passage `⇧⌘C` · Copy Markdown link | Copy passage `⇧⌘C` · Copy resume command `⌥⌘C` |
| Finder | Reveal in Finder `⌘R` | |

- Geoff named Return's behaviour, split view, copy path and send to Claude. The rest of the list, its grouping, and every chord are [P].
- The brief made read-only the way a session opens. Geoff then made Resume the Return action, so read-only is in the menu.
- Send to Claude inserts references (path with lines; session with turn) into that session's input and does not submit. DL-45 allows typing into a live session. [B for references; P for not submitting]
- With several results selected, Return sends them all (`search-multi.html`).
- Named but not drawn: `File under a project…` on Unfiled sessions (DL-4), `Carry on in a new session` on archived ones (DL-47).

Where Return lands: `search-open-file.html` (the passage outlined in 1.5 `text`, labelled `L40–58 · from search`, matched words semibold) and `search-open-session.html` (a right-pane tab, a `read-only` pill, a `Resume` button, the turn outlined the same way). The outline is separate from the `selected` fill that marks Claude's additions, so both can show at once.

## 5. Keys

DL-34 says a chord change needs a log entry. All of these are proposals except the two that are already logged.

| Key | Does | Status |
|---|---|---|
| `⇧⌘A` | Open Search | DL-46 |
| `⌘K` | Open Jump, or switch to it | DL-34 |
| `⇧⌘A` again, inside a project | Narrow to this project, then back to all projects | P |
| `↑` `↓` | Move through results; focus stays in the field | G |
| `↩` | The main action | G |
| `tab` | Actions for the selected result | G |
| `⇧tab` | Filters | P |
| `⇧↑` `⇧↓` | Select several | P |
| `⌘E` | Exact on or off | P |
| `⌘↩` `⌥⌘↩` `⇧⌘↩` `⌥⌘C` `⇧⌘C` `⌘R` | Direct chords for menu items (§4) | P |
| `esc` | Back one step (menu, then find-similar, then close) | P |

`⌘↩` already means "jump into the selected peek card's project" in the peek. Here it would mean Send to Claude. They never show at once, but it is one chord with two meanings.

Tab opening actions means Tab does not walk the controls. Arrows cover the list, Shift-Tab reaches the filters, and the menu is a list. VoiceOver users need the menu reachable by its own action as well.

## 6. Screens and states

| Screen | Shows | Notes |
|---|---|---|
| `search-overview` | Results at All projects | The canonical screen. Carries the coverage line, so it is also "coverage incomplete". |
| `search-project` | The same search from inside `checkout-redesign` | All projects in scope; this project's results come first [B: a modest boost]. Hint on the right of the filter row. |
| `search-project-narrowed` | Scope set to this project | The scope pop-up shows the project and is filled. `2 more in other projects` widens again. |
| `search-jump` | Jump scope | Names only: projects, groups, sessions. Session and group rows carry their state glyph. Always ends with `New project "…"` (LR-25) and `Search contents for "…"`. No filter row. |
| `search-empty` | Nothing typed | Recent searches; help on the right. |
| `search-typing` | Results arriving | What has arrived, then `Searching sessions…` with the working ring. |
| `search-exact` | A quoted phrase or an identifier | An `Exact` chip leads the filter row and removes itself when clicked; rows carry `exact`; the hint names `⌘E`. Exact turns on by itself for quoted phrases and identifier-like input. |
| `search-similar` | Find similar | The field holds `Similar to` and a chip for the source; typing narrows. `esc` returns to the previous results, and the footer says which. No `by meaning` labels, since everything here is by meaning. |
| `search-none` | No results | Says which filters are on, how many results there are without them, and offers `Clear filters` (Return) and `Include archived`. |
| `search-first-run` | Index building from nothing | A notice above the results in `ground` fill. Results are what is indexed so far, newest first. |
| `search-rebuilding` | Index being rebuilt | Field disabled. Says why and roughly how long. Jump still works. |
| `search-error` | Index unreadable | `Rebuild the index` (Return) and `Show details`. Jump still works. |
| `search-actions-file`, `-session` | Tab pressed | §4. |
| `search-multi` | Two selected | §4. |
| `search-open-file`, `-session` | After the action, no modal | §4. |
| `search-look` | The parts | Row states, scope switch, filters at rest and set, coverage line, menu, scrim, keys. |

The backdrop in each modal screen is an existing target (All projects or the project) and keeps build-handoff's exemptions. One thing in it is new: the toolbar field's label. The build-handoff targets still show `Jump to a project, group or session ⌘K` and were not re-exported.

## 7. Sample data

`fixture-search.json` holds the brief's three queries and their results, the coverage line, and what the screens add. Additions are listed in its `$additions` key so they can be told apart from the brief's content: the passage count and two extra passages for `docs/prd-v2.md`, dates for the exact results, the recent searches, the first-run figures, and one archived session used only on the sheet.

## 8. Tokens

`tokens-additions.json`. `scrim` is the only new colour. The field's 17/24 is the only new type size. Hover uses the existing `ground`. The accent is not used anywhere in search except where a session in the backdrop or in Jump needs you [B].

## 9. Not designed

- The filter pop-ups opened, and a date-range picker.
- A `memory` result: its icon and row.
- What a sent reference looks like in the terminal. That is Claude Code's output, and the back end's format.
- Find similar started from elsewhere in Duo (a file in the tree, a session row).
- Jump's own empty state (recents, starred), its action menu, and the create-project flow.
- Split view itself.
- Windows smaller than 1440×900. Suggest: stay centred, 92 from the top, width the smaller of 960 and the window less 96, list column fixed at 420, list scrolls.
- Dark appearance.
- Motion. Suggest none beyond a short fade for the scrim, off with Reduce Motion.
