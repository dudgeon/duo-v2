# Spike: the file navigator's scope, hidden files, and outside files as tabs

2026-10-05, on `design/home-many-projects`. Code read at `339c2e3`; behaviour checked by running the built app on a scratch workspace (below). Nothing committed beyond this note.

IDs: F-79 (this spike), Q-35 to Q-37 (the design questions below), C-20 (the `../` hole), ENH-9 (the work).

## Question

1. Does the project view's Files tree show hidden files (`.claude/`, `.env`, `.gitignore`)?
2. Can the navigator go outside the project's folder (parent folders, any folder)? What stops it?
3. Can the right pane open a file from outside the project as a tab, and does that tab survive switching to another project or Home and back? How are tabs stored and keyed?

## Answer today

**How it was checked.** `scripts/bundle.sh`, then `Duo --workspace /tmp/duo-spike-ws --capture-window … --then …` with scratch `CLAUDE_CONFIG_DIR` and `DUO_SUPPORT_DIR` (no Claude turns). Project `alpha` held `PROJECT.md`, `notes.md`, `docs/a.md`, `.env`, `.gitignore`, `.claude/settings.json`; `beta` beside it; `sibling.md` in the workspace; `/tmp/duo-spike-outside/outside.md` elsewhere. The harness's `tabs` action printed the tabs and tree at each step.

### 1. Hidden files: not shown

- The tree comes from one function, `LiveSnapshot.topLevelFiles`, `Sources/DuoKit/Live/LiveSnapshot.swift:347`. It enumerates with `options: [.skipsHiddenFiles]` (`:349`). Every dotfile and dot-folder is skipped, `.duo/` included.
- It is called once per project with a `PROJECT.md` on every 2 s refresh (`LiveSnapshot.swift:196`; timer at `Sources/DuoKit/Model/AppModel.swift:220`). Folder-only entries (DL-63) get no tree at all (F-45: `~` would mean walking Documents and Desktop).
- Other limits in the same function: three levels deep (`:353`), `node_modules`, `.build` and `build` skipped (`:354`), privacy-guarded folders skipped unless the project is inside one (`ProtectedFolders.skip`, `Sources/DuoSearch/ProtectedFolders.swift:16`), **stops at 200 entries** with no sign that it stopped (`:357`).
- The view builds the tree from those strings (`FileTreePane`, `Sources/DuoKit/Project/ProjectPanes.swift:207–228`). Every folder is drawn open; there is no collapse (`Chevron(direction: .down)`, `:292`).
- Run: `tree: ["PROJECT.md", "docs/", "docs/a.md", "notes.md"]`. No `.env`, `.gitignore` or `.claude/`.
- `duo2 files` lists the same array (`Sources/DuoKit/Control/AppModel+Control.swift:535–538`), so it hides them too. Search skips dot-folders and dotfiles on its own (`Sources/DuoSearch/FileSource.swift:48`, `:55`; `.github` excepted).

### 2. Navigating outside the folder: no, by design and by construction

- **Design.** DL-23 ("a file tree rooted in the project folder"); handoff §3.3 quotes Geoff: "a file navigator, rooted in the project's working directory"; `FileTree` in the handoff's component list is "rooted in the project folder". No DL, LR or ENH asks for wider navigation. Legacy's "`~/.claude` settings pane in the navigator" is on the not-carried list (`legacy-requirements.md:161`).
- **Code.** Everything is a path relative to the project folder: the tree's entries, `openDocument`, `liveFile` (`AppModel.swift:112`), `relative()` (`AppModel+Files.swift:67`), every file verb (`projectFolder.appending(path:)`). There is no parent row, no root other than `liveFolders[project]`, and the path line under FILES is plain text (`ProjectPanes.swift:218`).
- **Entry points refuse outside paths.** `duo2 doc open` and `duo2 open --file` go through `relativePath`/`locate` (`AppModel+Control.swift:721–752`), which return nil unless the file is inside a known project, so the reply is "'…' isn't a file in a project Duo knows". A relative link in a document to a file outside the project opens in the system's default app (`AppModel+Links.swift:46–49`). The one way out of the folder is Move To…, whose panel can pick any folder; moving a file out closes its tab (`AppModel+Files.swift`, `moveToFolder`).
- **Not the OS sandbox.** Duo isn't App Sandboxed: no entitlements file; release signs with hardened runtime only (`scripts/release.sh:125–127`). Claude Code's Seatbelt sandbox limits Claude's processes, not Duo; `duo2` inside it only reaches Duo's socket, and Duo does the file work. What macOS does impose is TCC: Desktop, Documents, Downloads and the rest raise privacy prompts the first time Duo walks into them (F-28, F-53). That's why `ProtectedFolders` exists.

