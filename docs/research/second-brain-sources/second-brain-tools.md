# Second brains: methods, Obsidian mechanics, and capture/inbox patterns

Research for Duo (2026-10-07). Duo is a Mac app that organizes Claude Code sessions into project folders of Markdown files, and it has to stay fully compatible with Obsidian.

**Labels.** **VERIFIED** means I fetched the primary source (official docs, the method author's own site, or the tool's source code) during this research and it supports the claim. **UNVERIFIED** means the claim rests on secondary sources, forum posts, or my prior knowledge, or the primary page didn't state it. Square-bracket numbers refer to the source list at the end.

---

## 1. Methods

### 1.1 PARA (Tiago Forte)

- PARA has four top-level categories: **Projects**, "short-term efforts … that you take on with a certain goal in mind"; **Areas**, "important parts of your work and life that require ongoing attention"; **Resources**, topics you're interested in; and **Archives**, "anything from the previous three categories that is no longer active." VERIFIED [1]
- Notes are organized by **actionability**, not by subject: "the ultimate system for organizing your life is one that is actionable." Forte argues against academic subject folders like "Psychology." VERIFIED [1]
- He recommends the same four categories in every tool (file system, cloud drive, notes app), and says the structure should "give you time, not take time." VERIFIED [1]
- **For Duo:** Duo's "project folder" maps directly onto a PARA Project. Archiving finished projects (moving them, not deleting them) is native PARA behaviour. A PARA user's vault usually has top-level folders such as `1 Projects/ 2 Areas/ 3 Resources/ 4 Archive/`. The numbering is common practice but UNVERIFIED as Forte's own rule.

### 1.2 Building a Second Brain: CODE and Progressive Summarization

- **CODE** stands for Capture, Organize, Distill, Express. VERIFIED [2]
  - Capture: keep "the ideas and insights you think are worth saving," in one central place. The test is **"keep what resonates"**: an intuitive judgment, not an analytical one.
  - Organize: "focus on your active projects" (PARA).
  - Distill: "actionable, bite-sized summaries," done gradually.
  - Express: "creating tangible results in the real world."
- **Inbox:** a temporary holding folder until items are filed into PARA. Forte recommends processing it in a **weekly batch of roughly 10–20 items**. VERIFIED [2]
- **Progressive Summarization** works in layers [3], VERIFIED:
  - Layer 1: the captured note.
  - Layer 2: **bold** the key passages.
  - Layer 3: ==highlight== the best of the bold.
  - Layer 4: an executive summary in your own words at the top.
  - Remix: turn it into something new.
  - The key principle is that you summarize **opportunistically, when you touch a note for other reasons** ("in small spurts, spread across time"), never up front.
- Forte's "4 levels of PKM" names a Level-1 failure: people hesitate to save because they're "not sure how or when you'll see them again." Retrieval confidence drives capture. VERIFIED [4]
- **For Duo:** progressive summarization is plain Markdown (`**bold**`, `==highlight==`, a summary block at the top), so it's Obsidian-safe. `==` highlight is Obsidian-flavoured Markdown, not CommonMark, so Duo's renderer should support it. An "AI distill" step should add a summary at the top and leave the original intact (layer 4), never rewrite the source.

### 1.3 Zettelkasten (Luhmann; zettelkasten.de; Ahrens)

- Luhmann's slip-box was a hypertext of numbered notes with a register of entry points. "It is not important where you place a new note as long as you can link to it." VERIFIED [5]
- **Atomicity:** "limiting each Zettel to one thought." VERIFIED [5]
- **Unique IDs:** for digital use the site prefers time-based IDs ("A time-stamp is a very simple way to create a unique string"). Because the ID is stable, titles can change without breaking links. VERIFIED [5]
- **Links carry context:** the goal is to "make connecting and not collecting a priority." Links without an explanation "will not create knowledge." VERIFIED [5]
- **Structure notes:** "a Zettel about other Zettel and their relationships," the same idea as Milo's MOCs. VERIFIED [5]
- **Fleeting / literature / permanent notes** come from Sönke Ahrens, *How to Take Smart Notes* (2017), not from the zettelkasten.de intro. UNVERIFIED (secondary sources only [6]).
  - Fleeting notes are quick captures, processed or discarded within a day or two.
  - Literature notes are short, selective notes on a source, with the reference.
  - Permanent notes are one idea each, understandable on their own, and linked.
  - Ahrens also has **project notes**, which serve one project and are not part of the permanent box.
  - zettelkasten.de points out that Ahrens' taxonomy is internally inconsistent. [6]
- **For Duo:** Ahrens' project notes vs. permanent notes is the same split Duo faces between session and project artifacts and durable knowledge. Fleeting notes have a short life by definition, so an inbox that nags about anything older than a few days fits the method.

