# Duo: fork threads, the two tabs, the moment after a fork — design handoff

Status: Geoff picked by buttons on 2026-10-20 (DL-228): the thread row A, auto-open A, the fork's tab **B (a fork mark)**, a split thread A. The canvas is https://claude.ai/artifact/84jHaESxQeitexXgaqGZAh ("Duo · Fork threads"). Built on `build/fork-tabs` (F-359, F-360; stand-ins Q-233).

This draws what **DL-227** (option A, `docs/research/fork-handling.md`, F-344) left undrawn: a `/branch` or `/fork` made in a Duo session leaves both sessions live, each in its own tab, and the left pane shows them as one thread. It fits **DL-217's pane order** (`sidebar-hierarchy-handoff/`), **DL-174's glyphs**, and **DL-225's scrolling strip** (`tabs-handoff/`). It changes none of them.

The screens are copies of the canvas boards: static HTML, with `png/` at 2x. They are presentation boards, so build only what the table names. The canvas sources are in `canvas/`; the boards draw their panes through `Pane.dc.html`, `Glyph.dc.html` and `Strip.dc.html`. Names and data are illustrative.

## Targets

| Screen | Build | Not chosen (canvas only) |
|---|---|---|
| `00-today-and-questions` | Context only: today's pane after a `/branch`, option A's rules, the four questions and the answers. | — |
| `01-thread-row` | **The thread row (A):** the original leads with the chevron, its forks under the thread rule; folded, the original's name with the thread's most urgent state. The foot: auto-open (A). | B (a heading row), C (forks on two lines) |
| `02-after-branch` | **The moment after `/branch`.** | — |
| `03-after-fork` | **The moment after `/fork`.** | — |
| `04-tabs` | **The fork mark (B)** on a fork's console tab, and where the new tab goes among many. | A (names alone, "‹title› (Fork)"), C (the name unchanged, no mark) |
| `05-edge-cases` | A thread in a task · **a split thread (A)** · 240 wide · keyboard, VoiceOver, duo2. | Split thread B (each session in its own section) |

## The thread row (`01`)

A **thread** is a session and its forks (DL-24; `ForkLineage`, `forkedFrom`, the job's `forkParentSessionId`). It is still one item in the list, and DL-217 places it.

- **Expanded:**
  - **The original is the first row**: a session row as built (26, glyph, name, wait, `activeTint` when its tab is open), with a chevron (down) before the glyph. A click on the row opens the original, and the chevron folds the thread.
  - **Its forks hang under the thread rule**, exactly as a task's sessions do (`borderEmphasis` 1.5 `controlEdge` at x 21; rows inset 3 from the rule). They are ordered oldest first, each a plain session row with its own glyph, name and wait. A row adds no words or mark: the session's name is its own (Claude's "‹title› (Branch)" for a `/branch`; for a `/fork`, whatever the session is called, the parent's title until Claude renames it).
  - **A fork of a fork** lines up under the same rule, by age. The thread is one list, not a tree.
- **Folded:** the original's name, so the row keeps its name when you open it. The glyph and wait are the thread's most urgent member's (DL-24), and `thread · n` follows as built (`CountPill`). **This changes the folded row as built**, which today takes the most urgent member's name.
- **Selection and tint:** each row takes `activeTint` while its tab is open and `selected` when selected, like any session row.

## When a thread opens by itself (`01`, the foot)

- **A fork made in Duo opens its thread**, with the fold's motion (`motionFold` 180 ms), so both sessions are seen the moment it happens.
- After that it stays as the user leaves it. Duo remembers it per project, as it does the time groups and Later (view state, nothing on disk).
- Threads Duo only finds (forks from before, or made outside Duo) start folded.

## In the sections (`05`)

- **A thread stays one row**, placed by its liveliest member, in DL-217's order. If any member has a tab, the thread is in OPEN (or under its task, O2). If none has, it goes where its most recent member would.
- **A member that needs you leaves the thread** for NEEDS YOU, as a task's sessions do. Its row there has a second line in `control` `text2`: "Fork of ‹original›" (the group page's words; for the original itself, nothing). It goes back into the thread when it's answered.
- **In a task:** the fork joins every task the original is in (DL-116), so the thread sits under its task. Its rule sits inside the task's, under the original's chevron: an inner rule at x 37 (21 + 1.5 + 14.5), rows inset 3 from it, the task's rule continuing beside it.
- **At 240 wide**, names cut at the end; the chevron, the rules and the waits stay whole.

## The console strip (`02`, `03`, `04`)

