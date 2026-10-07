# The "LLM wiki" pattern: Karpathy's description and what came after

*Research date: 2026-10-07. Every claim is marked **[V]** VERIFIED (I fetched the primary source and read the text) or **[U]** UNVERIFIED (secondhand, a search-engine summary, or a source I couldn't load). Numbered sources are listed at the end.*

---

## 1. Karpathy's pattern, as he wrote it

### 1.1 Timeline

| Date (UTC) | Artifact | Status |
|---|---|---|
| 2026-04-02 20:42 | X post "LLM Knowledge Bases" (status 2039805659525644595) [1] | [V] Full text and timestamp fetched through the fxtwitter API mirror |
| ~2026-04-04 | Gist "LLM Wiki" (`karpathy/442a6bf555914893e9891c11519de94f`) [2], shared as an "idea file" | [V] for the text. [U] for the exact creation date: the GitHub gist API returned 502 for the metadata, but the earliest gist comment is 2026-04-04T16:49Z, so the gist went up on or before that day. |
| 2026-04 to 2026-10 | 1,136 comments on the gist (last one 2026-10-05) | [V] Pulled from the comments API. Karpathy himself posted none of them. |

Secondary write-ups report the gist passing 5,000 stars and 5,000 forks. That is [U]; I couldn't load the gist metadata.

### 1.2 The tweet (2026-04-02): key lines [V] [1]

- "using LLMs to build personal knowledge bases for various topics of research interest … a large fraction of my recent token throughput is going less into manipulating code, and more into manipulating knowledge (stored as markdown and images)."
- **Data ingest:** "I index source documents (articles, papers, repos, datasets, images, etc.) into a raw/ directory, then I use an LLM to incrementally 'compile' a wiki, which is just a collection of .md files in a directory structure. The wiki includes summaries of all the data in raw/, backlinks, and then it categorizes data into concepts, writes articles for them, and links them all." He uses the **Obsidian Web Clipper** to turn web articles into .md, and "a hotkey to download all the related images to local so that my LLM can easily reference them."
- **IDE:** "I use Obsidian as the IDE 'frontend' … the LLM writes and maintains all of the data of the wiki, I rarely touch it directly." He mentions Marp for slides.
- **Q&A:** his wiki on one research topic is "~100 articles and ~400K words". "I thought I had to reach for fancy RAG, but the LLM has been pretty good about auto-maintaining index files and brief summaries of all the documents."
- **Output:** "I like to have it render markdown files for me, or slide shows (Marp format), or matplotlib images … Often, I end up 'filing' the outputs back into the wiki … So my own explorations and queries always 'add up' in the knowledge base."
- **Linting:** "LLM 'health checks' over the wiki to e.g. find inconsistent data, impute missing data (with web searchers), find interesting connections for new article candidates."
- **Extra tools:** "I vibe coded a small and naive search engine over the wiki, which I both use directly (in a web ui), but more often I want to hand it off to an LLM via CLI."
- **Further:** he considers "synthetic data generation + finetuning to have your LLM 'know' the data in its weights."
- **Closing:** "You rarely ever write or edit the wiki manually, it's the domain of the LLM. I think there is room here for an incredible new product instead of a hacky collection of scripts."

### 1.3 The gist "LLM Wiki" (the idea file) [V] [2]

It opens by framing itself as an idea file: "designed to be copy pasted to your own LLM Agent (e.g. OpenAI Codex, Claude Code, OpenCode / Pi, or etc.) … your agent will build out the specifics in collaboration with you."

**Core contrast with RAG.** "the LLM is rediscovering knowledge from scratch on every question. There's no accumulation." In the wiki model, "The knowledge is compiled once and then *kept current*, not re-derived on every query." The wiki is "a persistent, compounding artifact."

**Division of labour.** "You never (or rarely) write the wiki yourself — the LLM writes and maintains all of it. You're in charge of sourcing, exploration, and asking the right questions." Also: "I have the LLM agent open on one side and Obsidian open on the other … **Obsidian is the IDE; the LLM is the programmer; the wiki is the codebase.**"

**Three layers.**
1. **Raw sources**: "immutable — the LLM reads from them but never modifies them. This is your source of truth."
2. **The wiki**: "a directory of LLM-generated markdown files. Summaries, entity pages, concept pages, comparisons, an overview, a synthesis. The LLM owns this layer entirely … You read it; the LLM writes it."
3. **The schema**: "a document (e.g. CLAUDE.md for Claude Code or AGENTS.md for Codex) that tells the LLM how the wiki is structured … it's what makes the LLM a disciplined wiki maintainer rather than a generic chatbot. You and the LLM co-evolve this over time."

**Operations.**
- **Ingest**: "the LLM reads the source, discusses key takeaways with you, writes a summary page in the wiki, updates the index, updates relevant entity and concept pages across the wiki, and appends an entry to the log. A single source might touch 10-15 wiki pages." Karpathy prefers "to ingest sources one at a time and stay involved," but batch ingest is allowed.
- **Query**: "The LLM searches for relevant pages, reads them, and synthesizes an answer with citations." Answers can be a markdown page, a table, a Marp deck, a matplotlib chart or a canvas. "**good answers can be filed back into the wiki as new pages.**"
- **Lint**: "contradictions between pages, stale claims that newer sources have superseded, orphan pages with no inbound links, important concepts mentioned but lacking their own page, missing cross-references, data gaps that could be filled with a web search."

**Index and log.**
- `index.md` "is content-oriented … each page listed with a link, a one-line summary, and optionally metadata like date or source count. Organized by category … The LLM updates it on every ingest. When answering a query, the LLM reads the index first … works surprisingly well at moderate scale (~100 sources, ~hundreds of pages) and avoids the need for embedding-based RAG."
- `log.md` "is chronological. It's an append-only record … ingests, queries, lint passes." Entries use a parseable prefix: "`## [2026-04-02] ingest | Article Title`", which makes "`grep "^## \[" log.md | tail -5`" work.

**Tooling he names.**
- **qmd** for search: "hybrid BM25/vector search and LLM re-ranking, all on-device … both a CLI … and an MCP server."
- **Obsidian Web Clipper.**
- A fixed attachment folder (e.g. `raw/assets/`) plus a hotkey for "Download attachments for current file".
- The **graph view**, to see hubs and orphans.
- **Marp.**
- **Dataview** over YAML frontmatter ("tags, dates, source counts").
- "The wiki is just a git repo of markdown files."

**Framing.** He cites Vannevar Bush's Memex: "The part he couldn't solve was who does the maintenance. The LLM handles that." The gist closes: "This document is intentionally abstract … Everything mentioned above is optional and modular."

Two things the gist does not specify:
- **Link syntax.** It never says wikilinks or markdown links. It only says "interlinked", "cross-references" and Obsidian graph view, and the graph view implies links that Obsidian resolves.
- **A frontmatter schema.** Frontmatter is optional and exists for Dataview.

---

## 2. Implementations that followed

### 2.1 Claude Code / Agent Skills packages of the gist

**Astro-Han/karpathy-llm-wiki** (~2.4k stars [U], from a third-party listing) [3] [V for README and SKILL.md]

- **Contract:**
  - `raw/` holds immutable sources in topic subfolders, dated filenames such as `raw/topic/2026-04-03-source-article.md`.
  - `wiki/<topic>/<concept>.md` holds the articles.
  - `wiki/index.md` is "one row per article, grouped by topic, with link + summary + Updated date".
  - `wiki/log.md` is append-only and uses Karpathy's `## [YYYY-MM-DD] ingest | <title>` header.
  - It ships as a single `SKILL.md` that installs into Claude Code, Cursor, Codex or OpenCode.
- **Loops:**
  - *Ingest* is fetch to raw, then **triage** (log only if nothing is new), compile, cascade updates, and update index and log.
  - *Query* reads the index first, then full-text greps "with the topic's key terms *and their synonyms*". It may archive the answer as a page and prefix its index summary with `[Archived]`.
  - *Lint* has three tiers: safe auto-fixes (index consistency, internal links), mechanical reports, and judgment reports.
- **Notable rules:**
  - The **"Grounding Invariant"**: "Every load-bearing fact in wiki/ — numbers, dates, direct quotes — exists verbatim in the raw/ files linked by that article's Raw field." Lint checks this with grep.
  - Multi-source research may fetch in parallel, but "compilation must not — compile one source at a time, because index.md, log.md, and cascade updates are shared state."
  - Links are **standard markdown links**, not wikilinks.
- **"Design Boundaries" section.** Its list of things deliberately not built is a useful survey of the ecosystem: no source-hash freshness tracking, no numeric confidence scores, no per-article review dates, no vector or graph search ("at 50K–100K tokens of curated wiki, grep and read are more reliable"), no typed relation ontologies ("link semantics live in the prose around the link"), no MCP, no hooks or schedules ("those belong to the agent harness"). **OKF conformance is "tracked; will be revisited."**
- **Self-reported production stats:** 94 articles, 99 sources, 87 log entries in 7 days.

**kfchou/wiki-skills** (Claude Code plugin) [4] [V]

- **Skills:** `wiki-init`, `wiki-ingest`, `wiki-query`, `wiki-lint`, `wiki-update`, `wiki-audit`, `wiki-merge`.
- **Layout:** `SCHEMA.md` at the root (conventions plus the wiki root path; "how skills find the wiki"), `raw/`, `wiki/overview.md`, and flat `wiki/pages/<slug>.md`.
- **The design choices most relevant to merge conflicts:**
  - "**The index is generated, not hand-maintained.** `wiki/index.md` is a gitignored runtime artifact rebuilt from each page's `category` + `summary` frontmatter … so it never drifts from the pages — no manual entry bookkeeping, no merge conflicts."
  - "**The operation log comes from git.** … each operation is recorded as a commit carrying a `Wiki-Op:` trailer … Skills suggest the commit and commit on your confirmation — they never auto-commit." A `log.md` exists only for non-git wikis.
  - A tracked pre-commit hook runs deterministic, no-LLM checks and blocks a commit on an unresolved contradiction flag, missing frontmatter, a broken `[[link]]` or a slug collision.
- **Behaviours:**
  - Ingest "surfaces key takeaways and asks what to emphasize *before* writing anything."
  - Update "always shows diffs before writing."
  - `wiki-audit strong` uses a different-provider model (codex or gemini) as an adversarial fact-checker.
  - Lint writes a dated report page.
- **Links:** `[[wikilinks]]`, with the slug as the concept's identity (`wiki-merge` rewrites inbound links when it merges or splits pages).

**MehmetGoekce/llm-wiki** [5] [V]

- **Commands:** `/wiki ingest|query|lint|prune|status`.
- **L1/L2 split:**
  - L1 is auto-loaded Claude Code memory (~10–20 files: rules, gotchas, credentials).
  - L2 is the wiki (~50–200 pages, loaded on demand).
  - Routing rule: "Would the LLM making a mistake without this knowledge be dangerous or embarrassing? Then it belongs in L1."
- **Ingest phases:** analyze, scan the wiki, update pages, a quality gate (required properties, ≥1 cross-ref, no credentials), report, then `git commit`.
- **Superseded facts:** the block is rewritten and "the old wording moves into a collapsed `History`."
- **Prune:** evicts cold pages from the hub index into an `### Archive` section, based on an access log.
- **Lint:** 13 rules, including **index drift** and credential leaks.
- **Schema:** "the contract between you and the LLM … Without it … one uses `status: active`, another `state:: running`."
- **Obsidian vs Logseq table:**
  - Obsidian uses YAML frontmatter with `Wiki/Tech/Strapi.md` paths.
  - Logseq uses `key:: value` with `Wiki___Tech___Strapi.md` paths.
  - Both use `[[Wiki/Tech/Strapi]]` links.
  - The author argues Logseq's block outliner suits LLM appends better, and Obsidian suits human editing.

**Others (README seen only in search snippets, [U]):** toolboxmd/karpathy-wiki and NinjaKristo/karpiki (Claude Code skills), win4r/llm-wiki-claude-skill (single SKILL.md with ingest/query/lint/compile), lucasastorian/llmwiki and atomicmemory/llm-wiki-compiler (both cited by Astro-Han), and a community "LLM Wiki v2".

### 2.2 Ars Contexta (agenticnotetaking/arscontexta): a "second brain for your agent" [6] [V]

- **What it is:**
  - A Claude Code plugin, v0.8.0, ~3.5k stars [V via `gh search`].
  - The repo was created **2026-02-15**, before Karpathy's post, so it is a parallel lineage rather than a derivative.
  - `/arscontexta:setup` runs a roughly 20-minute conversation that "derives" a whole system: folder structure, CLAUDE.md, hooks, skills, MOCs (Maps of Content) and templates. The derivation is backed by "249 research claims" covering Zettelkasten, Cornell notes, PARA, GTD and so on.
- **Contract:**
  - **Three spaces:** `self/` (the agent's identity, methodology and goals; slow growth), `notes/` (the knowledge graph; may be renamed per domain), and `ops/` (queue state, sessions).
  - Wiki links between notes.
  - MOCs at hub, domain and topic levels.
  - Templates carry `_schema` blocks.
- **Loops:** the "6 Rs" are Record (manual capture into `inbox/`), then `/reduce`, `/reflect`, `/reweave` (update older notes with new links), `/verify` and `/rethink`. `/ralph` runs a queue with **a fresh subagent context per phase**. `/arscontexta:reseed` "re-derive[s] from first principles when drift accumulates."
- **Hooks:**
  - Session Orient (SessionStart; injects the tree and surfaces maintenance signals).
  - Write Validate (PostToolUse; schema enforcement on every note write).
  - **Auto Commit** (async git commit).
  - Session Capture (on Stop, to `ops/sessions/`).
- **Search:** optional qmd via a vault `.mcp.json`; otherwise "ripgrep + MOC traversal."
- **Relevance:** it is the most "agent-owned" design here. The vault is the agent's memory as much as the human's, and the harness (hooks) enforces structure, not only the prompt.

### 2.3 basic-memory (basicmachines-co): an MCP-native knowledge graph in Markdown [7] [V]

- **File format:** "Each file is an `Entity`. Entities have `Observations` (facts about them) and `Relations` (links to other entities). That's the whole grammar."
  - **Frontmatter:** `title`, `type` (default `note`), `permalink` (a URI slug), `tags`.
  - **Observations:** list items such as `- [category] fact text #tag (optional context)`, e.g. `- [method] Pour over highlights subtle flavors`.
  - **Relations:** `- relation_type [[Target]]`, or a quoted multi-word type such as `- "pairs well with" [[Dark Chocolate]]`. A bare `[[Target]]` or a wikilink in prose indexes as `links_to`.
- **Storage:** "Just files plus a local SQLite index" (Postgres is optional). Hybrid FTS plus FastEmbed vector search, with optional cross-encoder rerank.
- **MCP tools:**
  - `write_note`, `read_note`, `edit_note`, `move_note`, `delete_note`, `search_notes`, `recent_activity`, `build_context` (which walks `memory://` URLs), plus project tools.
  - Every tool is annotated with MCP read-only and destructive hints.
  - Newer releases add `schema_infer`, `schema_validate` and `schema_diff`.
- **Obsidian:**
  - "No setup. Point Obsidian at `~/basic-memory` (or your project folder) and the same wikilinks, frontmatter, and Markdown your AI writes appear in your graph view. Edit either side — sync handles the rest." [V]
  - The docs page [8] says links must be `[[Note Title]]` *and the target must exist* to show in Obsidian's graph [V].
  - Cloud sync is manual `bm cloud push/pull` over rclone. It is additive, never deletes, and aborts and lists conflicts when both sides changed [V].
- **Known integration bugs** (titles from the GitHub issue search) [V]:
  - Obsidian callouts parsed as observation categories (#738).
  - Extended checkbox markers (`[/]`, `[>]`) creating junk categories (#1241).
  - NFC/NFD filename variants creating duplicate entities on macOS with Syncthing (#1275, open).
  - File-watcher writes not vector-embedded until reindex (#1016).
  - Forward references not resolved until reindex (#1015).
  - A PermissionError during a scan triggering mass index deletion (#1007).
- **OKF:** issue #1246 asked for OKF conformance. The maintainers declined an OKF *link-style switch*. Their reasoning: "canonical Basic Memory authoring remains wikilink-native." Instead they landed:
  - standard Markdown links to project files indexed as `links_to` relations (#1514);
  - OKF-style `sources` frontmatter with footnote citations (#1490);
  - "deterministic generated `index.md` and `log.md` files for the live Wiki view" (#1381/#1396).
  - A `bm okf export/check` is tracked in #1550. [V]

### 2.4 qmd (tobi/qmd): local Markdown search [9] [V]

- **What it is:** "An on-device search engine for everything you need to remember."
- **Pipeline:**
  - Query expansion uses a fine-tuned 1.7B model and produces typed `lex`, `vec` and `hyde` sub-queries.
  - `lex` goes to BM25/FTS; `vec` and `hyde` go to vector search over `embeddinggemma-300M`.
  - Results are fused with Reciprocal Rank Fusion, then reranked by `qwen3-reranker-0.6b`.
  - It runs on GGUF models through node-llama-cpp, cached in `~/.cache/qmd/models/` (~2 GB total).
- **Concepts:**
  - **Collections**: named folders plus a glob mask.
  - **Context**: a tree of path descriptions returned with hits, which the README calls "the key feature … allows LLMs to make much better contextual choices."
  - Docids such as `#abc123` and `qmd://collection/path` URIs.
- **Interfaces:**
  - CLI: `qmd search|vsearch|query|get|multi-get`, with `--json` and `--files` output for agents.
  - MCP tools: `query`, `get`, `multi_get`, `status`, `metadata`.
  - Transports: stdio, or `qmd mcp --http --daemon` on :8181 to keep the models warm.
  - A Claude Code plugin is available (`claude plugin marketplace add tobi/qmd`).
- **Indexing is explicit, not watched.** You run `qmd update` (with an optional per-collection pre-command such as `git pull --rebase`) and `qmd embed`, using 900-token chunks with 15% overlap. Editing `index.yml` "does not re-index on its own." Metadata filtering over frontmatter keys exists.
- **Endorsements:** the gist [V] and Ars Contexta [V] both name qmd.

### 2.5 Obsidian-side agent access

- **Obsidian official CLI + kepano/obsidian-skills** [10] [V for the skills repo]
  - kepano (Obsidian's CEO) publishes an Agent Skills pack (~49k stars, created 2026-01-02): `obsidian-cli`, `obsidian-markdown` (with PROPERTIES, CALLOUTS and EMBEDS references), `obsidian-bases`, `json-canvas` and `defuddle`.
  - The CLI "interact[s] with a running Obsidian instance. Requires Obsidian to be open." Examples: `obsidian read file="My Note"` (where `file=` "resolves like a wikilink"), `search`, `property:set`, `backlinks`, `tags`, `daily:append`.
  - The CLI arrived in Obsidian 1.12 [U; from search summaries].
- **coddingtonbear/obsidian-local-rest-api** (~3.0k stars) [11] [V]
  - A plugin with a REST API on `https://127.0.0.1:27124` and a **built-in MCP server**.
  - "Surgically patch specific sections — target a heading, block reference, or frontmatter key."
  - JsonLogic queries over frontmatter, tags, path and content.
  - An SSE event stream for note created, frontmatter changed and file opened.
- **MarkusPfundstein/mcp-obsidian** (~4.5k stars) [12] [V]
  - A Python MCP server that sits on top of the REST plugin.
  - Tools: `list_files_in_vault`, `get_file_contents`, `search`, `patch_content` (relative to a heading, block or frontmatter field), `append_content`, `delete_file`.
- **cyanheads/obsidian-mcp-server** (~690 stars) [V for stars only]. Filesystem-direct servers (MCPVault, obsidian-mcp) work without Obsidian running [U].
- **Smart Connections** (brianpetro, ~5.5k stars) [13] [V]
  - Local embeddings ("ships with a local embedding model … no API key required") that surface related notes and blocks.
  - Its index lives in `.smart-env/`.
  - The README warns: "If you use a third party sync tool, add the `.smart-env/` directory to its ignore patterns to avoid conflicts."
- **Copilot for Obsidian** (logancyang, ~7.8k stars) [14] [V]
  - Now "Agents for your Obsidian vault." It hosts opencode, Claude Code or Codex (through an ACP adapter) inside Obsidian, using "their own CLI login."
  - It ships skills for Obsidian Markdown, Bases, Canvas and the Obsidian CLI.
  - Agent mode is desktop-only. A local "Miyo" index stays on the device.
- **Khoj** (~37.6k stars) [15] [V, README only]
  - A self-hostable "AI second brain": chat over docs, including markdown and org-mode, with Obsidian, Emacs, web and phone clients.
  - It is a retrieval (RAG) system, not an LLM-maintained wiki.

### 2.6 Google's Open Knowledge Format (OKF): the pattern as a spec [16][17] [V]

- **Provenance.**
  - OKF v0.1 was imported into `GoogleCloudPlatform/knowledge-catalog/okf/` on **2026-06-12** (commit "Import Open Knowledge Format reference enrichment agent (#28)").
  - v0.2 arrived on **2026-07-24** (#227).
  - The spec has since moved to **`GoogleCloudPlatform/open-knowledge-format`** (repo created 2026-08-11, ~860 stars). The `okf/` copy says "Stop using the copy … It is a frozen snapshot." [V]
  - The current spec is **v0.2**. The coordinator's description of "v0.1" matches the history: v0.1 was the June release.
  - The spec text itself does not mention Karpathy or "LLM wiki". It frames itself as a format for knowledge "continuously written and maintained by agents." The link to the LLM-wiki pattern is an inference from the structure, which is the same; it is not stated. [V]
- **Required fields.**
  - "`type` is the only always-required key; a concept carrying just `type` is fully conformant."
  - Recommended: `title`, `description`, `resource`, `tags`.
  - "Producers MAY include any additional keys. Consumers SHOULD preserve unknown keys when round-tripping and MUST NOT reject documents with unrecognized fields." [V]
- **Reserved filenames.** `index.md` and `log.md` "have defined meaning at any level of the hierarchy and MUST NOT be used for concept documents." [V]
  - **index.md** (§8) is "Directory listing … progressive disclosure."
    - It has no frontmatter, except an optional `okf_version` at the bundle root.
    - The body is `# Section` headings with `* [Title](relative-url) - description` entries.
    - "Producers MAY generate `index.md` automatically; consumers MAY synthesize one on the fly." [V]
  - **log.md** (§9) is "a flat list of date-grouped entries, **newest first**."
    - Headings are `## YYYY-MM-DD` (ISO, MUST).
    - Bullets lead with a bold word such as `**Update**:` or `**Creation**:`, which is a convention, not a requirement. [V]
    - **This conflicts with Karpathy's log.** His is append-only (newest last) with `## [date] op | title` headings.
- **Links (§6.1).**
  - "standard markdown links." The bundle-absolute form `/tables/customers.md` is "recommended because it is stable when documents are moved"; the relative form is also allowed.
  - "The specific kind (parent/child, references, joins-with, depends-on) is conveyed by the surrounding prose, not by the link itself" (untyped edges).
  - "Consumers MUST tolerate broken links … it may simply represent not-yet-written knowledge." **Wikilinks are not part of OKF.** [V]
- **v0.2 trust and lifecycle families (§5), all optional:**
  - `sources` (id, resource, title, author, usage_count, last_modified), cited in the body by Markdown footnotes.
  - `generated: {by, at}`.
  - `verified: [{by, at}]`, which yields trust tiers: unverified, then machine-confirmed, then human-reviewed (the last needs a `human:<id>` actor).
  - `status: draft|stable|deprecated` (absent means stable).
  - `stale_after` (an absolute ISO datetime).
  - Actor strings: `agent/version`, `human:<id>`, `process:<id>`. Every timestamp carries an explicit UTC offset. [V]
- **Conformance (§11).** Every non-reserved `.md` has parseable frontmatter with a non-empty `type`, and reserved files follow §8 and §9. Consumers "MUST NOT reject a bundle because of" missing optional fields, unknown types or keys, broken links, or missing `index.md`. [V]
- **Reception.**
  - basic-memory adopted it on the consumer side.
  - Astro-Han is tracking it.
  - A basic-memory commenter warned that the OKF reference viewer silently skips unparseable files (`except OKFDocumentError: continue`) and never calls `validate()`. [V, as a quote from the issue thread; I did not check the code itself.]

---

## 3. Failure modes and critiques

Sources here are the 1,136 gist comments [V, pulled through the API], implementation READMEs [V], and blog critiques [U].

1. **Drift and compounding error ("model collapse" of the wiki).**
   - The LLM reads its own earlier summaries, so errors get built on. Blog critiques say the "source chain quietly frays" and the wiki becomes "self-referential" [U: Medium "Hidden Flaw"; denser.ai; innobu].
   - Gist commenter Jwcjwc12: "the moment those files change, the compiled knowledge might be wrong — and doesn't know it. Health checks help, but that's just the LLM re-reading and guessing." They proposed per-claim source content hashes [V].
   - pollockchris083-arch: "Lint checks notes against notes … It just isn't enough when the notes describe a system that changes without you." Their fix was claims pinned to file and line, flagged when the code changes [V].
   - Mitigations seen: Astro-Han's verbatim Grounding Invariant [V], kfchou's per-footnote audit with a cross-provider adversary [V], and Ars Contexta's `/reseed` [V].
2. **Citation fidelity.** Marekai: "the quality rule 'no hallucinated citations' is an aspiration, not a technical guarantee." The LLM "paraphrases by default" and loses page numbers [V].
3. **Schema invention and inconsistency.**
   - MehmetGoekce's `status: active` vs `state:: running` example [V].
   - asakin cites an ETH Zurich result that LLM-generated context files hurt agent performance in 5 of 8 settings [V that the comment says this; U for the study]. Their fix is a human-review "training period".
   - aadjadj-bit: "The CLAUDE.md schema is the highest-leverage artifact … Most people skip it" [V].
4. **Index bloat and scale ceiling.**
   - Karpathy himself scopes the index-only approach to "~100 sources, ~hundreds of pages" [V].
   - Others put the ceiling anywhere from ~150–200 pages (50–100k tokens) to ~1,000 files [U]. Astro-Han puts it at 50–100k tokens for grep [V].
   - Responses: a generated index (kfchou), hub-index routing plus LRU prune to an Archive (MehmetGoekce), and qmd once grep stops being enough.
   - tashisleepy: "at under 50 docs, the wiki alone is enough. The [vector] layer earns its keep at 500+ docs" [V].
5. **Cost.**
   - frosk1: "You shift cost from query time to ingestion time … this can become expensive" [V].
   - One ingest touches 10–15 pages [V, gist]. Ars Contexta setup is "~20 minutes -- token-intensive" [V].
6. **Merge and sync conflicts.**
   - aadjadj-bit: "sync conflicts (iCloud, Obsidian Sync) become a real concern at scale. Worth defining in the schema which files are LLM-owned vs. human-owned" [V].
   - Shared-state hotspots are `index.md` and `log.md`. Every ingest rewrites both, so concurrent agents or devices collide.
   - Astro-Han serializes compilation for exactly this reason [V]. kfchou removes both files from version control: the index is generated and gitignored, and the log is git trailers [V].
   - Derived indexes inside the vault also conflict. Smart Connections tells users to exclude `.smart-env/` from third-party sync [V]. basic-memory has an NFC/NFD duplicate bug under Syncthing [V].
7. **Link rot and broken links.**
   - Every implementation lints for broken links, orphans and missing pages, following Karpathy's lint list [V].
   - In kfchou, broken `[[links]]` block commits [V].
   - OKF instead says broken links are legal ("not-yet-written knowledge") [V]. Obsidian treats unresolved wikilinks the same way, as placeholders.
   - basic-memory had forward references that only resolved on reindex [V].
8. **The human never reads it, and the "slop" objection.**
   - The pattern's premise is "You read it; the LLM writes it" [V], but nothing enforces the reading.
   - Gist reactions include "the slop machine in full perpetual motion … dragging down the Obsidian ecosystem" (Runecreed) [V].
   - Blog critics call "wiki" a category error when no humans collaborate [U].
   - Counter-designs force a human touchpoint: Karpathy ingests "one at a time and stay[s] involved" [V]; kfchou asks what to emphasise before writing and shows diffs before updates [V]; OKF's `verified: human:<id>` tier makes human review a recorded fact [V].
9. **Credentials and secrets in a git-synced wiki.** MehmetGoekce lints for credential patterns and keeps secrets in non-git L1 memory [V].
10. **Self-referential critique from implementers.** Astro-Han's "Design Boundaries" says access-based decay is wrong ("frequently asked is not the same as true") and that numeric confidence scores are "false precision" [V].

---

## 4. Obsidian compatibility details

**Links.**
- Obsidian defaults to **wikilinks** "due to its more compact format". "If interoperability is important to you, you can disable Wikilinks and use Markdown links instead" (Settings → Files and links → *Use [[Wikilinks]]*). Markdown-link targets must be URL-encoded (`Three%20laws%20of%20motion`) [V, help/links]. Obsidian can update links on rename [V].
- Ecosystem split:
  - **Wikilinks:** kfchou, MehmetGoekce, basic-memory (canonical), Ars Contexta.
  - **Standard markdown links:** Astro-Han and OKF (bundle-absolute `/path.md` recommended).
  - basic-memory now indexes both [V].
- Obsidian does resolve bundle-absolute `/path.md` links in practice [U; not checked against the docs].

**Properties (frontmatter)** [V, help/properties and kepano PROPERTIES.md]:
- **Types:** Text, List, Number, Checkbox, Date, Date & time, Tags.
- **Types are vault-wide per key.** "all properties with that name across your vault will use the same type." An agent that writes `status: 3` in one note and `status: draft` in another breaks the property UI.
- **No nested properties.** Nested YAML is unsupported in the Properties UI and shows only in source mode. This matters for OKF's `generated: {by, at}`, `verified: [{by, at}]` and `sources: [{…}]`, which will not render or edit as properties in Obsidian; they stay intact as YAML. [Inference from both sources.]
- **Links in properties must be quoted wikilinks:** `related: "[[Other Note]]"`, list items `- "[[Link]]"`. Markdown is not rendered in text properties.
- **Default keys:** `tags`, `aliases`, `cssclasses` (lists). The singular `tag`, `alias` and `cssclass` were deprecated in 1.4, and default-property support ends in 1.9. Obsidian Publish reserves `publish`, `permalink`, `description`, `image` and `cover`. basic-memory's `permalink` key collides by name with Publish's.
- **Tag syntax:** letters, numbers (not first), `_`, `-`, `/` for nesting; no spaces.

**Frontmatter keys used by each project:**

| Project | Keys |
|---|---|
| basic-memory | `title`, `type`, `permalink`, `tags` |
| OKF | `type` (required), `title`, `description`, `resource`, `tags`, `sources`, `generated`, `verified`, `status`, `stale_after` |
| kfchou | `category`, `summary` (these feed the generated index) |
| MehmetGoekce | `type`, `domain`, `confidence`, `created`, `updated` (Logseq `::` form, or YAML in Obsidian) |
| Karpathy | "tags, dates, source counts" for Dataview [V] |

**Other compatibility notes:**
- Obsidian-specific syntax (callouts `> [!note]`, extended task markers, block refs `^id`, embeds `![[…]]`) trips non-Obsidian parsers; see basic-memory #738 and #1241 [V].
- Obsidian's own Bases (`.base`) and JSON Canvas (`.canvas`) are the native "views" that kepano's skills teach agents to write [V].
- Derived index folders (`.smart-env/`, qmd's `~/.cache`, basic-memory's SQLite) live outside the notes or should be sync-ignored [V].
- **Combined format implied by the sources.** No single source states this; it is a synthesis. A file that satisfies Obsidian, OKF and basic-memory at once would have:
  - flat YAML with a non-empty `type`;
  - `title`, `description` and `tags` as lists;
  - standard Markdown links in the body (wikilinks are not OKF);
  - `index.md` and `log.md` in OKF's shapes.
- **Open tension:** OKF's log is newest-first, while Karpathy's is append-only with grep-able `## [date] op | title` headings.

---

## Sources

1. Karpathy, "LLM Knowledge Bases", X post, 2026-04-02. https://x.com/karpathy/status/2039805659525644595 (text fetched through https://api.fxtwitter.com/karpathy/status/2039805659525644595) [V]
2. Karpathy, "LLM Wiki" gist. https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f (raw text [V]; comments API, 1,136 comments [V]; gist metadata returned 502)
3. Astro-Han/karpathy-llm-wiki: https://github.com/Astro-Han/karpathy-llm-wiki (README and SKILL.md) [V]
4. kfchou/wiki-skills: https://github.com/kfchou/wiki-skills [V]
5. MehmetGoekce/llm-wiki: https://github.com/MehmetGoekce/llm-wiki [V]
6. agenticnotetaking/arscontexta: https://github.com/agenticnotetaking/arscontexta [V]
7. basicmachines-co/basic-memory: https://github.com/basicmachines-co/basic-memory (README [V]); issues #738, #1007, #1015, #1016, #1241, #1246, #1275 at https://github.com/basicmachines-co/basic-memory/issues [V by title; #1246 read in full]
8. Basic Memory Obsidian integration docs: https://docs.basicmemory.com/integrations/obsidian [V]
9. tobi/qmd: https://github.com/tobi/qmd [V]
10. kepano/obsidian-skills: https://github.com/kepano/obsidian-skills (skills/obsidian-cli/SKILL.md, skills/obsidian-markdown/references/PROPERTIES.md) [V]; Obsidian CLI docs https://help.obsidian.md/cli [U, not fetched]
11. coddingtonbear/obsidian-local-rest-api: https://github.com/coddingtonbear/obsidian-local-rest-api [V]
12. MarkusPfundstein/mcp-obsidian: https://github.com/MarkusPfundstein/mcp-obsidian [V]
13. brianpetro/obsidian-smart-connections: https://github.com/brianpetro/obsidian-smart-connections [V]
14. logancyang/obsidian-copilot: https://github.com/logancyang/obsidian-copilot [V]
15. khoj-ai/khoj: https://github.com/khoj-ai/khoj [V]
16. OKF v0.2 spec (frozen copy and commit history): https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf (SPEC.md, README.md) [V]
17. OKF canonical repo: https://github.com/GoogleCloudPlatform/open-knowledge-format (SPEC.md v0.2) [V]
18. Obsidian Help, Properties: https://obsidian.md/help/properties [V]; Links: https://obsidian.md/help/links [V]
19. Critiques, secondhand: https://foundanand.medium.com/the-hidden-flaw-in-karpathys-llm-wiki-e3a86a94b459 [U]; https://denser.ai/blog/llm-wiki-karpathy-knowledge-base/ [U]; https://www.innobu.com/en/articles/karpathy-llm-wiki-second-brain-enterprise-reality.html [U]; https://neo4j.com/blog/agentic-ai/scaling-karpathy-llm-wiki-graph/ [U]
20. Gist comments cited (all from the comments API [V]): Jwcjwc12 (#6082231), tashisleepy (#6081913), Marekai (#6085465), frosk1 (#6084952), Runecreed (#6085049), asakin (#6093103), aadjadj-bit (#6142662), pollockchris083-arch (#6312158)
21. Other implementations seen only in search results [U]: https://github.com/toolboxmd/karpathy-wiki, https://github.com/win4r/llm-wiki-claude-skill, https://github.com/NinjaKristo/karpiki, https://github.com/lucasastorian/llmwiki, https://github.com/atomicmemory/llm-wiki-compiler, https://github.com/cyanheads/obsidian-mcp-server
