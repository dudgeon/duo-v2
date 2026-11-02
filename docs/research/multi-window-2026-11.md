# Multi-window Duo, round 2: status, architecture and a build plan (2026-11-02)

**Why now.** A power user (v1) relies on several windows to move between projects, and Geoff wants multi-window. This round starts from the first one (`docs/research/multi-window.md`, 2026-10-07), DL-141, the studies canvas https://claude.ai/artifact/46yWPpDZn16Qtfrfhbuaw1 (`docs/design/multi-window-studies/`) and the spec page https://claude.ai/artifact/GaK5hPxTAxphXEZJSoXaYA. It doesn't redo them. It covers what has changed, the architecture in today's code, a build plan whose first slice is small, and the questions Geoff has left to answer.

Records: F-537, F-538, C-146, ENH-318, Q-428 to Q-432. Q-95 to Q-99 have been updated. Round 3 (later on 2026-11-02) added DL-308 (Q-428 answered), ENH-319 and F-542 (a base colour per window) and Q-435. Its review page for Geoff is listed under "Decisions for Geoff".

## Recommendation in five lines

1. **Code: keep `AppModel` as the window model, one per window, and lift what is app-wide into a new `AppCore`** (option 1 below). Most per-window state already sits on `AppModel`, whose doc comment says "One instance per window", so this moves the smaller half: the data, the processes and the per-project memory.
2. **Slice 0** makes that cut with nothing visible changing. **Slice 1** is the slice for the power user (v1): New Window ⌥⌘N, Open in New Window, each window titled with its project, and switching with ⌘\` and the Window menu.
3. **One rule until Q-97 is answered: a project is in one window.** Opening a project that already has a window brings that window forward (Xcode, Zed). This keeps C-43 and the two-editor problem out of slices 0 to 2, and it doesn't conflict with DL-141.
4. **`duo2` acts on the window that holds the caller's session.** With no session, it acts on the primary window, never the key window (v1's lesson). Only the on-screen verbs (about 50 of 248) need a `--window`.
5. **Build slices 0 and 1 now, past build plan §3a, giving the power user as the reason.** Then build restore and needs-you (slice 2). Window base colours (ENH-319) get their own slice once Q-435 is answered. Pins and one session in two windows (slice 3) wait for Q-95 to Q-97. Q-428 is answered: a project lives in one window (DL-308).

## 1. Status

### What Geoff has decided

- **DL-141 (2026-10-07):** independent windows, each optionally pinned to a project and optionally tinted as a whole. New Window is ⌥⌘N, and ⌘N stays New Markdown File. He chose this over the research's recommendation, a window per project.
- **Nothing else.** The spec page's `picks` and `submissions` collections are empty (read 2026-11-02 with ArtifactData). Neither the canvas nor the spec page has any comment threads.
- **Q-95 to Q-99 are all open:**
  - Q-95: opening and pinning (D1 to D3);
  - Q-96: tints (D4, D5, D11);
  - Q-97: one session or document in two windows (D6, D7);
  - Q-98: needs-you, the Window menu and Home (D8 to D10);
  - Q-99: when to build (D12).

### What has changed in v2 since 2026-10-07

| Area | Change since the first round | What it means for multi-window |
|---|---|---|
| **Split view** (DL-275 to DL-278, DL-306; F-506, F-531) | `SplitState` lives on `AppModel` and is documented "One `SplitState` per window". Its `taken` room (what a split took from the sidebar or console) is re-decided for the window it comes back in (F-531). A 1280×800 minimum is enforced per window. DL-306: under 1,303 the sidebar folds. | Already window-shaped. A second window gets its own room and fold. The per-project split tabs (`tabs[project]`) are per-project memory and move to `AppCore` (section 2). ENH-303 (detach a split into its own window) fits after slice 1. |
| **Editors** (C-135, F-506) | `EditorSet` on the model: one editor per side (`.main`, `.second`). `DocumentHomes` is a **shared** registry of which editor holds each file's buffer. Opening a file held elsewhere saves it there and lets it go first. | Half of the first round's per-window viewer work is done. With one `AppModel` per window, each window gets its own `EditorSet`, and `DocumentHomes` already keeps the one-home rule for a file across windows. The HTML, deck and Word viewers are still one per model (C-141), which is per window under option 1. |
| **Right pane and tabs** | Decks (hidden in release builds, DL-307), the Word viewer, web tabs, F-495's ⌘W routing (`keyboardInRightPane`). | Every viewer is a lazy property on `AppModel`, so it becomes per window for free. `webTabs` is a per-project dictionary of `WKWebView`s and has to be app-wide (it follows the project). |
| **Sessions and terminals** | Home opens in chat (DL-142), voice input (one microphone, `VoiceInput`), `ChatKeys`, shells per project (`shellTabs`). | Terminals stay one view per session, moved between slots (C-43). Under the one-project-one-window rule a session's view has one window to be in, except Home's (Q-431). The microphone is app-wide: dictation goes to the key window's composer. |
| **Control socket and `duo2`** | About 248 verbs (`DuoControl/Actions.swift`), DL-71 parity, director verbs (DL-256, DL-257). Requests carry `session` and `cwd`, never a window. | About 50 verbs act on what is on screen: `view *`, `go`, `open`, `peek`, `status`, `undo`, `split *`, `doc`/`html` with no path, `capture`, `doc shot`, `session open/close/next`. Those need a window. The other ~200 (sessions by id, files, repo, search, send, tasks, review, director) don't (Q-430). New Window and Close Window need a verb or a `Parity.uiOnly` line (Close Window is listed there today). |
| **Restore** | `restore-<FNV(Home root)>.json`, one file per Home workspace (`AppModel+Restore.swift:49`). It holds one on-screen project, the collapse flags, `homeTab`, `splitRoom` and a `projects[]` of per-project memory. | The per-project part stays as it is. The window part becomes `windows: [...]` in version 2, with a `.v1` backup (slice 2). Frames move from the single autosave name `"main"` to `"main"`, `"window-2"` and so on. |
| **SheetCenter** | 68 references. It is a global FIFO queue drawn by every `RootView`'s `SheetOverlay`. | With two windows, the same question would draw in both. Each question gets a target window: the window showing its project, else the key window, else the primary window (slice 0). |
| **Search** | `SearchService.shared` (the index), `SearchUI` on the model, ⌥⌘↩ opens in split. | The index stays app-wide and `SearchUI` becomes per window. A result in a project that another window holds brings that window forward (slice 1). |
| **The director** (DL-166, DL-200, DL-257) | The director drives Duo through `duo2`, often from outside Duo with no `DUO_SESSION_ID`. `refreshLive` prunes the director registries and delivers review comments. | The director's calls must land somewhere predictable: the primary window (Q-430). Its pruning and delivery are app work and must run once, not once per window (C-146). |
| **Notifications** | `Notifier.shared.model` is one weak reference, set on every refresh. | It becomes `AppCore`'s, and a notification click opens the project's window (slice 2). |
| **Key monitors** | `PaneKeyMonitor.installed` is static and binds the first model. `PaneFocus.swift:65` requires `title == "Duo"`. `ChatKeys` resolves the window from the event. | Each needs to map the event's window to that window's model (slice 0). |

## 2. Architecture

### Today: one `AppModel`, one `MainWindow`

The current counts are in F-537.

- `DuoApp.init` makes one `AppModel` (`Sources/Duo/DuoApp.swift:36`), one `ControlServer` (`:54`, with `handle` on that model) and one `MainWindow` (`:125`).
- `MainWindow.show()` makes an `NSWindow` by hand (F-29), titles it "Duo", autosaves its frame as "main" and calls `FixtureHarness.configure`.
- The scene is only `Settings {}` and `DuoCommands(model:)`.
- `AppDelegate`'s `reopen`, `dockMenu`, `openURL` and `flush` close over the one window and model.
- `AppModel` (970 lines plus 45 `AppModel+*.swift` files, about 9,900 lines) holds both kinds of state:
  - **Per-window:** `altitude`, `currentProject` (derived from it), `consoleTab`, `rightTab`, `homeTab`, `selectedFile`, `selectedSidebarItem`, `sessionSelection`, the pane collapse flags, `sidebarWidth`, `projectShown`, `fullScreen`, `splits`, `search`, `peekOpen`, the list and map filters, hover and drag, forms, `explainer`, `webFocus`, `editors`, `htmlViewer`, `deckViewer`, `docxViewer`.
  - **App-wide:** `fixture`, `liveRoot`, `liveFolders`, `terminals` (`TerminalStore`), `chats` (`ChatStore`), `repos`, `issueStates`, `trustNotices`, conversions, `refreshTimer`, `minuteTimer`, `seen`, `notified`, `keepRunningIDs`, `archivedProjectPaths`, `detachedForks`, the restore bookkeeping, `voice`, and the `DuoState` settings.
  - **Per-project memory, kept on the model today:** `openDocumentsByProject`, `lastConsoleTab`, `lastRightTab`, `shellTabs`, `shellTitles`, `consoleTabOrder`, `webTabs`, `parkedTabs`, `sourceDocuments`, `splits.tabs[project]`.
- The live loop: `startLive` (`AppModel.swift:~495`) starts the 2 s `refreshTimer`. It runs `refreshLive` and `scanTrustNotices`, which apply the snapshot and then do app work: `notifyNeedsYou`, `pruneDirectorRegistries`, `deliverReviewComments`, `archiveListedSessions`, `GitIgnoreOffer`, `moveDuoFiles`. They also do window work: the seen mark for `visibleSessionId`, and `settleMapOrder` keyed on `altitude`.
- Lookups of "the window": `title == "Duo"` in about 30 places. Eight are in product code: `DuoAlert.swift:10`, `AppModel+Panes.swift:96` (`paneWindow`), `Commands.swift:474` (Full Screen), `PaneFocus.swift:65`, `AppModel+Control.swift:49` and `AppModel+Organize.swift:318` (undo), `AppModel+Walk.swift:28` and `SessionListFilter.swift:141`. The rest are in the harness (`FixtureHarness`, about 25) and `ChatPerf`. `NSApp.keyWindow` is used in Close Window (`Commands.swift:307`), Settings and `Explainer`, and `NSApp.mainWindow` in `Shells.swift:68`.

### What is per window, what is app-wide, and what follows the project

This is the round's main finding (F-537): **there are three kinds of state, not two.**

| Kind | Holds | Where it lives |
|---|---|---|
| **App-wide** | Projects and sessions (`fixture`, `liveFolders`), terminals and their processes, chats, file watching and the refresh loop, the search index, notifications and the badge, `seen` and `notified`, director registries, restore I/O, settings, voice | `AppCore`, one per process |
| **Per project** ("follows the project") | Its open documents, last console and right tabs, tab order, shells, web tabs (`WKWebView`s), parked tabs, split tabs | `AppCore`, keyed by project, as the restore file already is. A project moving to another window brings all of it along. |
| **Per window** | Altitude and the project on screen, the console and right tab now showing, the collapse flags and widths, the split's room, search UI, peek, filters, hover, drag, forms, focus, undo, the editors and viewers, the sheet overlay, pane motion | `AppModel`, one per window |

### How a session or document moves between windows

- **A project** moves when you open it in another window, or when a window showing it navigates elsewhere and another window opens it. The per-project memory stays in `AppCore`, so the second window shows the same tabs. Terminal and web views move on the next draw, because `TerminalSlot` reparents them as it does today between the console, Home and the peek. The one fix (C-43): a slot removes only a view it still holds.
- **A session** belongs to its project. Moving a session to another project (`duo2 session move`, the sheet) takes it to that project's window, if there is one.
- **A document** belongs to its project's tab list. Its buffer has one home, through `DocumentHomes`. If it opens in another window's editor, the first editor saves it and lets go (F-506), so nothing is lost even if the one-project rule is relaxed later.
- **Home** is a project with one terminal. Its rule is Q-431.

### Options

| | **1. Per-window `AppModel` over a shared `AppCore` (recommended)** | **2. App-wide `AppModel` plus a new `WindowModel`** (the 2026-10-07 plan) | **3. One Duo process per window** |
|---|---|---|---|
| Shape | A new `@Observable final class AppCore` (`DuoKit/Model/AppCore.swift`) takes the app-wide and per-project state, the live loop, `TerminalStore`, `ChatStore` and restore I/O. `AppModel` gets `let core: AppCore` and forwarding computed properties (`var fixture: Fixture { core.fixture }`, and so on), so its 1,866 `model.` call sites and 191 `@Environment(AppModel.self)` readers don't change. `AppCore.windows: [WindowID: AppModel]` (weak) and `primary`. | `AppModel` stays app-wide. A `WindowModel` takes about 45 properties: `altitude` (110 references), `consoleTab` (170), `rightTab` (151), `currentProject` (180) and the rest. Views read two environment objects. | `open -n` a second Duo on the same Home. |
| Cost | Slice 0 is 2 build sessions (sorting 45 extensions into core and window; the title lookups; sheets, motion, menus, keys). Slices 1 to 3 as below. | Slice 0 is 4 to 5 build sessions: about 1,000+ call-site edits across views and `duo2` handlers. Every parallel branch that touches `AppModel` conflicts. | Small, but it breaks everything below. |
| Risk | Hidden app work inside `AppModel` methods running once per window (C-146): two disk scans, two notifications, two archive passes. Forwarding properties hide which object owns a value; a DuoChecks check counts the work per refresh with two models. `@Observable` tracks through computed forwarders, because `AppCore` is itself observable. | The size, and the churn while about six sessions build on `AppModel` each day. Mixing up `model.` and `window.` at a call site compiles, but routes wrong. | Two processes would both resume the same sessions, open two sockets (`duo2` reaches one) and keep two `restore-*.json` writers and two needs-you counts. |
| Rules out | Nothing for the product. All of DL-141 (pins, tints, a session in two windows) fits on top. | Nothing for the product, but it costs the most. | Shared sessions and terminals, needs-you across windows, one `duo2`. **Ruled out.** |

Why option 1: the code already treats `AppModel` as the window (its doc comment, `SplitState`, `EditorSet`, the viewers). Most of the state Geoff's windows need to differ already sits on it. Lifting the smaller half leaves views and `duo2` handlers as they are. v1's lesson applies too: it shipped a "registry-of-one" spine first, byte-identical with one window, and only then opened window 2 (F-538).

## 3. Build plan (option 1)

Each slice ends with DuoChecks, the check-ui states unchanged or compared with their boards, and a capture kept for Geoff. The timing checks (`check-chat-perf`, idle CPU) run through `scripts/timing-lock.sh`.

### Slice 0: one core, one window (nothing visible changes)

- **Build:**
  - `AppCore` with the app-wide and per-project state, and forwarders on `AppModel`.
  - `DuoApp` makes `AppCore` once, and `AppModel(core:)` for the main window.
  - `ControlServer` hands requests to `core.handle`, which resolves a window model (today, always the primary) and calls the existing `perform`.
  - Split `refreshLive` into `AppCore.refresh` (snapshot, notifications, director pruning, review delivery, archive, GitIgnore, moving files) and `AppModel.didRefresh` (the seen mark for its visible session, `settleMapOrder`). `Notifier.shared` points at the core.
  - `AppModel.window` (a weak `NSWindow`, set in `MainWindow.show`) replaces the eight product `title == "Duo"` lookups. Undo uses `model.window?.undoManager`.
  - The harness gets a `FixtureHarness.window(n)` helper and keeps "Duo" as window 1's title, so captures don't change.
  - `SheetCenter`: each `DuoQuestion` gets `target: QuestionTarget` (`.project(id)`, `.window(WindowID)`, or `.any`), and `SheetOverlay` draws a question only in its resolved window. `DuoAlert` uses the asking model's window.
  - `PaneMotion`: the counter and the notification are per window (`object: window`) (C-44).
  - `DuoCommands` resolves `core.keyModel` (the model whose window is key, else the primary) for every action. `PaneKeyMonitor` and `ChatKeys` map the event's window to its model.
  - `TerminalSlot`: a slot removes only a view it still holds (C-43).
- **Prove:**
  - `DUO_CHECKS=core` builds two `AppModel`s on one core and checks:
    - one scan and one notification per refresh;
    - each model's `altitude`, `consoleTab` and split are independent;
    - per-project memory is shared.
  - Every check-ui state is unchanged, and the timing runs are unchanged.

### Slice 1: two windows, one project each (what the power user (v1) needs)

- **Build:**
  - **File › New Window ⌥⌘N** opens a new window at All projects (`core.openWindow()`: a new `AppModel`, a new `MainWindow`, autosave name `window-<n>`, offset by 22 pt).
  - **Project › Open in New Window**, also on the right-click menu of map tiles and sidebar project rows (board 1's recommended option A). Bound to the verb `duo2 window new [<project>]`.
  - **The one-project-one-window rule.** `core.open(project:from:)` brings forward the window that already shows a project, wherever the open comes from: a tile, the sidebar, search, the peek's jump, a notification, `duo2 open`, `duo2 session open`. Otherwise it opens in the window the action came from.
  - **Home** as Q-431 decides. As recommended, every window has All projects. Home's pane is live in the window that last had it, and the others show "Home is open in another window" with Show Here. This is a stand-in until Q-98 D10 is drawn, and it gets a C or Q row when it's built.
  - **Window titles** are the project's name, or "Duo" at All projects. The system's Window menu then lists the windows, and ⌘\` moves between them. Nothing is drawn by Duo.
  - **Close Window (⇧⌘W)** closes a second window. Its project's memory stays in the core and its sessions keep running. The last window still doesn't quit Duo (v1's teardown bug, F-538).
  - **`duo2 window list|new|focus|close`**, and `status` lists the windows. On-screen verbs resolve by Q-430's rule, and `--window <n|project>` goes on the on-screen families. DL-71's parity check and `docs/cli/duo2.md` are regenerated.
  - **Harness:** `window-new:<project>`, `--capture-window <n>`, and a check-ui state `two-windows`.
- **Visible:** two menu items (board 1), window titles, and a stand-in for Home (Q-431). No new tokens. A capture of each window is compared with board 1 and board 10.

### Slice 2: the window set survives, and needs-you across windows

- `RestoreState` version 2 with `windows: [{id, altitude, project, collapse, homeTab, splitRoom, frameName}]`. The primary window comes first, `projects[]` is unchanged, and there's a one-time `restore-<key>.v1.json` backup. Off-screen frames are clamped, and a missing project falls back to All projects.
- **Needs-you:** each window's chip counts sessions not shown in it (board 8, Q-98 D8). A notification click and the peek's jump bring forward the project's window. Duo's windows go in the Window menu with needs-you marks (board 9, Q-98 D9). The Dock menu opens the right window.
- **Checks:** relaunch with two windows; a notification click into a window in the background.

### Colour slice: a base colour per window (ENH-319, after slice 1 and Q-435)

Geoff, 2026-11-02, answering Q-99: "One user request for multi window mode is to set different base colors per window instance; because window instances can be used to isolate user mental context, this helps context switching; we could even have each new window automatically pop in a new color; would need to be mutually exclusive w classic mode".

**Where it fits.** It needs one `AppModel` per window (slice 0) and a second window (slice 1), and nothing from Q-95 to Q-97. So it is its own slice, which can run beside slice 2 once Q-435 is answered. It replaces the "tints" part of slice 3: a base colour is board 4's option B (toolbar at full colour, panes at half) carried into dark, and Q-435 folds in Q-96's D4, D5 and D11.

**The design** is on the canvas https://claude.ai/artifact/46yWPpDZn16Qtfrfhbuaw1, boards 4a to 4c, all [P]:
- **Board 4a · A base colour for each window, light and dark.** Sky, Sage, Lilac, Sand and None, each with a light and a dark ground, pane and swatch. The colour changes the toolbar ground and the pane shade. The console, text, rules, selected row, cards, fields, the document's page and the needs-you orange stay as they are.
  - Contrast: text is 12.4:1 or better everywhere.
  - text2 is 5.59:1 or better on a coloured pane in light, and 6.18:1 or better in dark.
  - The light toolbar's needs-you chip keeps F-169's white fill, because the orange is 4.07–4.35:1 on a coloured light ground.
- **Board 4b · A new window's colour, and changing it.**
  - Recommended: a new window takes the first colour no open window has (Sky, Sage, Lilac, Sand, then round again). The first window stays None. A switch, "Colour new windows automatically", turns this off.
  - The alternative: new windows open plain.
  - To change a colour: the swatch after the project's name opens the five colours and the switch, or Window › Window Colour ▸, or `duo2 window colour <name>` (DL-71).
- **Board 4c · Window colours and Classic.**
  - Recommended: Classic turns window colours off. Every window shows Classic and the swatch leaves the toolbar. Window › Window Colour is dimmed with the reason. Each window gets its colour back when you leave Classic.
  - The alternative: window colours make Classic unavailable until every window is None.

**What it touches (F-542).** A window colour is a palette of window themes over the design tokens. It is not a fourth scheme like Classic, because a scheme resolves inside `NSColor`'s dynamic provider, which sees only the `NSAppearance`, and an appearance doesn't say which window it is drawing.
- **Tokens:** a `windowColour.<name>.light|dark.ground|pane|swatch` block in `build-handoff/tokens.json`. `gen-tokens.py` generates `DuoWindowColour`, and `gen-design-system.py` and the design system's `surfaces.md` add it as well.
- **Resolution:** the four tokens a colour overrides (`ground`, `pane`, `chatGround` and `toolOutputFill`) resolve through an environment value, `windowColour`, which each window's `RootView` sets from its `AppModel`. They become a `ShapeStyle` with `resolve(in:)`. That covers about 150 SwiftUI uses. The 18 AppKit uses (`DuoNSColor.ground` and `.pane`) ask the window's model.
  - A DuoChecks gate keeps the plain constants out of window-coloured views.
  - Web views (the editor, the HTML pages, decks) don't change, because the document's page keeps its colour.
- **Classic:** while `DuoScheme.classicActive` is set, `windowColour` resolves to None. That one line is the exclusion.
- **State:** `AppModel.windowColour`, saved per window in the restore file's `windows[]` (slice 2). "Colour new windows automatically" goes in `DuoState`.
- **Size:** 1 build session, plus the captures of 4a in light and dark.

### Slice 3: the rest of DL-141 (after Q-95 to Q-97)

- **Pin and the pinned-jump rule** (boards 2 and 3).
- **Relaxing the one-project rule into D6 and D7:**
  - a session in two windows, live in one and in chat in the other (F-168);
  - a document read-only away from its editor, with Edit Here, through `DocumentHomes`.
- **Then, separately:** ENH-303 (detach a split), ENH-26 (drag out to a window), ENH-27 (native tabs), ENH-318 (window sets).

### Sizes

| Slice | Build sessions (Sonnet) | Visible |
|---|---|---|
| 0 | 2 | nothing |
| 1 | 1–2 | menu items, titles, the Home stand-in |
| 2 | 1 | the chip, the Window menu, restore |
| colour | 1 | the window colours (boards 4a to 4c) |
| 3 | 2–3 | pins, chat elsewhere, read-only documents |

Slices 0 and 1 total 3 to 4 sessions, against v1's 13 to 17 engineer-weeks. They're cheap because the one-project rule leaves out what made v1 expensive: anything shown anywhere, focus routing, and a renderer per window.

## 4. What v1 teaches (F-538)

From `/Users/geoff/repos/duo` (ENH-191, its PRD `docs/prd/enh-191-multi-window.md`, tasks.md, `docs/DECISIONS.md:1049`):

- **The "three releases" were staged, not broken and fixed.**
  - v0.9.1 hardened write serialization. It fixed a lost-update bug that predated windows.
  - v0.9.2 shipped the registry with one window and no visible feature.
  - v0.10.0 opened window 2.
  - No BUG entries were filed against window routing after it shipped.
  - The cost was the 13 to 17 weeks of spine work, because Electron's main process held 128 reads and 37 sends to one `mainWindow`, plus 12 last-writer-wins caches.
- **What broke during the build:**
  - **Focus-based routing silently dropped sends to windows in the background.** You can't see this in testing, because the one window is focused. The fix was identity over focus, enforced by a grep gate (`check:routing`).
  - **Closing the last window tore down the socket**, which left `duo` dead after a Dock reopen.
  - Crashes in window 2's context menus, popups and confirms.
  - Dialogs parented to the main window.
  - Per-window caches pruned from one window's ids, erasing the other window's state.
- **Still open in v1:**
  - the per-request window target was module-global and "correct by discipline";
  - a window closed just before a crash came back;
  - the git watcher was last-armer-wins.
- **What v2 takes:**
  - the spine first, identical with one window (slice 0);
  - identity over focus for `duo2` and the director (Q-430);
  - a grep gate in DuoChecks against new `title == "Duo"`, `NSApp.keyWindow` and `NSApp.mainWindow` in product code;
  - app teardown only at quit;
  - per-window state keyed by window id;
  - restore written on window close, not only on the 5 s throttle.
- **Corrections to the first round:** lessons 31 and 32 of `legacy-duo-product-review.md` are about the accessibility tree, not windows. The window lines are 36, 81, 192, 229 and 235.

## 5. Decisions for Geoff

Each row is also in `docs/plan/concerns-and-questions.md`. The recommended option is listed first. The boards are on the canvas https://claude.ai/artifact/46yWPpDZn16Qtfrfhbuaw1, and the spec is https://claude.ai/artifact/GaK5hPxTAxphXEZJSoXaYA. No question needs a new board: slice 1's visible parts are on boards 1, 9 and 10.

**Review page (round 3):** https://claude.ai/artifact/AH33RCyja4xoCDUihYndZo (`docs/research/multi-window-review.html`). It covers Q-99, Q-429, Q-431, Q-435 (in three parts), and Q-426 and Q-427 from the power-user audit. Each card has a Send button. Answers are saved in the page's db as `answers/<id>` (the ids are `q99-when`, `q429-scope`, `q431-home`, `q435-palette`, `q435-new`, `q435-classic`, `q426-browser` and `q427-notice`) and also sent to Claude. The window colours were drawn after round 2, on boards 4a to 4c.

| Q | Question | Options (recommended first) | Shown on |
|---|---|---|---|
| **Q-99** (open) | When to build | **Slices 0 and 1 now**, logged past §3a for the power user (v1), then slice 2; slices 0 to 2 now; slice 0 only; after v1 | spec D12 |
| **Q-428** (answered) | A project already open in another window, until Q-97 is decided | **Answered 2026-11-02, "Bring its window": DL-308.** That window comes forward, so a project is in one window | board 6 · A session open in two windows; board 1 |
| **Q-435** | Window base colours (ENH-319) | **The palette as drawn; a new window takes the next unused colour, with a switch to turn that off; Classic turns colours off**; more or redrawn colours; new windows open plain; window colours make Classic unavailable | boards 4a · A base colour for each window, light and dark, 4b · A new window's colour, and changing it, 4c · Window colours and Classic |
| **Q-429** | What slice 1 includes | **New Window ⌥⌘N and Open in New Window (board 1 A), titles, the system Window menu**; also Pin (board 2); also tints (boards 4 and 5) | board 1 · How a new window opens; board 2; board 4 |
| **Q-430** | Which window `duo2` acts on | **The caller's session's window, else the primary window, never the key window, plus `--window`**; the caller's window, else the key window; always the key window | this doc, section 2 |
| **Q-431** | Home across windows in slice 1 | **All projects in every window, Home live in one, with a "Show Here" stand-in in the others** (Q-98 D10 later adds chat there); All projects only in the first window (other windows are project windows); Home's chat in every window now (D10 A, with F-183's focus check per window) | board 10 · What happens to Home |
| **Q-432** | Closing and relaunching | **Closing a window keeps its projects' tabs and sessions, and relaunch restores the window set and frames (slice 2)**; relaunch with one window; ask on quit | this doc, slice 2 |
| Q-95, Q-96, Q-97, Q-98 | Pin, tints, a session or document in two windows, needs-you, Window menu and Home | unchanged, on the spec page | spec D1 to D11, boards 2 to 10 |

## Records

- **F-537:** the window-state inventory as of 2026-11-02 (counts, the three kinds of state, the refresh loop mixing app and window work).
- **F-538:** v1's multi-window, corrected: a staged build, what broke, and what v2 takes from it.
- **C-146:** `AppModel`'s live loop and its init side effects run once per instance, so a second window would double the disk scans, notifications, archive passes and director pruning. Slice 0 moves them to `AppCore`, with a DuoChecks count.
- **ENH-318:** window sets: save and reopen a named arrangement of windows (Warp's launch configurations), and per-display restore.
- **Q-428 to Q-432:** above.
