# Session forks made in the TUI (GitHub #14)

Geoff's issue: "When a user forks a claude code session, a new tab should open with the forked session, and the existing session tab should remain; session forks should be visible/obvious in the session manager/left pane." This note says what `/branch` and `/fork` actually do, explains the "Workspace not trusted" error from #12, and puts three options to Geoff. No build. Records: F-344 (what the CLI does), Q-218 (which option), Q-219 (the trust error).

Checked on 2026-10-19 against Claude Code **2.1.219** (the work Mac's pinned version, npm-installed into a scratch folder) and **2.1.303** (current; the brief said 2.1.302, but the CLI auto-updated). Every run used a scratch `CLAUDE_CONFIG_DIR`, a dummy API key and `ANTHROPIC_BASE_URL` pointed at a closed port. The conversation was a hand-written two-message transcript resumed with `--resume`, so **no real turn ran**. Duo code facts are from `origin/main` 6b52031.

## 1. What the two commands do

They're different commands, and both exist on 2.1.219 and 2.1.303 with the same behaviour.

| | `/branch [name]` | `/fork [prompt]` |
|---|---|---|
| Description | "Create a branch of the current conversation at this point" | "Copy this conversation into a new background session and keep working here" |
| Which process runs the copy | **The same TUI process.** It switches to the new id, so the terminal now *is* the branch. | **A new background session in Claude's daemon** (`claude --bg`'s host). The TUI stays on the original. |
| The original | Has no process left. "Use /resume ‹old› to return to the original, or run claude -r ‹old› in a new terminal." | Keeps running in the same terminal. |
| Hooks | `SessionEnd` (reason `resume`) for the old id, then `SessionStart` with **`source: "fork"`** for the new id, same pid. On 2.1.303 `session_title` is "‹title› (Branch)". | `SessionStart` with `source: "fork"` for the new id, from a daemon process (not a child of the TUI). Nothing fires for the original. |
| Transcript | A new file. Copied records keep their message `uuid`s and carry **`forkedFrom: {sessionId, messageUuid}`**, plus a `custom-title` record "‹title› (Branch)". | 2.1.303: a new file with the copied records (same uuids) and a "this session began as a fork" note for Claude. **2.1.219: no transcript until the fork gets its first prompt.** Both: `‹config›/jobs/‹short›/state.json` holds `forkParentSessionId`, `forkSessionId` and `"needs": "send a prompt to start"`. |
| Can a terminal show it? | It's already in the terminal. | **`claude attach ‹short›`** shows it in a terminal on both versions (tested). Running `--resume` on it would make two writers (LR-8). |
| Trust | No check. | 2.1.303 runs a background-session trust check that's stricter than the TUI's (§2). 2.1.219 forked fine in every case I tried. |

`ForkLineage` (`Sources/DuoKit/Live/ForkLineage.swift`) still finds both kinds of fork through the shared uuids. Its header says "Claude writes no 'forked from' field". That's no longer true for `/branch`, whose `forkedFrom` names the parent directly.

## 2. Why `/fork` said "Workspace not trusted" (#12)

**Reproduced exactly on 2.1.303.** Here's the setup:

- The parent folder is trusted in `~/.claude.json`, and the project folder below it has no trust entry of its own. That's `~/claude-home`, Geoff's Home, and `couch-spacers`.
- A session starts in the project folder. The TUI accepts the parent's trust, so there's no trust prompt.
- The folder becomes a git repository while the session runs. `couch-spacers/.git` was made at 15:14 on 2026-10-15, 82 minutes after the folder.
- `/fork` then says: "Workspace not trusted. Run `claude` in ‹folder› once and accept the trust prompt, then retry."

**Why.** The background trust check (`Pe` in the 2.1.303 bundle) accepts a trusted parent only up to the git root. A repo's own folder needs its own `hasTrustDialogAccepted`. The TUI checked trust once, at start, when the folder wasn't a repo yet. A fresh `claude` in a git repo under a trusted parent does show the trust prompt (also tested). That's probably how couch-spacers got its `true` entry later.

**Is it Duo's fault?** No. Duo never writes trust and doesn't `git init`. Claude made the repo during the session. The same thing happens in Terminal. The two trust checks disagree inside Claude Code. On 2.1.219, `/fork` worked in the same setup.

**What Duo could do (Q-219):**
- (a) Report it upstream, and in the meantime tell the user what to do. Recommended, and it costs nothing in the app.
- (b) Duo writes the trust entry itself for a project it made under a trusted Home. This is a security decision made for the user, so not without Geoff's say-so.
- (c) When a Duo terminal shows that line, show a "Trust this folder" notice. That's a new visual, so it needs a canvas round.

## 3. What Duo does today

