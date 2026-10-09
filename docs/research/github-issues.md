# GitHub issues and Projects in Duo

Research date: 2026-10-09 · Status: **proposed, waiting on Geoff** (Q-169 to Q-174) · Canvas: https://claude.ai/artifact/9jwpM4HimuucECDXNhA2Aq · Decision page: https://claude.ai/artifact/9GHsANtdG8XHd1hnM8rcsb · Boards: `docs/design/github-issues-study/`

**The ask.** Geoff, 2026-10-09: "Many projects are repos; some of these repos track issues and/or implement GitHub projects. I don't know if these are already synced/syncable via clone/push/pull — but I want to understand what options exist for duo to help visualize, edit, and otherwise manipulate issues by human and agent. To the extent duo helps manipulate projects, we should attempt to reuse/share ui elements and UX mental models with the kanban features."

**Builds on, doesn't redo.**
- DL-149 and DL-157: GitHub for every repo project (`docs/research/github-primitives.md`).
- DL-148 and DL-150: the task board, computed from task notes (`docs/research/task-board.md`, `docs/design/task-board-handoff/`).
- DL-13: task frontmatter is the truth. DL-116: a session in a task knows it. DL-147: the project's brief. The rule that every file Duo writes stays Obsidian- and OKF-compatible.
- Users have a Claude Code CLI login only. `gh` may be missing or signed out. The work Mac is locked down.

**Markers.** **[doc]** read in a vendor's own docs this session (URL in Sources). **[probe]** run on this Mac on 2026-10-09 (read-only). **[U]** inferred or unverified.

---

## 0. The answer in one screen

- **No, issues and Projects don't travel with the repo.** A clone fetches branches and tags. GitHub exposes `refs/pull/<n>/head` for each pull request's commits, but no ref holds an issue, a comment, a label, a milestone or a Project [probe]. They live in GitHub's database. They're read and written only through the API: `gh`, REST, GraphQL or GitHub's MCP server. What a repo *does* carry is the scaffolding: issue templates and forms, the chooser's `config.yml`, PR templates and workflows, all under `.github/` [doc]. Labels can't be declared in a file at all [doc].
- **Claude can already do all of it.** In a session, Claude runs `gh issue …` with the user's own sign-in. So Duo shouldn't become an issue tracker. It should do what DL-149 did for git: **show the state, make the common moves one click, explain failures plainly, and tell Claude what it needs to know.** Triage, labels and wording stay with Claude and GitHub.
- **Recommended model: link, don't mirror (B).**
  - A task note can track one GitHub issue: a frontmatter line, `issue: "https://github.com/acme/checkout/issues/123"`. A URL property is a link in Obsidian, and nothing else in the note changes.
  - The card and the note show the issue's live state (open or closed, labels, assignee), read through `gh` and cached in `.duo/`.
  - The task's `status` stays local truth; the issue's state stays GitHub's. Duo **offers** to bridge them, and never does it on its own: "Close #123 too" when the task is done, and "closed on GitHub · Mark Done" when GitHub closes it first.
  - Mirroring issues into task notes (two copies, sync, conflicts) is rejected.
- **Recommended surface: an Issues lane on the board (W-A).** It's the board's first lane, filtered to *open, assigned to me* by default. It shows GitHub issues that aren't tasks yet. Dragging one into a lane makes a task note linked to it, with that lane's status. It's the board's own drag, with one new rule. A card with a **box** is yours; a card with the **issue mark** is GitHub's and isn't a task yet.
- **Writes to GitHub: a few explicit ones (b).**
  - Close and Reopen. New Issue from Task: a Duo sheet with `gh`, or GitHub's own new-issue page prefilled without it.
  - When Push opens a PR for a project whose task tracks an issue, the PR description says **"Closes #123"**. GitHub then closes the issue on merge, which needs no sync at all.
  - Labels, assignees and triage go through Claude, with a drafted **Ask Claude to Triage…**, the same pattern as DL-149's Ask Claude to Write These.
- **GitHub Projects (v2): later, but designed now as a board source.** It's the same board component with the Status field's options as its lanes. A drag writes Status. It needs `read:project`, or `project` to write. Geoff's own token has neither [probe], so it's the costliest step (§6). Recommended as ENH, drawn so it reuses the board unchanged.
- **First slice:** the `issue:` link, the card chip, Make Task from Issue, what Claude is told and "Closes #n" in the PR. It's small: it rides on the built repo and board code. The Issues lane follows; Projects comes later.

---

## 1. Facts

### 1.1 What's in a clone, and what isn't