### 3. Outside files as tabs: no; tabs survive switching, the selected tab doesn't

**How tabs are stored.**
- `openDocumentsByProject: [String: [String]]` (`AppModel.swift:74`), keyed by the project's **display name**. Each value is the project's tab ids in order: a path relative to the project folder, or `web:…` for a browser tab. `openDocuments` reads and writes the current project's list (`AppModel+Files.swift:24–27`).
- They're memory only while running. Restore on relaunch (LR-58) writes them per project **by folder** to `App Support/Duo/restore-<hash of Home>.json` (`AppModel+Restore.swift:38`, `RestoreState.Project.documents`, `:27`). On load, a document survives only if `folder.appending(path: d)` exists (`:104`).
- Opening a document checks nothing about where it is (`openDocument`, `AppModel+Files.swift:30`). The pane decides what to draw from `liveFile(path)`, which is `folder.appending(path: path)` if it exists (`AppModel.swift:112–116`). `ProjectPanes.swift:419` then shows the editor; otherwise it shows `DocumentPlaceholder` (`:431`), which is blank in live mode.

**Switching (run).**
1. In `alpha`, opened `notes.md`, `.env`, `../sibling.md` and `/tmp/duo-spike-outside/outside.md` (the harness calls `openDocument` directly, as the tree does).
2. Zoomed out, opened `beta` and `b.md`, came back to `alpha`.
3. Result: `tabs: ["notes.md", ".env", "../sibling.md", "/tmp/duo-spike-outside/outside.md"] right=Project`. Each project kept its own tabs. **The selected tab didn't survive:** `open(project:)` resets the right pane to Project unless the session it lands on carries a document (`AppModel.swift:455–462`).

