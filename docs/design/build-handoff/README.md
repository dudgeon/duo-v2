# Duo v2 — Build handoff from the design canvas

Status: for build · 2026-10-03 · Owner: Geoff · Written by the design session (Claude), for the Claude Code agent building Duo.

> **Still the target, with these superseded (2026-10-05):**
> - The `⌘K` JumpField became the `Search all projects ⇧⌘A` field (DL-80).
> - `project.html`'s session list by state became Needs you / Open / Today / This week / Earlier (DL-91).
> - The topic labels, "Project not under a topic" and the Elsewhere placement became folder columns with a folder mark and slash, and an unlabelled first column (DL-83, DL-89, DL-92).
> - The Project tab card became `PROJECT.md` itself (DL-60).
> - "Tasks are parked" no longer holds: tasks are notes with linked sessions (DL-87, DL-93).
> - The §4.1 terminal palette is now designed (surfaces-handoff DB-2).
> - Several §13 items are designed in later handoffs.
>
> The Duo design system: `docs/design/system/`, published at https://claude.ai/artifact/QMapKeLYS3TVV36QKEc6MH summarises what's current.

This folder is the output of the design pass that `docs/design/claude-design-handoff.md` asked for. **The designs themselves are in `screens/`. They are the target. This document explains them; it does not replace them.**

| File | What it is |
|---|---|
| `screens/overview.html` | **Target.** All projects (the zoomed-out altitude). |
| `screens/project.html` | **Target.** Inside a project. |
| `screens/flow-zoom-1.html` … `-4.html` | **Targets.** One flow, four steps: zoom in, peek, answer elsewhere, zoom out. Linked to each other. |
| `screens/look.html` | **Target.** The look on one sheet: type, colour, glyphs, pieces. |
| `screens/wireframes/group-page.html`, `grouping.html` | Wireframes. Structure only, for two surfaces that have no target yet. |
| `screens/manifest.json` | Every design file, its size, and the canvas board it came from. |
| `tokens.json` | Colours, type, radii, sizes and glyph shapes, read from the targets. |
| `fixture.json` | The data shown on every target, for previews and tests. |
| `tools/render-references.sh` | Renders every design file to a PNG. Run once, on the Mac. |
| `tools/compare.sh` | Puts an app screenshot beside its target and shows the difference. |
| `README.md` | Intent, behaviour, and everything a picture cannot show. |

---

## 0. The screens are the target

Geoff's instruction: the coding agent must be able to open the actual designs and build towards them as a literal target.

**The rule.** At 1440×900, light appearance, with `fixture.json` loaded, the app window looks like the matching file in `screens/`. Where this document's prose and a target disagree about how something looks, the target wins. Where there is no target for a surface (§13), build a stub and ask for a design; do not invent one.

The target files are the approved canvas boards, exported unchanged: same markup, same inline values. They are pictures written in HTML. Match what they draw; do not port their markup.

### 0.1 Seeing the designs

- **Open them.** They are plain files: `open docs/design/build-handoff/screens/overview.html`, or serve the folder (`python3 -m http.server 8766 --directory docs/design/build-handoff`) and use your browser or preview tool. The flow screens link to each other.
- **Measure them.** Every size, colour and gap is an inline style. Read the file, or use the browser inspector.
- **Render them.** Once, on the Mac:

  ```
  bash docs/design/build-handoff/tools/render-references.sh
  ```

  This writes `screens/png/<name>@2x.png` for every design file, at exactly twice the design size. It must run on macOS, because the designs use the system faces. It needs Google Chrome or another Chromium-family browser (`CHROME=/path` to choose one). Commit the PNGs so the target is frozen.
- **The live canvas.** The designs were made at https://claude.ai/artifact/Hip1Qk4vRHq2kWwXWnigic (Geoff's, private). The files here are a snapshot from 2026-10-03. If your session has the Artifact tool you can read a board directly: action `read`, that URL, path `project/<board>` with the board names from `screens/manifest.json`. If the canvas has moved on, ask for a fresh export; do not edit the files in `screens/`.

### 0.2 The loop, for every screen you build

1. **Put the app in the state the target shows** (table below), in a 1440×900 window, light appearance, fixture data.
2. **Capture it** as a PNG: the whole window, or a snapshot of the content view.
3. **Compare:**

   ```
   bash docs/design/build-handoff/tools/compare.sh overview path/to/app.png            # whole window
   bash docs/design/build-handoff/tools/compare.sh overview path/to/view.png --content-only   # no toolbar in the capture
   ```

   It prints the path of one image with three panels: TARGET, BUILD, DIFFERENCE. In DIFFERENCE, black is identical and bright edges are things in the wrong place or the wrong colour. Read that image, then read the target and the build at full size, region by region.
4. **Fix and repeat** until it meets the bar in §0.3.
5. **Keep the last comparison image** with the change, so Geoff can review it.

Build the fixture mode and the capture command first (§15, slice 1). Every later slice is checked with them.

| Target | State to reproduce |
|---|---|
| `overview` | All projects. Home tab: Morning triage. Selected action card: Copy review pass 2. |
| `flow-zoom-1` | As `overview`, with keyboard focus on the checkout-redesign tile. |
| `project`, `flow-zoom-2` | Inside checkout-redesign. Group PRD v2 selected and expanded. Console tab: PRD v2 edits. Right tab: `prd-v2.md`. File `docs/prd-v2.md` selected. Chip: 2 need you. |
| `flow-zoom-3` | As `project`, with the peek open and its first card selected. |
| `flow-zoom-4` | All projects after Copy review pass 2 was answered: 2 need you, 5 working, that session working with `now`. Selected: PRD v2 edits, in the map and the action column. |
| `look` | Not a window. A reference sheet for a component gallery or previews. |

