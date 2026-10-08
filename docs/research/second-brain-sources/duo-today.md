# Duo today, through the eyes of a vault / LLM-wiki / second-brain user

Read-only study of the `second-brain` work tree at `adfcd74` (main, 2026-10-07). All paths are relative to the repo root. "[U]" marks something I couldn't verify from the code or docs.

Three user shapes are considered throughout:

- **Obsidian vault:** `.obsidian/`, wikilinks, a template folder, attachments, maybe Templater, Tasks or Dataview.
- **LLM wiki:** `raw/` sources, `wiki/` pages, `index.md`, `log.md`, and a schema file in `AGENTS.md` or `CLAUDE.md` that Claude maintains.
- **Second brain:** `inbox/`, daily notes, thousands of small notes, PARA folders (`1 Projects/`, `2 Areas/`, …).

---

## 1. Inventory of what's built

### 1.1 How a folder becomes a project or Home

- **Discovery is marker-file only.** A project is a folder with `PROJECT.md`, and Home is a folder with `HOME.md`. The scan runs from the root up to 4 levels deep. It skips hidden folders, `node_modules`, `.build`, `build`, `Library` and protected folders (`Sources/DuoKit/Live/ProjectDiscovery.swift:18-59`; hidden folders skipped at `:52`, the name list at `:55`). A folder with a `CLAUDE.md` but no project file is listed as a "Claude folder" (`:37-38`, DL-103).
- **The project name is the folder name.** `title:` is ignored (`ProjectDiscovery.swift:113`). The tile reads only `goal`, `health` and `next` (or `milestone`) (`:120-122`).
- **Nothing detects `.obsidian/`, an OKF `_index.md`, `AGENTS.md` or `index.md`.** A grep of `Sources/` for `.obsidian`, `okf_version`, `_index.md`, `_PROJECT` and `project_brief` finds nothing. DL-147 (adopt any folder, `_PROJECT.md`, `project_brief: true`) is decided but not built (`docs/research/project-task-cx.md:3`, "not built").
- **Make a Project works only on folders Duo already lists**, meaning folders with Claude sessions or a `CLAUDE.md`. It writes `PROJECT.md` from the template unless one exists (`Sources/DuoKit/Model/AppModel+Organize.swift:154-177`). `duo2 project make` refuses any folder it doesn't list (`Sources/DuoKit/Control/AppModel+Control.swift:155-157`). This is the J3 dead end in `project-task-cx.md:47-51`.
- **New Project makes a new folder inside Home** with a `PROJECT.md` (`AppModel+Organize.swift:43-80`, written at `:55`).
- **Choose Home Folder accepts any folder** except `~`. If there's no `HOME.md`, it writes a three-line one (`type: home`, `# Home`, a sentence) (`Sources/DuoKit/Model/AppModel+Home.swift:29-43`). This is the only path today that takes an arbitrary, unlisted folder such as a vault.
- **Home claims only sessions run in its own folder**, not in its subfolders (DL-85). A session started in `vault/wiki/` shows as a separate "no project file" folder tile (DL-63).

### 1.2 File tree

- **Listing.** `LiveSnapshot.treeFiles` (`Sources/DuoKit/Live/LiveSnapshot.swift:374-394`) lists the project's top level plus the inside of each folder the user has opened. It is capped at **2000 entries**, and dotfiles show only with View › Show Hidden Files.
- **Never listed:** `.git`, `.DS_Store`, `.duo`, `node_modules`, `.build`, `build` and `.claude/worktrees` (`:365-369`). `.obsidian/` is hidden by default and appears greyed when hidden files are on (`Sources/DuoKit/Project/ProjectPanes.swift:359`).
- **The cap bites mid-listing.** The cap is checked while listing (`LiveSnapshot.swift:377, 389`), and the list is sorted only afterwards (`:393`). A folder with more than 2000 notes is silently truncated, and which entries survive depends on directory order [U].
- **Rendering.** The pane draws folders first, then files, alphabetically (`ProjectPanes.swift:287-335`). Rows are built with a plain `ForEach` inside a `VStack`, not a lazy stack (`:272, 388`). The tree has no filter, no "reveal active file" and no newest-first sort.
- **`duo2 files`** lists 3 levels and at most 200 entries (`LiveSnapshot.swift:397-411`).
- **File verbs (DL-61):** new Markdown file (⌘N), new folder, new from template, rename, duplicate, move, Trash, copy path or link, reveal, open with, and send to Claude.