**A tab whose file is outside the root.**
- **No UI or `duo2` path can create one today.** The tree only lists files inside the folder, `duo2` refuses (above), and links hand off to the system.
- **An absolute path** (only reachable from the harness) gets a tab titled `outside.md` over a **blank pane**: `liveFile` makes `<project>//tmp/…`, which doesn't exist. It would be dropped on relaunch.
- **A `../` path escapes the root silently:** `../sibling.md` opened in the editor (`editor=sibling.md`), because `liveFile` never checks that the result stays inside the folder. Nothing produces such a path today, but it's a latent hole. It would also survive relaunch.
- **Tabs are keyed by display name**, and names change when another folder of the same name appears (DL-83's uniquing, `LiveSnapshot.swift:215–221`). In-memory tabs would then go missing until relaunch, when restore re-keys them by folder. This is minor.

## What changing it takes

| Change | Files | Size |
|---|---|---|
| **A. Hidden files, behind a toggle.** Drop `.skipsHiddenFiles` when on, and always skip `.git`, `.DS_Store`, `.duo`, `.claude/worktrees` and `.build`. The setting goes in `DuoState`. Add a `duo2` verb for parity (DL-71). | `LiveSnapshot.swift`, `ProjectPanes.swift`, `DuoState`, the control registry, a DuoChecks check | **S** alone. **M** with what it really needs: folders that collapse and a listing past the 200 cap (see Risks). |
| **B. Navigating outside the folder.** Give the tree a root other than the project folder (enclosing folder, or any folder chosen), with every verb on absolute paths. | `topLevelFiles`, `FileTreePane`/`FileRow`, every verb in `AppModel+Files.swift`, `FileMenu`, `isInTree`, `duo2` file verbs, `ProtectedFolders` | **L**: it changes the "rooted in the project" model (DL-23) and every verb's addressing. |
| **C. Outside files as tabs.** A tab id for a file outside the folder (an absolute path, or `file:/…` like `web:`): `liveFile`/`keptFile` accept it; the title and its menu (no "relative path", rename not inline); `closeDocument`; restore's existence check; HTML pages get their own folder as read root (`HTMLViewer.open`, `allowingReadAccessTo` is the project today); `openLink` opens such files in Duo instead of handing them off; `locate` accepts outside paths for `duo2 doc open/read/edit`; an entry point (Open File…). | `AppModel.swift`, `AppModel+Files.swift`, `AppModel+Restore.swift`, `AppModel+Links.swift`, `AppModel+Control.swift`, `ProjectPanes.swift`, `HTMLViewer.swift`, a check | **M**. The editor itself needs nothing: it takes any URL and watches the file and its folder (`DocumentEditor.swift:306–327`). `duo2 doc status` already resolves absolute paths (`AppModel+Control.swift:338–340`). |
| **D. Keep the selected tab when coming back to a project.** Remember `rightTab` per project; `open(project:)` restores it unless a session's document should show. | `AppModel.swift` | **S** |
| **E. Close the `../` hole in `liveFile`.** Standardize, then require the folder prefix (or explicit outside-tab ids, C). | `AppModel.swift`, a check | **S**, worth doing regardless |

**Restore format.** `documents` is a list of strings, so absolute paths fit without a version bump. An older Duo reading them drops them, because its existence check prefixes the folder. That's the graceful downgrade LR-58 wants. A `file:` prefix behaves the same.

## Risks

- **Size.** Turning on hidden files lets `.git` (thousands of objects), `.venv`, `.next` and `.claude/worktrees/*` in; this repo's worktrees are whole copies. The 200-entry cap then fills with dot-folders and real files silently vanish. The tree is rebuilt every 2 s off the main thread; walks get longer. This is why collapse plus lazy per-folder listing belongs with A.
- **Secrets on screen.** `.env` and credential files would show in the tree and open in an editor that autosaves and keeps history snapshots (`App Support/Duo/history/`, F-44). Search already redacts secrets (`DuoSearch/Secrets.swift`); history doesn't. Opening `.env` would put a copy of it in Duo's history.
- **Privacy prompts.** A tree rooted at `~` or a parent of Documents walks into TCC-guarded folders (F-28, F-53). Opening one chosen file through an open panel doesn't prompt; walking does.
- **Watching outside the root.** Per-file watching is fine (the editor watches one file and its folder). The real risk is network or iCloud-evicted volumes stalling reads (LR-9's lesson), and the file vanishing when a disk unmounts. The removed-on-disk bar (DL-77) covers that.
- **Agent edits (LR-34).** Claude's edits to an open file go through Duo (`duo2 doc edit`, the pre-edit hook). For an outside file the hook's `doc status` works; `doc read/edit` don't until `locate` accepts outside paths. Without that, Claude's raw writes to an open outside file fall back to the editor's merge (DL-77). That's safe, but it's not the routed path.
- **Which project owns an outside tab.** It lives in one project's list. If the same file is open from two projects, the single shared editor still shows one buffer, so this is safe, but the tab exists twice.
- **The editor is Markdown-shaped.** `.env`, `.gitignore` and `settings.json` open in the CM6 live-preview editor. Files with no dot in their name (`Makefile`, `LICENSE`) fall to the blank placeholder (`ProjectPanes.swift:419`, `path.contains(".")`).

## Design questions for Geoff

These are design calls, not decided here. Each would get a stub and a Q-n until answered (CLAUDE.md: never invent a design).

1. **Hidden files at all?** If yes: where is the toggle (the FILES header, the View menu, the tree's right-click), is it global or per project, and how do hidden rows look (dimmed, or the same)? Which stay hidden even when it's on (`.git`, `.DS_Store`, `.duo`)?
2. **Does the tree stay rooted in the project?** DL-23 and your words in §3.3 say rooted in the project folder. Is going up a level (from the path line, say) wanted, or is reaching outside only for opening a single file?
3. **An outside file's tab:** how does it read as "not in this project" (a path hint, a different title, a tooltip with the full path)? Which project does it belong to? Does it come back on relaunch? Which file verbs does it offer?
4. **Where Open File… lives:** File menu with ⌘O (unassigned today; LR-25 once paired ⌘O with ⌘K, which DL-80 freed), the right pane's `+` menu, dropping a file from Finder on the right pane, or pasting a path into search (LR-25). Any chord goes on the locked chord map (LR-60).
5. **Coming back to a project:** should the right pane reopen on the tab you left, or on Project as now? (This isn't drawn; the current behaviour predates DL-60's "tabs stay".)

## Recommendation

- **Fix now (S, no design):** E, the `../` escape in `liveFile`, with a DuoChecks check.
- **D (S)** once Geoff answers question 5. It looks like the intent of DL-60 but isn't drawn.
- **C (M)** after questions 3 and 4. It's the most useful of the three: one-off files (a spec in Downloads, `~/.claude/CLAUDE.md`) without widening the tree. The editor already handles any path. Use an explicit tab id (`file:` + absolute path) rather than overloading relative paths, so restore and verbs can branch cleanly.
- **A (S, really M)** only with collapsible, lazily listed folders and a fixed skip list. Log it as an enhancement until Geoff answers question 1; consider keeping `.env`-style files out of history.
- **B (L): don't.** It fights DL-23 and brings TCC prompts and huge walks. C covers the real need. Revisit only if Geoff asks for it after C.
