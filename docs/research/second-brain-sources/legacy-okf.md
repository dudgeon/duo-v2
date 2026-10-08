# Legacy Duo's OKF vault ("graphbook"): what it was, how it worked, what to carry into v2

Read-only study of `~/repos/duo` (Electron, v0.10.1 to v0.13.7, Jun to Sep 2026) and the v2 research docs in `.claude/worktrees/second-brain`. Paths without a prefix are in `~/repos/duo`. Line refs are `file:line`.

## 0. Names and lineage

- The **product name was "graphbook"** and the **internal/CLI name was "vault"**. D17 later made "vault" the only user-facing word (`.claude/rules/vault.md:9-12`, `docs/prd/enh-208-vault.md` D17).
- The vault shipped first as a **strict Obsidian vault** (ENH-208, v0.10.1, 2026-06-10; `CHANGELOG.md:350`). ENH-216 (v0.11.0, 2026-06-15; `CHANGELOG.md:296`) then added **OKF mode** as a second at-rest serializer and made it the default in the New Vault dialog.
- **"OKF" is Google's "Open Knowledge Format" v0.1** (GoogleCloudPlatform/knowledge-catalog, June 2026), which formalizes Karpathy's "LLM Wiki" gist (`docs/research/okf-brainkit-folder-hierarchy.html`, the "Google OKF" card; `tasks-archive.md:1065`). What the spec says, as legacy read it:
  - the only required field is `type:`;
  - "The directory structure is independent of the domain" (§3);
  - Concept ID = the file's path with `.md` removed (§4);
  - links are plain markdown, and bundle-absolute `/x.md` is recommended (§5.1);
  - consumers must tolerate broken links, unknown types and missing indexes (§5.3);
  - `index.md` "MAY appear in any directory" (§6), and there is a `log.md` (§7);
  - `# Citations` (§8), conformance (§9), version handling (§11).
- **Duo's OKF was a dialect of that spec.** Duo added:
  - D19 filing rules;
  - a minted `id:`;
  - indexes with one heading per type;
  - the `listing:` spec;
  - the `_index.md` naming.

  The brainkit study calls this out as "two dialects under one roof" (`okf-brainkit-folder-hierarchy.html`, risk row "Duo's OKF dialect vs the bare Google-OKF spec").
