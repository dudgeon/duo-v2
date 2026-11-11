# Home's agent panel: gate it, make it opt-in, or move it (2026-11-10)

Research and design only; nothing here is built. Task: `tasks/home-agent-panel-options.md`. Records: F-648 (this study's findings), Q-498 to Q-501 (the open decisions), Q-488 answered here (recommendation), ENH-341 spare. Sketches: the Design canvas linked in "Sketches" below, every mark [P]. Decisions go to Geoff as a decision walkthrough (`docs/research/home-agent-panel-walkthrough/`).

## The ask

Geoff, 2026-11-10, in the ask-fallback-black-terminal worker: "please note these as issues that add to the case for a rethink about the home chat handling; director should spin up a worker to think about options for the home agent panel; maybe gate it in system prefs or require a more proactive user intervention to create a left pane home agent".

He had said it once before, on 2026-11-03 (DL-314, Q-447): "I think the home agent pane needs to be revisited; I'm, not sure most users will use it and we are doing a lot of strange workarounds, like this decision, to accommodate it" (ENH-322). DL-315, the same day, closed the column by default "until we figure out what to do with it". This study is that figuring out.

## How Home's agent came to be

| When | Record | What it did |
|---|---|---|
| 2026-10-03 | DL-22 | All projects is three panes: **the Home terminal on the left**, the map in the middle, the action column on the right. The build handoff: "At 340 wide the terminal is roughly 42 columns at 12 pt. That is intentional ('thin')" (`build-handoff/README.md`, screen `overview.html`). The pane was there for "the director agent" of the original brief. |
| 2026-10-03 | DL-54 (C-15) | **Live mode starts a Home session whenever Home has none.** "Start on first use" was the alternative not taken. |
| 2026-10-04 | DL-82 to DL-85 | Home is optional; with no Home folder the column asks for one (S2-3). |
| 2026-10-06 | DL-129 | Side panes hold their width: All projects 340 \| 600 \| 340; Home's column's minimum 280. |
| 2026-10-07 | DL-132 g, DL-142 | Chat in Home's column; **Home opens in chat**; the middle gets Board \| List. D, a Sessions view with the selected session's chat in the middle, was deferred (ENH-28). |
| 2026-10-14 | DL-197 | A director can run in Home, seeing every project. |
| 2026-10-30 | DL-262 | The List's first row, `New session in [★ home ⌄]  ⌘T`, starts a session in Home (or any folder). |
| 2026-11-02/03 | DL-311, DL-314 | Several windows: Home live in one, "Home is showing in the Blue window" with Show Here and Go There in the others. Geoff's ENH-322 remark. |
| 2026-11-03 | DL-315 | All projects' left sidebar (Home's chat) starts closed until the person toggles it. |

## What the column costs: every known problem

