# Multi-window Duo: what it would take

Research for Geoff's ask of 2026-10-07: "explore the implications/requirements for multi-window support; design ux studies if needed for visual affordances and decisions". No product code. The UX studies are on the canvas https://claude.ai/artifact/46yWPpDZn16Qtfrfhbuaw1, exported to `docs/design/multi-window-studies/`. Records: DL-141, F-167 to F-169, Q-95 to Q-99, C-43 and C-44, ENH-26 and ENH-27.

## Geoff's direction (DL-141)

On the research round Geoff chose **independent windows (model A below), each optionally pinned to a project and optionally tinted as a whole**, with **New Window on ⌥⌘N**. He asked for a design study of the options, then a spec with tradeoffs and a page to send his decisions from:

- the canvas has eleven boards, ten of them decisions: https://claude.ai/artifact/46yWPpDZn16Qtfrfhbuaw1;
- the spec page has twelve decisions, D1 to D12, and sends Geoff's picks to Claude: https://claude.ai/artifact/GaK5hPxTAxphXEZJSoXaYA (source in `docs/design/multi-window-studies/spec.html`).

The analysis below is the research as first written. Its recommendation (model B) was not taken. Model A's costs are kept down with one rule: **every live view has one home**. A terminal, an editor and a web view are each live in one window, and the other windows show the session in chat mode (F-168), the document read-only, or a stand-in. Pinning and tints are new; the open choices are Q-95 to Q-99.

## Summary

