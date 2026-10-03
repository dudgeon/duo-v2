# Obsidian-compatible task and project file format

Research date: 2026-10-03 · Status: recommendation for owner decision · Scope: `PROJECT.md` and `<project>/tasks/*.md`

**Decision being made.** The owner chose flat tasks: one markdown file per task, with YAML frontmatter. The files must also work as native Obsidian notes, so a project folder (or a parent "topic" folder) can be opened as an Obsidian vault. A richer layer (people, milestones, rollups) should be addable later without a migration. This doc fixes the on-disk contract that makes that possible.

**Markers.** **[V]** = verified this session against a primary source (help page, changelog entry, plugin source, or legacy Duo code/tests). **[U]** = unverified (inferred, or from memory). It needs a 10-minute check in a real Obsidian before the rule depends on it. **[L]** = verified empirically by legacy Duo in a real Obsidian 1.12.7 (`~/repos/duo/docs/prd/enh-208-vault.md` §10, 2026-07-09).

---

## 0. Recommendation in one screen

```yaml
# tasks/draft-prd-v2.md: Duo writes keys in this order; all but the first four are optional
type: task                 # text, required, literal "task"
title: Draft PRD v2        # text, required, human name (filename is the slug)
status: in-progress        # text, required: open | in-progress | waiting | review | done | dropped
owner: Geoff               # text, entity-ref (see §4.3); a person's display name
waiting_on:                # list of entity-refs (people or free text), present only when non-empty
  - Priya Shah
done_when: Eng lead signs off on PRD v2 and it is linked from PROJECT.md   # text, one line
due: 2026-10-10            # date, YYYY-MM-DD
depends_on:                # list of quoted relative markdown links to sibling tasks
  - "[Competitor scan](competitor-scan.md)"
milestone: Beta launch     # entity-ref; becomes a link when milestone notes exist
sessions:                  # list of bare Claude Code session UUIDs (not links, so not graph edges)
  - 3f2c9a1e-8b7d-4c1a-9e2f-5a6b7c8d9e0f
created: 2026-10-03        # date
completed:                 # date, written when status becomes done/dropped (omitted until then)
tags:                      # user-owned; Duo reads it and never writes it
  - prd
```

- **Filenames.** Use lowercase ASCII slugs (`draft-prd-v2.md`), fixed when the file is created. The human name lives in `title:`.
- **Link style.** References to files that exist are **quoted relative markdown links** (`"[Text](path.md)"`). References to things that may not have a note yet (people, milestones) are **plain text**. Readers accept plain text, wikilinks and markdown links interchangeably (§4.3).
- **No nested YAML objects** in any key Duo owns. **No `.obsidian/` writes, ever.**
- `PROJECT.md` uses the same field names where meanings match: `type: project`, `title`, `aliases`, `status`, `health`, `goal`, `owner`, `milestone`, `due`, `tags` (§4.6).

---

## 1. Obsidian primitives as of 2026-10

