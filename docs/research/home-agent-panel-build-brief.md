# Build brief: Home's agent on Home's page only (DL-336)

For a Sonnet build session started by director-duo-v2. The project CLAUDE.md's "Rules for every build session" apply and aren't repeated here (work tree, isolation, GPU lock, no visible runs, report by SendMessage).

## The job

Build DL-336 (Geoff, 2026-11-11, by button on https://claude.ai/artifact/VX53uLFeMrZ7S2skb3RYHQ):

1. **No Home column at All projects.** All projects is the middle (List or Board) and the Needs you column. Home's sessions run only in the console on Home's page.
2. **No Home session at launch.** One starts on first use: Home's page's existing "Start Claude in Home", the List's `New session in [★ home ⌄]` row, ⌘T there, or `duo2 session new`.
3. **The sidebar button and ⌃⌘S are hidden at All projects.** `duo2 view sidebar` at All projects exits 64 with "All projects has no sidebar".
4. **Q-488 (a):** while chat shows, the hidden terminal is held at 60 columns or more, whatever the pane's width, and the held size takes off the mic margin as `SlotView.layout` does (F-641).
5. **A release note only** (Q-500): nothing in the app. Put the line you'd suggest in your finding; the release skill picks it up from DL-336.

Read first: `docs/research/home-agent-panel.md` (the problems and the option, with file references), DL-336 in `docs/design/decisions.md`, F-640, F-641 and F-648 in `docs/plan/findings.md`.

## Targets

- The canvas https://claude.ai/artifact/PBJttSgB17RzCn8WQQo6sF, **board C1** (All projects) and **board C2** (Home's page). Their sources are `docs/design/home-agent-panel-study/canvas/project/c1-allprojects.dc.html` and `c2-homepage.dc.html`. The yellow notes are the board's, not the app's.
- C1 is a sketch on the home-evolution study's sample data, not a pixel target for the List: the List, its rows, the header and the cards are as built (`home-evolution-handoff/` `list-1440`, `needs-you`). What C1 sets is this:
  - no left pane and no sidebar button at All projects;
  - the middle takes the 340 the column had (at 1440: the middle and 340; at 1280 the same rule);
  - **a Home session that needs you is an ordinary needs-you card** (`ActionCard`, the same as any project's: name, `★ home · question` or the reason, the question box, the button). C1 draws its button as **Open Home**. Every other card says Open Project. If that wording isn't simple in `ActionCard`, use Open Project and ask the director, rather than inventing a third look.
- C2 is a project page as built, with ★ home's name. Nothing new is drawn there, so C2 is a check that Home's page works like any project's (sessions in its sidebar, console in chat at full width), not a pixel target.
- **Before you build, export the two boards** as a handoff, `docs/design/home-agent-panel-handoff/`:
  - `screens/c1-allprojects.html` and `c2-homepage.html`: the boards as published, the `.dc.html` wrapper stripped, as the other handoffs do; see `home-evolution-handoff/canvas/` for the reverse direction.
  - `screens/png/*@2x.png`, rendered with `build-handoff/tools/lib.sh`'s `shoot`.
  - A README naming DL-336, the targets, and what's exempt: the yellow notes and the sample data.
  - Don't edit the boards themselves.

## Slices (commit each, in order)

**Slice 1: All projects without the column.**
- `Shell/RootView.swift` `AllProjectsLayout`: take `HomePane` out of the `PaneSplit`. The split becomes the map or List plus `ActionColumnPane`. `PaneSplit` must cope with two panes; check how a project's split handles it.
- `AllProjects/AllProjectsPanes.swift`: delete `HomePane`, `HomeRule` (if only Home uses it), `HomePointerCard` and their helpers. Needs you shows Home's sessions as ordinary cards; find where `HomePointerCard(session:)` is chosen (around line 840) and drop the branch. Remove `HomePointerCard` from `Debug/GalleryView.swift`.
- Tokens: `paneOverviewHome` and `paneMinHome` go from `docs/design/build-handoff/tokens.json`. Then run `python3 scripts/gen-tokens.py` and `python3 scripts/gen-design-system.py`; never edit `Tokens.swift` by hand. Check `scripts/gen-tokens.py`'s own references.
- The toolbar's sidebar button is hidden at All projects; ⌃⌘S and View › Toggle Sidebar are disabled there (the menu item stays, disabled, as macOS does).
- `AppModel.leftCollapsedAllProjects` and `leftTouchedAllProjects`, their restore fields (`AppModel+Restore.swift`) and their uses (`AppModel+Home.swift`, `AppModel+Panes.swift`, `Debug/TargetState.swift`) go. Old restore files that carry them must still load: keep the Codable keys optional and ignored.
- `AppModel+Panes.swift`:
  - `showHomeSession` opens Home's page with that session selected, as a session link to any project does.
  - `focusHome`, and `focusPane(.left)` at All projects: ⇧⌘H opens Home's page; the left-pane key at All projects does nothing.
  - `focusHomeRequest` goes. Nothing reads it (F-640).
  - `goHome()` (`AppModel.swift`, ⇧⌘H) opens Home's page with Home's needs-you session selected, or its last.
- `AppModel+Links.swift`: a session link to a Home session opens Home's page.

**Slice 2: one place per session; windows.**
- `Model/AppCore+Windows.swift`, `AppCore.swift`, `Shell/WindowViews.swift`, `Control/AppModel+WindowControl.swift`:
  - `homeOwner`, `ownsHome` and `HomeElsewhere` go.
  - Home's page in two windows behaves as any project's page does in two windows.
  - Routing Home's sessions to the owner window (`AppCore+Windows.swift` around lines 104 and 157) goes.
- `Terminal/Terminals.swift`:
  - `TerminalSlot`'s `shown` rule (F-640) can simplify now that no window holds two slots for one session. Keep C-43's rule for two windows.
  - Remove `DUO_SLOT_RULE=old` and `scripts/check-chat-fallback-slot-live.sh`'s `RULE=old` and `WHERE=all-projects` paths. Keep the check for Home's page.
- `DuoChecks/WindowChecks.swift`: rewrite its Home ownership checks as "Home's page in two windows is any project's".

**Slice 3: no Home session at launch.**
- `AppModel.refreshLive` (`AppModel.swift` around line 538): drop the `if homeSessions.isEmpty { newSession(in: home.name) }` start. Keep `homeTab` pointing at Home's first session when there is one, but nothing may resume a session just because it's `homeTab`: with the column gone, only Home's page's console calls `model.terminal(project:session:)`.
- Home's page with no session shows the built `ConsoleMessage` "Start Claude in Home" (`Project/ConsoleStates.swift:198`). Check its words still fit, now that this is the normal first state rather than "the last one was closed". If they don't, keep them and ask the director.
- Re-run `docs/research/home-agent-panel-checks/check-f648.sh` on your build. It must log **no** `claude` start at launch, and the List must show no "Session …" row.

**Slice 4: Q-488 (a) and F-641.**
- `TerminalSession.applyHeldSize` (`Terminals.swift` around line 197):
  - take off the same mic margin `SlotView.layout` takes (`VoiceMicStyle.current.keepsMargin` on a Claude terminal, 4 cells);
  - then hold the hidden view at **max(pane width, 60 columns)** while chat shows;
  - name the 60 once, as a constant beside `holdSettle`, with its reason (Q-488, F-648: 60×49 clean).
- `scripts/check-chat-narrow-live.sh`:
  - it drives Home's column at All projects today, which no longer exists, so point it at a narrow console instead (a narrow window, or split view's narrow side);
  - expect the hidden terminal at 60 or more while chat shows;
  - expect one resize at most when the terminal is shown in a pane under 60 columns: Q-488's accepted cost.

**Slice 5: duo2 and docs.**
- `DuoControl/Actions.swift`:
  - `view sidebar` at All projects exits 64, "All projects has no sidebar";
  - `window home` (Show Here) goes;
  - `go home` opens Home's page;
  - `window list` drops its Home column or field;
  - `session open <home session>` opens Home's page.
  - Run DuoChecks' parity scan. Also remove the stale `Parity.uiOnly` entry "Open Settings…" ("not built"): Settings exists.
  - Regenerate `docs/cli/duo2.md` with `build/Duo.app/Contents/Helpers/duo2 help --markdown`.
- `docs/design/system/surfaces.md`:
  - "Home pane: terminal and session tabs" and "Home pane with no Home folder": retired, DL-336;
  - "Home in a second window": retired;
  - "The session list": no Home column beside it;
  - the `HomePane` component README: retired, DL-336.
  - The "dark pane is whoever you're talking to" principle in `docs/design/system/README.md`: at All projects there's no dark pane now. Say so in one line. Don't publish the design-system artifact; the director does.
- `docs/design/README.md`: list the new handoff.
- Where DL-336 supersedes them, mark these handoffs' screens in their READMEs (don't edit the screens):
  - home-evolution: `list-1440`, `list-1280`, `board-1440`, `home-chat`;
  - multi-window: `board-10-home`;
  - stand-ins: `q57-home-pill`;
  - surfaces: `home-none`.

