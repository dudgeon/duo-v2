# Split view: what Duo v2 has today, and what a split must respect

Read-only study of the work tree `.claude/worktrees/split-view` (branch research/split-view at e54ae738), plus the duo-decks work tree. Paths are relative to the repo root unless absolute. "As read" means it comes from reading the code; nothing was built or run.

---

## 1. Pane architecture today

**The decision on record.** DL-11 (`docs/design/decisions.md:21`): "Doc beside doc: **Tabs in the right pane for v1; side-by-side later.** … One document visible at a time in v1." Build plan §3a lists "side-by-side documents (DL-11)" under **v1.2 and later** (`docs/plan/build-plan.md:262`), and the CLAUDE.md rule says not to pull it into v1 without logging why. LR §4 item 11 (`docs/design/legacy-requirements.md:182`) is the origin: "Doc beside doc (legacy Split View): is a single right-pane document enough for v1? [P Q9]". `openDocument` still cites the rule: "one visible at a time, DL-11" (`Sources/DuoKit/Model/AppModel+Files.swift:83`).

**Types**
- `PaneSplit` (`Sources/DuoKit/Shell/PaneSplit.swift:10`) is an `NSViewRepresentable` over `DuoSplitView: NSSplitView` (`:179`).
  - `Pane` has `view`, `width` (nil means the flexible pane), `minWidth`, `collapsible` and `collapsed` (`:11-18`).
  - Dividers are 1 pt (`dividerThickness`, `:193`), painted in token colours by `drawDivider` (`:235-256`).
  - It has an optional `cover` (the task board laid over every pane but the last, `:29-32`, `:258-266`; F-219), a `liveColors` watcher (`:26-28`) and `onActivePane` (`:33-35`).
- It is built for exactly three side-by-side panes with one flexible pane.
  - The resize rule is `PaneWidths.resized` (`:372-385`): "side panes keep `current`, the `flex` pane takes the rest; under its minimum the last pane gives way first, then the first".
  - Collapse slides over `motion.paneToggle` (200 ms) with `PaneMotion` (`:309-348`, `:389-399`; F-130).

**The layout tree** (`Sources/DuoKit/Shell/RootView.swift`)
- `RootView` keeps **both altitudes alive** in a ZStack: `AllProjectsLayout` and `ProjectLayout` (`:11-23`).
- Each is its own `PaneSplit`:
  - All projects is Home | map/list | action column (`:48-66`).
  - A project is `ProjectSidebarPane` | `ConsolePane` | `RightPane` (`:87-105`), with the task board as the cover (`:98`).
- Each pane's view is wrapped in `.paneFocusRule(...)`.
- **F-208 rule** (`docs/plan/findings.md:2600-2618`; scan F-212 `:2645`):
  - `PaneSplit.updateNSView` must never set a pane's `rootView`. Pane views are set once in `makeNSView` (`PaneSplit.swift:64-72`).
  - A pane's view must capture nothing that changes; wrap such state in its own view (`DimmedUnderSheet`, `RootView.swift:71-82`).
  - DuoChecks fails if `RootView`, `AllProjectsLayout` or `ProjectLayout` reads chat or terminal state. C-84 (`concerns:248`) notes these guards scan fixed file paths.
- F-157/F-158: `sizeThatFits` returns the proposal. Without it, SwiftUI's Auto Layout walks every view (`PaneSplit.swift:91-95`; findings `:2045-2049`).

**Widths** (`docs/design/build-handoff/tokens.json:625-646`; DL-129 `decisions.md:265`)

| | Left | Middle | Right |
|---|---|---|---|
| Project, design (1440) | 300 | flex | 460 |
| Project, 1280×800 | 300 | 520 | 460 |
| All projects, 1440 | 340 | 600 (flex) | 340 |
| All projects, 1280 | 340 | 600 | 340 |
| Minimums | sessionsAndFiles 240, home 280 | console 480, map 440 | right 360, actionColumn 300 |