### 1.3 The Markdown editor (CodeMirror 6, `Vendor/codemirror/src/duo-editor.js`, 2028 lines)

- **Wikilinks are not supported.** The file has no `wiki` or `[[` handling. `[[Note]]` renders as plain text: it isn't marked as a link and can't be clicked. DL-17 says Duo "reads wikilinks it finds", but the editor doesn't. Typing `[[` to complete files is decided (DL-150) but not built.
- **Link following.** A click on a Markdown `[text](url)` link, or ⌘-click on a raw line, sends `openLink` (`duo-editor.js:1528-1542`). `AppModel.openLink` (`Sources/DuoKit/Model/AppModel+Links.swift:26-52`) then routes it:
  - `duo2://session|task` links go to the session or task;
  - http(s) links open in a browser tab for allowed sites, else in the system browser;
  - a relative path is resolved **against the document's own folder**, percent-decoded, opened in Duo if it's inside the project, and handed to the system otherwise;
  - a missing target shows "`<path>` isn't there."
- **Images.** Only `![](relative.png)` is drawn, resolved against the document's folder, up to 10 MB (`Sources/DuoKit/Editor/DocumentEditor.swift:220-232`). `![[embeds]]` are not.
- **Properties block (frontmatter).** It is decorated in place, the text stays the source of truth, and it reads up to 400 lines (`duo-editor.js:207-266, 246-248`). It has typed rows (text, list, number, checkbox, date, datetime, link), and `tags`, `aliases` and `cssclasses` are treated as lists (`:261`).
  - **Suggestions** come from `PropertyCorpus.scan`, which reads up to **1500 Markdown files** across the project and Home. It runs off the main thread, at most once a minute per project (`Sources/DuoKit/Live/PropertyCorpus.swift:16`, called from `Sources/DuoKit/Model/AppModel+Tasks.swift:428-440`).
- **Other editor features:** Claude's edits are highlighted and can be reverted; tables can be edited (DL-113); there's find, and the user's typing is merged with Claude's edits.
- **Not supported:** callouts, `==highlight==`, embeds, block references, math, Mermaid and Dataview. None of them appears in the editor source.

### 1.4 Search

- **What gets indexed.** One index covers projects, Home, folders with Claude sessions and folders with a `CLAUDE.md` (DL-103). A folder Duo doesn't list is never indexed. Indexing runs in the background with a 15 ms pause per file (500 ms on low power), most recently modified first (`Sources/DuoKit/Search/SearchService.swift:52-80`).
- **Which files count** (`Sources/DuoSearch/FileSource.swift:6-62`):
  - text extensions (md, txt, org, code, json, yaml, csv, html…) plus a PDF extractor the app registers; also .docx and .pptx;
  - files up to 5 MB;
  - `.gitignore` is respected;
  - **every dot-folder is skipped** (`.obsidian`, `.trash`, `.claude`), along with `dist`, `target` and similar build folders;
  - names on the secrets denylist are skipped.
  - `.canvas` and `.base` files are not indexed.