### 1.4 Evergreen notes (Andy Matuschak)

- "Evergreen notes are written and organized to evolve, contribute, and accumulate over time, across projects." VERIFIED [7]
- Principles, VERIFIED [7]:
  - atomic
  - concept-oriented
  - densely linked
  - "Prefer associative ontologies to hierarchical taxonomies"
  - "Write notes for yourself by default"
- The practice includes "A **writing inbox** for transient and incomplete notes" and "A **reading inbox** to capture possibly-useful references." VERIFIED [7]
- "'Better note-taking' misses the point; what matters is 'better thinking'". Most people "take only transient notes." VERIFIED [7]
- Matuschak's notes use **concept titles that are claims or full phrases** (e.g. "Evergreen notes should be atomic"), so the title alone carries the idea. VERIFIED by observing [7]

### 1.5 GTD (David Allen)

- The five steps are Capture ("Collect what has your attention"), Clarify ("Process what it means": is it actionable? If yes, the next action; if not, trash, reference, or hold), Organize, Reflect ("Review frequently"), and Engage. VERIFIED [8]
- **Weekly Review** has three phases [9], VERIFIED:
  - Get Clear: collect loose papers and materials, **"Get 'In' to zero,"** empty your head.
  - Get Current: review action lists, past and upcoming calendar, Waiting For, and project lists.
  - Get Creative: review Someday/Maybe, "be creative & courageous."
  - GTD calls the review the critical success factor. [9]
- The two-minute rule ("if it takes less than two minutes, do it now") is in Allen's book; it wasn't on the pages I fetched. UNVERIFIED.
- **For Duo:** "inbox zero" in GTD means every item has been **decided** (trash, reference, next action, project), not that the work is done. An AI triage pass in Duo can propose that decision per item; the user confirms in a batch.

### 1.6 Maps of Content and ACE (Nick Milo, Linking Your Thinking)

- **ACE** stands for Atlas, Calendar, Efforts: "the head spaces we orient our thoughts around." VERIFIED [10]
  - Atlas covers knowledge and relatedness ("Where would you like to go?").
  - Calendar covers time ("What's on your mind?"), and is where daily notes live.
  - Efforts covers action and importance ("What can you work on?").
  - Milo prefers "Efforts" to "Projects." VERIFIED in summary form [10]