- **brainkit/loopkit** (the owner's looplibrary project) is a sibling OKF-family "second brain for work" that ships as a Duo vault. It is marked by a root `loop.manifest.json` (`docs/research/duo-changes-plain.html`).

## 1. The OKF format

### 1.1 Mode marker and detection

| Format | Marker (the source of truth) | Links at rest |
|---|---|---|
| OKF | a root `_index.md` (or legacy `index.md`) whose frontmatter has `okf_version:` | `[Display](./note.md)` |
| Obsidian | a `.obsidian/` directory | `[[wikilinks]]` |

Source: `.claude/rules/vault.md:22-25`, `skill/references/vault.md:33-36`.

- **If both markers are present, `okf_version` wins** (D4).
- The mode lives in the vault. `~/.claude/duo/vault.json` is only a pointer: it holds `defaultVault` and `knownVaults` (`core/vault/default-vault.ts:1-30`).
- To find the vault for a path, Duo checks in order (`skill/references/vault.md:85-88`):
  1. an explicit `--vault`;
  2. walking up to the nearest marker;
  3. the default vault;
  4. otherwise, an error.
- **Foreign-bundle guard.** A root `loop.manifest.json` marks a foreign loopkit/brainkit vault (`core/vault/detect.ts:70-83`). Auto-relink and migrations skip it. A generic third-party OKF bundle without that file is *not* detected as foreign. That limit was accepted on purpose.

### 1.2 The root index file (`core/vault/scaffold.ts:246-266`)

```yaml
---
okf_version: "0.1"
title: <vault name>
type: index
---

<!-- duo:listing -->
```

- Duo writes the frontmatter once by hand, so the marker bytes stay stable. After that it never re-serializes the YAML.
- `duo vault publish` regex-replaces only the body after the `<!-- duo:listing -->` fence (`core/vault/listings.ts:1-30`, `LISTING_FENCE` at `:255`).

### 1.3 Frontmatter keys

There was no formal schema file. **"The corpus IS the schema"** (D9 no-sidecar): types, entities, aliases, properties and observed enums are recomputed from frontmatter on every call (`.claude/rules/vault.md:94-97`). `duo vault schema` prints that corpus as JSON, and it is what Claude reads.

| Key | Where | Type | Required? | Meaning |
|---|---|---|---|---|
| `type` | every note | string | **Required in OKF** (D10). Optional in Obsidian mode. | The typing key. **Never `class:`**. This was a recurring trap (`.claude/rules/vault.md:76-79`). An untemplated OKF capture gets `type: note`; the root index gets `type: index`. |
| `id` | every OKF note | 8-char base36 string | Minted at create time in OKF mode (D10). Never minted in Obsidian mode. | A stable relink key: a cyrb53-style hash of rel-path plus content, collision-checked. It is inserted right after the opening `---` (`core/vault/move.ts:66-125`). |
| `title` | OKF entities | string | Optional (D6) | The human name. The filename is a slug. Listings read `title:` before the basename (`listings.ts` `noteTitle`). |
| `aliases` | entities | list | Optional | Other names. OKF stubs auto-seed the title here when title ≠ slug, so vanilla Obsidian can find the note by name (ENH-266e; `scaffold.ts:432-462`). |
| `captured` | inbox notes | `YYYY-MM-DD` | Set on capture | Drives the "stale inbox > 1 week" rule (`core/vault/inbox.ts:1-11`). |
| `description` / `summary` | any | string | Optional | The one-liner in index bullets (`listings.ts` `noteDescription`). |
| `okf_version` | root index only | quoted string `"0.1"` | Required on the marker | Marks the vault as OKF. |
| `listing` | root index only | a Bases-shaped map (`filters`/`formulas`/`views`) | Optional (ENH-230) | Makes the index body render through the rollup engine. |
| `status`, `due`, `owner`, `initiative`, `attendees`, `themes`, `role`, `team`, `date` | per type template | scalar/list; dates are ISO | Soft (the template seeds them empty) | Domain fields. Fields that name another note are **graph edges**. |
| `spec`, `format`, `out`, `last_generated`, `last_hash`, `links` | `type: rollup` notes | string | `out`/`last_*` are stamped by the tool | A rollup's query source and its render provenance (`scaffold.ts:109-141`; `core/vault/rollup-notes.ts:108-186`). |

**Template meta keys.** These sit in `templates/<type>.md` only, and are excluded from a type's field list (`core/vault/corpus.ts:43`). A type's fields are every other key in its template.

- `folder`: the registry folder.
- `filingParent`: the frontmatter key that names the parent.
- `filingLoose`: whether the note sits loose in the parent's folder or in a `notes/` subfolder.
- `folderNote`: the entity owns a folder.

**Edges written in frontmatter.** In OKF mode, an entity reference is a *quoted* markdown link, for example `owner: "[Alice Park](../people/alice-park.md)"` (ENH-266; `core/markdown/vaultLinks.ts:298-335`).

- The quotes are load-bearing. Unquoted, a value that starts with `[` parses as a YAML flow sequence. That makes it invisible to the corpus, while the raw-regex backlink scan still sees it, so the two scans silently disagree (`.claude/rules/vault.md:39-46`).
- Obsidian mode keeps `owner: "[[Alice Park]]"`.

### 1.4 Folder layout

Source: `scaffold.ts:360-390`; filing rules in `skill/references/vault.md:195-212`.

```
<vault>/
  _index.md        okf_version marker + generated listing (legacy: index.md)
  _log.md          generated date log (legacy: log.md), written by publish
  templates/       soft schemas: person, theme, initiative, milestone, meeting, rollup (query-excluded)
  inbox/           atomic captures, YYYY-MM-DD-HHMMSS[ Title].md
  people/ themes/  registry folders for types with no parent
  initiatives/<name>/   folder-note type; its milestones sit loose here, meetings go under notes/
  notes/YYYY/MM/   time-bucket residue for notes whose parent isn't resolved yet
  rollups/         type: rollup notes (+ default HTML out)
  output/          rendered artifacts (legacy out/), regenerable
  archive/YYYY/    proposed only (D20), never automatic
  .obsidian/app.json   OKF seeds ONLY {useMarkdownLinks:true, newLinkFormat:"relative"}
```

- An OKF vault gets **no README and no `bases/` folder** (D10: the root index replaces the README, which had no frontmatter).
- The `.obsidian/app.json` seed was added in ENH-266c (`core/vault/obsidian-compat.test.ts:41-47`).
- Obsidian mode adds `bases/processing.base` and a README, and seeds `app.json` with `{promptDelete:false, alwaysUpdateLinks:true}` (`scaffold.ts:24, 346-359`).
- The walker skips `.obsidian`, `.trash`, `output`/`out`, `rollups` and `templates` (`core/vault/parse.ts:23`).
- `_index.md`/`_log.md` became the default in ENH-245. The plain `index.md`/`log.md` names are still detected. A vault never mixes the two: the log name always pairs with the index name it finds (`core/vault/okf-filenames.ts:17-79`).

### 1.5 Naming

- **OKF filenames are slugs** (D6): lowercase, diacritics stripped, punctuation and spaces folded to `-`, capped at 80 characters, and `note` when empty (`vaultLinks.ts:53-70`).
- The human name lives in `title:` and `aliases:`.
- Obsidian mode keeps the human name as the filename.
- **Exception: inbox captures are not slugged in either mode.** They are named `2026-06-12-101500 Pricing sync.md` (`scaffold.ts:416-418, 486-496`), so a link to one needs angle brackets: `[x](<inbox/2026… Title.md>)` (`move.ts:214-219`).

### 1.6 Link syntax

- **OKF: standard relative markdown links**, always `./`-anchored or climbing with `../`: `[Display](./people/jordan-lee.md)` (`vaultLinks.ts:231-270`).
- **No `[[wikilink]]` ever persists in OKF mode, frontmatter included** (`.claude/rules/vault.md:27-31`).
- **`[[` is an input gesture only.** Typing `[[Name]]` brings up autocomplete or the type-picker. When the target resolves, Duo rewrites it to the mode's at-rest form. This is "expand on resolve", D3 Option A in `docs/research/okf-vault-mode.html`.
- Bundle-absolute `/x.md` links (the form the spec recommends) were rejected. They only resolve on GitHub when the bundle is at the repo root, and they still break when the *target* moves (`okf-vault-mode.html` Decision 5).
- Link identity (`targetKey`) is the extension-less basename, lowercased, with `-`, `_` and space treated as the same character. So `[[Customer Orders]]` and `./customer-orders.md` resolve to one node (`vaultLinks.ts:72-110`).
- Section addressing is `[Meetings](./meetings.md)` in OKF and `[[Meetings#2026-06-09]]` in Obsidian (`skill/references/vault.md:405-416`).

### 1.7 Generated files

**`_index.md` body.** One heading per `type` (capitalized), or per top-level folder, then bullets of the form `* [Title](rel) - description`. This follows OKF §6.

**`_log.md`.** `## YYYY-MM-DD` groups, newest first, dated by **file mtime** (git authorship was skipped because it would need a spawn). This follows OKF §7.

**Stamp.** Both files carry this HTML comment (`listings.ts:257-270`):

```
<!-- duo:generated <kind> · source-hash <h> · dates from <src> · regenerate: duo vault publish -->
```

- `publish` is idempotent and writes only when the bytes change (`CHANGELOG.md:311`).
- `--dir` also writes an index in each folder.
- Hrefs in a listing are URL-encoded, a fix that shipped in v0.13.7 (`CHANGELOG.md:44`).

**Rollup artifacts.** HTML or Markdown files that embed `<!--duo:rollup-snapshot …-->` and `<!--duo:rollup-summary …-->` comments, so a change diff needs no sidecar (`core/vault/rollup.ts:4, 57-63`).

### 1.8 What taught Claude the format

- `skill/SKILL.md:3, 17-23, 217-240`: the hub skill. Its description triggers on vault, notes and rollups.
- `skill/references/vault.md`: the agent operating manual. The format table is at 29-61, the verbs at 63-83, moves at 90-124, frontmatter edges at 126-153, capture-by-narration at 155-177, filing at 195-212, the rollup loop at 214-403, processing at 418-447.
- `skill/references/rollup.md`, plus `rollup-guide.html` for people.
- `skill/references/vault-guide.html`: an illustrated user guide in 12 chapters. Chapter 12 is "OKF in real Obsidian" (line 562).
- `agents/duo.md` (subagent) and `docs/CLI-COVERAGE.md` § Vault.
- `.claude/rules/vault.md`: the contract for developers, path-scoped to `core/vault/**`.

## 2. Rollups and relinking

### 2.1 Rollups: two mechanisms, chosen by format

1. **Static listings in OKF** (D8). `duo vault publish` regenerates `_index.md`/`_log.md` from the corpus.
   - **Code does this, and a human or an agent triggers it.** Nothing watches for changes.
   - ENH-230 (`CHANGELOG.md:228`; `docs/prd/enh-230-okf-listing-convergence.md`): a `listing:` spec in the root index's frontmatter sends the index body through the **same Bases engine** as `.base` files. It supports grouping, `if()`/date formulas and summaries. If there is no spec, the output is byte-identical to the default group-by-`type`.
2. **`.base` queries, in both modes.** Obsidian renders them live; Duo renders them with `duo base render` or `duo rollup render <note|base> --html|--md`.
   - A rollup is a first-class **`type: rollup` note** in `rollups/` (ENH-228 D1). It holds its spec (an embedded ` ```base ` block or `spec:`) and its provenance.
   - Render stamps `out`, `last_generated` and `last_hash` back into the note surgically.
   - "Stale" means `last_hash` ≠ the current corpus hash (`skill/references/rollup.md:16-23, 50-55`). Duo found rollups with a `type == rollup` query; an `index.json` registry was rejected as a sidecar.
   - **The engine is a locked subset of Obsidian Bases 1.13.** Anything outside it renders as a ⚠ cell (D15, warn and render).
   - **Duo-only extensions:**
     - `groups:` declared buckets (Obsidian ignores the key);
     - `list(x).contains()` with link-identity folding;
     - `ancestors()` / `^=`;
     - `file.hasLink` / `@=`;
     - `ancestor:<prop>:<type>` grouping;
     - child-to-parent rollups (`skill/references/vault.md:272-334`).
   - **Who authors and triggers.** Claude writes the spec from the user's description in four steps:
     1. `duo vault schema`;
     2. write the note;
     3. `duo base lint` until clean;
     4. `duo rollup render`.

     The Rollups tab also offered a GUI builder (ENH-243, v0.13.3), and Refresh buttons re-render. "What changed" summaries are a deterministic diff that an interactive Claude narrates (`duo rollup render --summary`, ENH-229).

### 2.2 Relinking (D5)

OKF links are path-anchored, so a move breaks every inbound link. Duo committed to **owning moves** (`core/vault/move.ts:1-26`). Every path below is code, not Claude.

| Path | What it does | Writes |
|---|---|---|
| `duo vault mv <from> <to>` | The clean path. Moves the file, rewrites every inbound href byte-anchored, and re-bases the moved note's own outbound links. Throws if the destination exists. Also carries the `.md.duo.json` sidecar along (`CHANGELOG.md:312`). | the moved note and every note that links to it |
| `duo vault relink [--dry-run]` | Out-of-band repair (after Finder or git moves). Finds dangling markdown links and re-resolves each by **slug first; `id:` only breaks ties when several notes share a slug**. Rewrites the unambiguous ones; reports ambiguous and broken ones and never guesses (`move.ts:403-470`). | the notes that link to moved files |
| `duo vault relink --frontmatter` | The ENH-266 migration (`migrateFrontmatterLinks`, `move.ts:761`). It does four things: frontmatter wikilinks become quoted markdown links; bare frontmatter paths become quoted links; leftover body wikilinks become markdown links; aliases are backfilled. | the affected notes |
| **Auto-relink on vault open** | `maybeAutoRelinkVault` (`electron/main.ts:4404-4426`) runs relink *and* (since 2026-07-13) the frontmatter migration. **It writes when the app boots into the default vault (`main.ts:1836`), and only reports on a live vault switch (`main.ts:4536`).** It skips foreign bundles. Its safety nets are file history and git. | the vault, silently |

**Caveat on `id:`.** Hrefs never contain the id. In practice the id only settles slug collisions, and only when the id appears in the link's display or raw text (`move.ts:396-425`). The brainkit study's claim that the "stable id → loss-free id-first relink" is stronger than the code.

## 3. Features around the vault and what happened to them

| Feature | Shipped | Notes |
|---|---|---|
| CLI verbs: `vault init/list/schema/capture/stub/default/search/mv/relink/publish/promote`, `graph backlinks/orphans`, `base lint/render`, `rollup list/render/diff/delete/duplicate/set` | v0.10.1 to v0.13.3 | They read the filesystem in-process, with no app needed. These verbs were "the agent layer" (`skill/references/vault.md:63-83`). |
| **Capture**: ⇧⌘N quick capture into `inbox/`; capture by narration through Claude | v0.10.2 (`CHANGELOG.md:329`) | ⇧⌘N took over from New Folder (now ⌥⇧⌘N). The design is atomic and lossy capture, with processing doing the filing later. |
| **Inbox** column in the Vault tab, with a stale > 1 week chip | v0.12.2 (ENH-228, `CHANGELOG.md:214`) | Paired with `bases/processing.base` work-lists (stale inbox, untyped notes, milestones without a due date). |
| **Daily notes** | **Never built as a feature.** | "Daily" appears only as an exit criterion: "owner captures daily notes by narration" (`enh-208-vault.md:168`). There was no daily-note template or folder. `@today` smart tokens (D21) insert plain ISO dates. |
| **Templates** as soft schemas, type-picker silent stub on `[[New Name]]`, "+ new type…" writes `templates/<type>.md` | v0.10.2 | Notes created on the Obsidian side land untyped. "Processing" heals them, a designed asymmetry. |
| **Search**: the ⌘⇧F vault palette and `duo vault search` | v0.10.2 | It retired the global find-previous binding. The adversarial review called it "a simpler grep" and said "don't chase operator parity". |
| **Graph/backlinks** | CLI only (`duo graph backlinks/orphans`) | A backlinks panel and a graph view were **deferred indefinitely**; Obsidian was treated as the companion for those (`docs/research/vault-vs-obsidian.html` "don't chase"). |
| **Frontmatter properties panel** with clickable vault links | v0.13.1 (ENH-241) | |
| **Promote** a `##` section into its own entity | v0.11.0 | Originally it left an `![[embed]]` behind (D18). OKF D9 changed that to a plain link. |
| **Processing** pass: CriticMarkup suggestions plus a dated report note, with moves and archiving only proposed | Skill choreography (P8) | Blocked by BUG-199, whole-document churn, so it had to use surgical edits only. |
| **Vault tab and Rollups tab** (a GUI viewer and builder, an Entities grid) | v0.12.2, v0.13.3 | This is the "Phase 3" duplication the pre-build review warned against. |
| **Init-on-choose**, the New Vault dialog, last-used format | v0.13.2 (ENH-242) | Refuses to overwrite an existing `index.md`, and never nests one vault inside another. |

**What the owner actually did.**

- He daily-drove it from June to September 2026 (`docs/research/legacy-duo-product-review.md:120`).
- His real work vault was an OKF vault, "brainkit-gd" (`tasks-archive.md:870`). It was used for an AIPM initiative knowledge base with tracks, goals and initiatives.
- The rollup engine grew to meet that use: v0.13.4 to v0.13.6 added entity filters, ancestors, "links to" and group-by-goal (`CHANGELOG.md:52-76`; `docs/research/aipm-initiative-schema.html`).
- He worked on a second machine (work) from the DMG.

**Reversals and removals, with reasons.**

1. **Frontmatter edge form changed three times.** In each case the parser semantics were never checked before the format was locked.
   - D7 used a bare rel-path. It was reversed by FOLLOWUP-051, because a bare path is not a graph edge in either tool.
   - FOLLOWUP-051 then used `[[Title]]` in both modes (`CHANGELOG.md:303`). It was reversed by ENH-266, because in live Obsidian 1.12.7 a title-based frontmatter wikilink creates a **phantom node**: Obsidian resolves frontmatter wikilinks by filename only, never by title or alias.
   - ENH-266 settled on quoted markdown links (`enh-208-vault.md:208`).
2. **The migration went from opt-in to automatic and silent** (2026-07-13). The owner's reasoning: a CLI step means a legacy vault doesn't "just work" in Obsidian (`enh-208-vault.md:212`). The PRD also records a process incident: delegated attempts published docs ahead of code. Note that `CHANGELOG.md:28` still says "opt-in flag", which is doc drift.
3. **Promote leaves a link, not an embed.** `![[embed]]` gave way to a link because embeds don't render on GitHub.
4. **The rollup output default flipped.** ENH-229 made Markdown the default; ENH-228 D2 made it HTML ("owner is HTML-first"; `CHANGELOG.md:218`).
5. **Copy-as-Markdown was removed** from the Rollups editor header (`CHANGELOG.md:130`).
6. **Renames.** `index.md`/`log.md` became `_index.md`/`_log.md`, and `out/` became `output/` (ENH-245/246). Both use a dual convention, keeping the old name per vault.
7. **The editor sidecar `.md.duo.json` was dropped for fresh notes** because it polluted vaults (BUG-207, `CHANGELOG.md:315`).
8. **An agent built a bespoke dashboard instead of using `duo rollup`** (ENH-234, `tasks-archive.md:788-804`). The cause was contradictory skill text: one doc said "OKF has no `.base`, authoring one is a no-op" and another said "render works in both modes." The fix reconciled the docs inside the one skill rather than adding a second skill.
9. **v2 itself dropped the whole feature.** The verdict was "a second product grafted onto the first", per `legacy-duo-changelog-and-studies.md:216`, `legacy-duo-product-review.md:202`, and `legacy-requirements.md` §3 row "Vault / OKF / Obsidian serializers / Bases engine / rollups as a feature". The pre-build review had warned "Duo becomes a worse Obsidian" (`vault-vs-obsidian.html`).

## 4. LR-n requirements that bear on a second brain

`docs/design/legacy-requirements.md` has **no LR row dedicated to the vault**. The vault is explicitly *dropped*:

> §3: "Vault / OKF / Obsidian serializers / Bases engine / rollups as a feature | A second product. Keep the *patterns*: typed frontmatter edits, views derived from frontmatter. | P, C"

It is also raised as an open question:

> §4 Q6: "**Task model depth.** You daily-drove typed vault entities (initiative, milestone, person) and rollups. Should `tasks/*.md` link to people and milestones, be OKF-compatible so a vault can wrap a project later, and should a cross-project task view group by waiting-on or milestone? [P Q12; A Q1; C 36]"

The carried-forward LRs that a second brain would have to honour:

- **LR-26**: "**Never mutate a folder you didn't create on open**; refuse to clobber existing marker files; prefer the enclosing project over nesting a new one." (This comes straight from the foreign-bundle guard and ENH-242. Note that legacy's own auto-relink and frontmatter migration *do* mutate Duo-created vaults silently on open.)
- **LR-30**: "**Byte-faithful saves**; never normalize untouched markdown; a save-path backstop refuses any serialize that loses table rows or collapses length."
- **LR-31**: "**One reconciliation primitive for every file surface** (editor, HTML view, task index): conflict baseline = raw disk bytes last seen; echo-suppress own writes by hash registered *before* the write, consumed once, no timers."
- **LR-32**: the reconciliation state machine, including "rename/delete → recoverable affordance".
- **LR-34**: "**Agent writes to an open file go through the app** (MCP `doc.edit`, buffer-routed, cursor-preserving)…"
- **LR-35**: "**Atomic writes** … idempotent writers that are byte-equal when nothing changed." (The same rule as `vault publish` F20.)
- **LR-36**: "**Watcher hygiene**: realpath before watch, … ~250 ms debounce, walks off the main thread…"
- **LR-37**: "**Frontmatter properties panel** (expanded by default; typed one-click edits with undo; body untouched by property edits). This *is* the task editor for `tasks/*.md`. Non-throwing YAML parse; CRLF-safe split/join; reserve the `duo.*` namespace."
- **LR-38**: "**File history**: content-addressed, off the save path… Protects `tasks/*.md` from agent mistakes too." (This was legacy's safety net for silent relinks.)
- **LR-42**: "**CriticMarkup comments and suggest mode**…" (The basis of the processing pass.)
- **LR-23**: "**Stale references self-heal.**"
- **LR-25**: "Unified ⌘K / ⌘O … fuzzy-finds projects, tasks, sessions, files".
- **LR-52**: "Every UI action has an agent tool; deliberate asymmetries are written down."
- **LR-56**: "Short tool descriptions + one short skill on *when* to use them; contradictory or missing guidance is treated as a bug." (The direct lesson from ENH-234.)
- **§1 D3**: Claude-derived facts go in a **rebuildable** index, and only Duo-owned facts go in `.duo/`. This is the same as legacy invariant 1 ("files are the source of truth… a rollup registry `index.json` was rejected on principle"; `legacy-duo-changelog-and-studies.md:38`).

`docs/guide/coming-from-legacy-duo.md` never mentions the vault, OKF or rollups. A legacy vault user gets no migration note.

## 5. Compatibility notes

### OKF to Obsidian (what Obsidian does not read cleanly)

1. **Slug filenames.** Obsidian's explorer, tabs, quick switcher and link autocomplete show `alice-park`, not `title:`. Legacy mitigated this by auto-seeding `aliases:` and suggesting the Front Matter Title plugin (`vault-guide.html` ch. 12).
2. **Frontmatter wikilinks to slugged files** create phantom nodes, because resolution is by filename only (ENH-266). Quoted markdown links in frontmatter *do* resolve, and are clickable in Properties.
3. **Obsidian writes `[[wikilinks]]` by default.** Legacy seeded `.obsidian/app.json` with `useMarkdownLinks:true` and `newLinkFormat:"relative"`. **This means writing `.obsidian/`, which v2's DL-6 forbids** ("never write `.obsidian/`").
4. **`templates/X.md` carries `type: X`**, so a native Bases `type == "X"` filter shows a phantom template row. Every type-filtered query needs `'!file.inFolder("templates")'` (ENH-266d).
5. **Duo's Bases extensions** (`groups:`, `ancestors()`, `@=`, `ancestor:` group tokens, child-to-parent rollups) are ignored or unsupported in Obsidian.
6. **CriticMarkup** (`{++…++}`, `{~~a~>b~~}`) from the processing pass is not rendered natively by Obsidian (my inference; legacy docs don't test this).
7. **Notes created in Obsidian** land untyped, without an `id:`, in Obsidian's default folder (`skill/references/vault.md:451-452`).
8. **Housekeeping folders** (`templates/`, `output/`, `rollups/`) are noise in Obsidian's graph and search. The guide tells users to add them to Excluded files.
9. **Moves made in Obsidian.** In an OKF vault, Obsidian's markdown-link auto-update depends on the user's settings. Legacy relied on Duo's auto-relink on open instead.
10. **Inbox filenames with spaces** need `<…>`-wrapped hrefs.
11. **HTML-comment stamps and fences** (`<!-- duo:listing -->`, `<!-- duo:generated … -->`) are harmless in Obsidian's reading view.

### Obsidian to OKF and GitHub

- `[[wikilinks]]` render as literal text on github.com. That was the motivation for OKF (`tasks-archive.md:1065`).
- `![[embeds]]` and `.base` blocks show as inert text on GitHub.
- `.obsidian/` is tool-specific.
- Untyped notes and a frontmatter-less README fail OKF §9.

### Duo's OKF dialect against bare Google OKF (my reading of the spec quotes legacy captured)

1. **`_index.md` is a Duo/owner convention.** The spec's index is `index.md` (§6). A bare-OKF consumer probably won't treat `_index.md` as the index or find `okf_version` there. Legacy only *detects* both names; it doesn't emit the spec name by default.
2. **Identity differs.** The spec's Concept ID is the path. Duo's `./`-relative links and minted `id:` are an extra layer, and moves re-ID a concept under the spec.
3. **Indexes differ.** Duo writes headings per type and a `listing:` spec in the root frontmatter. Both are extras.
4. **Citations are missing.** No Duo analog to `# Citations` (§8) was ever built.

## 6. Lessons for v2

1. **Mine the model, not the engine.** The parts that survived contact with daily use:
   - frontmatter-typed files (`type:`);
   - "the vault IS the schema", computed live;
   - views derived from frontmatter;
   - generated listings stamped with a source hash;
   - quoted markdown links in frontmatter.

   The parts that cost the most and duplicated Obsidian:
   - a second Bases renderer;
   - in-app rollup tabs;
   - two serializers with migrations.

   v2 already leans this way: DL-6 (flat tasks, compatible with Obsidian), DL-17 (markdown links everywhere, quoted in frontmatter), DL-20 (no `.base` unless asked).
2. **Pick one serializer.** Legacy's "one graph, two serializers" doubled every write site and produced the migration chain. v2's DL-17 (markdown links only, read wikilinks but never write them) is legacy's OKF mode without the Obsidian mode, and that is the right call.
3. **Verify the parser before locking a format.** Frontmatter edges flipped three times because nobody opened the file in real Obsidian until late. Make a live Obsidian check, and a GitHub render check, a gate for any format decision. v2's DL-6 Q10 already says this.
4. **Identity: path or id?**
   - Legacy minted `id:` but its relink is effectively slug-first, so the id did little.
   - Bare OKF says path = identity.
   - v2's DL-19 (path is identity, `id` reserved) matches the spec.
   - If a second brain needs move safety, the tool must own moves (`mv` rewrites inbound links) and repair on launch, which is what DL-19 already says. Don't rely on ids alone.
5. **Don't write `.obsidian/`, and don't silently rewrite.**
   - Legacy wrote `.obsidian/app.json` and rewrote vault links silently on open. That conflicts with LR-26's spirit and with v2's DL-6.
   - If v2 ever needs a migration, propose it, or run it under file history (LR-38) with a visible summary.
   - Keep the foreign-folder rule (LR-26), extended to *any* folder Duo didn't create.
6. **Emit spec-conformant OKF if v2 claims OKF.**
   - Every note gets `type:`; slug filenames get `title:` and `aliases:`.
   - Decide `index.md` vs `_index.md` deliberately, since the spec names `index.md`.
   - Keep generated regions fenced and stamped, and make writers idempotent and byte-equal when nothing changed (LR-35).
   - Geoff's 2026-10-07 rule ("every file Duo writes must stay Obsidian- and OKF-compatible") needs exactly this list, plus the `templates/` exclusion rule for any query Duo writes.
7. **Agent guidance is a product surface.** The worst vault failure in production was an agent misled by docs that contradicted each other (ENH-234), not missing code. Use one skill hub, give the vault one paragraph of "when", and generate it from the tool list (LR-52, LR-56).
8. **Capture inbox plus an agent processing pass was the differentiator.** The adversarial review put the value in the agent layer: corpus-as-schema lint, tracked-change processing, prose-to-query. The UI duplicated Obsidian.
   - For v2, a second brain should probably be: a folder convention, a skill, `duo2`/MCP verbs, and the existing editor and properties panel.
   - Obsidian stays the companion for the graph, backlinks and mobile.
9. **Inbox naming should be slugged** if links into the inbox are expected. Legacy's spaced capture names forced `<…>` hrefs.
10. **Daily notes were never a feature.** Capture was atomic inbox notes dated by `captured:`. If v2 wants daily notes, that is new design work: in v2's process that means a canvas and a question (CLAUDE.md "Never invent a design"), not a port.