### 0.3 What "matches" means [P]

- Every element in the target is in the build, in the same order and grouping, and nothing is added.
- Pane edges, rules, row heights and other fixed sizes: within 1 pt.
- Text: the same string, size, weight and colour, positioned within 2 pt. Letter shapes will differ slightly between a browser and AppKit; that is expected.
- Colours: the exact token values. Sample the pixels.

### 0.4 What is not a target

The targets contain a few things the app must not copy literally. These are the only exemptions.

| In the target | In the app |
|---|---|
| Window frame, traffic lights, toolbar background | Drawn by the system. Match what is in the toolbar and its order, not its pixels. If the system's compact toolbar is not 38 high, the system wins and the panes start below it. |
| Everything in a dark pane below its tab strip | A real terminal running Claude Code. Match the pane's position, its background, and its tab strip. Use a placeholder view until terminals exist. |
| Grey bars | Placeholder content. Do not draw them. |
| The document's body type in the right pane | The editor's own styling. Match the pane, the tab strip, and the "added by Claude" block. |
| Reply buttons on cards: `Approve`, `Move into scope`, `Log open question`, `Route 3`, `Reply…` | Blocked on §12 Q1. Build them behind one switch, off. Compare with the switch on. |
| Popover arrow, corner and shadow | Drawn by the system popover. Match its width, contents and anchor. |

Everything else is literal: buttons, pills, the chip, cards, rows, selection shapes, rules, spacing, type. If a stock control does not look like the target, style it until it does.

---

## How to read this

Every claim carries one of four sources. Treat them differently.

- **[G]** Geoff said it during the design session. Settled.
- **[C]** Drawn on the canvas and reviewed by Geoff without objection. Build it; small details may still move.
- **[P]** My proposal. Not reviewed. Sensible default, change freely.
- **[R]** Required by a repo doc (`LR-n` in `legacy-requirements.md`, `DL-n` in `decisions.md`).

**Precedence.** `decisions.md` says it wins over other docs. This handoff does not change that. Where the canvas and the repo docs disagree, the disagreement is listed in §12 with a recommended default so the build is not blocked. Geoff's direct statements in the design session are newer than the "decided by default" items in `decisions.md`; §14 proposes log entries for him to confirm.

Measurements are read from the target markup, in points (1 px in a target = 1 pt). Geoff reviewed the designs on the canvas.

---

## 1. Read this first

1. **Two altitudes, one window.** *All projects* shows everything in flight. *Inside a project* is the three-pane workspace. You zoom between them. [G]
2. **The dark pane is whoever you are talking to.** At All projects it is the Home terminal, on the left. Inside a project it is the session console, in the middle. Everything else is light. [G]
3. **The terminal is Claude Code's own TUI, untouched.** Duo draws nothing inside it. Every Duo affordance lives in the light chrome. [G]
4. **Native macOS, system faces.** Swift, SwiftUI with AppKit where needed, SF Pro and SF Mono [G]. The system draws the window frame, toolbar and popover shape; everything else matches the targets (§0.4).
5. **Sessions are the spine. Tasks are parked.** Navigation never depends on a task existing. [G]
6. **One decision blocks part of the peek:** how the chrome answers a waiting session, given LR-15 forbids typing into it. See §12 Q1 before building any reply button.

---

## 2. The model as designed

### 2.1 Objects

| Object | What it is | On disk | Source |
|---|---|---|---|
| Topic | Area of responsibility. Light grouping only. | Parent folder, e.g. `~/work/payments/` | brief §3 |
| Project | Goal, health, next milestone. Home is one, pinned. | A folder with `PROJECT.md` | brief §3, DL-18 |
| Session | What you see, answer and resume. Carries the attention state. | Claude's transcript + Duo's index | brief §3 |
| **Thread** | A fork family folded into one row. Forks fold on their own. | Derived from fork lineage | [G] |
| **Group** | A named bundle of related threads. Made by hand, or by a session running a CLI verb. | Duo-owned, in `.duo/sessions.json` (DL-1) | [G] |
| Document | The deliverable being read and edited. | Any file in the project | brief §3 |
| Task | Optional. Found in project files when there are any. | `tasks/*.md` (DL-6, DL-13) | parked [G] |
| Ask | An incoming request in Home's inbox. | Not specified | [P], not in the brief |

Geoff on tasks: "task handling is still pretty tbd; projects will sometimes have project files, those files will sometimes have tasks; sometimes those will be associated with claude sessions; and sometimes claude sessions will maintain their own tasks…" So: reserve one slot for tasks on the Project tab and the group page, and build nothing that needs them.

### 2.2 Attention rolls up

A session carries one of five states. Its thread, group, project and topic each show the most urgent state underneath them. A group is **one row**, in the state of its most urgent session, so lists stay sorted by what needs you. [C]

Order, most urgent first: needs you → ready for review → working → idle → resolved. Within a state, longest wait first. [R: brief §3.3, LR-1]

The mapping from Claude's signals (`claude agents --json`, hooks) to these five states is LR-1 to LR-4's job, not this document's.

### 2.3 Two altitudes

| | All projects | Inside a project |
|---|---|---|
| Question it answers | What is in flight, and what is waiting on me? | Where was I, and what is this session doing? |
| Left | Home terminal (dark), 340 | Sessions by state, over a file tree, 300 |
| Middle | Project map, columns by topic | Session console (dark) |
| Right | Action column: needs you, ready for review, 340 | Tabs: Project · group page · documents, 460 |
| Leave by | Enter or click on a project tile | "All projects" in the toolbar |

"All projects" is the name of the zoomed-out surface (DL-2). "Home" is the triage project folder and its terminal.

---

## 3. Screens

### 3.1 Window and toolbar

Reference: every screen. [C]

