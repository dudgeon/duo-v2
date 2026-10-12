# Duo: session row glyphs, and the project pane's hierarchy — design handoff

Status: approved by Geoff, 2026-10-12 (DL-174), by buttons after one round on the canvas https://claude.ai/artifact/Eepq4MsbBwM24crUKaCPVE. Not built. ENH-72.

The canvas holds every option. The screens here are copies of the chosen boards (HTML, and `png/` at 2x). They are presentation boards: the panes drawn inside them are the targets. Where a board draws options or notes, build only what the table names. The new marks are in `glyphs/` as SVGs (10 × 10 viewBox, light colours; take the colours from the tokens named below, never the hex).

## Targets

| Screen | Build | Not chosen (canvas only) |
|---|---|---|
| `01-glyph-set` | **The session glyph (A): kind, with attention replacing it.** Eight marks, each 9 pt in a 10 × 10 box. Pane, selected, open tint, hovered (no change) and the provisional dark set are drawn. | B: kind plus a corner badge; C: kind leading, attention by the wait time |
| `02-in-place` | The project's left pane before and after, at 300 and 240. **Only the glyph changes on this board.** The hierarchy is `04`. | — |
| `03-reach` | **Every session row takes the glyph:** the project's left pane, All projects' tiles (`TileSessionRow`) and the session list (`SessionListRow`). **Console tabs keep `StateGlyph`**, because `>_` already marks a plain shell tab there. | Left pane only; console tabs too |
| `04-hierarchy` | **The pane's new hierarchy:** NEEDS YOU, then TASKS, then OTHER SESSIONS, which holds the time groups Open, Today, This week and Earlier. Then the Archived fold. Wording W3 + S1. | W1, W2, W4, W5; S2, S3; needs-you sessions in place; Other sessions first |
| `05-needs-you-mark` | **The drawn raised hand** in `needsYou`. The board shows it beside the options that were not chosen. | ✋ and 🙋 emoji; the accent “!”; today's dot |

## The glyph (`01`)

| State | Terminal session | Chat session |
|---|---|---|
| Idle | `>_`: a caret and an underscore, stroke 1.5, round caps and joins, in `text2` (`terminalIdle.svg`) | A bubble, r 1.5, tail at the bottom left, stroke 1.2, in `text2` (`chatIdle.svg`) |
| Working | The caret with a block cursor (3.2 × 3.6, r 0.5) in place of the underscore, in `text` (`terminalWorking.svg`) | The bubble in `text` with three dots (r 0.75) (`chatWorking.svg`) |
| Ready for review ("done") | A solid rounded square (r 2.2) in `text`, with `>_` knocked out in the row's own fill (`terminalDone.svg`) | The bubble filled solid in `text` (`chatDone.svg`) |
| Needs you | The raised hand in `needsYou` (`needsYouOnConsole` on the console) (`needsYouHand.svg`). It replaces the kind. | the same |
| Resolved | Today's tick in `text2`. It replaces the kind. | the same |

- **Nothing animates.** The cursor and the dots are still (README, Motion).
- **Shape carries every state.** Working and idle differ in shape, not only `text` against `text2`.
- On a selected or tinted row, the knocked-out `>_` takes that row's fill (`selected`, `activeTint`). Draw it as a cut-out, not in white.
- **Dark (provisional, DB-29):** the same tokens resolve to their dark values.
- **Accessibility label:** “‹name›, chat session, ready for review” or “‹name›, terminal session, needs you, waiting 4m”. The kind words are “terminal session” and “chat session”.
- **Wait words are unchanged** (DL-91, DL-133): no wait for ready for review; “at prompt” or “working” for sessions open in Duo.

### Where kind and state come from