- **How chunks are made and embedded.** Chunks are about 300 tokens with 45 tokens of overlap, split by paragraph and heading (`Sources/DuoSearch/Chunker.swift:14-15`). The model is **`bge-small-en-v1.5`**: Core ML, fp16, 384 dimensions, 512 tokens maximum, and English only (`Sources/DuoSearch/Embedder.swift:5-35`).
- **How queries run.** Retrieval is hybrid: brute-force cosine over **every stored vector** for each query (`Sources/DuoSearch/SearchIndex.swift:329-345`), plus FTS5 bm25, fused by reciprocal rank (`:204-240`). Defaults: 10 results, 1 passage per item, a 1.08 boost for the current project.
  - **Result kinds:** file, session and memory (`:165-175`).
  - **The modal** (⇧⌘A): name matches come first ("Go to"), Exact is ⌘E, and results can be multi-selected and sent to Claude (DL-76, DL-79, DL-80).
  - `duo2 search` works even when the app isn't running.

### 1.5 Templates engine (DL-146, built; F-186)

- **Engine:** `Templates` in `Sources/DuoKit/Live/Templates.swift`. §5 covers it in detail.
- **Template-editing actions:** `AppModel.editTemplate`, `copyTemplate`, `resetTemplate` and `previewTemplate` in `Sources/DuoKit/Model/AppModel+Templates.swift`. They have duo2 verbs (`template show|edit|copy|reset|preview`; `docs/cli/duo2.md:61-65`).
- **The template bar isn't drawn yet.** `templateInfo(forTab:)` exists, but no view uses it (a grep finds no caller).
- **New from Template** (`Sources/DuoKit/Live/FileActions.swift:127-147`) lists every `.md` file in the project's `templates/`, then Home's, except `new-project.md` and `new-task.md`. It fills the placeholders and names the file after the template (`meeting.md`, `meeting 2.md`; `freeName` at `:10-19`). `duo2 file template <t> [--in <folder>]` has **no `--name` option**.

### 1.6 Tasks

- **Every `.md` file in `<project>/tasks/` is a task.** Nothing checks `type: task` (`Sources/DuoKit/Live/TaskNotes.swift:31-38`). A missing `status` reads as `open` (for example `ProjectPanes.swift:152` and `TaskContext.swift:84`). File names are lowercase ASCII slugs (`TaskNotes.swift:75-79`).
- **Duo owns these keys:** `status`, `sessions` (quoted `duo2://session` links), `title` (on rename), `completed`, `archived` and `id`.
- **New Session in Task** drafts `@tasks/<note>.md` into the prompt without sending it (DL-112). Hooks tell each session which task it's in (DL-116).
- **The task board (DL-148) and `lanes:`/`references:` (DL-150) are not built.** A grep finds no board or `lanes` code outside `Sources/DuoKit/Debug/WindowCapture.swift`.

### 1.7 How a session starts, and what Claude is told

- **Launch command** (`Sources/DuoKit/Terminal/Terminals.swift:165-197`): `claude --session-id <id> --settings <per-session hooks file> --append-system-prompt <primer> [prompt]`.
  - A `prompt` given here is **sent as the first message**, which spends a turn (`AppModel.newSession(in:prompt:)`, `Sources/DuoKit/Model/AppModel.swift:533-547`; `duo2 session new --prompt`).
  - `draft(_:into:)` instead types the text and never presses Return (`Sources/DuoKit/Model/AppModel+Send.swift:84-108`).
- **The primer** (`Sources/DuoControl/Actions.swift:495-509`) tells Claude about `duo2`, to run `duo2 search` before grep, to edit open documents with `duo2 doc edit --stdin`, and to post a note and a next step.
- **Context from hooks.**
  - At SessionStart, Claude gets the project's name and folder and `goal`/`health`/`next` from `PROJECT.md`, never the body. At UserPromptSubmit it gets only what changed (`Sources/DuoKit/Live/ProjectContext.swift:27-92`).
  - If `CLAUDE.md` imports `@PROJECT.md`, Duo says only the project's name (`:48-53`).
  - Task context comes from `TaskContext` (DL-116).
  - Claude reads `CLAUDE.md` itself. **Duo does nothing with `AGENTS.md`.**