- One window (legacy-requirements D10). Design size 1440×900; must hold at 1280×800 (brief §7).
- Unified compact toolbar, 38 high: `.windowToolbarStyle(.unifiedCompact)`. The system draws the traffic lights, window shape and toolbar material; the target's are approximations (§0.4). On macOS 26 let the toolbar take the system look rather than forcing the flat `ground` fill.
- Leading: sidebar toggle. It collapses the left pane at either altitude. Collapsing never kills the terminal in it [R: LR-13].
- Trailing: Jump field, 300 wide, placeholder "Jump to a project, group or session", hint `⌘K`. Use a native search field. It opens the ⌘K palette (LR-25), which is not designed yet.

Toolbar content differs by altitude:

| Altitude | Content after the sidebar toggle |
|---|---|
| All projects | **All projects** (13 semibold), then four counts, each with its state glyph: `3 need you` (semibold, `needsYou`), `2 to review`, `4 working`, `14 idle` (`text2`). Gap 16. |
| Inside a project | `All projects` as a link (`text2`, underlined) › chevron › **project name** (13 semibold) › the needs-you chip. Gap 8. |

**Breadcrumb link.** Clicking "All projects" zooms out. [G]

**Needs-you chip.** [G: it lives in the top rail] Shows the count of sessions needing you **outside** the current project [C]. Hidden at zero [P]. Rest: 1.5 `needsYou` border, radius 6, 12 semibold `needsYou` text, filled-circle glyph, padding 0 8. Open: filled `needsYou`, white text and glyph. Click toggles the peek popover (§3.4).

### 3.2 All projects

Reference: `screens/overview.html`, `flow-zoom-1.html`, `flow-zoom-4.html`. [G: layout; C: details]

Geoff: "project map, with a left pane as a thin active terminal for the home pane, your current project based columns, and … the peek column for any sessions that need action."

**Left: Home terminal, 340 wide, `console` background.**

- Header, 36 high: `★ home` (13 semibold, UI face), path right-aligned (`~/work/home`, mono 12, `consoleText2`).
- Tab strip, 32 high: one tab per live Home session, mono 12, state glyph before the name. Active tab weight 500 `consoleText`; others `consoleText2`.
- Body: the terminal view for the selected Home session. Everything below the tab strip in the target (inbox lines, the question, the numbered options, the `>` input) is illustrative TUI output. Duo does not draw it.
- At 340 wide the terminal is roughly 42 columns at 12 pt. That is intentional ("thin"); make the split resizable.

**Middle: project map.**

- Grid of topic columns, `repeat(3, 1fr)`, gap 14, padding 16.
- Column: topic label (11/16 semibold, +0.06 em, uppercase, `text2`), then project tiles, gap 10.
- Tile: 1 `rule` border, radius 6, padding 10 12 12, row gap 2.
  - Project name, 13 semibold.
  - Goal, 13, wraps.
  - Health · next milestone, `text2` (`On track · Exec review Oct 14`). Health alone when there is no milestone.
  - Live sessions (needs you, ready for review, working), each a 24-high row: glyph, name, wait time right-aligned in `text2`. First row has 6 above it. Ready-for-review rows show no time.
  - No live sessions: one `text2` row, "Nothing running".
- `+ New project`: 38 high, 1 dashed `controlEdge` border, radius 6, centred `text2`. Sits at the end of the last column in the target. The create-project flow is not designed.
- Footer, 34 high, top rule: idle glyph, `14 idle, resumable`, chevron. This is LR-1's compact tier. What it opens is not designed.

**Right: action column, 340 wide, padding 16, gap 10, scrolls.**

- `NEEDS YOU · 3` label in `needsYou`.
- One card per session needing you, longest wait first. Card: 1 `rule` border, radius 6, padding 10 12 12, gap 8.
  - Header: glyph, session name (semibold), wait time right in `text2`.
  - Project name, `text2`.
  - The pending question, **verbatim**, wrapping (brief §7).
  - Buttons, gap 6, wrapping. See §12 Q1 before building the reply buttons. `Open project` always works.
- A Home session needing you is **not** a full card, because the Home terminal is already on screen. It is a pointer: 1 dashed `controlEdge` border, padding 8 12, header as above with `home` after the name, second line `← Waiting in the Home terminal`. Clicking it should focus the Home terminal on that tab. [P]
- `READY FOR REVIEW · 2` label in `text2`, 6 above it.
- Review card: diamond glyph, name (semibold); project (`text2`); one line saying what was produced (`wrote readout.md, 1.2k words`); a `Review` button. Review opens the project with the deliverable in the right pane. The row leaves this list once the deliverable has been opened. [C]

**Selection is shared.** The selected action card (1.5 `text` border, question boxed in 1.5 `needsYou`) and the same session's row in the map (`selected` fill, semibold name) highlight together. [C]

**Tile focus.** A focused tile has a 2-pt `text` outline and an `Enter to open` hint, right-aligned in `text2`. [C]

### 3.3 Inside a project

Reference: `screens/project.html`, `flow-zoom-2.html`. [G: layout; C: details]

**Left: 300 wide.** No back row; the toolbar breadcrumb replaces it. [G]

- Project header: name (14 semibold), health · milestone (`text2`). Padding 14 16 4.
- Sessions, sectioned by state. Section label: 11/16 semibold caps, padding 12 16 4, `needsYou` colour for Needs you, `text2` otherwise. Empty sections are omitted.
- Rows:

| Row | Height | Layout |
|---|---|---|
| Group | 28 | Disclosure chevron, glyph, name (semibold), pill `group · 3` (1 `controlEdge` border, white, radius 9, 11/16), wait time. |
| Thread, inside a group | 26 | Indented under a 1.5 `controlEdge` left rule at x 21. Chevron, glyph, name, pill `thread · 2` (1 `rule` border), wait time. |
| Session | 26 | 10-wide spacer where the chevron would be, glyph, name, wait time. |

