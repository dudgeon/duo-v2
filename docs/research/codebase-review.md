# Duo v2 codebase review

2026-10-12 · branch `review/codebase`, reviewed at main `844c6bb` and rebased onto `25c5297` · read-only on Duo's code: this is a report and a plan, and the director delegates the builds.

**Scope.** All of `Sources/`: 51,323 lines of Swift in 224 files (72,961 lines of tracked Swift, counting `Spikes/` and `Vendor/`). Also the editor's web code, 53 scripts, `Spikes/`, `Vendor/`, `Models/`, `wireframes/`, `video/` and `docs/`.

**Method.**
- Eight Sonnet reviewers each took one area: model and state; views; live state, hooks and terminals; chat; editor and web; `duo2`, search and checks; harness, scripts and docs; the intro video.
- I re-checked every finding below that is marked CONFIRMED, by reading the code or re-running the search, and dropped what I couldn't confirm. SUSPECTED marks a mechanism that is real in the code but whose cost or trigger isn't proven.
- Runtime numbers come from three sources:
  - a read-only `sample`/`footprint` of Geoff's own running Duo (the director's OK);
  - isolated background runs (own `DUO_SUPPORT_DIR`, scratch `CLAUDE_CONFIG_DIR`, the stand-in 2.1.219 CLI, SIGTERM by pid);
  - timed builds under the shared GPU lock.
- The measurement scripts are kept in the job scratchpad. They're listed under the measurement method so they can be re-run.

**Sizes.** S is under half a day for a Sonnet session, M is a day, L is several. Risk is the chance of a visible regression or a lost session.

## Summary: the ten changes worth the most