- Minimum window 1280×800 (`tokens.json:595`).
- **Narrow rule (DL-129 (2), F-129):** side panes hold their width and the middle takes the change. Under the middle's minimum the right pane gives way first, down to 360, then the left. A PTY is never below 8×1 (LR-14).
- **What that leaves the right pane** (my arithmetic from the delegate's constraints, `PaneSplit.swift:143-155`):
  - at 1440 with the sidebar shown: at most about 1440 − 300 − 480 − 2 ≈ **658**;
  - with the sidebar hidden: about **958**;
  - at 1280: about **498**.
  - So a split *inside* the right pane gets two halves of 180–330 pt at the usual sizes. That is under the right pane's own 360 minimum and under decks' "about 360" readability floor (decks R7).
- A pane's width is remembered **in memory only** while hidden (`savedWidths`, `PaneSplit.swift:188`, `:350-368`). Restore saves collapse flags, not widths (see §5).
- **F-9** (`findings.md:50-54`): a collapsed NSSplitView subview keeps its old frame. Collapse before first layout is deferred (`pendingCollapse`, `PaneSplit.swift:189-191`, `:268-277`), and dividers are found by walking visible widths (`:235-244`).
- F-128: the harness's `right-width:` must pick the split of the altitude on screen (`paneSplits`), because both altitudes are alive (`findings.md:1649-1653`). A nested split would add a third and fourth `NSSplitView` for such lookups to confuse.
- **Toolbar right-pane button:** ⌥⌘0, `duo2 view right show|hide|toggle` (DL-129 (1)). Opening a document into a hidden right pane shows it (`AppModel+Files.swift:86`).

## 2. Right pane tabs

**Model** (`Sources/DuoKit/Model/AppModel.swift`)
- `rightTab: String?`: "Project", a group name, or a document path (`:118`). There is **one selected tab per project view**.
- `openDocumentsByProject: [String: [String]]` (`:169`); `openDocuments` is the current project's list (`AppModel+Files.swift:31-35`).
- `lastRightTab` (`:194`), `selectedFile` (`:165`), `webTabs: [String: WebTab]` (`:236`), `readOnlySession` (`:123`).
- **A tab's identity is its string key.** Kinds:
  - `"Project"` (the project file, DL-60);
  - a group name;
  - a project-relative path;
  - `file:<abs>` for an outside file (DL-106);
  - `web:…` for browser tabs;
  - `ReadOnlySession.tabKey`.
- Keys are unique, so a file can be open in **one tab only**. `openDocument` appends the key only if it isn't already there (`AppModel+Files.swift:84-101`).

**Order and strip**
- `rightTabItems()` (`AppModel+Panes.swift:119-137`) is the one source of the strip's order: Project, the selected group, documents in order, the read-only session. ⌃Tab uses it (F-257).
- The strip is `ScrollingTabStrip` (DL-225, built F-354; `ProjectPanes.swift:819-858`). Project and a group page are pinned at the left; the rest scroll.
- Tab hover × and fill: DL-126, DL-134. Drag and Move Tab Left/Right: DL-220. Closing selects the left neighbour (`PopupPlacement.after`, `AppModel+Files.swift:133`).

**How a tab hosts a viewer.** One big `if/else` on `rightTab` in `RightPane.body` (`Sources/DuoKit/Project/ProjectPanes.swift:870-922`):
- browser tab: `BrowserTabView(tab:)` + `PickerBar`;
- read-only session: `ReadOnlySessionView`;
- `.html`/`.htm`: `HTMLViewerView(viewer: model.htmlViewer, …)` + `PickerBar`, and `.onDisappear { htmlViewer.sleep() }`;
- deck (pptx): `DeckView(viewer: model.deckViewer, …)`;
- Word: `DocxView(viewer: model.docxViewer, …)`;
- binary: `BinaryFileView` (Quick Look; C-26);
- any other dotted path: `DocumentStateBar` → `TemplateBar` → `MarkdownReviewSlot` → `DocumentEditorView(editor: model.editor, …)`;
- Project: the same stack for the project file;
- otherwise `DocumentPlaceholder` / `FolderProjectTab`.

**The singleton viewers (the central constraint)**
- `AppModel` holds **one** of each, lazily created:
  - `editor` (`AppModel.swift:216`, "The one document editor");
  - `htmlViewer` (`:218`);
  - `deckViewer` (`:221`);
  - `docxViewer` (`:224`).
- Each owns one `WKWebView` (or `DuoWebView`) and one `url`.
- The editor's view is **re-parented**: `DocumentEditorView.updateNSView` calls `host.show(editor.webView)` and then `editor.open(file)` (`Sources/DuoKit/Editor/DocumentEditor.swift:892-920`). `EditorHost.show` removes the web view from wherever it was.
- So two `DocumentEditorView`s on screen would steal one web view from each other and flip `editor.url` on every update. The research says it plainly: "Two windows on different documents would swap the document on every update" (`docs/research/multi-window.md:60-64`; F-167 `findings.md:2199-2217`).
- Browser tabs: one web view per tab (`webTabs`), which is likewise single-homed.
- Terminals: one view per session, moved by `TerminalSlot`. C-43 (`concerns:215`): "A terminal view drawn in two windows is taken by the last one."

**Kinds today, and what each reads from**

| Viewer | Reads from | Edits |
|---|---|---|
| Markdown/text | CodeMirror 6 live preview (DL-167) in one page that keeps per-document state by `docID` (`DocumentEditor.swift:384-398`; `duo.show(id, …)`) | Yes |
| HTML (`Editor/HTMLViewer.swift`) | Disk, polling once a second (`startWatching`, ~`:83-96`); `sleep()`/`wake()` | Read-only (DL-67, v1). No HTML source view exists: a `.html` always routes to the viewer (`ProjectPanes.swift:880`), and only `@codemirror/lang-markdown` is vendored (`Vendor/codemirror/package.json`) |
| Deck (pptx) (`Editor/DeckViewer.swift`) | The file on disk via the `duo-deck:` scheme, reloaded when its mtime changes (1 s timer, `:138-160`) | Read-only (DL-121, DL-125). There is no in-memory bytes path today, which decks' R1 needs |
| Word (`Editor/DocxViewer.swift`) | The file | Read-only (DL-162) |

- **Source mode** (DL-167 Q3) is **per document**, not per view: `sourceDocuments: Set<String>` (`AppModel.swift:184`; `AppModel+Source.swift:1-22`; View › Source Mode `Commands.swift:409`; `duo2 doc mode`). So "the same Markdown file as source on one side and preview on the other" can't be expressed with today's state.
- **F-120** (`findings.md:1529-1545`): a covered window's web views capture blank.
  - `WindowCapture.withWebSnapshots` (`Sources/DuoKit/Debug/WindowCapture.swift:36`) snapshots *every* web view showing in the window with `takeSnapshot` and lays each over its view while the capture runs. It uses `visibleRect ∩ bounds`, because WKWebView's `visibleRect` reaches 37 pt under the toolbar.
  - It already enumerates every web view, so two side-by-side web views should be covered. Each half's rect intersection must still be right.
  - CLAUDE.md: for pixel-exact editor work, also check in a browser page at the pane's width. A split changes that width.

## 3. Active pane, focus, and command routing

**DL-165** (`decisions.md:355`; provisional, Q-165/Q-166; `pane-focus-handoff/`)
- A 2 pt rule over the top of the active pane (`border.paneFocusRule`, `PaneFocusRule`, `Sources/DuoKit/Shell/PaneFocus.swift:4-32`).
- ⌥⌘→/⌥⌘← cycle left → middle → right.
- ⌃Tab/⌃⇧Tab step the **active pane's** tabs in drawn order. A local key monitor takes them even in terminals (`PaneFocus.swift:36-83`; F-256).
- `duo2 view pane …`, `view tab next|previous`.
- The model:
  - `DuoPane { left, middle, right }` (`AppModel+Panes.swift:8-10`);
  - `activePaneProject` / `activePaneAllProjects` (`AppModel.swift:206-207`);
  - set from `DuoSplitView`'s click monitor and its `firstResponder` KVO (`PaneSplit.swift:200-233`; F-257 `findings.md:2945`).
- `focusPane(.right)` gives the keyboard to the first visible of `[visibleWebTab, editor, htmlViewer]` web views (`AppModel+Panes.swift:100-108`).
- **There's no notion of a sub-pane.** Any responder inside `RightPane` reports index 2. A split needs a second level ("which side of the right pane") for ⌃Tab, focus, the rule and status.

**webFocus**
- `webFocus: WebFocus { none, editor, html }` (`AppModel.swift:242-243`) is set by each singleton's `onFocusChange` (`AppModel+Send.swift:249-252`, `:268-272`; browser `BrowserTabs.swift:533`).
- It's binary per kind. Two editors (or editor plus HTML) would both write it.

**⌘W, Close Tab** (`Navigation/Commands.swift:149`, enable `:183`, perform `:252-254`)
- Enabled when `visibleTerminal != nil || (webFocus == .editor && openDocuments.contains(rightTab))`.
- Performs `closeDocument(rightTab)` if `editor.hasFocus`, **else `closeVisibleSession()`**.
- As read: with an HTML page, deck, Word document or browser tab focused, ⌘W ends the console's session. It asks first only if the session is busy (`AppModel.swift:704-707`; `AppModel+CloseTab.swift`).
- LR-60 says "⌘W closes a tab, never the window" (`legacy-requirements.md:139`). In a split, ⌘W must close the focused side's tab (or the split) and never fall through to the console.

**⌘S Save** (`:145`, enable `:185`, perform `:257`): `model.editor.saveNow()`, the one editor only.

**⌘D Send Selection to Claude** (DL-79, `decisions.md:136`; `Commands.swift:153`, `:270`)
- `sendSelection` picks the editor if `webFocus == .editor || editor.hasFocus`, else HTML if `webFocus == .html` (`AppModel+Send.swift:345-352`).
- It goes to `visibleSessionId`, the console's tab (`AppModel.swift:481-486`).

**⌘F Find**
- `TextEditingCommands()` (`Commands.swift:375`): the system Find items go down the responder chain.
- `EditorWebView` maps `performTextFinderAction:`/`performFindPanelAction:` to CodeMirror's search (`DocumentEditor.swift:862-889`; F-43). The session list takes ⌘F for its filter (`SessionListFilter.swift:139`).
- Responder-routed, so it follows whichever side has focus, provided each side is its own responder.

**Format items and table items**
- Enabled on `webFocus == .editor`; performed with `model.editor.run("duo.exec(f)…")` (`Commands.swift:186-188`, `:258-261`).
- They always target the singleton editor.

**Voice** (DL-260/261/264/271)
- ⇧⌘D (`Commands.swift:154`, `:291`, `:381-384`).
- `VoiceTarget` is `chat(key) | terminal(key)` only (`Sources/DuoKit/Voice/VoiceInput.swift:8-12`). `voiceFocusTarget` resolves from `visibleSessionId` (`AppModel+Voice.swift:9-15`).
- Voice into a document is **designed, not built** (DL-266 (6), `markdown-toolbar-handoff/dictation.html`): "⇧⌘D goes to the document once it has the keyboard", plus `duo2 voice start --doc`.

**The formatting bar** (DL-266, `decisions.md:460`; `markdown-toolbar-handoff/README.md`)
- **Designed, not built** (no `formatBar` in Sources; surfaces.md:66 "Designed, not built"; "Build after 0.2.22").
- 24 high (`formatBarHeight`, a new token, not in tokens.json yet).
- Shown only "while `webFocus == .editor` on a Markdown document", while its menus are open or a dictation runs. Not on read-only files, a template's preview or **Source mode** (DL-266 (3); handoff `:26-27`).
- Laid over the editor (top padding 22 → 24, a 24 scroll margin, handoff `:31-33`); "The review bar (DL-237) keeps its place in the pane's stack, above" (`:34`).
- Under 420, the table controls Align and Delete fold into ⋯ (`:36`).
- Decks R8 wants it over the source column only.

**The Review bar** (DL-237, `decisions.md:434`; `markdown-review-handoff/README.md`)
- 44 high under the tabs (`:11`).
- The margin geometry is drawn at a 460 pane: text 228, margin 180 (`:23`). "Under 420 … the margin folds to a 24 gutter … a thread opens as a 280 popover" (`:48-50`).
- It sits in the stack `DocumentStateBar → TemplateBar → MarkdownReviewSlot → editor` (`ProjectPanes.swift:896-903`; `Project/MarkdownReviewBar.swift:66`).
- A split side at 230–330 is always in the narrow cut.

**Bars on other viewers**
- Deck bar 44 (`size.deckBarHeight`, `tokens.json:606`); DL-125 (A): ‹ › Slide n of N, Select Shape, Open With.
- The picker bar is at the bottom (`PickerBar`, `ProjectPanes.swift:1217`).
- It reads `model.sendTarget`, `visiblePage` and `htmlViewer`, which are singletons (`BrowserTabs.swift:506-512`).

## 4. Documents: one buffer per file, the same file twice, disk reconciliation

**One editor, one document on screen** (`Sources/DuoKit/Editor/DocumentEditor.swift`)
- `EditorController` (`:38`) holds one `url`, `phase` (closed/opening/open/conflict/removed, `:53-62`), `generation` (`:64`), `dirty`, `diskBytes`, **one file watcher plus one folder watcher** (`watch`, `:597-618`), `kept` (`:110-112`), `conflictLines`, `readOnlyReason`, `previewing`.
- `open(file)` saves or keeps the leaving document, then shows the next (`:211-253`). Switching mid-merge is queued: `switchingTo`, BUG-085.
- The page keeps undo, caret and scroll per document id (DL-167 step 3). Only **the shown document is watched and reconciled**; the others are loaded from disk when shown again.
- **A buffer per file, effectively.** The JS page has one EditorState per doc id, and Swift tracks only the one on screen.

**Disk reconciliation** (DL-77; LR-31, LR-32, LR-35, LR-36 `legacy-requirements.md:95-100`)
- Watchers settle 150 ms (`diskChanged`, `:620-649`).
- `reconcile` merges three-way in the page (`duo.external`), or marks a conflict: snapshots to `FileHistory`, `phase = .conflict`, autosave paused (`:703-744`).
- Renames are followed by `F_GETPATH` (`:629-641`). Removal sets `phase = .removed` and keeps the buffer.
- Saves are atomic and only when changed, merging a pending outside write first (`saveNow`, `:523-591`).
- **LR-31**: "One reconciliation primitive for every file surface (editor, HTML view, task index)" (`legacy-requirements.md:95`).

**`duo2 doc status`** (LR-34) answers for the single `url` only: "not open in Duo" otherwise (`status(of:)`, `:778-791`). Claude is told to write through `duo2 doc edit` while the user has the file open.

**The same file in two places today**
- Can't happen: tab keys are unique and there's one editor.
- If two editors were introduced, each would have its own `diskBytes`, watcher and dirty state. Each would see the other's save as an outside change. Two buffers would diverge, and the conflict or merge machinery would fire on itself.
- The multi-window research rated this "the biggest risk here … a new sync layer" (`multi-window.md:158`).
- Its rule for multi-window is "**every live view has one home** … the document read-only" elsewhere (`multi-window.md:12`; Q-97 D7: "read-only where it isn't being edited, with Edit Here (recommended), editable in both and kept in step (ENH-26)", `concerns:85`; ENH-26 (a), `enhancements.md:27`).
- For source plus preview of one file, decks R1 asks for **one buffer, two views**: "The preview renders from the editor's buffer, unsaved edits included, never from disk alone." Today's HTML and deck viewers read disk, a second or more late.

**Closing a tab** saves, then `closeFile()` (the shown doc) or `forget(u)` (a hidden doc's page state) (`AppModel+Files.swift:121-139`; F-52, BUG-098).

**Renames and moves** rewrite `openDocumentsByProject` and `lastRightTab` keys in several places: `AppModel+TaskMenu.swift:77-78`, `AppModel+Control.swift:1124`, `AppModel+DuoFilesMove.swift:21`, and the editor's `onRenamed` (`AppModel+Send.swift:~240`). Any split state keyed by path needs the same follow.

## 5. Persistence

- DL-107 (`decisions.md:179`): coming back to a project restores the console's tabs and the right pane's tabs, with the same tab selected.
- **Where.** Not in the project's files. It's in the support folder: `restore-<hash of Home>.json` (`RestoreState.file(root:)`, `Sources/DuoKit/Model/AppModel+Restore.swift:44-48`). That fits DL-53's machine state, and Obsidian/OKF compatibility (memory) argues against putting view state in project files.
- `RestoreState` (`:8-42`): `leftCollapsed…`, `rightCollapsed…`, `homeTab`, and per project `folder`, `sessions`, `consoleTab`, `documents`, `rightTab`, `webTabs` (address by `web:` key), `tabOrder`. Version 1.
- **No pane widths** are saved (`savedWidths` is in memory, `PaneSplit.swift:188`). A divider position for the split (decks R10, "the divider where the user left it, as panes do today") is new: panes don't persist widths today.
- `currentRestoreState` and `applyRestore` (`:57-162`) gather documents per project from `openDocumentsByProject` and keep `rightTab` only if it is "Project" or among the documents (`:134`, `:154`). A split stored as a pair would need the same validation.
- Also remembered app-wide in `DuoState`: `sourceDocuments` (`HookEvents.swift:246-247`), folded properties, `reviewDeliveries`; `markdownMarkup` is in memory per file (`AppModel.swift:258`).

## 6. duo2 parity (DL-71)

- **Rule.** `decisions.md:113`: "everything a person can do in Duo, Claude can do with `duo2`. A check fails when a user action has no verb." CLAUDE.md: a new button or menu item names a verb in `Sources/DuoControl/Actions.swift`, or is listed in `Parity.uiOnly` with why. Then regenerate `docs/cli/duo2.md`.
- **Registry.**
  - `ActionFamily` (`Actions.swift:9-29`): view, docs, review, html, slides, send…
  - `ActionID` raw values are the CLI verbs (`:32-…`).
  - Each `DuoAction` is `.init(id, family, args, help, ui: [labels], everyday:)`. Examples:
    - `viewRight` `:166`;
    - `viewTab` `:167-168` ("<Project | document path | group | next | previous>");
    - `viewTabMove` `:169`;
    - `viewPane` `:172` ("next|previous|left|middle|right");
    - `docOpen` `:347`, `docClose` `:348`, `docTabs` `:349` ("The open document tabs, and which one shows");
    - `docMode` `:363-365`;
    - slides `:460-467`.
- **`Parity.uiOnly`** (`:526-569`) maps a label to its reason. Stale entry: "Toggle Right Pane": "not built yet" (`:538`), though `viewRight`'s `ui` lists it.
- **The check** (`Sources/DuoChecks/main.swift:3083-3111`, asserted at `:1567`):
  - every `DuoCommand` title must be in some action's `ui` or in `uiOnly`;
  - every `Button("…")`, `Menu("…")`, `ActionMenuItem("…")` label in `Sources/DuoKit` (Debug excluded) must be known;
  - every `.onActivate {`, `.onDrag`, `.onDrop(` line must carry `// action: <verb>` (resolved against the registry) or `// not an action:`.
  - Right-pane examples: `// action: view tab` and `// action: doc close` (`ProjectPanes.swift:825`, `:955`, `:982`).
- **Singular-view assumptions in the verbs.**
  - `doc read` defaults to "the showing document" (`:351`).
  - `doc tabs` names "which one shows".
  - `slide` is "The deck showing and the slide on screen".
  - `doc screenshot` captures a Markdown preview "only while it is showing" (`:380`; ENH-289 wants an off-screen second editor, `enhancements.md:86`).
  - `duo2 status` names the active pane (DL-165 (4)).
  - A split makes "the showing document" ambiguous. Every such verb needs a side or "both".
- **The decks proposal** (R9): `duo2 split <file>`, `duo2 split` (status), `duo2 split close`; the deck verbs are Duo Decks' own.
- **A ready hook in search.** The Tab menus for files and sessions already carry a disabled **"Open in split view ⌥⌘↩"** (`Sources/DuoKit/Search/SearchModel.swift:148`, `:169`; perform is `break  // split view isn't built (search-handoff §9)`, `AppModel+Search.swift:479-480`). The chord was accepted in DL-79 (e) ("`⌥⌘↩` split view"; Q-23 `concerns:34`). "Split view itself" is listed under search-handoff §9 "Not designed" (`docs/design/search-handoff/README.md:164`). It applies to **sessions** too (a read-only or live session beside a document?), not only files.

## 7. Multi-window

- **DL-141** (`decisions.md:298`): "Independent windows; each can be pinned to a specific project … New Window is ⌥⌘N". Its decisions are open: Q-95 to Q-99 (`concerns:83-87`). Studies are in `docs/design/multi-window-studies/` ("**in study. Nothing here is approved to build**", README `:3`). Multi-window is deferred past v1 (build plan §3a, `:262`).
- **Not built.** `Sources/Duo/DuoApp.swift` makes one `MainWindow` (`:100`).
- **F-167** (`findings.md:2199-2217`): one `AppModel` holds ~45 window-state properties (`rightTab` 63 references, `consoleTab` 61, …). It also has one editor, HTML viewer and deck viewer, 24 "the window" lookups (16 by `title == "Duo"`; e.g. `paneWindow`, `AppModel+Panes.swift:84`; `PaneFocus.swift:47`, `:62`, `:76`), and global singletons (`SheetCenter.shared`, `PaneMotion` C-44, `visibleSessionId`, menus capturing one model with no `FocusedValue`).
- **Overlap with split view.** Both need **per-view instances** of the editor and viewers, and a rule for one file in two views.
  - Q-97 D7 (`concerns:85`) is the same question one level up: read-only plus Edit Here, or kept in step.
  - ENH-26 (a): "one document editable in two windows at once, kept in step keystroke by keystroke with Claude's highlights in both" (`enhancements.md:27`).
  - Whatever split view chooses for "same file twice" sets the precedent for D7, or should follow Geoff's pick there.
  - Q-99's "slice 1" (split `AppModel` into app and window models) also reduces the singleton problem for split view.
- C-43/C-44 (`concerns:215-216`): a single-homed view and global `PaneMotion` also bite a nested split that slides.

## 8. Approved visuals relevant to a split

- **Precedence** (CLAUDE.md): DL > approved screens > design system > handoff prose. Nothing for split view is drawn. Search-handoff §9 lists it as not designed, so per "Never invent a design" a split needs a canvas round first (DL-26, `decisions.md:56`).
- **Dividers.** 1 pt in `rule` between light panes and in `consoleRule` beside the console. A pane's border is inside its width (F-5, `findings.md:30-33`; F-10 content-box heights). There's no visible handle or grip: DL-129 rejected "C: a handle on the divider" (`decisions.md:265`).
- **Right pane's tab strip** (PaneTabs README; `docs/design/system/components/PaneTabs/README.md`):
  - 36 high on `pane` (`size.tabStripHeight`), with a 1 `rule` under it (`ProjectPanes.swift:868`).
  - 20 horizontal padding (`:865`).
  - Tabs `gapPaneTabs` 24 apart (DL-134), in `body`, the selected one in `bodyEmphasis`.
  - The hover × is 16 (radius 4); the hover fill is radius 5, 24 high, on `ground`.
  - Project and a group page are pinned. The strip scrolls with 24 fades (`size.tabFade`), a 32 peek (`size.tabPeek`) and an `n ⌄` all-tabs menu (DL-225, `tabs-handoff/screens/right-pane.html`, which includes "the narrowest pane").
  - `+` makes a Markdown file; right-click `+` gives New Markdown File and New Browser Tab.
- **Active-pane rule.** 2 pt `paneFocus` (`text`) on light, `consoleText` on the console, over the strip's top; nothing moves (`tokens.json:583-588`; DL-165). The design system's light set only is approved (DB-29).
- **Bars under the tabs:**
  - DocumentStateBar notices (`slice3/editor-notices.html`);
  - TemplateBar (DL-146);
  - Review bar 44 (DL-237);
  - Deck bar 44 (DL-125, wraps when narrow, F-121);
  - Word bar (DL-162, `docxMenu*` tokens);
  - Browser bar (DL-129: "at a 360 right pane the browser bar's address truncates and the zoom % stays");
  - Formatting bar 24 (DL-266, overlay, not built).
- **Motion.** A pane hiding or showing animates its width over `motion.paneToggle` (0.2 s, inOut, `tokens.json:1332`, `:1365`); the terminal is resized once at the end. Tabs fade and slide (DL-130). Reduce Motion makes all of it instant.
- **Appearance.** Dark is DL-224 and Classic is DL-252. HTML pages, Word documents and decks keep their author's colours in dark (Q-222/DL-224; `HTMLViewer` sets `.aqua`).
- **Status in the design system** (`docs/design/system/surfaces.md`):
  - right pane documents and tabs: `:53`, `:62-66`;
  - deck: `:74`;
  - HTML page: still a **stand-in**, DL-70 (`:75`);
  - browser: stand-in (`:76`);
  - formatting bar: designed, not built (`:66`).
- **Handoff statuses** (`docs/design/README.md`):
  - narrow: target, built (`:44`);
  - pane-focus: provisional (`:78`);
  - tabs: target (`:53`);
  - markdown-review: target (`:42`);
  - markdown-toolbar: target, not built (`:51`);
  - pptx: target, built (`:43`);
  - multi-window: study only.

## 9. Duo Decks' current plans (research/duo-decks, `/Users/geoff/repos/duo-v2/.claude/worktrees/duo-decks`)

- **Task.** `/Users/geoff/repos/duo-v2/tasks/duo-decks.md`. Geoff, 2026-10-31: decks as Markdown from templates, a rendered viewer, pptx export. The latest progress line says "Viewer Q-350 waits for split view; the rest goes ahead".
- **The split view task.** `/Users/geoff/repos/duo-v2/tasks/split-view.md`. Records reserved: F-474..F-480, Q-362..Q-369, C-135..C-137, ENH-301..ENH-303, DL-275..DL-278.
- **The study.** `docs/design/duo-decks-study/` (README; `plan.md`; canvas https://claude.ai/artifact/Sk28K1tkHgwk6gHs7RFGqQ, board 8 = the viewer options; page https://claude.ai/artifact/7H6wxTs26LW1DvAfSZCsyi). All [P]; nothing is built or decided.
- **The viewer** (`plan.md:112`): a `type: deck` Markdown file gets a Slides view. The writer's pptx is drawn by the existing pptx-renderer (DL-121/125), so "what you see is the export". "Source and slides sit side by side."
- **Q-350 → DL-269** (`plan.md:336-343`): the board 8 split variants.
  - **S1** source and slides as the two sides of a split in the right pane [recommended, pending split-view's framing];
  - **S2** slides in a pane of their own beside the right pane;
  - **S3** stacked, slides over source, for narrow widths;
  - **F** no split: a Source/Slides toggle in one tab;
  - **F′** interim: export, then open the pptx in today's viewer.
- **Phases** (`plan.md:226-236`): P0–P2 now (parser, checker, writer, `duo2 deck templates|check|export|render`, the skill, extraction). P3, the viewer, comes after split view. "The P1 writer and parser expose the anchor map (slide and slot → source lines) from the start."
- **Requirements sent to split view.** `docs/design/duo-decks-study/split-view-requirements.md` (commit a7199013):
  - **R1** one file, two views, one buffer; the preview renders from the buffer, not disk. Doc-beside-doc should fall out of the same mechanism.
  - **R2** live re-render ~250 ms after typing pauses (writer plus renderer 20–40 ms for 30 slides), keeping scroll and not flashing; rendering never writes a file.
  - **R3** two-way sync (caret → slide; click on a slide → caret on its slot), optional scroll-follow, off by default, with no echo loops.
  - **R4** selection, ⌘D and comments in the source; quiet comment marks on slides; Select Shape resolves to the slot.
  - **R5** problems mark source lines and show under their slide.
  - **R6** export state and Export ⌄ in the preview's own bar.
  - **R7** under about 360 pt slides are hard to read; split view decides how to fold (toggle or stacked).
  - **R8** the formatting bar and mic are on the source side only; the preview has its own bar (‹ › Slide n of N, problems, Select Shape, Export ⌄); dictation goes into the source.
  - **R9** duo2: `split <file>`, `split`, `split close`; deck verbs are Decks' own.
  - **R10** a file in split reopens in split, with the same sides and the divider where it was left.
  - A proposed `SourcePreview` protocol: `canPreview`, `render(text, revision)`, `reveal(anchor, reason)`, `onAnchorMap`, `onActivate`, `onCurrent`, `onProblems`.
  - Ownership: the provider owns the anchor map; split view owns the policy (follow, debounce, loops, panes, divider, folding, persistence, `duo2 split`); the editor owns the source side (caret and visible-range events, reveal, marks).
  - Asks back: does the shape work; what split view provides; the narrow threshold and folding; and whether "same file, two views" is in the first build.

## 10. Constraints and risks for a split

1. **Scope and records.** DL-11 says side-by-side comes later, and build plan §3a puts it in v1.2+. Building it now needs a logged reason (CLAUDE.md "v1 scope") and a DL from Geoff (DL-275..278 reserved). The search action "Open in split view ⌥⌘↩" (DL-79 e) is the existing entry point and chord.
2. **Design first.** Nothing is drawn (search-handoff §9). Every visible mark needs a Design canvas with the Duo design system, [P] marks, Geoff's approval, then export to `docs/design/<slice>-handoff/` (CLAUDE.md, DL-26). DL-129 already rejected a visible divider handle as the right-pane toggle.
3. **Singleton viewers.** There is one `EditorController`, one `HTMLViewer`, one `DeckViewer` and one `DocxViewer`, each with one web view that is re-parented on update (`AppModel.swift:216-225`; `DocumentEditor.swift:892-920`). Two of a kind on screen needs per-view instances.
   - Every caller of `model.editor` / `editorIfLoaded` (menus, format items, Save, `duo2 doc *`, the review bar, `DocumentStateBar`, Source mode, the quit flush) must learn which one.
   - Either an "active editor" or an editor per side. This is the same refactor multi-window's slice 1 needs (F-167, Q-99).
4. **The same file twice.** Two independent buffers would treat each other's saves as outside changes and run DL-77's merge/conflict against themselves; `doc status` would answer for one. Options:
   - (a) one buffer with two views: CodeMirror can show two `EditorView`s on one state, inside the one editor page, so the split could live inside the existing web view;
   - (b) one editable view and one read-only one (Q-97 D7's recommendation for windows);
   - (c) disallow it.
   - Decks need (a) or (b) at least for source plus a *different viewer* (slides), where the viewer must render from the buffer, not disk (R1).
5. **Source mode is per document** (`sourceDocuments`). Markdown source beside its own preview needs per-view mode. DL-266 also hides the formatting bar in Source mode; decks' source side is the normal live-preview editor, so the bar shows there.
6. **Viewers read disk.** HTML and deck viewers poll mtime once a second (`HTMLViewer.startWatching`, `DeckViewer` `:138-160`). A live preview of unsaved text needs a push path (`render(text, rev)`), and for decks, pptx bytes in memory through `duo-deck:`. LR-31's one reconciliation primitive per file surface must still hold.
7. **HTML source has no editor path.** `.html` always routes to the viewer (`ProjectPanes.swift:880`), and only lang-markdown is vendored. HTML source beside its page needs the editor to open HTML as text (a new routing rule, maybe HTML highlighting) and the read-only viewer to follow the buffer.
8. **Widths.** The right pane is 360–~658 at 1440 with the sidebar shown (~498 max at 1280). Halves fall under the right pane's 360 minimum, the review margin's 420 cut (DL-237, gutter mode always), the formatting bar's 420 table fold (DL-266), the browser bar's 360 truncation (DL-129), and decks' ~360 slide floor (R7).
   - A split inside the right pane must grow the right pane (eat console width down to 480, hide the sidebar), fold to a toggle or stack below a threshold, or take a different geometry (decks' S2: a fourth pane).
   - `PaneSplit`/`PaneWidths` assume three panes with one flex. A fourth pane or a nested split changes the DL-129 resize rule (which pane gives way first), F-9's collapse handling and the slide motion (`PaneMotion` global, C-44).
9. **F-208 and F-212 guards.** A nested split must not make `RootView` or `ProjectLayout` read changing state, and must not replace hosting views' root views. Whether the split shows must be watched inside AppKit, as `cover` and `liveColors` are. A source-scan guard reads `PaneSplit.swift` by path (C-84).
10. **Focus has no sub-pane.** `DuoPane` is left, middle, right. Everything in `RightPane` reports index 2 (`PaneSplit.swift:219`).
    - The pane rule, ⌥⌘←/→ order, ⌃Tab (the "active pane's tabs" in `rightTabItems` order), `focusPane(.right)` (first visible web view), `duo2 view pane|tab` and `duo2 status` all need a split-side level. DL-165 is still provisional (Q-165/166).
    - Decide whether each side has its own tab strip (two strips? one strip with a pair tab?) and how ⌃Tab behaves.
11. **`webFocus` is per kind,** not per view (`none|editor|html`). Two editors, or an editor beside an HTML page, collide. Menu validation (Format, Table, ⌘W, ⌘D, zoom) reads it.
12. **⌘W.** Closes `rightTab` only when the singleton editor has focus, else ends the console session (`Commands.swift:183`, `:252-254`). In a split it must close the focused side or end the split, never the console, as LR-60 requires. As read, ⌘W from a focused HTML page, deck, Word document or browser tab already closes the console session today, which is worth checking before the split builds on it.
13. **⌘S, Format and table items** go to `model.editor`, and need the focused side's editor. **⌘F** is responder-routed (fine if each side is its own responder; the find bar position and the formatting bar's 24 scroll margin apply per side). **⌘D** picks by `webFocus`/`editor.hasFocus` and sends to `visibleSessionId`. Decks R4 adds slot context for picks on slides.
14. **Voice.** `VoiceTarget` has no document case yet. DL-266 (6) adds it (designed, not built). A split must say which side gets dictation (decks: the source) and how ⇧⌘D resolves.
15. **The formatting bar and review bar belong to the editor column,** not the right pane. DL-266 places the bar over the editor and the review bar "in the pane's stack, above"; in a split both belong to the source side's stack. The preview keeps its own bar (deck 44, R6/R8). `DocumentStateBar`/`TemplateBar`/`MarkdownReviewSlot` read the singleton editor's state.
16. **The picker bar** (`PickerBar`, Select Shape / Select Element / Select Text) reads `visiblePage`, `htmlViewer` and `deckViewer` singletons and `sendTarget`. Two pages on screen need it bound to a side.
17. **Tab identity.** Keys are strings and unique per project, so a file is in one tab. A split as a pair (source key and view key, or one key plus a mode) must survive rename and move handling. Keys are rewritten in at least four places (`AppModel+TaskMenu.swift:77-78`, `AppModel+Control.swift:1124`, `AppModel+DuoFilesMove.swift:21`, the editor's `onRenamed`). It must also survive closing (left neighbour), ⌃Tab order, drag and Move Tab, the pinned rules (DL-225, Q-210), and the "· conflict" mark on a tab (`ProjectPanes.swift:948`).
18. **Persistence.** The restore file is per Home in the support folder, with no pane widths. R10's divider position and the split's sides are new fields; bump or extend `RestoreState` (version 1) with optional fields, as `rightCollapsed…` and `tabOrder` were. Validate on restore as `rightTab` is (`AppModel+Restore.swift:134`, `:154`). Keep it out of project files (OKF and Obsidian compatibility).
19. **duo2 parity.** Every split control needs a verb in `Actions.swift` with its `ui` labels; clicks and drags need `// action:`. DuoChecks' `parityGaps` enforces it. "Showing document" verbs (`doc read`, `doc tabs`, `slide`, `doc screenshot`, `status`) need a side. Regenerate `docs/cli/duo2.md`. Decks' proposal is `split`, `split <file>`, `split close`.
20. **Multi-window precedent.** Q-97 D7 (one document in two windows) and ENH-26 (a) are undecided. A split's same-file rule should match whatever Geoff picks there, or be decided together. Window-model work (Q-99 slice 1) removes the same singletons.
21. **Captures.** `withWebSnapshots` covers every web view (F-120). Proofs need fixture states for split layouts and `compare.sh` against approved screens. Pixel-exact editor checks should be done at each side's width in a browser page (CLAUDE.md). Harness actions like `right-width:` must find the right split (F-128).
22. **Performance and memory.** Each added WKWebView is a WebContent process. The editor page reloads after a process death (C-81, `DocumentEditor.swift:195`). Viewers sleep when hidden (C-83: `htmlViewer.sleep()`, deck `sleep/wake`); a second visible viewer means a second poll. Live re-render at 250 ms (R2) must stay off the main thread's critical path (F-208 lessons; `check-scale.sh`). C-79 notes Duo's idle CPU is already high.
23. **Terminals.** If a split ever puts a session beside a document (search's "Open in split view" on a session row), a terminal view is single-homed (C-43). Chat mode can type through it off-screen (F-168). LR-14 requires a PTY to resize once at the end of a slide (F-130).
24. **No system alerts.** Any question, such as a busy session or "replace the split?", goes through `SheetCenter` or a Duo sheet (CLAUDE.md, F-54).