- Selection: inset rounded fill, `selected`, radius 6, 8 from the pane edges. This is the native sidebar selection shape.
- A single session with no forks is a plain row. `thread · n` appears only when n ≥ 2; `group · n` counts sessions, not threads. [C]
- Buttons: `Resume a session`, `+ New session`. Resume comes first on purpose [R: LR-7, brief §4.3].
- Files: pinned to the bottom, 2 `controlEdge` rule above. Label `FILES`; the project path (mono 11, `text2`); a tree rooted in the project's working directory [G]. Rows 24 high, mono 12. A file Claude changed carries `edited by Claude` right-aligned in the UI face, `text2`. Geoff's exact ask: "a file navigator, rooted in the project's working directory".

**Middle: console, `console` background, flexible width.**

- Tab strip, 36 high: one tab per open session in this project, mono 12, glyph before the name, then `+`. On the dark strip the needs-you glyph is `needsYouOnConsole`.
- Body: the terminal view. The question, the `❯ 1.` options and the `>` line in the target are what Claude Code prints, approximated. Duo draws none of it.
- Plain shell tabs live here too (DL-8). Not drawn.
- No session open: LR-11's placeholder, "No session in ‹project› · Start Claude here". Not drawn.

**Right: 460 wide.**

- Tab strip, 36 high, padding 0 20, gap 18: `Project`, then any open group page (`PRD v2`), then open documents (`prd-v2.md`). Active tab semibold; others `text2`. One document visible at a time (DL-11). Give the strip tab roles [R: LR-63].
- Document: the CodeMirror live-preview editor from the stack rec. The target's type (headings 14 semibold, body 13/20, padding 22 28) is a placeholder for the editor's own styling, which is out of scope here (brief §10).
- Claude's additions: a `selected`-fill block, radius 6, with `added by Claude` beside the heading. This is LR-33's temporary highlight (DL-5): it clears on the user's next edit.

### 3.4 Peek popover

Reference: `screens/flow-zoom-3.html`. [G: peek and reply in place, with a way to go Home or jump in; C: the popover; P: the chords]

- Opens from the needs-you chip. Native popover, arrow pointing at the chip [R: LR-59]. 420 wide, padding 14 16 16, gap 10.
- Label `NEEDS YOU ELSEWHERE · 2`.
- The same cards as the action column, longest wait first. One is selected.
- Every card has a way out: `Jump into project` on project sessions, `Home ⇧⌘H` on Home sessions. [G]
- Footer hints, 12/16 `text2`: `↑↓ Select` · `⌘↩ Jump into the selected project` · `⇧⌘H Home` · `esc Close`.
- The console and the document underneath stay exactly where they were.
- Reply buttons on these cards are subject to §12 Q1.

### 3.5 Designed at low fidelity only

These were agreed as wireframes and never drawn in the final look, so they have no target. The wireframes show structure only: take the look from the targets, and note the superseded details listed in each wireframe's header comment. Build a stub and ask for a design before building them out.

**Project tab** (right pane, first tab). No wireframe is included: the only one drawn was built around tasks, which were then parked. The focused-project card from brief §5: goal, health, next milestone, sessions with resume and new actions, key files in plain language (LR-29), and one reserved `TASKS` slot.

**Group page** (right pane tab, opened by selecting a group). Wireframe: `screens/wireframes/group-page.html`. Title and `Group · 3 sessions`. Sessions oldest first, each with state, age and a one-line summary; forks indented under their parent with `Fork of ‹name›`. Actions: `Resume ‹most recent›`, `+ New session here`. Then `DOCUMENTS` the group's sessions touched, and a reserved `TASKS · TBD` slot that "shows tasks from the project's files when they mention these sessions".

**Making a group.** Wireframe: `screens/wireframes/grouping.html`. By hand: select rows, name the group, press Group; or drag one row onto another. By a session: `duo group "PRD v2" prd-v2-edits quick-q-about-tax-rules`. The syntax is a placeholder; the CLI's name is open (DL-16). Any session can run it, including Home. Both routes produce the same result. [G: "a user should just manually group related threads and/or the app should have a cli verb that lets it do the same"]

---

## 4. Tokens

Full set in `tokens.json`. Use semantic names in code (an asset catalog colour set per token), never raw hex, so a dark appearance can be added without touching views.

### 4.1 Colour

| Token | Value | Used for |
|---|---|---|
| `ground` | `#F3F4F6` | Toolbar, sheet backgrounds |
| `pane` | `#FFFFFF` | Light panes, cards, popover, buttons |
| `selected` | `#E9ECEF` | Selected row, Claude's-additions block |
| `rule` | `#C9CDD3` | Pane dividers, card borders, field border |
| `controlEdge` | `#8B939C` | Button and pill borders, dashed borders, group rule, files rule |
| `text` | `#1F2328` | Primary text, review and working glyphs, selected-card border |
| `text2` | `#5B636D` | Secondary text, idle and resolved glyphs, chevrons |
| `needsYou` | `#C2410C` | The one accent. Needs-you glyph, label, chip, question box |
| `placeholderBar` | `#D5D9DE` | Mock only |
| `placeholderBarOnSelected` | `#C3C8CE` | Mock only |
| `console` | `#15171B` | Chrome around terminals: pane, tab strips |
| `consoleRule` | `#2B2F36` | Rules on the console |
| `consoleText` | `#E6E8EB` | Text on the console |
| `consoleText2` | `#9AA1AB` | Secondary text and inactive tabs on the console |
| `needsYouOnConsole` | `#F97316` | Needs-you glyph on the console |