- Duo v2 shipped one window on purpose. DL (`decisions.md:36`) says "Single window for v1, state designed window-aware", from legacy D10. Legacy Duo's multi-window (ENH-191) took three releases and a registry refactor, estimated at 13 to 17 engineer-weeks. Its one lesson that carries over: **resolve every target by identity, never by focus.**
- v2 is less window-aware than the decision hoped. One `AppModel` holds the app-wide data and about 45 properties of one window's UI. There is one shared editor, one HTML viewer and one deck viewer. Each terminal and each web page is a single `NSView` moved between panes. Twenty-four places look up "the window", sixteen of them by `title == "Duo"`. (Details in [What assumes one window](#what-assumes-one-window-today).)
- One model makes most of that easy: **a window per project.** Duo already keeps sessions, open documents, browser tabs and the last console and right tabs per project (`openDocumentsByProject`, `lastConsoleTab`, `lastRightTab`, the restore file's per-project entries). If a project can be open in only one window at a time, no session, terminal, document or browser tab is ever wanted in two windows. Most of the hard problems go away: a stolen terminal view, two editors on one file, a session "visible" twice.
- **Recommendation:** the main window keeps both altitudes, All projects and Home. Extra windows each hold one project. Opening a project that already has a window brings that window forward. (Model B below.)
- **The v1 slice:** Project › Open in New Window, with a context-menu item on tiles and sidebar rows. The window is titled with the project's name. Needs-you shows in every window. The Window menu lists the windows. `duo2 window …`, and every verb resolves its window from the caller's session. The window set is restored on relaunch. Tear-off documents and native tabs come later (ENH-26, ENH-27).
- **Size:** about four build slices. The biggest is splitting `AppModel` into an app model and a window model. That part is worth doing even before any second window exists, because it pays off the identity-not-focus rule.

## What assumes one window today

The single-window state found in the code, with places and counts. File paths are under `Sources/`.

### The window itself
- `MainWindow` (`Duo/DuoApp.swift:178-222`) makes one `NSWindow` by hand in AppKit, because SwiftUI's `Window` scene sometimes launched with no window (F-29, F-30).
  - It sets title `"Duo"` and frame autosave name `"main"`.
  - It sets `isReleasedWhenClosed = false` and `tabbingMode = .disallowed`. `allowsAutomaticWindowTabbing` is off.
- The SwiftUI scene is only `Settings {}` plus the menus.
- The AppDelegate's `reopen`, `openURL` and `flush` all close over that one window and model.

### One model for everything
- `AppModel` (`Model/AppModel.swift`) is created once and captured by the control socket, the menus and Settings.
- Per-window state on it:
  - Navigation: `altitude`, `homeTab`, `consoleTab`, `rightTab`, `selectedFile`, `selectedActionSession`, `selectedSidebarItem`, `focusedTile`, the expanded groups and folders, `mapFilter`, `renamingPath`.
  - Panes: the four pane-collapse flags.
  - Overlays: `peekOpen` and `peekSelection`, `search` (`SearchUI`).
  - Hover and drag state, `webFocus`, `fullScreen`, `projectShown` (the project fade).
- Rough reference counts: `currentProject` 93, `rightTab` 63, `consoleTab` 61, `altitude` 56, `homeTab` 36.

### Finding "the window"
- 24 uses of `NSApp.windows`, `keyWindow` or `mainWindow`; 16 of them match `title == "Duo"`.
  - Undo uses that window's undo manager (`AppModel+Organize.swift:284`). With two windows, undo history would split.
  - `DuoAlert`, the walk, `Shells.swift`'s accessibility announcement, chat perf, and about ten places in `FixtureHarness`.

### Terminals
- One `TerminalSession` per session, for its whole life. It owns one SwiftTerm view and its PTY (`Terminal/Terminals.swift`).
- `TerminalSlot.SlotView.show` moves the view: `removeFromSuperview`, then `addSubview`.
  - If two windows show the same session, the last one to update takes it.
  - The other slot's `current?.removeFromSuperview()` would then pull it out of the first window (C-43).
- **The process is not the problem:** it belongs to the session, not to a window. Only the view does.

### Chat mode
- Chat reads the terminal's buffer offscreen (`attachChat`), and its mode is per session.
- A chat view could be drawn in two windows, because it is SwiftUI over an observable store.
- `ChatKeys` installs one app-wide key monitor. It already resolves the window from the key event's `windowNumber`, but then acts on the model-wide `visibleChat`.

### Documents
- `EditorController` is one lazy instance holding one `url`, `dirty` flag, `conflict` and `kept` text. `DocumentEditorView.updateNSView` calls `editor.open(file)`.
- Two windows on different documents would swap the document on every update. Two windows on one document would need two editors kept in step: CodeMirror state, unsaved typing and Claude's highlights.
- `HTMLViewer` and `DeckViewer` are single instances in the same way.
- The quit flush saves only the one editor.

### Browser tabs
- One `WKWebView` per tab, stored app-wide in `webTabs`, moved between panes like the terminals.
- `browser screenshot` refuses a tab that isn't on screen.

### Focus and "the visible session"
- `visibleSessionId` is one value: `homeTab` or `consoleTab`, by altitude. It drives:
  - the "seen" mark on ready-for-review sessions;
  - which session is never notified;
  - `visibleTerminal`, `visibleChat`, `duo2 session close` with no id, and search focus.
- `DuoFocus.take()` activates the app. It doesn't pick a window.

### Sheets
- `SheetCenter.shared` is one queue, drawn in the window by `SheetOverlay`. With two windows, the same question would show in both.

### Motion
- `PaneMotion` is a global counter, and its notification is posted with a nil object.
- Every terminal slot holds its layout while a slide runs, so a pane sliding in one window would freeze terminal resizing in every window (C-44).
- The width rules of DL-129 are per view and already safe.

### Menus
- `DuoCommands` captures the one model. Nothing uses `FocusedValue` or `focusedSceneValue`.
- Close Window is `NSApp.keyWindow?.performClose`. Full Screen looks for the window titled "Duo".
- **⌘N is New Markdown File and ⇧⌘N is New Folder** (DL-34, DL-108), so the usual New Window chord is taken. ⌥⌘N is free.
- The Window menu is the system's default, with nothing of Duo's.

### Restore
- `RestoreState` (`Model/AppModel+Restore.swift`) is one file per Home. It holds:
  - one on-screen project, the collapse flags and `homeTab`;
  - per project, its sessions, `consoleTab`, documents, `rightTab` and browser tabs.
- It saves no window list and no frames. The frame is kept only by the autosave name `"main"`.
- `state.json` (`DuoState`) is app-wide preferences and stays as is.

### Control socket and `duo2`
- Every request carries `session` (from `DUO_SESSION_ID`) and `cwd`.
- File verbs already prefer the caller's project (`projectFor(cwd:)`, 12 uses) before `currentProject`.
- The verbs that act on "the" window:
  - `status`, `open`, `go`, `peek`, `session open`, every `view …`, `undo`;
  - `doc open/close/tabs/select/save/read/status`;
  - `selection`, `html …`, and `browser …` without `--tab`.
- The help text says "the project on screen" (`DuoControl/Actions.swift:258`).

### Notifications and the Dock badge
- `notifyNeedsYou` is skipped when `NSApp.isActive` or the session is `visibleSessionId`.
- Clicking a notification calls `open(project:)` on the one model.
- The badge is app-level, which is right.

### Test tooling
- `FixtureHarness.configure` sizes one window, runs `--then` actions against the one model, and captures that window.
- `scripts/check-ui.sh` launches one app per state and writes one PNG.
- DuoChecks builds `AppModel` headless about 15 times.

### What already fits

Hook events, the session snapshot, `TerminalStore`, `ChatStore`, `webTabs`, the notifier and badge, and `DuoState` are app-wide, and should stay that way.

The per-project memory already exists: documents, last tabs, and browser tabs per project. Requests already carry the caller's session and cwd. `ChatKeys` already resolves the window from the key event.

## What legacy Duo did

- v0.10.0 shipped "N independent windows, single socket, identity-not-focus" (ENH-191).
  - The review's verdict: "Later. Keep the identity-not-focus rule when it comes." (`legacy-duo-product-review.md:36`)
  - Its lesson 32: "Default resolution is by identity, never by focus (lowest-id primary window…). App-global prefs fan out live to every window."
- Its costs:
  - Focus-based routing silently dropped sends to backgrounded windows.
  - Per-window pin and state rules that the Home study then had to work around.
  - A shared state file that needed serialized writers (lesson 31).
  - Chord clashes, among them New Window on ⇧⌘N (`legacy-duo-product-review.md:235`).
- Restore saved one `WindowState` per window, with its terminals and browser tabs.
- What v2 should take from this:
  - Independent windows let any session appear anywhere, and that cost the most.
  - A rule that gives every object one home window removes most of it.

## The models

Each model below is scored on the same questions:

- What does the user get?
- What changes in the code?
- Which window owns a terminal's view?
- What happens to a session that is open in two windows?
- What is "the visible session"?
- How does `duo2` pick a window?
- How does needs-you reach the user?
- What is restored on relaunch?

### A. Independent windows (legacy's model, and Safari's)

**What users get.** Any number of full Duo windows, each with its own altitude, project and tabs. ⌘-click a project to open it in a new window, and use the second monitor however you like.

**What changes.**
- **State:** everything per window in the list above moves to a `WindowModel`.
- **Terminal views:** one session in two windows is allowed. The view lives in one of them, and the other shows a stand-in, "Showing in another window · Show Here", which moves it. A live mirror needs a second terminal emulator fed from the same PTY. SwiftTerm doesn't do that, and its scrollback and size would disagree.
- **Documents:** the editor becomes one per window. A file open in two editors needs both kept in step: unsaved typing, conflicts, Claude's highlights. That is a new sync layer, so it is the biggest risk here.
- **The visible session** becomes a set, the key window's first.
- **`duo2`** resolves the window holding the caller's session, then the key window. Every "on screen" verb has to say which window it means.
- **Needs-you:** the toolbar chip counts sessions outside the window, and notifications are skipped only for sessions visible in some window.
- **Restore:** a window list, each with its altitude, project, panes and frame.
- **Home:** its one terminal can be in only one window. Going up to All projects in a second window either steals Home's terminal or shows a stand-in.

**Risks.**
- This is exactly what cost legacy three releases.
- Two editors on one file.
- Home's terminal moving back and forth between windows.
- Every `duo2` verb has to be audited.
- The window a verb lands in becomes hard for a Claude session to predict.

**Size:** large, about 6 to 8 build slices. It also needs the document-sync layer.

### B. A window per project (Xcode workspaces, VS Code folders) — recommended

**What users get.**
- The main window works as today, both altitudes, with All projects and Home.
- Any project can open in its own window, with the same three-pane workspace inside.
- Two projects side by side, or one on each monitor.
- Opening a project that already has a window brings that window forward, wherever you opened it from: a map tile, search, a notification, the peek or `duo2 open`.

**What changes.**
- **State:** a `WindowModel` holds the window-level state: altitude (main window only), current project, pane collapse, search, peek, hover and drag, the undo manager and the per-window viewers.
  - Per-project state stays where it is.
  - `AppModel` keeps the data and a list of windows, plus a map `projectWindow[projectId]`.
- **Terminal views:** a session belongs to its project, and its project is in at most one window. So its view has one place to be, and moving views stays as it is. Two cases remain:
  - Home's sessions show only in the main window.
  - A session moved to another project moves to that project's window with it.
- **Documents:** a document belongs to its project in the same way, so it is open in one window at a time. Each window gets its own editor, HTML viewer and deck viewer (a dozen lines in `AppModel`), and the quit flush saves every editor.
  - Not covered: a document outside every project, which opens as a tab in "the project on screen". That becomes the key window's project.
  - Not covered: one file open as a tab in two projects. That is rare; it gets a rule (Q-97).
- **The visible session:** one per window. It counts as visible, for notifications and the seen mark, if it is visible in any window. The key window's session is the one keyboard and search focus go to.
- **`duo2`:** the caller's session gives its project, and the project gives its window (the identity rule). Without a session, the key window, then the main window.
  - `duo2 status` lists the windows.
  - New verbs: `duo2 window list`, `window open <project>`, `window focus <project>`, `window close <project>`.
  - An optional `--window <project|main>` on the verbs that act on what is on screen.
- **Needs-you:** the toolbar chip in each window counts sessions that need you outside that window. The peek's jump brings forward the window that holds the project. Notifications open the project's window. The Window menu marks windows that hold a needs-you session.
- **Restore:** `RestoreState` gains `windows: [{project?, frame, panes}]`. The main window is always first. Per-project state is already there.
- **Home:** stays in the main window. In a project window, ⌘↑ and ⇧⌘H bring the main window forward rather than changing altitude. The breadcrumb's "All projects" does the same.

**Risks.**
- Splitting `AppModel` touches 300 or more references. Doing it in one slice with no behaviour change, proven by the checks, keeps it safe.
- `SheetCenter` has to choose a window. A question about a project goes to that project's window, and anything else goes to the key window.
- `PaneMotion` has to be scoped per window (C-44).
- Fixture captures have to say which window they capture (`--capture-window <n>`).
- A user who wants the same project twice, terminal on one screen and documents on the other, isn't served. That is model D, later.

**Size:** medium, about 4 build slices (below).

### C. A second window as a viewer of the same model

**What users get.** Window › New Viewer shows the same state as the main window: the same project and tabs, a mirror. It is only useful for presenting.

**What changes.** Little state; but each view can be shown only once, so the mirror would show stand-ins for terminals, the editor and browser tabs. It gives nothing over screen mirroring.

**Risks:** it looks like multi-window and isn't. Users would expect independence.

**Size:** small, but not worth building. Ruled out.

### D. Tear-off panes and tabs (Arc's Little Arc, Safari's tab drag-out, VS Code's floating editor)

**What users get.**
- Pull one document, HTML page, deck or browser tab out of the right pane into a small window of its own. For example, the PRD big on the second monitor while the console stays on the laptop.
- Possibly pull a session's console out too.

**What changes.** A torn-off item leaves its project's right pane and lives in an auxiliary window. That window is a single pane with its tab strip, a bar naming its project, and "Put Back". The ownership rule still holds: one item, one place.

**Risks.**
- Aux windows are a second kind of window, which needs its own design.
- Restore has to remember them.
- Torn-off consoles bring back the Home and focus questions.

**Size:** medium on top of B. It shares B's groundwork: per-window viewers and identity routing.

**Fits after B** as ENH-26.

### E. macOS native window tabs (Finder, Terminal, Ghostty)

**What users get.** Window › Merge All Windows, and project windows as tabs in one window's system tab bar, with ⌃Tab between them.

**What changes.** Little beyond B: turn `tabbingMode` back on for project windows, give each a `tabbingIdentifier`, and name the tab with the window title.

**Risks.**
- The system tab bar stacks above Duo's toolbar and own tab strips: three rows of tabs (console tabs, right-pane tabs, window tabs).
- It clashes with DL-21's "one window" altitudes.
- ⌃Tab is likely to collide with terminal use.

**Size:** small on top of B, but it needs a design call. ENH-27.

## Prior art

| App | Model | Worth taking | Worth avoiding |
|---|---|---|---|
| Xcode | A window per workspace. Opening a project that's open brings its window forward. Tabs inside the window, optional native tabs. | One project, one window; "focus, don't duplicate" | Window tabs plus editor tabs plus panes is too many levels |
| VS Code | A window per folder. File › New Window (⇧⌘N). Editors can float in their own windows (since 1.85). | A folder opens in its window, and opening it again focuses it. Floating editors (model D). | Its ⇧⌘N is our New Folder |
| iTerm2 | Independent windows, tabs and split panes. A session can move between windows (drag a tab out), never be in two. | A session lives in one place, and moving it is a drag | Arrangements are hard to find |
| Finder | Native tabs and windows, Merge All Windows | The Window menu's standard items | — |
| Safari | Independent windows and native tabs. Drag a tab out to make a window. Tab groups. | Dragging a tab out is well known | Many windows of the same thing |
| Arc | One main window per space, Little Arc for a link opened from elsewhere, and splits | A small secondary window for one item (model D) | Hidden window semantics |
| Warp | Independent windows with tabs. Launch configurations restore a set of windows. | Restoring a named window set | — |
| Ghostty | Native tabs and windows, quick terminal | Native tabs for terminals feel right *for a terminal app* | Duo isn't one |
| Zed | A window per project. Opening a project folder that's open focuses its window. | The same as Xcode, and newest | — |

The pattern most like Duo is Xcode and Zed: a window belongs to a project, and asking for that project again brings it forward.

## Recommendation (the research's; Geoff chose A, see above)

**Model B, a window per project, with the main window keeping All projects and Home.** It gives the thing people want, two projects side by side or on two screens. It keeps one rule a user can say aloud: *a project is in one window*. And it reuses what Duo already keeps per project. It never puts one session or one document in two places, so there is no stolen terminal and no two-editor sync. Legacy's model A is the one that cost three releases.

### The v1 slice (if Geoff approves)

1. **Split the model** (no visible change). `WindowModel` per window. Per-window viewers. `SheetCenter` and `PaneMotion` scoped to a window. Undo per window. Menus routed with `FocusedValue`. Every `title == "Duo"` lookup replaced with the window that owns the thing. Proven by DuoChecks, every check-ui state unchanged, and a perf check.
2. **Project windows.**
   - Project › Open in New Window, also on the context menus of tiles and sidebar rows, and ⌥⌘N if the chord is approved (DL-34).
   - Opening a project that has a window focuses that window.
   - Closing a project window puts the project back in the main window's reach. Nothing is lost: its sessions keep running and its tabs are remembered as today.
   - Window titles are the project's name. The breadcrumb's "All projects" brings the main window forward.
3. **Needs-you and the Window menu.**
   - Each window's chip counts sessions outside it, and the peek jumps to the right window.
   - Notifications open the project's window.
   - The Window menu lists Duo's windows, with needs-you marked.
4. **`duo2` and restore.**
   - `duo2 window list|open|focus|close`, and `status` lists the windows.
   - Every on-screen verb resolves its window by the caller's session, then the key window, and takes `--window`.
   - Restore keeps the window list and frames.
   - The harness gets `--capture-window <n>` and a `window-open:<project>` action. check-ui gains two multi-window states.

Each slice ends with a capture. The parts that show (the Window menu, the chip, the title, a project window) are built to the approved boards in `docs/design/multi-window-studies/`.

### Not in v1
- Tearing off documents and browser tabs (D, ENH-26).
- Native window tabs (E, ENH-27).
- The same project in two windows.
- Dragging a tile out of the window to open it (the board shows it as an option; it needs a drag session leaving the window, which AppKit gives, but it's polish).

## Records
- **DL-141:** Geoff's direction: independent windows, pinnable, tinted; New Window ⌥⌘N.
- **F-167:** Duo's single-window assumptions, with counts (this doc's "What assumes one window").
- **F-168:** chat mode types through the session's terminal view, wherever that view is drawn, so a second window can answer a session in chat mode.
- **F-169:** on a full tint, text2 keeps AA but the needs-you orange doesn't; the chip gets a white fill.
- **Q-95 to Q-99:** the spec's decisions: opening and pinning, tints, one session or document in two windows, needs-you, the Window menu and Home, and when to build.
- **C-43:** a terminal slot losing its view to another window removes it from that window.
- **C-44:** `PaneMotion` is global, so a pane slide in one window freezes terminal layout in all.
- **ENH-26:** later parts: one document editable in two windows, and dragging a tile or tab out into a window.
- **ENH-27:** native window tabs for project windows.
