# GitHub in Duo: what legacy offered, what others do, what v2 should do

Research date: 2026-10-07 · Status: **decided, DL-149** (Geoff, 2026-10-07: all of it in v1; repo state in the Files block; Duo's sheet pushes; the fork in v1, known at copy time; a clone per project) · Target: `docs/design/github-handoff/` · Canvas: https://claude.ai/artifact/76ZGzopVk1eLx9d2pnWA2i · Boards: `docs/design/github-study/`

Geoff, 2026-10-07: "claude _can_ perform cli tasks to operate github, but we should incorporate github primitives in many places; eg we should make it easy to add a project from remote (gh), as a new or existing branch, and make it easy to push and/or open a pr (anticipating that many users will not be admin); do research on what legacy duo offered and what we should do".

Duo's users are PMs and other non-engineers with a Claude Code CLI login. Many won't have `gh`, won't be signed in, and won't have admin or even write access to the repos they work in. Duo never stores a token.

Markers: [src] quoted from shipped source code; [probe] observed on this Mac on 2026-10-07; [doc] from a vendor's docs; [U] unverified.

## Contents

0. [The short answer](#0-the-short-answer)
1. [Legacy Duo](#1-legacy-duo)
2. [The landscape](#2-the-landscape)
3. [What v2 should do](#3-what-v2-should-do)
4. [Failure states and their words](#4-failure-states-and-their-words)
5. [Duo and Claude](#5-duo-and-claude)
6. [duo2 verbs](#6-duo2-verbs)
7. [Recommendation, effort, v1 slice](#7-recommendation-effort-v1-slice)
8. [Questions for Geoff](#8-questions-for-geoff)
9. [Records](#9-records)

## 0. The short answer

- **What changes from the legacy call.** `legacy-requirements.md` (the dropped-features table) cut "Git for PMs: worktrees UI, clone, pull, propose-changes PR, repo chips" from v1 as code-shaped. This study brings back four of the five, reshaped: **getting a repo as a new project, its state on the project, Push / Open PR (with a fork when you can't push), and Get Latest.** The worktrees UI stays out. The "folder vanished" recovery pattern and fail-closed probes are kept as before.
- **Duo does the mechanics; Claude does the words.** Duo runs the network and permission steps the same way every time and explains their failures in plain words. Claude writes commit messages and PR descriptions, and resolves conflicts, from an instruction Duo drafts and shows.
- **Never a token.** Duo uses the user's own `gh auth` or git's credential helper (Apple's git ships `osxkeychain`). Sign-in is `gh auth login --web` in a Duo shell tab.
- **Works without `gh`.** Paste a link; git copies and pushes; the pull request opens as GitHub's own compare page, filled in. `gh` adds the repo picker, knowing your access ahead of time, forks, and PR numbers.
- **Assume no admin, maybe no write.** A project from GitHub starts on its own new branch, so a protected `main` doesn't block it. No write access means a fork, said in the sheet before it happens.
- **Not a git client.** No staging area, history, rebase or branch manager. One project, one branch, set when it's made.

## 1. Legacy Duo

Source: `~/repos/duo` (read only), its `CHANGELOG.md` (CL), `tasks.md`, and the three `docs/research/legacy-duo-*.md` summaries. Paths are relative to `~/repos/duo`.

### 1.1 Shared plumbing

- **Exec.** `core/git/exec.ts:65-106`: `execGit('git'|'gh', args)` via `execFile`, no shell, a 10 s default timeout, never throws; ENOENT becomes `notFound`. **BUG-136** (`exec.ts:16-37`, CL:869): a Finder-launched app doesn't inherit the shell's PATH, so `gh` wasn't found and the clone modal falsely said "gh not authenticated"; fixed by prepending `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`.
- **Auth probe.** `core/git/auth.ts:49-78`: `gh auth status`, parsing `Logged in to (\S+) account (\S+)`. Three states: not installed, signed out, signed in.
- **No stored credentials.** No keytar, `safeStorage`, `GH_TOKEN` or PAT anywhere. Policy ENH-224 D9 (`docs/prd/enh-224-file-open-flow.md:79`): rely on the helper `gh` installs. The ENH-149 research (`docs/research/github-auth-probe.html`) recommended `gh auth login --web` and flagged SAML-SSO orgs.
- **Error classifiers.** `core/git/failure-sniff.ts:14-40`: substring heuristics on stderr ("could not read username", "403", "repository not found", …).
- **Argument safety** (CL:269-270, commit 38426fa): values starting with `-` rejected; `--branch=<ref>` and `--` before URLs.
- **Doctor panel** (ENH-150), meant to replace every "run `gh auth login`" pointer: never shipped.

### 1.2 Feature by feature

| Feature | What it did | How it went |
|---|---|---|
| **Repo chips** (ENH-152a/b/c, ENH-155) | `core/git/status.ts:90-143`: five git calls per probe. Chip `main · 3 modified, 2 ahead, 1 behind` (`shared/host-api.ts:1712-1743`); per-file dots ("Modified · +24 / −7"); Open on GitHub / Copy GitHub URL (`core/git/remote-url.ts:43-118`). Display probe fails open. | Geoff rejected v1 for hiding when clean: "no visual indication that duo/ is root of a github repo in the navigator view (very bad)" (`tasks.md:2462`). "Five implementation rounds locked the final shape" (CL:905). BUG-135 (a `~/Documents/.git` claimed every nested repo); BUG-204 (symlinked roots lose the chip; open). |
| **Clone** (ENH-151, ENH-162) | `core/git/clone.ts:77-116`: `gh repo clone`, falling back to `git clone`. Three ways in: File › Clone from GitHub…, right-click in the tree, a URL pasted in ⌘O. `CloneModal.tsx`: URL, parent folder, collision check. `duo clone`. | The modal took 3+ revisions (transparent body, occluded by native views BUG-153/209, ⌘A broken BUG-131). Errors were raw: `Clone failed (<kind>): <stderr>`. The banner said "gh not authenticated" even when gh was missing. Linking an existing folder to GitHub (ENH-154) was never built. |
| **Pull** (ENH-253, v0.13.4) | `core/git/pull.ts:74-185`, no gh: fetch; fast-forward or merge; on conflict `merge --abort`. Dirty tree: a red **"Discard my changes and pull"** that ran `git reset --hard @{upstream}`. Probes fail closed; a TOCTOU re-check. | Geoff: "needs to work without Claude… simple options for a non-GitHub-conversant PM". Shipped with no live walk. Review found probes failing open, false discard warnings, hidden stderr, `--json` exiting 0 on failure. Conflict copy: "ask someone comfortable with git for help". "Unsaved changes" meant uncommitted ones. |
| **Propose changes** (ENH-224, v0.11.2) | Paste a GitHub file URL → a managed checkout in `~/.claude/duo/checkouts/`; a bar in the viewer; one sheet (Title, Branch, Description, diff) → `runShareBack` (`share-back.ts:164-268`): branch `duo/<slug>-<sha>`, commit, `viewerPermission` probe, auto-fork if not WRITE (`fork.ts`), push, `gh pr create`. `--yes` required on the CLI. | Live-verified end to end (octocat/Spoon-Knife PR #40238). Bugs: matched a stranger's `head:main` PR; "View PR" did nothing (`window.open` no-op). Never built: "upstream changed, pull latest". **Forked even when the probe failed.** Fork push URL hard-coded to github.com. Checkouts never refreshed or cleaned. Protected branches never met (always a fresh branch). |
| **Worktrees UI** (ENH-210, ENH-222) | `git worktree list --porcelain`; a pill and switcher; inline New worktree… (`claude/<slug>` in `.claude/worktrees/`); remove from the CLI only. | Geoff: "agents-in-worktrees is Duo's reason to exist". Removed worktrees broke their sessions' resume (ENH-232, open). Record-number collisions three times. |
| **Folder vanished** | `useNavigator.ts:240-268`: back to main with "Worktree "<label>" was removed — you're back on main.", else the nearest ancestor; a probe that throws never drops state. | Worked. Kept by the legacy review. |

Who used what: there's no telemetry; the evidence is Geoff's walks. He drove the chips, pull and worktrees. ENH-224 was built for PM docs living in engineering repos.

### 1.3 Lessons for v2

1. Never store credentials. Find `gh` and `git` by explicit path (BUG-136): a GUI app doesn't inherit the shell's PATH.
2. Display probes may fail open (show nothing); anything that changes files fails closed. Unknown is never 0.
3. One classifier, typed error kinds, words for each. Legacy leaked raw stderr and was sometimes wrong ("gh not authenticated" for gh missing; "unsaved" for uncommitted).
4. Never offer a destructive "discard and pull". Re-check before acting, on every path including the CLI.
5. Anything that publishes under the user's identity (push, PR, fork) needs explicit consent: a sheet in the UI, `--yes` on the CLI.
6. Fork only when the access probe *says* read-only, not when it fails.
7. Treat user values as arguments, never flags.
8. Compare resolved real paths (BUG-204). Don't hard-code `github.com`.
9. Shell-out git surfaces cost a lot of polish (clone modal 3+ rounds, chips 5). Build only what's needed.

## 2. The landscape

### 2.1 Tool by tool

**GitHub Desktop** (the closest model).
- Clone dialog with tabs "GitHub.com", "GitHub Enterprise", "URL"; the first two list your repos [doc].
- Signs in through the browser ("Continue With Browser") and keeps **its own token** in the keychain [doc]. Duo must not do that.
- One toolbar button that changes with state: "Publish branch", `Push origin`, `Pull origin`, `Fetch origin`, with ahead/behind counts and "Last fetched …" (`app/src/ui/toolbar/push-pull-button.tsx`) [src].
- **Warns before you commit, not after a failed push** (`app/src/ui/changes/commit-message.tsx`) [src]: "You don't have write access to **{repo}**. Want to [create a fork]?" and "**{branch}** is a protected branch. Want to [switch branches]?"; rulesets checked locally too.
- Fork dialog: "Do you want to fork this repository?" / "It looks like you don't have write access to {owner/repo}. If you should, please check with a repository administrator. Do you want to create a fork of this repository at {login/repo} to continue?" / **Fork This Repository** [src]. Then "How are you planning to use this fork?": "To contribute to the parent project" / "For my own purposes" [src].
- Create Pull Request opens the browser [doc].

**VS Code** (Source Control and the GitHub extension).
- Action button: Commit → **Publish Branch** → **Sync Changes ↓n ↑n**; sync confirms "This action will pull and push commits from and to "{remote}/{branch}"" (`extensions/git/src/actionButton.ts`, `commands.ts`) [src].
- **Fork after a refused push**: "You don't have permissions to push to "{owner}/{repo}" on GitHub. Would you like to create a fork and push to it instead?" [Create Fork] [No], then "The fork … was successfully created on GitHub." [Open on GitHub] [Create PR] (`extensions/github/src/pushErrorHandler.ts`) [src].
- Its own message for push protection (GH009): "Your push to "{o}/{r}" was rejected by GitHub because push protection is enabled and one or more secrets were detected." [src]
- Auth through its GitHub provider and its own askpass; tokens in SecretStorage (the keychain).

**Tower, Fork (fork.dev).** Account-based repo lists and one-click clone; in-app PR forms; both store their own tokens (PAT or OAuth). Tower forks only on github.com; Fork has no in-app fork. Engineer tools [doc].

**Cursor.** Its editor inherits VS Code's flows. Cloud agents need the Cursor GitHub App, which "Requires Cursor admin access and GitHub org admin access" [doc]: out of reach for Duo's users.

**Claude Code.**
- The CLI uses the user's own git and `gh` (`gh pr create`); it doesn't know your permissions until a push fails. A PR it makes links to the session; `claude --from-pr` resumes it [doc].
- `/install-github-app` needs repo admin and a signed-in `gh` [doc]: out of reach.
- claude.ai/code: GitHub through the Claude GitHub App or an uploaded `gh` token, behind a proxy; "Create PR" offers full, draft, or "jump to GitHub's compose page"; its fetches never prompt ("If git or ssh would ask for a password … the fetch fails") [doc].
- The claude.ai Projects GitHub connector is read-only file sync: "We do not retrieve commit history, PRs, or other metadata" [doc].

**GitHub's web editor.** Editing a repo you can't write to: GitHub "will automatically fork the repository and open a pull request for you"; the commit button becomes **Propose changes** [doc]. The model for "you don't need to know what a fork is".

**`gh` 2.101.0** [probe, help text].
- `gh auth login` defaults to the browser; the token goes in the system credential store, falling back to a plain-text file when none is found. `gh auth setup-git` makes `gh` git's credential helper.
- Exit codes: 0 OK, 1 failure, 2 cancelled, 4 auth required. `gh auth status` exits 1 signed out; with `--json` it always exits 0. `gh repo view` signed out exits 4. **`GH_PROMPT_DISABLED=1 gh pr create` signed out printed the login hint and exited 0.**
- `gh repo clone` of a fork adds the parent as `upstream`. **`gh repo fork` makes the fork `origin` and renames the old origin `upstream`** unless `--remote-name` says otherwise.
- `gh pr create` offers to fork when the branch isn't pushed (interactive only); "Any fork created this way will only have the default branch"; `--head user:branch` skips it (users only, not orgs: cli/cli#10093). `--dry-run` "May still push git changes".
- Permission and protection, as a READ user on `cli/cli`: `gh repo view --json viewerPermission` → `READ`; `gh api repos/o/r --jq .permissions` → push false; **`gh api repos/o/r/branches/trunk` → `"protected": true`, readable by any reader**; `…/branches/trunk/protection` → 404 for non-admins; `…/rules/branches/trunk` lists rulesets only, not classic protection.

**git without `gh`** [probe].
- Apple's git sets `credential.helper=osxkeychain` system-wide (`/Library/Developer/CommandLineTools/usr/share/git-core/gitconfig`).
- With no credential, `GIT_TERMINAL_PROMPT=0 git ls-remote https://github.com/o/r` fails at once: "fatal: could not read Username for 'https://github.com': terminal prompts disabled". **The same for a private repo and one that doesn't exist.**
- Push rejections, reproduced against a local bare repo with a `pre-receive` hook: `remote: error: GH006: Protected branch update failed for refs/heads/main.` / `! [remote rejected] main -> main`; non-fast-forward: `! [rejected] feat -> feat (fetch first)`. GH009 for secrets [src: VS Code]; GH013 for ruleset violations [U]; `Permission to o/r.git denied to <user>` / 403 for no write [U].
- `git status --porcelain=v2 --branch` gives branch, upstream and `branch.ab +1 -1` in one call; a conflict shows as `u UU …` rows.

### 2.2 Comparison

| | Token | Clone picker | No write access | Protected branch | Sync | PR |
|---|---|---|---|---|---|---|
| GitHub Desktop | Its own, keychain | Your repos / URL | Warned before commit; fork dialog + purpose | Warned before commit | One button, ↑↓, last fetched | In browser |
| VS Code | Its own, keychain | Your repos | Fork offered after a refused push | Raw error | Publish, then Sync ↓↑ | Extension or after fork |
| Tower / Fork | Their own | Account list | Fork on github.com / none | Raw error | Separate buttons | In app |
| Claude Code CLI | User's gh / helper | — | Whatever `gh pr create` does | Model reads the error | Model runs git | `gh pr create` |
| claude.ai/code | App or uploaded gh token | Repo selector | Private needs the app | — | Pushes its branch | Full / draft / compose page |
| GitHub web | Browser session | — | Automatic fork, "Propose changes" | Forced to a new branch | — | Compose page |
| **Duo (proposed)** | **User's gh / helper; none stored** | **Your repos (gh) / any link** | **Said in the sheet before pushing; fork on confirm** | **Avoided by a new branch; Move to a Branch if met** | **Repo line + Get Latest; quiet fetch** | **gh, or the compose page** |

### 2.3 Patterns to borrow, and pitfalls

Borrow: Desktop's warn-before (permission and protection known when the repo is added); GitHub web's fork-as-a-side-effect and Desktop's "If you should, please check with a repository administrator"; one state-aware action with ↑↓ counts; tiered capability (gh signed in → everything; keychain only → copy, push, PR in the browser; nothing → public copy and a guided sign-in); `gh` driven non-interactively (`GH_PROMPT_DISABLED=1`, `--json`, `--repo`, `--head`); typed errors from stable tokens (GH006, GH009, 403, fetch first, "could not read Username"); never block on a prompt; show the PR on the project.

Pitfalls: exit codes that lie (`gh pr create` 0 while signed out); `/protection` 404 isn't "unprotected"; private and missing look alike signed out; a 403 can name a stale keychain account; `gh repo fork` swapping origin; the `/usr/bin/git` stub raising a system install dialog when the Command Line Tools are missing [U] (Duo must check for them first: no system alerts, F-54); gh's plain-text token fallback; admin-only paths (the GitHub apps); "pushed" isn't "mergeable".

## 3. What v2 should do

Boards are on the canvas; each [P].

### 3.1 Add a project from GitHub (boards 1–3)

**Where it sits.** Agreed with the project & task CX study (duo-v2-5d, 2026-10-07): Geoff chose its option A, one New project sheet with **Start from: A new folder | A folder I have | From GitHub** (DL-147, theirs). The CX study owns the sheet, the segment and the Name, Goal, In and Will write rows. This study owns everything under From GitHub. New projects write `_PROJECT.md` (DL-147).

**The repo field.** Paste any link (`https://github.com/o/r`, `…/tree/<branch>` which preselects that branch, `git@github.com:o/r.git`, or `o/r` with gh), or **Choose…**: `gh repo list` for you and your orgs, newest push first, and `gh search repos` as you type. Without gh, Choose… explains and offers to install it (board 10).

**The Found box.** Before anything is copied, one quiet box says what Duo found: private or public, whether you can push, whether the default branch is protected, who you're signed in as, and whether the repo is already on this Mac. With gh: `gh repo view --json viewerPermission,visibility,defaultBranchRef` and `gh api repos/o/r/branches/<default> --jq .protected` (plus rulesets). Without gh: `git ls-remote` says only whether it's reachable, and the box says Duo can't tell what you can push until you share.

**The branch** (board 2). Two choices in the sheet (A, recommended): **A new branch for this work** (default; `<login>/<project-slug>`, or `<slug>` without gh; made from the default branch, changeable) or **A branch that's already there** (a popup of GitHub's branches, newest first, with open PR numbers and "yours"; someone else's branch says your pushes join their PR). B, one combined field in GitHub Desktop's style, is drawn and not recommended: a typo silently makes a new branch. A new branch exists only on this Mac until the first push, so making a project never changes GitHub.

**Where it lands** (board 3). **A clone per project**, a normal folder in Home under the topic chosen in In (default: a topic named after the repo). A second project from the same repo is a second copy. Worktrees (one clone, a worktree per project) or a shared hidden bare repo save disk but tie projects together: deleting or moving one breaks the others, which is legacy's ENH-232 again (Q-124). Claude Code's own `.claude/worktrees/` stay as they are inside a project.

**Duo's files stay out of git, visibly.** A checkbox in the sheet, on by default: **Keep `_PROJECT.md` out of git (listed in `.git/info/exclude`)**, which also covers `.duo/`. `.git/info/exclude` stays on this Mac, so Duo's files never reach a commit or PR and the repo's `.gitignore` is untouched. The notice afterwards names it (DL-50: offer, never silent). Unticked, `_PROJECT.md` is an ordinary file the user may commit (Q-125).

**Getting it.** Progress in the same sheet (`git clone --progress`), Cancel removes the half-made folder; then the project opens with the notice: "Copied acme/website into website/pricing-copy, on a new branch, geoff/pricing-copy. Nothing changes on GitHub until you push. `_PROJECT.md` is listed in `.git/info/exclude`, so it stays out of git." Clone by `gh repo clone` when signed in, else `git clone`, values after `--`.

### 3.2 The repo's state on a project (boards 4–5)

Shown only when the project's folder is in a git repo with a GitHub remote; nothing otherwise. Three places drawn:

- **A, under the project's status line** (recommended): two lines in the left pane's header, the branch, then one fact and at most one button. The header is where the project says how it's going.
- B, in the Files block: beside the files, but at the bottom of a pane that's often short.
- C, a toolbar chip with a popover: always visible, but crowds the toolbar, which so far shows place, not state.

In every option, the file tree marks changed and new files (`changed`, `new` in `text2`, where "edited by Claude" sits today), and `_PROJECT.md` reads "kept out of git".

Twelve states (board 5), with the most pressing shown: conflict › signed out › protected › behind › to push › changed › PR › clean. Words: "up to date with GitHub", "3 files changed", "↑2 to push", "not on GitHub yet", "PR #482 open", "↓4 new on GitHub", "1 file in conflict" (in `text` semibold, not `needsYou`, which stays for sessions), "read only · 2 to push to your fork", "protected · 1 to push", "signed out of GitHub", "can't reach GitHub · checked 2 h ago". "Commit" stays out of the line.

Kept current: local state from `git status --porcelain=v2 --branch` on file events; GitHub's side from a quiet `git fetch` every 5 minutes while the project is open (`GIT_TERMINAL_PROMPT=0`, a time limit; on failure the line says so and when it last could); the PR from `gh pr view --json number,state` when signed in.

### 3.3 Push and open a PR (boards 6–8)

**Push…** on the repo line (or Project › Push to GitHub…, ⇧⌘P [P]) opens one sheet: the changed files ticked (with +/−), any commits already made, a **Message**, and **Open a pull request into acme/website main** with a description and **As a draft**. Message and description start from the project's goal and the sessions' titles; **Ask Claude to Write These** has Claude fill them (§5). One button named for what it does: **Push and Open PR**, **Push** (a PR is open), **Fork, Push and Open PR**, **Push and Open in Browser**.

What Duo runs: `git add -- <ticked>`, `git commit -m …`, `git push -u origin <branch>` (never `--force`), then `gh pr create --repo o/r --base main --head <branch> --title … --body-file …` with `GH_PROMPT_DISABLED=1`, checking the output rather than the exit code. The notice: "Pushed geoff/pricing-copy and opened PR #482 into acme/website main. The session "Tighten the FAQ" is told." [Open PR].

**No write access** (board 7). Known before the sheet opens (`viewerPermission` READ or TRIAGE), so the sheet says it first: "**You can read acme/website but not push to it.** Duo will push your branch to your own copy of it on GitHub, geoffd/website (a fork), and open the pull request into acme/website from there. The owners see the pull request; your fork is public if acme/website is." Duo runs `gh repo fork o/r --clone=false --remote --remote-name fork` (so `origin` keeps meaning the original), `git push -u fork <branch>`, `gh pr create --repo o/r --head <login>:<branch>`. An existing fork is reused. When access couldn't be known (no gh, or GitHub didn't say), Duo pushes and asks only if GitHub refuses with 403 (B). Unlike legacy, Duo never forks because a probe failed.

**No `gh`** (board 8). git pushes through the keychain; the PR opens as GitHub's compare page, `https://github.com/o/r/compare/<base>...<branch>?expand=1&title=…&body=…`, filled in, where the user presses Create pull request. Forking needs gh (board 10 explains).

**Protected branch.** Rare, since projects from GitHub start on a branch; for a project adopted from a folder on `main`, Duo knows from the probe and the sheet offers **Move to a Branch and Push**: `git switch -c <new>`, push that, and only once the new branch holds every commit, reset `main` to `origin/main`.

### 3.4 Pull and sync (board 9)

- **Get Latest** brings in new commits on the project's own branch: `git fetch`, `git merge --ff-only --autostash @{u}`, else `git merge --no-edit --autostash @{u}`.
- **Bring In Changes from main** merges the base in, as GitHub's "Update branch" does.
- Merge, never rebase (one step to undo, no force push). Uncommitted files ride along; nothing is ever discarded (legacy's "Discard my changes and pull" is gone).
- A conflict stops with Duo's question: "Your changes and GitHub's both changed content/faq.md. Duo stopped bringing in the 4 new commits on main. Nothing is lost…" [Show the File] [Put Back] [**Ask Claude to Combine**]. Put Back is `git merge --abort`.
- Every probe that leads to a change fails closed.

## 4. Failure states and their words

In Duo's question look (DuoQuestion, never a system alert, F-54). Each says what happened, what was and wasn't changed, and one way forward; git's and gh's own output sits behind a Details disclosure. Classified by exit code and stable tokens; anything unknown says "GitHub refused the push" with Details. Board 10.

| Case | Detected by | Title | Body | Buttons |
|---|---|---|---|---|
| No gh (when a step needs it) | `gh` not found on the explicit path list | Duo needs the GitHub CLI for this | Listing your repos and making a fork use GitHub's own command-line tool, gh. It isn't on this Mac. You can still paste a repo's link: Duo copies and pushes with git. | Paste a Link · **Install in a Shell…** (`brew install gh` typed, not run; without Homebrew, the download page) |
| Signed out | `gh auth status --json hosts`; git's "could not read Username" | Sign in to GitHub | Duo never sees your password or keeps a token. The GitHub CLI signs you in through your browser and keeps the sign-in in your Mac's keychain, where git uses it too. | Cancel · **Sign In in a Shell…** (`gh auth login --web --git-protocol https`, then `gh auth setup-git`; Duo retries when it ends) |
| No access or not found | 404 / ls-remote failure | Duo can't see acme/website | It may be private, the link may be wrong, or your GitHub account (geoffd) hasn't been given access. Ask the repo's owner to add you, or sign in with another account. | Switch Account… · **Open on GitHub** (signed out: "Sign in to see acme/website", Sign In) |
| SAML SSO | "Resource protected by organization SAML enforcement" | acme needs you to authorize single sign-on | Your organization requires single sign-on for the GitHub CLI. Authorize it on GitHub once, then try again. | Cancel · **Open GitHub** |
| Protected branch | probe ahead, or `GH006` | main is protected on acme/website | Changes to main go in through a pull request. Duo can move your 2 commits to a new branch, geoff/pricing-copy, push that and open the pull request. main here goes back to match GitHub. | Cancel · **Move to a Branch and Push** |
| Not fast-forward | `(fetch first)` / `(non-fast-forward)` | GitHub has newer work on geoff/pricing-copy | Someone pushed to this branch (or you did from another Mac). Get it first, then push. | Cancel · **Get Latest and Push** (never a force push) |
| No write (found late) | 403 / "Permission to … denied to <user>" | You can't push to acme/website | GitHub says your account, geoffd, can read it but not push to it. If you should be able to, check with the repo's owner. Or Duo can push to your own copy (a fork) and open the pull request from there. | Cancel · **Fork and Push** (without gh: install gh or ask for access) |
| Secrets | `GH009` | GitHub refused files that look like secrets | GitHub's secret scanning found something like a password or key in content/plans.json and refused the push. Nothing was pushed. Remove it (Claude can help), then push again. | Show Details · **Ask Claude to Remove It** (never offer to bypass) |
| Offline / timeout | network error, time limit | Duo couldn't reach GitHub | Check you're online and try again. Nothing was changed. | OK · **Try Again** (background fetch: the line only) |
| No git identity | `user.email` unset | Tell git who you are | Commits carry a name and email, and this Mac has none set for git. They show on GitHub next to your changes. | Cancel · **Save for This Repo** |
| Conflict | merge stopped | (§3.4) | | Show the File · Put Back · **Ask Claude to Combine** |
| No Command Line Tools | `xcode-select -p` fails | Duo needs Apple's command line tools for git | (stand-in; not drawn) | Checked before `/usr/bin/git` is ever run, so macOS's own install dialog never appears (C-53) |

## 5. Duo and Claude

Claude Code can do all of this from the terminal, and still can. Duo's part is the one-click safe path, the visible state, and plain failures. Board 11.

| Step | Who | Why |
|---|---|---|
| Copy a repo, make the branch | Duo | Deterministic; from the sheet's answers; no turn spent |
| Know your access and the rules | Duo | Probed once, then told to Claude, so Claude never guesses |
| The repo line, fetch | Duo | Always on |
| Commit message, PR title and description | Claude, if asked | Words from the work |
| Commit, push, fork, open the PR | Duo | Publishes under your name: only from the sheet you confirmed |
| A conflict | Claude, if asked | Judgement |
| Anything else git | Claude | As today; Duo's line shows the result |

**What Claude is told** when a session starts in a repo project (appended to the brief, as the project's goal is): the repo and branch, whether you can push (and to `fork`, not `origin`, when you can't), that the default branch is protected, that `_PROJECT.md` and `.duo/` are Duo's and excluded, and that the user shares through Duo's Push unless they ask Claude to.

**Ready-made instructions**, shown before sending, in the project's open session or a new one (as New Session in Task's drafted prompt, DL-112):
- *Ask Claude to Write These:* "Write a commit message and a pull request title and description for the changes in this project (git diff origin/main, plus the 3 uncommitted files)… Don't commit or push. Put them in Duo's Push sheet with: `duo2 repo draft --message "…" --title "…" --body "…"`."
- *Ask Claude to Combine:* "Bringing main into geoff/pricing-copy stopped with a conflict in content/faq.md. Combine both versions keeping what each side meant, then `git add` the file and `git commit --no-edit`. Don't push. Then tell me in two lines what you kept from each side."
- *Ask Claude to Remove It* (GH009): names the file and the rule; don't push.

## 6. duo2 verbs

Every button above has one (DL-71). Board 12.

```
duo2 project new --from-github <link|owner/repo> [--new-branch <name> [--from <base>] | --branch <existing>]
                 [--name] [--goal] [--in <topic>] [--keep-in-git] [--json]
duo2 repo status [<project>] [--json]         branch, base, ahead, behind, changed, pr, access, protected, reachable
duo2 repo check  [<project>|<owner/repo>]     gh present, signed in as, access, protection (reads only)
duo2 repo latest [<project>]                  Get Latest
duo2 repo update [<project>] [--from main]    Bring In Changes from main
duo2 repo push   [<project>] [--message] [--files …] [--fork] --yes
duo2 repo pr     [<project>] [--title] [--body] [--base] [--draft] [--browser] --yes
duo2 repo draft  --message --title --body     fills the open Push sheet
duo2 repo move-to-branch <name> [<project>] --yes
duo2 repo signin                              a shell tab with gh auth login
duo2 repo open   [<project>] [--pr]
```

Anything that publishes needs `--yes` outside the sheet (legacy's rule). Failures exit non-zero with the question's title and body; `--json` failures exit non-zero too (legacy's `--json` exited 0).

## 7. Recommendation, effort, v1 slice

S = a day or less, M = a few days, L = a week or more.

| # | Recommendation | Boards | Effort |
|---|---|---|---|
| R1 | The repo line (A) and file marks; local state and a quiet fetch; the popover | 4, 5 | M |
| R2 | From GitHub in New project: paste a link; the gh picker when signed in; the Found box | 1 | M |
| R3 | The branch: new (default) or existing, option A | 2 | S |
| R4 | A clone per project in Home; the visible exclude checkbox; progress and notice | 3 | S |
| R5 | Push… and Open PR: one sheet; `gh pr create`, or GitHub's compare page without gh | 6, 8 | M |
| R6 | No write access: the fork, said in the sheet (needs gh) | 7 | M |
| R7 | Get Latest and Bring In Changes from main; the conflict question | 9 | S–M |
| R8 | The failures, classified, in Duo's question look, with Details | 10 | M |
| R9 | What Claude is told; the drafted instructions; `duo2 repo draft` | 11 | S |
| R10 | `duo2 repo …` and `project new --from-github` | 12 | S with each step |

**First slice:** R1–R5, R8–R10: see where a repo stands, bring one in on a new branch, push and open a PR with or without gh, plain failures. About two weeks. Then R6 (fork) and R7 (Get Latest). Why the fork can follow: people at a company usually have write access and meet protected branches, which a new branch avoids; the fork serves open source and other teams' repos (Q-123).

**Later:** ENH-37 (GitHub Enterprise and other hosts), ENH-38 (the PR on the project: checks, reviews; a shallow first copy for big repos), ENH-39 (git identity from GitHub; first-run setup of git and gh). Worktrees per project.

**v1 scope.** The build plan's §3a doesn't hold any of this. If Geoff approves, the slice needs a line there with why (CLAUDE.md: "Don't pull later features into v1 without logging why"); the director decides where it sits.

## 8. Questions for Geoff, and his answers (DL-149)

1. **Where the repo state shows** (Q-122): A under the status line (recommended), B in Files, C a toolbar chip. **Geoff: B, the Files block.**
2. **Who pushes** (Q-126): Duo's sheet, Claude writing the words on request (recommended); or Claude does it all. **Geoff: Duo's sheet.**
3. **Fork in the first slice, or after** (Q-123). Recommended after. **Geoff: in v1, and "we should know when they do the initial clone that they will need to fork in the future".** So the From GitHub sheet's Found box says it when the repo is chosen; asked when the fork is made, **Geoff: at the first push** (nothing made on the account until then).
4. **A clone per project, or worktrees** (Q-124). **Geoff: a clone per project, "but want to support worktrees w/in a cloned project in the future".**
5. **`_PROJECT.md` in a repo** (Q-125): the visible checkbox, on, as recommended (not asked separately; agreed with the CX study).
6. **v1 scope** (the director's question): **Geoff: all of it in v1** (R1–R10, Get Latest and conflicts included). Build plan §3a has the line.

## 9. Records

- **Findings:** F-194 (private and missing look alike signed out), F-195 (protection readable by readers; `/protection` 404; rulesets apart), F-196 (`gh` fork and PR behaviours that matter to a GUI), F-197 (git's defaults on a Mac and the push-rejection tokens).
- **Questions:** Q-122 to Q-126.
- **Concerns:** C-53 (a GUI driving git and gh must never block on a prompt or dialog), C-54 (Duo publishing under the user's name: forks, pushes, PRs).
- **Enhancements:** ENH-37, ENH-38, ENH-39.
- **Decision:** DL-149.
