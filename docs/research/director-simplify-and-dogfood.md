# Director: simplification plan and dogfood review

*Shared state between the duo-director build session (it owns `## Simplification plan`) and the dogfood reviewer (it owns `## Dogfood review`), set up by the director on 2026-10-15 so the review judges the plan, not code about to go. Both write `## Open questions / Geoff's answers`. The build session commits this file.*

## Simplification plan

Geoff, 2026-10-15: "consider that you may be overcomplicating things and explore options that achieve the same functional goals reliably with less complexity." Each part of the skill, the verbs and DL-199's carrying gets one of keep, cut or replace. Status is planned, doing or done (with its commit). Branch `feature/duo-director`.

### Done

| Part | Verdict | What replaces it | Status |
|---|---|---|---|
| The user's yes for `--adopt` and `--handed-back`: a keystroke in the director's own tab, found by `$CLAUDE_PID`, after an "ask" record with a 30-minute expiry | **replace** | Duo asks the user itself, with the confirm sheet merges already use (`AppModel.confirm`); the verb waits up to 600 s. Every question comes before anything is written. | done, ca34c2f |
| `ClientCaps.pid`, the `asked` record, `SubmitGuard.handedBack`, the in-memory "typed since the director's last message" | **cut** | (gone with the above) | done, ca34c2f |
| Background workers: a minted `--session-id` with a name fallback | **replace** | `claude --bg` ignores `--session-id` (measured, F-318). The worker is pending under a name unique to the start (`-n <task>-<6 hex>`), and Duo links it at the refresh when a session with that name appears. No link step, no `--adopt`. A pending worker frees its slot after 30 min. | done, ca34c2f |
| Which project: Duo's folder for the cwd, falling back to the project on screen, then Home | **replace** | `DirectorPlace.resolve(from:)`: the nearest `PROJECT.md` at or above (never above Home, else the folder itself) and the nearest `HOME.md`. The same rule with Duo closed; the app prefers the Duo folder it names; an unknown folder is refused. | done, ca34c2f |
| Rule sources: "(none yet)" for both a missing file and a missing section | **replace** | Says "no PROJECT.md yet: offer Make a Project" or "no ## Director section yet". | done, ca34c2f |
| Fixed name, `.duo/director.json`, stand-down, roles by session id, `start --take-over` | keep | | done, 24f06cf |
| Workers = sessions the director started or the user let it adopt (registry), never a note's linked sessions | keep | | done, 24f06cf |
| DL-199 ladder: SendMessage, background resume, headless turn, Duo's guarded Enter, resume in Duo, queue | keep | | done |
| Guarded Enter: directed task, idle, empty prompt, 2-minute quiet window after a keystroke, echo seen before Enter | keep | (the keystroke monitor stays for the quiet window only, once the next item lands) | done |
| `watch` (polls status, survives Duo restarts), `guide`, `retire`, the log and its metrics | keep | | done |
| `ClientCaps` probe (beacon, settings, Monitor's flag) | keep | | done |
| Harness: stand-in claude + profiles (tier 1), plugin-eval scenarios (tier 2) | keep | | done |
| Skill core text, Director sections (DL-207), organising work (DL-208), Done to log.md (DL-209), inboxes (DL-210), the Never section | keep | | done |

### Planned (from the dogfood reviewer's needs, agreed)

| Part | Verdict | What replaces it | Status |
|---|---|---|---|
| The pause (DL-200) triggered by keystrokes in Duo | **replace** | A user turn in the worker's transcript since the director's last send that isn't one of the director's own messages (Duo's sends are logged by text; SendMessage arrives as a cross-session message). It sees Remote Control and background workers, which keystrokes can't, ignores permission answers by nature, and drops the per-keystroke hook and its cache. Reviewer item e. | planned |
| The cap counts every recorded worker on an unfinished task, stopped ones too | **replace** | Count running workers plus pending ones. A worker stopped after its merge, waiting days for sign-off, frees its slot. Reviewer item 4. | planned |
| `start` needs Duo running | **replace** | With Duo closed, `duo2 director start <task> --background` records the pending worker in `director.json` itself (DuoControl only) and prints the command; Duo links it at its next refresh. The note is written by hand, as the skill already says. Reviewer item 5. | planned |
| `DirectorPlace` takes a git work tree as its own project | **replace** | A folder whose `.git` is a file naming `<main>/.git/worktrees/<x>` resolves to the main checkout. Reviewer item c. | planned |
| Offline "No Home" when Duo has a Home configured elsewhere | **replace** | With Duo closed, read Duo's configured Home from its state file before saying there's none. Reviewer item d. | planned |
| The worker's brief names `tasks/<slug>.md` relative to the project | **replace** | The note's absolute path, plus "if you can't write the note, put your Progress lines in your report". Reviewer item a. | planned |
| The verbatim Request through a shell argument | keep, document | `duo2` already reads an argument from stdin (`--request --stdin`); the skill says to use it for anything long or quoted. Reviewer item b. | planned |

## Dogfood review

*(the reviewer's section)*

## Open questions / Geoff's answers

1. **Standing yes** (the reviewer puts this one to Geoff): Never 3 and §6 say a push, delete or publish waits for the user "whatever the rules say", but Geoff's standing OK covers pushing main after a checked merge and sweeping merged work trees. Proposal: a yes counts when the user gave it for that action, in their own words naming it or as a standing line in a Director section (it can be time-boxed); a worker's ask or the director's own inference never does.
2. **Duo's two new questions** (the build session's): `--adopt` and `--handed-back` now show Duo's existing confirm sheet with new wording ("Let director-x take this on?", "Hand “…” back to director-x?"). No new surface was drawn. Is the existing sheet fine, or should these be designed? Not yet asked; the director may bundle it with the install-question re-ask.