| # | Change | Size | Risk | Evidence |
|---|---|---|---|---|
| 1 | **Stop the idle burn** (C-79): cache hook summaries; one embedder, settle time and memoized token counts in the indexer; stop republishing `fixture` every 2 s; release closed chats; memoize `realPath`. *In flight on `fix/idle-cpu`, as fixes (a)–(d).* | M | Low | Geoff's Duo, up 4.5 days, idle: 45–150% CPU, 782 MB (peak 2.6 GB). The sample splits it as indexer ≈0.9 core, 2 s refresh ≈0.6 core (hook re-parse alone ≈0.34). Isolated, release: 40 hook logs add 3.5 points of a core. |
| 2 | **Fix ten confirmed bugs, S each** (the [correctness batch](#bugs-and-risks), C-80, C-81): `duo2`'s pre-edit hook fails closed on a stale token; env endpoints never fall back; value-less flags swallow the next argument; the properties fold is never remembered; Earlier turns drops live turns; task menus rewrite notes under unsaved editor text; two dead-end buttons; `GitIgnoreOffer` bypasses `GitTool`; two NSAlerts. | S×10 | Low | Each is proven at a file:line below. |
| 3 | **Bound chat memory**: tail-parse the transcript instead of holding every record (ENH-23 d); feeds of hidden chats ingest nothing; one shared feed timer. | M | Medium | `ChatFeed.history` keeps every parsed record for the feed's life. A 236 MB fixture parses in 1.15 s and holds 417 MB, against 0.25 s and 55 MB tail-only. F-157 recorded a 352 MB peak for one chat; F-208 recorded 3.1 GB on the 16-tab work Mac. |
| 4 | **A two-speed live refresh**:<br>• a structure pass (projects, history, titles, trees, threads) on change or every 15–30 s;<br>• a live pass (beacons and hooks of running sessions) every 2 s;<br>• cache the repo state instead of 7–8 `git` spawns per tick;<br>• `treeFiles` for the open project only. | L | Medium | **Measured: 32.5% of a core idle with 600 sessions** (release), 33% of it in `LiveSnapshot.build` and 14% in `realPath`. 42 sessions cost 1.9%. Every 2 s it re-derives everything from disk:<br>• `realpath` and a history sort per project, O(P²·H);<br>• trees, task notes and session indexes for every project;<br>• `DuoState` decoded 3 times;<br>• about 200 `git` processes a minute. |
| 5 | **No disk reads in view bodies**:<br>• make the per-row context menu a lazy view;<br>• keep `DuoState` in memory;<br>• index `Fixture` sessions by key. | S–M | Low | `SessionOrganizeMenu`, on 9 surfaces, builds its menu in `body`, so every row reads state.json and parses every task note on each snapshot (`AllProjectsPanes.swift:1048,1053`). |
| 6 | **Web view lifetimes and crash safety**:<br>• weak script-message handlers, with closed browser tabs torn down;<br>• restored web tabs load lazily;<br>• recover when a WebContent process dies;<br>• the editor's web view is not built at launch. | M | Low–med | No `webViewWebContentProcessDidTerminate` anywhere, so a crashed editor process loses unsaved text silently (C-81). `WebTab` retains itself through its handler (`BrowserTabs.swift:140`). Restore loads every saved tab in every project (`AppModel+Restore.swift:117-122`). |
| 7 | **Ship third-party notices** in the app and the repo (C-82). | S | Low | Only the docx viewer's licences reach `Duo.app`. SwiftTerm, CodeMirror, Sparkle, pptx-renderer (Apache-2.0, MPL-2.0, ECharts) and the bge model ship without theirs (`bundle.sh:50-61`). |
| 8 | **Search typing path**: one query embedder, a debounce, and the index opened off the main thread. | S | Low | Each query builds a new `Embedder` (Core ML model plus a 30k-line vocabulary) and a new `SearchIndex` (`AppModel+Search.swift:156-157`). `indexState()` runs on the main thread per keystroke. |
| 9 | **Mechanical splits and a checks registry**: the four biggest view files; `perform()` by verb family; DuoChecks' 2,600-line `run()`; the slowest type-checks. | S each | Very low | 13 functions take over 200 ms to type-check. `ChatPerf.perform` takes 4.3 s, `DuoChecks.run()` 2.2 s and `SessionListFilter.matches` plus its expression 3.5 s. A typo in `DUO_CHECKS` runs the whole suite. |
| 10 | **Debug code out of release, plus a dead-code sweep**:<br>• `#if DUO_HARNESS` or a harness target;<br>• the dead harness actions, flags and states;<br>• the stale `Parity.uiOnly` rows and design-README statuses. | M | Low | 3,370 lines of `Debug/` compile into the release app, along with 656 KB of chat fixtures. It includes `disk-write`, `freeze` and a walk-setup that spawns `python3`. 42 harness actions are used by nothing. |

**The intro video pipeline** has its own top 3 ([§ Intro video pipeline](#intro-video-pipeline)):
1. A per-scene render cache and a `--scene` preview: today every cut is a 23-minute render.
2. Cameras placed relative to anchors, with a stale-anchor check: absolute-pixel cameras break on every layout change.
3. A no-GPU check stage plus a Doc-sync tool: the hand sync of `line:` indices and `shotSha` caused 8 of 50 rework commits.

**Headline numbers** (release build, isolated, background; [details](#memory-and-performance)):
- `duo2` answers 0.5 s after launch.
- Idle CPU is 3.5–4.4% of a core for 42 sessions or 16 restored tabs, and **32.5% for 600 sessions**: the 2 s refresh grows with history.
- 40 hook logs add 3.5 points.
- First launch peaks at 0.75–1.8 GB while the index is built and transcripts are parsed whole.
- Live heap at rest is 57 MB.
- The editor's three WebKit processes start at launch with no document open.

## Abandoned code

**How each item was proven.** A whole-word search over `Sources scripts video .claude docs/cli`, and Vendor's `src/` for the JS, counting string-reachable names too: harness actions, `--state` names, JS bridge names and `duo2` labels. "def only" means the one hit is the declaration.

**Old-CLI shims stay.** None of them is dead on Claude Code 2.1.219, the work Mac's pin. DL-155 trusts any 2.1.x, so gates below 2.1.219 stay in range too:
- the paste-on-send path below 2.1.269 (`ChatVersion.externalEditor`);
- the plan-file read below 2.1.285 (`freshPlanInHook`);
- the 2.1.219 effort footer and `commandRowBelow` (`ChatScreen.swift:53,58,67`);
- the chat hook set gated at 2.1.152;
- `cliUnderstandsRelocation` (below 2.1.169);
- `RemoteControl.supported`.

### Swift: remove (S, no risk unless noted)

| Item | Where | Proof |
|---|---|---|
| `ChatComposerStandIn` | `Chat/ChatView.swift:487-496` | def only; the composer has been native since "phase 4" |
| `ChatSession.onChange` and its 3 calls | `Chat/ChatSession.swift:238, 404, 410, 430` | never assigned. The `onChange =` sites in `AppModel+Send.swift:258-287` and `BrowserTabs.swift:456` belong to other types. |
| `ChatPaste.promptHoldsOnly` | `Chat/ChatPaste.swift:99-106` | used only by `DuoChecks/ChatChecks.swift:875`; `removeImageTokens` and `sendPlan` replaced it |
| `@Environment(AppModel.self) model` | `Chat/ChatReviewCard.swift:11` | the body (14-31) never reads it |
| `AppModel.appVerbs` | `Control/AppModel+Control.swift:18-19` | def only (its comment claims DuoChecks; DuoChecks uses `ActionID.allCases`) |
| `cancelPush`, `cancelGitHubProject`, `isOldWordDocument`, `boardDrag` | `AppModel+Push.swift:171`, `AppModel+GitHubProject.swift:200`, `AppModel+Convert.swift:27`, `AppModel.swift:77` | def only each; `cancelSheet()` already clears both forms |
| `fixtureArchived` | `AppModel.swift:116` | read once (`ArchivedProjects.swift:8`), assigned nowhere, so that branch is unreachable |
| `AppModel.mapProjects(inTopic:)` | `AllProjects/ArchivedProjects.swift:13-16` | def only |
| `Fixture.homeInbox`, `InboxItem`, `otherIdleSessions`, `now` | `Model/Fixture.swift:72,122,127,130` | only constructor arguments write them; nothing reads them. Removing `now` is also C-79 (c). |
| `Attention.state(for:lastStopMessage:)`, `Attention.Reason.plan` | `Live/Beacons.swift:66,70-82` | only DuoChecks (`main.swift:519-523`) calls it; production uses `Attention.live`. Remove the 5 checks with it. |
| `RepoView.duoChanges` | `Git/RepoLine.swift:28` | def only |
| `SessionIndex.Entry.archived` filters | `LiveSnapshot.swift:122,171` | nothing writes `.archived` (`DuoState.archivedSessions` replaced it). Keep the keys so files round-trip, but drop the dead filters. `starred` is def only. |
| `contentOf` in `SearchIndex.search` | `DuoSearch/SearchIndex.swift:253,271` | written, never read: the only reader of column 8 |
| `SessionSource.Transcript.cwd` | `DuoSearch/SessionSource.swift:13,32` | always `nil` |
| search schema stamp and the per-open `ALTER TABLE` | `SearchIndex.swift:42` | `schema = 1` is written and never read; the ALTER runs on every writable open with its error swallowed. Use `PRAGMA user_version`. |
| `DuoGlyphPath` | generated into `Design/Tokens.swift:525-531` by `gen-tokens.py:241` | def only. `StateGlyph.swift:36-66` hard-codes the same five shapes, so they can drift: emit it and use it, or stop emitting it. |
| `Bordered.radius` | `Shell/Components.swift:79` | the `bordered(…)` wrapper never passes it |
| `MapPacking.columns` | `AllProjects/AllProjectsPanes.swift:381-389` | only DuoChecks (`main.swift:1181`) calls it. `PackedColumns.pack` repeats the loop inline (360-367), so the check proves a copy. Make `pack` call it. |
| `--gallery` and `Debug/GalleryView.swift` (112 lines) | `DuoApp.swift:206` | no script, doc, skill or video uses it. It also takes the `Parity.uiOnly` row "Resume a session" and its line in `docs/cli/duo2.md:279`. |
| `--terminals demo`, `TerminalsMode.demo` | `DuoApp.swift:63-68`, `AppModel.swift:19,253-255`, `LaunchOptions.swift:14,41,79` | no script or check; live mode (DL-82) replaced it. M, low. |
| 42 harness actions | `Debug/FixtureHarness.swift` | used nowhere outside the file (reviewer's per-name search): add-column, ask-remove-column, board-filter, chat-answer, chat-ask, chat-send, console-state, convert-failed, disk-restore, doc-select, docx-dump, docx-markup, docx-person, docx-send-picked, edit-bold, explain-tasks, hover-card, hover-lane, hover-new-task, makeproject, move-card, newfolder, outside-title, search-action/archived/close/key/kind/pick/scope/state/turns, send-file/project/session, sheet-cancel/goal/into/ok, similar-file, task-delete, task-move. A further 53 appear only in docs and records: review those as a batch. |
| duplicate `case "zoom-out"` | `FixtureHarness.swift:122` and `:238` | the second is unreachable |
| `perf-scroll`, `perf-watch`, and `Watchdog` | `Debug/ChatPerf.swift:44-67, 248-277` | used only in the file; `perf-wheel` and `perf-append` replaced them. `Watchdog`'s thread never stops. |
| 8 `--state` names | `HomeListTargets.swift:8,23-26`; `VideoTargets.swift:13-24` | `list-filter` and `list-nothing` appear only in findings. `video-s4-menu`, `video-s5-chat-open/-draft/-paste-text/-paste-image` and `video-s6-final` are unused: `video/` uses only `video-s5-chat`. That makes `impliedActions`' `video-s5-` branch (`VideoTargets.swift:305`) dead. |

### Editor web code: remove (S)

- **Unused `window.duo` exports** (`Vendor/codemirror/src/duo-editor.js`):
  - `setFolded` (2351), `properties` (2352), `merge3` (2400), `claudeChanges` (2437), `typeSlowly` (2454), `hiddenCount` (2464).
  - `scripts/check-merge.mjs` extracts the *function* `merge3` from the source text, not the export.
  - `bench`, `typeOne` and `caret` are used only by `Spikes/S4Editor`.
- **An unused import:** `replaceNext` (line 10).
- **`post("ready")` (2466)** has no Swift handler. Readiness comes from `didFinish` (`DocumentEditor.swift:123`).
- **Three dead arms in the `noteEdit` bridge** (`DocumentEditor.swift:390-393`): `removeReference`, `addSession` and `status`. The page posts only `addReference` (`duo-editor.js:643`).
- **`EditorController.kept[…].text`** is written (`DocumentEditor.swift:153, 462`) and never read. Line 462 keeps a whole document's unsaved text alive for nothing.

### Not dead, though it looks it

- **The docx → Markdown converter** (`DuoSearch/Docx.swift`). DL-162 keeps Convert to Markdown, reached from `DocxView.swift:68` and `duo2 file convert`. But `Docx.swift`, `DocxOutline.swift` and `Pptx.swift` (about 1,400 lines) live in `DuoSearch`, and neither search nor `duo2` uses them: a layering fix, low payoff. Its `.reject` and `.leaveOut` options are set only by checks (Q-62): keep them on purpose or delete them.
- **`ChatStore.forget`** (`ChatSession.swift:515`). It has no caller because the call is missing: C-79 (c).
- **`flushTask`** (`AppModel+TaskMenu.swift:48`). Def only since 28123ad, but it is the missing editor flush: C-81.
- **Test seams in the app target.** `ChatFeedProbe`, `ComposerProbe` and `TerminalStore.closingCount` are fine.

### Outside `Sources/`

| Item | Proof | Verdict |
|---|---|---|
| `Vendor/swift-markdown-engine/` (1.1 MB, Apache-2.0) and `Spikes/S6Native` | referenced only by S6Native's `Package.swift`; its `VENDORED.md` says "Not used by Duo itself" | remove after tagging |
| `Spikes/S4Editor`, `S7WebView`, `S14Embed` | prose mentions only | move to an `archive/spikes` tag (precedent: `archive/s1-swiftterm`) |
| `Spikes/DocxViewer` (216 KB) | docs only; keep `patch-paraids.py`, the fallback named in `Vendor/docx-viewer/README.md:12` | remove the rest |
| `Spikes/chat-mode`, `DocxToMarkdown/docs` + `out/duo`, `PptxViewer/decks` | live test infrastructure: DuoChecks (`ChatLive.swift:90`, `main.swift:1695,1936,2135`), `check-deck.sh:28`, the `make-chat-*` generators | **keep**; move to `Tests/Fixtures/` and `Tools/mock-claude/` so `Spikes/` can be archived |
| `Spikes/S13CoreML` | `Models/README.md` names `convert.py` as provenance | keep; move to `Models/convert/` |
| `wireframes/` (164 KB) | only `.claude/launch.json` points at it; `01-shell.html` has no source in `wireframes/src/` | remove with its launch entry |
| `.claude/launch.json` `edtest` | serves `build/edtest`, which nothing creates | remove |
| `scripts/chip-measure.py` | nothing references it (a DL-168 one-off) | remove |
| `docs/plan/review/phase-*` (7 MB of 2026-10-03 screenshots) | findings and the build plan only | keep the findings' text; move the PNGs to an archive tag |
| `video/src/lib/Callout.tsx`, `kind: 'desk'`/`'card'` (`plan.mjs:218-279`), `Turn.tsx`, scene `many`, the `stand-in` transitions, `pipeline/wallpaper-options.mjs`, `score/mix.py`, `score/jobs/samples.json`, `voice/experiments/*.py`, `video/archive/` | no importers (`shots.json` uses only drawn scenes) | remove. The five studio compositions in `Root.tsx` are kept on purpose (`shot-grammar.md`), but they don't need to be in the render bundle. |
| `DUO_MENU_UPDATE`, `DUO_DOWNLOADS_DIR`, `DUO_COMPOSE_DIR` | set by no script or doc | SUSPECTED: confirm, then drop |

### Stale text in code and the registry (S)

- **`Parity.uiOnly` rows** (`Actions.swift`, then regenerate `docs/cli/duo2.md`):
  - "Toggle Right Pane" (441) says "not built yet", but `view right` and `Commands.swift:68` build it.
  - "Open Settings…" (444) says "not built", but Settings exists (`DuoApp.swift:153`). See C-80 for the button.
  - "Resume a session" (456) covers only the debug gallery.
  - `Cancel` and `Not Now` are listed twice.
- **Comments that misdescribe the code:**
  - `Actions.swift:5-6` names an `ActionButton` that doesn't exist.
  - `ChatScreen.swift:14-15` gives the "only these answer dialogs" rule, which DL-145, DL-155 and DL-164 superseded.
  - `DuoToolbar.swift:193-195` says search "isn't built yet".
  - `TreeDrop.swift:72` and `ArchivedProjects.swift:5` still call themselves stand-ins (DL-132 settled them).
  - `ClaudeStorage.swift:5-6` says calibration runs "on launch"; it runs only before a migration.
  - `DocxViewer.swift:14-16` says nothing watches layout, but `docx.js:355-358` installs two observers.
- **Docs that promise an About box that doesn't exist:** `Vendor/docx-viewer/README.md:8` ("Settings › About lists the notice") and `codemirror/build.sh`. See C-82.

## Refactors

Ranked by payoff against risk. Each has a task in the [build sequence](#proposed-build-sequence). Performance refactors are under [Memory and performance](#memory-and-performance).

### High payoff, low risk

1. **One `DuoState` in memory** (M).
   - `DuoState.load()` reads and decodes state.json on every call (`Live/HookEvents.swift:268-270`). That covers:
     - 3 calls per refresh in `LiveSnapshot.build` and 1–3 on main (`AppModel+Notify.swift:15,27,28`);
     - per row in context menus (`ArchivedSessions.swift:7`);
     - per hover event (`Explainer.swift:41,48,207`);
     - per `body` in Settings (`SettingsView.swift:80,215`);
     - 5 times in the `settings` verb (`AppModel+Control.swift:308-315`).
   - Make it an `@Observable` store with write-through `update`. Keep `load(_ url:)` for DuoChecks, and move `DuoState` out of `HookEvents.swift`.
   - A generic `JSONFile<T>` (load with default, skip unchanged bytes, atomic save) would replace the four hand-written copies: `DuoState`, `RestoreState`, `SessionIndex` and `HookEvents.settingsFile`.
2. **One session lookup.**
   - `Fixture.session(key:)`, backed by a dictionary built once per snapshot, replaces all of these:
     - about 24 `fixture.sessions.first { $0.tabKey == … }`;
     - nine `fixture.sessions + (fixture.archivedSessions ?? [])` concatenations, some per row;
     - five copies of `tabKey == key || sessionId == key` (`AppModel+Migrate.swift:74`, `+Tasks.swift:127,142`, `+Links.swift:11`, `ArchivedSessions.swift:14`);
     - `findSession` (`AppModel+Control.swift:1042`).
   - Also index sessions by project. `MapLayout.build`, `ProjectTile` (3–4 scans each) and `SessionList.build` are O(projects × sessions) per body (`MapLayout.swift:134,153`, `AllProjectsPanes.swift:673-690`, `SessionList.swift:43,76-89`).
   - S–M.
3. **Mechanical file splits.** Types are `internal`, so these are cut-and-paste with no behaviour change (S each):
   - **AllProjectsPanes.swift (1,287 lines), into 7 files:**
     - HomePane: 5-174
     - map grid and packing: 176-399
     - MapHeader: 401-485
     - tiles: 487-831
     - action column: 833-1020
     - menus: 1022-1186
     - drag and drop: 1188-1287
   - **ProjectPanes.swift (1,172), into 5:**
     - sidebar: 5-270
     - file tree and its menus: 272-516 and 753-894
     - console pane: 518-557
     - right pane: 559-751
     - document bars: 896-1172
   - **TaskBoardView.swift (852):** chrome, lanes, cards, empty state, glyph.
   - **SearchView.swift (943):** overlay and field, filters, states, results, preview, footer. Move `PopUp`, which the tab strips use, to Shell/.
   - **Chat:**
     - `ChatComposerView` (760): area, menus, field, `ComposerTextView`, slash.
     - `ChatScreen` (652): signatures, model, regex, reader, pickers, question.
     - `ChatSession` (610): prefs, terminal, fallback, request, `ChatStore`, and `ClaudeVersion`, which goes to `Claude/`.
     - `ChatView` (593): UI state, pane, you-views, status lines, Claude card, link hover.
   - **12 SwiftUI view types that sit in model files** (`AppModel+Tasks.swift:231-719`, `AppModel+TaskMenu.swift:424-505`) move to `Project/`.
   - **`AppModel+Control.perform()`** is a ~680-line switch (37-712): one extension file per verb family, keeping the exhaustive switch as the router.
   - **DuoChecks' `run()`** is about 2,600 lines with 689 `check(` calls. Make a registry of `(name, group, run)`, with `DUO_CHECKS=a,b`, `--list`, and an error on an unknown name: today a typo silently runs everything. Then move each group to its own file, using the line ranges in the reviewer's notes: Control, Search, Migration, Browser, DocViewer, Files, Task and LayoutToken.
4. **One sheet and question policy** (M).
   - `SheetCenter.ask` should own `Env.autoconfirm`. Today 14 call sites intercept it by hand, in three different behaviours:
     - log and take the default (`AppModel+TaskMenu.swift:334`, `+Organize.swift:244,255`, `+Home.swift:118`, `+Convert.swift:61,129`);
     - log and return (`+Repo.swift:114,201,246`, `+Update.swift:231`);
     - log and still ask (`+Board.swift:391`, `+Drop.swift:69`).
   - Replace the four optional form slots (`moveIntoHomeForm`, `newProjectForm`, `pushForm`, `gitHubProjectForm`), the OR-chain `sheetIsUp` and `SheetOverlay`'s precedence chain (`Shell/Sheets.swift:20-26`) with one queue. A question queued while a form is open is invisible today but still counts as a sheet.
   - Extract the sheet chrome, which is pasted five times: `PushSheet.swift:49-54`, `Sheets.swift:68-73,111-116`, `GitHubProjectSheet.swift:~70`, `DuoQuestion.swift:231-236`.
5. **Shared helpers**, S each, with a DuoChecks case per helper.
   - **Tilde-shortening:** at least 10 copies. Several use `replacingOccurrences(of: home, with: "~")`, which rewrites any occurrence, so `/Users/geoffrey/x` becomes `~rey/x`. They are:
     - `AppModel.short` (`+Migrate.swift:66`);
     - `+Templates.swift:145`;
     - `+Control.swift:1012,1019,1029`;
     - `ConsoleStates.swift:65`;
     - `SendFormat+Docx.swift:10`;
     - `ProjectDiscovery.swift:114`;
     - `MissingFolders.swift:18`;
     - `ChatIngest.swift:14`;
     - `LiveSnapshot.swift:191`;
     - `SessionList.swift:79`;
     - `Installer.swift:132`;
     - `InstallPrompt.swift:46,66`.
   - **Path relative to a folder:** 8 variants.
   - **Age text:** 4 formatters with different outputs: `RepoLine.ago`, `AppModel.ago`, `AppModel.age`, `Attention.waitText`.
   - **The `yyyy-MM-dd` formatter** is built per call, 4 times.
   - **The main window** is found by `title == "Duo"` about 25 times.
   - **Process ancestry and ppid:** 2 copies each (`AppOwning`, `ProcessLiveness`, `AppModel.isDescendant`).
   - **The Claude config dir** is resolved 3 ways (`LegacyDuo.claudeDir`, `ClaudeStorage.swift:9`, `SearchService.swift:72`).
   - **The `CharacterSet("“”\"")` title trim** is pasted 5 times.
   - **The mono font** is built inline 7 times.
   - **The frontmatter idiom** is pasted 11 times (`TaskNotes.swift`, `Templates.swift`, `TaskBoard.swift`, `PropertyCorpus.swift`). Make one editor; DL-93's byte-for-byte output is the check.

### Medium payoff

6. **One transcript reader and one title ladder** (M, medium risk).
   - **Eight readers each split JSONL and run `JSONSerialization` their own way:**
     - `ChatFeed`, `ChatIngest`;
     - `ThreadCache.head`/`full`;
     - `SessionTitles.read`;
     - `ClaudeStorage.filingCwds`;
     - `Inventory.evidence`;
     - `Migrator.firstCwd`/`currentCwd`;
     - `SessionSource.read`;
     - `HookEvents.read`.
   - Replace them with one `TranscriptTail`: an offset watermark, a line scanner, a cheap substring prefilter before JSON (as `filingCwds` already does), and one cache keyed by (path, size, mtime).
   - **Three title ladders disagree:** `SessionTitles.title`, `SessionSource.read` and `Inventory.evidence`. A search hit names an untitled session by its raw first 80 characters, while the sidebar shows the cleaned, quoted prompt. Put one ladder in DuoControl or DuoSearch, which both sides can import.
   - **Two decoders read the same hook-payload fields** (`HookEvents.parse` and `ChatIngest.hook`).
7. **A `ScriptedPage` host for the deck, Word and HTML viewers** (M). They repeat:
   - the settle/waiters state, the scheme handler, the navigation policy and the failure handler;
   - a `SchemeProxy`;
   - a 1 Hz polling timer each (`HTMLViewer.swift:53-62`, `DeckViewer.swift:131-140`, `DocxViewer.swift:249-258`).

   Use `EditorController.watch`'s vnode watcher instead of polling (`DocumentEditor.swift:494-515`). This saves about 150 lines and gives every viewer the same sleep and wake: only Docx has `sleep()` today. Merge the two pickers too (`deck.js:74-118`, `docx.js:310-343`).
8. **One tab-row component** for Home, console and right pane (M; pixels).
   - The same stack is written three times: close glyph, hover fill, underline, organise menu, transition (`AllProjectsPanes.swift:46-122`, `ConsoleTabStrip.swift:79-124`, `ProjectPanes.swift:569-664`).
   - Home's copy has already drifted: no overflow `» n`, and on the dark strip it uses the light menu-target fill.
   - Also unify:
     - six fold toggles;
     - eight hover-bookkeeping blocks over seven `String?` model properties;
     - three pills;
     - two segmented controls;
     - about eight Canvas glyphs (the magnifier is drawn three times).
9. **Decode the editor bridge into an enum** (S).
   - `DocumentEditor.swift:371-418` is eight `if let … kind ==` casts. `propertiesFolded` falls through them (C-81).
   - The `duo.*` contract is about 100 stringly-typed call sites in 14 files. A DuoChecks case that loads the bundle and asserts the Swift call list ⊆ `Object.keys(window.duo)` would guard it.
10. **Registry-driven flags for `duo2`** (S–M).
    - `Invocation.switches` (`Actions.swift:482`) is a hand-kept set, separate from each verb's declared args. That is how five value-less flags went missing (C-80).
    - Declare flags per `DuoAction`.
    - Make the parity scan follow the specific verb rather than one global label set. Today it matches only literal `Button(`/`Menu(`/`ActionMenuItem(` labels and misses 18 `Toggle(`s and 14 `Picker(`s. One parity tag is already wrong: `AppModel+Tasks.swift:612` tags Copy Link `// action: doc prop`.

### Large, do last

11. **Extract `RepoModel`** (M–L): `+Repo`, `+Push`, `+GitHubProject` and `+RepoControl`, 841 lines.
    - It needs an explicit `project:` because `repoVerb` calls `open(project:)` (`AppModel+RepoControl.swift:18`). A `duo2 repo` call from a background session therefore navigates Geoff's window.
    - `showPush` and `pushFromCLI` build `PushForm` twice.
12. **Extract `TasksModel`** (L): `+Tasks`, `+TaskMenu`, `+Board` and `+TaskContext`, 1,824 lines and 15 stored properties.
    - First move out the ~365 lines of views and ~175 lines of editor property menus.
    - Add a `NoteEdit` helper (read, edit, atomic write, register an undo that restores the bytes) for its ~9 copies.
13. **Extract `LiveWorkspace`** (L, high risk): `AppModel.swift:394-585`.
    - `apply()` is a 12-step main-thread chain: follow sessions, follow shells, search, task titles, note context, notify, archive, gitignore offer, repo, restore, save restore, Home auto-start.
    - Every extracted type needs a host protocol of about 8 members. `refreshLive` alone has 70 callers in 15 files, `liveFolders` 94 in 21 and `currentProject` 82 in 18.
    - Do it after task 6 of the sequence (the two-speed refresh) has settled the shape.
14. **A `DemoOverrides?` holder** (M) for the 13 test and video hooks on the production model: `fixtureChats`, `fixtureTerminals`, `videoDemoFolder`, `videoTasks`, `listClock`, and others.
    - About 14 production branches test them.
    - About 47 `accessibilityIdentifier("video.…")` calls and 8 `videoDemoFolder` overlays sit in production views. A `.videoAnchor(…)` modifier would remove about 35 lines of noise.

## Memory and performance

### Measured: the field

**Geoff's own Duo** (pid 34502): the main checkout's debug ("Duo Dev") build on the acceptance workspace, up 4 days 15 h, nothing changing on screen. F-286 has the details.

- **CPU:** 45–150% by `ps` over 30 s; 106% and 160% at other moments.
- **Memory:** footprint 782 MB, peak 2.6 GB. That includes 286 MB of GPU buffers held by the search model (`IOAccelerator`) and 404 MB of small mallocs.
- **Threads and files:** 46 threads (15 SwiftTerm reader/gather pairs), 177 open files.
- **The 10 s sample** (~5,940 samples per thread; 59 samples ≈ 1% of a core):

  | Frame (inclusive) | Samples | Share of a core |
  |---|---|---|
  | `SearchService.pass` → `indexProject` → `Chunker.chunks` → `WordPiece.normalize/words/pieces`; `Embedder.embed` on MPSGraph | 5,176 | ≈ 87% |
  | `AppModel.refreshLive` → `LiveSnapshot.build` | 3,716 | ≈ 63% |
  | of which `HookEvents.read` (256 KB tail, `Data.split`, `JSONSerialization` per line) | 1,992 | ≈ 34% |
  | the main thread | — | nearly idle; no SwiftUI or Core Animation frames |

### Measured: isolated runs

Release build of this branch, background, the stand-in 2.1.219 CLI, first launch each time. The fixture is `make-scale-fixture.py`: 6 projects and 42 sessions, 4 of them 16.7 MB long transcripts, unless the shape says otherwise.

| Run | Shape | `duo2` answers | CPU, first 30 s | **Idle CPU, 60 s→end** | Footprint end / peak | WebKit processes |
|---|---|---|---|---|---|---|
| rel-short | 42 sessions, no long transcripts | 0.68 s | 2.3 s (8%) | **3.5%** | 127 MB / 294 MB | 3 at launch, no document |
| rel-idle | the default fixture | 0.51 s | 8.0 s (27%) | **3.7%** | 444 MB / 1.1 GB | 3 |
| rel-events | + 40 sessions with a 256 KB chat-mode hook log | 0.54 s | 8.7 s | **7.2%** | 478 MB / 1.2 GB | 3 |
| rel-churn | + a 500 KB Markdown file in Home, appended every 20 s | 0.50 s | 8.1 s | **3.9%** | 318 MB / 1.2 GB | 3 |
| rel-scale16 | check-scale's shape: 16 chat tabs restored, Home in chat, board | 0.50 s; restore parked 14 at 5.5 s | 7.0 s | **4.3%** | 177 MB / 930 MB | 3 |
| rel-term16 | the same tabs in terminal mode | 0.50 s | 7.0 s | **4.4%** | 205 MB / 754 MB | 3 |
| rel-many | **40 projects, 600 sessions** | 0.46 s | 22.0 s (73%) | **32.5%** | 253 MB / 1.8 GB | 3 |
| rel-docs | + 4 notes and 4 HTML pages opened by `duo2 doc open` | 0.53 s | 9.0 s | **4.0%** | 216 MB / 1.0 GB | 3 → 4: 2 WebContent in total (~67 MB) |
| dbg-events | the debug build, as rel-events | 0.79 s | 11.9 s (40%) | **9.8%** | 475 MB / 1.2 GB | 3 |
| dbg-churn | the debug build, as rel-churn | 0.56 s | 10.6 s | **5.0%** | 474 MB / 1.2 GB | 3 |

**What the numbers show:**

1. **The live refresh grows with session history.**
   - At 600 sessions it costs a third of a core while idle (rel-many). Its 10 s sample has `LiveSnapshot.build` at 2,328 of 7,054 samples (33%), with `realPath` alone at 976 (14%), `ClaudeStorage` at 258 and `SessionArchive` at 132.
   - At 42 sessions the same build costs 1.9% (rel-idle: 134 samples).
   - Duo lists every Claude session on the Mac (DL-82), so a long-time user's history makes this the biggest steady cost.
   - Task 6 (two speeds, memoized `realPath`, history indexed by id) should bring rel-many under 5%. That's an estimate: the structure pass moves from every 2 s to on-change or every 20 s.
2. **Hook logs cost about 3.5 points of a core per 40 logs, release or debug.**
   - rel-events: `HookEvents.read` 295 samples (4%); dbg-events: 431 (6%).
   - The debug build is only ~1.4× slower here, because the work is in Foundation's `Data.split` and `JSONSerialization`.
   - Every Duo-started session keeps its log forever (nothing prunes `events/`), so the cost only grows. On Geoff's Mac it is 34% of a core.
   - C-79 (a) removes it for every log that hasn't changed.
3. **Re-indexing one big edited file is cheap in release.**
   - rel-churn is only +0.2 points over rel-idle.
   - The field's ≈0.9 core comes from DL-103's scope on a developer's Mac: every repo Claude has run in, including `duo-v2` with ~15 sessions editing large docs. Many files change every minute, and each is re-tokenized and re-embedded.
   - C-79 (b)'s settle time bounds that to once per quiet period per file.
4. **Launch is quick, first launch is heavy.**
   - `duo2` answers in 0.46–0.79 s in every shape.
   - The first 30 s cost 7–22 s of CPU, and the footprint peaks at 0.75–1.8 GB. The 8 s launch samples show why:
     - the first index pass, `SearchService.pass`, ≈2,800 samples. Of those, `SessionSource` (whole-transcript parsing for session search) is ≈2,100, and the model load (`MLModel`) ≈1,750.
     - `LiveSnapshot.build`, ≈2,300. With this fixture, most of it is `ThreadCache.head`: the fixture's transcripts have no `uuid`, so it reads to its 4 MB cap. Its loop re-splits and re-parses the whole buffer after each 64 KB chunk (`ThreadCache.swift:57-63`), which is quadratic up to the cap. Real transcripts stop early, but a transcript whose first user line comes late pays it.
   - Without long transcripts the peak is 294 MB (rel-short). So reading transcripts incrementally in `SessionSource` (refactor 6, task 13) is the lever for the first-launch peak.
5. **Memory at rest is modest.**
   - A `heap` of the rel-idle shape at 90 s shows 57 MB of live allocations under a 173 MB footprint. Nothing large is retained by Duo's code at rest.
   - The bigger end-of-run footprints (318–478 MB) are index passes in flight: Core ML's GPU buffers and transient parses.
   - Chat history is different: it is held for as long as a chat is attached (refactor and task 4).
6. **Web views are cheap, apart from one at launch.**
   - All Markdown documents share one editor process, and all HTML pages one viewer process: 4 notes and 4 pages make 2 WebContent processes, ~67 MB.
   - But the editor's WebContent, GPU and Networking processes start at launch with no document open. The launch sample shows the path: `DuoCommands.body` → `DuoCommand.isEnabled` (`Commands.swift:173`, Save) → `AppModel.editor.getter` → `EditorController.init`.
   - Fix: `editorIfLoaded` (task 2).
7. **The main thread is quiet in background runs:** 60–125 busy samples of ~7,000 (1–2%). Background windows may not be drawn (F-208), so this understates SwiftUI cost.
   - The code-level invalidation findings below aren't visible in these numbers: `fixture` republished every 2 s, per-row disk reads in menus, the hidden altitude still rendering.
   - They need the visible gate (`DUO_TEST_FOREGROUND=1`, Geoff's OK) with SwiftUI body counters.

### Expected gains, per proposal

| Proposal | Before | Expected after | Basis |
|---|---|---|---|
| C-79 (a) hook summaries cached | +3.5 points per 40 logs (release); 34% of a core in the field | ≈ 0 for unchanged logs | rel-events vs rel-idle; the field sample |
| C-79 (b) indexer: one embedder, settle time, memoized token counts, vacuum on change | ≈ 87% of a core in the field (debug, many busy repos) | proportional to quiet-period edits; ~0 between them | the field sample; rel-churn shows the per-file cost is small in release |
| C-79 (c) `fixture` not republished; closed chats released | `fixture` reassigned every 2 s | 0 when nothing changed | code (AppModel.swift:482, LiveSnapshot.swift:302) |
| Task 6: two-speed refresh, memoized `realPath` | 32.5% of a core at 600 sessions; 1.9% at 42 | < 5% at 600 | rel-many's sample (33% in `build`, 14% in `realPath`) |
| Task 6: repo state cached | 7–8 `git` spawns every 2 s for the open project (~200 a minute) | `status` on `.git` change or every 10 s | code (RepoStatus.swift:127-148) |
| Task 13: incremental `SessionSource`, prefilter | first-launch peak 0.75–1.8 GB; 7–22 s of CPU in the first 30 s | peak near rel-short's 294 MB | launch samples; rel-short vs rel-idle |
| Task 2: no editor at launch | 3 WebKit processes (~25–45 MB) with no document | 0 | the launch sample |
| Task 4: chat tail-parse | 417 MB and 1.15 s to open a 236 MB transcript; held while attached | 55 MB and 0.25 s | the chat reviewer's standalone benchmark (ENH-23 d, F-157) |

### Code-level findings, not yet measured

All CONFIRMED in code; magnitudes are SUSPECTED until measured.

- **Polling everywhere, no tolerance.**
  - All live state is polled. There's no FSEvents or kqueue except the editor's per-document vnode watchers, and no timer sets `tolerance`.
  - The full inventory of timers, intervals and threads is in the live reviewer's notes. The main ones:
    - 2 s refresh;
    - 0.15 s per chat feed;
    - ~100 ms hang-monitor ping;
    - 1 Hz per viewer;
    - 60 s archive;
    - 60 s search;
    - 60 s property and reference scan once the editor exists.
- **The hang monitor pings the main thread about every 100 ms, forever** (`HangMonitor.swift:55-66`). That defeats App Nap. The director has kept it as field evidence; tolerance only.
- **Per-row work in views** (task 5):
  - menus read state.json and every task note;
  - `SendMenu` evaluates its targets twice per row, each reading every beacon file;
  - `terminal(project:session:)` is called from view bodies and does I/O (`ProjectPanes.swift:540`, `AllProjectsPanes.swift:132`).
- **The hidden altitude keeps rendering** (`RootView.swift:10-21`, opacity 0, ENH-45 "still to do"). `ProjectMapPane` builds `mapLayout` on every snapshot while you're inside a project.
- **No lazy containers in the list views.** Each row has a `MenuProbe` that installs an `NSEvent` monitor. Dragging the divider re-instantiates every row of the session list.
- **Broad invalidation:**
  - hover state is a `String?` on the model (seven of them, forced by the no-`@State` rule), so every reader redraws;
  - `TaskCard` runs an uncached `GreedyLines.wrap` (an `NSString.size` per word prefix);
  - `AdaptiveColumns`' `ViewThatFits` builds every tile three times;
  - `PackedColumns` measures each tile twice.
- **Chat:**
  - hidden feeds still read and ingest every ~2 s;
  - every PTY chunk of every attached chat hops to main;
  - `screenLines`/`columns` take two full terminal snapshots for the dimensions;
  - `ChatToolDescriber.preview` regex-strips every line of a tool result to keep 8 (24 ms for a 20k-line Read);
  - `ChatLog.steps` is an O(n) flatMap on every hook event;
  - `ChatLinkHover` hit-tests and builds an `NSLayoutManager` per mouse move;
  - `ChatMemo` is count-limited only, and `ChatPictureCache` is unbounded.
- **Editor:**
  - `blocksField` rebuilds every table and image decoration on any transaction (`duo-editor.js:1587-1590`), with `JSON.stringify` twice per table;
  - images are read and base64-encoded on main for every widget creation, uncached;
  - `diffLines` keeps a trace that could reach hundreds of MB for a fully rewritten 10k-line document;
  - every open snapshots the file into history (SHA-256, a blob, an index rewrite) on main.
- **Search queries:**
  - every query loads all vectors with a `Data` copy per row;
  - exact mode runs `instr(lower(text))` over all chunks;
  - `GitIgnore.match` compiles a regex per file per pass;
  - `Embedder` reads outputs through `NSNumber` subscripts: 12,288 allocations per batch.
- **The editor's web view at launch** (above) and **every saved browser tab loaded at launch** (C-83).

## Maintainability

### Build time and warnings

Measured in this work tree with Swift 6.4 (swiftlang-6.4.0.34.1) on the Mac mini, under the GPU lock, while other sessions were working (load average about 5). F-287 has the numbers.

| Build | Time |
|---|---|
| Cold `swift build` (debug; SwiftPM's dependency cache warm) | 44 s |
| `scripts/bundle.sh release` | 116 s; app 100 MB (binary 28 MB, Resources 68 MB of which the model is 64 MB) |
| Touch one DuoKit file (`AppModel.swift`) | 21 s |
| Touch `DuoControl/Actions.swift` (every target depends on it) | 38 s |
| No-op build | 0.2–2 s, **but 6 of 14 no-op runs recompiled the whole package (124 steps, 17–27 s)** with nothing changed |

**The no-op rebuilds.** I couldn't isolate the cause. SwiftPM 6.4 builds with Swift Build (`.build/out`, `manifest.pif`), and SwiftTerm's build-info plugin re-ran each time it happened. They happened after idle gaps of 30 s and 180 s, but not after 90 s. Every session's edit-build loop pays this, and the video session saw `bundle.sh` take 126–564 s. Next step: compare `--build-system native` in a scratch path (task 15).

**Type-check hot spots** (`-warn-long-function-bodies=200`; 13 over the limit):

| ms | Function |
|---|---|
| 4,329 | `ChatPerf.perform(_:on:)`, `Debug/ChatPerf.swift:18` |
| 2,214 | `run()`, `DuoChecks/main.swift:27` |
| 1,739 + 1,727 | `matches(_:search:in:)` and an expression at line 68, `AllProjects/SessionListFilter.swift:53` |
| 834 | `FixtureHarness.perform`, `Debug/FixtureHarness.swift:95` |
| 833 | `RightPane.body`, `Project/ProjectPanes.swift:564` |
| 617 | `chatChecks()`, `DuoChecks/ChatChecks.swift:33` |
| 420 | `ConsoleTabStrip.tab(_:short:)`, `Project/ConsoleTabStrip.swift:79` |
| 415 | `AppModel.perform`, `Control/AppModel+Control.swift:37` |
| 334 | `VideoTargets.apply`, `Debug/VideoTargets.swift:30` |
| 229–259 | `HomePane.body`, `AllProjectsPanes.swift:670` body, `DocxView.body` |

**19 compiler warnings,** worth fixing as one S task:
- **`ChatPaste.swift:215,243`, a real one:** "weak reference will always be nil". `ComposerProbe` assigns a fresh `Coordinator` to the composer's `weak var coordinator` (`ChatComposerView.swift:365`), so it is gone at once. The five paste checks (`ChatChecks.swift:922-928`) therefore run the composer without its coordinator, which is less than they claim. Hold it strongly in the probe.
- **`Explainer.swift:192`:** a main-actor static read from a `Sendable` closure, an error in Swift 6 language mode.
- **Unused results:** `ask(_:sig:)` ×2 (`ChatKeys.swift:127`, `ChatReviewCard.swift:268`) and `map` (`AppModel+Search.swift:31`).
- **Captures that differ from the outer scope:** `AppModel+Convert.swift:159` (weak self) and `Explainer.swift:239` (unowned).
- **Ten deprecated `Text + Text`** (macOS 26).
- **One each:** `init(cString:)` (`DocumentEditor.swift:529`), `accessibilitySetValue` (`Anchors.swift:24`), a duplicate pattern (`FixtureHarness.swift:238`, the second `zoom-out`), a localized interpolation (`GalleryView.swift:43`), an unnecessary `nonisolated(unsafe)` (`ChatSession.swift:581`), and `'shown' mutated after capture` (`ChatChecks.swift:143`).

### DuoChecks gaps

**The search golden set runs only on Geoff's main checkout** (`main.swift:752-758`).
- It needs the untracked `Spikes/S13CoreML/out/bge-small-fp16.mlpackage` and `~/repos/smol-sim-search/tests/fixtures`. Every work tree reports 1,260 checks where main reports 1,266, and search regressions slip past branch checks.
- That matters now, since `fix/idle-cpu` changes the indexer.
- Fix: point it at `Models/bge-small-fp16`, reassembled as `bundle.sh` does, plus a small committed golden fixture, and print "skipped" instead of passing silently.

**Logic that broke before and has no check.** These are pure logic and checkable without a UI; the full table of 25 regressions is in the reviewer's notes, and 20 of them are covered.

| Finding | What broke | The check to add |
|---|---|---|
| F-108 | A stale `DUO_TOKEN` made the pre-edit hook refuse every Write | The hook's decision, extracted into DuoControl and tested: still broken today (C-80) |
| F-51 | A drag-drop confirmation was lost to an app-modal NSAlert | A source scan: no `NSAlert(`/`runModal` outside an allow-list. Two remain today. |
| F-169 | Needs-you orange failed AA on the tinted toolbar | Contrast ratios computed from the generated tokens |
| F-272 (F-263, F-264) | Rename lost unsaved text; `/private` ids disagreed | `docID`/`plainPath` normalization, today script-only (`check-editor-host.sh`) |
| (new) | Value-less flags swallowing an argument | Cross-read every handler's `inv.has("x")` against the verb's declared flags |
| (new) | The editor bridge's names | Swift's `duo.*` calls ⊆ `window.duo`'s exports |

**Coverage of the plumbing.**
- About 50 of 182 verbs appear as literals in DuoChecks.
- `ControlServer`/`ControlClient` framing, tokens and the 1 MiB cap have no tests.
- The ENH-46 root scan (`main.swift:1809-1826`) greps only `RootView.swift` for chat and terminal reads. It misses `DuoToolbar`, which sorts all sessions twice per body through `needsYouElsewhere`, and the overlays. It also misses any broad `fixture` read.

**Node checks.** The five `scripts/check-*.mjs` editor checks need `playwright-core` from `/tmp/pwc` and run in no gate. `check-chat-perf.sh` (the DL-137 budget) isn't in any skill. There's no `scripts/check-all.sh` and no CI.

### Scripts

- **No shared library.**
  - The scratch-workspace block is pasted into 4 check scripts.
  - The `env -u DUO_SUPPORT_DIR … run-live.sh`, crop and compare sequence repeats in 3–4 more.
  - The shebangs split 14 bash and 10 zsh.
  - `scripts/lib.sh` should hold `mk_ws`, `iso_env` (with `mktemp`), `live`, `crop_compare` and `stop_pid`.
- **Fixed `/tmp` paths collide between parallel sessions** (CONFIRMED):
  - `check-docx.sh` and `check-deck.sh` both use `/tmp/d-dx` and `/tmp/d-dx-cc` (`check-docx.sh:15-16,33`);
  - `check-editor-host.sh` uses `/private/tmp/pcf-host-1`;
  - `check-paste-image.sh` runs `rm -rf` on fixed paths.
- **Duplicate pixel tools.** Three PNG writers (`crop.py:45`, `chat-crop.py:23`, `filmstrip.py:22`). `pixels.py`, `crop`, `edges`, `ink`, `samepng`, `chat-crop`, `filmstrip` and `chip-measure` should be one `px.py` with subcommands.
- **Fixture generators** paste the same `ts`/`iso`/`epoch` helpers (`make-chat-fixtures.py:20-29`, `make-chat-polish-fixtures.py:19-28`, `make-chat-slash-fixtures.py:21`).
- **The 50 chat boards are listed in three places** (`ChatTargets.boards`, `check-chat.sh`, `fixture-chat/*`). They agree today, with no guard.
- **`--then` splits on commas,** hence the `⸴` hack in `check-paste-image.sh:21`. Accept newlines or `--then-file`.
- **`gen-video-tokens.py`'s output has no staleness check,** unlike the other two token generators.
- **Verdicts for all 53 scripts.**
  - Keep 38.
  - Record-only 14: `check-merge.mjs`, `check-editor-source.mjs`, `check-editor-state.mjs`, `check-task-note.mjs`, `check-paste-image.sh`, `check-task-paste.sh`, `check-docx.sh`, `check-deck.sh`, `icon-proof.swift`, `github-fixture.sh` and the four `make-*` fixture generators. Wire the useful checks into `check-all`.
  - Remove 1: `chip-measure.py`.

### Docs drift (CONFIRMED)

- **`docs/design/README.md`'s status column is stale.** A session that reads "not built" for a built feature may build it again. It says:
  - chat-mode, chat-slash, github and home-evolution: "not built";
  - explanatory-tooltips: "approved, not built";
  - chat-paste: "building".

  Per `docs/design/system/surfaces.md` and the findings, all six are built. Four folders are missing from the table: `dock-badge-handoff`, `multi-window-studies`, `slice2-handoff` and `small-features-handoff`.
- **`surfaces.md:63`** gives `wireframes/group-page.html`; the file is in `docs/design/build-handoff/screens/wireframes/`.
- **CONTRIBUTING:**
  - It lists 6 `--state` names; there are 169.
  - It says "`swift run` inside each" spike; 4 of 9 have a `Package.swift`.
  - It omits the director skill, `video/`, `docs/guide/` and four `Vendor/` folders.
- **The About box:** `Vendor/docx-viewer/README.md:8` and `codemirror/build.sh` promise one, and none exists (C-82).
- **`PROJECT.md`** has an empty goal and next step.
- **`docs/cli/duo2.md` is current;** DuoChecks enforces it. I spot-checked 10 verbs.

### Records hygiene

- **`scripts/check-records.sh`** checks that every id from both parents survives a merge and that none is duplicated. It misses:
  - dangling references;
  - a collision where two records took one number and only one survived;
  - truncated bodies;
  - the acceptance ledger.

  It runs from no hook or CI.
- **Gaps below the maxima:** F 14, Q 33, C 15, ENH 11, DL 3. `git log -G` finds no heading ever written for the F gaps, so they look reserved rather than lost.
- **Misplaced row:** Q-168 sits at the end of the Concerns table, not in Open questions.
- **Numbers taken during this review:** two other sessions took Q-183, Q-184 and DL-174 while it ran. The shared-numbers rule worked, but only because everyone re-reads every branch. A tiny `scripts/next-record.sh <kind>` that does the `git fetch --all` and scans every ref and work tree would make it one command. My scan is `maxrec.py`, under the method below.

### Dependencies and licences

| Dependency | Pin | Licence | In the repo | In `Duo.app` |
|---|---|---|---|---|
| SwiftTerm | revision `6a955b06`, untagged `main` ("2.0 line") | MIT | only in `.build/checkouts` | **no notice** |
| swift-argument-parser 1.8.2, swift-png 4.5.1, `h` 1.0.1 | `Package.resolved` | Apache-2.0 | — | not linked on macOS: they are SwiftTerm's own dependencies (via its `PortableGraphics` trait), not stale entries |
| Sparkle | 2.10.0, sha256 in its README | MIT plus bundled externals | `Vendor/Sparkle/LICENSE` | **no notice** (`bundle.sh` `ditto`s the framework only) |
| CodeMirror 6 and Lezer | exact pins plus lockfile; esbuild 0.28.2; `dist/cm6.js` is byte-reproducible | MIT | `dist/THIRD-PARTY-LICENSES.md` | **no notice**. `@codemirror/autocomplete` is imported but undeclared (hoisted). |
| pptx-renderer 1.3.0 (patched) | vendored | Apache-2.0; bundles ECharts (Apache-2.0), JSZip (MIT), mtx-decompressor (MPL-2.0) | `LICENSE`, `THIRD_PARTY_NOTICES.md`, `licenses/` | **no notice**; 1.83 MB unminified |
| @file-viewer/docx 0.3.33 and JSZip 3.10.1 | vendored | Apache-2.0; MIT or GPLv3 | yes | yes, the only notices copied (`bundle.sh:60`) |
| swift-markdown-engine `1c2e76c` | vendored | Apache-2.0 | yes | unused (remove) |
| bge-small-en-v1.5, Core ML fp16 | rev `5c38ec7c`, checksummed parts (DL-40) | MIT | `MODEL_CARD.md` | **no notice** |
| Remotion 4.0.529, React 19.3.0, TypeScript 7.0.2 (`video/`) | exact | Remotion License: free for individuals and companies of up to 3 people | no note in `video/` | not shipped |
| Video voice, score and ACE-Step models | `models.lock.json`, outside the repo | non-commercial | — | not shipped; acceptable per Geoff's standing decision |

- **SwiftTerm risk:** its revision lives only on an untagged `main`. A force-push upstream would make it unfetchable. A fork or tag would pin it.

### Repo size

- **Tracked:** 266 MB in 2,361 files, and `.git` is 229 MB after 693 commits in 10 days.
  - PNGs are 171 MB of it, 170 MB of them in `docs/`.
  - `findings.md` has 299 revisions and grows fast (516 KB).
- **Duplicate PNGs:** 55 byte-identical groups waste 25.4 MB, mostly study ↔ handoff copies of the same board (github-study 8.1 MB, task-board-study 6.4, home-evolution 5.6, project-task-cx 3.4).
  - A decided study can keep a README pointing at its handoff.
  - Handoff `screens/` stay untouched (CLAUDE.md).
- **Models:** 64 MB, needed by DL-40. Each model swap adds 63 MB more to history, so move to a release asset or LFS before the next one.
- **`.git` debris:** 53 `tmp_obj_*` files left from interrupted concurrent writes; a `git gc` clears them.
- **`.claude/worktrees/`** is excluded only by `.git/info/exclude`, which a clone doesn't get. Add it to `.gitignore`.

### Work trees and branches

Listed only; nothing was deleted. The director decides.

20 work trees use about 25 GB:
- each has its own `.build`, about 1.1 GB;
- `video-pipeline` is 9.1 GB, with a 3.1 GB `.cache` that has no GC.

| State | Work trees |
|---|---|
| Active | `codebase-review` (this), `fix-idle-cpu`, `research-voice-input` (4 unmerged commits) |
| Merged, last commit today | `session-glyphs`, `new-task-fold`, `new-task-fold-1b`, `explanatory-tooltips`, `video-pipeline` |
| Redundant (its one commit is already on main) | `video-fixtures` |
| Merged, 1–3 days old | `fix-chat-slash-below` (10-11), `task-pane-fixes`, `task-send` (10-09) |
| **Stale, merged, 4+ days** | `session-row`, `source-links`, `test-model-out` (10-08); `task-board`, `multi-window` (10-07); `tb-main-check` (a detached scratch checkout, 10-07); `duo-v2-user-docs-3e76b8` (10-06) |

- **Merged branches with no work tree:**
  - local: `feature/github`, `staging/github-merge` (268 behind), `fix/chat-footer-c78`, `research/claude-code-mods`, `research/editor-approach`, `editor-host-cases`, `editor-host-show`, `editor-web-2`, `fix/task-pane`;
  - remote: `origin/claude/menu-bar`, `scripted-instances`, `tables`.
- **Unmerged and old:**
  - `proto/chat-finer-rows`: 1 commit, 384 behind, 10-07;
  - `origin/prd/legacy-sessions`: 5 commits, 692 behind, 10-03.
- **A leftover tag:** `video-pipeline-pre-rebase`.

## Intro video pipeline

Geoff asked, in his words: "see if the approach to intro video script management and generation needs a refactor to improve performance, reduce errors, or improve the human<>agent collaboration on iterative video development."

**Sources.**
- The `video/` code at main (which includes `video/pipeline`).
- 88 commits touching the video paths, all from 10 to 12 Oct.
- The INTRO VIDEO session's transcript (843380b2). Over the two days Geoff wrote about 20 chat messages, left 40 Doc comments and answered 22 button rounds.
- The fixtures session (3174260c).
- Artifact timestamps in the `video-pipeline` work tree.
- The video session's own answer to "what costs you most per iteration".

No renders were run: they need the GPU lock and take 23 minutes.

### Top 3

| # | Change | Size | Risk | Evidence |
|---|---|---|---|---|
| 1 | **Render per scene, cached, with a `--scene S7 [--draft]` preview.**<br>• Key each scene's mp4 on its slice of `timeline.json`, the hashes of its captures and audio, and the hashes of `src/**` and the tokens.<br>• Render only changed scenes (`remotion render --frames=a-b`) and join them with `ffmpeg -c copy`.<br>• Mix and loudnorm the audio once for the whole film, so the score and ducking stay continuous across scene edges (the video session's condition).<br>• Generate the score bed once at a fixed long length and trim it: its key includes the film's length today (`score.mjs:18-19`), so every length change makes a new 100 MB bed and the music can change under review. | M | Low–med | A cut is a full render, ~22–24 min for the 7:13.7 film (13,011 frames at ~9 fps), plus waits for the GPU lock and the fine-tune windows. The video session ranks this its #1 cost: "I usually only need to see one scene". Over two days: 17 full builds, 17 stills-only builds, 31 direct `remotion` calls, and 0 uses of the existing `--draft`. Expected: a one-scene edit drops from ~23 min to ~3–5 min (estimate, not measured). |
| 2 | **Cameras relative to anchors, with a stale-anchor check.**<br>• Write cams as `on: <anchor>` plus padding instead of absolute window rects.<br>• When an anchor's frame moves between captures, name the cams and beats that used it.<br>• Key captures by the PNG's own hash downstream, so an app rebuild that doesn't change a picture doesn't cascade into re-planning. | M | Low | The video session's #2 cost. 11 of 50 cams are absolute rects, e.g. S10 at y250/y196/y290, so the Tasks fold and now DL-174 force recapture, re-measure, re-frame and beat-fit. The capture key hashes the whole Duo binary (`capture.mjs:12`), so any app rebuild recaptures all 71 states (~380 s), as after the unrelated merge 62bedcd. 8 of 50 rework commits were "the app changed under the video". |
| 3 | **A no-GPU check stage that runs first, and a Doc-sync tool.**<br>• Split `build.mjs` into check → prepare → render.<br>• The check stage verifies every beat's word is in its line, every named state exists in `VideoTargets.screens`, the transition and pause indices, and that every `requires` item names the beat or state that realises it (so `built` is derived, not hand-set). It also prints a line diff of the script since the last build.<br>• Give lines stable keys instead of positional `line: N`, or write a sync tool that aligns old and new exports and rewrites indices and `shotSha`.<br>• Record the Doc revision in `script.md`'s header so the next sync reads only what changed (`sinceRev`). | M | Low | 8 of 50 rework commits were hand-syncing the Doc, `script.md` and `shots.json` (e.g. 1de2756 renumbered ~20 `line:` indices by hand). Another 6 were "a shot note wasn't built". The video session ranks this its #3 cost: silently error-prone, and a Doc edit shifts every beat's word timing. "S11-1 has no word 'date'" surfaced only after voicing. |

### The pipeline as built

1. **Doc → `video/script.md`.** By hand: the agent reads the Doc and edits `script.md` with heredocs.
   - `README.md:5` says "each build exports it", but no code in `build.mjs` or `pipeline/` does (CONFIRMED). This doc drift should be fixed with task V3.
   - DL-169 and `docs/research/intro-video.md:261` still cite the archived v1 Doc.
2. **Parse and join** (`pipeline/script.mjs`, `build.mjs:34-55`). It stops on an orphan shot, an empty `requires`, or a `shotSha` that differs from the hash of the Shot paragraph *and all prose after it*.
3. **Voice** (`voice.mjs`). Cached per line on (text, setup): a text edit re-voices one line; a voice, reference or engine change re-voices all 43.
   - Speech is checked by Parakeet (WER ≤ 0.05), with up to 3 more seeds per failing line.
   - VoxCPM takes ~10 min for 43 lines.
4. **Captures** (`capture.mjs`, `Debug/VideoTargets*.swift`). Keyed on the whole app binary plus all fixture bytes. About 5.4 s per state, 71 states.
5. **Plan** (`plan.mjs`). It places cams, clicks and marks on spoken words. It isn't cached, and it isn't deterministic: S11's end card reads `gh release list` and `new Date()`.
6. **Score** (cached on length), **wallpaper** (cached; it cost 20 min a render before 13ac071), **lint**, then **12 stills** (22–29 s when everything is cached).
7. **Render** (the whole film every time), then loudnorm, a contact sheet and `report.md`. A 720p copy and `SendUserFile` are by hand.

### What caused rework

50 of the 88 commits were rework:

| Cause | Commits | Shas |
|---|---|---|
| Doc ↔ `script.md` ↔ `shots.json` hand sync (renumbering, `shotSha`) | 8 | 19074e2, 1de2756, 42ac46e, a0b1db1, a464d89, eb193d7, 724cc01, c703f37 |
| Fixture data wrong or unstable | 8 | 9ede517, 5d13cdb, 24a695c, 4b435e9, cc7ddea, 49e976f, c2305eb, 50566c6 |
| App changed under the video, or a note misdescribed the app | 8 | 556b960, db01f74, a8ef8ff, 10d2ced, 6de8c28, b47274a, 9353f61, 838fc75 |
| A shot note not built, or Geoff's comment fixes | 6 | 679f701, 7b3ce42, 5b0ddfa, 4176a9b, d7e24ce, ea4347b |
| Visual-craft rejections (wallpaper, callouts) | 6 | d3181b4, ee52a4b, d851aac, 7dd9073, 965dd0e, 4fd5017 |
| Narrator swaps (5 narrators in 3 days) | 4 | cd4994d, 33b11a9, 3e8f057, 844c6bb |
| Pronunciation and the speech check | 4 | 520b906, e8148a9, 2574ff7, f5d091f |
| Cuts vs transitions | 3 | 00b7685, 56cb98e, 9d1d715 |
| Render crashes or speed | 3 | 13ac071, 0650933, 8694272 |

What Geoff had to repeat, from the transcript:
- **Looks rejected as low effort, 9 times:** the wallpaper ×4, callouts ×4 ("extremely low effort", "sloppy and amateur", "still just visually boring and bad"), and the v2 prototype.
- **"What I wrote wasn't built", 6 times.** One example: "My script explicitly said I wanted an animated transition…"
- **4 voice direction changes** behind 7 sample rounds.
- **3 rounds of fixture content.**

His taste lives in per-user memory files (`feedback-video-visual-craft.md` and others) that a fresh or compacted session may not read. A committed `video/style/taste.md` holding his rejections, in his words, would travel with the repo.

### Collaboration

1. **Edits don't notify.** A Doc edit tells no one. Only a comment sent with "Send to Claude" does, so Geoff has to say "I made a number of changes… review them all".
2. **The full Doc is ~84 KB of XML.** `sinceRev` was used, but no revision bookmark is kept in the repo.
3. **Feedback means watching the whole film.** Each cut is a 7-minute mp4 (15 were sent), and Geoff watches all of it to find the one change.
   - Add an `out/review.json` per build with each scene's start, end and still, its `requires` items, and the timecode where each is realised.
   - Add a 480p clip per changed scene, with ✓ or ✗ marks and the words that triggered a re-voice.
   - Publish it as a separate Build report artifact or Doc tab. Don't put it in the script tab, which Geoff edits live.
4. **A promise the build breaks.** `script.md:14` tells Geoff "a `> note` … is ignored by the build". `script.mjs:45` keeps `> notes` after `Shot:` and hashes them (`build.mjs:47`), so editing a note stops the build (CONFIRMED). S7 carries 24 such lines.
   - Either hash only the Shot paragraph and its list items, as the rule promises, or change the rule's wording.
   - Store the hashed text, so a mismatch prints a diff rather than a bare hash.
5. **Live drift today.** I checked the Doc at rev 4617 against `script.md`.
   - All 43 lines, 12 topics and the lexicon match.
   - S7's two note bullets are in the opposite order, so a re-export would trip its `shotSha`.
   - Report placeholders still read "(title) (about _ s)" for S1 and S2.

### Video maintainability and risks

- **A silent narrator fallback.** A missing or mistyped `DUO_VOICE_JSON` falls back to the house voice with only a log line (`voice.mjs:13-14`). The Qwen and VoxCPM cuts differ by 39 s, so a wrong narrator changes every timing. Fail instead.
- **A machine-bound default narrator.** It depends on `/Users/geoff/repos/duo-voice` (venv, LoRA) and a 25 GB `~/Library/Caches/duo-video`. A clean checkout can't reproduce the cut. That's acceptable for a one-person film, but it should say so in the README.
- **Captures ship in the release app.** The video's 79 states (834 lines of `VideoTargets*.swift`) and 49 `video.*` anchors are part of the release binary. Nothing on the app side notices a removed anchor. See task 11 for the harness gate.
- **Dead code:** `src/lib/Callout.tsx`, the `desk`/`card` kinds, `Turn.tsx`, `many`, the stand-in transitions, `wallpaper-options.mjs`, `score/mix.py`, `voice/experiments/` and `video/archive/` (see [Abandoned code](#abandoned-code)).
- **No `typecheck` script, no test, no CI.**
- **Fixture duplication:** 13 chat transcripts total 4.7 MB, with a 558 KB line repeated in about 10 of them.
- **Cache hygiene:** 515 captured PNGs in `.cache`, of which 71 are live (86% stale), and 3.1 GB with no GC. `fxKey` is recomputed 71 times per build (`capture.mjs:22`).
- **Remotion's licence:** free for individuals and companies of up to 3 people. Larger companies need a Company License, and the terms change at 5.0. Duo doesn't ship Remotion, but anyone at a larger company who renders the film needs one. Add a note to `video/README.md` and decide whether the work Mac's employer applies (Q-186).
- **Hand-rolled lock wrappers.** The GPU lock's `locked.sh` and `held.sh` live in session scratchpads, and the lock has no staleness check. Commit one `scripts/gpu-lock.sh` that records the pid and refuses a live owner but clears a dead one.

## Bugs and risks

Each CONFIRMED item was re-checked at the line given. The records: C-79 is the idle burn; C-80 to C-83 are new concerns; Q-185 to Q-188 are questions for Geoff.

### Correctness batch (S each)

| # | Bug | Where | Record |
|---|---|---|---|
| 1 | **`duo2`'s pre-edit hook fails closed.** Any app-level error except "not open" (a stale token, an unreadable request) denies Claude's Write/Edit with "Duo couldn't make this change": the F-108 symptom, still live. | `Sources/duo2/main.swift:107-113` | C-80 |
| 2 | **Env endpoints never fall back.** `ControlEndpoint.discover` returns `DUO_SOCKET`/`DUO_TOKEN` without trying `endpoint.json`. A session that outlives a Duo restart (Remote Control, `--bg`) has every verb refused until it restarts. | `DuoControl/Control.swift:34-41` | C-80 |
| 3 | **Value-less flags swallow the next word.** `hidden`, `anyway`, `not-now`, `cancel` and `fetch` aren't in `Invocation.switches`. So `duo2 files --hidden docs` loses `docs`, and `duo2 file convert --anyway a.docx` loses the file. | `DuoControl/Actions.swift:482`; read at `AppModel+Control.swift:176,803,910`, `BrowserTabs.swift:788`, `AppModel+RepoControl.swift:19` | C-80 |
| 4 | **The properties fold is never remembered.** The page posts `propertiesFolded`, but Swift routes only kinds with the prefix `"property"` ("properties…" doesn't match), so the message falls through to the selection guard and is dropped. `rememberFold` is unreachable. | `Editor/DocumentEditor.swift:398-401`, `AppModel+Tasks.swift:579` | C-81 |
| 5 | **Task menus rewrite a note under unsaved editor text.** Rename, archive, status, link and add-to-task read and write the file without flushing the editor: `flushTask` has had no caller since 28123ad. `moveCard`, `addReference` and `continueTasks` do flush. The menu and a board drag also use different writers for one status change. | `AppModel+TaskMenu.swift:48`, `AppModel+Tasks.swift:264-267`, `AppModel+Board.swift:99` | C-81 |
| 6 | **Earlier turns drops live turns.** `ChatFeed.history` is set once at attach and never extended, and `loadEarlier` replays from that snapshot and replaces `items`. Turns since attach vanish after a click. | `Chat/ChatFeed.swift:19,73,93-104` | — (task 4) |
| 7 | **Two dead-end buttons.**<br>• "Claude Code not found" offers Open Settings…, which toasts "Settings isn't built yet", though Settings exists.<br>• "Folder missing" offers Locate Folder…, which says it's waiting on a design, though `model.locateFolder` exists and the tile uses it. | `Project/ConsoleStates.swift:182,189` | — |
| 8 | **`GitIgnoreOffer` runs `/usr/bin/git` directly,** with no timeout. `GitTool.gitPath` exists to avoid the "install developer tools" dialog (C-53). | `Live/GitIgnoreOffer.swift:40-41` | — |
| 9 | **Two system alerts remain:** `DuoAlert.present(NSAlert…)`. CLAUDE.md: "Duo never shows a system alert". `DuoAlert` also polls every 0.5 s, forever, until a visible "Duo" window exists. | `AppModel+Files.swift:271`, `AppModel+Search.swift:377-378`, `DuoAlert.swift:10-17` | — |
| 10 | **`@FocusState`,** against the Xcode-free rule (DL-30). | `Navigation/PeekView.swift:7` | — |

### Risks

- **No recovery when a WebContent process dies** (C-81). There is no `webViewWebContentProcessDidTerminate` anywhere (CONFIRMED). If the editor's process crashes:
  - every open document's unsaved text (up to the 1 s autosave), caret, undo and conflict-kept state is lost;
  - the page stays blank while `pageReady` stays true;
  - `saveNow` treats the error as nothing to save.

  This contradicts DL-77's "never lose either side". The viewers and browser tabs go blank the same way.
- **Closed browser tabs and closed chats are never released** (C-83).
  - `WebTab` registers itself as its own script handler (`BrowserTabs.swift:140-141`), and `closeWebTab` only drops the dictionary entry (417-424). The tab, its `WKWebView` and its WebContent process stay alive, and audio, video and downloads keep running.
  - `ChatStore.forget` has no caller, so a closed chat keeps its 0.15 s timer and its whole parsed transcript (C-79 (c) covers this one).
- **Third-party notices aren't shipped** (C-82; see the licence table).
- **DL-3 holds for top-level navigation only** (Q-185).
  - There is no `WKContentRuleList` (F-33 said both layers are needed) and no CSP on `editor.html`.
  - A local HTML page can load remote scripts and images.
  - A Markdown note with a remote image fetches it.
  - An allowed site can embed any iframe (`BrowserTabs.swift:195`).
- **`duo2 browser` widens itself** (Q-188, SUSPECTED as a design gap). `AllowedSites.allows` admits any `file:` URL (`BrowserTabs.swift:19-26`), and `browser allow <host>` adds a site with no prompt (`AppModel+Control.swift:272`). A prompt-injected session could allow any host, then read pages in the signed-in store, or read local files outside Claude's sandbox.
- **Main-thread stalls** (CONFIRMED in code; magnitude unmeasured):
  - `ClaudeLocator.lookUp` runs `/bin/zsh -lc 'command -v claude'` with `waitUntilExit` and no timeout at launch, when claude isn't in the 4 stock paths (nvm, npm, Volta) (`Terminals.swift:43-50`).
  - `ClaudeVersion.known` and `RemoteControl.supported` can block up to 3 s when cold. They aren't single-flighted.
  - `GitHubAccess.sign()` runs `gh auth status`, up to 2 × 10 s, in `showGitHubProject` (`AppModel+GitHubProject.swift:64`).
  - `Migrator.cliUnderstandsRelocation` scans the 240 MB `claude` binary in 4 MB chunks, uncached (`Migrator.swift:102`).
  - `Migrator.apply`/`verify` re-read and JSON-parse relocated transcripts.
  - `duo2 session show` parses a whole transcript for 3 turns (`AppModel+Control.swift:204`).
  - Docx and pptx outlines unzip and parse on main (`AppModel+Docx.swift:112`, `AppModel+Slides.swift:42`), and `Docx.readability` parses `document.xml` on every open and reload.
- **Unbounded disk growth** (CONFIRMED): nothing ever deletes these.
  - `events/<id>.jsonl` holds full hook payloads, tool inputs and file contents included, and `*.settings.json` sits beside it.
  - `chat-images/` gets a Quick Look PNG per preview.
  - The archive fingerprints every listed transcript's sidecars each minute.
- **Lost updates** (SUSPECTED): read-modify-write with no lock.
  - `.duo/sessions.json` between the background `/cd` loop (`AppModel.swift:430-441`) and main-thread writers.
  - The archive manifest between `sync` and `forget`.
  - `HangLog.append` on a concurrent queue (`HangMonitor.swift:79,88`).
- **`GitTool.run` can wait out its timeout on a fast exit.** It sets `terminationHandler` after `p.run()`, and `group.wait()` after a timeout is unbounded (`GitTool.swift:93-108`). SUSPECTED.
- **Emoji folder names** (SUSPECTED, high confidence). `ClaudeStorage.encode` maps per Unicode scalar; Claude's regex runs on UTF-16 units, so an astral character encodes `-` where Claude writes `--`. DuoChecks tests BMP characters only (`main.swift:427-431`). Verify with a real `claude -p` in an emoji-named folder.
- **Two sessions with the same title in one project** may collide (SUSPECTED). `Session.id` is `project/name` (`Fixture.swift:51`), and list clicks resolve by name.
- **Isolated test instances may share `UserDefaults`** (search recents, the window frame) with Geoff's Duo (SUSPECTED). Neither is guarded by `SupportFolder.isIsolated`.
- **Minor:**
  - `templateVerb`'s `default:` performs the destructive reset (`AppModel+Control.swift:741`), so a new template verb routed there would reset a template.
  - The socket is `chmod 600`ed only after `.ready`.
  - There's no `SIGPIPE` handling in `ControlClient.send`.
  - The 1 MiB request cap closes the connection without a reply.
  - `--stdin` on a TTY blocks forever.
  - `Installer` writes `~/.claude/CLAUDE.md` with `.atomic`, which would replace a symlink with a file (SUSPECTED).

## Proposed build sequence

Each task is scoped for one Sonnet build session: files, the check that proves it, and what could break. The order puts safety and cheap wins first and the large extractions last. Tasks 1–5 can run in parallel; tasks 6 and 13–14 touch `LiveSnapshot`/`AppModel` and should run alone.

| # | Task | Files | Proven by | Could break |
|---|---|---|---|---|
| 0 | **Idle CPU (C-79 a, b, c).** *In flight: `fix/idle-cpu`.* | `HookEvents.swift`, `LiveSnapshot.swift:140,302`, `SearchService.swift`, `SearchIndex.swift`, `Chunker.swift`, `WordPiece.swift`, `AppModel.swift:482`, `ChatFeed.swift`, close paths, `HangMonitor.swift` | DuoChecks counters: no parse or tokenize for an unchanged file; `fixture` assigned 0 times across idle refreshes. Re-run the `rel-events`/`rel-churn`/`rel-idle` runs below (≤ 2% CPU after 60 s). | Needs-you detection when a hook log is replaced; search freshness for a file edited constantly (it now waits to settle) |
| 1 | **`duo2` control plane (C-80).**<br>• The hook fails open on anything but a successful edit.<br>• Env endpoints retry `endpoint.json` on connect failure or "wrong token".<br>• Flags declared per action, with a check that every `inv.has` flag is declared. | `Sources/duo2/main.swift`, `DuoControl/Control.swift`, `DuoControl/Actions.swift` | New DuoChecks for the hook decision (F-108's case), env fallback, and a flag cross-read; `scripts/check-sandbox.sh` | Hook behaviour inside Claude's sandbox; scripts that pass a value after one of those flags (none found) |
| 2 | **Document safety (C-81).**<br>• Fix `propertiesFolded` routing; decode the bridge into an enum.<br>• Add WebContent termination handlers that reload and re-show, keeping dirty text.<br>• Wire `flushTask` into every task-note writer; make menu and board one writer.<br>• Save's `isEnabled` uses `editorIfLoaded`. | `DocumentEditor.swift`, `HTMLViewer.swift`, `DeckViewer.swift`, `DocxViewer.swift`, `BrowserTabs.swift`, `AppModel+Tasks.swift`, `AppModel+TaskMenu.swift`, `AppModel+Board.swift`, `Commands.swift:173` | DuoChecks: bridge names ⊆ `window.duo`; a harness action that calls the termination delegate, then asserts the text is back; `check-editor-host.sh`; WebKit processes at launch = 0 (measured 3 today) | Editor restore after a crash; task note writes racing the editor's autosave |
| 3 | **Lifetimes (C-83).**<br>• A weak script-handler proxy, with `removeAllScriptMessageHandlers` on close.<br>• Restored web tabs load on first show.<br>• Viewer timers stop when hidden.<br>• `ChatStore.forget` on close, if `fix/idle-cpu` hasn't done it. | `BrowserTabs.swift`, `AppModel+Restore.swift:117-122`, `HTMLViewer.swift`, `DeckViewer.swift`, `DocxViewer.swift` | A DuoChecks weak-reference check that a closed `WebTab` deinits; `leaks` on a test instance; the WebKit process count after closing tabs | Popups that hand back to their opener (`PopupPlacement`); restoring a tab that was on screen |
| 4 | **Chat memory (ENH-23 d) and Earlier turns (bug 6).**<br>• Index line offsets, parse back to 50 prompts, keep offsets rather than records.<br>• `loadEarlier` re-reads from the file, including live turns.<br>• Hidden feeds ingest nothing and catch up in `wake()`.<br>• One shared feed timer, with tolerance. | `ChatFeed.swift`, `ChatLog.swift`, `ChatSession.swift` | `scripts/perf-chat.sh` and `check-chat-perf.sh` budgets; a ChatChecks case for Earlier turns after a live turn; footprint after opening the 236 MB fixture (417 MB today) | Turn boundaries across a backward read; images in replayed turns; `/clear` and `/resume` inside one process |
| 5 | **No disk reads in bodies.**<br>• A `SessionContextMenu` view struct.<br>• `DuoState` as an in-memory store.<br>• `Fixture.session(key:)` plus a by-project index.<br>• `SendMenu` evaluates its targets once.<br>• Explainer and Settings read the store. | `AllProjectsPanes.swift:1022-1070`, `ObjectMenus.swift`, `SendMenu.swift`, `HookEvents.swift` (`DuoState`), `Explainer.swift`, `SettingsView.swift`, `Fixture.swift` | DuoChecks counter: `DuoState.load` from disk ≤ 1 per launch; `TaskNotes.load` 0 per snapshot with the menu closed; `check-ui` pixel-identical | Archive state shown in a menu built before the toggle; Settings toggles |
| 6 | **Two-speed live refresh.**<br>• A structure pass on change signals (vnode on `~/.claude/projects`, `.duo/sessions.json`, Home) or every 20 s.<br>• A live pass every 2 s (beacons, hooks of beaconed sessions); slower when Duo is inactive.<br>• Index history by id, memoize `realPath`, `treeFiles` for the open project only.<br>• Cache the repo's root, remotes and git dir; run `git status` only when `.git` changes or every 10 s. | `AppModel.swift:394-500`, `LiveSnapshot.swift`, `AppModel+Repo.swift`, `Git/RepoStatus.swift`, `Live/ThreadCache.swift`, `SessionArchive.swift` | A DuoChecks equivalence check (two-speed output = full build on the scale fixture); `check-scale.sh` passes; `rel-many` CPU and `git` spawn count before and after | Moves (`/cd`, F-32) and new sessions appearing late; needs-you latency must stay ≤ 2 s |
| 7 | **Search typing path.** One lazy query embedder; a 120 ms debounce with cancellation; `indexState()` off main; read vectors without a `Data` copy per row. | `AppModel+Search.swift`, `SessionListFilter.swift:121`, `SearchIndex.swift:332`, `SQLite.swift` | Type 30 characters: one `MLModel` load (Allocations); query latency on a copy of a large index | Exact-mode results; the archived toggle |
| 8 | **Third-party notices (C-82).** Generate `THIRD-PARTY-NOTICES.md` from `Vendor/`, SwiftTerm, Sparkle and the model card; `bundle.sh` copies it into Resources. The visible part waits on Q-186. | `scripts/bundle.sh`, a new `scripts/gen-notices.py`, the root notice file | A DuoChecks case: every `Vendor/*` and Package dependency has an entry; the file is in the bundle | Nothing at runtime |
| 9 | **Mechanical splits** (Refactor 3): the four big view files, chat files, `perform()` by family, the task views out of `Model/`, and the DuoChecks registry. **Schedule when few sessions are editing these files.** | as listed | `swift build`; all `check-ui` and `check-chat` states pixel-identical; DuoChecks count unchanged; type-check warnings at 200 ms drop | Merge conflicts with concurrent sessions (high); nothing at runtime |
| 10 | **Dead code and stale text:** the [removal list](#abandoned-code); the `Parity.uiOnly` rows (regenerate `docs/cli/duo2.md`); the design README statuses and missing folders; CONTRIBUTING; the 19 warnings, including the probe's weak coordinator. | as listed | DuoChecks, `check-records.sh`, `swift build` warnings = 0 (or only deprecations) | A harness action a script builds dynamically (none found) |
| 11 | **Debug code out of release.** `#if DUO_HARNESS` (set by the debug bundle and by DuoChecks) around `Debug/`, the walk-setup and the video states, or a `DuoHarness` target. `bundle.sh` copies fixtures in debug only. | `Package.swift`, `Sources/DuoKit/Debug/*`, `AppModel+Walk.swift`, `scripts/bundle.sh`, `video/pipeline/capture.mjs` (it captures from a debug build) | Release binary and bundle size; `check-ui` and the video stills still work on the debug build | Production views that read `FixtureHarness.designContentTop`/`holdsPeek` (they need a seam); video captures from a release build |
| 12 | **Test and script hygiene.**<br>• `scripts/lib.sh` with an `mktemp` `iso_env`; fix the fixed `/tmp` paths.<br>• `px.py`.<br>• `check-all.sh`, including the `.mjs` checks with a `scripts/package.json`.<br>• The golden set from `Models/` plus a committed fixture.<br>• A `gen-video-tokens` staleness check.<br>• `.claude/worktrees/` in `.gitignore`.<br>• `scripts/next-record.sh`. | `scripts/*`, `Sources/DuoChecks/main.swift:752-758`, `.gitignore` | `check-all.sh` green on a fresh work tree, with the golden set counted (1,266, not 1,260) | Scripts other sessions run mid-change |
| 13 | **One transcript reader and one title ladder** (Refactor 6). | `Live/SessionTitles.swift`, `ThreadCache.swift`, `ClaudeStorage.swift`, `Inventory.swift`, `Migrator.swift`, `HookEvents.swift`, `DuoSearch/SessionSource.swift`, `Chat/ChatFeed.swift` | DuoChecks: the same title from the sidebar and search for the fixture sessions; parse counts | Titles that change for existing sessions (needs Geoff's eye on a fixture) |
| 14 | **Extract `RepoModel`, then `TasksModel`** (Refactors 11–12). | the `+Repo*`, `+Push`, `+GitHubProject`, `+Tasks*` and `+Board` extensions | DuoChecks; `check-ui` for the board and the task pane; the `duo2 repo` verbs no longer navigate | Wide: these are the most-touched areas |
| 15 | **Build speed.** Find the cause of the full no-op rebuilds (try `--build-system native` in a scratch path); break up the 13 slow type-checks. | `Package.swift`, the functions listed | 10 no-op builds after idle gaps all under 3 s | Toolchain behaviour |

**Intro video, separate:**

| # | Task | Files | Proven by |
|---|---|---|---|
| V1 | Check stage first; stable line keys or the sync tool; Doc revision in the header; fix the `> note` hash scope (or the rule's wording); fail on a missing voice file; a committed `video/style/taste.md`; a committed GPU-lock script | `video/build.mjs`, `pipeline/script.mjs`, `pipeline/voice.mjs`, `video/script.md` header, `video/README.md`, `scripts/gpu-lock.sh` | `node build.mjs --check` fails in under 5 s on a renamed state or a missing word |
| V2 | Per-scene render cache plus `--scene`; a fixed-length score bed; capture keys by PNG content; cache GC; `fxKey` once per build | `build.mjs`, `pipeline/capture.mjs`, `pipeline/score.mjs`, a new `pipeline/render.mjs` | A one-scene edit re-renders one scene; frame-identical output against a full render for an unchanged film |
| V3 | Anchor-relative cams and a stale-anchor check; `review.json` and per-scene clips for Geoff | `shots.json` schema, `pipeline/plan.mjs`, `pipeline/capture.mjs` | S10's cams survive the DL-174 pane change with no hand re-framing |

## Measurement method

**Geoff's own Duo** (pid 34502; the main checkout's debug "Duo Dev" bundle, `--workspace ~/DuoAcceptance/workspace`, real support folder, started 2026-10-07):
- `ps` over time;
- one `sample 34502 10`;
- `footprint`, `vmmap --summary`, `lsof | wc -l`.

That's read-only, with the director's OK: no signals, no `duo2`, nothing in its support folder.

**Isolated runs.** The scripts are in the job scratchpad, `/Users/geoff/.claude/jobs/233351a5/tmp/m/`; copy them into `scripts/` if they're to be kept.
- **`measure.sh <label> <secs> [--events N] [--churn KB] [--docs N --html N] -- <make-scale-fixture args>`** makes the scale fixture in `/tmp/d-rv-XXXX` with the stand-in 2.1.219 TUI (`scripts/scale-tui.py`). Then:
  - It launches the bundle with its own `DUO_SUPPORT_DIR`, a scratch `CLAUDE_CONFIG_DIR` and `DUO_AUTOCONFIRM=1`, in the background (F-227).
  - It times the endpoint and the first `duo2 status` (using that instance's `DUO_SOCKET` and `DUO_TOKEN`).
  - It samples launch for 8 s, records `%cpu`, RSS and cumulative CPU time every 5 s, samples 10 s near the end, and takes `footprint`, `vmmap`, `leaks`, threads, open files and child processes.
  - It counts the WebKit processes that appear 9 s after launch and at the end.
  - It quits with SIGTERM to its own pid.
  - `--events N` gives N sessions a 256 KB hook log of chat-mode lines. `--churn KB` writes a Markdown file of that size in Home and appends a paragraph every 20 s, as a session editing a big doc does.
- **`matrix.sh`** runs the 10 configurations one at a time, each under the shared GPU lock: `rel-idle`, `rel-short`, `rel-events`, `rel-churn`, `rel-scale16`, `rel-term16`, `rel-many`, `rel-docs`, `dbg-events`, `dbg-churn`.
- **`inclusive.py <sample> <frame>…`** gives inclusive sample counts for frames in a `sample` call graph.
- **`build.sh`, `noop.sh` and `idle-rebuild.sh`** time the builds.
- **`../maxrec.py`** finds the highest record numbers on every ref.

**Caveats.**
- Every run is a background run, so the window is drawn but not shown. macOS may skip drawing, which understates layout and SwiftUI cost (F-208's trap). The visible gate (`DUO_TEST_FOREGROUND=1`) needs Geoff's OK and wasn't run.
- The Mac was shared: load average about 5, swap 12.1 of 13.3 GB used, other sessions building.
- `make-scale-fixture.py` writes user records without a `uuid`. That sends `ThreadCache.head` to its 4 MB cap on the 4 long transcripts, so the first-launch numbers overstate that one step. Real transcripts carry uuids.
- Each isolated run is a first launch: empty index, empty archive. Geoff's Duo, up 4.5 days, is the steady-state evidence.