- Milo's vaults also use a `+` (inbox/"Add") folder and an `x` folder for templates and attachments. UNVERIFIED (not on the fetched page).
- **MOC:** "a cluster of information that maps 'things' in context with other 'things'." The trigger to create one is the **Mental Squeeze Point**: "Whenever you start to feel that tickle of overwhelm … create a new MOC." VERIFIED [11]
- Milo says structure must be earned, not pre-built. UNVERIFIED (search summary of Milo's posts [10b]).
- **For Duo:** a MOC is just a Markdown note made mostly of `[[links]]`. Duo can generate or refresh one for a project folder, such as a project index note. That's an Obsidian-native artifact; a proprietary index would not be. The Mental Squeeze Point is a good, user-legible cue for offering "make a map of this project."

---

## 2. Obsidian specifics

Obsidian's help moved from help.obsidian.md to **obsidian.md/help/** (301 redirects observed). VERIFIED.

### 2.1 Daily notes (core plugin) [12]

Settings, VERIFIED:

| Setting | Behaviour |
|---|---|
| Date format | Default `YYYY-MM-DD`, using Moment.js tokens. Tokens can create **subfolders**: `YYYY/MMMM/YYYY-MMM-DD` produces `2023/January/2023-Jan-01`. |
| New file location | A folder for daily notes. |
| Template file location | Its content is copied into each new daily note. |

Other behaviour, VERIFIED:
- "Open today's daily note" opens the note, or creates it if it doesn't exist.
- With the plugin enabled, any `date` property renders as a link to that day's note.
- An "Open daily note on startup" toggle exists in the app but wasn't on the page I fetched. UNVERIFIED.

Config keys:
- The plugin's options object holds **`folder`, `format`, `template`**. VERIFIED from the source of `obsidian-daily-notes-interface`, the shared library other plugins use to read these settings [13].
- Those options are persisted at `.obsidian/daily-notes.json`, with an `autorun` key for open-on-startup. UNVERIFIED: no public doc; open a real vault to confirm.
- A missing key means the default applies (vault root, `YYYY-MM-DD`, no template). UNVERIFIED but standard behaviour.

### 2.2 Unique note creator (formerly the "Zettelkasten prefixer") [14]

- The help page documents only **Template file location** (empty by default), configured under Settings → Core plugins → Unique note creator. VERIFIED
- Its example names a note made at 09:45 on 2024-01-01 `202401010945`, which implies a default prefix of `YYYYMMDDHHmm`. VERIFIED (example) [14]
- The settings UI also has a prefix format and a "New file location." UNVERIFIED: not on the help page.
- Config file is `.obsidian/zk-prefixer.json`. A forum report confirms the folder path is stored there [15]. Its keys are likely `folder`, `format`, `template`. UNVERIFIED
- An 0.5.x-era changelog says it "will automatically increment the minute if the file already exists." UNVERIFIED (search snippet of the changelog) [15]

### 2.3 Templates (core plugin) [16]

Variables, VERIFIED:
- `{{title}}` is the active note's title.
- `{{date}}` defaults to `YYYY-MM-DD`.
- `{{time}}` defaults to `HH:mm`.
- Format overrides use Moment tokens after a colon: `{{date:YYYY}}`, `{{time:HH:mm}}`.

Settings: Template folder location, Date format, Time format. VERIFIED

Gotcha, VERIFIED: the Properties UI can rewrite unquoted template variables in frontmatter. Edit templates in Source mode, or quote them (`created: "{{date}}"`).

Config file `.obsidian/templates.json` with key `folder` (and `dateFormat`, `timeFormat` when changed). UNVERIFIED.

Only these three variables exist in core. Anything else in `{{…}}` is left literal. UNVERIFIED (consistent with the docs listing only three).

### 2.4 Properties [17]

Properties are YAML frontmatter between `---` lines. JSON is accepted but saved back as YAML. VERIFIED

Types, VERIFIED:
- Text
- List
- Number
- Checkbox
- Date (`YYYY-MM-DD`)
- Date & time (`2020-08-21T10:30:00`)
- Tags (only for `tags`)

Each property name has **one type vault-wide**. VERIFIED. The type map is stored in `.obsidian/types.json`. UNVERIFIED (the help page doesn't say).

Default and reserved keys, VERIFIED:
- **`tags`**, **`aliases`**, **`cssclasses`**, all lists.
- For Publish: `publish`, `permalink`, `description`, `image`, `cover`.
- Singular `tag`, `alias`, `cssclass` are deprecated, with default support ending in 1.9.

Rules, VERIFIED:
- **Internal links in properties must be quoted** (`"[[Link]]"`). Obsidian adds the quotes when you type, but "templating plugins may not."
- Nested properties and Markdown in properties are unsupported.
- Names must be unique within a note.

**For Duo:** write lists as block lists, quote every wikilink, never nest objects, use the plural reserved keys, and pick one type per key across everything Duo writes (e.g. `created` is always Date & time). A key that is a Date in one Duo note and Text in another will be coerced or flagged in Obsidian.

### 2.5 Bases (core plugin) [18][19][20]

- "Bases is a core plugin that lets you create database-like views of your notes." Views can be saved as a **`.base`** file or embedded in a Markdown `base` code block. VERIFIED [19]
- Layouts: Table, List, Cards, Kanban, Map; plugins can add more. VERIFIED [19]
- `.base` is YAML. Top-level keys, VERIFIED [18]:
  - `filters` (with `and` / `or` / `not`)
  - `formulas` (referenced as `formula.x`)
  - `properties` (display config, e.g. `displayName`)
  - `summaries`
  - `views` (each with `type`, `name`, and optionally `filters`, `order`, `limit`, `groupBy`, `summaries`)
- What it queries, VERIFIED [18]:
  - **note properties** (frontmatter: `note.status` or just `status`)
  - **file properties** (`file.name`, `file.folder`, `file.mtime`, `file.ext`, `file.size`, `file.tags`, `file.links`, functions like `file.hasTag("x")`)
  - formulas
  - `this`: the base file itself, the embedding note when embedded, or the active file when in the sidebar
- Embedding: `![[File.base]]`, or `![[File.base#View]]` for a specific view, or a fenced `base` block. VERIFIED [20]
- **For Duo:** Bases is the official, file-based way to get "a dashboard of my inbox" or "all notes in this project with status: open." For example: `filters: and: [file.inFolder("Inbox")]`, sorted by `file.ctime`. Duo can write `.base` files that Obsidian renders natively. Duo would then need to render them itself, or at least not corrupt them. Bases supersedes much of what people used Dataview for.

### 2.6 Web Clipper [21][22][23]

- A browser extension for Chrome, Brave, Arc, Orion, Firefox, Safari and Edge. It saves locally to the vault, has highlighting, and has an **Interpreter** (natural-language prompts that extract or transform page data with an LLM). Templates use variables, filters and logic. VERIFIED [21]
- Template **behavior** options, VERIFIED [22]:
  - Create a new note
  - Add to an existing note (top or bottom)
  - **Add to daily note** (top or bottom; needs Daily notes enabled)
- **Triggers:** URL prefix, `/regex/`, or `schema:@Recipe…`. The first match wins; if nothing matches, the first template in the list is used. VERIFIED [22]
- **Default template**, VERIFIED from source [23]:
  - `behavior: 'create'`, `noteNameFormat: '{{title}}'`, **`path: 'Clippings'`**, content `{{content}}`.
  - Properties: `title` (text, `{{title}}`), `source` (text, `{{url}}`), `author` (multitext, as wikilinks), `published` (date), `created` (date, `{{date}}`), `description` (text), **`tags: clippings`**.
- **For Duo:** an Obsidian user's vault very likely has a `Clippings/` folder full of notes with `source:` and `tags: [clippings]`. That's a de facto "reading inbox." Duo can treat `Clippings/` (or anything tagged `clippings`) as inbox material without inventing a new convention. Reusing the key names `source`, `created` and `tags` keeps Duo's captures consistent with clips.

### 2.7 New-note location, links, backlinks, graph, bookmarks

- **Settings → Files and links → Default location for new notes** offers "Vault folder", "Same folder as current file", or "In the folder specified below." VERIFIED [24]
- Related settings: New link format (shortest path / relative / absolute), Use Wikilinks, and Default location for new attachments (vault folder, specified folder, same folder, or subfolder under current folder). VERIFIED [24]
- Likely `app.json` keys: `newFileLocation` (values `root` / `current` / `folder`), `newFileFolderPath`, `attachmentFolderPath`, `useMarkdownLinks`, `newLinkFormat`, `alwaysUpdateLinks`. UNVERIFIED: forum and plugin code only [25].
- **Links** [26], VERIFIED:
  - Wikilinks are the default; Markdown links need URL-encoded paths.
  - Clicking a link to a note that doesn't exist **creates it**. If the link contains a folder path, it's created there, not in the default location.
  - Headings link with `[[Note#Heading]]`; blocks with `[[Note#^id]]`. Block links "don't work outside Obsidian."
  - Renaming a file auto-updates links unless the user turns that off.
- **Backlinks** pane [27], VERIFIED:
  - **Linked mentions** come from notes that link to the active note.
  - **Unlinked mentions** come from notes that contain its name without a link.
  - It can also be shown at the bottom of the note ("Backlink in document").
- **Outgoing links** pane lists the note's links plus unlinked mentions of other notes' names or aliases, with one-click linking. VERIFIED [28]
- The help page doesn't define "unresolved links." The graph's "Existing files only" filter hides links to notes that don't exist yet. VERIFIED [29]
- **Graph** [29], VERIFIED:
  - Global graph, and a local graph with a depth slider.
  - Filters for tags, attachments, existing files only, and orphans.
  - Colour groups defined by search queries.
  - An animate time-lapse by creation time.
- **Bookmarks** can hold files, folders, searches, headings, blocks, graphs and links, organized in groups. VERIFIED [30]. They're stored in `.obsidian/bookmarks.json`. UNVERIFIED.
- **`.obsidian/` folder** [31], VERIFIED:
  - It holds "all the settings files pertaining to your vault."
  - Its name can be changed ("Override config folder", which must start with `.`).
  - Duo must therefore **not hard-code `.obsidian`**. It should detect a vault by any dot-folder containing `app.json` or `core-plugins.json`. That detection heuristic is UNVERIFIED.
- Typical contents: `app.json`, `appearance.json`, `core-plugins.json`, `community-plugins.json`, `daily-notes.json`, `templates.json`, `zk-prefixer.json`, `bookmarks.json`, `graph.json`, `hotkeys.json`, `types.json`, `workspace.json`, and `plugins/<id>/data.json`. UNVERIFIED: the help page lists none of them.

### 2.8 Community plugins

**QuickAdd** [32], VERIFIED:
- A **Capture choice** writes text to a target file. "Capture to" takes a path, which may contain format syntax; `Inbox` becomes `Inbox.md`. It can also capture to the active file.
- Options: "Create file if it doesn't exist" (optionally from a template); Task (`- [ ] …`); write position (top, bottom, cursor, or after/before a matching line such as a heading, with "insert at end of section" and "create line if not found").
- The capture format defaults to `{{VALUE}}`; for example `- {{DATE:HH:mm}} {{VALUE}}`.
- Tokens: `{{VALUE}}`, `{{DATE[:fmt]}}`, `{{VDATE}}`, `{{TIME}}`, `{{LINKCURRENT}}`, `{{DAILY}}` (the daily-note path from core or Periodic Notes settings), `{{TEMPLATE:path}}`, `{{MACRO}}`, `{{FIELD}}`, `{{SELECTED}}`, `{{RANDOM}}`, and more.
- The canonical QuickAdd inbox pattern is a global hotkey (via Obsidian's hotkeys) that prompts for one line and appends `- HH:mm text` under `## Inbox` in today's daily note or in `Inbox.md`.

**Templater** [33][34]:
- Syntax is `<% … %>`, e.g. `<% tp.date.now("YYYY-MM-DD") %>`, `tp.file.title`. VERIFIED [33]
- Execution commands are `<%* … %>` (JavaScript) and dynamic commands are `<%+ … %>`; both exist. UNVERIFIED (named in nav only).
- "Trigger Templater on new file creation" listens for file creation and replaces commands in the new file's content, using **folder templates** (deepest folder wins, `/` is the catch-all) or **regex templates**. The docs warn it is risky if new files contain unsafe content. VERIFIED [34]
- **Implications for a non-Templater app:**
  - Templater tags are plain text, so any other reader (Duo, GitHub, core Obsidian) **shows `<% … %>` literally**. Inference from the syntax; UNVERIFIED as stated behaviour.
  - Worse: if Duo **creates a file inside a folder that has a Templater folder template**, and Obsidian is running with the trigger enabled, **Templater may inject template content into Duo's new file**. Inference from [34].
  - Duo should never execute Templater code (it is arbitrary JavaScript). It may optionally offer to resolve a small safe subset (`tp.date.now`, `tp.file.title`), but is safer leaving template files alone.

**Dataview** [35], VERIFIED:
- Inline fields: `Key:: Value` on its own line, `[key:: value]` inline, and `(key:: value)` (key hidden in Reading mode).
- Frontmatter keys become fields automatically.
- Implicit fields such as `file.cday`, `file.outlinks`, `file.tasks`.
- Queries live in fenced `dataview` (DQL) or `dataviewjs` blocks. UNVERIFIED in this session; widely known.
- **For Duo:** `key:: value` lines are plain text, so they're harmless to preserve. Duo should never "clean them up."

**Tasks** [36][37], VERIFIED:
- Tracks `- [ ]` checklist items across the vault and writes status changes back to the source file.
- Date signifiers: 📅 due, ⏳ scheduled, 🛫 start, ➕ created, ✅ done, all `YYYY-MM-DD`; e.g. `- [x] take out the trash ✅ 2021-04-09`.
- Recurrence uses 🔁. An optional global filter (e.g. `#task`) is "not set by default."
- Queries are fenced `tasks` blocks. UNVERIFIED (not on the pages fetched).
- **For Duo:** if Duo writes action items, emitting `- [ ] text 📅 2026-10-10` makes them show up in Tasks queries. Duo should also preserve emoji and date suffixes when it toggles a checkbox: the Tasks plugin appends `✅ date` on completion.

**Kanban** (mgmeyers):
- "Create markdown-backed Kanban boards in Obsidian." VERIFIED [38]
- Format: frontmatter `kanban-plugin: board`, `## Heading` per lane, `- [ ]` list items as cards, and a trailing `%% kanban:settings … %%` JSON block. UNVERIFIED (third-party plugins that read the same format [39]).
- One such plugin reports that the original Kanban plugin **rebuilds the file on save and drops foreign content**. UNVERIFIED [39]
- Note that Bases now ships a Kanban layout too [19].

**Periodic Notes** (Liam Cain):
- Extends daily notes to weekly and monthly notes (the README covers weekly and monthly), each with its own folder, template and format. Defaults are `gggg-[W]ww` and `YYYY-MM`. VERIFIED [40]
- The shared library also reads `quarterly` and `yearly` settings, and checks an `enabled` flag per period to decide whether Periodic Notes overrides core Daily notes. VERIFIED from source [13]

**Readwise** (official Obsidian export) [41], VERIFIED:
- Exports to a base folder (default `Readwise/`), with optional `Books/`, `Articles/`, `Tweets/` and `Podcasts/` subfolders.
- Syncs on open, or every 1, 12 or 24 hours.
- **Append-only**: "nothing in Obsidian will ever be overwritten," and new highlights are appended.
- If you rename or move a file, it is **recreated** on the next export.
- Jinja2 templates for every part; YAML properties are off by default.
- **For Duo:** treat `Readwise/` as machine-owned and append-only. Never rename or move files inside it, or duplicates appear.

---

## 3. Other tools' capture, inbox and AI patterns

| Tool | Capture and inbox model | AI pattern | Status |
|---|---|---|---|
| **Logseq** | **Journals-first** outliner. Today's journal is the default capture surface, and every line is a block (`- `). A file graph has `journals/` (one file per day, `yyyy_MM_dd.md`), `pages/`, `assets/`, and `logseq/config.edn`. Properties use `key:: value`, not YAML. | Plugins only (not core). | Obsidian's importer confirms "Select the folder that contains `pages` and `journals`," that it converts page properties, block refs, workflow states and journal filenames, and that DB graphs are unsupported: VERIFIED [42]. File naming and `config.edn`: UNVERIFIED [43]. |
| **Tana** | Capture to **Today, Tomorrow, Inbox, or a pinned node**; a default is set by long-press. Voice memos are transcribed. **Supertags** turn a node into a typed object with template fields and defaults (e.g. a Task starts as `Status: Inbox`) and can extend other supertags. | When a supertag with fields is chosen at capture, **AI autofills the fields from what you said**. | VERIFIED [44][45] |
| **Reflect** | "Start with today's note." Backlinked graph. Web clips and audio memos. Notes "live in a folder you choose." | Bring your own API key. "Answers linked to source notes." Notes marked private are excluded from AI. | VERIFIED [46] (marketing page) |
| **Mem** | Capture "without stopping to organize." Voice ("Push-to-Remember"), bot-less meeting recording, web clipper. | A background agent "builds a living picture of your tasks, projects, and goals." Semantic search and chat. | VERIFIED [47] (marketing page) |
| **Notion AI** | n/a | Chat searches the workspace and connected apps (Slack, Drive) and shows only what the user can access. @-mention a page to focus it; a source picker ("All sources") narrows scope. Falls back to "world knowledge" if nothing is found. Answers have citations. | VERIFIED [48] |
| **Apple Notes Quick Note** | **Fn/Globe-Q** from anywhere, or the bottom-right **hot corner** by default. Safari "Add to Quick Note" for links and selections. Notes go to a **Quick Notes** folder. By default it reopens the last Quick Note unless "Always resume to last Quick Note" is turned off. | n/a | VERIFIED [49] |
| **Drafts** | Opens "ready for you to type" with no naming or filing, "keeping your text first." Actions then send or transform text. It also has Inbox, Flagged and Archive views. | n/a | Capture-first wording: VERIFIED [50]. Inbox/Flagged/Archive: UNVERIFIED (not on the fetched page). |
| **Claude Projects** | Self-contained workspaces with their own chats, **project knowledge** (uploaded docs, text, code) and **custom instructions**. Free accounts get 5 projects; sharing needs Team or Enterprise. | When knowledge nears context limits on paid plans, "Claude seamlessly enables **RAG mode** to expand capacity by up to 10x." A new beta of projects is "rolling out in stages, starting with Claude Code." | VERIFIED [51] |
| **NotebookLM** (Google's help now titles it "Gemini Notebook") | Sources are PDFs, websites, YouTube, audio, Google Docs and Slides. | Chat gives "grounded information … with clear in-line citations." Outputs include study guides, briefings, audio overviews and mind maps. | VERIFIED [52]. Source limits (50/notebook free, 300 Plus) and the "notebook guide" name: UNVERIFIED [53]. |

**Cross-cutting patterns.**
- **Default to a time-based capture target** (today's daily note) and **defer classification**: Logseq, Tana, Reflect, Apple Notes, Drafts.
- **Classify at capture only when it's one cheap gesture**, and let AI fill in the rest: Tana's supertag plus AI autofill.
- **AI Q&A is scoped and cited**: Notion's source picker, NotebookLM's sources, Claude Projects' knowledge, Reflect's private exclusion.

---

## 4. What goes wrong, and what makes capture stick

### Failure modes

- **Collector's fallacy.** "'To know about something' isn't the same as 'knowing something.'" Unread piles become an "alibi." The remedy is short cycles of research, reading and assimilation, with time limits. VERIFIED [54]
  - This lines up with Forte's "keep what resonates" filter [2] and Matuschak's "better thinking, not better note-taking" [7].
- **Inbox overflow and no processing ritual.**
  - GTD makes the weekly review the critical success factor, and "Get 'In' to zero" its first phase. VERIFIED [9]
  - Forte processes the inbox weekly in batches of 10–20. VERIFIED [2]
  - Ahrens' fleeting notes are meant to die within a day or two. UNVERIFIED [6]
  - An inbox with no review cadence becomes a second archive.
- **Over-organizing and premature structure.**
  - Forte: the system should "give you time, not take time." VERIFIED [1]
  - Milo: structure must be earned, and you make a MOC only at the Mental Squeeze Point. VERIFIED [11]
  - The zettelkasten.de intro: "It is not important where you place a new note as long as you can link to it." VERIFIED [5]
- **Tag sprawl.** Topic tags ("#diet") return everything vaguely related: "The search for tags gets really messy really fast." Use **object tags** only, and fix tagging habits early because "cleaning up later is difficult." VERIFIED [55]
- **Retrieval doubt suppresses capture.** If you don't trust you'll see a note again, you stop saving it. VERIFIED [4]
- **Tool lock-in and format drift.**
  - Readwise recreates files you've moved [41].
  - Kanban may rewrite whole files [39].
  - Templater can inject into new files [34].
  - Block links don't work outside Obsidian [26].
  - Each of these is a way a second tool can collide with an Obsidian vault.

### What makes capture stick

These are consistent across the sources above; the pattern is VERIFIED per tool where cited.

1. **One global gesture from anywhere.** Apple's Fn-Q and hot corner [49]; QuickAdd plus a hotkey [32]; Drafts opening ready to type [50].
2. **No decisions at capture time.** No title, folder or tags. Default to today's note or the inbox [12][44][50]. GTD separates Capture from Clarify for exactly this reason [8].
3. **Speed.** Forte says capturing takes seconds [2]. Anything that blocks on a network call, an AI round-trip or a picker loses captures.
4. **Context comes free.** Web Clipper's `source` and `created` properties [23], QuickAdd's `{{LINKCURRENT}}` [32], and Reflect keeping the source link with clips [46]. The capture tool should record where and when without asking.
5. **A trusted, scheduled processing step**, with AI proposing and the human confirming. Tana's AI autofill [45] and GTD's clarify questions [8] suggest a "triage" UI: suggested destination, tags and next action per item, accepted in bulk.
6. **Retrieval you trust.** Cited Q&A over your own notes [46][48][51][52] makes saving feel worthwhile [4].

---

## 5. Design implications for Duo

These are recommendations, not sourced facts.

- **Read the vault's own settings; don't impose new ones.** Use Daily notes `folder` / `format` / `template` (or Periodic Notes when its daily setting is `enabled`), Templates `folder`, Default location for new notes, attachment folder, and link style (wikilink vs. Markdown, shortest path). Resolve the config folder name rather than assuming `.obsidian`. Treat the exact JSON key names as UNVERIFIED until checked against a real vault.
- **Capture default:** append a line or block to today's daily note (`- HH:mm text`, QuickAdd style) or to an `Inbox.md` / `Inbox/` folder. Make it a single global hotkey, with no prompts.
- **Frontmatter discipline:**
  - Plural reserved keys only.
  - Quoted wikilinks; block-style lists; no nesting.
  - Reuse Web Clipper's names (`source`, `created`, `tags`, `author`, `description`).
  - One stable type per key, e.g. `created` is always Date & time.
- **Respect machine-owned folders and syntax.**
  - `Readwise/` is append-only: never move or rename inside it.
  - Leave `Clippings/` names alone unless the user files them.
  - Kanban boards: edit only via the board structure, or not at all.
  - Never execute or strip `<% %>`, `key:: value`, Tasks emoji, `%% … %%` comments, or `^block-ids`.
  - Be aware that creating a file in a folder that has a Templater folder template can trigger injection when Obsidian is open.
- **Views as Bases.** Express any inbox or project dashboard as a `.base` file or a `base` code block, so Obsidian shows the same view.
- **Distill like Forte, link like Luhmann.** AI summaries go at the top as a layer-4 block and never replace the source. AI-proposed links get a one-line reason (link context). Offer a MOC or index note when a project folder crosses a size threshold (the Mental Squeeze Point), not up front.
- **Processing ritual.** A weekly "Get In to zero" view that lists inbox items older than N days, with AI-proposed destinations (PARA folder or project, tags limited to existing object tags, next action as a `- [ ]` task) and bulk accept.

---

## Sources

Fetched during this research (primary):
1. Forte, "The PARA Method" — https://fortelabs.com/blog/para/
2. Forte, "Building a Second Brain: overview (CODE)" — https://fortelabs.com/blog/basboverview/
3. Forte, "Progressive Summarization" — https://fortelabs.com/blog/progressive-summarization-a-practical-technique-for-designing-discoverable-notes/
4. Forte, "The 4 Levels of PKM" — https://fortelabs.com/blog/the-4-levels-of-personal-knowledge-management/
5. zettelkasten.de, "Introduction to the Zettelkasten Method" — https://zettelkasten.de/introduction/
6. zettelkasten.de, "Concepts of Sönke Ahrens explained" (secondary on Ahrens) — https://zettelkasten.de/posts/concepts-sohnke-ahrens-explained/ (search result, not fetched)
7. Matuschak, "Evergreen notes" — https://notes.andymatuschak.org/Evergreen_notes
8. David Allen Co., "What is GTD?" — https://gettingthingsdone.com/what-is-gtd/
9. David Allen Co., "The GTD Weekly Review" — https://gettingthingsdone.com/2009/05/the-gtd-weekly-review/
10. Milo, "ACE Folder Framework" — https://blog.linkingyourthinking.com/notes/ace-folder-framework ; 10b. LYT search summary (Ideaverse pages)
11. Milo, "MOCs overview" — https://blog.linkingyourthinking.com/notes/mocs-overview (and "mental squeeze point" — https://blog.linkingyourthinking.com/notes/mental-squeeze-point, search snippet)
12. Obsidian Help, Daily notes — https://obsidian.md/help/plugins/daily-notes
13. liamcain/obsidian-daily-notes-interface, settings.ts — https://github.com/liamcain/obsidian-daily-notes-interface/blob/main/src/settings.ts
14. Obsidian Help, Unique note creator — https://obsidian.md/help/plugins/unique-note
15. Obsidian forum, zk-prefixer.json folder path — https://forum.obsidian.md/t/cant-change-folder-path-for-zettelkasten-notes/2624 ; Obsidian changelog v0.5.1 (search snippets)
16. Obsidian Help, Templates — https://obsidian.md/help/plugins/templates
17. Obsidian Help, Properties — https://obsidian.md/help/properties
18. Obsidian Help, Bases syntax — https://obsidian.md/help/bases/syntax
19. Obsidian Help, Bases — https://obsidian.md/help/bases
20. Obsidian Help, Create a base (Embed a base) — https://obsidian.md/help/bases/create-base
21. Obsidian Help, Web Clipper — https://obsidian.md/help/web-clipper
22. Obsidian Help, Web Clipper templates — https://obsidian.md/help/web-clipper/templates
23. obsidianmd/obsidian-clipper, template-manager.ts (default template) — https://github.com/obsidianmd/obsidian-clipper/blob/main/src/managers/template-manager.ts
24. Obsidian Help, Settings (Files and links) — https://obsidian.md/help/settings
25. Obsidian forum, newFileLocation / attachmentFolderPath — https://forum.obsidian.md/t/how-to-change-the-directory-of-default-location-for-new-notes-through-plugin-api/75371 (search snippets)
26. Obsidian Help, Internal links — https://obsidian.md/help/links
27. Obsidian Help, Backlinks — https://obsidian.md/help/plugins/backlinks
28. Obsidian Help, Outgoing links — https://obsidian.md/help/plugins/outgoing-links
29. Obsidian Help, Graph view — https://obsidian.md/help/plugins/graph
30. Obsidian Help, Bookmarks — https://obsidian.md/help/plugins/bookmarks
31. Obsidian Help, Configuration folder — https://obsidian.md/help/configuration-folder
32. QuickAdd docs, Capture choice — https://quickadd.obsidian.guide/docs/Choices/CaptureChoice
33. Templater docs, Syntax — https://silentvoid13.github.io/Templater/syntax.html
34. Templater docs, Settings — https://silentvoid13.github.io/Templater/settings.html
35. Dataview docs, Adding metadata — https://blacksmithgu.github.io/obsidian-dataview/annotation/add-metadata/
36. Tasks docs, Introduction — https://publish.obsidian.md/tasks/Introduction
37. Tasks docs, Dates — https://publish.obsidian.md/tasks/Getting+Started/Dates
38. mgmeyers/obsidian-kanban README — https://github.com/mgmeyers/obsidian-kanban
39. Community plugin pages describing the Kanban format (Boardwalk, React Kanban, Kanban for Professionals) — https://community.obsidian.md/plugins/boardwalk (search snippets)
40. liamcain/obsidian-periodic-notes README — https://github.com/liamcain/obsidian-periodic-notes
41. Readwise docs, Obsidian export — https://docs.readwise.io/readwise/docs/exporting-highlights/obsidian
42. Obsidian Help, Import from Logseq — https://obsidian.md/help/import/logseq
43. Third-party Logseq format guides (search snippets; docs.logseq.com too large to fetch)
44. Tana docs, Supertags — https://outliner.tana.inc/learn/features/supertags
45. Tana docs, Tana mobile (capture destinations, voice) — https://outliner.tana.inc/docs/tana-mobile
46. Reflect homepage — https://reflect.app/
47. Mem homepage — https://get.mem.ai/
48. Notion Help, "Everything you can do with Notion AI" — https://www.notion.com/help/guides/everything-you-can-do-with-notion-ai
49. Apple Notes User Guide (Mac), Start a Quick Note — https://support.apple.com/guide/notes/apdf028f7034/mac
50. Drafts docs, Getting started — https://docs.getdrafts.com/gettingstarted/
51. Claude Help Center, "What are projects?" — https://support.claude.com/en/articles/9517075-what-are-projects
52. Google Help, "Learn about Gemini Notebook" (NotebookLM) — https://support.google.com/notebooklm/answer/16164461
53. Secondary NotebookLM coverage (Siena, TechRepublic; search snippets)
54. zettelkasten.de, "The Collector's Fallacy" — https://zettelkasten.de/posts/collectors-fallacy/
55. zettelkasten.de, "Object tags vs. topic tags" — https://zettelkasten.de/posts/object-tags-vs-topic-tags/
