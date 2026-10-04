# Duo surfaces — design handoff

Status: slice 1 of several · 2026-10-04 · Owner: Geoff · Answers `docs/design/design-brief-2026-10-04.md`. Written by the design session (Claude).

Same shape as `build-handoff/` and `search-handoff/`, and the same rule: the files in `screens/` are the target. This document explains them and covers what a picture cannot show. It grows one slice at a time; Geoff reviews each slice on the canvas (page "Surfaces") before the next.

| Slice | Surfaces | Status |
|---|---|---|
| 1 | DB-1 idle list · DB-2 terminal colours · DB-3 console with nothing running · DB-4 shell tabs | **here, awaiting review** |
| 2 | DB-5 first run · DB-6 Home · DB-7 needs you · DB-8 folder moved · DB-9 create a project | next |
| 3 | DB-10 Settings · DB-11 legacy notice · DB-12 folders, moving, merging | |
| 4 | DB-13 HTML tab and picker · DB-14 editor notices · DB-15 the document | |
| 5 | DB-25 narrow windows and motion · DB-26 menu bar · DB-27 notifications | |
| then | v1.1: DB-17 to DB-24 | |

| File | What it is |
|---|---|
| `screens/*.html` | Targets and sheets, exported unchanged from the canvas. Each carries `design-size`, `design-kind` and `design-surface` metas. |
| `screens/manifest.json` | Every screen, its DB-n, its size and what it shows. |
| `tokens-additions.json` | New tokens only: the terminal palette, a few sizes, two icons. |
| `fixture-surfaces.json` | Sample data these screens add to the fixture's world. |
| `tools/render-references.sh` | Renders the PNGs with build-handoff's renderer. Run on the Mac. |

PNGs are not included: they need the Mac's system faces. I rendered every screen in a Linux browser with fallback fonts to check layout; nothing overflowed or collided there.

## How to read this

- **[G]** Geoff decided it (a DL-n, or on the canvas).
- **[B]** The brief requires it.
- **[P]** My proposal. Change freely.

**Backdrops.** Where a screen shows the window behind a new surface, it is drawn as the decisions now stand, not as `build-handoff` exported it: no reply buttons on cards and `Open project` only (DL-29, DL-58), no `Resume a session` button (DL-59), a `+` on the right pane's tab strip (DL-61), and the toolbar field reading `Search all projects ⇧⌘A` (DL-80). Build-handoff's own targets were not re-exported.

---

## DB-1 · What `14 idle, resumable ›` opens

Screens: `idle-list`, `idle-many`.

**Answer to the brief's questions [P].** A popover from the footer, like the peek. Sorted by recency, grouped by when. No search field of its own: typing selects by title, and anything further is what search is for.

