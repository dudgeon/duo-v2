Duo is a native Mac app for product managers who run many Claude Code sessions at once. It organises those sessions into projects, shows which ones need you, and keeps each session's terminal beside the documents it works on. Design for one person on their own Mac, comfortable with Claude Code in a terminal but not an engineer, with six or more sessions running on a normal day. They value knowing what's waiting on them, confidence that nothing is lost, and low ceremony.

This system is the current state of Duo's design: what's approved, what's built, and what's built with a stand-in look while its design is pending. Read it in this order:
- this README;
- **Model**: Duo's objects and states;
- **Surfaces**: every screen and its status;
- the component you're working on;
- **Working on Duo's design**: how to read the targets and hand work back.

Every component README starts with a **Status** line:
- **Designed**: built to an approved target screen.
- **Designed, changed by decision**: a target, amended by a later decision (DL-n).
- **Stand-in**: built from a decision; its look waits on design (DB-n).
- **Designed, not built.**
- **Not built.**

Stand-ins are open for design. Decisions are not: propose a change, don't redraw it silently.

Duo is SwiftUI, not a web app. There's no component library to mount, and `window.Duo` declares nothing. Each component's preview is a static recreation from the tokens, and its README names the SwiftUI view to build from. Design with the tokens and these guidelines; don't look for components to import.

## Principles

- **Two altitudes, one window.** *All projects* shows everything in flight. *Inside a project* is a three-pane workspace. The user zooms between them (⌘↑ out, a click or Return in).
- **The dark pane is whoever you're talking to.**
  - At All projects it's Home's terminal, on the left.
  - Inside a project it's the session console, in the middle.

  Everything else is light chrome on `pane` and `ground`.
- **The terminal is Claude Code's own TUI, untouched.** Duo draws nothing inside it. Every Duo affordance lives in the chrome around it.
- **Native macOS, system faces.** SwiftUI with AppKit, SF Pro and SF Mono, native menus, sheets and popovers. The system draws the window frame, toolbar and popover shape; design everything else.
- **Sessions are the spine.** Every Claude Code session on the Mac is listed, from Claude's own logs, with no setup. Projects, tasks and groups organise sessions; none is required.
- **Attention first.** Order lists by what needs the user: needs you → ready for review → working → idle → resolved, longest wait first. A group or task shows the state of its most urgent session.
- **One accent, and it means "needs you".** `needsYou` (`needsYouOnConsole` on the dark pane) marks only sessions waiting on the user. Health (`At risk`, `Off track`) is plain text. Never use the accent for selection, links, brand or decoration.
- **Plain files are the truth.** Projects are folders with `PROJECT.md`, Home a folder with `HOME.md`, tasks are Markdown notes. Duo never hides state the user can't see in Finder or Obsidian.
- **Never lose a session.** Destructive actions (Delete Session…, Move into Home…) confirm in a sheet. Everything else undoes with ⌘Z.

## Content

Write the way a knowledgeable colleague talks: plain, short, specific. Sentence case. No exclamation marks, no apologies, no emoji. Name things by what the user recognises (a session, a project, a folder) rather than by how they're stored.

- **Messages say what happened and what to do next.** "No session open in refunds" / "Pick up where you left off, or start fresh in this folder." · "No Home folder yet" · "example.com isn't on your allowed sites".
- **Buttons are verbs, in sentence case:** `Start Claude here`, `Resume Reading note 1`, `+ New session`, `+ New task`, `Choose Home Folder…`.
- **Menu items follow macOS:** Title Case, with an ellipsis when a sheet or picker follows. Examples: `Copy Link`, `Make a Task`, `Archive Session`, `Move into Home…`, `Delete Session…`, `New Browser Tab`.
- **Wait times** read `now`, `4m`, `1h`, `3d`.
  - Show them for needs-you, working and idle sessions; never for ready for review.
  - A session open in Duo reads `at prompt` or `working` instead.
  - Never truncate a wait time.
