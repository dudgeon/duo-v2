# Duo: GitHub in a project — design handoff

Status: approved by Geoff, 2026-10-07 (DL-149), by buttons in two rounds. Not built: the build is a separate job. In v1 (build plan §3a).

The research and the reasoning are in `docs/research/github-primitives.md`; the study, with every option drawn, is `docs/design/github-study/` and the canvas https://claude.ai/artifact/76ZGzopVk1eLx9d2pnWA2i. The screens here are copies of the study's boards. Where a board draws options, build only the one named below.

## Targets

| Screen | Build | Not chosen on the board |
|---|---|---|
| `01-new-from-github` | From GitHub in the CX study's New project sheet (DL-147 owns the sheet, segment and its Name, Goal, In and Will write rows): Repository (paste a link, or Choose… from gh), the Found box, Branch, the two checkboxes. **The read-only Found box** (top right): known when the repo is copied; the fork is made at the first push. | — |
| `02-branch` | **A**: two radio choices, a new branch (default `<login>/<slug>` from the default branch) or one that's there (the popup) | B, one combined field |
| `03-landing` | **A clone per project** inside Home; progress in the sheet; the done notice naming `.git/info/exclude` | One clone + worktrees; a hidden bare repo |
| `04-status` | **B**: the branch at the right of the Files header, one fact and at most one button under it, `changed` / `new` / `kept out of git` marks in the tree | A (under the status line), C (a toolbar chip) |
| `05-states` | All twelve states, in B, with their words and buttons; the most pressing wins | — |
| `06-push-pr` | The Push sheet with write access; the done notice | — |
| `07-fork` | **A**: the sheet says it first; **B** only when access couldn't be known ahead and GitHub refuses with 403 | — |
| `08-no-gh` | The sheet without gh; the PR on GitHub's compare page | — |
| `09-get-latest` | The repo state's menu; the conflict question | — |
| `10-failures` | Every failure's title, body and buttons, in DuoQuestion's look, with git's output behind Details | — |
| `11-duo-and-claude` | What Claude is told (appended to the brief); the three drafted instructions, shown before sending | — |
| `12-duo2` | The `duo2 repo` verbs and `project new --from-github` (DL-71) | — |

## Behaviour a picture can't show

- **Never a token.** Duo uses the user's `gh auth` or git's credential helper; sign-in is `gh auth login --web --git-protocol https` then `gh auth setup-git` in a Duo shell tab. `gh` and `git` are found by explicit path (legacy BUG-136); `xcode-select -p` is checked before `/usr/bin/git` runs, so macOS's install dialog never appears.
- **Never block, never alert** (C-53, F-54): every call with `GIT_TERMINAL_PROMPT=0`, `GH_PROMPT_DISABLED=1`, `GH_NO_UPDATE_NOTIFIER=1` and a time limit; output parsed rather than exit codes trusted (F-196).
- **Access and protection** are read when the repo is chosen and again before a push: `gh repo view --json viewerPermission,visibility,defaultBranchRef`, `gh api repos/o/r/branches/<b>` (`protected`) and its rulesets (F-195). Without gh, Duo can't know ahead and says so.
- **Fork** only when the probe says READ or TRIAGE, never because it failed; `gh repo fork o/r --clone=false --remote --remote-name fork`; push to `fork`; `gh pr create --repo o/r --head <login>:<branch>`. An existing fork is reused.
- **Publishing** (push, PR, fork) only from a confirmed sheet; `duo2` needs `--yes` (C-54). Never a force push; never a bypass of secret scanning.
- **The repo state stays current** from `git status --porcelain=v2 --branch` on file events and a quiet `git fetch` every 5 minutes while the project is open; the PR from `gh pr view --json number,state`.
- **Get Latest** merges (`--ff-only`, else `--no-edit`, both `--autostash`), never rebases, never discards; Put Back is `git merge --abort`. Probes that lead to a change fail closed.
- User values are arguments, never flags: `--` before URLs and paths, `--opt=value`, a leading `-` refused.
- Copy that isn't drawn (the Command Line Tools missing): a stand-in in DuoQuestion's look and a question in `concerns-and-questions.md`.

## Owned elsewhere

The New project sheet, `_PROJECT.md` and the notice pattern belong to the project & task CX study (DL-147). Worktrees inside a cloned project come later (DL-149).