| Part | Spec |
|---|---|
| Footer | A button. Click or Return toggles the list. While open, its text is `text`, semibold, and the chevron points up. At zero it reads `Nothing idle`, in `text2`, with no chevron, and is not a button (drawn in slice 2 with DB-7's quiet state). |
| Popover | 460 wide, above the footer's left end, arrow pointing down at it. `pane` fill, 1 `rule` border, radius 10, the popover shadow. Tall as its content up to the map's height less 32; then the list scrolls and the heading and key row stay put. |
| Heading | `IDLE, RESUMABLE · n`, the section-label style. |
| Buckets | `THIS WEEK · n`, `LAST WEEK · n`, then one per month (`SEPTEMBER · 61`). Newest first, by last activity. |
| Row | 26 high, radius 6. Idle glyph, title, then right-aligned: project in `text2` (150 at most), age (30 wide). Titles and projects truncate at the tail. |
| In a group | The group's name in a pill after the title (1 `rule` border, as the thread pill). |
| Unfiled | An `Unfiled` pill where the project goes [B: DL-63]. |
| Archived | An `archived` pill after the title [B: DL-49]. It resumes like any other; Duo puts the transcript back (DL-47). |
| Open elsewhere | Title in `text2`, and `open in Terminal` where the age goes. Not resumable [B: LR-8]. |
| Selected | `selected` fill. The first row is selected when the list opens. |

**Keys.** `↑` `↓` move. Return resumes: the project opens with that session in the console, as clicking it in the project's list does [B]. `⌘↩` opens its project without resuming, the meaning it already has in the peek (DL-34). Esc closes and returns focus to the footer. Typing letters moves to the next title that starts with them. The footer is the last stop in the map's focus order. No chord is proposed for opening the list; DB-26 can give it a Go menu item.

**Right-click on a row** shows the menu that already exists: `Move to Project`, `Send to Claude`, `Send To ▸` [B].

**Open elsewhere.** Return on such a row opens its project, where the console explains (DB-3). It is listed so the session can be found, even though it can't be resumed.

**Not listed:** a session that is running but quiet (DL-55).

**VoiceOver.** The footer: "14 idle sessions, button". A row: "Interview synth, in PRD v2, checkout-redesign, idle 2 days".

---

## DB-2 · The terminal's colours

Screen: `terminal-palette` (a sheet). Values: `tokens-additions.json` › `terminal`.

**Answers [P].** Diff red and green are mid-saturation: clear, not neon. The selection is a fixed neutral, not the editor's, because the editor's is the system highlight, which a user can set to orange.

| | Normal | Contrast | Bright | Contrast |
|---|---|---|---|---|
| Black | `#2B2F36` | 1.3 | `#7D8590` | 4.8 |
| Red | `#E27A85` | 6.3 | `#F09AA3` | 8.4 |
| Green | `#8CC08A` | 8.6 | `#A9D7A6` | 11.1 |
| Yellow | `#D6C26B` | 10.1 | `#E8D98E` | 12.6 |
| Blue | `#7FA8E6` | 7.4 | `#A4C3F3` | 10.0 |
| Magenta | `#C792D8` | 7.3 | `#DAB1E7` | 9.8 |
| Cyan | `#74C2C9` | 8.8 | `#9BDBE0` | 11.6 |
| White | `#C9CDD3` | 11.2 | `#FFFFFF` | 17.9 |

Contrast is against `console` (`#15171B`). Everything a program would use for text is 4.5 or better. Black is the one exception, as in every dark palette; bright black, which programs use for comments and hints, is 4.8.

- **No orange [B].** Red sits at hue 354 and yellow at hue 49, either side of the needs-you accent at hue 25, and both are far less saturated. Nothing in the palette can read as "needs you".
- **Cursor:** a steady block in `consoleText`; the character under it is drawn in `console`. No blink.
- **Selection:** `#3A4250` behind the text; the text keeps its colours. `consoleText` on it is 8.2.
- **Bold** is the bold face in the same colour, not the bright colour.
- **Increase Contrast:** the second set in the tokens. Normal colours take the bright values and the brights lighten again; black becomes `#4A4F57`.
- **What this does not control.** Claude Code's default theme draws its own colours, including its orange mark and its diff backgrounds, and Duo draws nothing inside the terminal (DL-27). The palette governs shells and anything that uses the 16 indexed colours.

---

## DB-3 · A console with nothing running

Screens: `console-none`, `console-ended`, `home-none`, and the sheet `console-empty-states`.

**Answer to "one layout or several?" [P].** One layout for every case with no terminal to show. A different treatment for a session that has ended, because its output is still worth reading.

**The message.** In Duo's own type (not the terminal's), at the top left of the dark pane, 24 in from its edges, under the tab strip. Title 13 semibold `consoleText`; one or two lines of 13/20 `consoleText2`, 440 wide at most; buttons 8 below. In the Home pane the padding is 20 16. The tab strip stays, with `+`.

**Buttons on the console.** The standard button's size and radius, 1 `consoleText2` border, no fill, `consoleText` label. No new token. The first button is the default: Return presses it when the pane has focus.

| State | Title | Body | Buttons |
|---|---|---|---|
| No session open, history exists | No session open in ‹project› | Pick up where you left off, or start fresh in this folder. | `Resume ‹last session›` · `Start Claude here` |
| Nothing has run here | No session in ‹project› | Nothing has run in this project yet. | `Start Claude here` |
| Claude Code not found | Duo can't find Claude Code | It looked in the usual install folders and on your login shell's PATH. Install Claude Code, or point Duo at it in Settings. | `Open Settings…` · `Look Again` |
| Open somewhere else | ‹session› is open in ‹app› | It has been running there since ‹time›, so Duo won't start a second copy of it. Finish there and look again, or carry on here as a fork: a new session with the same history. | `Look Again` · `Resume as a Fork` |
| Folder missing | This session's folder is missing | ‹path›. Starting it will use the nearest folder that still exists, ‹folder›. | `Start in ‹folder›` · `Locate Folder…` |
| Home, no session | No Home session | Home is where asks get sorted and sent to projects. | `Start Claude in Home` |