Release context **[V]**: the current public desktop release is **1.13.7 (2026-08-12)**. **1.14.0–1.14.4** are early access (2026-09-02 → 2026-10-01). Source: [obsidian.md/changelog.xml](https://obsidian.md/changelog.xml).

### 1.1 Properties (frontmatter)

- **Format [V].** YAML between `---` fences at the top of the file. A JSON block is also accepted, but Obsidian reads it and saves it back as YAML ([help/properties](https://obsidian.md/help/properties)).
- **Types [V].** Text, List, Number, Checkbox, Date, Date & time, plus a special Tags type used only by `tags` ([help/properties](https://obsidian.md/help/properties)).
  - Formats are `date: 2020-08-21` and `time: 2020-08-21T10:30:00`.
  - Bases also parses ISO datetimes with a timezone offset since 1.10 ([1.10.3 public, 2025-11-11](https://obsidian.md/changelog/2025-11-11-desktop-v1.10.3/)).
- **Types are vault-wide, keyed by property name [V].** "All properties with that name across your vault will use the same type."
  - Assignments are stored in `.obsidian/types.json` as `{"types": {"<name>": "<type>"}}`. The help page does not name this file; secondary sources do, so treat the file name and shape as **[U]**.
  - 1.13 (public 2026-07-30) shows whether a type was assigned automatically or chosen manually ([1.13 public](https://obsidian.md/changelog/2026-07-30-desktop-v1.13.4/)).
  - **Implication:** Duo's field names must carry the type a vault would naturally infer (`due` = date, `sessions` = list), and must use the same type everywhere. `due` therefore means a date in both tasks and projects.
- **Default properties [V].**
  - `tags`, `aliases` and `cssclasses` must be **lists**.
  - The singular forms (`tag`, `alias`, `cssclass`) and string values were removed in 1.9.10 ([2025-08-18](https://obsidian.md/changelog/2025-08-18-desktop-v1.9.10/)).
  - Publish adds `publish`, `permalink`, `description`, `image` and `cover`.
- **Nested properties: not supported [V].** The help page lists them under unsupported features.
  - The Properties panel shows a nested map as an "unknown type" raw-JSON value **[U, forum reports]**.
  - Bases can read object fields as `property.subprop` or `property["subprop"]` ([help/bases/syntax](https://obsidian.md/help/bases/syntax)).
- **Markdown inside properties: unsupported by design [V].**
- **YAML rewriting [V for the forum reports, U for current behaviour].** Editing any property in the Properties UI re-serializes the whole block:
  - comments are deleted;
  - flow lists become block lists;
  - quoting is normalized;
  - `#` is stripped from tags.

  Sources: forum threads [65851](https://forum.obsidian.md/t/yaml-properties-api-processfrontmatter-removes-alters-string-quotes-comments-types-formatting/65851/6), [104006](https://forum.obsidian.md/t/yaml-bug-editing-in-live-preview-or-reading-mode-reformats-and-deletes-comments/104006) and [101635](https://forum.obsidian.md/t/non-source-mode-property-edits-detrimentally-convert-flow-to-block-style-multi-level-yaml-list-of-lists-sequence-of-sequences/101635).
  - YAML anchors and aliases are disabled on write since 1.9.10 [V].
  - Whether key order is preserved on rewrite is **[U]**; it probably is.

### 1.2 Links

- **Syntax [V].** `[[Note]]` and `[Note](Note.md)` are equivalent. Markdown link targets must be URL-encoded, so a space becomes `%20` ([help/links](https://obsidian.md/help/links)).
- **Settings → Files and links [V]** ([help/settings](https://obsidian.md/help/settings)):
  - **Use [[Wikilinks]]** is on by default. When it is off, Obsidian *generates* markdown links; typing `[[` still works as an autocomplete gesture.
  - **New link format**: *Shortest path when possible* (the default), *Relative path to file*, or *Absolute path in vault*.
  - **Automatically update internal links** on rename.
  - **Override config folder.** The config folder can be renamed but must start with `.`.
- **Links in properties.**
  - Wikilinks must be quoted (`link: "[[Episode IV]]"`, and `"[[Link]]"` inside lists) [V].
  - Unquoted, `[[x]]` parses as a nested YAML sequence. Legacy Duo hit exactly this bug [L].
  - Bases: "Wikilinks in frontmatter properties are automatically recognized as Link objects" [V].
- **Markdown links in properties [V]**, since **1.11** ([EA 2025-12-10](https://obsidian.md/changelog/2025-12-10-desktop-v1.11.0/), [public 2026-01-12](https://obsidian.md/changelog/2026-01-12-desktop-v1.11.4/)):
  - "Markdown links are now supported in text and list properties. Internal links are automatically updated when the destination file is moved or renamed."
  - 1.11 public also fixed markdown links in properties when the file name contains spaces.
  - Legacy Duo confirmed in 1.12.7 that `owner: "[Alice Park](../people/alice-park.md)"` is clickable in Properties and creates a real backlink, whatever the wikilink setting [L].
  - **[U]** Whether Bases treats a markdown-link *property value* as a Link object, so that `x == this` and `x.asFile()` work, is not documented. Do not depend on it; §4.7 shows filters that avoid it.
- **Resolution [V/L].**
  - Wikilinks resolve by **basename**, and a path-qualified form is used when the basename is ambiguous.
  - Frontmatter wikilinks match the *filename only*. They never match `title:` and never match `aliases:`. A title-based wikilink to a slug-named file becomes an unresolved "phantom" node [L].
  - Relative markdown links resolve by path. This means they **do not depend on where the vault root is**, which matters because the owner wants both project-as-vault and topic-as-vault.
- **Renames [V].** Obsidian rewrites inbound links in both syntaxes, frontmatter included since 1.11.

### 1.3 Tags [V] ([help/tags](https://obsidian.md/help/tags))

- `tags:` is a YAML list without `#`. The inline form in the body is `#tag`.
- Tags nest with `/`: `#inbox/to-read`, and a search for the parent matches the children.
- Tags are case-insensitive, contain no spaces, and need at least one non-digit character.
- Bases: `file.hasTag()` is case-insensitive, and `tags.contains("A")` also matches `A/B` (1.9.12 and [1.9.14](https://obsidian.md/changelog/2025-10-01-desktop-v1.9.14/)).

### 1.4 Aliases [V] ([help/aliases](https://obsidian.md/help/aliases))

- `aliases:` is a list. Aliases show up in link suggestions.
- Choosing an alias inserts `[[filename|alias]]`; a bare `[[alias]]` does **not** resolve.
- Aliases are the only way a slug-named file shows its human name in the Obsidian quick switcher and in autocomplete [L, ENH-266e].

### 1.5 Bases (core plugin)

- **History [V].**
  - Introduced in 1.9.0 (EA 2025-05-21) and made public in **1.9.10 (2025-08-18)**. Bases are stored in `.base` files (YAML) or as a ` ```base ` code block embedded in a note.
  - 1.10 (public 1.10.3, 2025-11-11) added **Group by**, the List view, table summaries, the Bases plugin API, the official Maps plugin, `reduce()` and `html()`.
  - 1.12 (public 2026-02-27) added a search toolbar and drag-to-import.
  - **1.14.0 EA (2026-09-02)** added a **Kanban layout**: Group by defines the columns, and dragging a card "update[s] the grouped property in that note". Groups also became collapsible.
  - 1.14.2 lets cards move between folder columns when grouped by `file.folder`.
  - Kanban requires 1.14, which is still early access ([help/bases/views/kanban](https://obsidian.md/help/bases/views/kanban)).
- **File shape [V]** ([help/bases/syntax](https://obsidian.md/help/bases/syntax)):
  - Top-level keys are `filters`, `formulas`, `properties` (e.g. `displayName`), `summaries` and `views`.
  - Each view has `type`, `name`, its own `filters` (AND-ed with the global ones), `groupBy: {property, direction}`, `order`, `summaries` and `limit`.
  - Only **one** group-by property is allowed.
  - Filters are recursive `and`/`or`/`not` lists of expression strings.
- **File properties [V].** `file.name`, `file.path`, `file.folder`, `file.ext`, `file.size`, `file.ctime`, `file.mtime`, `file.tags`, `file.links`, `file.backlinks` (expensive), `file.embeds` and `file.properties`.
- **Functions [V].** `file.hasTag()`, `file.hasLink()`, `file.inFolder()`, `file.hasProperty()`, `list.contains()` / `containsAny()`, `link()`, `file.asLink()`, `link.asFile()`, `link.linksTo()`, `date()`, `today()`, `date.relative()` and `if()`.
- **Link equality [V].** `author == this` is true when the link resolves to this file, and `authors.contains(this)` tests list membership.
- **What `this` refers to [V].**
  - In a base opened directly, `this` is the `.base` file, so `this.file.folder` is the base's folder.
  - In an embedded base, `this` is the embedding note.
  - In the sidebar, `this` is the active note.
- **What Bases can filter and group on.** Any top-level scalar or list property, any `file.*` property, and formulas.
  - Kanban drag-to-move works only for a *note property*. It is disabled for formulas and `file.*`, and only Markdown files can move.
  - **[U]** What a Kanban drag writes for list-valued or link-valued group properties.
  - **Design consequence:** `status` must be a plain text scalar so Kanban can write it.
- **Bases rows are files, not list items.** No core feature turns `- [ ]` checklist lines into rows. **One file per task is therefore the Bases-native unit**, which supports the flat-task decision.

### 1.6 Canvas (brief)

- `.canvas` files use the open JSON Canvas format. Nodes can reference vault files by path.
- Since 1.12 (public 2026-02-27), canvas links count as backlinks and graph edges [V].
- No Duo implications beyond "ignore `.canvas` files and preserve them".

### 1.7 Checkboxes

- Core Obsidian renders `- [ ]` and `- [x]` and lets you toggle them [V, implied by editor notes in the 1.14.0 changelog]. Custom status characters such as `- [/]` render as checked and are styled by themes **[U]**.
- Core search has `task:`, `task-todo:` and `task-done:` operators **[U]**.
- There is no core "task" entity: checkboxes are text inside a note.

---

## 2. Ecosystem conventions (task-as-file)

Install counts come from the `obsidian-releases` stats JSON; activity comes from GitHub. Both were fetched 2026-10-03 [V].

| Plugin | Status 2026-10 | Unit | Relevance to Duo |
|---|---|---|---|
| **TaskNotes** (callumalpass) | Very active: 4.13.8 released 2026-10-02, 1.88M downloads | **One note per task, frontmatter.** Uses Bases for its views | **The de-facto task-as-file convention.** Align vocabulary with it (below). |
| **Obsidian Tasks** | Active: 8.4.0 released 2026-08-25, 4.35M downloads | **Checklist line.** Emoji metadata inline, e.g. `- [ ] Do x 📅 2026-10-10 ⏫ 🆔 a1 ⛔ b2`, or a Dataview-style `[due:: …]` format **[U: emoji set from memory]** | Not a task-file format. Any `- [ ]` subtask inside a Duo task body *will* show up in Tasks queries; that is acceptable. **Duo must not emit Tasks emoji syntax.** |
| **Dataview** | Stagnant: last release 0.5.70 on 2025-04-07, last push 2025-11-17; still 5.07M downloads | Reads frontmatter plus inline `key:: value` fields | Still installed widely, but Bases has replaced it for frontmatter queries. **Duo must never write inline `key::` fields.** The successor, Datacore, is at 0.1.29 (2026-03-23). |
| **Projects** (marcusolsson → obsmd-projects) | **Archived** (last push 2025-07-18) and no longer in the community list | Folder of notes plus frontmatter | Dead. Its job is done by Bases. |
| **Kanban** (obsidian-community) | Stale: last release 2024-05-30; 2.72M downloads | **One board file** of checklist cards (`kanban-plugin:` frontmatter **[U]**) | Not task-as-file. Superseded by the Bases Kanban layout (1.14). Ignore. |
| **mdbase spec** (mdbase-dev, by the TaskNotes author) | Young: ~100 stars, pushed 2026-10-03 | `mdbase.yaml` declares typed markdown collections (JSON Schema, CEL queries) | TaskNotes ships an mdbase contract (`tasknotes-spec` 0.3.0-rc.3, mdbase 0.3.0). Worth watching; no action now. |

**TaskNotes schema [V].** Taken from `@tasknotes/model` 0.3.0-rc.9 `DEFAULT_FIELD_MAPPING` and `src/settings/defaults.ts`.

- **How a note is identified as a task.** Default: tag `task` (`taskIdentificationMethod: "tag"`, `taskTag: "task"`). Alternative: property-based, e.g. `type` = `task`. The default folder is `TaskNotes/Tasks`.
- **Field keys (all configurable).**
  - Core: `title`, `status`, `priority`, `due`, `scheduled`, `contexts`, `projects`.
  - Time and dates: `timeEstimate`, `completedDate`, `dateCreated`, `dateModified`.
  - Other: `attachments`, `recurrence`, `blockedBy`, `reminders`, `timeEntries`, `pomodoros`; the archive tag is `archived`; manual sort order is `tasknotes_manual_order`.
- **Statuses.** `none`, `open`, `in-progress`, `done`; only `done` counts as completed. Default `open`.
- **Priorities.** `none`, `low`, `normal`, `high`. Default `normal`.
- **Dates.** `YYYY-MM-DD`; `scheduled` may carry `THH:mm`.
- **`projects`.** A **list of quoted wikilinks**, e.g. `["[[Q1 Planning]]"]`.
- **`blockedBy`.** A list of **objects** `{uid: "<link>", reltype: FINISHTOSTART|…, gap?}`. That is a nested shape, so it shows as "unknown type" in Properties.

**What is most common for one-note-per-task (2026).** TaskNotes-style frontmatter:

- `status`, `due` and a `project(s)` link in frontmatter;
- tasks identified by a tag or a `type` property;
- views in Bases.

Outside Obsidian, Backlog.md (`docs/research/agent-harness-landscape.md`) uses the same shape. Duo's schema below is deliberately TaskNotes-adjacent:

- the status values overlap (`open`, `in-progress`, `done`);
- `title` and `due` are shared;
- a TaskNotes user can point TaskNotes at Duo tasks by setting property identification to `type` = `task` and adding three statuses.

Duo does *not* adopt TaskNotes' camelCase keys or its nested `blockedBy`. The owner's names (`waiting_on`, `done_when`) are snake_case.

---

## 3. Legacy Duo "OKF" vault: what the owner already used

Sources: `~/repos/duo/core/vault/**`, `.claude/rules/vault.md`, `docs/prd/enh-208-vault.md`, `docs/DECISIONS.md`, and `docs/research/legacy-duo-*.md` in this repo.

**Conventions the owner used (carry forward):**

- **The typing key is `type:`**, never `class:` (`core/vault/corpus.ts`; `.claude/rules/vault.md` "Vocabulary contract"). Templates stamped `type` first.
- **Slug filenames plus `title:`** in OKF mode. `slugStem` (`core/markdown/vaultLinks.ts:53`):
  1. NFKD-normalize and strip diacritics, then lowercase;
  2. turn punctuation into spaces, and turn spaces and underscores into `-`;
  3. collapse runs of `-` and trim `-` from the ends;
  4. cap at 80 characters.

  Slug collisions get `-2`, `-3`, and so on (`core/vault/filing.ts`).
- **Alias auto-seed** (ENH-266e): when a title differs from its slug stem, the title went into `aliases:` so Obsidian's switcher shows it.
- **Relative markdown links at rest**, including inside frontmatter, *quoted*: `owner: "[Alice Park](../people/alice-park.md)"` (ENH-266, 2026-07-09). `[[ ]]` was input-only; no wikilink ever persisted in OKF.
- **Field vocabulary** in the starter templates (`core/vault/scaffold.ts:27-75`):
  - `owner`, `status`, `due`, `initiative`, `attendees: []`, `themes: []`, `aliases: []`;
  - milestone `status: on-track`, initiative `status: active`.
- **`duo.*` frontmatter namespace reserved** (`docs/DECISIONS.md` "Reserved frontmatter namespace", locked 2026-04-24): "Keep the namespace shallow (`duo.foo`…)". Only `duo.trackChanges` was ever reserved, and no code in the repo writes it today.
- **Stable `id:`** (8-char base36 hash, `core/vault/move.ts:68`) minted on OKF notes as the relink key for out-of-band moves.
- **Files are the schema; never cache it in a sidecar** (ENH-228). Refuse to clobber, and never mutate a foreign vault (`isForeignVault`, `obsidian-compat.test.ts`).

**Where OKF diverged from Obsidian, and the lessons:**

1. **FOLLOWUP-051 (2026-06-14).** A bare relative path in YAML (`owner: "./people/alice-park.md"`) is not a graph edge in Duo's parser or in Obsidian; the relationship is silently dropped. The fix switched frontmatter to `"[[Title]]"`.
   - That fix was then **reversed by ENH-266 (2026-07-09)**: a title-based wikilink to a *slug-named* file is a phantom node in Obsidian, because wikilinks resolve by filename only. The final answer was quoted markdown links.
   - **Lesson:** verify parser semantics in a real Obsidian before locking a format (`legacy-duo-changelog-and-studies.md` row `okf-vault-mode.html`).
2. **The YAML `[` trap.** Unquoted `owner: [[Alice]]` is a nested array. Duo's YAML reader and its raw-regex link scanner silently disagreed on it.
3. **`templates/` pollution.** A `type == "X"` filter in a `.base` also matched the template file (ENH-266d). **Lesson:** do not keep files with `type: task` that are not tasks (templates) in the vault, or exclude them in every filter.
4. **Silent auto-migration on vault open** (ENH-266 follow-up, 2026-07-13). The owner chose "fully automatic, silent" link rewriting. That is *incompatible* with the v2 rule "preserve what you didn't write". **v2 should not inherit it.**
5. **Writing `.obsidian/app.json`** (ENH-266c) to flip Obsidian to markdown links. This was absent-only, but it was still a write into Obsidian's config. v2 drops it (§5).
6. **Mode markers** (`okf_version` in `_index.md` vs `.obsidian/`) and two serializers. v2 needs no mode: one serializer (markdown links) whose output Obsidian reads natively.

---

## 4. Recommendation

### 4.1 Principles

1. **Obsidian-normal YAML.** Duo writes frontmatter in the form Obsidian's own serializer produces, so a round-trip through Obsidian's Properties UI produces no meaningful diff:
   - block lists (`key:` then `  - item`);
   - no flow style, no comments, no anchors;
   - scalars unquoted unless YAML requires quotes;
   - links always double-quoted;
   - dates unquoted ISO.
2. **Flat scalars and lists only** in Duo-owned keys. No nested maps.
3. **Readers are lenient, writers are strict.**
   - Duo *reads* wikilinks, markdown links, plain text, flow lists, quoted dates, `\r\n` and JSON frontmatter.
   - Duo *writes* only the canonical forms.
4. **The location is the project.** `<project>/tasks/<slug>.md` belongs to `<project>` because of where it sits. No field can override that.
5. **Surgical edits.** Changing a field rewrites only that key's lines. New keys go at the end of the block, in canonical order. Everything else stays byte-identical.

### 4.2 Task fields (`tasks/*.md`)

| Key | Obsidian type | Required | Value format | Notes |
|---|---|---|---|---|
| `type` | Text | yes | `task` | The typing key (legacy convention). Bases filter: `type == "task"`. For TaskNotes, set property identification `type`=`task`. |
| `title` | Text | yes | free text, one line | Human name. Changing it does **not** rename the file. |
| `status` | Text | yes | `open` \| `in-progress` \| `waiting` \| `review` \| `done` \| `dropped` | Matches the design's "Open → in progress → done" plus three PM states. `review` means the agent proposes done and the human must accept (`agent-harness-landscape.md` §Tasks). `open`, `in-progress` and `done` are TaskNotes' defaults. Kanban columns = status. |
| `owner` | Text | no (default: the user's configured name) | entity-ref (§4.3), single | A person's **display name**, e.g. `Geoff`. Not the token `me`, which means someone else when a file is shared; "mine" is computed by comparing with a Duo setting. |
| `waiting_on` | List | no; omit when empty | list of entity-refs | People, teams or free text ("Legal sign-off"). Soft lint: non-empty ⇒ `status: waiting`. "Needs you" = `waiting_on` contains the user's name. |
| `done_when` | Text | no | one line | Longer criteria go in a `## Done when` body section; Properties can't render markdown. |
| `due` | Date | no | `YYYY-MM-DD` | Never write a datetime into `due`. |
| `depends_on` | List | no | quoted relative markdown links to tasks, e.g. `"[Competitor scan](competitor-scan.md)"` | Real file references, so real links: graph edges, renamed along with the target by Obsidian and by Duo. Not TaskNotes' nested `blockedBy`. |
| `milestone` | Text | no | entity-ref, single | Plain text until milestone notes exist. |
| `project` | Text | **reserved; Duo does not write it** for tasks under `<project>/tasks/` | quoted markdown link to a `PROJECT.md` | It would duplicate the location and drift when a task moves. If present (hand-written, or a future cross-project task), the location wins and Duo shows a lint warning. Duo never rewrites it. |
| `sessions` | List | no; omit when empty | bare Claude Code session UUIDs | See §4.4. |
| `created` | Date | yes (Duo writes it) | `YYYY-MM-DD` | No `updated` field: `file.mtime` covers it, and a timestamp would churn git diffs. |
| `completed` | Date | when status → `done`/`dropped` | `YYYY-MM-DD` | Removed if the task is reopened. |
| `tags` | Tags | user-owned | YAML list, no `#` | Duo preserves and reads tags; it never adds or removes them. |
| `aliases`, `cssclasses`, anything else | — | — | — | Preserved byte-faithfully. |

**Canonical key order** for keys Duo writes: `type, title, status, owner, waiting_on, done_when, due, depends_on, milestone, sessions, created, completed`.

- Duo never moves an existing key. It inserts a missing key just after the nearest preceding canonical key that is present, or at the end of the block.
- If that turns out to be awkward to implement, appending at the end is acceptable.

**Body conventions** (all optional; Duo must parse files without them):

- free prose first, then `## Done when`, `## Notes` and `## Log`;
- subtasks as `- [ ]`;
- no H1. Obsidian shows the filename as the inline title, and Duo shows `title:`.

### 4.3 Entity references: one grammar now, so it can become a link later

`owner`, `waiting_on[]`, `milestone` and `project` share one **value grammar**. Readers must accept all three forms from day one:

| Form | Example | Obsidian graph edge? | Who writes it |
|---|---|---|---|
| plain text | `Priya Shah` | no | Duo v1, for people and milestones with no note |
| quoted relative markdown link | `"[Priya Shah](../../people/priya-shah.md)"` | yes (1.11+) [V/L] | Duo, whenever the target **file exists** |
| quoted wikilink | `"[[priya-shah\|Priya Shah]]"` | yes [V] | Never Duo; users editing in Obsidian (the default setting) will create these |

**Resolution.** Duo's index resolves every form to an entity key:

- A link resolves to its target path.
- Plain text is matched case-insensitively against `title:` and `aliases:` of notes with the right `type:` (`person`, `milestone`). An unmatched value stays a free-text ref.

**Why this needs no migration.**

- The key names and cardinalities (scalar vs list) never change.
- When a people or milestone layer arrives, old plain-text values still resolve through the index, and new writes produce markdown links.
- An *optional*, explicit, previewed "linkify" command can upgrade old values. It never runs automatically, unlike legacy ENH-266.

**Alternative considered: quoted wikilinks to handles now** (`owner: "[[geoff]]"`).

- For: it becomes a resolved Obsidian edge, with zero rewrites, the moment `geoff.md` appears anywhere. This is the Obsidian-native forward-reference idiom.
- Against:
  - it creates unresolved nodes in the graph today;
  - it forces person filenames to equal handles, a vault-wide basename namespace (`legal.md` would collide);
  - it does not fit free-text `waiting_on` entries;
  - it reintroduces the wikilink/slug phantom-node class.
- Rejected, but it is a reasonable owner override (open question Q2).

**Caveat [U].** Bases compares link and string values differently. `waiting_on.contains("Priya Shah")` will miss a value written as a link. Views that must cover mixed forms should match on a formula, e.g. `waiting_on.toString().contains("Priya Shah")`. Test this.

### 4.4 Session IDs

- **Recommendation:** a top-level `sessions:` list of bare UUID strings.
  - It is a normal List property, shown as chips in Obsidian's Properties panel.
  - UUIDs are not link syntax, so they create **no graph nodes**.
  - Bases can filter it (`sessions.length > 0`, or `file.hasProperty("sessions")`).
  - `claude --resume <uuid>` works from it directly, so the data is useful without Duo.
- **Rejected options:**
  - **A nested `duo: {sessions: […]}`.** Obsidian shows it as an "unknown type" JSON blob; Properties edits re-serialize it; and it violates the no-nested-keys rule.
  - **A flat dotted key `duo.sessions:`.** Bases' `duo.sessions` syntax would mean *nested* access, so you would have to write `note["duo.sessions"]` **[U]**. Many YAML-path tools treat it ambiguously.
- **Store only the ID.** Title, state and cwd belong in `.duo/sessions.json` and the SQLite index, which are rebuildable (`stack-recommendation.md` #10). An object list such as `[{id, title}]` would break the Properties UI.
- **Make one side canonical** (`agent-harness-landscape.md` "Task ↔ session link"): **the task file's `sessions:` is canonical for task↔session membership**. `.duo/sessions.json` can cache the reverse but must never be hand-maintained as a second copy.
- **`duo.*` namespace.** Keep it reserved, for Duo-private *app* state only (none is needed for tasks today). If it is ever used, write flat keys with a non-dot separator (`duo_foo`) so Bases and Dataview don't parse them as nested. This changes the legacy `duo.foo` spelling (Q5).

### 4.5 Filenames, folders, link style, tags

- **Slug.** Legacy `slugStem` rules (§3) with a **60-character** cap. Collisions get `-2`, `-3`, and so on.
  - Slugs contain only `[a-z0-9-]`, so they avoid Obsidian-forbidden characters (`# ^ [ ] | \ / :`).
  - They avoid the markdown-link-with-spaces bug class (1.11 fix), and they need no `%20` and no shell quoting for agents.
- **Filenames are fixed at creation.** A title edit does not rename the file; an explicit "Rename file to match title" action does, and it rewrites inbound links in both syntaxes. Agents and session transcripts refer to tasks by path, so stable paths matter more than pretty ones.
- **Folders.**
  - `<project>/PROJECT.md` and `<project>/tasks/*.md` (flat, no subfolders).
  - Duo-private state lives in `<project>/.duo/`. Obsidian ignores dot-folders, so it is invisible to Obsidian **[U, well known]**.
  - Done tasks stay in `tasks/`; filter on status. An optional `tasks/archive/` is out of scope.
- **Links Duo writes, in frontmatter and body: relative markdown links, as written by Obsidian's "Relative path to file" option** (`../PROJECT.md`, `competitor-scan.md`). Why:
  1. They resolve the same whether the vault root is the project folder or the topic folder. `[[PROJECT]]` is ambiguous in a topic vault where every project has a `PROJECT.md`.
  2. They render as links on GitHub and in any CommonMark renderer, including Duo's CM6 editor without wikilink extensions. Wikilinks show as literal `[[…]]`.
  3. Obsidian has supported them in properties, including rename-tracking, since 1.11.
- **Wikilinks: read, never write.** Duo's CM6 editor should *render and follow* `[[…]]` (basename resolution, scoped to the enclosing topic or project) because Obsidian users will write them. Duo must never convert them.
- **Recommended Obsidian settings** (documented for the user; Duo never writes them): Use [[Wikilinks]] **off**, New link format **Relative path to file**, Automatically update internal links **on**.
- **Tags.** Duo does not use tags for structure: type, status and project are properties or locations. `tags:` is the user's. Inline `#tags` in task bodies are fine.

### 4.6 `PROJECT.md` fields

| Key | Type | Required | Values |
|---|---|---|---|
| `type` | Text | yes | `project` |
| `title` | Text | yes | Project name, e.g. `Checkout redesign` |
| `aliases` | List | Duo seeds `[<title>]` at creation | Essential here: the basename `PROJECT` says nothing in the quick switcher or autocomplete. When `title` changes, Duo replaces only the alias entry equal to the old title. |
| `status` | Text | yes | `active` \| `paused` \| `done` \| `archived` |
| `health` | Text | no | `on-track` \| `at-risk` \| `off-track` (legacy milestone vocabulary) |
| `goal` | Text | no | one-line goal statement; the narrative goes in the body |
| `owner` | Text | no | entity-ref |
| `milestone` | Text | no | entity-ref (the next milestone) |
| `due` | Date | no | `YYYY-MM-DD` (target date). Same name and type as in tasks. |
| `tags` | Tags | user-owned | — |

### 4.7 Examples

**`tasks/draft-prd-v2.md`**

```markdown
---
type: task
title: Draft PRD v2
status: waiting
owner: Geoff
waiting_on:
  - Priya Shah
done_when: Eng lead signs off on PRD v2 and it is linked from PROJECT.md
due: 2026-10-10
depends_on:
  - "[Competitor scan](competitor-scan.md)"
milestone: Beta launch
sessions:
  - 3f2c9a1e-8b7d-4c1a-9e2f-5a6b7c8d9e0f
  - 9b1d4e7a-2c3f-4a5b-8e6d-0f1a2b3c4d5e
created: 2026-10-03
tags:
  - prd
---

Rewrite the checkout PRD around the abandonment data. Context in [the project](../PROJECT.md).

## Done when

- [ ] Problem and metrics sections reflect the Q3 funnel data
- [ ] Priya has cleared the data-retention language
- [ ] Eng lead review comments resolved

## Log

- 2026-10-03: First draft written with Claude; sent retention section to Priya.
```

**`PROJECT.md`**

````markdown
---
type: project
title: Checkout redesign
aliases:
  - Checkout redesign
status: active
health: at-risk
goal: Cut checkout abandonment from 38% to 30% by end of Q4
owner: Geoff
milestone: Beta launch
due: 2026-12-15
tags:
  - q4
---

Checkout abandonment is our largest leak. This project ships a one-page checkout with saved payment methods.

## Tasks

```base
filters:
  and:
    - type == "task"
    - 'file.folder == if(this.file.folder == "/", "tasks", this.file.folder + "/tasks")'
views:
  - type: table
    name: By status
    groupBy:
      property: status
      direction: ASC
    order:
      - title
      - owner
      - waiting_on
      - due
```
````

The embedded block is optional; whether Duo scaffolds it is Q6. Duo's own renderer shows it as a code block; in Obsidian it is a live table.

**`tasks.base`** (a standalone file next to `PROJECT.md`; it proves compatibility):

```yaml
# Lists this project's tasks grouped by status. Works whether the vault root is the project or the topic folder.
filters:
  and:
    - type == "task"
    # `this` = this .base file. A vault-root file's folder is assumed to be "/" [U: verify].
    - 'file.folder == if(this.file.folder == "/", "tasks", this.file.folder + "/tasks")'
formulas:
  overdue: 'if(due && due < today() && status != "done" && status != "dropped", "overdue", "")'
properties:
  formula.overdue:
    displayName: Overdue
views:
  - type: table
    name: By status
    groupBy:
      property: status
      direction: ASC
    order:
      - file.name
      - title
      - owner
      - waiting_on
      - due
      - formula.overdue
  - type: table
    name: Waiting
    filters:
      and:
        - status == "waiting"
    order:
      - title
      - waiting_on
      - due
  - type: kanban            # Obsidian 1.14+ (early access as of 2026-10-03); the YAML type id "kanban" is [U]
    name: Board
    groupBy:
      property: status
      direction: ASC
```

A topic-level `all-tasks.base` would use only `type == "task"` and `status != "done"`, grouped by `file.folder`. That needs no `this`.

**Compatibility test to run before locking the format** (about 10 minutes, Obsidian 1.13.7 public plus 1.14 EA):

1. Open a project folder, then its topic folder, as a vault.
2. Confirm `tasks.base` lists the tasks in both cases and checks the `this.file.folder == "/"` assumption.
3. Drag a card on the Board and confirm only the `status` line changes.
4. Edit `due` in the Properties UI and diff the file: confirm key order and quoting survive.
5. Rename `competitor-scan.md` in Obsidian and confirm `depends_on` is rewritten.
6. Check that `depends_on` links appear in Backlinks and that `sessions` UUIDs do not appear in the graph.
7. Test `waiting_on.contains()` with mixed forms.

### 4.8 What Duo must never do

1. **Never create, write or modify the Obsidian config folder** (`.obsidian/` or a renamed `.<name>/` containing `app.json`). That includes `types.json`, `app.json` and workspace files. Never create a `.obsidian/` to "make" a vault.
2. **Never reorder keys, reformat, re-quote or re-flow** frontmatter Duo didn't change. Edit only the lines of the keys being changed; unknown keys, comments and blank lines stay **byte-identical**.
3. **Never delete or rename a key it doesn't own.** Never touch `tags`, `aliases` (except the PROJECT.md title-alias rule) or `cssclasses`, nor `tag`/`alias`/`cssclass`, nor plugin keys (`priority`, `scheduled`, `projects`, `tasknotes_*`, `kanban-plugin`, and so on).
4. **Never write nested maps or object lists** in Duo-owned keys. Never write YAML comments or anchors that Duo depends on, because Obsidian strips them.
5. **Never write an unquoted value that starts with `[`, `{`, `*`, `&`, `!`, `|`, `>`, `%`, `@`, `` ` `` or `#`, or that contains `: `.** Always double-quote links.
6. **Never write a datetime or a timezone offset into a date field.** Never write `#` inside `tags:` values. Never write tags or aliases as strings.
7. **Never rewrite links Duo didn't author.** That means no automatic wikilink↔markdown-link conversion and no silent relink on open (unlike legacy ENH-266). Any bulk rewrite is explicit, previewed and undoable.
8. **Never move or rename a file without rewriting inbound links in both syntaxes**, frontmatter included. When unsure, don't rename.
9. **Never emit Dataview inline fields (`key:: value`) or Tasks-plugin emoji metadata.**
10. **Never require a `types.json` assignment for correctness.** Parse dates from strings and accept quoted dates (`"2026-10-10"`).
11. **Never byte-compare Obsidian-edited files for conflict detection.** Obsidian may re-serialize the block, so compare parsed values, consistent with SHA-based echo suppression for Duo's *own* writes only.
12. **Never put non-task files with `type: task` (templates, fixtures) inside a vault.** Duo's task templates live in the app bundle or `.duo/`.
13. **Never treat `.base`, `.canvas` or other non-`.md` files in `tasks/` as tasks.** Never delete them.

---

## 5. Open questions

- **Q1. Kanban dependence.** Bases Kanban is 1.14 *early access* (2026-10-03). Should the compatibility promise target the 1.13 public release (table/list grouped by status), with Kanban as a bonus?
- **Q2. Entity refs now (§4.3).** Plain text with reader-side resolution (recommended), or quoted wikilinks to handles (immediate Obsidian edges, at the cost of a vault-wide handle namespace)?
- **Q3. `PROJECT.md` naming in topic vaults.** Every project note shares the basename `PROJECT`. Aliases fix the switcher and markdown links fix resolution, but `[[PROJECT]]` typed by a user is ambiguous. Is this acceptable, or should the project note be `<slug>/<slug>.md` (folder-note convention) with `PROJECT.md` dropped? That would conflict with the existing design brief.
- **Q4. Stable `id:`.** Legacy OKF minted 8-char ids for relinking after out-of-band moves. Recommendation: omit in v1 (path = identity; FSEvents tracks renames). Should it be reserved now so a later layer can mint ids lazily?
- **Q5. `duo.*` spelling.** Is the change to flat `duo_` keys (or no Duo-private keys in task files at all) acceptable versus the locked legacy `duo.foo`?
- **Q6. Should Duo scaffold `tasks.base` or the embedded block?** That would be an Obsidian-only artifact in every project. Recommendation: no; offer an explicit "Add Obsidian board" action.
- **Q7. `.obsidian/` in git.** If a user opens a project as a vault, Obsidian creates `.obsidian/` inside a git repo. Duo must not write `.gitignore`/`.obsidian`, so should it *advise* (a one-line hint) when it detects one?
- **Q8. Nested vaults.** Opening both a topic folder and one of its projects as vaults nests `.obsidian/` folders. Obsidian discourages this **[U]**. Should we document "pick one level per topic"?
- **Q9. TaskNotes interop.** Should Duo also accept TaskNotes keys on read (`projects`, `completedDate`, `dateCreated`, `scheduled`, `priority`) so a TaskNotes-created note in `tasks/` shows up correctly? Recommendation: accept `scheduled`/`priority` on read; never write them.
- **Q10. Verify the [U] items** in the §4.7 compatibility test before the schema is locked. In particular: Bases' treatment of markdown-link property values, `this.file.folder` at the vault root, the Kanban `type` id, and key-order preservation in the Properties UI.

## Sources

- **Obsidian help** (help.obsidian.md now redirects to obsidian.md/help; fetched 2026-10-03):
  - [properties](https://obsidian.md/help/properties)
  - [links](https://obsidian.md/help/links)
  - [settings](https://obsidian.md/help/settings)
  - [tags](https://obsidian.md/help/tags)
  - [aliases](https://obsidian.md/help/aliases)
  - [bases/syntax](https://obsidian.md/help/bases/syntax)
  - [bases/functions](https://obsidian.md/help/bases/functions)
  - [bases/views](https://obsidian.md/help/bases/views)
  - [bases/views/kanban](https://obsidian.md/help/bases/views/kanban)
- **Obsidian changelog** ([feed](https://obsidian.md/changelog.xml)):
  - [1.9.0 EA 2025-05-21](https://obsidian.md/changelog/2025-05-21-desktop-v1.9.0/)
  - [1.9.10 public 2025-08-18](https://obsidian.md/changelog/2025-08-18-desktop-v1.9.10/)
  - [1.9.14 2025-10-01](https://obsidian.md/changelog/2025-10-01-desktop-v1.9.14/)
  - [1.10.3 public 2025-11-11](https://obsidian.md/changelog/2025-11-11-desktop-v1.10.3/)
  - [1.11.0 EA 2025-12-10](https://obsidian.md/changelog/2025-12-10-desktop-v1.11.0/)
  - [1.11 public 2026-01-12](https://obsidian.md/changelog/2026-01-12-desktop-v1.11.4/)
  - [1.12 public 2026-02-27](https://obsidian.md/changelog/2026-02-27-desktop-v1.12.4/)
  - [1.13 public 2026-07-30](https://obsidian.md/changelog/2026-07-30-desktop-v1.13.4/)
  - [1.14.0 EA 2026-09-02](https://obsidian.md/changelog/2026-09-02-desktop-v1.14.0/)
- **TaskNotes:**
  - [tasknotes.dev core concepts](https://tasknotes.dev/core-concepts/), [task properties](https://tasknotes.dev/settings/task-properties/), [property identification](https://tasknotes.dev/settings/property-identification/)
  - `@tasknotes/model` 0.3.0-rc.9 (npm) `DEFAULT_FIELD_MAPPING`
  - [github.com/callumalpass/tasknotes](https://github.com/callumalpass/tasknotes) `src/settings/defaults.ts`, `src/types.ts`
- **Ecosystem stats:** [obsidian-releases community-plugin-stats.json](https://github.com/obsidianmd/obsidian-releases), plus the GitHub API for dataview, obsidian-tasks, datacore, obsmd-projects and [mdbase-spec](https://github.com/mdbase-dev/mdbase-spec).
- **Forum threads on YAML rewriting:** linked in §1.1.
- **Legacy Duo (read-only):**
  - `~/repos/duo/core/vault/{types,scaffold,filing,move,detect,obsidian-compat.test}.ts`
  - `~/repos/duo/core/markdown/vaultLinks.ts`
  - `~/repos/duo/.claude/rules/vault.md`
  - `~/repos/duo/docs/prd/enh-208-vault.md` (§3, §10)
  - `~/repos/duo/docs/DECISIONS.md` ("Reserved frontmatter namespace")
  - `~/repos/duo/skill/references/vault-guide.html`
- **This repo:**
  - `docs/research/legacy-duo-{architecture-review,product-review,changelog-and-studies}.md`
  - `docs/research/agent-harness-landscape.md`
  - `docs/design/{claude-design-handoff,stack-recommendation,legacy-requirements}.md`