- **Names** (sessions, projects, files) take one line and truncate the tail.
- **Untitled sessions:**
  - Until Claude titles a session, show the user's first words in quotes: `“Summarise the six buyer…”`.
  - Before anything is typed, show its start time: `Session 4:12 PM`.
  - Never `New session`.
- **Questions** from Claude show verbatim, never summarised, and wrap.
- **Counts** follow a middle dot: `NEEDS YOU · 2`, `task · 3`, `Earlier · 5`, `21 idle, resumable ›`.
- **Paths** abbreviate the home folder: `~/repos/duo-v2`.

## Colour

Light chrome, from `tokens.json`:
- **Grounds:** `ground` for the toolbar and sheet backgrounds; `pane` for panes, cards, popovers and buttons.
- **Selection:** `selected` for the selected row and for Claude's additions to a document. `activeTint` marks sessions with a tab open in Duo (provisional, DB-33).
- **Text:** `text` for primary text, and the review and working glyphs. `text2` for secondary text, the idle and resolved glyphs, and chevrons.
- **Lines:** `rule` for pane dividers and card or field borders. `controlEdge` for button and pill borders, dashed borders and the group rule.
- **The accent:** `needsYou` only (above). `onNeedsYou` is text on the filled chip.

The dark pane uses `console`, `consoleRule`, `consoleText`, `consoleText2` and `needsYouOnConsole`. These are fixed in every appearance. Inside terminals, use only the `terminal*` colours (DB-2), with `terminalHC*` when Increase Contrast is on.

`scrim` dims the window behind the search modal. The `placeholderBar` colours exist only in design targets; don't build them.

Light is the only approved appearance. A dark set exists in the source as provisional and unapproved (DB-29). Don't design dark screens unless asked.

## Type

System faces only: `ui` (SF Pro) and `mono` (SF Mono). Don't bundle fonts, and never letter-space the console.

- `body` 13/20 is the default; `bodyEmphasis` 13/20 semibold for names that lead a row or card.
- `title` 14/20 semibold for pane titles and document headings.
- `control` 12/16 for buttons and hints; `chip` 12/20 semibold for the needs-you chip.
- `sectionLabel` 11/16 semibold, capitals, +0.66 tracking, for section labels (`NEEDS YOU · 2`, `payments /`).
- `pill` 11/16 for count pills.
- `mono` 12/19 for console chrome and file names; `monoActiveTab` (500) for the selected console tab; `monoPath` 11/20 for the project path under FILES.
- `searchField` 17/24 for the search modal's field only.

## Space, shape, layout

- **Sizes** are points, shown as px.
  - Pane content insets `panePadding` 16.
  - Rows are `rowFile` and `rowTileSession` 24, `rowSession` 26, `rowGroup` 28.
  - Buttons are `buttonHeight` 26: 12/16 label, padding 4 10, 1 `controlEdge` border, `radiusControl` 6, `pane` fill.
- **Gaps:**
  - `gapGlyphToLabel` 6, `gapRowItems` 8, `gapButtonToButton` 6;
  - `gapCardToCard` 10, `gapTileToTile` 10, `gapMapColumns` 14.
- **Radii:** 6 for controls, cards, selection fills and fields; `radiusPill` 9; `radiusPopover` 10.
- **Borders:**
  - `borderHairline` 1 for rules and cards;
  - `borderEmphasis` 1.5 for the chip, question box, selected card and thread rule;
  - `borderFilesDivider` 2 above FILES;
  - `borderDash` (3, 2) for the New project tile and drop targets.
- **Shadow:** `shadowPopover` only, on popovers Duo draws (search, menus, the idle list, drag cards). Nothing else carries a shadow; separate things with `rule`, not elevation.
- **The window** is designed at 1440 × 900, with a minimum of 1280 × 800.
  - All projects: left `paneOverviewHome` 340 · flexible map · right `paneOverviewActionColumn` 340.
  - Inside a project: left `paneProjectSessionsAndFiles` 300 · flexible console · right `paneProjectRight` 460.