### 1.8 Send to Claude, chords, sheets

- **Send to Claude** (DL-67 to DL-69, `AppModel+Send.swift`): sends a selection (⌘D), a file or folder (as an `@`-reference relative to the session's folder), a session, a project, an HTML element or a slide shape. The text arrives as a bracketed paste and is never submitted.
- **Chords:** one locked table, `DuoCommand` (`Sources/DuoKit/Navigation/Commands.swift:7-140`): ⇧⌘A search, ⌘↑ All projects, ⇧⌘H Home, ⌘T session, ⌘N new Markdown file, ⌘O Open File, ⌘K link, ⌘D send, ⌘P print.
  - **No global hotkey, menu-bar item or Services entry exists.** A grep for `RegisterEventHotKey`, `addGlobalMonitor` and `NSStatusItem` finds nothing.
- **Questions and sheets:** `SheetCenter` with `DuoQuestion` (`Sources/DuoKit/Shell/DuoQuestion.swift`), and the sheets in `Sources/DuoKit/Shell/Sheets.swift`.
- **Scheduling:** none in Duo. The guide defers to Claude Code's own scheduling (`docs/guide/coming-from-legacy-duo.md:46`); DL-9 is "later".

### 1.9 What Duo writes into user folders

| Write | When | Ref |
|---|---|---|
| `PROJECT.md` (base: `type`, `title`, `aliases`, `status: active`, `goal`, `health`, `next`, `created`; body Why / Done when / Notes / Log) | New Project, Make a Project | `Templates.swift:33-60`, `AppModel+Organize.swift:55,159` |
| `HOME.md` (`type: home`) | Choose Home Folder, if missing | `AppModel+Home.swift:39-41` |
| `.duo/sessions.json` | Any session Duo starts or files | `Sources/DuoKit/Live/SessionIndex.swift:41` |
| `.gitignore` gains `.duo/` | Only on a yes to a one-time question, and only in a git repo | `Sources/DuoKit/Live/GitIgnoreOffer.swift:13-60`, DL-50 |
| `tasks/<slug>.md` | + New task, Make a Task | `AppModel+Tasks.swift:22-31` |
| `templates/new-task.md` / `new-project.md` | Edit Template (writes the base to Home's `templates/`), Make a Template for <project> | `AppModel+Templates.swift:49-86` |
| Surgical frontmatter edits (`status`, `sessions`, `title`, `completed`, `archived`, `id`) | Task verbs | DL-93, DL-115 |
| `.obsidian/` | **Never** | format doc §4.8 rule 1 |

---

## 2. Fit and clash, for a vault user

| Situation | Today | Verdict |
|---|---|---|
| **Vault root as a project** | It needs a `PROJECT.md` at the root. A vault with no Claude history isn't listed, so Make a Project can't reach it. **Workarounds:** `duo2 home set <vault>`, which writes `HOME.md`; or run `claude` once in the vault from Terminal and then Make a Project. Duo then adds `PROJECT.md` (a new note in the vault, with a `## Log` section and `type: project`). Every project's note shares the basename `PROJECT` (C-51). | **Clash.** It can be adopted, but only by a back door. An LLM wiki's `index.md` / `AGENTS.md` isn't recognised as a brief. |
| **Vault as Home** | Works for any folder. Projects are found 4 levels deep, so PARA's `1 Projects/foo/PROJECT.md` shows as a column labelled "1 Projects" (topics are the folder names). Home's session runs at the vault root with the vault's `CLAUDE.md`. | **Fit.** It's the natural route, and the guide maps topics to PARA areas (`docs/guide/topics.md:406`). |
| **Sessions in subfolders** (`wiki/`, `inbox/`) | Home claims only sessions run in its own folder. Sessions run elsewhere become stray "no project file" tiles until they're moved. | **Clash** for a wiki where Claude works per-folder. |
| **`tasks/` vs the vault's own folders** | Any `.md` in `<project>/tasks/` is a task, with no `type` check, and status defaults to open. On the default case-insensitive disk, **`Tasks/` matches too**. A vault's `Tasks/` folder of Tasks-plugin or TaskNotes notes would flood Open tasks on All projects. Tasks elsewhere (TaskNotes' `TaskNotes/Tasks`, inline `- [ ]`) are invisible (ENH-34). | **Clash.** |
| **Thousands of notes in the file tree** | The top level is cheap. Opening a large folder lists up to 2000 entries, with no lazy rendering, filter or reveal-active-file. Beyond 2000 entries, which ones are shown is arbitrary. | **Partial clash** for daily-notes and Zettelkasten folders. |
| **`.obsidian/`, `.trash/`** | Hidden in the tree by default, never searched, never written. | **Fit.** |
| **Wikilinks** | `[[Note]]`, `[[Note\|alias]]`, `[[Note#Heading]]` and `![[img.png]]` show as raw text: not links, not clickable, and no backlinks. Duo writes only Markdown links (DL-17). | **Clash** for the many vaults that use wikilinks. |
| **Markdown links in Obsidian's default "shortest path" style** | `[x](Note.md)` pointing to a note in another folder is resolved against the current note's folder, so it fails with "Note.md isn't there". Relative-path vaults work, and `%20` is decoded. | **Clash** unless the vault uses relative paths. |
| **Attachments** | `![](../attachments/a.png)` relative to the note works. Obsidian's vault-root or attachment-folder resolution and embeds don't. | **Partial.** |
| **Properties** | Typed rows match Obsidian's types; `tags`, `aliases` and `cssclasses` are lists; suggestions come from up to 1500 notes; edits are surgical. | **Fit.** |
| **Frontmatter keys Duo adds** | PROJECT.md: `type`, `title`, `aliases`, `status`, `goal`, `health`, `next`, `created`, and later `lanes` (DL-150). Tasks: `type`, `title`, `status`, `sessions`, `created`, `id`, `archived`, `completed`, and later `references`. The `type` and `status` keys collide with vault taxonomies, so Bases filters on `type` pick up Duo's notes. `project_brief: true` (decided, not built) is the one key Duo would add to a user's own note. | **Mostly fit**, by design (the format doc). Watch `type` and `status`. |
| **Search across many notes** | Only listed folders are indexed. The model is English-only bge-small. Every query scans every vector, which is fine for thousands of notes and unmeasured for tens of thousands [U]. Wikilink structure isn't used, and `.canvas`/`.base` files are skipped. The first indexing pass of a big vault takes a while [U]. | **Fit** for meaning and words. **Clash** for non-English vaults and very large ones [U]. |
| **Templates** | Obsidian's own placeholders, the `templates/` folder (it matches `Templates/` on a case-insensitive disk), and Templater code left as written. | **Fit**, apart from the §5 gaps. |
| **Claude's context** | Claude reads `CLAUDE.md` natively. Duo adds only `goal`/`health`/`next` and task lines. An LLM wiki's `AGENTS.md` schema isn't read unless `CLAUDE.md` imports it (`@AGENTS.md`) [U: Claude Code's own AGENTS.md handling]. `index.md` and `log.md` aren't surfaced, and the primer steers Claude toward `duo2 search`. | **Partial.** |
| **Claude's bulk writes** (wiki ingest touches many pages) | Only open documents go through the editor (`duo2 doc edit`). The tree marks "edited by Claude" only on the focus document (`ProjectPanes.swift:345, 362-366`). Ready for review is per session. | **Partial**: there's no "pages changed this session" list. |
| **Capture (inbox, daily note)** | No global hotkey, no daily note and no inbox verb. ⇧⌘H gives Home's session, ready to type, and the guide's starter `CLAUDE.md` suggests an `inbox.md` (`docs/guide/home.md:186`). | **Gap.** |
| **`.duo/` in the vault** | It's a hidden folder, ignored by Obsidian and offered once for `.gitignore`. | **Fit.** |

---

## 3. What a vault user trips on first (the first hour)

1. **"Where's my vault?"** A vault with no Claude history isn't on the map. There's no folder picker for projects; File › Open File… opens a single note, and `duo2 project make ~/Vault` answers "no folder". The only routes are Choose Home Folder (turning the whole vault into Home and writing `HOME.md`) or running `claude` in Terminal first (J3; `AppModel+Control.swift:156`).
2. **Wikilinks are dead text.** The first note they open is full of `[[…]]` that don't look like or work as links, embeds show as `![[…]]`, and Obsidian-style Markdown links to notes in other folders say "isn't there" (`AppModel+Links.swift:43-46`).
3. **Their `Tasks/` folder becomes Duo tasks.** If a project or Home folder has `tasks/` or `Tasks/`, every note in it appears as an *open* task, and Duo may write `status`, `sessions` or `id` into those notes the moment they use a task verb (`TaskNotes.swift:31-38`).
4. **Duo's notes appear in their vault.** `PROJECT.md` or `HOME.md` appear in Obsidian's file list, graph and Bases (with `type: project` and `## Log`). `templates/new-task.md` lands in the vault's template folder after one Edit Task Template, and sessions run in subfolders become stray tiles. Every write is plain Markdown, but none of it was asked for in vault terms (C-51).
5. **Big folders and capture.** Opening a `Daily/` or `Zettel/` folder with thousands of notes gives a long, eagerly drawn list that is cut at 2000 entries with no filter. When they reach for quick capture, there's no hotkey, no daily note, and New from Template names the file after the template (`daily 2.md`), not today's date (`FileActions.swift:139-147`).

Close runners-up: semantic search is English-only; an `AGENTS.md` schema is ignored; Templater templates produce notes with raw `<% … %>` in them.

---

## 4. Existing hooks a second-brain feature could build on

| Hook | Types and functions | What it gives |
|---|---|---|
| **Templates engine** | `Templates.make`, `render`, `fill`, `setting`, `scalar`, `formatted` (`Live/Templates.swift`); `Templates.Kind` (`project`, `task`); `Templates.file`/`text` lookup | Obsidian-compatible filling, surgical frontmatter set-by-key, YAML-safe scalars. Adding a kind (say `.note` or `.daily` → `templates/new-daily.md`) is a few lines. |
| **New from Template** | `FileActions.templates`, `FileActions.newFromTemplate`, `AppModel.newFromTemplate`; `duo2 file template` | Any `.md` in `templates/` already works. It needs a name argument (`{{date}}`-named files) and a destination folder default. |
| **Task model and menus** | `TaskNotes.load`, `parse`, `newNote`, `settingStatus`, `slug`; `AppModel.makeTask`, `newTask`, `newSession(inTask:project:)`, `setTaskStatus`; `AppModel+TaskMenu.swift`; DL-115 menu | A pattern for "notes in a folder that Duo lists, with surgical keys". An inbox could reuse it with an `inbox/` folder and a status. |
| **Starting Claude with an instruction** | `AppModel.newSession(in:prompt:)` (sent); `AppModel.draft(_:into:)` (typed, not sent); `sendToNewSession`; `whenPromptReady` | "Process my inbox", "file this note", "ingest raw/x.pdf into the wiki" as one-click sessions, drafted or sent. |
| **Send to Claude** | `AppModel.send(_:to:)`, `filePayload`, `projectPayload`, `documentSelectionPayload`; `SendFormat.*` | Send a note, a folder (`raw/`) or a selection to a session as context. |
| **Context hooks** | `HookEvents.settingsFile(for:cli:chatEvents:)`; `ProjectContext.hook`/`atStart`/`onPrompt`; `TaskContext`; `duo2 hook context` | A place to tell each session about the vault: its schema file, `index.md`, today's daily note, the inbox count. It's said once at start and as diffs after. |
| **Primer** | `DuoAction.primer()` (`DuoControl/Actions.swift:495`) | Generated from the verb registry, so a new `duo2 note …` or `duo2 inbox …` verb is advertised to Claude automatically. |
| **duo2 verb registry** | `Sources/DuoControl/Actions.swift` (`Parity.uiOnly`); handlers in `AppModel+Control.swift` | DL-71: every UI action has a verb, so Claude can drive capture and filing. |
| **Search** | `SearchIndex.search`, `SearchQuery` (`kinds`, `projects`, `similarTo`); `findSimilar(file:)`; `duo2 search` | "Related notes", inbox triage ("where does this go?" via find similar), and wiki lint. |
| **Property corpus** | `PropertyCorpus.scan` | Vault-wide key and value vocabulary, for suggestions or a schema view. |
| **Questions and sheets** | `SheetCenter`, `DuoQuestion`; New Project sheet in `Shell/Sheets.swift`; `confirm(title:detail:button:)`, `registerUndo` | Duo-styled confirmation and Undo for any write into a vault (C-51's mitigation). |
| **Home** | `AppModel.setHome`, `homeFolder`, Home's session, ⇧⌘H `goHome` | The chief-of-staff session is already the "inbox processor" in the guide. |
| **File tree and drops** | `LiveSnapshot.treeFiles`, `FileTreePane`, `TakesFileDrops`, `FileDrop.swift` | Drop files into `raw/` or `inbox/` from Finder; a hook for a filter or lazy list. |
| **Link router** | `AppModel.openLink(_:from:)` | One place to add wikilink resolution (by basename, vault-wide) and vault-root paths. |
| **Discovery** | `ProjectDiscovery.walk`, `found(at:root:)`, `enclosingProject` | Where `.obsidian/`, `_index.md`, `AGENTS.md` and `project_brief` detection would go (DL-147). |
| **Scheduling** | None in Duo; Claude Code's own scheduled sessions show up like any other (DL-9 later) | A daily "process inbox" run would be a Claude Code routine today. |

---

## 5. Templates engine in detail

**Syntax** (`Templates.substitute`, `Live/Templates.swift:161-176`). The regex is `\{\{\s*(title|date|time)\s*(?::([^}]*))?\}\}`:

- `{{title}}` is the title passed in. For New Project that's the name; for a task, the human title; for New from Template, the new file's name.
- `{{date}}` is `YYYY-MM-DD` and `{{time}}` is `HH:mm`.
- `{{date:FORMAT}}` and `{{time:FORMAT}}` take Moment tokens, translated to `DateFormatter` (`:187-207`). The supported tokens are `YYYY YY MMMM MMM MM M dddd ddd Do DD D HH H hh h mm m ss s A a ZZ Z`, plus `[literal]`. Any other letter is output literally.
- Spaces inside the braces are tolerated.
- **Nothing else is a placeholder**, and Templater's `<% … %>` is left byte for byte.

**How a file is made** (`render`, `:129-135`):

1. Placeholders are filled. In the frontmatter, a value holding a placeholder is rewritten as a YAML scalar, quoted only when YAML needs it (`:140-158, 211-222`). So `title: "{{title}}"` becomes `title: Draft PRD v2`.
2. Known values are set by key with `setting` (`:226-245`): the key's line and its list items are replaced in place, or the key is added at the end of the block. A frontmatter block is created if there's none.
3. An optional `bodyPrefix` line goes after the first `# ` heading (`:248-259`).
4. Files are written with `.withoutOverwriting`, so a template never overwrites a file.

**File names and lookup** (`Templates.Kind.fileName`, `:13-18`; `Templates.file`, `:86-97`):

- The names are `templates/new-project.md` and `templates/new-task.md`. They're named `new-…` because `templates/project.md` would be `PROJECT.md` on a case-insensitive disk and turn `templates/` into a project (F-186).
- **Tasks:** the project's own `templates/new-task.md`, else Home's `templates/new-task.md`, else `Templates.baseTask`.
- **Projects:** Home's `templates/new-project.md`, else `baseProject`. A project's own `new-project.md` is never used.
- **New from Template:** any other `.md` in the project's `templates/`, then Home's; a project's file shadows Home's of the same name (`FileActions.swift:127-135`).

**Making an inbox note today.**

- **By hand:** put `inbox.md` (or `capture.md`) in Home's or the project's `templates/`. Then choose New from Template (right-click a folder) or run `duo2 file template inbox --in inbox`.
- **Result:** `inbox/inbox.md`, then `inbox/inbox 2.md`, and so on. `{{title}}` fills as `inbox 2`, and `{{date}}`/`{{time}}` fill correctly.
- **What's missing:** there's no way to pass a name (so no `2026-10-07 1432.md` file names), to pass body text, or to set keys. Those three are what `Templates.make`'s `title:`, `values:` and `bodyPrefix:` already do for projects and tasks.
- **Programmatic route:** a second-brain feature would add a `Kind` (or a general `make(template: URL, title:, values:, bodyPrefix:)`) and a verb such as `duo2 note new --template inbox --in inbox --title "{{date:YYYY-MM-DD HHmm}}" --stdin`.

**Collisions with Obsidian and Templater.**

- **Obsidian core Templates:** the same syntax on purpose, so one file serves both. The differences:
  1. In Obsidian `{{title}}` is the **file name**. Duo uses the human title for tasks and projects and the file name for New from Template (the trade-off in F-185).
  2. Obsidian's `{{date}}` and `{{time}}` use the formats set in `.obsidian/templates.json`. Duo always uses `YYYY-MM-DD` and `HH:mm` and never reads that setting.
  3. **Moment coverage is partial.** Weekly-note formats break: `{{date:gggg-[W]ww}}` comes out as the literal `gggg-Www`, because `g`, `w`, `W`, `Q`, `E`, `X` and `dd` aren't translated (`:188-205`).
  4. Duo accepts `{{ title }}` with spaces, which Obsidian may not [U].
  5. Obsidian's template folder is whatever its settings say (often `Templates/`, `_templates/` or `99 Templates/`). Duo only looks in `templates/`; `Templates/` works on a case-insensitive disk, and other names don't.
- **Templater:** there's no syntax collision, because `<% %>` is never touched. But Duo **never runs** Templater code, so a note Duo makes from a Templater template contains raw `<% tp.… %>` until Obsidian processes it. Whether Templater's "trigger on new file creation" processes a file created outside Obsidian is [U].
- **Templates with `type:`** are matched by Bases `type == …` filters (legacy lesson ENH-266d). Duo never reads `templates/` as projects or tasks (F-186), but Obsidian's bases will unless they exclude the folder.

---

## Bottom line

**Where it fits.** Duo's file format work (DL-6, DL-17, DL-146, the format doc's §4.8 "never" list) makes it a safe guest in a vault:

- it writes plain, Obsidian-normal frontmatter;
- it never touches `.obsidian/`, and edits keys surgically;
- its templates use Obsidian's own syntax;
- search ignores dot-folders;
- Home maps cleanly onto a PARA vault.

**Where it clashes.** The interaction layer is code-project shaped:

- adopting a vault needs a back door;
- wikilinks and vault-root links don't work;
- `tasks/` is claimed by folder name alone;
- the tree isn't built for thousands of notes;
- there's no capture surface (no hotkey, daily note or inbox);
- context injection knows `PROJECT.md` and `CLAUDE.md` but not an LLM wiki's `AGENTS.md`, `index.md` or `log.md`.

DL-147's adopt flow and DL-150's `[[` completion are the decided fixes for the first two and are not built yet.