## Checks (each slice's own, then all at the end)

- **Build:** `swift build` and DuoChecks (`swift run DuoChecks`), under the GPU lock in `--shared` mode. These pin the column and need rewriting rather than deleting:
  - `TerminalSlotChecks.swift`: the card opens Home's page;
  - `PaneFocusChecks.swift`;
  - `SplitViewChecks.swift`;
  - `main.swift`: around line 552, and its `paneOverviewHome`;
  - `WindowChecks.swift`.
- **States:**
  - `scripts/check-ui.sh list-1440 list-1280 board-1440 list-new-session-nohome list-new-session-empty`, and every Home List state in `Debug/HomeListTargets.swift`, plus a needs-you state with a Home session (add one to `HomeListTargets` if none exists).
  - Compare with board C1, region by region: no left pane; the middle starts at x=0; the Needs you column is still 340; Home's card is ordinary.
  - Measure with `scripts/pixels.py`.
- **Home's page:** a capture of Home's page in chat (a fixture state) beside board C2.
- **Live, isolated and in the background** (a stub `claude`, or the mock API; no real Claude turns):
  - `check-f648.sh`: no start at launch;
  - `check-chat-fallback-slot-live.sh` on Home's page;
  - the reworked `check-chat-narrow-live.sh`;
  - `check-composer-focus.sh`: it guarded C-47's two composers, and may now only need Home's page;
  - `check-windows.sh`: Home's page in two windows.