- **A fork's tab goes right after the tab it came from**, wherever that is in the strip, never at the end. It fades in (`motionTabIn`) as the strip slides (`motionTabMove`).
- **The fork mark (B, chosen):**
  - On every fork's tab, for as long as the tab is open. The original's tab has none.
  - It sits after the state glyph, 6 before the title: 10 × 10, single stroke 1.3, round caps and joins, in the tab's text colour (`consoleText2`; `consoleText` when selected). The mark is three small circles (r 1.2) joined as a branch. Its path is in `canvas/Strip.dc.html`. It is a new drawn icon: add it to the design system's `assets/Icons/` when it's built.
  - The title is the session's own: "‹title› (Branch)" after a `/branch`, and the parent's title after a `/fork`, until Claude renames it. The mark stays through a rename.
  - Its accessibility label: "‹name›, fork of ‹original›, ‹state›".
  - In the all-tabs menu (`n ⌄`, DL-225) the row shows the mark too, in light colours after the state glyph. *This isn't drawn on the boards: it's a stand-in, under Q-229.*
- **The light strip over chat** (DL-136) follows the same rules, the mark in `text2` (`text` when selected). *Not drawn: a stand-in, under Q-229.*

## Just after `/branch` (`02`)

1. Duo sees `SessionStart` with `source: "fork"` and the same pid. It **splits instead of re-keying**: the terminal's tab becomes the branch's tab, placed right of where the original's was, titled from Claude's title, with the fork mark. It stays **selected and focused**, since that's where you're typing.
2. **The original reopens in its old place** by `claude --resume ‹old›`, at its prompt (idle glyph). It costs no tokens until used.
3. **The thread opens** (above): the original first, the branch under the rule and selected.
4. **Task links:** the branch joins every task the original is in.
5. **No notice bar or toast.** VoiceOver announces "‹branch› opened, a fork of ‹original›".

## Just after `/fork` (`03`)

1. **The original stays selected**, focus in its terminal.
2. **The fork's tab appears right of it**, unselected, running `claude attach ‹short›`. It carries the fork mark. It reads idle while the fork waits for its first prompt; a `/fork ‹prompt›` starts it, so it reads working.
3. **The thread opens**: the original first (selected), the fork under the rule. **The fork's row is there at once**, even on Claude Code 2.1.219, where the fork has no transcript until its first prompt: Duo reads it from `‹config›/jobs/‹short›/state.json`.
4. **Closing the fork's tab detaches** (⌘W, Close Tab, `duo2 session close`). The fork keeps running in Claude's background. Its row stays in the thread, untinted, as a session running outside Duo (DL-174). Opening the row attaches again (`duo2 session open`) instead of DL-109's "open somewhere else".
5. The tab's menu is a session tab's menu as built; nothing is added.

## Keyboard, VoiceOver, duo2

- No new shortcut (DL-34). ⌃Tab steps the strip in its order, so a fork's tab comes right after its original (DL-165).
- VoiceOver reads the original "Pricing research, terminal session, at prompt, thread of 2, expanded", and a fork "Pricing research (Branch), fork of Pricing research, terminal session, working".
- duo2 (DL-71):
  - `duo2 sessions` marks a fork with `forkOf` and `fork: branch|fork` (`--json` too).
  - Folding a thread uses the group fold verb, keyed by the original's session id. The builder confirms the verb's name and adds it to `Actions.swift` if it's missing.
  - Detach and attach are `session close` and `session open`.
- All projects' tiles and the session list keep one row per session, as now.

## Not drawn here

- Q-219 (c), a "Trust this folder" notice for `/fork`'s "Workspace not trusted": drawn in `trust-notice-handoff/` (DL-229).
- `/clear` and `/resume` keep today's behaviour (re-key, `continued-from`).

## For the build

- **Fixture states for `scripts/check-ui.sh`:**
  - a thread after `/branch`, both open, in OPEN;
  - a thread after `/fork`, the attach tab open;
  - the same folded;
  - a thread in a task;
  - a fork that needs you;
  - many tabs with the fork mid-strip.

  Compare at 300 and 240.
- **DuoChecks:**
  - `/branch` splits and `/clear` re-keys, by `source` and pid;
  - task links are copied to a fork;
  - the thread's placement (liveliest member; needs-you leaves it);
  - a fork's tab goes right of its original;
  - the parent comes from `forkedFrom` or `state.json` before `ForkLineage`.
- **Update** `docs/design/system/surfaces.md`, and the SessionRow and console tab READMEs, when it ships. The design-system artifact is the director's to publish.

## Open

Q-229: the stand-ins above (the mark in the all-tabs menu and on the chat strip), and whether a fork's row in the left pane should also carry the mark. The boards draw none there; Geoff chose the mark for tabs, and thread A for the pane, which adds no words.