- **The toolbar** is native: the system draws it 40 high on macOS 27. Content sits below it.

## State glyphs

Every session state has its own shape, 9 pt in a 10 × 10 box, so colour is never the only signal. The SVGs are in `assets/Glyphs/`.

| State | Shape | Colour |
|---|---|---|
| Needs you | filled circle | `needsYou` (`needsYouOnConsole` on the console) |
| Ready for review | filled diamond | `text` |
| Working | ring, stroke 1.5 | `text` |
| Idle | dash, stroke 1.6, round caps | `text2` |
| Resolved | check, stroke 1.6 | `text2` |

Pair every glyph with a visible label or an accessibility label. Never animate a glyph; working is a still ring, not a spinner.

## Iconography

Duo uses SF Symbols where the system has the right one, and a few drawn icons where it doesn't. Draw icons as single-weight strokes with round caps and joins, in `text2` (`consoleText2` on the console). Never use emoji or filled pictograms.

- **Drawn** (`assets/Icons/`):
  - the chevrons;
  - search's file and session marks;
  - the shell prompt mark and more-tabs mark on the console;
  - eight property-type icons for the properties block (DB-16).
- **SF Symbols:**
  - `sidebar.left` (toggle), `magnifyingglass` (search);
  - `folder`, before a map column label (stand-in, DB-38);
  - `square`, for a task line's box (stand-in);
  - `safari`, `chevron.left` and `chevron.right` in a browser tab's bar (stand-in, DB-20).

Duo has no logo yet. Set the name in plain type.

## Motion

Minimal: state changes are noticeable but never animated for their own sake.
- Glyphs swap in place.
- Lists use the system's default insert and remove.
- Popovers and sheets use the system's animations.
- Honour Reduce Motion.

## Accessibility

Contrast on the light grounds:
- `text` on `pane`, `ground` and `selected`: 15.8 / 14.4 / 13.3.
- `text2` on the same: 6.1 / 5.5 / 5.1.
- `needsYou` on `pane` and `ground`: 5.2 / 4.7.
- White on `needsYou`: 5.2.
- `controlEdge` on `pane`: 3.1.

On the console: `consoleText` 14.6 and `consoleText2` 6.9 on `console`, and `needsYouOnConsole` 6.4.

Known gaps, kept as they are in the source:
- `rule` on `pane` is 1.6:1, so card and field borders are decoration, never the only boundary.
- `controlEdge` on `ground` is 2.8:1.

Every needs-you surface also says "needs you" in words. Every action is reachable from the keyboard and by `duo2` (the command line Claude sessions use to drive Duo). Focus returns to where it was when a popover or sheet closes, including into a terminal.

## Keyboard

All Duo shortcuts carry ⌘, so they never collide with keys typed into Claude Code. The map is locked: a new shortcut needs a decision-log entry (DL-34).

| Keys | Action |
|---|---|
| ⇧⌘A | Search everything (names first) |
| ⌘↑ | All projects |
| ⇧⌘H | Home, its terminal focused |
| ⇧⌘P | Needs you elsewhere (the peek) |
| ⌘↩ | Jump into the peek's selected project |
| ⌃⌘S | Toggle the left pane |
| ⌘T / ⇧⌘T / ⌥⌘T | New Claude session / new shell / new browser tab |
| ⌘L | A browser tab's address field |
| ⌘N / ⇧⌘N | New Markdown file / new folder |
| ⌘S, ⌘B, ⌘I | Save, bold, italic in the editor |
| ⌘D | Send selection to Claude |
| ⌘W / ⇧⌘W | Close tab (never the window) / close window |
| ⌥⌘0, ⌥⌘← → | Right pane, previous and next pane (not built) |