| Thing | In the repo? | Where it lives | Source |
|---|---|---|---|
| Branches, tags | yes | `refs/heads`, `refs/tags` | [probe] |
| A PR's commits | fetchable, not by default | `refs/pull/<n>/head` (`git ls-remote` on cli/cli lists 266 heads, 205 tags and 5,398 `refs/pull/*` refs; nothing else) | [probe] |
| Issues, comments, PR discussion, reviews | **no** | GitHub's database; REST, GraphQL, `gh` | [doc] issues REST; [probe] no refs |
| Labels, milestones | **no** | made in the UI or API by anyone with write access; new repos get ten defaults | [doc] managing-labels |
| Projects (v2) | **no** | owned by a user or an org, not a repo; can span repos | [doc] creating-a-project |
| Issue templates | yes | `.github/ISSUE_TEMPLATE/*.md` (front matter: `labels`, `assignees`, `title`, `type`) | [doc] about templates |
| Issue forms | yes | `.github/ISSUE_TEMPLATE/*.yml`; `projects: [OWNER/NUMBER]` adds new issues to a Project; `labels` must already exist | [doc] syntax-for-issue-forms |
| Template chooser | yes | `.github/ISSUE_TEMPLATE/config.yml`: `blank_issues_enabled`, `contact_links` | [doc] configuring templates |
| PR templates, CODEOWNERS, workflows | yes | root, `docs/` or `.github/`; only on the default branch | [doc] about templates; [U] CODEOWNERS page not opened |

So **clone, pull and push never move an issue.** A repo without network access has its templates but not a single issue. `dudgeon/duo-v2` has issues and Projects switched on, zero issues and no `.github/` [probe].

### 1.2 What can read and write them

| Interface | Issues | Projects v2 | Notes |
|---|---|---|---|
| **`gh issue`** | list, view, create, edit, close, reopen, comment, develop, pin, lock, transfer, delete [doc] | — | `--json` fields include `labels`, `assignees`, `parent`, `subIssues`, `blockedBy`, `blocking`, `issueType`, `closedByPullRequestsReferences`, `projectItems` [doc, probe] |
| **`gh project`** | — | 19 subcommands: list, view, item-list, item-add, item-edit, field-list, … [doc] | minimum scope `project`; refuses client-side without `read:project` [probe] |
| **REST** | full; `per_page` ≤ 100; PRs come back as issues [doc] | **since 2025-09-11**: list and get projects, fields, items; add and remove items; update field values. No field creation, no drafts [doc] | ETags: a 304 doesn't count against the primary limit when authenticated [doc]; `gh api` shows the 304 as an error [probe] |
| **GraphQL** | full | full: `ProjectV2`, items, `fieldValues`, `updateProjectV2ItemFieldValue` (text, number, date, single select, iteration), drafts [doc] | Assignees, labels and milestone change through the issue's own mutations, not the project's [doc]. No ETags. |
| **GitHub MCP server** | `issue_read`, `issue_write`, `list_issues`, `search_issues`, comments, sub-issues, dependencies, labels [doc] | `projects_list`, `projects_get`, `projects_write` (toolset `projects`, off by default) [doc] | Remote at `api.githubcopilot.com/mcp/` (OAuth or PAT) or local Docker. Needs a token or OAuth Duo doesn't hold. |
| **Webhooks** | `issues` on repo, org and App hooks [doc] | `projects_v2_item`: **org hooks only**, public preview [doc] | Need a server that receives them. Duo has none, so a Mac app polls. |

**Newer issue features, all in the API.** Sub-issues and issue types reached GA on 2025-04-09, and the item limit for Projects rose from 1,200 to 50,000 [doc]. Dependencies (blocked by, blocking) reached GA on 2025-08-21 [U: search result; `gh` exposes `blockedBy` and `blocking`]. Issue types are set per organization, so a personal repo has none [U].

### 1.3 Auth, limits, offline

- **Scopes** [doc]:
  - `repo` covers private issues; `public_repo` covers public ones only.
  - `read:project` reads Projects; `project` reads and writes them.
  - Fine-grained tokens **can't reach a user-owned Project at all** (a known gap GitHub lists).
  - `gh auth login`'s minimum is `repo`, `read:org` and `gist`; `project` is added with `gh auth refresh -s project` [doc].
- **Geoff's `gh`** (2.101.0) has `gist`, `read:org`, `repo` and `workflow`. It has **no `read:project`** [probe].
  - Asking `gh issue list` for the `projectItems` field then fails the **whole** command with INSUFFICIENT_SCOPES, not just that field [probe] (F-267).
  - Even a public org's Projects can't be read without the scope [probe].