The accent means "needs you" and nothing else. Health (`At risk`, `Off track`) is plain text, not colour. Project colours, if added later, must exclude the accent [R: LR-27].

The terminal's own palette (16 ANSI colours, cursor, selection) is not designed. Set the terminal background to `console` and foreground to `consoleText`; pick the rest in the SwiftTerm spike.

### 4.2 Type

| Role | Face | Size / line | Weight | Notes |
|---|---|---|---|---|
| UI body | SF Pro (system) | 13 / 20 | regular | Default everywhere in light chrome |
| Emphasis | system | 13 / 20 | semibold | Names, active tabs |
| Pane title, doc heading | system | 14 / 20 | semibold | |
| Button, chip, hints | system | 12 / 16 | regular; chip semibold | |
| Section label | system | 11 / 16 | semibold | Uppercase, tracking +0.06 em (0.66 pt) |
| Pill | system | 11 / 16 | regular | |
| Console chrome, paths, file names | SF Mono (system monospaced) | 12 / 19 | regular; active tab 500 | |
| Path under FILES | system monospaced | 11 | regular | |

Geoff asked for system faces. Use `Font.system(size:weight:design:)` with `.default` and `.monospaced`; do not bundle fonts. Never letter-space the console [R: LR-21].

### 4.3 Shape and size

