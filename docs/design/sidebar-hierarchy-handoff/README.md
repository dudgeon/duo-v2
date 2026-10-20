# Duo: the sidebar's hierarchy, the director on top, live work over long-range tasks — design handoff

Status: approved by Geoff (DL-217, DL-218). He picked by buttons on 2026-10-17. On 2026-10-19 he added "open sessions should be above tasks", and chose O2 by button the same day. The canvas is https://claude.ai/artifact/LUJfX4njDoqrtgQwVzFTiP. Not built: the build is a separate job.

This **amends DL-174's pane hierarchy** (`session-glyphs-handoff/04-hierarchy`). DL-174's glyphs, task rows, thread rule, time-group fold rows and wording all stay. What changes is the order of the sections, and which rows go in them.

The screens here are copies of the canvas boards: static HTML, with `png/` at 2x. They are presentation boards, so build only what the table names. The canvas sources are in `canvas/`: the boards draw their panes through `Pane.dc.html` and `Glyph.dc.html`. Names and data are illustrative: a sample checkout project with 16 tasks, about the size of Geoff's busiest project.

## Targets

| Screen | Build | Not chosen (canvas only) |
|---|---|---|
| `00-today-and-decisions` | Context only. Today's pane as built (the director is row 27), the rules every option shares, and the decisions as taken. | — |
| `01-pane-order` | **The target pane.** PINNED (the director's slot, then Keep Running sessions) · NEEDS YOU · OPEN · TASKS (in play, then Later, then + New task) · OTHER SESSIONS (Today, This week, Earlier) · Archived. | A (director slot only), C (a NOW section), D (backlog behind a board row) |
| `02-open-above-tasks` | **OPEN holds open sessions that are in no task (O2).** A task's open tabs stay under their task. | O1 (every open tab in OPEN, naming its task), O3 (the whole task moves up) |
| `03-director-slot` | The director's slot in four states: working, needs you, not open, and a replaced director still open, which shares the slot with **Close**. | Showing the old director as an ordinary row; hiding it |
| `04-edge-cases` | The Later fold opened, with a done task · 240 wide · Home · All projects' tile · keyboard, VoiceOver and duo2. | — |

## The order (`01`)

From the top. A section with no rows isn't shown.

1. **PINNED · n**: a section label (`sectionLabel`).
   - **The director first**, in its slot (below). It is there whether or not it's set to Keep Running.
   - **Then every Keep Running session**, as ordinary session rows with the Keep Running pin after the name (the park handoff's 9 pt pin, in `text2`), most recent first.
   - A pinned session that belongs to a task shows here, not under the task. The task row still counts it, as it does for a session waiting in NEEDS YOU. Turning Keep Running off sends the row back.
   - On hover, the label's + is Keep Running: a menu of the open sessions not yet kept (`duo2 session keep-running <id> on`). **This menu's look is a stand-in (Q-207).**
   - PINNED shows when there is a director or a Keep Running session, and not otherwise.
2. **NEEDS YOU · n**: as built. The director never appears here, even when it waits on you (see the slot).
3. **OPEN · n**: sessions with a tab open in Duo, running or parked, that are **in no task** and aren't pinned or waiting on you. Most recent first. They are rows at the section's top level, with `activeTint`, reading `working` or `at prompt` (DL-133). On hover the label's + is New Claude Code session (it moves here from OTHER SESSIONS).
   - **A task's open tabs stay under their task** (O2). That task ranks first in TASKS because it has a live session.
   - Sessions working outside Duo (background workers) aren't open. They stay under their task, or under Today in OTHER SESSIONS.
4. **TASKS · n**: n counts every listed task, including those in Later.
   - **In play first.** A task is in play while one of its sessions is live (open in Duo, working, or needs you), or ran in the last 3 days, or its note changed in the last 3 days (a director's Progress line counts). Status isn't used.
   - Order is as built: by the most urgent session (needs you, ready for review, working, idle), then by most recent activity. **Task lines with no session sort among the groups by their note's last change**, no longer in a fixed block after them.
   - **Done tasks** (DL-187's look) sink below the in-play tasks. After 3 quiet days they join Later, until they're archived (DL-204).
   - **Later · n**: every task not in play, in a fold row (`rowGroup`: chevron, the name in `bodyEmphasis`, count in `text2`). It sits after the in-play tasks and before + New task, and starts folded. Opened, it lists tasks most recent first, with their age (`5d`, `2w`, `1mo`) where the status sits. A task leaves Later as soon as something happens in it. Duo remembers per project whether Later is open, as it does for the time groups.
   - + New task stays last (DL-172).
5. **OTHER SESSIONS · n**: sessions in no task that aren't open, pinned or waiting on you. **The Open group is gone** (its rows are in OPEN). Today, This week and Earlier stay as built, Earlier folded.
6. **Archived · n**, as built.

The footer (+ New Claude Code session) and FILES are unchanged.

## The director's slot (`01`, `03`)

- **Which session it is:** the one `.duo/director.json` names as `current`, by session id (`duo2 director status`). A name starting "director-" proves nothing (DL-200), so Duo never puts a session in the slot because of its name.
- **The row is two lines:**
  - The first line is the session glyph (DL-174), the name in `bodyEmphasis`, the Keep Running pin when it's set, and the wait (`working`, `at prompt`, `6m`).
  - The second line is in `control` (12/16) `text2`: "Director · 2 workers", where the count is the running workers `duo2 director status` lists. When a worker is waiting on you, it adds "· 1 needs you".
  - Padding is 5 × 8, inside the row's usual 8 margin; the glyph is top-aligned with the first line.
  - It takes `activeTint` when its tab is open and `selected` when selected, like any row. A click opens it, and the session menu is the usual one.
- **States (`03`):**
  1. *Working:* the usual case.
  2. *Needs you:* the hand replaces the glyph, and the second line reads "Director · needs you · 2 workers". It stays in the slot and isn't repeated in NEEDS YOU, whose count is the rows under it. The project's tile, the needs-you chip and the peek count it, as they would any session.
  3. *Not open* (no tab, or parked with Keep Running off): idle glyph, last wait, "Director · not open". A click opens it and resumes it (DL-156).
  4. *A replaced director still open:* after a `--take-over`, or a resume that gave the director a new session id. The old session sits in the slot under the current one, its name in `text2`, its second line "Replaced 2h ago" with a **Close** button (Duo's button). Close is Close Tab (`duo2 session close`): its Claude process ends, the session stays listed, and the row leaves the slot.
- **Home** (`04`): Home's director (DL-197) sits in Home's slot. Its second line also counts the projects it directs in ("Director · 3 projects · 1 worker"). A project's director never shows in Home.
- **No director:** no slot.
- **At 240** (`04`), under 280 wide, the second line drops the word "Director" and keeps the counts. Names truncate their tail; waits never do.

## All projects' tile (`04`)

The tile's session rows put needs-you sessions first (as now), then the director, with its name in `bodyEmphasis`. Keep Running sessions don't move in tiles. Home's List (DL-142) stays ordered by recency (Q-206).

## Keyboard and VoiceOver

- The order on screen is the order everywhere. VoiceOver reads PINNED first, and the list's arrow keys follow the same order when ENH-58 adds them.
- No new shortcut (DL-34). ⌃Tab cycles the console's tabs in their own order (DL-165). The sidebar's order doesn't change the tab strip.
- The slot reads "director-checkout, director, terminal session, working, 2 workers, kept running". Later reads "Later, 11 tasks, folded".

## duo2 (DL-71)

- `duo2 session keep-running <id> on|off` exists. It is PINNED's verb and its +.
- `duo2 view group later expand|collapse` uses the existing group verb.
- `duo2 sessions` marks `director` and `pinned`. `--json` adds `"director": true` and the row's `"section"` (`pinned`, `needs-you`, `open`, `tasks`, `later`, `other`).
- `duo2 tasks` adds whether each task is in Later, and its last activity.
- Close on a replaced director is `duo2 session close` (exists).

## Migration

Nothing on disk changes, and nothing new is stored. The order is worked out from sessions, notes and `.duo/director.json`, and fold state is view state. On the first launch of this build, tasks quiet for 3 days go into Later (folded), and the director moves up.

## For the build

- **The intro video films this pane.** Its anchors stay (`video.session.<name>`, `video.task.<slug>`, …). Tell the video session when this merges.
- **Fixture states for `scripts/check-ui.sh`:**
  - a project with a registered director (`.duo/director.json` naming a fixture session) and one Keep Running session;
  - a needs-you director;
  - a replaced director still open;
  - 16 tasks, 11 of them quiet for over 3 days;
  - a done task;
  - Home with a director.
  
  Compare at 300 and 240.
- **DuoChecks:**
  - the in-play rule (live, session in 3 days, note in 3 days, done after 3 quiet days);
  - which section each row lands in (a pinned session in a task, an open session in a task, a needs-you director);
  - the slot keyed by session id, not by name.
- **Update** `docs/design/system/surfaces.md` and the SessionRow, SectionLabel and SessionList READMEs when it ships.
- **The interval:** the 3 days is one constant (Q-203). The list holds its order while the pointer is in it (DL-130) (C-94).

## Open

Q-203 to Q-208 in `docs/plan/concerns-and-questions.md`.
- Q-203: the 3-day threshold.
- Q-204: a director started in Duo set to Keep Running by default.
- Q-205: a director that runs outside Duo.
- Q-206: Home's List and Q-183.
- Q-207: the look of PINNED's + menu.
- Q-208: whether workers get a mark.
