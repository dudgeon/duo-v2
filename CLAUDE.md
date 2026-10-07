# Duo v2 — notes for Claude

Read `CONTRIBUTING.md` first for build commands and layout (`README.md` is for people using Duo). Releases are on GitHub (`gh release list`); the newest tag is what Geoff runs.

## Precedence

1. `docs/design/decisions.md` (DL-n) wins over every other doc.
2. The approved design screens are the literal target for anything visible (DL-26), unless a decision changed them. They live in each handoff's `screens/` (`docs/design/README.md` lists the handoffs and their status). Where a handoff README's prose and its screen disagree about looks, the screen wins.
3. The design system, `docs/design/system/`, restates the current design in one place (Claude Design reads it as https://claude.ai/artifact/QMapKeLYS3TVV36QKEc6MH). Where it disagrees with 1 or 2, they win.
4. Then the handoff READMEs (§n), `docs/plan/build-plan.md`, `docs/design/legacy-requirements.md` (LR-n), `docs/design/stack-recommendation.md`.

## Rules

- **Build to the screens, then prove it.** Every visible change ends with a capture compared with its target (`scripts/check-ui.sh <states>` for fixture states, `docs/design/build-handoff/tools/compare.sh <screen> <png>` for live captures), looked at region by region; measure with `scripts/pixels.py`. Captures draw web views (the editor, HTML viewer, browser tabs) from WebKit's own snapshot, even when the test window is covered (F-120); for pixel-exact editor work, also check in a browser page at the pane's width. Keep the last comparison image for Geoff.
- **Never invent a design.** Anything not drawn gets a stand-in and a question in `docs/plan/concerns-and-questions.md`. New surfaces are designed in this session on a Design artifact canvas with the Duo design system, every mark a [P]; Geoff approves; then they're exported to `docs/design/<slice>-handoff/` and built. Don't build the quick-reply buttons (DL-29).
- **Stay Xcode-free** (DL-30, ADR-0001): no `@State`, `@Entry`, `@FocusState`, `#Preview` or other SwiftUI macros; no XCTest or Swift Testing. App state is `@Observable` classes. Logic checks go in `Sources/DuoChecks`.
- **Tokens are generated.** Edit `docs/design/build-handoff/tokens.json`, run `python3 scripts/gen-tokens.py` and `python3 scripts/gen-design-system.py`; never edit `Tokens.swift` or `docs/design/system/tokens.json` by hand, never use raw hex in views. When a surface's status changes, update `docs/design/system/surfaces.md` and the component's README, and republish them to the design system artifact.
- **Don't edit a handoff's `screens/`.** They are a snapshot of the design canvas.
- **Duo never shows a system alert.** Questions go through `SheetCenter` (`Shell/DuoQuestion.swift`) or a Duo sheet; an alert can block a scripted run or `duo2` (F-54). Scripted runs auto-answer with `DUO_AUTOCONFIRM=1`.
- **Every UI action has a `duo2` verb** (DL-71): a new button or menu item names one in `Sources/DuoControl/Actions.swift` (or is listed in `Parity.uiOnly` with why); DuoChecks scans for gaps. Regenerate `docs/cli/duo2.md` with `build/Duo.app/Contents/Helpers/duo2 help --markdown`.
- **Record as you go.** Facts learned while building go in `docs/plan/findings.md` (F-n); risks and questions in `docs/plan/concerns-and-questions.md` (C-n, Q-n); Geoff's decisions in `decisions.md`; wanted-but-unscheduled ideas in `docs/plan/enhancements.md` (ENH-n).
- **Record numbers are shared across sessions.** Several sessions work at once and have taken the same number three times. Pull before you take a number, take the next one after the highest anywhere (`git fetch --all`, then check the files on `main` and on open branches), and commit the record with its code. When you merge a branch that reused a number, renumber the branch's records and every reference to them (its code comments too), and say so in your finding.
- Never use `claude -c` or the resume picker programmatically; always mint `--session-id` (DL-14).
- **Close out big batches with an acceptance walk** (`.claude/skills/acceptance-walk/SKILL.md`): every card names the commit that built it, so a rejected feature can be reverted; Geoff may defer. Open walks are listed in `docs/acceptance/README.md`, so check there first.
- **Releases** use the `release` skill (`scripts/release.sh <version> --notes …`): it builds the committed HEAD, signs, notarizes and publishes. Before a release, merge finished work trees (`git worktree list`).
- **v1 scope is in the build plan §3a.** Don't pull later features into v1 without logging why.

## Director

One session, `*DUO DIRECTOR*`, runs the other sessions as their engineering manager (Geoff is the PM): it delegates work to new sessions (background Claude sessions with Remote Control, outside Duo unless Geoff says otherwise), reviews and merges their branches, keeps records consistent and cuts releases Geoff approves. Its job description is `.claude/skills/director/SKILL.md`. A director that resumes (after compaction or a restart) starts there. Build sessions report to it by `SendMessage` to `DUO DIRECTOR` when their work is committed.

## Branches

`main` is the trunk: branch from it, merge back to it, release from it. Work trees under `.claude/worktrees/` are other sessions' branches; merge them when their work is finished, renumbering records as above.

## Running the app from a Claude session

`scripts/check-ui.sh` and `build/Duo.app/Contents/MacOS/Duo --state … --capture …` open a window briefly and quit. Captures need no permissions; `--capture-window` draws the window's frame view (terminals then show as blank panes: their text is in the layer, F-25). With the screen locked, computer-use can't capture either; add `dump` to `--then` and pass `open --stderr <file>` to read each terminal's text. `--workspace <root>` runs on real folders and starts real Claude sessions (Home starts one on launch); quit with SIGTERM to that instance (`kill -TERM <pid>`; Duo quits as with ⌘Q: terminals end, the document saves), never AppleScript (it can raise an Automation prompt) and never `kill -9`. Captures never use screencapture(1) unless `DUO_SCREENCAPTURE=1` (Screen Recording prompts block unattended runs, F-54). Prefer `scripts/run-live.sh <ws> <png> <actions> [stderr]`, which never hangs (F-26); `type:<text>` and `enter` drive the visible terminal; set `DUO_MODEL=claude-haiku-4-5-20251001` for test turns (DL-33). Test sandbox behaviour with `scripts/check-sandbox.sh` (Seatbelt, no tokens) before spending a Claude turn on it.

- **A Duo whose support folder isn't the real one is isolated** (F-113): it asks no install question, never takes focus, and writes nothing outside its folders unless `DUO_INSTALL_ROOT` is set. Sessions started before F-113 still inherit the real `DUO_SUPPORT_DIR`: launch test instances with `env -u DUO_SUPPORT_DIR` until Geoff's Duo runs F-113's build.
- **Never touch Geoff's own Duo or data from a script.** A scripted run gets its own `DUO_SUPPORT_DIR` (a short path: the control socket's path must stay under 104 characters, so not deep in a scratchpad) and, for anything that shows sessions, a scratch `CLAUDE_CONFIG_DIR` (copy the fixtures' buckets with `cp -Rp`). Point `duo2` at that instance with **both** `DUO_SOCKET` and `DUO_TOKEN` from its `endpoint.json`; with either missing, `duo2` quietly reaches Geoff's running Duo. Never copy credentials. Back up `~/DuoAcceptance` before a test that changes it and check it against the backup after.
- **Screenshots for docs or the design system** use sample data only: the fixtures (`~/DuoAcceptance`, `scripts/acceptance/fixtures.py`) with a scratch config and support folder as above.
- Harness actions for states that need a click are in `Sources/DuoKit/Debug/FixtureHarness.swift` (`sheet-move:`, `sheet-new:`, `merge:`, `user-type:` + `disk-write:` for a conflict, `ask-legacy`, `render-settings:<png>` for the Settings window, …).
