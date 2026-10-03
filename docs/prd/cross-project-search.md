# PRD — Cross-Project Search

> **Status:** Draft v0.1, 2026-10-03. Standalone requirements document, written to be lifted into the broader Duo v2 product plan.
> **Owner decisions:** eighteen answers locked through AskUserQuestion on 2026-10-03 (§ 4, L1–L18). Items the owner wasn't asked about are listed as open questions (§ 10). This document does not choose them.
> **Evidence base:** two proofs of concept by the owner, both shown to work on a company-managed Mac: [`dudgeon/smol-sim-search`](https://github.com/dudgeon/smol-sim-search) (offline local embeddings for Claude Code) and [`dudgeon/mini-meeting-minutes`](https://github.com/dudgeon/mini-meeting-minutes) (vendored on-device Core ML models delivered through a git clone). The scope and the vocabulary of projects, sessions, the registry, and the Unfiled inbox come from [`legacy-session-consolidation.md`](legacy-session-consolidation.md) (the "consolidation PRD").
> **Place in the v2 plan (added 2026-10-03):** `docs/plan/build-plan.md` Phase M. **v1.1** ships P1 (files across all projects, hybrid retrieval, the read-only search CLI, coverage, a basic UI); **v1.2** ships P2–P3. P0's gates are spikes S13–S15, run before Phase M. Duo's build is Xcode-free and delivered by `git clone` plus a local build (DL-30), which is the pattern L9 asks search to follow; whether Duo runs on the work Mac (Q1) is tested after the first usable build (DL-31). The read-only search CLI is the read-only half of Duo's CLI (DL-15, DL-16). Vocabulary: sessions not in a project are called **Unfiled**, matching the consolidation PRD and the approved designs (this draft said "Unsorted").
> **Altitude:** this PRD says *what* search must do and the constraints it must respect. It deliberately does not specify Duo v2's form factor, delivery mechanism, UI layout, storage engine, or command syntax. Those follow from decisions made elsewhere in the Duo v2 plan.

---

## 1. Problem

The consolidation PRD organizes a person's work into projects: one root folder each, with sessions attached. Once there are a dozen projects, the questions people actually ask cut across them:

- "Where did we decide how retries should work? I think it was in the billing project, or maybe a session in March."
- "Which of my projects has the stakeholder notes about pricing?"
- "I solved this error before. Which session was it, so I can resume it?"

Today none of these questions has a good answer:

- **Text search is literal and project-bound.** Duo v1's vault search matches exact strings in one vault. Claude's grep and glob are literal, cost many tokens, and stay inside the current directory. Neither finds a paraphrase ("charged twice" vs "duplicate billing").
- **Sessions aren't searchable at all.** Months of reasoning sit in transcripts under `~/.claude/projects`, and the only way to find something is to remember the session's title.
- **The POC works, but only one folder at a time.** smol-sim-search proves that local, offline semantic search runs inside a corporate sandbox. Its index lives in `./.sem` in one directory and it can't see sessions. It is a skill for Claude, not something the person can use directly.

Duo v2 needs one search, used by both the person and Claude, that covers everything Duo knows about: every project's files, every session (assigned to a project or not), and the memory Claude keeps. It has to find things by meaning as well as by exact text, run entirely on the device, and stay current without anyone remembering to rebuild an index.

---

## 2. Goals and non-goals

### Goals

1. **One query, everything Duo knows.** Search covers all four sources (§ 7.1) across every project in the registry, plus Unfiled sessions, in one ranked result set.
2. **Meaning and exact text.** Paraphrases match, and so do exact identifiers, names, and error strings (L4).
3. **Equal for people and Claude.** The person gets a search UI. Claude gets a CLI that returns the same results as structured data. Neither is a second-class port of the other (L3).
4. **Always current, never in the way.** Indexing happens in the background, is throttled, and is honest about what isn't covered yet (L8).
5. **Nothing leaves the Mac.** No network access at query time or while indexing. No content telemetry.
6. **Results lead to action.** From any result you can open it, resume it, send it to Claude, or find similar content (L11).
7. **One search, not three.** This replaces Duo's literal vault search, the curation view's title filter, and in-app use of the smol-sim-search skill (L13).

### Non-goals (this PRD)

- Similarity *analysis* (duplicates, clusters, themes, outliers, pairwise compare) in the UI or in the CLI. Planned as a follow-on (L12).
- Search over content outside Duo's projects and sessions: web pages, Google Docs, email, the home folder at large.
- Languages other than English, ranked well (L16). Non-English text is still indexed, and exact-text matching still works on it.
- Searching across machines or syncing indexes between them.
- Cloud sessions (`claude.ai/code`), as in the consolidation PRD.
- Automatic grouping proposals of any kind (L14 keeps the consolidation PRD's L3 apart from a user-initiated exception).

---

## 3. Users and scenarios

The persona is the consolidation PRD's: a heavy Claude Code user, increasingly a PM or other non-engineer (Duo's primary audience), with months of sessions and a dozen projects on one Mac. The second "user" is Claude, working in a session inside Duo.

| Tag | Scenario | What "good" looks like |
|---|---|---|
| S-RECALL | "Where did we land on retry policy?" The answer is a paragraph in one project's `docs/decisions.md` and a back-and-forth in a session in a different project. | Both appear near the top of one result list, each labelled with its project and source type. The person opens the doc at the matched lines, or resumes the session. |
| S-PARAPHRASE | The person searches "customers charged twice". The notes say "duplicate billing". | The notes are found. |
| S-EXACT | The person pastes `ERR_SESSION_7F3` or a function name. | Every exact occurrence ranks at the top, across projects. |
| S-AGENT | Claude, sandboxed, is asked to "use what we learned in the onboarding project". | Claude runs the search CLI, gets ranked paths and line ranges as structured data, reads only those, and answers without grepping other folders or loading them into context. |
| S-UNSORTED | A useful session lives in the `$HOME` junk drawer and was never assigned. | It shows up in results labelled Unfiled. From the result, the person can resume it or, in the curation view, assign it (L14). |
| S-SIMILAR | The person finds one relevant session and asks for "more like this". | Related files and sessions from every project, ranked. |
| S-COLD | First launch after the feature ships, with months of backlog. | Search works immediately on whatever is indexed so far, most recent content first, and says plainly what isn't covered yet. The Mac stays usable. |
| S-SECRET | A transcript contains an API key that was pasted into a prompt. | The key never appears in a stored snippet or in a result, and a search for it doesn't surface it as readable text. |
| S-ARCHIVED | A session was archived last month. | It is findable when the person turns on an "include archived" filter, and hidden otherwise. |
| S-NOAPP | Claude runs the CLI while the Duo app isn't running. | Results still come back from the existing index, with a note saying how fresh it is. |

---

## 4. Decisions

### Locked by owner (2026-10-03)

| # | Decision | Outcome |
|---|---|---|
| L1 | What is searched | **Project files, session transcripts, Unfiled (junk-drawer) sessions, and Claude's memory plus `CLAUDE.md` files.** All four in the first complete release. |
| L2 | What "scoped projects" means | **Every project in Duo's registry**, plus Unfiled sessions. Search spans all of them by default, and the user narrows from there. |
| L3 | Who searches | **People and Claude, equally.** A human UI and an agent CLI are both required. |
| L4 | Retrieval | **Hybrid:** semantic (embeddings) and lexical (exact or keyword) combined into one ranking. |
| L5 | Index location | **Central and Duo-owned**, outside project folders. The index is a cache and lives with Duo's machine-local state; project folders carry only the project files the consolidation PRD and `docs/design/decisions.md` (DL-1, DL-13) define. |
| L6 | Inference engine | **On-device Core ML** (the mini-meeting-minutes pattern), not the POC's ONNX Runtime on CPU. |
| L7 | What gets indexed from transcripts | **Whatever is simplest.** Interpreted as conversation text only: user prompts, assistant prose, and session titles and summaries. No tool calls, tool output, or thinking. |
| L8 | When indexing happens | **In the background, throttled**, with an initial backfill. Search works on a partial index and reports what's missing. |
| L9 | How the model and runtime reach the Mac | **Follows Duo v2's delivery approach**, whatever that turns out to be. This PRD only sets constraints (§ 7.9). |
| L10 | How Claude reaches search | **A read-only CLI that opens the index directly.** It doesn't depend on the Duo app running or on a connection to it. |
| L11 | Actions on a result | **Open, resume, send to Claude, and find similar.** All four in scope. |
| L12 | Similarity analysis (duplicates, clusters, outliers, compare) | **Out of scope.** Follow-on PRD. |
| L13 | Existing search surfaces | **Absorbed into this search.** It replaces v1's literal vault search and the curation view's title filter, and supersedes the smol-sim-search skill inside Duo. |
| L14 | Relationship to consolidation PRD L3 ("no automatic proposals") | **User-initiated use is allowed.** Duo never proposes groupings, but the person may search or "find similar" inside the curation view and assign the results by hand. This amends consolidation L3 and should be added to that PRD as L3b. |
| L15 | Secrets | **Exclude and redact.** Respect `.gitignore` and a default deny-list of secret-bearing files. Redact recognizable secrets before anything is stored. Only the user can read the index. |
| L16 | Language | **English.** Keep the POC's model (`bge-small-en-v1.5`). |
| L17 | Lifecycle | **Archived content stays searchable** behind a filter that is off by default. **Deleted content is removed** from the index promptly, including deletions by Claude Code's retention sweep. |
| L18 | How results are presented | **One ranked list with facets** (project, source type, date). Results from the current project get a modest boost. |

### Owner context recorded during the interview

- Nobody has yet confirmed whether Duo itself (the app or its CLI) runs on the owner's work Mac. Both POCs do. This is the top risk (§ 13).
- The mini-meeting-minutes delivery pattern worked on the work Mac: models are committed to git with checksums and arrive through a `git clone` from GitHub, followed by a local build. Nothing is downloaded from model hubs, and nothing is downloaded at runtime.

---

## 5. What the POCs prove, and what they don't

| Claim | smol-sim-search | mini-meeting-minutes | Status for this PRD |
|---|---|---|---|
| Local embeddings give useful semantic search over notes, docs, code, and records | ✅ golden top-1 queries, measured scores | — | Proven (on ONNX/CPU) |
| Installing works on the company Mac with no model-hub downloads | ✅ (vendored, nothing downloaded) | ✅ (vendored, one git clone) | Proven for both patterns, but not for Duo itself |
| Core ML inference runs on the company Mac | — | ✅ (speech models) | Proven for MMM's models; **not proven for an embedding model** |
| Embedding runs inside Claude Code's sandbox (writes only to allowed places, no network) | ✅ (ONNX/CPU, write-isolation checks) | — | **Not proven for Core ML.** Core ML may write compiled-model or accelerator caches outside allowed paths. Must be verified (§ 11, P0). |
| Incremental re-indexing is cheap | ✅ (size and mtime, then content hash) | — | Proven; reuse the approach |
| Indexing throughput is good enough for a backlog of months | ❌ (~34 dense chunks/s on CPU) | — | **Not proven.** Core ML (L6) is expected to be much faster. P0 measures it. |
| Search works across projects and covers transcripts | ❌ (one directory, files only) | — | New in this PRD |
| Hybrid ranking | ❌ (semantic only) | — | New in this PRD |

---

## 6. Concepts

- **Source:** one of four kinds of searchable content: *file* (under a project root), *session* (a transcript), *memory* (Claude's per-project auto memory), and *instructions* (`CLAUDE.md` files). Memory and instructions may share one facet in the UI.
- **Item:** something a result points to: a file, a session, or a memory file.
- **Chunk:** the unit that is embedded and matched. A passage of a file, or one turn of a session. Each chunk has a **locator** that lets an action jump straight to it (line range, page, record, or turn).
- **Attribution:** which project an item belongs to. Files belong to the project whose root contains them. Sessions and memory are attributed **at query time** from the registry and inventory defined in the consolidation PRD. Re-homing a session never requires re-indexing it.
- **Coverage:** the fraction of in-scope items that are indexed and up to date. Coverage is always reportable.

---

## 7. Functional requirements

Numbering is stable. "Must" is required for the first shippable increment, "should" before the feature is called complete, and "may" marks a documented option.

### 7.1 Scope and sources

- **FR-7.1.1** Search must cover every project in the registry (L2). Projects added, removed, or re-rooted in the registry must enter, leave, or move within search scope without a manual step.
- **FR-7.1.2** **Files:** the POC's formats at a minimum: Markdown, plain text, source code, CSV/TSV and JSON/JSONL (one record per item), and PDF. Binary files, `.git`, dependency and virtualenv folders, and very large files are skipped, and `.gitignore` rules apply, as in the POC.
- **FR-7.1.3** **Sessions:** every transcript the consolidation inventory knows about, whether attributed to a project, Unfiled, or archived (L1, L17). Sidechain and subagent transcripts are not indexed separately.
- **FR-7.1.4** **Memory and instructions:** each bucket's auto memory, attributed to a project through the bucket's resolved root, and the `CLAUDE.md` files within project roots.
- **FR-7.1.5** Unfiled sessions must be searchable and labelled as Unfiled in results (S-UNSORTED).
- **FR-7.1.6** A project whose root is missing (*detached* in the consolidation PRD) keeps its indexed content, shown with that status, until the project is removed.
- **FR-7.1.7** Users must be able to exclude paths (per project and globally) from indexing.

### 7.2 What gets extracted

- **FR-7.2.1** From transcripts, index **conversation text only** (L7): the text of user prompts, the prose of assistant replies, session titles (custom and AI-generated), and summaries. Tool calls, tool results, file snapshots, and thinking are excluded.
- **FR-7.2.2** Transcript parsing must tolerate the format changing between Claude Code versions: unknown record types are skipped, partial lines are tolerated, and parsing never fails on content it doesn't recognize. The consolidation PRD's warning that the format is internal applies.
- **FR-7.2.3** Session chunks follow conversational turns, so a result can open or resume at the matched turn.
- **FR-7.2.4** Live sessions (still being written) must be indexable incrementally as they grow. The indexer must detect when a transcript was rewritten rather than appended to, and re-index it in that case.
- **FR-7.2.5** Every chunk carries enough location information for the actions in § 7.6 to land at the right place.

### 7.3 Indexing lifecycle

- **FR-7.3.1** Indexing runs in the background and needs no user action (L8). There is no "build index" step to remember.
- **FR-7.3.2** **Backfill order** favors what is most likely to be searched: recently active projects and recent sessions first.
- **FR-7.3.3** **Throttling:** indexing must not noticeably degrade foreground work. It must back off under load and should pause or slow down on battery power. The exact policy is a P0 output.
- **FR-7.3.4** **Freshness:** changes to project files, transcripts, and memory are picked up automatically. Re-indexing is incremental: only changed content is re-embedded, as in the POC.
- **FR-7.3.5** **Identical content is embedded once.** Moving or renaming a file, relocating a session, or moving a folder (consolidation PRD § 7.4–7.5) must not trigger re-embedding of unchanged content.
- **FR-7.3.6** **Coverage is visible.** While coverage is below 100%, both the UI and the CLI must say so, with enough detail to judge it (for example, "sessions before June not yet indexed").
- **FR-7.3.7** **Deletion is prompt** (L17). When an item is deleted, whether by the user, by Duo's delete action, or by Claude Code's retention sweep, its entries must disappear from results within the normal freshness window. Archived items stay, marked as archived.
- **FR-7.3.8** The **model is part of the index's identity**, as in the POC. An index built with a different model, model revision, or numerical configuration is never queried with another. Changing the model triggers a rebuild in the background, not a broken search.
- **FR-7.3.9** The index is a cache. Deleting it is always safe, and it rebuilds itself.

### 7.4 Retrieval and ranking

- **FR-7.4.1** **Hybrid** (L4): every query runs both semantic and lexical retrieval, and the results are merged into one ranking.
- **FR-7.4.2** An exact identifier, quoted phrase, or literal string must rank its exact matches at the top (S-EXACT). An explicit exact-only mode must exist to cover the literal search being replaced (L13).
- **FR-7.4.3** Results from the current project (when there is one) get a modest boost. They must not crowd out strong matches from other projects (L18).
- **FR-7.4.4** Results are grouped by item by default (one entry per file or session, with its best-matching passage), with a way to expand to every matching passage.
- **FR-7.4.5** Identical content in several places (a file copied into two projects) is shown once, noting where else it appears.
- **FR-7.4.6** Filters: project (including Unfiled), source type, date range, and include-archived (default off). Filters work the same in the UI and the CLI.
- **FR-7.4.7** Similarity scores are relative (see the POC's notes on interpreting scores). Ranking must not depend on a fixed absolute relevance cutoff. The UI must not present a raw score as a percentage of relevance.

### 7.5 Human search experience

- **FR-7.5.1** Search is reachable from anywhere in Duo and defaults to all projects (L2), with a quick way to narrow it to the current project.
- **FR-7.5.2** Results are one ranked list (L18). Each result shows its project, source type, date, title (a file name or session title), and a snippet of the matching passage.
- **FR-7.5.3** Facets for project, source type, and date are available on the result list.
- **FR-7.5.4** Coverage status (FR-7.3.6) is visible near the results whenever coverage is incomplete.
- **FR-7.5.5** Search must be fully usable from the keyboard.
- **FR-7.5.6** Inside the curation view (consolidation PRD § 7.3), search and "find similar" are available on the person's initiative, and results can be multi-selected and assigned (L14). Duo never runs a similarity search there unprompted or pre-selects anything from one.

### 7.6 Result actions (L11)

- **FR-7.6.1** **Open:** files open in Duo at the matched location. Sessions open read-only at the matched turn, using the consolidation PRD's read-only transcript action.
- **FR-7.6.2** **Resume:** a session result can be resumed under the consolidation PRD's resume rules (§ 7.7 there), including its handling of older CLI versions and missing folders.
- **FR-7.6.3** **Send to Claude:** one or more selected results can be handed to the active Claude session as references (paths with line ranges, or session and turn references), not pasted wholesale.
- **FR-7.6.4** **Find similar:** starting from a result, a file, or a session, find related content across all projects, with the same filters and presentation as a query (S-SIMILAR).

### 7.7 Agent surface (L3, L10)

- **FR-7.7.1** A CLI exposes query, find-similar, and coverage/status, with the same scope, filters, and ranking as the UI. It returns structured output: one machine-readable document per call, with diagnostics kept separate.
- **FR-7.7.2** The CLI is **read-only**. It opens the index directly and never writes anything: not to the index, project folders, caches, or temp locations outside what Claude Code's sandbox permits. It must work while the Duo app isn't running (S-NOAPP).
- **FR-7.7.3** It must run inside Claude Code's sandbox without exclusions, without `dangerouslyDisableSandbox`, and without changes to settings, matching the POC's compliance bar.
- **FR-7.7.4** When the index is stale or incomplete, the CLI says so in its output rather than failing.
- **FR-7.7.5** Results carry paths and locators precise enough for Claude to read only the matched ranges (the POC's context-discipline rule).
- **FR-7.7.6** Duo's Claude-facing guidance (skill or equivalent) teaches Claude to prefer this search over grep or recursive reads for cross-project and meaning-based questions, and carries over the POC's guidance on reading scores and limiting context. Inside Duo it supersedes smol-sim-search (L13).

### 7.8 Privacy and secrets (L15)

- **FR-7.8.1** Respect `.gitignore`, and apply a default deny-list of secret-bearing files (for example environment files, private keys, credential stores) that the user can extend.
- **FR-7.8.2** Recognizable secrets (API keys, tokens, private-key blocks, and similar patterns) are **redacted before anything is stored**: in snippets, in the lexical index, and in the text that gets embedded. No form of a redacted secret survives in the index.
- **FR-7.8.3** The index is readable only by the user's account.
- **FR-7.8.4** No network access by any search component, at install-time indexing, while indexing, or at query time. No telemetry of content, queries, or results.
- **FR-7.8.5** Redaction is best effort and documented as such, as in mini-meeting-minutes.

### 7.9 Runtime and delivery constraints (L6, L9)

These are constraints on whatever delivery approach Duo v2 adopts, not a choice of one.

- **FR-7.9.1** Inference uses Core ML on device (L6).
- **FR-7.9.2** The model is `BAAI/bge-small-en-v1.5` at a pinned revision (L16), converted for Core ML. The conversion is reproducible, and its provenance and checksums are recorded the way both POCs record theirs.
- **FR-7.9.3** Nothing is fetched from a model hub or any third-party host on the user's Mac, at install or at runtime. Model weights arrive through the same channel as the rest of Duo v2 and are verified against checksums.
- **FR-7.9.4** Updates to the model or runtime flow only through Duo's own update path. Search components never update themselves.
- **FR-7.9.5** The Core ML conversion must match the POC's ranking quality (acceptance in § 12) before it ships.

### 7.10 Replacing existing surfaces (L13)

- **FR-7.10.1** The literal vault search and its CLI counterpart are replaced by this search. Its exact-only mode (FR-7.4.2) must cover what people used literal search for, and anything that relied on the old CLI's output gets a documented migration.
- **FR-7.10.2** The curation view's free-text title and first-prompt filter (consolidation FR-7.3.2) is served by this search, scoped to sessions.
- **FR-7.10.3** If smol-sim-search is also installed, Claude inside Duo is pointed at Duo's search. Its per-folder `./.sem` indexes are left alone.

---

## 8. Data and storage requirements

Storage engine and layout are open (§ 10). Whatever is chosen must meet these requirements:

- **D-1** Stored centrally, in a Duo-owned location outside every project folder (L5), alongside or near Duo's registry.
- **D-2** Keyed so that re-homing, relocating, or moving content never invalidates embeddings (FR-7.3.5). Sessions are keyed by session id and attributed live; content is keyed by content hash.
- **D-3** Records the model identity per index (FR-7.3.8).
- **D-4** Safe for one writer and many concurrent readers, so the CLI can read while indexing is under way (FR-7.7.2). Crash-safe: an interrupted update never leaves a corrupt index, as with the POC's generation swap.
- **D-5** Supports the corpus size in § 9 within the query-latency targets.
- **D-6** Holds no unredacted secrets (FR-7.8.2) and is readable only by the user (FR-7.8.3).

---

## 9. Non-functional requirements

Targets are set against the consolidation PRD's reference machine (41 buckets, 844 MB of transcripts, 6–12 real projects). P0 confirms or revises them.

- **NFR-1 Corpus size.** Must handle the reference machine's full backlog plus project files. A rough estimate, to be measured in P0: on the order of 10⁵ chunks.
- **NFR-2 Query latency.** Results feel instant in the UI. A CLI call completes, including startup, fast enough that Claude prefers it to grep. The POC's figure (~0.25 s cold including model load) is the bar to beat or match.
- **NFR-3 Backfill time.** A reference-machine backfill completes within a working session (hours, not days) without degrading foreground use. At the POC's CPU throughput this would take hours of full CPU, which is why L6 chose Core ML and why P0 measures it.
- **NFR-4 Freshness.** A saved file or a new session turn is searchable within about a minute while Duo is running.
- **NFR-5 Resource use.** Indexing uses bounded memory and disk, and its disk footprint is reported in status.
- **NFR-6 Platform.** Apple silicon Macs. The minimum macOS version follows Duo v2's floor and Core ML's requirements, whichever is higher.
- **NFR-7 Robustness.** Unreadable files, malformed transcripts, and files changing during a read are skipped and reported, never fatal.

---

## 10. Open questions

| # | Question | Why it matters | Proposed way to close |
|---|---|---|---|
| Q1 | Does Duo itself run on the owner's work Mac? | If it doesn't, every surface here is moot there. | Test Duo v2's delivery on the work Mac as early as possible. The CLI design (L10) keeps a standalone fallback viable. |
| Q2 | Can Core ML embed queries inside Claude Code's sandbox without writing outside allowed paths (compiled-model and accelerator caches) or needing accelerator access the sandbox denies? | FR-7.7.2–7.7.3 depend on it. MMM proved Core ML on the work Mac, but not inside Claude's sandbox. | P0 spike: run before-and-after listings of cache locations, as the POC did, with the sandbox on. Test CPU-only compute and precompiled models as mitigations. |
| Q3 | Does the Core ML conversion keep ranking quality at the precision the hardware uses? | The POC found that quantization changed rankings (6–8 of 8 golden top-1s agreed). | P0 parity test (§ 12). |
| Q4 | Which storage engine for the lexical and vector halves? | Affects D-4 concurrency and the CLI's footprint. | Decide in P1 against D-1 to D-6. |
| Q5 | How are semantic and lexical results merged, and how strong is the current-project boost? | Ranking quality. | Tune against the golden set (§ 12). |
| Q6 | What's in the default secret deny-list and redaction patterns? | L15. | Start from common secret-scanner rule sets, and test on the reference machine's transcripts. |
| Q7 | Should record files (CSV/JSONL) offer column selection, as the POC's CLI does? | Embedding every column adds noise. | Default to all text columns, and revisit if results are noisy. |
| Q8 | Should sessions removed by the retention sweep stay findable as snippets? | L17 says no. Listed here only so the trade-off is on record. | Closed unless the owner reopens it. |
| Q9 | ~~Should consolidation L3 be formally amended (L14) in that document?~~ **Closed 2026-10-03:** added to the consolidation PRD as L3b. | — | — |

---

## 11. Phasing

| Phase | Delivers | Exit criterion |
|---|---|---|
| **P0 Gates** | Core ML conversion of bge-small with parity results. Throughput on the slowest supported Apple silicon. Query embedding inside Claude Code's sandbox (Q2). A corpus-size estimate from the reference machine. A Duo v2 viability check on the work Mac (Q1). | Every gate passes, or the PRD is revised: for example, CPU-only compute for the CLI, or keeping ONNX for queries if Core ML can't meet FR-7.7.2. |
| **P1 Files + agent** | Central index (§ 8), the file source across all registry projects, hybrid retrieval, the read-only CLI, Claude guidance, coverage reporting, and a basic search UI. | S-RECALL (files only), S-PARAPHRASE, S-EXACT, S-AGENT, and S-NOAPP pass. |
| **P2 Sessions + memory** | Session, memory, and instructions sources. Unfiled and archived handling. Facets. Open and resume actions. Secret redaction across all sources. | S-RECALL (full), S-UNSORTED, S-SECRET, S-ARCHIVED, and S-COLD pass on the reference machine. |
| **P3 Replace + extend** | Find similar, send to Claude, curation-view integration (L14), replacement of vault search and the title filter (§ 7.10). | S-SIMILAR passes. The old search surfaces are removed with migration notes. |

**Dependencies:** consolidation P0 (inventory) for session discovery, liveness, and the retention sweep. Consolidation P1 (registry) for projects, attribution, Unfiled, and the read-only transcript viewer.

---

## 12. Acceptance and test strategy

- **Golden set.** Extend the POC's golden queries with a cross-project set built from the reference machine: paraphrase queries, exact-identifier queries, and session-recall queries, each labelled with its expected items. Ship gates: hybrid ranks at least as well as semantic-only and lexical-only on every category, and exact-identifier queries put an exact match in the top three.
- **Core ML parity.** On the POC's fixtures, Core ML vectors match the reference model closely enough that every POC golden top-1 is unchanged and known scores agree to within a small tolerance (set in P0).
- **Sandbox compliance.** Before-and-after listings of the user cache locations, the temp locations, and the install location around CLI queries with Claude Code's sandbox on, as in the POC. No writes outside permitted paths, and no network connections.
- **Secrets.** Planted secrets in files and transcripts never appear in stored text, snippets, or results. The planted set covers each pattern class and each source.
- **Lifecycle.** Delete, archive, restore, relocate, and folder move (consolidation fixtures) each produce the correct index state without re-embedding unchanged content.
- **Resilience.** Kill indexing mid-update and the index is still readable and repairs itself. Truncated and unknown-format transcripts are skipped and reported.
- **Coverage honesty.** On a partial index, the reported coverage matches what is actually indexed.

---

## 13. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Duo doesn't run on the work Mac (Q1) | The feature doesn't reach the owner's main environment | Test early. The read-only CLI (L10) can stand alone, as the POC does. |
| Core ML writes caches or needs accelerator access the sandbox blocks (Q2) | The agent path fails in the sandbox | P0 gate. Fall back to CPU-only compute or precompiled models for queries, while the app does background indexing on the accelerators. |
| Conversion changes rankings (Q3) | Worse results than the POC | Parity gate, and keep full precision where needed. |
| Backfill too slow or too heavy (NFR-3) | The person's first impression is "search is broken" or "my Mac is slow" | Recent-first backfill, throttling, honest coverage reporting, and a P0 throughput measurement. |
| Transcript format changes (FR-7.2.2) | Sessions silently drop out of search | Tolerant parsing, coverage counts per source, and fixtures per CLI version (shared with the consolidation PRD). |
| Redaction misses a secret | Secret stored in the index | Index readable only by the user, nothing leaves the Mac, best-effort disclosure, and the user can extend the deny-list. |
| Similarity tools reopen the consolidation PRD's L3 debate | Scope creep into automatic grouping | L14 draws the line: user-initiated only, nothing pre-selected. Analysis features stay out (L12). |

---

## Appendix A — Glossary

Terms from the consolidation PRD (project, registry, bucket, session, Unfiled, junk drawer, archive, sweep) keep their meanings. New terms: **source**, **item**, **chunk**, **locator**, **attribution**, **coverage** (§ 6); **hybrid retrieval**: semantic and lexical retrieval merged into one ranking.

## Appendix B — References

- `dudgeon/smol-sim-search`: README, `CLAUDE.md`, `skills/smol-sim-search/SKILL.md`, `references/{cli,recipes,interpreting-scores}.md`.
- `dudgeon/mini-meeting-minutes`: README, `install.sh`, `Models/README.md`.
- `docs/prd/legacy-session-consolidation.md` (this repo).
- Duo v1 (`dudgeon/duo`): `docs/CLI-COVERAGE.md` (`duo vault search`).
