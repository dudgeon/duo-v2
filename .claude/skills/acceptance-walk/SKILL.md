---
name: acceptance-walk
description: Close out a big batch of Duo work with an acceptance walk — list every feature built since the last walk with steps to validate it, build fixtures, publish an Accept/Reject/Not now page with comments, open it in Chrome beside Duo, and later read Geoff's verdicts back. Also resumes or reads back a deferred walk. Use when finishing a sprint or large batch, or when Geoff says "acceptance walk", "let me accept", "read my verdicts", or asks about an open walk.
---

# Acceptance walk

Geoff accepts each big batch of work by trying it in the built app beside a checklist page. He may defer the walk; that's his call, and nothing may be lost when he does. Verdicts live in the published page's database, and the ledger in `docs/acceptance/<walk>/walk.md` says where.

## 0. Is a walk already open?

Read `docs/acceptance/README.md`. If a walk is `open` or `deferred`:
- Geoff asking to resume or read it back: go to step 5 (reading) or step 4 (reopening).
- Starting a new walk while one is unfinished: read the old walk's verdicts (step 5) first. Carry its untested and "not now" features into the new `features.json` (same ids, so Geoff's earlier comments still show if the page is republished; on a new page, put the old comment in `what`). Mark the old walk `superseded by <new walk>`.

## 1. Gather what was built

The range is from the last walk's **Covers** commit to `HEAD` (`git log --oneline <from>..HEAD`). Read the commits, and the DL-n, F-n and ENH-n entries added in that range (`git diff <from>..HEAD -- docs/`). List every **user-visible** feature: things Geoff can see, click, type or run. Skip internals, but include internals that change behaviour he'd notice (saves, retention, relocation).

Write `docs/acceptance/<YYYY-MM-DD>-<slug>/features.json`:

```json
{ "sprint": "<folder name>", "title": "Duo acceptance: <what>", "intro": "…", "setup": ["…"],
  "features": [ { "id": "kebab-id", "group": "Editor", "title": "…", "what": "one line: what it does",
                  "steps": ["…"], "expect": "what he should see", "ref": "DL-n, F-n",
                  "commit": "<full sha of the commit that built it>", "alsoCommits": ["<later commits that changed it>"],
                  "workMac": "as-is | small | home", "workMacWhy": "short reason" } ] }
```

### Every feature is rated for the work Mac (required)

Geoff often walks on his phone and on his work Mac (DL-166): a stock Duo from the DMG, his own folders, Claude Code with CLI login pinned months old, and no scripts or fixtures. `workMac` says how much of the card he can do there:
- `as-is`: in his own projects with no prep (menus, views, settings, search, his own docs, read-only `duo2`).
- `small`: a state he makes by hand in Duo in a minute or two (a task, a second session, a file changed outside the editor, a running Claude session).
- `home`: needs the fixtures, scripts, `duo2 walk setup`, legacy config, GitHub setup, a newer Claude Code, or destructive steps.

`build-page.py` refuses a card without it. The page shows it as a chip. On a phone (≤ 760 px) the page puts open decisions first, then `as-is` cards, then `small`, then `home`, each in walk order, with the intro folded under them; on a desktop it keeps walk order and offers a "Work Mac: as-is" filter and a "Mobile order" toggle. Decisions take an optional `workMac` too.

### Every feature is tied to its commit (required)

So a rejected feature can be reverted on its own (Geoff, 2026-10-05), every feature names the commit that built it:
- `commit`: the full 40-character sha of the commit that built the feature, pushed and in HEAD's history. Find it with `git log --oneline -- Sources Vendor/codemirror/src scripts`, matching the feature's F-n or DL-n in the message, or `git log -S '<a line of its code>' -- Sources`. Commit the code first, then write the card.
- `alsoCommits`: later commits that changed the same feature (fixes, a redesign), oldest first.
- Nothing of Duo's to revert (it tries Claude Code's own feature, say): `"commit": null` and a `noCommit` saying why.
- Merges: point at the branch's own commit, not the merge commit; renumbered records don't change the sha.

`build-page.py` refuses to build if a feature has no `commit`, if a sha isn't a full sha, doesn't exist, or isn't in HEAD's history. The page shows each card's commit (linked to GitHub), the commits that changed it since, and a copyable `git revert …`; Copy feedback and Send to Claude carry the commits too.