| Token | Value |
|---|---|
| Radius: control, card, selection, field | 6 |
| Radius: pill | 9 |
| Radius: popover | 10 in the target; the system popover draws its own |
| Border: hairline | 1 |
| Border: emphasis (chip, question box, selected card, thread rule) | 1.5 |
| Border: files divider | 2 |
| Toolbar height | 38 |
| Tab strip height | 36 (Home's session tabs: 32) |
| Row height | 24 file and tile rows · 26 session rows · 28 group rows |
| Button | 12/16 text, padding 4 10, so 26 high with its border |
| Pane widths at 1440 | All projects 340 · flex · 340. Project 300 · flex · 460. |
| Pane padding | 16 |
| Gaps | 2 inside a tile · 6 glyph to label, button to button · 8 row items · 10 card to card · 14 map columns |
| Popover | 420 wide. The shadow in the target stands for the system popover shadow. |

### 4.4 State glyphs

9 pt, drawn in a 10×10 box. Shape carries the meaning; colour is secondary (brief §7, LR-63).

| State | Shape | Colour in light chrome | SF Symbol fallback |
|---|---|---|---|
| Needs you | Filled circle, r 5 | `needsYou` | `circle.fill` |
| Ready for review | Filled diamond | `text` | `diamond.fill` |
| Working | Ring, r 4.2, stroke 1.5 | `text` | `circle` |
| Idle | Horizontal dash, stroke 1.6, round caps | `text2` | `minus` |
| Resolved | Check, stroke 1.6, round caps and joins | `text2` | `checkmark` |

Paths are in `tokens.json`. Prefer drawing them as shapes so they stay crisp at 9 pt.

---

## 5. Components

| Component | Variants | Notes |
|---|---|---|
| `StateGlyph` | 5 states × light, console | §4.4. Always paired with a text label or an accessibility label. |
| `SectionLabel` | default, needs-you | Uppercase, with a `· n` count. |
| `SessionRow` | session, thread, group; selected; in a tile | One component with a `kind`. Group and thread rows have a disclosure and a pill. |
| `CountPill` | group, thread | `group · n`, `thread · n`. |
| `ProjectTile` | default, focused, nothing running | Whole tile is the click target. |
| `NewProjectTile` | — | Dashed. |
| `ActionCard` | needs-you, needs-you selected, Home pointer, review | Question text verbatim. |
| `NeedsYouChip` | rest, open, hidden at zero | Toolbar. |
| `PeekPopover` | — | Native popover holding `ActionCard`s and a hint row. |
| `Breadcrumb` | — | Link › chevron › current. |
| `JumpField` | — | Native search field, `⌘K`. |
| `PaneTabs` | console (dark, mono), right pane (light), Home sessions (dark, mono, 32) | Tab roles. `⌘W` closes a tab, never the window [R: LR-60]. |
| `FileTree` | file, folder, selected, edited by Claude | Rooted in the project folder. Trash, rename, reveal per LR-40. |
| `Button` | default | Match the target: 26 high, 12/16 label, 1 `controlEdge` border, radius 6, `pane` fill. Use a custom button style if the stock bordered style does not look like it. |
| `TerminalHost` | — | From the stack rec. Appears in the Home pane and the console. |

---

## 6. States and interactions

### 6.1 The zoom flow

Reference: `flow-zoom-1.html` to `flow-zoom-4.html`, linked in order. Geoff's verdict on this flow: "looks good to me."

1. **All projects.** Arrow keys move focus between tiles. The focused tile shows `Enter to open`.
2. **Enter or click** opens the project. The left pane lists its sessions and the toolbar chip shows what needs you elsewhere. In the target the console opens on the session that needs you and the right pane on the document it is editing; make that the default [P].
3. **Click the chip.** The peek opens over the project. You deal with another project's session without leaving. The chip is filled while open.
4. **Click "All projects".** The overview has moved on: counts updated, the answered session now shows as working with `now`, the action column is one card shorter. The session you were last in is the selected row in its tile.

### 6.2 Element behaviour

| Element | Action | Result | Source |
|---|---|---|---|
| Project tile | Click, or Enter when focused | Zoom into the project | C |
| Session row in a tile | Click | Zoom into the project with that session open | P |
| Action card | Click | Select it; highlight its row in the map | C |
| Action card › `Open project` | Click | Zoom into that project with that session open | C |
| Home pointer card | Click | Focus the Home terminal on that session's tab | P |
| Review card › `Review` | Click | Zoom in with the deliverable open on the right | C |
| `14 idle, resumable ›` | Click | Not designed | — |
| `+ New project` | Click | Not designed (create-project flow) | — |
| Breadcrumb `All projects` | Click | Zoom out | G |
| Needs-you chip | Click | Toggle the peek | G |
| Peek card › `Jump into project` | Click, or `⌘↩` on the selected card | Close the peek, zoom into that project, open that session | G; chord P |
| Peek card › `Home` | Click, or `⇧⌘H` | Close the peek, go to All projects, focus the Home terminal | G; chord P |
| Peek | `esc`, click outside | Close; focus returns to where it was | P |
| Group row | Click | Select; open the group page tab on the right | C |
| Group or thread chevron | Click | Expand or collapse | C |
| Thread or session row | Click | Open or focus that session's console tab. Re-check liveness first [R: LR-8]. | C |
| `Resume a session` | Click | Prior sessions first: 3 visible plus "show all" [R: LR-7]. List not designed. | R |
| `+ New session` | Click | New session in this project's folder | C |
| File row | Click | Open in a right-pane tab | C |
| Console tab `+` | Click | Same as `+ New session` | P |

Hover states are not drawn. Use the system default for buttons and rows and add nothing custom. [P]

### 6.3 Keyboard

Keys typed into a focused terminal belong to Claude Code, and Return is never remapped [R: LR-16]. Duo's own chords should all carry ⌘ so they cannot collide with the TUI, and they live in one registry [R: LR-60].

| Chord | Action | Status |
|---|---|---|
| `⌘K` | Jump palette | In the brief and LR-25 |
| `↑ ↓ ← →`, `Enter` | Move between tiles and open, when the map has focus | C |
| `↑ ↓` | Select a card in the peek | P |
| `⌘↩` | Jump into the selected card's project | P |
| `⇧⌘H` | All projects, Home terminal focused | P |
| `esc` | Close the peek | P |
| unassigned | Open the peek · zoom out to All projects with the map focused · cycle focus between panes · collapse the right pane | Needed |

LR-60 says to lock the chord map once, in the spec. These are inputs to that map, not the map. LR-60 also lists chords to avoid.

---

## 7. Sizing and resize

Only 1440×900 was drawn. The rest is [P].

| Thing | Rule |
|---|---|
| Splits | All resizable. Left and right panes collapse (brief §7). Only the left toggle is drawn. |
| Minimums | Home pane 280 · action column 300 · project left pane 240 · right pane 360 · console 480. |
| Terminal | Never resize a PTY below 8 columns by 1 row, including during collapse animations [R: LR-14]. |
| 1280×800, project | Console is about 520 wide, roughly 67 columns at 12 pt. Tolerable; collapsing the right pane gives it back. |
| 1280×800, All projects | Map is about 600 wide; three columns of about 180. Goals wrap to two lines. Tolerable. |
| More than three topics | Not drawn. Suggest an adaptive grid with a 220 minimum, wrapping to further rows; the map scrolls vertically. |
| Tall columns | Each of the map and the action column scrolls on its own. The Home terminal scrolls itself. |

---

## 8. Content rules and edge cases

| Case | Rule | Source |
|---|---|---|
| Pending question | Shown verbatim, never summarised, wraps. Suggest a 6-line cap with "more" on unselected cards. | brief §7; cap P |
| Names (session, project, file) | One line, truncate the tail. Wait time never truncates. | P |
| Wait time | `now`, `4m`, `1h`, `3d`. Shown for needs-you, working and idle; not for ready for review. | C |
| Copy | Plain, short, sentence case, no exclamation marks. | brief §7 |
| Reason for needing you | LR-1 requires a reason (permission, question, plan to approve, blocked). Not drawn. Suggest appending it to the card's project line: `onboarding-v3 · permission`. | R; placement P |
| Project with nothing live | `Nothing running`. | C |
| Project not under a topic | Not drawn. Home is one such project and lives in the left pane instead of the map. Suggest a last column with no label. | P |
| No Home project | Not drawn. Home is "supported, not mandated" (brief §5). Suggest the left pane starts collapsed and the map takes the width. | P |
| Nothing needs you | Not drawn. Chip hidden; action column shows only Ready for review, or a single quiet line. | P |
| No projects (first run) | Not drawn. | — |
| Session idle and not in a group | An `IDLE · n` section in the project's left pane, below Working. Drawn in the wireframes, absent from the final screens only because the fixture's idle sessions are grouped. | C |
| Folder moved or missing | Banner and recovery, never a crash [R: LR-23]. Not drawn. | R |
| Folder with Claude history but no `PROJECT.md` | Not drawn (DL-4). | R |
| Loading | Session facts come from a cache, so lists render at once [R: LR-4, LR-64]. Show a row with whatever is known rather than a spinner. | P |

---

## 9. Motion

Nothing was specified beyond the brief: "minimal; state changes should be noticeable but not animated for their own sake." Proposals, all [P]:

| Element | Trigger | Motion |
|---|---|---|
| Altitude change | Zoom in or out | Cross-fade, 150 ms, ease-out. None with Reduce Motion. |
| State glyph | State changes | Swap in place, no animation. |
| Card leaving the action column | Answered or reviewed | Remove with the default list animation. |
| Peek | Open or close | System popover animation. |
| Working glyph | — | Static. No spinner. |

---

## 10. Accessibility

Contrast, computed from the tokens:

| Pair | Ratio | Needs |
|---|---|---|
| `text` on `pane` / `ground` / `selected` | 15.8 / 14.4 / 13.3 | 4.5 |
| `text2` on `pane` / `ground` / `selected` | 6.1 / 5.5 / 5.1 | 4.5 |
| `needsYou` on `pane` / `ground` | 5.2 / 4.7 | 4.5 |
| White on `needsYou` (open chip) | 5.2 | 4.5 |
| `controlEdge` on `pane` (button borders) | 3.1 | 3.0 |
| `consoleText` / `consoleText2` on `console` | 14.6 / 6.9 | 4.5 |
| `needsYouOnConsole` on `console` | 6.4 | 3.0 |

Known gaps: `rule` on `pane` is 1.6, so card and field borders are decoration, not the only boundary; `controlEdge` on `ground` is 2.8. Use native controls in the toolbar and honour Increase Contrast.

- **Never colour alone.** Every state has its own shape, and every needs-you surface also says "needs you" in words [R: LR-63].
- **VoiceOver.** Glyphs are decorative next to a visible label; give the row a combined label: "PRD v2 edits, needs you, waiting 4 minutes". Tiles: "checkout-redesign, on track, 1 needs you, 1 working". The chip: "2 sessions need you in other projects". Announce a session entering needs-you politely, and never for the focused session [R: LR-2].
- **Keyboard.** Every action in §6.2 is reachable without a pointer. Focus order at All projects: toolbar, Home terminal, map, action column. Inside a project: toolbar, sessions, files, console, right pane.
- **Focus.** Opening the peek moves focus into it; closing returns focus to where it was, including a terminal.
- **Tab strips** expose tab roles and selected state [R: LR-63].
- **Dynamic text.** Sizes are fixed points in the targets. Console type is a global setting (LR-21).

---

## 11. Where each thing on screen comes from

Per DL-1: facts derived from Claude's data live only in the rebuildable cache; Duo-only facts live in `<project>/.duo/sessions.json`.

| On screen | Source | Owner |
|---|---|---|
| Topic | Parent folder of the project | Files |
| Project name, goal, health, next milestone | `PROJECT.md` (`title`, `aliases` per DL-18) | Files |
| Session name | Title ladder [R: LR-6]. Read, never written. | Claude-derived |
| Session state, wait reason | `claude agents --json` plus hooks [R: LR-2, LR-3] | Claude-derived |
| Wait time | Time since the state was entered | Derived |
| Pending question text | Hook payload or transcript tail, captured when the session starts waiting [R: LR-4] | Claude-derived |
| Review summary line | Files touched and artifacts from the digest [R: LR-4] | Claude-derived |
| "Ready for review" cleared | A "seen" mark set when the deliverable is opened | Duo-owned |
| Thread (fork lineage) | Duo records the parent when it starts a fork itself. Forks made inside the TUI need detecting; how is unverified. | Mixed; needs a spike |
| Group name and members | `.duo/sessions.json` (DL-1). Shape is a proposal [P]: `groups: [{ name, sessions: [uuid, …] }]`, flat, a session in at most one group. | Duo-owned |
| `edited by Claude`, `added by Claude` | Files touched by a session since the user last edited them [R: LR-33] | Derived |
| Home | A project marked as Home in Duo's registry. How the user marks it is not designed. | Duo-owned |
| Counts in the toolbar | Roll-up of the above | Derived |

Every UI action needs a matching CLI command, and the command list is the spec [R: LR-52, DL-15]. From this design that means at least: list what needs you, open a project, open or resume a session, group and ungroup, open a file in the right pane.

---

## 12. Open decisions and conflicts

### Q1. How does the chrome answer a waiting session? Blocks the reply buttons.

The screens show quick replies in the action column and the peek: `Approve`, `Move into scope`, `Log open question`, `Route 3`, `Reply…`. Geoff chose "peek and reply in place", and the brief says the pending question "can be shown and answered without opening the session".

**LR-15 (must) says: "Never inject keystrokes into a running Claude session."** As far as the repo's research shows, the programmatic answer channels (`canUseTool`, `--permission-prompt-tool`) belong to headless sessions; an interactive TUI session showing a prompt is answered by keys in its terminal. During the design session I told Geoff that quick replies would work by sending input to the session as if he had typed it. That is what LR-15 forbids, and I had not read LR-15 when I said it. The two cannot both stand as written.

| Option | What the user gets | Cost |
|---|---|---|
| **A. The reply surface is the real terminal.** `Reply…` swaps the card for that session's live terminal view, inside the popover or column. The user presses `1` or types, in Claude Code's own UI. | In-place answers, zero injection, full TUI fidelity. | No one-click `Approve`. The terminal view is re-parented and resized, so the TUI redraws twice. The popover needs to be wider than 420 for this. |
| **B. A narrow exception to LR-15.** A reply button may write to the PTY only on an explicit click, only if the session is still waiting on the same prompt when re-checked at click time, and only an option key or the typed reply plus Return. | One-click answers as drawn. | Breaks the letter of a must. Needs the option-to-key mapping to be reliable, and a race check like LR-8's. |
| **C. Answer through hooks.** Duo holds the `PermissionRequest` hook open for unfocused sessions and returns the decision itself. | One-click answers without typing. | Unverified; needs a spike. Likely permission prompts only, and the TUI would show nothing while the hook is held. Conflicts with LR-2's time-bounded hooks. |

**Recommended default: build A now; add B only if Geoff signs it off as a decision-log entry.** A is needed regardless, for free-text replies and for prompts Duo cannot parse, and it fits "maximally compatible with the Claude Code TUI". Until this is decided: build the cards with the question and `Open project` / `Jump into project` / `Home`; put the quick-reply buttons behind one switch that is off.

One lead to check in the state-layer spike: Claude Code's own Agent View replies inline to background sessions (`agent-harness-landscape.md` §1.2). Whether that channel can reach a session Duo hosts in a PTY is unknown.

If the answer is A alone, the quick-reply buttons come off the screens and the cards need a redraw.

### Q2. Project map versus "three attention columns"

`decisions.md` (decided by default, not asked) and LR-1 say three columns: needs you, in progress, done. Geoff then specified the project map with an action column. The three buckets survive in a different arrangement: Needs you and Ready for review in the action column, live sessions inside their project tiles, idle sessions as the footer tier. **Default: build the canvas layout**, since it came from Geoff directly and later. Needs a log entry (§14).

### Q3. Task files versus "tasks are TBD"

DL-6 and DL-13 fix the task file format and make task frontmatter the truth for task ↔ session links. Geoff then parked tasks in the UI. These do not collide: the format decisions stand, and no navigation depends on tasks. **Default: build no task-specific navigation or views beyond the reserved slots.** LR-37's frontmatter panel is editor scope and is not affected.

### Q4. Dark appearance

LR-63 says both themes are first-class, and the brief expected dark to be the default. Geoff chose two-tone, which is a light chrome. No dark chrome was approved. `tokens.json` carries a provisional dark set taken from a direction he passed over ("Night"); its control border is 2.2 against the ground, short of 3:1. **Default: ship light; use semantic colours throughout so dark is a token change; do not ship the provisional dark set without Geoff seeing it.**

### Q5. Chords

`⌘↩` and `⇧⌘H` are proposals; four actions have no chord (§6.3). LR-60 wants one locked chord map. **Default: put all Duo chords in one registry from day one so they are cheap to change.**

### Q6. Left pane, brief versus canvas

Brief §5 says the left pane is "projects and tasks" and a file explorer "does not own the left pane". On the canvas, projects moved to the map and the project's left pane is sessions over files, at Geoff's request. **Default: build the canvas.** Needs a log entry.

### Smaller things

- Label mismatch that I introduced: the action column says `Open project`, the peek says `Jump into project`. Same action. Pick one; I suggest `Open project`.
- The Look sheet says "routing is a sheet". No routing flow was drawn (§13), so treat that as intent only.
- `Ask` as an object is my proposal and is not in the brief's vocabulary.

---

## 13. Not designed yet

Listed so nothing is assumed. Each needs a design pass or a decision before it is built.

- Route an ask from Home to a project (brief prompts C2 and D). Home's suggestions are terminal text, so the controls must live in chrome; this needs rethinking, not just drawing.
- `⌘K` Jump palette (LR-25).
- Create a project (brief C4). Project moved or renamed (brief C5, LR-23).
- Empty states: first run, no Home, nothing needs you, no session open in a project (LR-11).
- The resume-first list (LR-7) and what `14 idle, resumable ›` opens.
- Project tab and group page in the final look (§3.5). Grouping by hand in the final look.
- Folders with Claude history that are not projects (DL-4). Plain shell tabs (DL-8).
- The browser in the right pane, the element inspector, the allow list (DL-3, LR-43 to LR-50).
- Editor internals, file history, conflict banners (LR-30 to LR-38).
- Tasks, anywhere.
- Dark appearance. The terminal's ANSI palette.
- Right-pane collapse control. Settings. Menus. Notifications.
- Component sheet at all states (brief prompt E) beyond what `look.html` shows.

---

## 14. Proposed decision-log entries

Wording for Geoff to confirm or change before anything goes into `decisions.md`. All from the design session on 2026-10-03.

| # | Topic | Proposed entry |
|---|---|---|
| DL-21 | Altitudes | Two: **All projects** and **inside a project**, one window, zoom between them. |
| DL-22 | All projects layout | Home terminal (left) · project map by topic (middle) · action column for needs-you and ready-for-review (right). Replaces the default three-column board as the layout; the three buckets remain. |
| DL-23 | Inside a project | Left pane is sessions by state over a file tree rooted in the project folder. Console in the middle. Right pane tabs: Project, group pages, documents. Amends brief §5. |
| DL-24 | Threads and groups | Forks fold into one thread row. Related threads are grouped by hand or by a CLI verb. Groups are Duo-owned facts. A group shows the state of its most urgent session. |
| DL-25 | Tasks in the UI | Parked. Nothing in navigation depends on a task. File format per DL-6 and DL-13 stands. |
| DL-26 | Look | Two-tone: light chrome, dark console. System faces. One accent, for needs-you. The design screens are the literal build target; only system-drawn chrome is exempt. |
| DL-27 | Console | Claude Code's TUI, unmodified. Duo draws nothing inside the terminal. |
| DL-28 | Peek | A popover from the toolbar needs-you chip, listing what needs you elsewhere, with a way to jump into that project or go Home. |
| DL-29 | Answering from the chrome | Open: §12 Q1. |

---

## 15. Suggested build order

A suggestion for the UI only [P]. It does not replace the stack rec's spikes, and slices 1 to 3 need none of them.

1. **Shell, tokens and the comparison harness.** Window, toolbar, the three-pane split at both altitudes, the colour sets and type styles, `StateGlyph`. A debug mode that loads `fixture.json` and puts the window into each state in §0.2, and a command that captures the window as a PNG. Run `render-references.sh` and commit the PNGs.
2. **All projects, static.** Map, tiles, action column, counts, from the fixture. A placeholder view where the Home terminal goes.
3. **Inside a project, static.** Session list with groups and threads, file tree on a real folder, right-pane tabs with a plain text view.
4. **Navigation.** Zoom in and out, shared selection, chip and peek popover with `Open project` and `Home`, the chord registry.
5. **Terminals.** `TerminalHost` in the console and the Home pane, after the SwiftTerm spike. Hide without killing (LR-13).
6. **Live state.** Replace the fixture with `claude agents --json` and hooks, after that spike. Cache per DL-1.
7. **Groups.** By hand, then the CLI verb, stored in `.duo/sessions.json`.
8. **Replying from the chrome**, once Q1 is decided.

Every slice ends with the loop in §0.2 and a comparison image.