- **Kind** is the mode a click would open the session in: `ChatPrefs.mode(for:home:)` (`Chat/ChatSession.swift`; `chat.json` in the support folder). That is the session's own mode once chosen; otherwise the mode used last, and chat for Home sessions (DL-119 (5), DL-142 (6)). A session running outside Duo (another terminal, the desktop app) is a terminal session. For a session open in a tab, use the tab's live `ChatSession.mode`, so the row changes when the Terminal/Chat pill is pressed.
- **State** is unchanged (`Attention.live`, `Live/HookEvents.swift`). Ready for review comes from the Stop hook on sessions Duo started or resumed. A turn whose last message ends in “?” is needs you; any other stop is ready for review until seen. That works on every CLI Duo supports, 2.1.219 included. Sessions running outside Duo have no Duo hooks, so they show working and needs you (from Claude's own status file) but never ready for review. That is a known limit (Q-184), not a bug.

### Task rows

- A task row keeps its chevron, task box, name in `bodyEmphasis` and status.
- **Its glyph slot shows the hand while one of its sessions needs you, and is empty otherwise.** A task has no kind; its sessions show their own state. This replaces the most-urgent `StateGlyph` on task rows.
- Group rows (non-task, `group · n`) follow the same rule.

### Not changed

- Console tabs (`ConsoleTabStrip`), the action column's cards, the peek and the Dock menu keep `StateGlyph` and their words.
- `StateGlyph` stays as it is for those surfaces. The new view is a separate one; call it `SessionGlyph(kind:state:)`.

## The hierarchy (`04`)

This replaces DL-91's sections in a project's pane, and DL-93's task rows mixed into those sections.

1. **NEEDS YOU · n**: session rows waiting on the user, from tasks or not, at the top as today. A waiting session leaves its task or time group until answered. Its task row shows the hand meanwhile.
2. **TASKS · n**: a section label, `sectionLabel`.
   - The task rows sit under it, ordered by their most urgent session, then by recency, as now.
   - A task's sessions hang under the thread rule (`threadRuleX`) when the task is unfolded.
   - **+ New task** is the last row (DL-172), and the Explainer triggers stay as built.
   - On hover the label shows a + at its trailing end: New task.
   - **A task's sessions appear only under their task**, never also in a time group.
   - With no tasks, it holds DL-147's explainer and the New task row (DL-172).
   - DL-172's Tasks *fold* becomes this section, and it isn't foldable.
3. **OTHER SESSIONS · n**: the sessions in no task. On hover the label shows a +: New Claude Code session.
   - Under it are time groups at the task rows' level. Each is a fold row: chevron, name in `bodyEmphasis`, count in `text2`, `rowGroup` 28.
   - The groups are **Open** (a tab open in Duo), **Today**, **This week** and **Earlier**. Open, Today and This week start unfolded; Earlier starts folded, as today. An empty group isn't shown.
   - Their session rows are indented to the nested rows' inset (as under a task, without the rule).
   - Group rows (`group · n`) sit in the time group of their most urgent session, as now.
4. **Archived · n**: the fold, last, as built (DL-115).

The footer (**+ New Claude Code session**) and FILES are unchanged.

## duo2 (DL-71)

- The headers' + buttons are `duo2 task new` and `duo2 session new` (existing).
- Folding a time group uses the existing view-group action (the build session checks `Actions.swift`).
- The glyph needs no verb, but `duo2 sessions` should print the kind (`terminal` / `chat`) beside the state, so a session can read it.

## For the build

- **The intro video films this pane** (S4, S7, S10 and the sidebar shots), so its captures will change. Its anchors stay: `video.session.<name>`, `video.task.<slug>`, `video.task.<slug>.group`, `video.task.<slug>.disclosure`, `video.newtask.button`. Tell the video session when this merges.
- Fixture states for `scripts/check-ui.sh`: a project with every glyph (both kinds × idle, working, ready for review; needs you; resolved), a task with a waiting session, and an empty Tasks section. Compare at 300 and 240.
- DuoChecks: kind mapping (chat.json mode, default, Home, outside Duo), and the task row's hand-or-empty rule.
- Update `docs/design/system/components/StateGlyph/README.md` and `SessionRow/README.md` to “built” when it ships.

## Open

- **Q-183:** All projects' session list keeps its recency grouping across projects (DL-142) for now. Should it adopt this split? Not drawn.
- **Q-184:** “done” is a guess for a question written without a “?”, and absent for sessions running outside Duo. Is that acceptable, or should Duo look harder?
