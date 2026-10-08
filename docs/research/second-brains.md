# LLM wikis and second brains in Duo: research and service design

Status: **study, every proposal [P]**; nothing here is decided until Geoff answers (Q-129 to Q-134, then DL-152). No product code. The boards are on the Design canvas named in `docs/design/second-brain-study/README.md`.

Geoff, 2026-10-07: "many users will have a project (or more) that contain LLM wiki and or OKF second brains. Please do research on these implementations and think about what features we could add (not just a pile of features but thoughtful service design) to better support these uses without getting in others' way." His standing rule for this work: "For everything we build, I want to maximize backwards compatibility with existing obsidian handling and/or OKF."

Marks: **[V]** verified against a primary source in this study (fetched docs, repos, the code); **[U]** unverified (secondhand, or not checked); **[P]** a proposal. The raw research, with every source, is in `docs/research/second-brain-sources/`:

| File | What |
|---|---|
| `llm-wiki.md` | Karpathy's pattern from his own tweet and gist, the implementations that followed (Claude Code skills, basic-memory, qmd, Ars Contexta, Obsidian-side agents), Google's OKF spec, failure modes, Obsidian compatibility |
| `second-brain-tools.md` | PARA/BASB, Zettelkasten, evergreen notes, GTD, MOCs; Obsidian's Daily notes, Unique notes, Templates, Properties, Bases, Web Clipper, links; QuickAdd, Templater, Dataview, Tasks, Kanban, Periodic Notes, Readwise; Logseq, Tana, Reflect, Mem, Notion AI, Apple Quick Note, Drafts, Claude Projects, NotebookLM |
| `legacy-okf.md` | Legacy Duo's OKF vault (`~/repos/duo`, read only): format, rollups, relinking, what shipped, what was reverted |
| `duo-today.md` | Duo v2 at `adfcd74` through a vault user's eyes, with `file:line` references |

---

## 0. In one screen

**Who.** Three kinds of people keep a folder of notes beside their Claude work: the *Obsidian keeper* (a vault of human-written notes, PARA or Zettelkasten, daily notes), the *wiki operator* (Karpathy's pattern: sources in `raw/`, pages Claude writes, `index.md`, `log.md`, a schema file), and the *work brain* (Geoff's case: an OKF-style vault fed from many places, processed by Claude, read in Obsidian). Everyone else uses Duo for code and documents and must not notice any of this.

**What the research says.** The value is in two loops, not in a second Obsidian:

1. **Capture is one gesture with no decisions** (Apple's Fn-Q, QuickAdd, Drafts, Tana [V]), and lands in an inbox or today's note.
2. **Processing is where the AI earns its keep**: Claude proposes where each item goes, the person confirms in a batch (GTD's clarify step, Forte's weekly 10–20 items [V]); for a wiki, Claude compiles one source into 10–15 pages and updates the index and log (Karpathy [V]).

Legacy Duo learned the same thing the hard way: its capture inbox and Claude's processing pass were the differentiator, while its rollup engine, Bases renderer and vault tabs duplicated Obsidian and were dropped as "a second product" (`legacy-okf.md` §3, §6).

**The design in one line [P].** A project (or Home) can be marked a **knowledge base**. That opt-in changes nothing on disk, gives the folder an **inbox** with a count, a **capture chord** that drops a note into it from anywhere through the templates engine, a **Process with Claude** button that opens a session with a ready-made, editable instruction, the wiki's own **index and log as tabs**, **search scoped** to it, and a few lines telling Claude where the schema, index, log and inbox are. Duo provides the moments; Claude does the work in a session; the files stay the user's and stay plain Markdown that Obsidian and OKF read.

**Before any of it:** the things a vault user trips on in the first hour are not missing features but Duo misreading their files (§2.4): wikilinks are dead text, Obsidian-style links say "isn't there", a `Tasks/` folder becomes Duo tasks, big folders truncate arbitrarily, and a vault can't be made a project without a back door. Those fixes help everyone and come first.

---

## 1. Who, and their files

| | Obsidian keeper | Wiki operator | Work brain (Geoff) |
|---|---|---|---|
| Shape | `.obsidian/`, PARA folders or a flat Zettelkasten, `Daily/`, `Templates/`, `Clippings/`, attachments | `raw/` (immutable sources), `wiki/` pages, `index.md`, `log.md`, `AGENTS.md` or `CLAUDE.md` as the schema | OKF: `type:` on every note, slug names + `title:`, quoted markdown links, `_index.md` with `okf_version`, `inbox/`, `templates/` (legacy `brainkit-gd`) |
| Who writes | The person; Claude sometimes | Claude ("You read it; the LLM writes it" [V]) | Both: captures from anywhere (Brainstem's email and assistant inbox), Claude files and links |
| Links | Wikilinks by default [V] | Either; Karpathy doesn't say [V]; OKF says markdown [V] | Quoted relative markdown links (DL-17) |
| What they want from Duo | Claude next to their notes without breaking them | A place to run ingest, query and lint loops and see what changed | Capture and processing, rollups, everything readable in Obsidian |
| Biggest fear | Duo rewriting their vault | Drift: the wiki quietly wrong (§2.1) | Losing a capture; a silent rewrite (legacy's auto-relink) |

A knowledge base is long-lived: a PARA *area* or *resource*, not a project with an end. Duo's guide says "a Duo project is a piece of work with an end" (`docs/guide/projects.md`). That tension is why the opt-in matters: a knowledge base tile shows its inbox and latest log entry, not a goal and health.

---

## 2. Research

### 2.1 The LLM wiki (`llm-wiki.md`)

- **Karpathy's pattern** (tweet 2026-04-02, gist "LLM Wiki" by 2026-04-04 [V]). Three layers: `raw/` sources, "immutable — the LLM reads from them but never modifies them"; the wiki, which "the LLM owns … entirely … You read it; the LLM writes it"; and a **schema** (CLAUDE.md or AGENTS.md) that "you and the LLM co-evolve". Three operations: **ingest** ("A single source might touch 10-15 wiki pages"; he prefers "one at a time and stay involved"), **query** ("good answers can be filed back into the wiki as new pages"), **lint** (contradictions, stale claims, orphans, missing pages, missing cross-references). `index.md` is the catalog the LLM reads first ("works surprisingly well at moderate scale (~100 sources, ~hundreds of pages)"); `log.md` is append-only with `## [YYYY-MM-DD] ingest | Title` entries. "Obsidian is the IDE; the LLM is the programmer; the wiki is the codebase." He names Web Clipper, qmd, Dataview, the graph and git. The gist fixes neither link syntax nor a frontmatter schema [V].
- **Implementations.** Skills (Astro-Han/karpathy-llm-wiki: a "Grounding Invariant" that every load-bearing fact appears verbatim in `raw/`, and "compile one source at a time, because index.md, log.md, and cascade updates are shared state" [V]); kfchou/wiki-skills (the index is *generated* from frontmatter and gitignored, the log is git trailers, "no merge conflicts"; asks what to emphasise before writing, shows diffs before updates [V]); MehmetGoekce/llm-wiki (L1 auto-loaded memory vs L2 wiki; 13 lint rules [V]); **Ars Contexta** (a Claude Code plugin predating the gist: `self/`, `notes/`, `ops/`; hooks that orient on start, validate every write, auto-commit; a fresh subagent per processing step [V]); **basic-memory** (an MCP server; entities with `- [category] fact` observations and `- relation [[Target]]` relations; Obsidian reads the same files [V]); **qmd** (local BM25 + vectors + rerank, CLI and MCP, explicit `qmd update`, endorsed by Karpathy [V]); Obsidian's own CLI and kepano's agent skills; Copilot for Obsidian now hosts Claude Code inside Obsidian "with their own CLI login" [V].
- **OKF** (Google's Open Knowledge Format [V]): v0.1 2026-06-12, **v0.2** 2026-07-24, now at `GoogleCloudPlatform/open-knowledge-format`. `type` is the only required key; producers may add keys and consumers must keep them; `index.md` and `log.md` are reserved at any level; links are standard markdown (bundle-absolute `/x.md` recommended), untyped, and broken links must be tolerated; **wikilinks are not OKF**. Its log is **newest first** under `## YYYY-MM-DD`, the opposite of Karpathy's append-only log. v0.2 adds optional `sources`, `generated`, `verified` (human review as a recorded fact), `status`, `stale_after`; the nested ones don't show in Obsidian's Properties panel but survive as YAML. The spec never names Karpathy; the lineage is inferred from the shared shape [V].
- **What goes wrong** [V from gist comments and READMEs unless marked]: drift (the LLM builds on its own summaries; "Health checks help, but that's just the LLM re-reading and guessing"); citations paraphrased away; schema drift (`status: active` vs `state:: running`); index bloat past a few hundred pages; ingest cost; **sync and merge conflicts on `index.md` and `log.md`**, which every ingest rewrites; and the human never reading it ("the slop machine in full perpetual motion"). The designs that hold up keep a human touchpoint: one source at a time, ask before writing, show the diff, record human review.

### 2.2 Second brains (`second-brain-tools.md`)

- **Methods** [V]: PARA files by actionability (Projects, Areas, Resources, Archives); BASB's CODE, with the inbox processed weekly in batches of 10–20 and summaries added on top, never replacing the source; Zettelkasten's atomic notes with time-based IDs; Matuschak's writing and reading inboxes; GTD's "Get 'In' to zero", where zero means *decided*, not done; Milo's maps of content, made only at the "Mental Squeeze Point", never up front.
- **Obsidian's mechanics** [V unless marked]: Daily notes has a folder, a Moment date format (slashes make subfolders) and a template; Templates fills only `{{title}}`, `{{date}}`, `{{time}}` (with formats) and warns that Properties can rewrite unquoted placeholders; Properties has one type per key vault-wide, plural reserved keys only, quoted links, no nesting; **Bases** (`.base`) is the native way to show an inbox or a list by folder and property; **Web Clipper**'s default template saves to `Clippings/` with `title`, `source`, `author`, `published`, `created`, `description`, `tags: clippings` (from its source); the config folder can be renamed, so a vault is not always `.obsidian/`. Where the settings live (`daily-notes.json`, `templates.json`, `app.json` keys) is [U] and must be checked in a real vault before Duo reads them.
- **Plugins to leave alone** [V unless marked]: Templater's `<% %>` is JavaScript Duo must never run, and with "trigger on new file creation" it may inject a folder template into a file Duo creates while Obsidian is open (inference); Readwise is append-only and recreates files that are moved; the Kanban plugin may rebuild its file on save [U]; Dataview's `key:: value`, Tasks' emoji dates, `%% %%` and `^block-ids` are plain text to keep byte for byte.
- **Other tools**: capture defaults to a time-based target and defers filing (Logseq journals, Tana's Today/Inbox, Reflect, Apple Quick Note on Fn-Q, Drafts "ready for you to type"); classification at capture only when it's one cheap gesture (Tana's supertags, with AI filling the fields); AI Q&A is **scoped and cited** (Notion's source picker, NotebookLM, Claude Projects' knowledge, Reflect leaving out private notes) [V].
- **What makes capture stick**: one global gesture; no decisions; speed (nothing waits on AI or the network); context for free (source and time recorded without asking); a trusted processing step; retrieval you trust, because doubt about seeing a note again stops people saving it (Forte [V]). **What goes wrong**: the collector's fallacy, inboxes with no ritual, premature structure, tag sprawl.

### 2.3 Legacy Duo's OKF vault (`legacy-okf.md`)

- Shipped June–September 2026 as "vault": OKF dialect (`type:` required, minted `id:`, slug files + `title:`/`aliases:`, quoted relative markdown links, `_index.md` with `okf_version`, generated `_index.md`/`_log.md` with a source-hash stamp), `inbox/` captures on ⇧⌘N, an Inbox column with a "stale > 1 week" chip, a rollup engine (a subset of Bases plus Duo-only extensions), `vault mv`/`relink`, and a skill that taught Claude the format. Geoff daily-drove it (`brainkit-gd`).
- **Reversals**: frontmatter links changed form three times because nobody checked Obsidian's parser first; relink and a link migration ran **silently on open**; legacy wrote `.obsidian/app.json`; an agent built a bespoke dashboard because two skill docs contradicted each other (ENH-234). v2 dropped the feature as "a second product grafted onto the first" (`legacy-requirements.md` §3) and kept the patterns: typed frontmatter edits, views derived from frontmatter.
- **Never built**: daily notes, a backlinks panel, a graph (Obsidian was the companion).
- **Lessons that carry**: put the effort into the agent layer, not a second Obsidian; one link format (DL-17); check formats in real Obsidian and on GitHub before locking them; never write `.obsidian/`, never rewrite silently (LR-26); contradictory agent guidance is a bug (LR-56); slug inbox names (legacy's spaced names forced `<…>` links).

### 2.4 Duo today, through a vault user's eyes (`duo-today.md`)

**Fits**: Duo writes Obsidian-normal frontmatter and edits only its own keys, line by line; never writes `.obsidian/`; search skips dot-folders; the properties block has typed rows; the templates engine fills exactly Obsidian's placeholders and leaves Templater's alone; Home maps onto a PARA vault (projects found 4 levels down, topics named by folders); `.duo/` is invisible to Obsidian.

**What a vault user trips on first** (each checked in the code for this study; F-202 to F-205):

1. **Getting the vault in.** Discovery looks only for `PROJECT.md`, `HOME.md` or `CLAUDE.md`; a vault with no Claude history isn't listed and `duo2 project make` refuses it. The routes are making the whole vault Home or running `claude` in it from Terminal first. DL-147's "A folder I have" is the decided fix, not built.
2. **Links are dead.** The editor has no wikilink handling: `[[Note]]` and `![[img.png]]` are plain text. A markdown link resolves only against the note's own folder (`AppModel+Links.swift:43-46`), so Obsidian's default "shortest path" links to notes in other folders say "isn't there" (F-202).
3. **Their `Tasks/` folder becomes Duo tasks.** Every `.md` in `tasks/` is a task with no `type: task` check, status defaulting to open (`TaskNotes.swift:31-38`); on a case-insensitive disk a vault's `Tasks/` matches (F-203).
4. **Big folders truncate arbitrarily.** The tree's 2000-entry cap is checked while listing and the list sorted after (`LiveSnapshot.swift:374-394`), so which notes show depends on directory order; no filter, no newest-first (F-204).
5. **No capture.** No global hotkey, daily note or inbox verb; New from Template names the file after the template (`inbox 2.md`) and can't take a title, text or keys; Moment formats like `gggg-[W]ww` come out literal (`Templates.swift:187-207`, F-205).

Runners-up: Claude is told `goal`/`health`/`next`, but nothing about `AGENTS.md`, `index.md` or `log.md`; semantic search is English-only (`bge-small-en`) and scans every vector; a session started in `wiki/` shows as a stray folder.

**Hooks to build on** (names from the code): `Templates.make`/`render`/`setting` (a new kind is a few lines); `AppModel.draft(_:into:)` (types an instruction, never sends) and `newSession(in:prompt:)`; Send to Claude; `ProjectContext`/`TaskContext` hooks (what a session is told at start and on change); `DuoAction.primer()` (new verbs are advertised to Claude automatically); `SearchQuery.projects`/`findSimilar`; `PropertyCorpus`; `SheetCenter`/`DuoQuestion`/`registerUndo`; `openLink` (the one place for wikilink resolution); `ProjectDiscovery.walk` (where vault detection goes).

---

## 3. Principles [P]

1. **Opt-in, and invisible until then.** Nothing about knowledge bases shows, listens or writes until someone marks a folder as one. No chord is registered, no fold drawn, no line added to Claude's context. Code projects never see it.
2. **Files are the truth; Duo writes nothing it doesn't have to.** Marking a knowledge base writes nothing into the folder. A capture writes one new note. Duo never generates `index.md` or `log.md` (Claude or the user's tools do), never relinks on open, never moves a note by itself.
3. **Compatible by construction.** Every file Duo writes is plain Markdown with flat YAML that Obsidian's Properties, Templates and Bases and OKF read without loss: `type:` first (OKF's one required key), quoted links, block lists, plural reserved keys, one type per key, no Duo-only keys or syntax. Read the vault's own conventions (its inbox, templates, daily-notes settings, link style) before proposing Duo's.
4. **Duo sets up the moment; Claude does the work; the person decides.** Processing, ingest, linting and answering are Claude's, in an ordinary session the person can watch, interrupt and resume. Duo's buttons *draft* the instruction and never press Return (DL-112's rule), so the person always says go. No `-p`, no SDK, CLI login only.
5. **Keep a human touchpoint in every loop.** One batch at a time, a proposal before changes, the changed pages visible after. This is the research's answer to drift and "slop".
6. **Don't rebuild Obsidian.** No graph, no Bases renderer, no rollup engine, no plugin emulation. Obsidian stays the companion for the graph, Bases, mobile and its plugins; Duo is where Claude works on the same files.
7. **Instructions live where Claude Code looks.** A repeatable instruction ("process my inbox") is best a Claude Code command or skill in the folder, which Claude and the person can both read and edit, rather than a string inside Duo.

---

## 4. The journeys: a service blueprint [P]

Lanes: what the person does; what Duo shows (front stage); what Claude does; the files (back stage); what stays the person's.

| Journey | Person | Duo (front stage) | Claude | Files (back stage) | Stays the person's |
|---|---|---|---|---|---|
| **0. Set up** | Opens a vault or wiki folder in Duo; marks it a knowledge base | Detects `.obsidian/`, OKF `index.md`/`_index.md` with `okf_version`, `AGENTS.md`/`CLAUDE.md`, `raw/`+`wiki/`, an inbox-like folder (`inbox/`, `Inbox/`, `+/`, `00 Inbox/`, `Clippings/`); a sheet shows what it found and what it will use; says it writes nothing | — | Nothing written; Duo's note of the choice in `.duo/` (Q-130) | Which folder is the inbox; whether it's a knowledge base at all |
| **1. Capture** | Presses the chord anywhere, types or pastes, Return | A small capture panel: the knowledge base, a text field, Return saves; a URL pasted becomes `source` | — (no AI at capture: speed) | One new note in the inbox from `templates/new-note.md` (the project's, else Home's, else Duo's base): `type: note`, `title`, `created`, `source` when given; slug name `2026-10-07-pricing-sync.md` | The words; whether to open it |
| **2. See the inbox** | Glances at the tile or the project | A count on the tile and an INBOX fold in the project, newest first, oldest age shown | — | Read only | — |
| **3. Process the inbox** | Clicks **Process with Claude**, reads the drafted instruction, presses Return | A new session in the knowledge base, in chat, with the instruction drafted (the folder's `/process-inbox` command if it has one, else Duo's, Q-133); the session is linked to the inbox; when done it's Ready for review | Reads the schema, proposes per note: merge into a page, a new page, a task, or discard; waits; then edits, moves with links updated, appends to the log | Notes moved out of the inbox, pages edited, `log.md` appended (all Claude's, visible in the session) | Every decision: Claude proposes, the person confirms |
| **4. Ingest a source** (wiki) | Drops a PDF or clip into `raw/`, or right-clicks it | **Ingest with Claude** on the file's menu drafts "/ingest raw/x.pdf" or Duo's instruction (ENH-42) | Summarises, asks what to emphasise, updates 10–15 pages, the index and the log | `wiki/` pages, `index.md`, `log.md` | The source (immutable), what matters |
| **5. Ask** | Asks a question | Search scoped to the knowledge base (Q-134), and a chat session started in it reads the schema and index first | Answers with links to the pages; files a good answer back as a page when asked | Optional new page | Whether an answer is worth keeping |
| **6. Look after it** | Opens the Index or Log tab; occasionally asks for a check | Index and Log as tabs beside the Project tab (Q-132); **Check with Claude** drafts a lint instruction (ENH-42); a schedule is Claude Code's (ENH-43) | Lints: contradictions, orphans, missing pages, broken links, stale claims; writes a dated report | A report page; fixes only after a yes | What to fix |
| **7. Daily note** | Opens today's note, or captures into it | **Today** opens or makes today's note from Obsidian's Daily notes settings; capture can append a line to it (ENH-40) | Can summarise the day into it on request | `Daily/2026-10-07.md` from the vault's own template | The journal |
| **8. Rollups** | Wants a view across notes | Duo doesn't render rollups: Claude writes a `.base` (Obsidian shows it) or a Markdown/HTML page (Duo shows it) | Writes the query or page from a description | `.base`, `rollups/*.md` | Which views exist |

Two cross-cutting moments:

- **What Claude is told.** In a knowledge base, a session's start hook (beside `ProjectContext`) adds a few lines: "This folder is a knowledge base. Read AGENTS.md before changing pages. index.md lists the pages; log.md records changes. The inbox is inbox/ (12 notes)." Only paths and counts, said once and on change, never file contents (as DL-116 does for tasks).
- **Two sessions on one knowledge base.** Every ingest and processing pass rewrites `index.md` and `log.md` (§2.1). When Process or Ingest starts while another session in the same knowledge base is working, Duo says so in the drafted instruction's sheet: "Another session is changing this knowledge base. Wait for it, or go ahead." (C-58.)

---

## 5. Candidates, ranked [P]

Value: how much it helps the three kinds of people. Fit: how well it keeps the principles. Effort: S (days), M (a week or two), L (more).

| # | Candidate | Who it helps | Value | Fit | Effort | Verdict |
|---|---|---|---|---|---|---|
| 1 | **Read vaults correctly**: wikilinks drawn and followed (`[[Note]]`, `[[Note\|alias]]`, `[[Note#Heading]]`), shortest-path markdown links resolved by name across the folder, `![[image]]` drawn; never written (DL-17) | Every vault user | High | High | M | **v1, first** (prereq) |
| 2 | **Don't misread a vault's folders**: a note in `tasks/` is a task only with `type: task` or no `type`; the tree sorts before it caps and lists newest-first on request | Every vault user; everyone with big folders | High | High | S | **v1** (prereq) |
| 3 | **Bring a vault in**: DL-147's "A folder I have" (decided) | Every vault user | High | High | M (decided elsewhere) | **v1 dependency**, built by the project & task slice |
| 4 | **Mark a knowledge base** (detection, a sheet, writes nothing) and **tell Claude** where the schema, index, log and inbox are | All three | High | High | S | **v1** |
| 5 | **Inbox**: a count on the tile, an INBOX fold newest first | Keeper, work brain | High | High | S | **v1** |
| 6 | **Capture chord and panel** through the templates engine (`templates/new-note.md`, a new kind) | Keeper, work brain | High | High | M (a global hotkey via Carbon needs no permission [U]; the panel) | **v1** (Geoff's example) |
| 7 | **Process with Claude**: a session drafted with the folder's command or Duo's instruction | All three | High | High | S | **v1** |
| 8 | **Index and Log as tabs** | Wiki operator, work brain | Medium | High | S | **v1** |
| 9 | **Search scoped to the knowledge base** | All three | Medium | High | S (`SearchQuery.projects` exists) | **v1** |
| 10 | **Today's note** from Obsidian's settings, and capture into it | Keeper | Medium | High once the settings are verified | M | **Next** (ENH-40) |
| 11 | **Ingest, Check, File this answer** actions; a "pages this session changed" list | Wiki operator | Medium | High | S each | **Next** (ENH-42) |
| 12 | **Backlinks and unresolved links** under a note; make a page from an unresolved link | Keeper, wiki operator | Medium | High | M | **Next** (ENH-41) |
| 13 | **Scheduled checks** through Claude Code's own scheduling; the report shows in the Log | Wiki operator | Low–medium | Medium | S on Duo's side | **Later** (ENH-43) |
| 14 | **Search for big and non-English vaults** (multilingual model, an approximate index), and indexing a folder Duo doesn't list | Big vaults | Medium | High | M–L | **Later** (ENH-44) |
| — | AI at capture (auto-title, auto-file) | — | Low | Low (speed, decisions at capture) | — | **Drop**: capture must not wait |
| — | Duo generating `index.md`/`log.md` | — | Low | Low (shared state, two formats: OKF newest-first vs Karpathy append-only) | — | **Drop**: Claude or the user's tools own them |
| — | Graph view, a Bases or Dataview renderer, a rollup engine | — | Medium | Low (legacy's "second product") | L | **Drop**: Obsidian is the companion |
| — | Relinking on open, auto-migrations, writing `.obsidian/` | — | — | Breaks LR-26, DL-6 | — | **Never** |
| — | A separate "Brains" area of the app | — | Low | Low (a second product) | M | **Drop**: a knowledge base is a project or Home with a mark |

---

## 6. The v1 slice [P]

Prerequisites (help everyone, no opt-in): **#1 links** and **#2 folders**, plus DL-147's adopt flow (#3).

Then, behind the opt-in:

1. **Use as Knowledge Base…** on a project's or Home's menu, and as a checkbox in DL-147's "A folder I have" when a vault or wiki is detected. A sheet: what Duo found; Inbox (a folder, detected or `inbox/`, made on first capture); Index, Log, Schema (detected, or none); New notes from (the template in use); "Duo writes nothing in the folder." `duo2 kb use|off|show`.
2. **The tile and the project.** The tile's goal line becomes "Knowledge base · 12 in inbox · last change 2h ago" (from the log's newest entry when there is one). The left pane gets an **INBOX · 12** fold above the sessions: notes newest first with age, **Process with Claude** in its header, + to capture.
3. **Capture.** A global chord (Q-131) opens a small panel over whatever is in front: the knowledge base (last used; a popup when there are several), one field (first line is the title), Return saves, ⌘Return saves and opens, Esc discards after asking if there's text. A pasted URL fills `source`. The note: `templates/new-note.md` through `Templates.make` (a new `Kind.note`), named `<inbox>/<date>-<slug>.md`, collisions `-2`. Duo's base:

   ```markdown
   ---
   type: note
   title: "{{title}}"
   created: "{{date}}"
   source:
   ---

   # {{title}}

   ```

   `source` is written only when there is one. Every key is one the research found already in use (OKF's `type` and `title`, Web Clipper's `created` and `source`, DL-146's `created` as a date). `duo2 capture [--kb <p>] [--title …] [--source <url>] [--stdin | <text>]`.
4. **Process with Claude.** A new chat session in the knowledge base with the instruction drafted, not sent (Q-133): the folder's own `/process-inbox` when `.claude/commands/process-inbox.md` or a skill of that name exists; otherwise Duo's text, with **Save as Command…** to write it as `.claude/commands/process-inbox.md` (Claude Code's folder, invisible to Obsidian) so the person and Claude can edit it. `duo2 inbox [<kb>]`, `duo2 inbox process [<kb>]`.
5. **Index and Log tabs** beside the Project tab when the files exist; Log opens at the newest entry whichever way the file is ordered (Q-132). `duo2 kb index|log`.
6. **Scoped search.** Inside a knowledge base, ⇧⌘A opens with an **In <name>** scope token; ⌫ widens to everything (Q-134). `duo2 search --project <p>` already scopes.
7. **What Claude is told** (§4), through the hook beside `ProjectContext`; the primer lists the new verbs (DL-71).

Out of v1: Today's note (ENH-40), backlinks (ENH-41), Ingest/Check/File-this-answer (ENH-42), schedules (ENH-43), search scale (ENH-44).

Proof when it's built: the boards for the slice (once approved and exported), captures compared region by region; DuoChecks for the template (`type: note` first, quoted title, no Duo-only keys), for "a knowledge base writes nothing" (a fixture vault's bytes unchanged after marking), and for `tasks/` ignoring `type:` other than task; a round-trip of a captured note through Obsidian's Properties UI with no meaningful diff [U until run].

---

## 7. Questions, concerns, later

**Questions for Geoff** (`concerns-and-questions.md`):

- **Q-129 — What is a knowledge base in Duo?** A: any project or Home, marked (recommended). B: Home only. C: a separate kind with its own place on the map.
- **Q-130 — Where does the mark live?** A: Duo's own `.duo/` (recommended: writes nothing Obsidian sees, deletable, like DL-1's Duo-only facts). B: a key in the brief (`knowledge_base: true`, like DL-147's `project_brief`), visible to Obsidian and to Claude. C: a line in the folder's `CLAUDE.md`.
- **Q-131 — The capture chord.** A: global ⌃⌥⌘N, registered only once a knowledge base exists (recommended). B: in-app only. C: global, the user picks the keys in Settings first.
- **Q-132 — Index and log.** A: tabs beside the Project tab (recommended). B: one "Knowledge base" tab with the inbox, the latest log entries and a link to the index. C: nothing special; they're files.
- **Q-133 — Process with Claude's instruction.** A: the folder's `/process-inbox` command when there is one, else Duo's text with Save as Command… (recommended). B: Duo's text only, edited in Settings. C: always a command; Duo writes one on first use.
- **Q-134 — Scoped search.** A: an In <name> scope token, on by default inside a knowledge base (recommended). B: a separate Search Notes command. C: keep today's boost for the current project.

**Concerns:**

- **C-57 — Other tools write into the same folders.** A note Duo creates in a folder with a Templater folder template may get template code injected while Obsidian is open; Readwise recreates files that are moved; Obsidian Sync and iCloud can conflict with Claude's bulk edits. Mitigation: atomic writes (LR-35), never capture into machine-owned folders (`Readwise/`), document the Templater interaction, reconcile on open (LR-31).
- **C-58 — Parallel sessions collide on index.md and log.md.** Mitigation: the warning in §4; Duo's instruction says "one batch at a time"; LR-31 for open files.

**Later** (`enhancements.md`): ENH-40 Today's note; ENH-41 backlinks and unresolved links; ENH-42 Ingest, Check, File this answer, and the changed-pages list; ENH-43 scheduled checks; ENH-44 search for big and non-English vaults.

**Findings** (`findings.md`): F-202 links (wikilinks, shortest path, embeds); F-203 `tasks/` claimed by folder name; F-204 the tree's cap before sort; F-205 the templates engine's gaps for notes (Moment tokens, the vault's own date settings and template folder, no name for New from Template); F-206 the research facts that change Duo's format work (OKF v0.2 and its new home, reserved `index.md`/`log.md`, the two log orders, wikilinks not OKF, nested v0.2 keys unseen in Properties).