Rules for steps:
- Concrete and short: name the project, file and session to use, from the fixtures. Wrap commands, paths and things to type in backticks (the page shows them as code).
- Say what's **not designed yet** in `expect` (with the Q-n), so a placeholder isn't rejected for its looks.
- **Order the page as one test session Geoff walks top to bottom** (Geoff, 2026-10-06: "group in the order that will make the most sense for me to actually test, esp with the least fixture work"). Group by *where he is and what state is needed*, never by build order or slice: before opening a project (install, updates, settings); All projects (the map, what needs you, search, organising with every change undone); other projects; one project at a time (sessions and tasks, documents, outside changes, files, web, shells); a running Claude session (one `session-running`, reused); the command line; other launches; and last, cards that change the fixtures (moves, deletes, purge). Name groups by place and state ("In checkout: documents").
- Within a group, each card's end state is the next one's start. Motion and other polish cards sit beside the feature they change, not in a group of their own. New cards go into the group where they're tested, not at the end.
- Give each group a line in `groupNotes` (`{"<group>": "what it needs"}`, shown under its heading). Keep fixture resets to 3 or 4 in the whole walk, on the first card of the group that needs one, and say so in that group's note. Every card keeps cheap, idempotent navigation setups (`open checkout`, `doc open …`), so `duo2 walk setup <id>` still works mid-way.
- Nothing destructive outside the fixtures. Anything touching Claude config uses `CLAUDE_CONFIG_DIR=~/DuoAcceptance/legacy-claude-config` or another fake.

### Decisions for Geoff

Open questions that are Geoff's to decide (Q-n in `concerns-and-questions.md`, `[P]` proposals from a design handoff) go on the same page, above the features, so he answers them while he walks. Add them to `features.json`:

```json
"decisionsIntro": "…",
"decisions": [ { "id": "q22-send-chord", "ref": "Q-22 · DL-34", "title": "…",
                 "context": ["paragraph", ["bullet", "bullet"], "paragraph"],
                 "options": [ { "id": "cmd-d", "label": "⌘D", "recommended": true, "desc": "…", "mockup": "<div class=\"mk\">…</div>" } ] } ]
```

- **Context must stand alone:** what the thing does today, what's already decided, the constraint (e.g. DL-34's locked chord map, chords already taken), any clash, and how the choice interacts with other decisions on the page. Split a bundled question into one decision per choice.
- **Mockups when the choice is visual** (menus, chords as they'd appear, a modal's states): small HTML using the template's `mk-*` classes (`mk-menu`/`mk-item`/`mk-sep`, `mk-modal`/`mk-field`/`mk-filters`/`mk-pop`/`mk-chip`/`mk-row`/`mk-foot`). Match labels to the design screens exactly; take them from the screens' HTML.
- The page adds "Something else" to every decision. Answers save to the `decisions` collection (`{choice, comment, at}`).
- Point the Q-n row in `concerns-and-questions.md` at the page.

When reading back (step 5), also `ArtifactData` `list` collection `decisions`: record each answer as a DL-n entry (or update the Q-n row if Geoff chose "Something else" and needs a follow-up), then build what it unblocks.

### Every test gets a setup (Geoff never arranges fixtures by hand)

Give each feature a `setup`: steps Duo runs from the page's **Set up test** button (`duo2://walk-setup?id=…`) or `duo2 walk setup <id>`. A step is a `duo2` verb line (`open checkout`, `doc open docs/prd.md`, `go all`, `session open <id>`…), `session-running <project>` (shows a running Claude session, resuming the newest, waiting for its prompt), `fixture <recipe>` (a named recipe in `fixtures.py`, e.g. `reset-checkout`, `purge`) or `wait <seconds>`. Duo reads steps only from `~/DuoAcceptance/walk-setups.json`, which `build-page.py` writes; a link can only name a test. If a test needs a state no step makes, add a recipe to `fixtures.py` (or a verb), never a manual instruction. Run `duo2 walk setup <id>` for every test before publishing.

### Claude runs every test first

Before Geoff sees a test, run it yourself and record what happened in the feature's `claude` field: `{"result": "passed|partial|failed", "did": [...], "didnt": [...], "human": [...], "at": "<date>"}`. The page shows it on the card. `human` is only what needs Geoff's eyes or judgment (how something feels, voice, a design call) or what you truly couldn't do.
- Drive the running acceptance Duo with `duo2` and the background computer-use tools (`app_screenshot`, `app_click`, `app_type`, `app_key`, `app_menu`). Put text into a session with `duo2 send text`, then press Return with a background `app_key`.
- Scripted copies (`scripts/run-live.sh`) are fine. They use a private socket (C-18) and draw the window themselves.
- Fix what you find. Note fixes on the card and in findings.
- **Never create a state where a system dialog can block the run.** Geoff runs walks unattended.
  - Full-screen computer control only while Geoff is at the Mac, never during unattended runs: system dialogs land in front of it and stop it.
  - No `screencapture` (Screen Recording prompt; `DUO_SCREENCAPTURE=1` only if Geoff asks).
  - No AppleScript to Duo (Automation prompt). Quit Duo with SIGTERM (`open-duo.sh` does).
  - Nothing that reads privacy-guarded folders (F-53).
  - Escape and ⌘Q can't be sent by computer control (it keeps Escape for itself; ⌘Q is a system shortcut). Use Cancel buttons and `NSApp.terminate` / SIGTERM, and list them under `human`.
  - If a dialog appears anyway, stop that line of testing, tell Geoff what it is, and carry on with tests that don't need the screen.