- **`/branch`:** `followSessionChanges` (`AppModel.swift:596`) sees the terminal's beacon report a new id and re-keys the tab, chat and console selection to it. It files the branch as `continued-from:‹old›`. The original loses its tab and becomes an idle row, and its task links aren't copied (`continueTasks` runs only for `source == "clear"`, `AppModel+TaskContext.swift:20`). This is the behaviour #14 reports.
- **`/fork`:** the original keeps its tab. The fork's pid isn't Duo's, so it lands in `liveElsewhere`. Opening its row shows the "open somewhere else" console (DL-109), which offers Resume as a Fork: a fork of the fork. Nothing opens by itself, and no task links are copied. On 2.1.219 it isn't even listed until it gets a prompt (no transcript yet).
- **Left pane:** once both transcripts exist, `ForkLineage` folds parent and fork into one **thread row** (`SidebarModel.swift:52`, "thread · 2" pill with a chevron). The row shows only the most urgent member's name. So the fork is *hidden* inside a row, not "obvious". The thread row has no drawn expanded state.
- **Build plan:** "Thread detection for forks made inside the TUI (S11)" sits under **v1.2 and later** (§3a). The detection mostly exists already (F-57 folds any fork with shared uuids). What's missing is the tab behaviour and a visible fork in the list.

## 4. Options

All three share three pieces:
- Tell `/clear`, `/resume` and `/branch` apart by the SessionStart `source` that `duo2 hook context` already receives.
- Carry task links to a fork, the way `/clear` already does. A fork is a new session in the same work (DL-116).
- Read the parent from `forkedFrom` or the job's `state.json` before falling back to `ForkLineage`.

### Option A: two tabs, both live (recommended)

Gives Geoff exactly what #14 asks for.

- **Tab strip.**
  - `/branch`: the live terminal moves to a **new tab right of the original**, named from Claude's "‹title› (Branch)", and keeps focus, since that's where you're typing. Duo reopens the original in its old tab position with `claude --resume ‹old›`. The resume is a second Claude process that sits at the prompt and costs no tokens until used.
  - `/fork`: a **new tab right of the original runs `claude attach ‹short›`**. Focus stays on the original, because `/fork` means "keep working here".
- **Left pane.** The thread shows its members: the original, then each fork indented under it with "Fork of ‹name›" (the words the group page already uses). That's a new look for an expanded thread row, so it **needs a canvas round**. It overlaps the sidebar-hierarchy design round, so do it there.
- **Task links.** The fork joins every task the original is in.
- **`followSessionChanges`.** On `source == "fork"` with the same pid, split instead of re-keying: re-key the terminal to the new id, open a resume tab for the old id, and file the branch as `forked-from:‹old›`. `/clear` and `/resume` keep today's behaviour. A new arm adopts a daemon fork whose `forkParentSessionId` is one of Duo's tabs: an attach tab and a task-link copy.
- **New pieces.** A terminal kind that runs `claude attach`. Check that chat mode, needs-you and ⌘W behave on an attached session; ⌘W should detach, not end it. A `duo2` verb for anything a button can do (DL-71); the existing `session open` probably covers it.
- **Cost: M–L, Sonnet,** about 2–3 days. The attach terminal is the unknown. One extra live process per `/branch`. The canvas round comes first.
- **Risk.** Claude's daemon and `attach` are newer and less documented than `--resume`. A future CLI change to the job files breaks adoption, but not the tabs Duo already has open.

### Option B: split `/branch`, list `/fork`

- **Tab strip.** `/branch` works as in A. `/fork` opens no tab. The fork stays in Claude's background, where `/fork` put it.
- **Left pane.** The same expanded thread as A. The fork's row says it runs in the background, and opening it attaches instead of showing DL-109's "open somewhere else". Same canvas round.
- **Task links and `followSessionChanges`.** As A.
- **Cost: M, Sonnet,** about 2 days. The attach terminal is still needed, but only on demand.
- **Trade-off.** It respects `/fork`'s own meaning (a background helper) and avoids a tab you didn't ask for. But it's not the "new tab" #14 asks for.

### Option C: follow, and make the original easy to find

- **Tab strip.** No change: one tab follows the live process. `/branch` keeps today's re-key, and `/fork` opens nothing.
- **Left pane.** The expanded thread from A, so the original is one click away. Opening it resumes it in a new tab, which already works. Canvas round as above.
- **Task links.** Copied, as in A.
- **`followSessionChanges`.** Only the task copy and the `forked-from` provenance. No splitting.
- **Cost: S, Sonnet,** under a day after the canvas.
- **Trade-off.** It doesn't keep the original's tab. The `/fork` row still lands on DL-109's screen unless attach is added.

### Build plan placement

A or B pulls part of the v1.2 item into v1. The line to add to §3a: "**Pulled into v1 by DL-n** (Geoff, 2026-10-19, #14): `/branch` replaced the open tab, so the original vanished from the console and lost its task links. That fails the v1 test of never losing a session from view." C would be a small v1 fix, with the rest staying in v1.2.

## 5. Recommendation and answer

**Geoff chose A (2026-10-20).** Next: draw the expanded thread row in the sidebar-hierarchy canvas round, then a Sonnet build. The trust question (Q-219) is still open: Geoff took it to be about Duo's own fork, so it needs asking again with where the error came from.


**Option A**, built after the expanded thread row is drawn in the sidebar-hierarchy round. Trust: **(a)**, report upstream and say what to do, with no Duo change now.

Why A:
- It's the only option where neither session leaves view, and that's the v1 test.
- The `/branch` half reuses what Duo already does (a resume tab, re-keying).
- The `/fork` half is one new terminal kind that #13's per-turn Fork could reuse.

If attach misbehaves in Duo's terminal or in chat mode during the build, B is the fallback with the same visuals.