- Resume comes before Start, on purpose (brief §4.3, LR-7's intent). `Start Claude here` is LR-11's wording [B].
- **Open somewhere else: explain, and offer a fork. Never end the other process [P].** Ending it could lose a turn in flight in another app. `Look Again` re-checks liveness (LR-8). This is the brief's question; see Questions.
- **Not found** replaces the text the terminal prints today. `Open Settings…` goes to DB-10 (slice 3).
- **Folder missing** follows LR-18. `Locate Folder…` is DB-8's action (slice 2); the wording may move with it.
- **Home, no session** appears only after the last Home tab is closed, since Duo starts one at launch (DL-54). In `home-none` the counts change because Home's two sessions are closed: 2 need you, 3 working, 16 idle, and the Home pointer card is gone.

**Ended.** The terminal stays as the process left it, scrollable. A bar sits under it: 40 high, 1 `consoleRule` above, Duo's type. Left: `‹session› ended at 10:42.`, or `Claude quit unexpectedly at 10:42 (exit 1).` Right: `Resume` (the default) and `Close Tab`. Resume continues in the same tab. The tab's glyph becomes the idle dash, and the session moves to Idle in the list on the left.

---

## DB-4 · Plain shell tabs

Screens: `shell-tab`, `shell-new-menu`, `shell-narrow` (1280×800), and the sheet `console-tabs`.

**Answers [P].** A chevron beside `+` asks for a shell, and two chords. A shell tab does carry a glyph: a prompt mark, so tabs stay aligned and a shell is never mistaken for a session. A promoted tab announces nothing visually beyond its glyph changing.

| Part | Spec |
|---|---|
| Shell tab | The prompt mark (11×9, `tokens-additions.json`), then the title, mono 12 like every console tab. Selected: `consoleText`, weight 500. Otherwise `consoleText2`. |
| Its title | The command it is running (`./export-funnel.sh`). When it is waiting, the shell's name (`zsh`). |
| `+` | Starts a Claude session, as it does today. Unchanged. |
| The chevron | Beside `+`. Opens a menu: `New Claude Session ⌘T`, `New Shell ⇧⌘T`. A native menu; the screen shows its items, order and chords. |
| Promotion [G: DL-8] | Typing `claude` turns the tab into a session tab in place: the prompt mark becomes a state glyph, the title becomes `New session` until the session has one, and the session joins the list on the left. No banner. VoiceOver says "Now a Claude session". |
| A shell that exits | Cleanly: its tab closes. With an error: the tab stays, with DB-3's bar: `The shell exited with an error (exit 1).` · `New Shell` · `Close Tab`. |
| Too many tabs | Titles shorten to 24 characters, then the tabs furthest right move into a `» n` menu that sits before `+`. The selected tab is never hidden. The menu lists the hidden tabs with their glyphs. |

- **Chords.** `⌘T` and `⇧⌘T` are free in `Commands.swift`. They need a log entry (DL-34).
- **Shells are not sessions.** They are not in the list on the left, not in the toolbar's counts, and never need you.
- `⌘W` closes the tab (DL-34). Closing a shell that is still running a command should ask first, in a sheet (F-54). Not drawn.
- Shells are not restored on relaunch [P].
- Tab roles for VoiceOver [B: LR-63]: "zsh, shell, tab, 3 of 4".

---

## Questions for Geoff

| DB | Question | My default |
|---|---|---|
| DB-1 | Should a session that is open in Terminal appear in the idle list at all? | Yes, marked, so it can be found. |
| DB-2 | Is the muted palette right, or do you want diffs louder? | Muted. |
| DB-3 | When a session is open somewhere else, should Duo offer to end it there? | No: explain, and offer a fork. |
| DB-4 | `⌘T` for a new Claude session and `⇧⌘T` for a new shell? | Yes. |
| DB-4 | Should a shell that exits cleanly close its own tab? | Yes. |

## Not designed in this slice

- The idle footer at zero (comes with DB-7's quiet state in slice 2).
- The sheet that asks before closing a shell with a running command.
- The `» n` overflow menu opened.
- Hover and pressed states for buttons on the console (DB-32).