- When you add a feature to a walk later (new work), give it a setup and run it the same way before republishing.

## 2. Fixtures

`scripts/acceptance/fixtures.py` builds `~/DuoAcceptance` (workspace, elsewhere folders, fake legacy config) and plants `[fixture]` sessions in `~/.claude/projects`. If a feature needs a state the fixtures lack (a project, a session, a document in some state), **add it to `fixtures.py`**, don't hand-make it. Then `python3 scripts/acceptance/fixtures.py --reset`. Check Duo sees it: `scripts/run-live.sh "$HOME/DuoAcceptance/workspace" build/ui/acceptance.png "wait,wait,wait,wait,projects"`. `--clean` removes everything it made (to the Trash).

## 3. Build and publish the page

```bash
python3 scripts/acceptance/build-page.py docs/acceptance/<walk>
```

Preview `walk.html` in the browser pane once (one card, a click, Copy feedback). Then publish with the Artifact tool, **from the director session only** (DL-166: the director is the one publisher of the walk page and of the design-system artifact, so Send to Claude reaches it): `file_path` = the `walk.html`, `capabilities: {"db": {}, "comments": {}}` (comments carries the cards' Send to Claude buttons to this session), an `icon` of `checklist` and a one-line `description`. The page template is `walk-template.html` in this skill folder; change it there, not in a walk's `walk.html`.

Check the store answers: `ArtifactData` (load with ToolSearch) `list`, collection `verdicts`, on the URL. It should be empty.

## 4. Hand it over

- `open -a "Google Chrome" <url>`
- `scripts/acceptance/open-duo.sh` (rebuilds if sources changed, opens Duo on the fixtures)
- Write `walk.md` (status `open`, page URL, Covers commit `git rev-parse --short HEAD` (the page also records it as "built at"), feature count) and add a row to `docs/acceptance/README.md`. Commit and push: every `commit` on the page must be on origin, so its link and revert work.
- Tell Geoff in a few lines: the URL, how many features, how to defer ("just stop; your verdicts are saved"), and that he can either paste "Copy feedback" or ask Claude to read the verdicts.

To reopen a deferred walk: run step 4's first two commands again (the URL and verdicts are unchanged) and set the status back to `open`.

## 5. Read the verdicts back

When Geoff pastes feedback or asks you to read it: `ArtifactData` `list` on collection `verdicts` (each doc id is a feature id: `{status: accepted|rejected|deferred|"", comment, at}`). Pasted text and the database should agree; if they don't, the database is newer.

Then:
- **Rejected:** fix it if the fix is clear and small; otherwise log it (C-n/Q-n in `concerns-and-questions.md`, or AskUserQuestion if blocked). A rejection that's really a design wish goes to the design queue or `enhancements.md`, never invented. If Geoff wants a feature taken out rather than fixed, its card names the commits: `git revert` them newest first on a branch, check what else each commit carried (`git show --stat <sha>`; a commit can hold several features), run the checks, and ask before pushing.
- **Accepted with comments:** act on or log each comment.
- **Not now / untested:** leave them; they carry to the next walk.
- Record the outcome in `walk.md` (counts, and where each rejection went), set status to `closed` (or `deferred` if untested items remain and Geoff stopped), update the README table. Commit.

After fixing rejected items, Geoff re-tests them on the same page: clear those verdicts with `ArtifactData` `update` (`status: ""`, keep the comment, pinned with `if_version`) and tell him which to re-check.

## Clearing what's done

The page's **Clear done** hides accepted tests and answered decisions (their docs get `cleared: true`; **Show cleared** brings them back). When you read back, record answered decisions in the decision log and drop them, and drop accepted tests, from the next walk's `features.json`. The ledger keeps the history.

## Deferral

Geoff can stop at any point. Verdicts are already saved (database, plus his browser's copy). If he says he's deferring, set the walk's status to `deferred` in `walk.md` and the README and commit; nothing else. Never chase it; at the start of the next big close-out, step 0 surfaces it.