Each comes from one of two facts: **Home's session is drawn in a narrow pane** (340 pt, 38 to 43 terminal columns), or **Home's session has two places in one window** (the column at All projects and the console on Home's own page, both kept in the window; plus a third place per extra window).

| # | Record | Problem | Status |
|---|---|---|---|
| 1 | C-47, F-183 | Home's chat stayed in the window under a project: two composers fought for the keyboard. | Fixed, with a focus check (`check-composer-focus.sh`). |
| 2 | F-208 | 0.2.5 froze at launch: Home's chat state re-laid out the whole window. | Fixed. |
| 3 | F-449, F-456, Q-341 | The hidden terminal swung between 87 columns (Home's page) and 42 (the column): Claude redrew on every move. | Fixed by holding the hidden terminal at the chat pane's width. |
| 4 | DL-311, DL-314, Q-447 | A terminal can be live in one window only, so other windows show a stand-in with Show Here and Go There. Geoff called this a workaround (ENH-322). | Built as a stand-in. |
| 5 | DL-315, F-558 | The column was closed by default because nobody knew what it was for; a saved-state migration with a `touched` flag followed. | Built. |
| 6 | F-640 (1) | Oliver's report: a black terminal after chat fell back on Home's page: the column, out of sight, took the terminal view from the console. | Fixed (`SlotView.takes`); a debug switch `DUO_SLOT_RULE=old` stays in the app for the live check. |
| 7 | F-640 (2) | Home's Needs you card pointed at the column, which DL-315 had closed, and focused nothing. | Fixed (`showHomeSession` opens it). |
| 8 | C-178, Q-488 | Questions asked of Home at All projects are drawn at 38 to 43 columns, where chat refuses 2 to 4 of 17 question shapes and drops to the terminal. Geoff: these fallbacks "routinely fail". | Open. |
| 9 | F-641 | The hidden terminal is held at 43 columns but shown at 38 (the mic margin, DL-264), so every chat-to-terminal switch in the column redraws, the redraw F-456 removed. | Open. |
| 10 | **F-648 (new)** | **Home's Claude session runs at every launch even though its column is closed.** `AppModel.refreshLive` starts one when Home has none (DL-54), and `HomePane` is built while collapsed (a collapsed pane keeps its view, `PaneSplit`), so `model.terminal(project:session:)` resumes Home's last session. Since DL-315 most people never see it: a `claude` process, its trust check and any question it raises live in a pane nobody opened. | Open (read in code, not run: see "What I checked"). |
| 11 | Q-109 | "Home opens in" has no designed home in Settings; it's a stand-in row. | Open (small). |
| 12 | ENH-28 | The Sessions view (DL-142 D) waits on the Home question (Q-98). | Waiting. |

Fixes 1, 3, 6 and 7 each added a rule that only Home needs (a focus check, a held size, a slot rule, a pane that opens itself). Problems 8, 9 and 10 are open. Every one goes away if Home's session has one place, and that place is as wide as any other console.

**What the column is for.** Asking about everything at once ("what came in overnight?"), and the director in Home (DL-197). Both work the same from a Home session on Home's page: the session runs in Home's folder either way. The column gives a glance at it from All projects. Since DL-315 the glance is closed by default, so for a new user the column is already opt-in, but the session behind it is not (10).

## Options

Effort is in build sessions (a session is about a day of Sonnet work with its checks). Every option keeps Home's sessions themselves: they still show in All projects › List as `★ home`, on Home's page, in Needs you and the Dock badge.

### A. A Settings switch (Geoff's first idea)

**What the person sees.** Settings › Home gains a row: "☐ Show Home's agent at All projects. A Claude session in your Home folder, beside the map." Off by default for new installs. Off: no column, no sidebar button at All projects, no Home session at launch. On: today's column.

- **Goes away (off):** problems 8, 9 and 10 for people who leave it off; the Needs you pointer card (Home sessions get ordinary cards).
- **Stays (on), and in the code for everyone:** 4, 6, 7, 8, 9 and the rules behind 1 and 3. Two modes to test from now on.
- **Migration:** existing installs that touched the column and left it open (DL-315's `touched`) get the switch on; everyone else off.
- **duo2 (DL-71):** `duo2 settings home-agent on|off`.
- **Effort:** about one session. **Risk:** low to build, but it keeps every workaround, and an option that hides a feature tends to stay hidden; ENH-322's "not sure most users will use it" turns into "we can't tell".

### B. Start Home's agent only when asked (Geoff's second idea)

**What the person sees.** At All projects the column is closed and nothing runs. Opening it (the sidebar button, ⌃⌘S, the View menu) the first time shows a short card instead of a session: "Home's agent. A Claude session in your Home folder that can see every project. Use it to ask what needs you, or to run a director across projects. [Start Home's Agent] Not Now". After Start, today's column. The List's `New session in ★ home` row starts one too.

- **Goes away:** problem 10 (no session until asked), and the question of what a closed column is for.
- **Stays:** 4, 6, 7, 8 and 9 for everyone who starts it, and the column's code.
- **Migration:** existing Home sessions keep working; anyone with the column open keeps it.
- **duo2:** `duo2 session new --project home` (exists); the card's buttons map to it and to `duo2 view sidebar hide`.
- **Effort:** about one session (DL-54 reversed, the card, checks). **Risk:** low; one new surface (the card).

### C. Home's agent lives on Home's page only (recommended)

**What the person sees.** All projects is two panes: the map or List in the middle, Needs you on the right. No left column, no sidebar button at All projects. Home is a project like the others: its page (the ★ home tile, the `★ home` rows in the List, ⇧⌘H) opens with its sessions in the left sidebar and the console in the middle, full width, in chat. The List's `New session in [★ home ⌄]` row is the deliberate action that starts a Home session (it already exists, DL-262). Nothing runs at launch.

- **Goes away:** problems 1 to 10 at the root: one place per session, so no slot rule, no held size for a second pane, no pane that opens itself, no Show Here or Go There (Home's page in two windows is the same as any project's: one writer, LR-8). Questions are drawn at a console's width (at the 480 pt minimum, about 59 columns before Q-488's floor). Home's needs-you sessions get full cards with the question and Open Project, like every other project's, instead of the pointer card.
- **What's lost:** the glance at Home's chat from All projects. One keystroke gets there (⇧⌘H), and Needs you still surfaces Home's questions at All projects.
- **Migration:** nothing to move: Home's sessions are where they were. Existing users with the column open see All projects without it. A one-line release note says where Home's agent went. A one-time in-app note is possible (Q-500) but adds a surface for a few users.
- **duo2:** `go home` opens Home's page (was: the column at All projects). `view sidebar` at All projects reports "All projects has no sidebar" (exit 64) instead of toggling. `window home` (Show Here) retires; `window list` drops its Home column. `session open <home session>` opens Home's page. `session chat --home` stays (Home's sessions still open in chat). No new verbs.
- **Effort:** about two sessions, mostly removal: `HomePane` and `HomeElsewhere` out of `AllProjectsLayout`; `homeOwner`/`ownsHome`; the slot's `shown` rule simplifies; DL-315's flag and its migration retire; `HomePointerCard` goes; DL-54 reversed; DuoChecks that pin the column (TerminalSlotChecks, PaneFocusChecks, SplitViewChecks) rewritten; approved screens that draw the column (`home-evolution-handoff` list-1440 and others, `multi-window-handoff` board 10) superseded by a decision. **Risk:** medium: it reverses DL-22, DL-54 and parts of DL-142, DL-311 and DL-315, so several handoffs' screens stop being targets in one place. It also clears the way for ENH-28.

### D. Keep the column, make it work at its width

**What the person sees.** The same column. Either **D1**, Q-488 (a): while chat shows, the hidden terminal is held at 60 columns or more, whatever the pane's width, so questions are drawn at a width the reader is proved at; or **D2**, the column opens wider (480, about 60 columns) at the cost of the map; or **D3**, Home's chat opens as a sheet or popover over All projects (wide, but modal over the map it talks about).

- **Goes away:** problem 8 (D1, D2), 9 (if F-641's margin is also fixed). D3 also removes the pane, but adds a new transient surface that still holds a terminal slot (1, 6).
- **Stays:** 4, 5, 6, 7, 10.
- **duo2:** none new (D1, D2); D3 needs `duo2 view home-agent show|hide`.
- **Effort:** D1 under a session; D2 a design round (it changes DL-129's widths and the approved screens); D3 a design round plus a session. **Risk:** D1 low (one redraw when the terminal is shown in a narrow pane); D2 and D3 medium.

### E. Home in a Sessions view (ENH-28, later)

DL-142's D: All projects lists every session on the left, ★ Home pinned first, and the selected session's chat opens in the middle, wide. Home's agent becomes one of the sessions you can open in place. It's the right long-term shape for "talk to Home from All projects", but it is a design round and a large build, and it waits on Q-98. C clears the way for it; A, B and D don't.

### Side by side

| | Fixes 8, 9 (narrow questions) | Fixes 10 (runs unseen) | Fixes 4, 6, 7 (two places) | New surfaces | Effort | Risk |
|---|---|---|---|---|---|---|
| A switch | for those off | for those off | for those off | a Settings row | ~1 session | low; keeps every workaround |
| B on request | no | yes | no | the start card | ~1 session | low |
| **C Home's page only** | **yes** | **yes** | **yes** | none (a release note) | ~2 sessions, mostly removal | medium; reverses DL-22, DL-54 |
| D1 60-column floor | yes | no | no | none | <1 session | low |
| D2/D3 wider or a sheet | yes | no | partly | a design round | 1 to 2 sessions | medium |
| E Sessions view | yes | yes | yes | a design round | large | waits on Q-98 |

## Recommendation

1. **Q-498: C.** Home's agent lives on Home's page only. It is Geoff's second idea carried through: the deliberate action already exists (`New session in ★ home`, and opening Home's page), and the column it would guard goes, with every workaround it needed. A (the switch) keeps every cost in the code for the people who turn it on, and B keeps them for everyone who starts it.
2. **Q-499: start Home's session on first use** (reverse DL-54). Whatever shape is chosen, no Claude session should run unseen. Home's page with no session shows the existing "Start Claude in Home" state (`ConsoleStates`), and the List's row starts one.
3. **Q-500: a release note only**, no in-app note. Few people opened the column after DL-315; their sessions don't move.
4. **Q-501: at All projects, the sidebar button and ⌃⌘S are hidden** (the toolbar keeps the right-pane button), rather than kept for a later projects sidebar (ENH-146), which would get its own design.
5. **Q-488: (a), hold the hidden terminal at 60 columns or more while chat shows**, and take F-641's mic margin off the held size. Under C the 38-column case goes, but narrow consoles remain (a narrow window, split view's panes), so the floor is still worth having, and it's small. If C is not chosen, (a) is the fix for Home's column too.

## Sketches

New surfaces are drawn on the Design canvas https://claude.ai/artifact/PBJttSgB17RzCn8WQQo6sF with the Duo design system, every mark [P]: **00** the study; **C1** All projects without Home's column (no sidebar button, a full needs-you card for Home); **C2** Home's page as the one place Home's agent runs; **A** Settings › Home's switch; **B** the column's start card; **D2** a 480-wide column. Sources in `docs/design/home-agent-panel-study/canvas/`. Nothing is built.

## What I checked, and what I only read

- **Ran, isolated and in the background, no tokens:**
  - F-648's launch check (`home-agent-panel-checks/check-f648.sh`, a stub `claude` that logs its starts): with Home's column closed, Duo started Home's `claude` at launch and listed a session nobody started (`f648-launch.png`).
  - The live chat suite (`DUO_CHECKS=chat-live`, Claude Code 2.1.316 against the mock API) at 38×49, 43×49 and 60×49: 4, 2 and 0 of 17 question cases fall back (`chat-live-38-43-60x49.txt`). 60×49, Q-488 (a)'s floor at the column's height, had not been run before.
- **Read in code, not run:** the resume of an existing Home session with the column closed (the same `HomePane` body), the launch start (`AppModel.swift` `refreshLive`, the `fixture.home` block), the collapsed pane keeping its view (`PaneSplit.swift`), `HomePane` resuming the session (`AllProjectsPanes.swift`, `AppModel.terminal(project:session:)`), the widths (`Tokens.swift`), the verbs (`DuoControl/Actions.swift`). Launch with a stub `claude` was run (above); a real `claude` was not.
- **Read in records:** everything in the tables above.