- **chat-live:** `DUO_CHAT_LIVE_SIZES=60x49 DUO_CHECKS=chat-live swift run DuoChecks` must stay 17 of 17. 38×49 may still fall back: it's no longer a width Duo draws questions at while chat shows.
- **Background:** `scripts/check-background.sh` still proves the front app stays in front.
- **Merge gate:** the director runs it at merge. Name in your report anything you expect it to flag.

## Records

- Take the next free F-, C-, Q- and ENH- numbers from `tasks/_record-reservations.md` in the main checkout. The director reserves them in your brief. Commit each record with its code.
- One finding for the build. It says:
  - what moved;
  - the release-note line you'd suggest, for example: "Home's agent now lives on Home's page: ★ home in the list, or ⇧⌘H. New Home sessions start when you ask, not at launch";
  - what you checked live versus only in DuoChecks.
- Anything undrawn you had to decide goes in `docs/plan/concerns-and-questions.md` as a stand-in with a question, never invented. The likely ones:
  - the "Open Home" button wording;
  - "Start Claude in Home" as the first state of Home's page;
  - ⌃⌘S disabled at All projects versus beeping.

## Done means

- All five parts of DL-336 are built on a branch from origin/main, in slices, not pushed.
- Captures are compared with C1 and C2, and the last comparison images are kept in `docs/design/home-agent-panel-handoff/checks/`.
- `check-f648.sh` logs no launch start.
- chat-live at 60×49 is 17 of 17.
- DuoChecks and the parity scan pass.
- `docs/cli/duo2.md` and `surfaces.md` are updated.
- The report reaches director-duo-v2 with:
  - full shas;
  - each check's result;
  - what was run versus read;
  - the suggested release-note line;
  - any new questions with their links.

## Not in this job

- ENH-341 (an opt-in way back to a Home column) and ENH-28 (the Sessions view).
- The intro film: it may show Home's column. Run `node video/build.mjs --check` in `video/` and report what it says, but don't re-shoot anything.