- **Signed out, `gh` refuses everything**, even a public repo's issues: "To get started with GitHub CLI, please run: gh auth login". `gh api` doesn't send a request either [probe]. Unauthenticated REST through URLSession would work for public repos at 60 requests an hour [doc]. Most work repos are private.
- **Rate limits** [doc]:
  - REST: 5,000 an hour. GraphQL: 5,000 points an hour, at least 1 point a query.
  - Search: 30 a minute; 10 for issue semantic search. Content creation: about 80 a minute.
  - One GraphQL query can fetch every linked issue's state at once, so polling every five minutes costs about 12 points an hour for a project.
- **Offline.** GitHub has nothing offline [doc: no such feature found]. With no network `gh` fails in 0.04 s with `dial tcp …` or `proxyconnect`, exit 1 [probe]. A blackholed route or DNS failure wasn't tested, so Duo sets its own time limit, as DL-149 does. Anything shown offline comes from Duo's cache.

### 1.4 What others do

| Tool | Model | Direction | Worth borrowing |
|---|---|---|---|
| **GitHub Mobile** | thin client: issues and PRs, assign to Copilot [doc] | live | nothing stored locally |
| **GitHub Desktop** | a git client, no issues [doc] | — | confirms "not a tracker" is a normal line to draw |
| **VS Code GitHub PRs & Issues** | saved issue queries, **Start Working on Issue** makes a branch and sets the active issue; the commit box is prefilled; `#` completion [doc] | read; writes via git and PRs | one action from an issue to working on it, and the active issue shown on screen |
| **Linear ↔ GitHub** | the ID in a branch or PR links it; "closes / fixes" in a PR closes; "part of / relates to" links without closing; status moves on push and merge; two-way GitHub Issues sync of comments, status, labels and assignee [doc] | two-way (Linear's cloud) | **the PR's words are the link**; status follows git events |
| **Jira + GitHub** | dev data (branches, commits, PRs) shown on Jira items; Smart Commits transition items; no official Issues sync (Exalate and Unito do it, for a fee) [doc] | one-way into Jira | commit and PR text as the bridge |
| **Obsidian: GitHub Issues** (lonoxx) | one note per issue, frontmatter, a "persist block" for your own text, pull on start and on an interval, PAT [doc] | one-way pull | a stable ID in frontmatter. Shows the mirror's cost: the note is overwritten except your block. |
| **Obsidian: GitHub Tasks** | issues as checkbox lines in one note, `^gh-NNNN` IDs [doc] | one-way | — |
| **Obsidian: GitHub Link** | renders an issue URL as a tag with live title and state; `github-query` blocks [doc] | read | **a link that shows state**: closest to B |
| **git-bug** | issues as git objects (operation logs under `refs/…`), Lamport clocks, offline; bridges to GitHub, GitLab and Jira (no assignees or milestones) [doc] | two-way via bridges | issues *in* git is possible, but it's a different tracker, and teams on GitHub won't move |
| **gh-dash** | TUI, saved issue and PR sections in YAML, custom actions [doc] | read, some writes | sections as saved queries (the lane's filter) |
| **Copilot coding agent** | an issue assigned to Copilot starts an agent session that branches, pushes and opens one PR [doc] | — | **the issue as the launch point for a session**: Duo's "New Session in Task" on a linked task does this with Claude Code |

**The pattern.** Almost everyone **links by ID and derives status from events.** Only Linear and paid connectors sync two-way, over a small field set, and none documents its conflict rules. The Obsidian plugins that write notes pull one-way and protect a user block. Nobody makes a local file the truth for a GitHub issue.

---

## 2. What Claude can already do, and what Duo should add

Claude in a repo project runs `gh` itself. Any of `gh issue create/edit/close/comment` and `gh project item-edit` is one prompt away, under the user's own sign-in. Duo shouldn't wrap that. Following DL-149's split:

| Job | Who | Why |
|---|---|---|
| See which issues are mine and which tasks track which issue | **Duo** | Always visible, costs no turn |
| Link a task to an issue; make a task from an issue | **Duo** | Local file writes; deterministic |
| Keep the card's issue state current; say when GitHub closed it | **Duo** | Cheap polling; one batched query |
| Tell Claude a task's issue | **Duo** | DL-116's hook gains one line |
| "Closes #123" in the PR Duo opens | **Duo** | DL-149's Push sheet already drafts the PR |
| Close or reopen the tracked issue, on an explicit offer | **Duo** (option b) | One click, said before it happens |
| New issue from a task | **Duo** (option b): sheet with `gh`, else GitHub's page | Respects templates and forms |
| Triage, labels, assignees, wording, comments, sub-issues | **Claude**, from a drafted instruction | Judgement and words |
| Anything else on GitHub | Claude or GitHub | As today; Duo's next poll shows the result |

**Don't** make Duo a second GitHub. A label editor, comment threads, assignee pickers, sub-issue trees and milestones would all be poorer copies of github.com and of `gh`.

---

## 3. The model: how issues relate to task notes (board 02)

| | (A) Live, read-only list | **(B) Linked task (recommended)** | (C) Mirror into task notes | (D) A GitHub Project as the board |
|---|---|---|---|---|
| On disk | nothing | `issue:` on the task notes that track one | a task note per issue, kept in sync | nothing (the Project is the truth) |
| Truth for status | GitHub | task `status` local; issue state GitHub's | **two copies** of title, body, state and labels | the Project's Status field |
| Sync | none (read) | none; Duo **offers** close and done, never automatic | two-way with conflict rules | Duo writes Status on drag |
| Conflicts | none | none (no shared field) | many: both edited, closed vs done, label renames, body edits | GitHub's last write wins |
| Repo noise | none | one line per linked note | a file per issue, churning on every refresh; in the repo if `tasks/` is tracked | none |
| Obsidian | n/a | a URL property: clickable | notes overwritten by sync (the lonoxx plugin's persist-block problem) | n/a |
| Offline | cached list | cached state; the link always works | full (stale) | cached, read-only |
| No `gh` / signed out | nothing to show | the link works; the state line says "Sign in to see #123" | can't sync | nothing |
| Cost | M | **S** (link and chip) to M (lane) | L, and ongoing | L, plus a scope step |
| Verdict | a part of B (the Issues lane) | **recommended** | **rejected** | later, as a board **source** (§6) |

**Why B.**
- It needs no sync engine and it has no conflicts. Each fact has one home: the task's status is in the note and the issue's state is on GitHub.
- It matches what nearly every tool does (§1.4): link by ID, show live state, and bridge through events ("Closes #n" in the PR).
- It's Obsidian-clean: one quoted URL property.

**Why not C.**
- Two copies of every field.
- The repo churns on every poll.
- An Obsidian edit and a GitHub edit collide.
- Nobody else trusts a local note as an issue's truth.

**One-off import, though, is B.** Make Task from Issue writes a new note: the issue's title, `issue:`, and the issue's body quoted once under Notes with a "from GitHub, 2026-10-09" line. After that the note is the user's. Duo never rewrites it.

### 3.1 The link on disk (Q-170, board 03)

```yaml
---
type: task
title: Guest checkout times out on slow 3G
status: in-progress
issue: "https://github.com/acme/checkout/issues/123"
sessions: [5f0c…]
created: 2026-10-09
---
```

- **`issue:`, one full URL, quoted (recommended).**
  - A URL property is a clickable link in Obsidian and in OKF tools.
  - It works for GitHub Enterprise hosts.
  - It's unambiguous outside the repo, for example in a task moved to Home.
  - One tracked issue per task keeps "close together" unambiguous.
- **Read leniently, written in one form.** Duo also reads `owner/repo#123`, `#123` (the project's GitHub remote) and an `issues:` list (it takes the first). It writes only the full URL form, and only when asked.
- **Other issue and PR URLs in `references:`** (DL-150) show live state on their reference rows, but get no bridge offers. A task tracks one issue and can mention many.
- **Alternatives:**
  - only `references:`: no new key, but "the" issue becomes ambiguous;
  - an `issues:` list: several tracked issues; then the close offer has to ask which.
- Duo writes `issue:` surgically, through the editor's buffer when the note is open (DL-13's rule). DL-167's "one writer for task-note YAML" covers it.

### 3.2 Bridge rules (board 06)

Every one is an offer. Nothing changes GitHub on its own.

| When | Duo shows | Choosing it does |
|---|---|---|
| A tracked task is marked Done (Set Status, drag onto Done, `duo2 task status`) | Mark Complete's 5-second notice (DL-130) gains **Close #123 too** | `gh issue close 123 -R acme/checkout` (reason "completed"); the card's chip turns closed. Undo while the notice shows reopens. |
| GitHub closes the issue while the task is open | line 2: **closed on GitHub** (`text` semibold), and in the note's properties **Mark Done** | `status: done` (the usual write) |
| The issue reopens while the task is done | line 2: **reopened on GitHub** · Reopen Task | `status: open` |
| Push opens a PR in a project whose open tasks track issues | the drafted PR body ends `Closes #123` (one line per tracked open issue in this repo, unticked rows in the sheet for the rest) | GitHub links the PR and closes the issue on merge, with nothing for Duo to sync |
| A task is dropped (Dropped fold) | nothing on GitHub | — (close as "not planned" is in the issue menu) |

---

## 4. The surface: where issues show (Q-171, boards 04 and 05)

| | **W-A · An Issues lane (recommended)** | W-B · A third segment | W-C · Picker only |
|---|---|---|---|
| What | The board's first lane, `ISSUES · n`, GitHub issues **not yet tracked by a task**; filter popup: *Assigned to me* (default), *Mentioning me*, *All open*, *Label…*; folds to a 34-wide strip like Done | **Sessions \| Tasks \| Issues** in the toolbar; Issues is a list over the left and middle panes, the issue in the right pane | No issue surface. **Link Issue…** in the card and task menus and the note's properties, **New Task from Issue…** in + New task's menu. |
| Mental model | "Pull work onto your board": the board's drag, with one new source | "GitHub's list, beside your board" | "Tasks can point at issues" |
| Reuse | lanes, cards, drag, fold strip, filter popup, right-pane note: **all the board's** | the switch and right pane; a new list | the property rows (DL-150's references look) |
| Cost | M | M–L | S |
| Risk | two kinds of card on one board, so it needs the mark rule (§5) | a second place to look; the board and issues drift apart | issues stay invisible until you go looking |

**W-A's rules.**
- The lane shows only when the project's repo has a GitHub remote with issues switched on (`hasIssuesEnabled`). Its filter menu can hide it, per project, kept in `.duo/` and not in the brief.
- Order: recently updated first, as GitHub orders issues. A drag inside the lane does nothing, as on the board.
- **Dragging a card into a lane** = Make Task from Issue with that lane's status. It writes `tasks/<slug>.md` from the project's task template (DL-146), with `title`, `status` and `issue:` set by key. The card leaves the Issues lane and appears in the target lane as a task, with the issue chip. ⌘Z undoes it (deletes the new note).
- **A click** shows the issue in the right pane, as a card's note does: title, state, labels, assignees, the body rendered read-only, the last 3 comments, then **Make Task**, **Open on GitHub** and **Ask Claude About It…**. It's a read-only page drawn like a note (board 05) [P].
- **Dragging an issue onto a session** in the Sessions view isn't a drop target, so it does nothing. A session dropped onto an issue card is `task new --issue` plus `task add`: a task is made and the session put in it, which is the board's session-onto-card drop.
- **Empty lane:** "No open issues assigned to you in acme/checkout", plus the filter.
- **Without `gh` or signed out:** the lane holds one card-sized notice, "Sign in to GitHub to see issues here", and **Sign In in a Shell…** (DL-149's flow and words).

---

## 5. Shared UI with the board (board 04, 07)

**Carries over unchanged.**
- Lanes, lane headers (`LABEL · n`), the 6 px lane well, card frame, selection border, hover.
- Drag: lift, ghost, the target lane `selected` with a dashed edge, the dashed slot, ⌥⌘← and ⌥⌘→.
- The Done strip and folds; computed order inside task lanes.
- The right pane shows the selected card.
- Session rows (S1) on task cards; `duo2 task status`, `task add` and `task board`.
- The header row: count, Filter tasks, Anyone ▾, + New task.

**New, all [P].**

| Mark | Where | Meaning |
|---|---|---|
| **Issue mark**: a circle with a dot (open), a circle with a tick (closed), in `text2` | in place of the task box, on cards in the Issues lane | GitHub's issue, not a task yet |
| `#123` in mono `text2` | after the title on issue cards; on line 2 of a task that tracks one | the number, never coloured |
| **Issue chip on line 2** of a task card: mark + `#123` + state when not open | task cards that track an issue | "tracked on GitHub" |
| `closed on GitHub` in `text` semibold | line 2 | needs a decision from you; not `needsYou` colour (that stays for sessions, as overdue does) |
| Labels as plain `text2` words, `bug · p1` | issue cards, line 2 | **GitHub's label colours aren't used**: they would break the system's quiet palette |
| `ISSUES · n` lane with a filter popup in its header | first lane | the lane's source |

**At a glance.** A card with a **box** is a task, yours, on disk. A card with the **issue mark** is a GitHub issue that isn't a task. A task card with an issue chip is both, linked. The shapes differ even in a 34-wide strip: the box is square and the mark is round.

---

## 6. GitHub Projects (v2) as a board source (Q-173, board 08)

**Designed now, built later (recommended).**
- **Where.** A source popup replaces the board header's `TASKS · n`: **Tasks ▾**, with *Tasks* and *GitHub: Q4 Roadmap (acme #7)*. Listed when the repo's owner has Projects linked to this repo.
- **Lanes = the board view's column field.** GitHub defaults it to Status; it can be any single-select or iteration field [doc].
  - The options come in GitHub's order and count as the board's `lanes:`, read-only. + Add Column is hidden: columns are edited on GitHub.
  - Items with no value show in **No Status**, as Bases' None column does.
- **Cards = items.**
  - Issues and PRs show the issue mark (a PR shows the branch mark from DL-149's study); drafts show neither.
  - `#n` and the repo show when the Project spans repos.
  - Line 2 holds assignees, the iteration (`Sprint 14`) and the first two text, number or date fields visible in the view. Choosing fields is ENH-36's job.
- **Session rows** come from the local task that tracks the item's issue (`issue:`). Dropping a session on a GitHub card makes that task (`task new --issue` plus `task add`). So sessions attach only to local tasks, never to GitHub.
- **A drag between lanes** writes the field: `gh project item-edit --id … --field-id … --single-select-option-id …`. ⌘Z writes it back. Built-in workflows still run on GitHub, for example closed → Done.
- **Order inside a lane** is GitHub's (it stores item positions). A drag inside a lane does nothing, as on the task board.
- **Filters:** Iteration ▾ (*Current* by default when an iteration field exists) beside Anyone ▾.
- **Scope step.**
  - Reading needs `read:project`; dragging needs `project`. A Project board with neither shows "Duo needs permission to see your GitHub projects", plus **Allow in a Shell…**, which types `gh auth refresh -s read:project` (or `-s project` for writing) for the user to run.
  - Fine-grained tokens can't see user-owned Projects at all [doc], so that case says so.
- **Why later.**
  - It's a second data model for the board (GitHub's fields, positions and workflows).
  - It's a new scope every user has to grant.
  - The org-only webhooks mean polling.
  - Geoff hasn't said his projects use Projects; the duo-v2 repo has none.
  - Linking (B) gives most of the value first.

**Field mapping.**

| Projects v2 | Duo board |
|---|---|
| Status (single select), or the view's column field | lanes, in GitHub's order |
| No value | a **No Status** lane |
| Iteration | a filter (Current, Next, All), and `Sprint 14` on line 2 |
| Assignees | Anyone ▾ and the owner on line 2 (as `owner:` is for tasks) |
| Labels, milestone | line 2 words; a filter later |
| Text, number, date fields | line 2 (ENH-36 chooses) |
| Item position | order inside a lane (GitHub's) |
| Draft issue | a card with no mark and no number; Convert to Issue is on GitHub |
| Built-in workflows | GitHub runs them; Duo shows the result at the next poll |

---

## 7. Human and agent

### 7.1 `duo2` verbs (DL-71)

Every button above has one.

```
duo2 issue list   [--project <p>] [--mine | --mentions | --all | --label <l> | --search <q>] [--json]
                                             the Issues lane (open, not yet tracked by a task)
duo2 issue show   <ref> [--refresh] [--json] the issue preview: state, labels, assignees, body, last comments
duo2 issue open   <ref>                      Open on GitHub
duo2 issue close  <ref> [--not-planned] [--comment <c>] --yes      Close #n (the Done notice's offer)
duo2 issue reopen <ref> --yes
duo2 issue new    --from-task <task> [--web] [--yes]               New Issue from Task (links it on success)
duo2 issue lane   [show|hide] [--filter mine|mentions|all|label:<l>] [--project <p>]
duo2 issue triage [--project <p>]           Ask Claude to Triage…: prints the drafted instruction
duo2 task issue   <task> <ref> | --clear [--project <p>]           Link Issue… / Unlink (writes issue:)
duo2 task new     [title] --issue <ref> [--status <lane>]          Make Task from Issue; a drag from the Issues lane
# later (§6)
duo2 task board   --source tasks | github:<owner>/<number>
duo2 project-item set <ref> <field> <value> --yes                  a drag on a GitHub Project board
```

- **`<ref>`** is a URL, `owner/repo#n`, or `#n` (the project's GitHub remote).
- Anything that writes to GitHub needs `--yes` outside a sheet, as `duo2 repo push` does. Failures exit non-zero with the question's title and body (DL-149 §6).

### 7.2 What Claude is told (DL-116, board 09)

DL-116's SessionStart lines for a task gain one line when the note has `issue:`:

> Duo: this session is in the task "Guest checkout times out on slow 3G" (tasks/guest-checkout-timeout.md, in progress). It tracks GitHub issue acme/checkout#123 (open; labels: bug, p1; assigned: geoffd): https://github.com/acme/checkout/issues/123. Read it with `gh issue view 123 -R acme/checkout --comments`. Change the issue on GitHub only when the user asks. A pull request for this work should say "Closes #123".

- **At UserPromptSubmit**, the same "what changed" line DL-116 already sends gains the issue's changes: "#123 was closed on GitHub", "#123 gained label p0", "#123 was linked".
- **Never the body.** Claude reads it with `gh` when it needs it. That saves tokens, and the body is untrusted content: it's data, not instructions.
- **Ask Claude to Triage…** (the Issues lane's menu), shown before sending, in the project's open session or a new one:
  > Look at the open issues in acme/checkout that are assigned to me (`gh issue list --assignee @me`). For each, suggest labels from the repo's existing ones (`gh label list`), say whether it's a duplicate, and propose a one-line next step. Don't change anything on GitHub until I say which to apply; then use `gh issue edit`.
- **Ask Claude About It…** (the issue preview): "Read acme/checkout#123 with its comments and tell me in five lines what's being asked and what's unclear. Don't change anything on GitHub."
- **New Session in Task** on a task that tracks an issue drafts its first prompt from the issue, like DL-112's drafted prompt: "Work on acme/checkout#123 …". This is VS Code's "Start Working on Issue" and the Copilot agent's issue-as-launch-point, done with Claude Code.

---

## 8. Feasibility (v2)

| Piece | Cost | Risk | Offline | No `gh` / signed out | v1? |
|---|---|---|---|---|---|
| `issue:` link, chip on card and properties | S | low | cached state, "as of 10:32" | the link opens in the browser; "Sign in to see #123" | **v1 slice** |
| Poll linked issues (one GraphQL query per repo, every 5 min while the board shows; dormant off-screen, ENH-45) | S | low: 12 points an hour; never ask for `projectItems` without the scope (F-267) | keeps the cache | no polling | v1 slice |
| Make Task from Issue (menu, and `duo2 task new --issue`) | S | low | needs the issue's title: from the cache, else the URL's number | `#123` title, body empty | v1 slice |
| What Claude is told | S | low (DL-116's hook exists) | cached | the URL only | v1 slice |
| "Closes #n" in Push's PR | S | low (DL-149's sheet exists) | n/a | works: GitHub's compare page takes the body | v1 slice |
| Bridge offers (Close too, closed on GitHub) | S–M | a write to GitHub; explicit only | hidden | hidden | v1.1 (with W-A) |
| Issues lane (W-A) and issue preview | M | two kinds of card, so the mark rule | cached list | sign-in card | v1.1 |
| New Issue from Task | M | templates and forms; required fields mean the web page | n/a | GitHub's new-issue page, prefilled (`?title=&body=&template=`) | v1.1 |
| Ask Claude to Triage / About It | S | none (Claude does the writes, when told) | n/a | Claude's `gh` needs sign-in too: the instruction says so | v1.1 |
| GitHub Project as a board source (§6) | L | new scope; GitHub's model; positions; drafts | read-only cache | nothing | **later (ENH-68)** |
| Mirror into notes (C) | L, ongoing | conflicts, churn | — | — | **no** |

**Shared with DL-149's plumbing.**
- `gh` is found by explicit path, run with `GH_PROMPT_DISABLED=1` and `GH_NO_UPDATE_NOTIFIER=1` and a time limit, and its output is parsed rather than its exit code trusted (F-196).
- Failures use DuoQuestion's words: no `gh`, signed out, SAML, no access, offline.
- The cache is `.duo/issues.json` per project: Duo's state, never committed, and listed unticked in Push like `.duo/` (DL-157).

**On the work Mac.** `gh` may be absent. Then the link, the chip's number, the browser link and "Closes #n" all still work. Nothing here needs a newer Claude Code: the hook lines are plain `additionalContext`, as DL-116's are.

---

## 9. Decisions for Geoff

On the decision page (https://claude.ai/artifact/9GHsANtdG8XHd1hnM8rcsb), each with the recommendation first:

- **Q-169 · The model:** **B, link** · A, live list only · C, mirror · D, Project as the truth.
- **Q-170 · The link on disk:** **`issue:` one URL** · only `references:` · an `issues:` list.
- **Q-171 · Where unlinked issues show:** **W-A, an Issues lane** · W-B, a third segment · W-C, picker only.
- **Q-172 · What Duo writes to GitHub:** **(b) Close/Reopen and New Issue from Task, plus "Closes #n"** · (a) nothing; Claude and GitHub only · (c) triage too (labels, assignees, comments).
- **Q-173 · GitHub Projects:** **later, designed as a board source (ENH-68)** · v1 read-only · v1 read-write · never.
- **Q-174 · When:** **slice 1 in v1, lane and offers in v1.1** · all in v1 · all after v1.

The page's source is `docs/research/github-issues-decisions.html`; answers land in its `answers` collection.

## 10. Records

- **F-266**: Issues, labels, milestones and Projects aren't in a clone. Only branches, tags and `refs/pull/*` are exposed. Templates and forms are in `.github/`.
- **F-267**: `gh` without `read:project` fails a whole issue query that asks for `projectItems`. Signed out, `gh` refuses even public reads. Offline it fails fast with `dial tcp`.
- **Q-169 to Q-174**: §9.
- **ENH-68**: a GitHub Project as a board source (§6).

## Sources

- **GitHub docs** (opened 2026-10-09):
  - docs.github.com/en/rest/issues/issues
  - …/issues/using-labels-and-milestones-to-track-work/managing-labels
  - …/communities/using-templates-to-encourage-useful-issues-and-pull-requests/about-issue-and-pull-request-templates
  - …/configuring-issue-templates-for-your-repository
  - …/syntax-for-issue-forms
  - …/rest/projects/projects
  - …/rest/projects/items
  - …/issues/planning-and-tracking-with-projects/automating-your-project/using-the-api-to-manage-projects
  - …/using-the-built-in-automations
  - …/learning-about-projects/about-projects
  - …/customizing-views-in-your-project/changing-the-layout-of-a-view
  - …/understanding-fields/about-iteration-fields
  - …/creating-projects/creating-a-project
  - …/webhooks/webhook-events-and-payloads
  - …/rest/using-the-rest-api/best-practices-for-using-the-rest-api
  - …/rate-limits-for-the-rest-api
  - …/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api
  - …/rest/search/search
  - …/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps
  - …/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens
  - …/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens
  - …/get-started/using-github/github-mobile
  - …/desktop/overview/about-github-desktop
  - …/copilot/using-github-copilot/coding-agent/about-assigning-tasks-to-copilot
- **GitHub changelog:**
  - github.blog/changelog/2025-04-09-evolving-github-issues-and-projects/
  - github.blog/changelog/2025-09-11-a-rest-api-for-github-projects-sub-issues-improvements-and-more/
  - dependencies (2025-08-21): search result only.
- **`gh` manual:** cli.github.com/manual/gh_issue, gh_issue_list, gh_project, gh_auth_login.
- **MCP server:** github.com/github/github-mcp-server (README, first 100k characters).
- **Others:**
  - code.visualstudio.com/docs/sourcecontrol/github
  - linear.app/integrations/github and linear.app/changelog
  - support.atlassian.com/jira-cloud-administration/docs/integrate-jira-software-with-github/ and …/enable-smart-commits/
  - github.com/lonoxx/obsidian-github-issues
  - github.com/epistemic-technology/obsidian-github-tasks
  - github.com/nathonius/obsidian-github-link
  - github.com/git-bug/git-bug, with its doc/design/data-model.md, doc/feature-matrix.md and doc/usage/third-party.md
  - github.com/dlvhdr/gh-dash
- **Probes** (this Mac, `gh` 2.101.0, read-only):
  - `gh auth status`
  - `gh issue list -R cli/cli --json …` (with and without `projectItems`)
  - `gh project list --owner github`
  - a GraphQL `projectsV2` query
  - `gh api rate_limit`
  - an ETag `If-None-Match` round trip (304)
  - an empty `GH_CONFIG_DIR` (signed out)
  - `HTTPS_PROXY=http://127.0.0.1:9` (offline)
  - `git ls-remote https://github.com/cli/cli.git`
  - `gh repo view` on dudgeon/duo-v2
- **This repo:**
  - `docs/research/github-primitives.md`, `task-board.md`, `project-task-cx.md`, `obsidian-compatible-task-format.md`
  - `docs/design/task-board-handoff/`, `github-handoff/`
  - `docs/design/decisions.md`: DL-13, DL-71, DL-112, DL-116, DL-130, DL-146 to DL-150, DL-157, DL-167
  - `Sources/DuoControl/Actions.swift`
  - `Sources/DuoKit/Live/TaskContext.swift`
