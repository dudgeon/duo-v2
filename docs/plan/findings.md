# Duo v2 — Build findings

What building and testing taught us, in order. Each finding says what was observed, how, and what it changed. Facts here are verified on this machine unless marked otherwise. Open questions and risks go in `concerns-and-questions.md`; decisions go in `../design/decisions.md`.

Machine: macOS 27.0 (26A428), Apple silicon, Command Line Tools only (Swift 6.4, SDK MacOSX27.0), Chrome 154.

---

## F-1 · Chrome 154 never exits after a headless screenshot or DOM dump (2026-10-03)

- **Observed:** `render-references.sh` hung on its first call. `--screenshot` and `--dump-dom` both write their output, then the process stays alive indefinitely, with or without `--virtual-time-budget` or `--disable-gpu`.
- **Changed:** `docs/design/build-handoff/tools/lib.sh` `chrome_run` now runs Chrome in the background and stops it once the screenshot file stops growing or the dumped DOM reaches `</html>` (bounded by `CHROME_TIMEOUT`, default 60 s). All nine references render in about 14 s.

## F-2 · The Command Line Tools can build the whole app, minus Xcode's macro plugins (2026-10-03)

- **Observed:** the CLT SDK includes SwiftUI, AppKit, WebKit and Observation, and `swift build` produces a working SwiftUI app. But `@State` is a macro in this SDK and fails with "plugin for module 'SwiftUIMacros' not found". Swift Testing's `@Test` fails the same way ("TestingMacros"), and XCTest isn't present. `@Observable` works (its macros ship with the toolchain). There is no `actool`, so no asset catalogs.
- **Changed:** DL-30 (Xcode-free as policy); ADR-0001. App-level state is an `@Observable` class held by `let`. Checks run as an executable (`swift run DuoChecks`). Colours are generated Swift from `tokens.json` (`scripts/gen-tokens.py`).
- **Watch:** views must avoid SwiftUI macros (`@State`, `@Entry`, `#Preview`, `@Previewable`). Use `@Observable` models, `@Environment`, and plain `let`/`var`.

## F-3 · Window rendering is in the display's colour space unless pinned (2026-10-03)

- **Observed:** captured token colours came back one unit off in one channel (`#15181C` for `#15171B`) after the capture converted from the display's colour space to sRGB.
- **Changed:** fixture mode sets `window.colorSpace = .sRGB`. Captured pixels now equal token values exactly.

## F-4 · The system's compact toolbar is 40 pt on macOS 27, not 38 (2026-10-03)

- **Observed:** with `.unifiedCompact(showsTitle: false)`, the window is 902 pt tall when the content area below the toolbar is 862 pt.
- **Changed:** nothing in the targets. Per handoff §0.4 the system wins; fixture mode sizes the content area to exactly 1440×862 so `compare.sh --content-only` lines up.

## F-5 · Pane edges match the targets to the point (2026-10-03)

- **Observed:** with a custom `NSSplitView` (1 pt token-coloured dividers; a pane's border counted inside its width, as the targets draw it), sampling row y = 500 gives All projects 0–339 `console`, 339–340 `consoleRule`, 340–1100 `pane`, 1100–1101 `rule`, 1101–1440 `pane`; Inside a project 0–299, 299–300 `rule`, 300–980 `console`, 980–981 `rule`, 981–1440. Identical to the targets.
- **How:** `scripts/pixels.py` (dependency-free PNG sampler) against `screens/png/*@2x.png`.

## F-6 · Toolbar items need a flexible spacer to reach the trailing edge (2026-10-03)

- **Observed:** a `.primaryAction` item sat directly after the `.navigation` items, not at the trailing edge as the target's `margin-left: auto` places it.
- **Changed:** `ToolbarSpacer(.flexible)` before the Jump field. Toolbar items also use `.sharedBackgroundVisibility(.hidden)` so macOS 27 doesn't put each in a glass capsule.

## F-7 · Whole-window capture needs Screen Recording (2026-10-03)

- **Observed:** `screencapture -l <window>` fails without the Screen Recording permission for the launching app.
- **Changed:** `--capture-window` falls back to drawing the window's frame view, which shows the toolbar's contents (the part §0.4 says to match) though not always the system material. The main comparison path is content-only and needs no permission.

## F-8 · AppKit eats valueless command-line flags; a stray path stops the window appearing (2026-10-03)

- **Observed:** `Duo --state overview --collapse-left --capture out.png` never showed a window. AppKit reads arguments as `-key value` pairs, so `--collapse-left` took `--capture` as its value, leaving `out.png` stranded. AppKit treated the stray path as a file to open and the SwiftUI app sat waiting on that request, idle in its run loop with no window.
- **Changed:** every Duo flag takes a value (`--left collapsed`); `LaunchOptions` documents the rule. `scripts/check-ui.sh` runs each capture under a 30 s watchdog so a hang fails loudly.

## F-9 · A collapsed NSSplitView pane keeps its old frame (2026-10-03)

- **Observed:** collapsing a pane before the split view had a size left the panes out of order (AppKit logged "inconsistent state"). After collapsing, the hidden subview still reports its old frame, so finding a divider by comparing frames picked the wrong one and painted a stray 1 pt rule at the window edge.
- **Changed:** collapse requests made before first layout are deferred until after it; divider positions are computed from visible widths; a divider beside a collapsed pane is painted as the open neighbour. Verified: collapsed All projects is `pane` 0–1100 then `rule` 1100–1101; collapsed project is `console` 0–980 then `rule` 980–981.

## F-10 · The targets are CSS content-box: borders add to heights (2026-10-03)

- **Observed:** a 1 pt offset everywhere below the toolbar. In the targets, elements without `box-sizing: border-box` draw their border outside their stated height: the toolbar is 38 + 1 = 39 pt, the Home header 36 + 1, Home tabs 32 + 1, the map footer 34 + 1, the `+ New project` tile 38 + 2. Only the panes (explicitly border-box) have borders inside their width.
- **Changed:** the content area starts at 39 pt. Fixture mode sizes it to 1440×861, and the handoff's `compare.sh --content-only` now crops at 39, not 38. Strip and tile heights are content heights with their rules added. Card padding is border plus padding (`Bordered`).

## F-11 · SwiftUI line height: use `.lineHeight(.exact)`, then shift down by half the leading (2026-10-03)

- **Observed:** extra leading computed from AppKit font metrics (`lineSpacing` plus padding) made each line about 0.8 pt taller than the targets' CSS `line-height`, compounding down every card. With `.lineHeight(.exact(points:))` the line boxes match exactly, but CoreText puts all the extra leading below the glyphs while CSS splits it, so text sat high: 2 pt at 13/20 and mono 12/19, 1 pt at 11/16.
- **Changed:** `duoText` uses `.lineHeight(.exact(points: lineHeight))` plus `.offset(y: ⌊extraLeading / 2⌋)`. Ink boxes for section labels, card names, tile rows, buttons and console text now match the targets to 0 pt vertically (`scripts/ink.py`).

## F-12 · The reference PNGs draw mono text in Menlo, not SF Mono (2026-10-03; corrected)

- **Observed:** mono strings in the build are about 2.7% wider than the targets. First read as narrower spaces in Chrome; measuring a space-free path settled it. The target's `~/work/payments/checkout-redesign` (mono 11) is 217.5 pt wide: Menlo gives 218.5, SF Mono (`monospacedSystemFont`, `.AppleSystemUIFontMonospaced`) gives 224.4. The targets' stack is `ui-monospace, 'SF Mono', SFMono-Regular, Menlo, monospace`. Headless Chrome doesn't support `ui-monospace`, and SF Mono isn't installed under the other two names (it ships as the system font `SFNSMono`), so Chrome fell back to Menlo.
- **Changed:** nothing in the build. Handoff §4.2 and Geoff ("system faces") specify SF Mono, so the build keeps it; mono strings run a little wider than the references, and tabs to the right of a long mono label start a little later. Logged as Q-14 in case Geoff's canvas review showed Menlo and he prefers it.

## F-13 · SwiftUI avoids one-word last lines; CSS doesn't (2026-10-03)

- **Observed:** the focused tile's hint wrapped as "Enter" / "to open" in the build and "Enter to" / "open" in the target. SwiftUI's text layout pulls a word down to avoid an orphan, and there's no SwiftUI control for it.
- **Changed:** the hint uses a non-breaking space ("Enter to"). Any wrapped text ending in a single word can differ the same way; check wrapped strings in each comparison.

## F-14 · Tools for reading comparisons region by region (2026-10-03)

- `scripts/crop.py <state> X Y W H`: one region, TARGET | BUILD | DIFFERENCE, at 2x. The most useful view.
- `scripts/ink.py <state> X Y W H [--light]`: where the ink is in a region, build versus target, as deltas. Measures text placement.
- `scripts/edges.py <state> col X | row Y`: colour changes along a line, side by side. Good for borders; noisy through text and dashes.
- Also: a flexbox-style `FlexShrinkRow` layout reproduces CSS flex-shrink where HStack's distribution differs (flow-zoom-1).

## F-15 · The system popover centres on its anchor; captures composite it (2026-10-03)

- **Observed:** the peek, a SwiftUI `.popover` from the toolbar chip, is a separate `_NSPopoverWindow`, so content captures didn't include it. Drawing its frame view works (the glass background renders as plain `pane`), but into a fresh standard bitmap: the sRGB-converted capture bitmap can't take a drawing context, so the first attempt silently drew nothing. The system centres the popover on the chip; the target drew its arrow near the popover's left edge, about 150 pt further right.
- **Changed:** `WindowCapture` composites visible popover windows at their on-screen position. The placement difference is accepted under handoff §0.4 (system popover: match width, contents and anchor); the anchor matches.

## F-16 · Scripted navigation lands exactly on the designed states (2026-10-03)

- **Observed:** `--then` runs actions after launch (open, peek, down, jump, home, zoom-out, focus-tile). Starting from `overview`, the captures after focus-tile, open checkout-redesign, and open + peek are pixel-identical (0 differing pixels, `scripts/samepng.py`) to the `flow-zoom-1`, `project` and `flow-zoom-3` captures made from fixture states. Jump from the peek, then zoom out, selects the session last visited in both the map and the action column (flow-zoom-4's behaviour).
- **How:** 15 navigation checks in `DuoChecks` (29 in total) plus the scripted captures.

## F-17 · Spike S1: SwiftTerm runs Claude Code's TUI; automated half passes (2026-10-03)

Branch `spike/s1-swiftterm`, `Spikes/S1TermSpike`. SwiftTerm `main` at `6a955b0` (2.0 line), `claude` 2.1.288, `TERM=xterm-256color`, `COLORTERM=truecolor`, no `TERM_PROGRAM`.

| Check | Result |
|---|---|
| P1 Builds as a SwiftPM dependency with the Command Line Tools only | **Pass.** Fetches and compiles (with `swift-png`, `h`, `swift-argument-parser` as transitive dependencies). |
| P2 The TUI renders | **Pass on content.** Claude Code's folder-trust dialog appears laid out at 100×32: box rule, wrapped prose, `❯` marker, footer. Verified through SwiftTerm's text (`selectAll` + `getSelection`); pixels not yet seen (see below). |
| P3 Resize while running | **Pass.** 100×32 → 60×20: SwiftTerm reports the new grid, Claude redraws at 60 columns, no crash. |
| P4 Idle CPU | **Pass.** Host app 0.0% CPU, 77 MB RSS with one terminal; `claude` 0.0–0.6% CPU, 192 MB. |
| P5 Hidden view keeps the process | **Pass.** Hidden for half the run, process alive, screen intact when shown. |
| P6 Environment scrub | **Pass, and necessary.** Launched from a Claude session, the parent passes about 27 `CLAUDE*` variables, including `CLAUDE_CODE_SESSION_ID` and a messaging socket and token. Dropping `CLAUDECODE` and every `CLAUDE_*` except `CLAUDE_CONFIG_DIR` leaves the child with none. |

Not yet done, and why:
- **Pixels.** SwiftTerm draws through a frame driver into its layer; `cacheDisplay`, `CALayer.render(in:)` and calling `draw(_:)` all produce a fully transparent image. Seeing terminal pixels needs `screencapture` with the Screen Recording permission, or a person. Terminal content is exempt from comparison (handoff §0.4), so the comparison loop is unaffected; Duo's own captures will show terminals as blank.
- **The interactive half of S1:** typing, Shift+Enter, mouse selection and copy, a permission prompt, AskUserQuestion, `/tui fullscreen`, and `TERM_PROGRAM` variants for the kitty keyboard protocol. These need someone at the keyboard, and answering prompts makes model calls.
- **S2 (six streaming sessions):** needs six sessions producing output, which costs tokens.

## F-18 · Spikes S1 (interactive) and S2 (six streaming sessions) pass (2026-10-03)

Same setup as F-17, using Haiku (DL-33). Input is sent by the spike's `--keys` (a harness simulating a person; LR-15 governs Duo, not the harness). Sessions ran in throwaway folders under `.build/s2/` in this repo.

**S1, interactive half: pass.**
- **Folder trust is per folder and not inherited**: a subfolder of a trusted repo still gets Claude's trust dialog. Down + Enter accepts it. Duo's create-project and first-session flows will meet this dialog in every new folder.
- **The whole TUI renders**: the welcome banner (block-character logo, model and plan line), notices, the input box with rules, the mode line ("⏸ manual mode on · ? for shortcuts").
- **Streaming**: an 80-line answer streams and scrolls correctly.
- **AskUserQuestion** renders as Claude Code's own picker (☐ header, `❯ 1. Yes` with descriptions, "Type something.", "Chat about this", key hints).
- **Tool use and permission**: "Create hello.txt" shows `⏺ Write(hello.txt)` and its result; Enter accepted, and the file exists on disk.
- **Shift+Enter** sent as `ESC CR` gives a two-line input (`first line` / `second line`) without submitting, and Claude shows its "ctrl+g to edit in Vim" hint. LR-16's one remap works.

**S2: pass.** Six terminals in one window, five hidden, each running `claude --model haiku` on a 1,500-word story:

| | Peak | Typical while streaming | After streams end |
|---|---|---|---|
| Host app CPU (one core = 100%) | 11.3% | 3–8% | 0.1–0.6% |
| Host app memory | 100 MB | 100 MB | 91 MB |
| Six `claude` processes, CPU (sum) | 177% (startup) | 30–40% | 8–12% |
| Six `claude` processes, memory (sum) | 2.4 GB | 2.1–2.4 GB | 2.1 GB |

The SwiftTerm risk behind C-2 (75–82% of a core on 1.x) doesn't reproduce on the 2.0 line: hidden terminals cost almost nothing, and the host stays near the plan's 15% bar at its worst moment. The `claude` processes dominate memory (about 350 MB each), as the stack research predicted; that cost is Claude Code's under any host.

**Side effects to clean up later:** the test sessions exist in `~/.claude/projects` under `.build/s2*` paths, and their folders are marked trusted in `~/.claude.json`. Harmless; `claude purge` on those paths removes them.

## F-19 · Once the bundle is opened with `open`, executing its binary directly may show no window (2026-10-03)

- **Observed:** after launching `build/Duo.app` once with `open -n`, every direct `build/Duo.app/Contents/MacOS/Duo …` launch sat idle in its run loop with no window (the F-8 symptom with valid flags), and kept doing so for the same bundle. `open -n … --args …` launches of the same build captured normally. Not fully explained; LaunchServices registration is the likely trigger.
- **Changed:** `scripts/check-ui.sh` launches through `open -W -n --stderr <log> … --args …`. Run Duo through `open` everywhere scripted.

## F-20 · SwiftTerm terminals attached to a slot need an explicit repaint (2026-10-03)

- **Observed:** a terminal created when its pane becomes visible (the console after zooming in) showed only a cursor while its buffer held Claude Code's full welcome screen (confirmed by dumping its text). SwiftTerm's Core Graphics renderer draws from a snapshot; `needsDisplay` alone repaints the old one, and the internal invalidation runs only on resize or selection changes.
- **Changed:** `TerminalSlot` calls `GuardedTerminalView.repaint()` (select-all then select-none, which invalidates without resizing the PTY) when it attaches a view. Verified on screen through computer-use.

## F-21 · `onTapGesture` isn't reachable through accessibility (2026-10-03)

- **Observed:** computer-use's accessibility press on the console tabs did nothing; it worked on the project tiles, which had `accessibilityAction`. VoiceOver and Full Keyboard Access have the same gap (handoff §10 requires every action without a pointer).
- **Changed:** `onActivate { }` pairs the tap with a default accessibility action and the button trait; every tappable row, card, tab and file uses it. Home's session tabs became switchable at the same time.

## F-22 · Phase D: real Claude Code sessions in Duo's panes (2026-10-03)

Verified with `--terminals demo` (real `claude` sessions in scratch folders under `.build/demo`) and computer-use screenshots (`docs/plan/review/phase-d/`):
- The Home pane runs Claude Code at the design's "thin" width (about 42 columns); the console runs it at about 87. Background and foreground come from the `console` tokens.
- Every session starts with a Duo-minted `--session-id` (DL-14), a scrubbed environment and `DUO_SESSION_ID` (LR-20), in its project's folder. The `claude` binary is found without the GUI `PATH` (LR-19).
- Switching console tabs starts the second session on first use and shows the first one unchanged on return. Zooming out and back, and collapsing and expanding the left pane, leave every session's process running: identical PIDs before and after (LR-13). The 8×1 floor is enforced in the view (LR-14).
- Keyboard input reaches the focused terminal: `/help` brings up Claude Code's slash-command menu.
- Quitting ends the sessions (a terminate pass on quit, and the PTY closing); no orphaned `claude` processes remain.
- Fixture captures are unchanged: 0 differing pixels against the Phase C captures, since terminals are off in fixture mode.

## F-23 · Spike S9: where the attention state comes from (2026-10-03)

One Haiku session asked an AskUserQuestion and waited, with every hook logged through a per-session `--settings` file (no global settings touched, LR-55).

**`claude agents --json` and the beacons (`~/.claude/sessions/<pid>.json`) agree**, and need no setup:
- Every live session on the machine: `pid`, `cwd`, `kind`, `sessionId`, `name`, `status`.
- `status` is `busy`, `idle`, or `waiting`; while waiting, `waitingFor: "input needed"` (the research also lists "permission prompt"). The beacon adds `statusUpdatedAt` (the wait time), `entrypoint` (`cli`, `claude-desktop`), `nameSource`, `version`, and a `messagingSocketPath`.
- Sessions Duo didn't start appear too (Terminal, the Desktop app): the "live elsewhere" signal LR-8 needs.

**Hooks**, in order for one AskUserQuestion turn:

| Event | When | Useful fields |
|---|---|---|
| `SessionStart` | launch | `source: startup`, `model` |
| `UserPromptSubmit` | prompt sent | `prompt`, `prompt_id` |
| `PreToolUse` | tool about to run | `tool_name: AskUserQuestion`, `tool_input` |
| `PermissionRequest` | the TUI shows the question | `tool_input.questions[]`: `question`, `header`, `options[{label, description}]`, `multiSelect` |
| `Notification` | 6 s later | `notification_type: permission_prompt`, `message: "Claude needs your permission"` |
| `PostToolUse` | answered | `tool_response`, `duration_ms` |
| `Stop` | turn ends | `last_assistant_message` |
| `SessionEnd` | exit | `reason` |

**Consequences for Phase E:**
- Needs-you comes from the beacon's `status: waiting` (authoritative, readable as a file) with `PermissionRequest` as the instant edge. That payload already holds the **verbatim question and options** for the action-column card, with no transcript parsing.
- A plain-text question ends with `Stop` and `status: idle`. The plan maps that to needs-you with reason "question" when `last_assistant_message` asks something, otherwise to idle, or to ready-for-review when a deliverable was written. Legacy set needs-you on every `Stop` (LR-2) and was noisy.
- Hooks fire for permission prompts and AskUserQuestion alike; `notification_type` tells them apart (LR-2's "actionable types only").

## F-63 · Archive a session anywhere it's listed; idle lists newest first (2026-10-04)

- **Archive Session / Unarchive Session (Geoff):** filing, like archiving a project.
  - Stored by id in Duo's state, so plain folders work too.
  - Archived sessions leave every list and count: the snapshot moves them into `Fixture.archivedSessions` and out of groups.
  - They keep their transcript and Duo's copy, stay searchable, and sit in an `Archived · n` fold at the end of their project's list.
  - Refused while the session runs.
  - Undoable. Also available as `duo2 session archive|unarchive`.
- **The session menu (Send, Find Similar, Move to Project, Archive, Delete) is now wherever a session is listed:**
  - tile rows, the project's list, the idle list;
  - needs-you and review cards;
  - console tabs and Home's tabs;
  - search (Archive session and Delete session… in the Tab menu).
  - The project list did have the menu (checked with a real right-click); what it lacked was Archive.
- **Bug: a new session landed in "Older".** Rows sort by state, then by wait, longest first. That is right for needs-you and working, but for idle it put the oldest on top, and the fold then took everything after the first five, which meant the newest. Idle and resolved now sort most recent first.

## F-62 · ⇧⌘A left the keyboard in the terminal (2026-10-04)

- **Seen (Geoff):** the search modal opened, but typing still went to the terminal.
- **Cause:** the field asked for focus in `updateNSView`, which runs before SwiftUI puts the field in its window on the modal's first appearance. The request found no window and was never repeated. This is the same race as the naming field (F-55).
- **Fixed:** the field takes focus when it reaches its window, and keeps checking for a moment, since a re-rendering pane (the terminal) can reclaim first responder.
- **Checked:** in a scripted run, first responder moved from the terminal to the field's editor. In Geoff's Duo, Go › Search Everything… then typing went into the search field.

## F-61 · Geoff's home-view round: open a project by click, archive a project, active tint, delete a session (2026-10-04)

- **ENH-5:** a single click on a tile already opened its project, confirmed with a synthesised mouse event in a scripted run. A card's project name in the action column now opens the project too.
- **ENH-7 (active = a terminal open in Duo):** such sessions now appear on their tile even at the prompt (tiles listed only needs-you, review and working), and are tinted with a new provisional `activeTint` token there and in the project's session list. The selected row's grey fill wins over the tint.
- **ENH-6 (archiving is filing, Geoff):**
  - Archived projects are stored by folder path in Duo's state and move from their topic column into an Archived rollup at the end of the map.
  - Counts, search and sessions are unchanged.
  - Tile right-click › Archive Project, rollup row › Unarchive Project, `duo2 project archive|unarchive`. Undoable. `duo2 projects` marks them.
  - Checked live on two fixture folders, then undone.
- **Delete Session… (Geoff):**
  - A journaled `delete` in the migrator removes the transcript, its sidecar and siblings, Claude's per-session `file-history`, `session-env`, `tasks`, `debug` and `todos` entries, and Duo's archived copy; the session also leaves every Duo index and group.
  - Never `~/.claude.json`, `history.jsonl` or memory.
  - Refused while the session runs. The user confirms in a sheet listing the paths and bytes. It can't be undone; the journal lists what went.
  - Session right-click › Delete Session…, `duo2 session delete`.
  - 3 checks on a fake config. Nothing real was deleted.
- **Design brief:** DB-33 (active look), DB-34 (Archived rollup), DB-35 (revert on the highlight), DB-36 (delete confirmation at scale).

## F-60 · Revert Claude's changes (ENH-4); clicking a session resumes it (2026-10-04)

- **Revert:**
  - The editor records each change that arrives from Claude (`doc edit`, `doc replace`, `doc insert`, the hook) or from outside (the merge), with the text it replaced. Positions are mapped through later edits, for as long as the change is highlighted (until the user's next edit, DL-5).
  - **Revert This Change** puts back the change at the caret; **Revert All of Claude's Changes** puts back every change still highlighted. A revert isn't a user edit, so the other highlights stay.
  - Where: the editor's right-click menu, Edit › Revert Claude's Change and Revert All of Claude's Changes, and `duo2 doc revert [--all | --line n]`.
  - Checked live: two changes, one reverted by line, then the rest.
  - The highlight's own affordance waits for a design. The harness's `editor-js:` takes `⸴` for a comma.
- **Click to resume (Geoff):** a needs-you or review card at All projects now opens its project with the session resumed in the console. Tile rows, the session list, Home's tabs and the idle list already did. Arrow keys still only move the selection.
- **Learned:** a fork keeps its original's title, and title lookups pick the first match, so Duo can open the fork when the original was meant. Session ids are unaffected.

## F-59 · CONS: inventory, evidence and the journaled migrator (2026-10-04)

- **Read-only (P1):**
  - `duo2 inventory` lists every Claude storage folder with:
    - its sessions and bytes;
    - folders whose cwd is gone;
    - collisions (sessions from several cwds, FR-7.8.2);
    - duplicate ids (FR-7.8.1);
    - catch-all folders;
    - how many sessions Claude's cleanup takes within 7 days, and how many Duo's archive already holds.
  - `duo2 evidence <folder>` gives each session's edited files, its candidate home and its date clusters (FR-7.10.2–4).
  - Both run off the main thread. Checked on a fake config, and live: the home folder is the only catch-all here.
- **Migrator (P2/P3, Geoff: build it, test on fakes only):**
  - `Migrator` relocates a session (moves its transcript, sidecar folder and siblings, then appends one `relocated` record, as `/cd` does) and moves a folder with every session under it (folder first, then transcripts, FR-7.5.5).
  - Invariants enforced:
    - a write-ahead journal in Duo's Application Support;
    - liveness (running sessions are refused);
    - encoder self-calibration (any folder name Duo can't reproduce stops everything);
    - the CLI version gate (the binary must contain `relocatedCwd`);
    - kept mtimes;
    - verification (records parse, history bytes unchanged, the record is last, ids unique);
    - undo by reverse replay;
    - interrupted journals block new migrations.
  - 10 checks run it end to end on a throwaway Claude config, including undo byte for byte.
  - Verbs: `duo2 migrations`, `migrate plan relocate|move-folder`, `migrate apply` (the user confirms in Duo), `migrate undo`.
  - Nothing has been applied to the real `~/.claude`. Two plans were made against fixture sessions to check the output, and left unapplied.
- **Not built:**
  - Delete (FR-7.6.2): destructive, and DL-47's copy archive covers preservation.
  - Archive by move (DL-47 chose copies).
  - Re-keying `~/.claude.json` and `history.jsonl` on a folder move. The plan notes the trust prompt that follows.
  - `git worktree repair`.
  - The curation surface: DB-31.

## F-58 · Surfaces slice 1 built: idle list, terminal colours, empty console, shell tabs (2026-10-04)

- **Built to surfaces-handoff slice 1** (Geoff: build it if it fits the direction; the design choices go on the walk as decisions with mockups).
  - **DB-1:** the map footer is a button; the idle list opens above it.
    - Calendar-week buckets, then "Earlier" or months.
    - Group, Unfiled and archived pills.
    - "open in Terminal" rows.
    - ↑↓, Return resumes, ⌘↩ opens the project, Esc, type-to-select.
    - New verb `duo2 idle`.
  - **DB-2:** the 16-colour palette, cursor, selection and Increase Contrast set, applied to every terminal and re-applied when the setting changes.
    - The steady block cursor is set with DECSCUSR, because SwiftTerm keeps the terminal internal.
  - **DB-3:** one message layout for every console with nothing to show.
    - States: none open (Resume ‹last› first), never ran, Claude not found, open elsewhere (Look Again, Resume as a Fork), folder missing, Home with no session.
    - An ended session keeps its output, with a bar (Resume, Close Tab).
    - Exits come from SwiftTerm's process delegate.
  - **DB-4:** shell tabs with the prompt mark, titled by the foreground job (KERN_PROCARGS2; a script shows as `./export-funnel.sh`, not `bash`).
    - `+ ⌄` opens New Claude Session ⌘T and New Shell ⇧⌘T.
    - Typing `claude` promotes the tab in place: the beacon's process descends from the shell. A shell that exits cleanly closes its tab; one that fails keeps the bar.
    - Too many tabs: titles shorten to 24 characters, then the tabs furthest right move into `» n`.
    - New verbs: `duo2 shell new`, `session fork`.
- **Learned:**
  - `claude --resume <id> --fork-session --session-id <new>` honours the given id; the transcript appears under it after the first message. Search's "Resume as a fork" was starting a plain new session; it now forks.
  - A Claude started inside a Duo shell runs as the shell's child. Duo was counting it as "open elsewhere"; it now counts descendants of its own terminals as its own.
  - `ClaudeLocator` now caches its answer, since the console asks on every draw and the PATH fallback starts a login shell.
- **Compared:** idle-list, idle-many, console-none, console-ended, home-none and shell-tab, with `compare.sh` now also finding surfaces-handoff.
  - Left as designed in the handoff's prose, where the screen differs:
    - the ended session moves to Idle on the left (the target still shows it under Working);
    - the idle list's height follows "the map's height less 32" (the target just stops drawing);
    - the fixture's idle ages don't follow calendar weeks, so fixture mode uses the fixture's own buckets.
- **Stubs:** Open Settings… (DB-10), Locate Folder… (DB-8), asking before closing a shell with a running command, the `» n` menu's look.

## F-57 · Groups and threads in the live workspace; duo2 changes undo one at a time (2026-10-04)

- **Threads (DL-24, S11):**
  - Live sessions now carry `forkOf`, so the sidebar folds a fork under its parent, and a group lists its threads parent first.
  - `ThreadCache` reads each transcript's head once (the first user message's uuid and its start).
  - Only sessions sharing a head are read in full, and incrementally: a growing transcript is read from where the last read stopped. The 2 s refresh never re-reads a long transcript.
  - Checked with a synthetic parent and fork, before and after the fork grows.
- **Groups by CLI:**
  - New verbs: `duo2 groups`, `group new|add|remove|rename|delete`.
  - Groups are stored in the project's `.duo/sessions.json` by session id, so renaming a session doesn't break its group.
  - A session belongs to one group. An emptied group goes away.
  - A group's sessions share a project.
  - The verbs read the file, not the last snapshot, and the sidebar updates at once.
  - Grouping by hand in the UI waits for its design (DB-18).
- **Undo bug, found by the group tests:**
  - With `groupsByEvent`, the first undo registered from a duo2 command opened an automatic group. That group closes only at the next user event; with the screen locked there was none.
  - Every later change joined it, so `duo2 undo` reverted them all at once. This hit moves and merges too.
  - `registerUndo` now makes each change its own group, with automatic grouping off while it registers.
  - Checked: three group changes undid one at a time.

## F-56 · Search M-UI built to search-handoff's screens (2026-10-04)

- **Built:**
  - The modal, opened by ⇧⌘A or by clicking the toolbar field. It has a scrim, a field row with no Search/Jump switch (DL-80), a filter row (pop-up buttons, Include archived, and the Exact chip with its ×), a 420-wide list beside the preview, the coverage line, and the footer.
  - The Tab action menu, with DL-79's chords and ⌘D for Send to Claude.
  - Every state: empty with recent searches, typing, exact, find similar (Esc goes back), none, first run, rebuilding, unreadable, multi-select, and narrowing to the project and back (⇧⌘A again).
  - The two landings: a file opens at its lines with the `L40–58 · from search` outline and matched words semibold; a session opens read-only in a right-pane tab, with Resume.
- **Live:**
  - Name matches (projects, groups, sessions) come first as "Go to" rows and need no index (DL-80).
  - Content comes from the index off the main thread. Later keystrokes cancel older answers.
  - Several hits on the same file or session become one row with its passages, and file passages are labelled with their nearest heading.
  - A session's preview shows the turns either side of the match.
  - ⌘D sends references (`@path:lines`, or a session with its turn) into the dark pane's session without submitting.
  - Recent searches are kept in Duo's defaults.
- **Measured:**
  - 15 targets compared with `scripts/check-ui.sh search-*`, with `compare.sh` now finding search-handoff's screens.
  - Differences left on purpose:
    - the scope switch (DL-80);
    - placeholder bars in previews and in the fixture document (§0.4);
    - the ⌘K copy (Q-25);
    - the checkbox drawn inactive because the window isn't key during capture;
    - split view greyed out.
  - Each state has its own minimum body height, read from the targets: 440, 400 on first run, 360 exact, 260 none, 220 empty, error and rebuilding.
- **Parity:**
  - Search's controls map to `search` and `search-status`, Resume to `session open`.
  - New verb `search-rebuild` for Rebuild the index.
- **P3 (later the same day):**
  - Archived sessions show the `archived` pill only with Include archived, and add Carry on in a new session (DL-47, DL-49). Resume puts the transcript back.
  - Find Similar is on the file tree's and session rows' right-click menus. It opens the designed similar view (DB-23 may restyle it).
  - Rows are built off the main thread. A session's neighbouring turns load only when it's selected, since transcripts can be tens of MB.
  - 13 checks for the model.
- **Not designed, stubbed:**
  - New project from search (DB-9).
  - Memory rows (DB-22).
  - Filter pop-ups opened: they are native menus (DB-21).
  - The scrim doesn't cover the toolbar: it's the system's, outside SwiftUI's content.

## F-55 · Walk reruns with the screen locked: real key events, three fixes (2026-10-04)

- **How:** the screen locked while Geoff was out, so computer control could neither see nor click. Duo's harness now sends real key events (`event:esc|return`). They go through the app's queue, so the local monitors see them; when the window can't become key they go window-first, as NSApp would deliver them. Other new harness actions: `editor-js:`, `html-click:` / `html-js-click:`, `sheet:<button>`, `send-picked-new` and `ui-state`. `DUO_INSTALL_ROOT` points the installer, app and duo2 alike, at a throwaway folder, so the install loop runs end to end without touching `~/.claude`.
- **Fixed:**
  - **Inline naming:** the name field asked for focus once, asynchronously, before SwiftUI had put it in the window. Focus stayed elsewhere, so Esc and typing missed it. The field now takes focus when it reaches its window.
  - **File verbs from another folder:** `duo2 file reveal|open-with|path|rename|…` resolved paths only in the caller's folder's project (from the repo, that's the `duo-v2` folder entry) and printed the usage line when the path wasn't there. They now try the project on screen too, and a wrong path says where Duo looked.
  - **Cancel messages:** Haiku read `not moved (the user cancelled)` as "waiting for confirmation". The message now reads: "Not moved: the user clicked Cancel in Duo. Nothing changed and nothing is pending."
- **Learned:**
  - WebKit ignores synthetic mouse clicks in a window that isn't key. The page's own `click()` still raises a link activation.
  - Claude Code labels Duo's PreToolUse deny "hook error", but Claude reads the "Done:" reason correctly and doesn't retry.
- **Walk:** 63 of 65 passed by Claude's runs. Two items stay with Geoff: Writing Tools and dictation (ed-spelling), and Move To…'s folder panel (fv-edit).

## F-54 · Unattended runs: no step may raise a system dialog (2026-10-04)

- **Seen:** while I ran the walk by computer control, macOS kept asking Duo for Screen Recording ("record screen and audio") although Settings listed Duo as allowed, and a UserNotificationCenter dialog sat over Duo and stopped the run. Geoff: "this is massively impacting your testing loops and you need to stop doing this"; later, "don't create a state where a system dialog blocks you".
- **Causes:**
  - `run-live.sh` used `--capture-window`, which ran screencapture(1), and that needs Screen Recording.
  - Each rebuild is ad-hoc signed, so macOS sees a new app and asks again.
  - Full-screen computer control puts system dialogs in front of the run.
  - Quitting Duo with AppleScript can raise an Automation consent.
- **Changed:**
  - Captures draw the window themselves; screencapture only with `DUO_SCREENCAPTURE=1`.
  - Duo quits on SIGTERM as on ⌘Q, so scripts quit by pid: `run-live.sh` and `open-duo.sh` no longer use AppleScript.
  - The acceptance-walk skill now forbids unattended full-screen control and anything that prompts.
  - Duo's own questions (the .gitignore offer, install consent, move/merge confirmations, error notes) were app-modal alerts. `runModal` holds the main queue, so while one waited unanswered, duo2, the edit hook and refresh all stalled. They are now sheets on the window (`DuoAlert`): the question waits, and the app keeps working. Checked: `duo2 ping` and `duo2 projects` answered with the .gitignore sheet up.
- **Also learned:**
  - Audit at 10:30 (the tccd log, and on-screen windows by owner): Duo raised no privacy prompt after the 09:25 build. `scripts/check-sandbox.sh` still quit Duo through AppleScript; it now quits by SIGTERM. A keychain prompt at 10:17 came from `codesign` with the Developer ID key in a parallel signing session, not from Duo or the walk. That session moved its signing to its own keychain, so it no longer prompts.
  - Computer control keeps Escape for itself and can't send ⌘Q, so Escape and ⌘Q behaviour stay on Geoff's list.
  - Background `app_key` Return reaches a Duo terminal, which is enough to run Claude turns unattended.

## F-53 · Duo set off macOS privacy prompts (Music, Photos…) it had no need for (2026-10-04)

- **Seen:** while I ran the walk with computer control, macOS kept raising a privacy prompt over Duo. Geoff: "duo NEEDS to stop proactively asking for permissions to things it does not need, like music, photos, etc — it freaks users out".
- **Cause:** the search indexer walked the files of every folder on the map, including folder entries (DL-63). One is `geoff` (`~`, where Claude sessions were started), so the walk went into ~/Music, ~/Pictures, ~/Documents and the rest. F-28's guard covered only project discovery.
- **Fixed:**
  - `ProtectedFolders` (DuoSearch) is the one rule: no walk enters Desktop, Documents, Downloads, Pictures, Movies, Music, Library, Public or Applications under home unless the walk started inside it. The home folder is never a file root.
  - Search indexes files only for documented projects; folder entries contribute their sessions. Their previously indexed files are dropped.
  - Project discovery and the file list use the same rule.
- **Checked:** 2 checks (the home folder yields no files; Music and Pictures are skipped from home, while a project at ~/Documents is still read).
- **For Geoff:** macOS remembers the answers already given to Duo's prompts; System Settings › Privacy & Security lists them, and Duo needs none of them.

## F-52 · Walk run by computer control: what it found (2026-10-04)

Running every test on the acceptance page (Geoff: "attempt every test yourself prior to asking me"), with real clicks, keys and right-clicks:
- **Opening a project could leave the console black:** opening only picked a session that was working or waiting on the user, never one idle at its prompt. Fixed: it falls back to a session with a running terminal.
- **Format › Bold and Italic were greyed while the editor had the focus:** menus re-validate only when observed state changes, and the editor's focus wasn't observed. Fixed: web views report focus (`webFocus`).
- **⌘I never reached Format › Italic:** CodeMirror's select-parent-syntax took it. Fixed: Duo's menu chords are removed from CodeMirror's keymap (⌘D, ⌘I, ⌘B, ⌘S, ⌘W, ⌘N, ⇧⌘N, ⌘K, ⇧⌘A, ⇧⌘P, ⇧⌘H, ⌘↩).
- **A non-UTF-8 file's tab showed the previous document's text:** the editor never loaded it. Fixed: it's shown decoded (Windows-1252, then Latin-1), read-only, never saved.
- **The Older fold:** a section with five sessions plus `Older · 4` was headed `Idle · 6`. Fixed: the fold counts its sessions.
- **Two folder entries were both named `payments/checkout`:** names are keys, so one hid the other. Fixed: parent folders are added until the name is unique.
- **Escape cancelled neither inline naming nor the element picker.** The field now claims Escape itself; a diagnostic logs where Escape goes (still open).
- **Sessions in the acceptance folders opened on Claude's trust prompt.** Geoff allowed me to trust the fixture folders.
- **Walk setup kept starting new sessions:** each restart added another `New session`. Fixed: it resumes the project's latest one.
- **Other observations:**
  - WebKit adds its own Reload beside Reload Page.
  - Send To lists Home's session as `New session` right above the New Session item.
  - The Edit menu names the undo action ("Undo Move Session") only while Duo is frontmost.

## F-51 · Drag and drop on the map: the confirmation was lost (2026-10-04)

- **Geoff's report:**
  - Dragging on All projects showed a translucent ghost, so tiles overlapping each other were illegible.
  - There was no motion.
  - Release did nothing visible: "half built or simply broken?"
- **Cause, found with computer control and a new diagnostic log** (`App Support/Duo/logs/duo.log`, `DuoLog`):
  - The drop reached Duo and the merge was called.
  - Its confirmation was an app-modal `NSAlert` started inside the drop. It came up as a loose window, and the drag image froze over it.
  - Nothing looked changed until it was answered.
  - Drag and drop had never been exercised with real input before (F-45 used an auto-confirm switch).
- **Fixed:**
  - **Confirmation:** a sheet on the Duo window, shown 0.25 s after the drop, once the drag has finished. Move and merge now report their result by callback, so `duo2 session move` and `project merge` answer from the user's actual choice.
  - **What follows the pointer** is an opaque white card with the popover shadow (`onDrag(_:preview:)`).
  - **The source sinks** (35%, 96%) while dragged. SwiftUI has no drag-ended callback, so the mouse button is polled to restore it.
  - **The tile under the card rises** (103%, 2 pt outline, shadow), with spring animations.
  - **The target says what arrived:** it pulses and shows "2 sessions moved in" for 2.5 s. Tiles list only running sessions, so a merge of idle ones was otherwise invisible.
- **Verified with real mouse input:**
  - scratch dragged onto refunds brought up the sheet over the window;
  - Merge moved both sessions, the empty scratch folder left the map and refunds pulsed;
  - Edit › Undo put them back.
- **Not verified:** the drag preview itself mid-drag, because full-screen capture wasn't approved in time.
- **Noted:** the Edit menu shows "Undo" without the action's name ("Undo Merge Projects").

## F-50 · Collisions: merge by line, never write blind, keep every version (DL-77) (2026-10-04)

- **Legacy, reviewed** (summary in `docs/design/collisions.md`):
  - It read the disk before every save and had robust watching.
  - It never merged: any outside change to a buffer with unsaved edits raised a banner.
  - About 11 bugs came from Markdown round-trip normalising and self-echo timing.
  - Its own record says autosave made the unsaved-edits protection "largely illusory".
- **Built:**
  - **Merge:** a three-way merge by line (Myers diff per side, diff3 grouping), replacing the one-hunk-per-side merge. A 30,000-line file merges in 4 ms (`node scripts/check-merge.mjs`, 9 cases).
  - **Saving:** each save reads the disk first, and again before the rename; it merges an unseen outside write first, and a conflict stops the save.
  - **Watching:** the file and its folder, with symlinks resolved, settling for 150 ms. Duo's own saves are recognised by content.
  - **Kept text:** unsaved text kept per document when you switch away in a conflict or after a removal.
  - **Removed on disk:** keeps the buffer, pauses autosave, offers Save to Recreate.
  - **Quit:** saves flush (`applicationShouldTerminate`, 2 s cap).
  - **History:** content-addressed snapshots in `App Support/Duo/history/`. Kept: the file as opened, both sides of a conflict, the side a resolution replaces, and the text before a removal. At most 200 per file. Listed by `duo2 doc history`.
  - **Resolving:** Keep Mine / Use Theirs in the app and with `duo2 doc resolve`.
- **Verified live** (harness actions `user-type`, `disk-write`, `disk-rename`, `disk-delete`, `editor-state`):
  - unsaved typing plus an in-place write on another line: merged and saved;
  - the same with an atomic rename: merged;
  - the same line: a conflict, with the buffer kept as mine, the disk as theirs, and history holding both;
  - switching away and back: the text is kept and the conflict re-detected;
  - `duo2 doc resolve theirs`: took the file's version, with the user's text in history;
  - delete: the bar shows, and the text stays.
- **Not yet:**
  - a Compare view;
  - browsing and restoring history in the app;
  - designed bars (Q-20);
  - deletions highlighted (only inserted text is marked).

## F-49 · Claude editing an open document: what it does, and the hook (DL-78) (2026-10-04)

- **Setup:**
  - A test workspace at `~/DuoAgentTest`, whose checkout folder Claude trusts (accepted with the harness's new `key:` action), and `build/edit-test.sh`.
  - `docs/prd.md` is open in Duo's editor, and the prompts are neutral, never naming Duo or `duo2`.
  - Tool calls are read from the transcript; the editor's highlight count and the disk diff are checked.
- **Test A (Haiku, primer only, no hook):** it searched, read the file, and then went for its own Edit tool, never `duo2`. That stopped at a permission prompt, because auto mode doesn't apply to Haiku. Geoff's sessions run Opus in auto mode, where such an edit would go straight to disk. Under the old `doc status` wording ("write anyway and Duo merges"), it was even invited to.
- **Test A again (Haiku, with the hook):**
  - It ran `duo2 status`, read the file, then Edit.
  - The hook applied the edit in the editor (highlighted) and declined the write with "Done: …".
  - Claude reported success correctly, with no permission prompt; the file autosaved.
  - Claude Code labels the decline "PreToolUse:Edit hook error", but Claude read the reason as intended.
- **Test B (Haiku, stronger primer, hook off):** it still used Edit. Instructions alone don't steer Haiku.
- **Test C (Opus, stronger primer, hook off, auto mode):**
  - It ran `duo2 status`, then `cat` and `duo2 doc status`, then piped the Edit JSON into `duo2 doc edit --stdin`.
  - Its first try used a relative path, which `doc edit` then wrongly rejected (fixed: relative to the caller's folder); it retried with the full path.
  - The edit applied, highlighted.
- **Test D (Haiku, with the hook, a two-part rewrite):** two Edits, both routed through the editor, with two highlighted changes, saved.
- **So:**
  - **The hook is the guarantee where hooks run.**
  - **The primer is the backup where they don't** (followed by Opus, not by Haiku).
  - **The merge is the floor:** a direct write still lands highlighted and never over unsaved text.
  - `duo2 doctor` reports whether hooks run in the session.
- **Only the showing document counts as open:** other tabs are files on disk, so an Edit to one of them passes through.

## F-48 · How sessions learn duo2: the install loop (DL-74, DL-75) (2026-10-04)

- **Two reviews of legacy Duo** (its CLI, then how it teaches sessions) are summarised in `docs/design/cli-teaching.md`. Legacy's record: generated text never drifted, hand-written text did (verbs that don't exist in the always-on priming); "write only if missing" kept fixes from ever reaching users; a SessionStart hook doubled the always-on cost; the global `claude` wrapper broke when Claude moved.
- **Built:** `Installer` (DuoControl), all generated from the registry: a short block (under 110 words, checked) in `~/.claude/CLAUDE.md` between `<!-- duo2:begin … -->` and `<!-- duo2:end -->` (legacy's regex can't match it, and v2's legacy detector ignores it); `~/.claude/skills/duo2/SKILL.md`; `~/.local/bin/duo2` linked to the app's `Helpers/duo2`. Rewritten at every launch; a file whose hash isn't Duo's is left alone and reported; a removed block is never re-added; the newest format wins; `installed.json` in App Support is the manifest.
- **Consent** (DL-75): one alert at launch lists every change; the answer is stored with a hash of that list and asked again only when it changes. `duo2 install` / `duo2 uninstall` change it later; `duo2 doctor` shows each piece's state.
- **Legacy restore copies whole files back**, which would drop v2's block: restore now re-adds it. 11 checks cover the loop against a temporary home (`Installer.testRoot`).

## F-47 · duo2 parity: one action registry (DL-71–DL-73) (2026-10-04)

- **`DuoAction.all`** (`Sources/DuoControl/Actions.swift`) is the only list of actions: 69 verbs in 10 families. The CLI resolves two-word verbs (`file rename`) then one-word ones, and old spellings (`doc-status`) still work. `duo2 help`, `duo2 help <family>`, the reference (`docs/cli/duo2.md`, `duo2 help --markdown`), the primer every Duo session gets, the skill and the CLAUDE.md block are all generated from it.
- **Parity is enforced three ways:** the app's handler is a `switch` over every action with no `default`, so a new verb that the app doesn't handle won't compile; `DuoChecks` scans `Sources/DuoKit` and fails on any `Button`, `Menu` or menu item whose label isn't an action's `ui` label or in `Parity.uiOnly` (with its reason), and on any click or drag (`.onActivate`, `.onDrag`, `.onDrop`) without `// action: <verb>`; and the reference file must match the registry.
- **Text by default, `--json` on every verb**; errors on stderr with a non-zero exit (64 for usage). Confirmations stay with the person: `session move` and `project merge` show Duo's sheet and the CLI waits (10-minute timeout) for the answer.
- **Which project a verb acts on** without `--project`: the one holding the caller's folder (Claude's own project), then the one showing. Caught in testing: run from this repo, `file new` created a file in the repo (a folder entry), so every file reply now names its project.
- **Agent edits go through the editor** (LR-34): `doc insert` and `doc replace` change the buffer with the "added by Claude" highlight and autosave; `doc replace` refuses text that isn't found or isn't unique.
- Verified live, driven only by `duo2` (open, session new, files, file new/rename/path/duplicate/trash, doc open/read/insert/replace/tabs, html element/pick, send element/file/project/text, sessions, session show, project show, view tab, go all, undo, an unknown verb).

## F-46 · Send to Claude, local HTML and the element picker (DL-67–DL-70) (2026-10-04)

- **Delivery is one bracketed paste** (`ESC[200~ … ESC[201~`), never Enter. SwiftTerm doesn't expose whether the program asked for bracketed paste, so Duo always brackets; only Claude sessions receive sends, and Claude Code always enables it. Every control character but newline and tab is stripped first: an `ESC[201~` in the content would otherwise end the paste and run the rest as keystrokes.
- **Claude Code folds pastes** into `[Pasted text #n +N lines]`, and **turns an image path in a paste into an attachment** (`[Image #1]`): the element's screenshot arrives as an image Claude can see.
- **Readiness comes from the beacon:** no beacon means Claude is still at the folder-trust prompt (a paste there landed in the trust menu in testing); `waiting` means a question or permission menu. Sends wait for `busy` or `idle`, and the menu says why when they can't.
- **The page's own selection**: WebKit adds a Copy item to its context menu only when something is selected (`WKMenuItemIdentifierCopy`), and Copy Image over an image; Duo reads those to decide whether to offer Send Selection / Send Image. Images in a selection are found in the range's cloned fragment and sent as file paths.
- **The picker** is an injected user script: `mouseover` outlines, a capturing `click` freezes (and is swallowed so the page doesn't act), Esc exits. The payload follows LR-44 (tag, legacy's selector, heading trail, text, allow-listed attributes) plus computed styles, the box, capped outer HTML and an element screenshot (`takeSnapshot` of the element's rect, outline hidden), saved under `App Support/Duo/context/`.
- **Local HTML** opens in its own read-only `WKWebView` with read access to the project folder, reloads within a second when the page or its neighbouring css/js/images change, and sends links to other sites to the default browser (DL-3).
- Captures without Screen Recording draw web views blank (like terminals, F-25); `html-snapshot` in the harness takes the web view's own picture.

## F-45 · Organising sessions and projects (DL-63–DL-66) (2026-10-03)

- **Claude's whole history is read** (`ClaudeStorage.history()`: every top-level transcript with the folder it belongs to after any `/cd`, cached by modification time). Each project lists every past session in its folder (DL-59), not only those Duo filed; beyond the five most recent idle ones they fold under **Older · N**.
- **Folders with sessions but no PROJECT.md** become map entries (DL-63): on this Mac `~` (4 sessions), `~/repos` (4), `count-fidget`, `pm-harness` (has CLAUDE.md), `thinking-about-risk`, `duo-v2` (has CLAUDE.md), all under **Elsewhere**. Their tiles show the path, "No project file" or "Has CLAUDE.md · no project file", and the count of past sessions. They get no file tree: `~` would mean walking Documents and Desktop (privacy prompts, F-28).
- **Right-click**: sessions (left pane and tiles) → Move to Project ▸; folders → Make a Project, Merge Sessions Into ▸; projects → Merge Into ▸. **Drag** a session or a tile onto a tile to move or merge. Every one asks first with a sheet listing exactly what moves (DL-66), then can be undone (Edit › Undo restores every index touched, byte for byte; Make a Project's undo moves the new PROJECT.md to the Trash and forgets the registry entry).
- **Moves stick** (DL-64): an entry with `provenance: moved-by-user:<from>` stays in the project it was filed in; cwd-based attribution and history never take it back.
- **`--resume <id>` works from any folder** (Haiku remembered a word across folders), but in headless mode the transcript stays where it was. **Relocation on resume:** Duo starts the moved session in its *old* folder and, when Claude's beacon reports the prompt idle, sends `/cd <project folder>`. Two traps found live: `/cd` to the folder the session is already in moves nothing, and text plus Return sent in one burst is taken as a paste (the Return doesn't submit), so Return goes separately. A trust dialog can't receive the keystrokes: the beacon only appears once the session is running. Verified: the transcript moved to checkout-redesign's folder, "Moved to …".
- **Sidebar rows activate by session identity** (they used the name, wrong when two share one).
- Verified live with an auto-confirm switch (`DUO_AUTOCONFIRM`, checks only): move, merge and make-a-project, each undone exactly. 129 checks pass (history in place, folder entries with CLAUDE.md, sticky moves). Fixture captures unchanged except the DL-59 button region.
- **Not seen with a real right-click or drag yet:** Geoff to try. The New project button stays inert until the PROJECT.md template (G-1).

## F-44 · File verbs, document tabs, the Project tab, and a save race (2026-10-03)

Built from Geoff's requests (DL-59–DL-62). Live mode; fixture mode attaches none of it.

- **File verbs** (`FileActions`, `AppModel+Files`): New Markdown File (⌘N), New Folder (⇧⌘N), New from Template (the project's `templates/`, then Home's), Rename (inline), Duplicate, Move To…, Move to Trash (never a hard delete), Copy Path, Copy Relative Path, Copy as Link (`[name](relative/path.md)`, DL-17), Reveal in Finder, Open With (default app, others, or Other…), Send to Claude (types `@path ` into the console session's prompt without sending, DL-45). The same menu on file rows and on document tabs (plus Close Tab, Close Other Tabs); the tree's background offers the "new" verbs. Names never clobber ("Untitled 2.md").
- **Inline naming** (DL-62): a native text field in the row, the stem selected; Return or clicking away confirms, Esc cancels. Rename carries open tabs and the editor to the new path; Move to Trash closes them.
- **Document tabs persist** per project; switching to Project no longer closes your file. The right pane has a + like the console's. **The Project tab opens `PROJECT.md`** (or `HOME.md`) in the editor (DL-60); its frontmatter shows as text until ENH-1. "Resume a session" is gone (DL-59).
- **The tree shows folders**, empty ones included (the snapshot now lists `folder/` entries).
- **⌘W closes the focused tab**: the document when the editor has focus, else the session (menu: Close Tab).
- **A save race, found by the checks here:** switching documents started the old file's save, then loaded the new file, which replaced the editor's idea of "what's on disk" before the save's text came back. The old file was then compared with the new file's bytes and rewritten (identical bytes this time; with different timing, the wrong file could have been written). Saves now capture the file and its baseline up front, skip entirely when nothing was typed, and only update state if the file is still the one open. Verified: viewing `PROJECT.md` no longer touches it; an edit followed by an immediate switch saves the right text to the right file.
- **Flaky peek captures:** flow-zoom-3's popover was missing or half-drawn in about half the captures with this change set (a fixed 1.5 s delay sometimes landed before the popover finished appearing). The harness now waits for the popover window and its fade before capturing: 6/6. Bisect: 04c1f09 was stable, so something in this set slowed the first render slightly; not traced further.
- **Fixture targets vs DL-59:** project, flow-zoom-2 and flow-zoom-3 now differ from the targets only where "Resume a session" was (rows 242–268 pt); an exemption by decision.
- Verified live (harness): new file → opened and naming; rename → tab and editor follow; new folder shown; duplicate; trash. **Not yet seen with a real right-click** (the screen-takeover prompt timed out): Geoff to try.
- 126 checks pass.

## F-43 · With the screen unlocked: the real window, menus and the editor by hand (2026-10-03)

Checked with computer-use on the running app (live mode, demo workspace).

- **The AppKit window** (F-30) looks and behaves as before; **menus press**: Go › All Projects moved the view (confirmed with `duo2 status`).
- **The editor was invisible in the real window.** The web view was attached once while its container was zero-sized and not yet in a window; autoresizing alone never grew it (the scripted snapshot had passed because WebKit can snapshot an unattached view). It now sits in a host view that lays it out on every pass, as the terminals do. Shown: target typography, task checkboxes, hidden syntax, the raw line under the caret, the native caret.
- **Spelling:** check-as-you-type is now on by default for the editor (`WebContinuousSpellCheckingEnabled`, registered so the user's choice still wins); typing "recieve teh" was corrected by macOS with its usual marks. **The Edit menu lacked** Find, Spelling and Grammar, Substitutions, Transformations and Speech; SwiftUI's `TextEditingCommands()` adds them.
- **Format › Bold (⌘B) and Italic (⌘I)** drive the editor (stack rec #9) and are enabled only while it has focus; Bold on a double-clicked word reached the file via autosave.
- **Find (⌘F) in the editor** routes to CodeMirror's search, not WebKit's: CodeMirror renders only visible lines, so a page-level find would miss the rest of a long document. The editor's web view handles both `performTextFinderAction:` and the older `performFindPanelAction:` (SwiftUI's Find item sends the latter); the panel is CodeMirror's, in token colours, a stub until designed (Q-20). Menu items that depend on focus are disabled while Duo isn't frontmost, which is macOS behaviour, not a bug. In a terminal, Find opens SwiftTerm's own find bar, which is cramped in the 340-pt Home pane (its buttons render 2 pt wide): a design item.
- **Writing Tools** didn't appear in the Edit menu; the editor now asks for full Writing Tools (`writingToolsBehavior = .complete`). Whether they show depends on Apple Intelligence on this Mac; **still to check by hand**, with dictation.
- **Sidebar bug:** sessions were folded into threads by *name*; two live sessions both called "New session" became a false "thread · 2" and one was hidden. Rows are now keyed by session identity; fixture captures unchanged (0 px).
- **The `.gitignore` alert** shows as a standard alert; "Don't Add" records the answer and writes nothing. Wording now handles a project that is itself the repository.
- Enhancements logged from Geoff: ENH-1 Obsidian-compatible frontmatter editing, ENH-2 JSON editing modes (`docs/plan/enhancements.md`).

## F-42 · Remote decisions built: sidecars, purged sessions in search, the .gitignore offer (2026-10-03)

- **Sidecars (DL-48):** the archive copies a session's sidecar folder (tool outputs, subagent transcripts) when its fingerprint (files, bytes, newest change) moves, and restores it with the transcript.
- **Purged sessions in search (DL-49):** sessions whose transcript Claude removed but Duo archived are indexed from the archive copy and marked `archived` (CLI: "(archived by Duo)", JSON `archived: true`). Index schema 2 adds the column (added in place). SRCH Q8/L17 need updating to match.
- **`.gitignore` offer (DL-50):** once per launch per project, off the main thread, Duo asks git itself (`git check-ignore`) whether `.duo/` is ignored, so ignored parents and nested rules count (the demo workspace inside this repo's ignored `.build/` was correctly not offered). If not, a standard macOS alert asks once; the answer is remembered per repository in `Duo/state.json`. Scripted captures never show it; `DUO_GITIGNORE_ANSWER` answers it in tests. Verified live with a scratch repo: `.duo/` appended, git ignores it, the answer stored. The alert itself is unseen until the screen is unlocked, and is a system alert pending a design (§13 notices).
- 126 checks pass.

## F-41 · Retention: archive and keep-alive (DL-44, DL-47) (2026-10-03)

- **What Claude Code's cleanup checks** (its own code, 2.1.289): every swept file is deleted when `stat.mtime < now − cleanupPeriodDays` (`if(!(w.mtime<r))return s.filesRetainedFresh++`); session folders are judged by their modification time too. Timestamps inside the transcript don't matter. The period comes from settings (managed policy, then user), default 30; 0 turns cleanup off. A scratch-config test was inconclusive (unauthenticated, Claude exited before sweeping), so this rests on the code.
- **Archive:** after each refresh is applied (at most once a minute, off the main thread), every listed session's transcript is copied to `~/Library/Application Support/Duo/archive/<id>.jsonl` (folder 0700, files 0600) when its size or modification time changed, with a manifest of its folder (after any `/cd`) and title. **The first version archived nothing:** it ran before the refresh applied the new snapshot, saw the empty starting state and waited a minute; now it runs after.
- **Purged sessions:** stay listed under their archived title. Resuming puts the transcript back where Claude Code looks (never over an existing one) and runs `--resume`. Verified live: a planted transcript was archived, removed (simulating the sweep), listed as "Velocity rules audit", and resumed with its conversation back. `duo2 session carry-on <id>` starts a new session in the same project whose first prompt points Claude at the archived transcript (Geoff's idea).
- **Keep-alive:** a listed transcript (and its sidecar folder of tool outputs and subagents) untouched for half the period gets its modification time set to *half the period ago*, not now, so it never ages out yet doesn't jump to the top of anything sorted by recency. Checked: a 25-day-old session moves to 15 days; a fresh one is untouched.
- 124 checks pass. Still open in Q-19: archiving sidecars, a disk limit, and whether purged sessions stay searchable (SRCH Q8 says no today).

## F-40 · Phase I begins: the document editor in the right pane (2026-10-03)

Geoff chose this next (2026-10-03). Live mode only: fixture mode keeps the placeholder the targets exempt, so the six fixture captures stay pixel-identical (checked: 0 differing pixels).

- **One shared `WKWebView`** (`EditorController`, re-parented like terminals) loads the vendored bundle from `Duo.app/Contents/Resources/editor/` (`bundle.sh` copies it). Clicking a file in the tree opens it in the right pane.
- **Styling from the tokens:** the app injects Duo's colours as CSS variables (no hex in the editor); body 13/20, headings 14 semibold, padding 22 28, pane background, as the target's document area. Verified by computed styles. Review image: `docs/plan/review/phase-i/editor-live.png` (WebKit's own snapshot; the frame-view capture can't see web content). Bold and link syntax hide off the caret's line; headings style; **task lists needed the GitHub-flavoured dialect** (`markdown({ base: markdownLanguage })`): CodeMirror's default is plain CommonMark.
- **Files stay the truth:** opening never writes (checked byte for byte). Non-UTF-8 files and files with mixed line endings open read-only (LR-30). Autosave a second after the last change, and on switching documents; ⌘S saves now. Saves are temp-file-then-rename and only when the text differs from disk (LR-35).
- **Outside changes:** a file watcher (re-armed after rename-saves) feeds the three-way merge from S5: applied, merged with local edits elsewhere, or a conflict that keeps the user's text. Verified live: an edit autosaved, then a line appended "by another app" merged in.
- **Claude's edits arrive as outside changes** (it writes files directly). A clean document reloads silently and **highlights what arrived** until the user's next edit (DL-5, LR-33; formatting commands count as edits). **On a conflict, autosave pauses** (LR-32): without that, the next autosave would have overwritten the other writer's change on disk, a data-loss path in the first version. Verified live: the outside title stayed on disk while unsaved edits waited. **`duo2 doc-status <file>`** (LR-34) tells Claude whether a file is open, unsaved or in conflict. Routing Claude's writes *through* the buffer (`doc.edit`) and the `PreToolUse` warning are left for now: the merge already handles raw writes safely.
- **Not designed yet (Q-20):** the conflict banner, the read-only notice, and editor internals beyond the target's type (list bullets, tables, images, code blocks). Stubs only; nothing invented.

## F-39 · Spike S6: the native hedge (swift-markdown-engine) doesn't scale; CodeMirror 6 stays (2026-10-03)

Geoff asked for S6 to run now (2026-10-03). `Vendor/swift-markdown-engine`: the dependency-free core at commit `1c2e76c1` (Apache-2.0); it **builds with the Command Line Tools alone**. `Spikes/S6Native` hosts its `NativeTextViewWrapper` (TextKit 2) offscreen and drives the text view directly.

| Same criteria as S4 (F-34) | Native engine | CodeMirror 6 |
|---|---|---|
| Unedited round trip (385 KB, 13 KB, CRLF, 1.2 MB) | byte-identical ✔ | byte-identical ✔ |
| Open 1.2 MB / 385 KB / 13 KB | 3.7 s / 1.2 s / 0.35 s | 7–23 ms |
| Typing, 1.2 MB (p95) | **244 ms** | 1 ms |
| Typing, 13 KB (p95) | 3.6 ms | — |
| Memory with 1.2 MB open | 543 MB (process) | 102 MB (WebContent) |
| After 300 characters on 1.2 MB | 1.4 GB | 129 MB (paced) |

- **Decision stands: CodeMirror 6 for v1**, native later (stack rec #8). The engine is pleasant at PM-document sizes but its cost grows with document length, so a long transcript-derived note or the legacy `tasks.md` would freeze typing.
- Not judged: the outside-edit caret (the spike rebuilt the view rather than updating it in place, which isn't a fair test), and the engine's own bold command (it needs its controller wired to the view; the spike typed the markers instead). The binding isn't updated synchronously after an edit (likely debounced).
- Keyboard-side checks (spellcheck, dictation, Writing Tools) would favour native; they're still to do for CodeMirror with Geoff at the Mac.

## F-38 · Search P2 back end: sessions and memory (2026-10-03)

- **Sessions (L7, FR-7.2):** every top-level transcript in `~/.claude/projects/*/`. Only conversation text: user prompts (not tool results, harness-wrapped commands or system reminders) and assistant prose (not thinking or tool calls). One unit per turn ("You: … Claude: …"), split at 300 tokens, located as `turn N` (FR-7.2.3). Title: custom → AI → first prompt. Unknown record types and broken lines are skipped (FR-7.2.2); a changed transcript is re-read whole (FR-7.2.4, simple and correct; appends could be incremental later).
- **Attribution:** the transcript's cwd (or its last `relocatedCwd`) inside a workspace project's folder → that project; otherwise **Unfiled** (FR-7.1.5). This conversation, run from `~/repos/duo-v2`, shows as Unfiled against the demo workspace, as it should.
- **Memory:** `~/.claude/projects/<bucket>/memory/*.md`, attributed through the bucket's sessions. `CLAUDE.md` files inside projects were already covered as files.
- **Deletion (L17):** a transcript that disappears (Claude's retention sweep, or deleted) leaves the index on the next pass; Q-19's archive will decide whether purged sessions stay findable.
- `duo2 search --kind session|memory|file` filters by source (FR-7.4.6); session results give the transcript path and the turn.
- Live on this Mac: 42 sessions, 10 memory notes and 20 files → 702 passages, 686 unique (embedded once). 118 checks pass, including: thinking, tool calls and tool output never reach the index; a session outside every project is Unfiled; a deleted transcript leaves.
- **Chord change:** search is `⇧⌘A`, like Chrome's tab search (DL-46).
- **Find similar (FR-7.6.4):** `duo2 search --similar <path>` uses the mean of the item's passage vectors and leaves the item out. The item's own passages must be dropped *before* the relative margin is applied, or the item (cosine ≈ 1) sets a margin nothing else meets; the first version returned nothing.
- **Duplicates (FR-7.4.5):** identical passages in several files show once, with `also in:` the other paths.
- **⌘W closes the session tab** (ends its process; the session stays filed and resumable) and **⇧⌘W closes the window**, since the window is AppKit now and ⌘W would otherwise close it (LR-60). Verified live: the closed session's terminal and process are gone, its index entry stays. 120 checks pass.

## F-37 · Legacy Duo detection and a reversible disable (DL-39) (2026-10-03)

- Legacy Duo installs five things into `~/.claude` (its `install-service.ts`): hooks tagged `"_duo": "managed-v…"` in `settings.json`, a `<!-- duo:managed-v… -->` … `<!-- duo:end -->` block in `CLAUDE.md`, `skills/duo/`, `agents/duo.md`, and a `claude` wrapper in `duo/bin/`. None are on this Mac; the work Mac may have them.
- `duo2 legacy` lists what's there; `duo2 doctor` mentions it. `duo2 legacy disable --yes` copies `settings.json` and `CLAUDE.md` into `~/Library/Application Support/Duo/backups/legacy-duo-<time>/`, removes only the marked hooks and block, and moves the skill, subagent and wrapper into the backup. `duo2 legacy restore <backup>` puts everything back byte for byte (checked on a scratch config folder; `CLAUDE_CONFIG_DIR` honoured). The user's own hooks and `CLAUDE.md` text are untouched; `settings.json` is rewritten with sorted keys (the original is in the backup).
- The in-app notice DL-39 describes needs a design (§13); the CLI covers detection and the action until then. 110 checks pass.

## F-36 · Phase M1: search over every project's files, by meaning and by words (2026-10-03)

Built ahead of v1.1 because every remaining v1 feature waits on a design (logged in the plan). `Sources/DuoSearch` (Foundation, SQLite, Core ML, Accelerate; no AppKit), the app's background indexer, and `duo2 search` / `search-status`.

- **Storage (SRCH Q4, decided here):** one SQLite file in `~/Library/Application Support/Duo/search/` (folder 0700, file 0600). FTS5 with the Porter stemmer for words; one fp32 vector per unique passage, keyed by the hash of its redacted text (FR-7.3.5: a moved file re-embedded nothing in the checks). **Rollback-journal mode, not WAL:** WAL readers must write the shared-memory file, which the sandboxed CLI can't. The model's identity is stored; a different model empties and rebuilds the index (FR-7.3.8).
- **Model delivery (DL-40):** `Models/bge-small-fp16/` commits the converted model with its weights in two parts under 50 MB, `SHA256SUMS` and provenance; `bundle.sh` reassembles and verifies them, and the app compiles the model into Duo's folder on first launch. One fp16 model for both indexing (GPU) and queries (CPU), so index and query numerics are identical (64 MB, not 191 MB for two).
- **Files (FR-7.1.2, FR-7.8):** text, code, CSV/TSV, JSON/JSONL and PDF (text via PDFKit, registered by the app only, so `duo2` doesn't load AppKit). `.gitignore` honoured (globs, `**`, anchored, directory-only, negation); dependency and build folders skipped; secret files denied; keys, tokens, JWTs, private-key blocks and credentials in URLs redacted before anything is stored.
- **Chunks:** paragraphs and headings (Markdown, text), blank-line blocks (code), one record per row (JSONL, CSV); up to 300 tokens, 45-token overlap when a unit is split (the POC's numbers).
- **Ranking (Q5, first tuning):** reciprocal-rank fusion (k = 10) of semantic and keyword candidates; literal matches of a quoted phrase or identifier-like token on top; current project × 1.08; grouped one result per file. **The first version put an unrelated `PROJECT.md` first** for a question asked from that project: OR'd stopwords ("day") made it a keyword match, rank fusion ignores how strong a match is, and a 15% boost decided it. Fixed with a stopword list, semantic candidates limited to within 0.12 cosine of the best (relative, FR-7.4.7), sharper fusion and a smaller boost; now a check.
- **Golden set through Duo's own pipeline:** 7/7 top-1 on the POC's fixtures, PDF included. Re-indexing unchanged files embeds nothing.
- **A real bug the checks caught:** relative paths were sliced off absolute ones, but directory listings spell `/var` and `/private/var` differently, so every file looked new on the second pass and gitignore rules matched the wrong paths. Relative paths are now built while walking, and the root is resolved first.
- **Agent path (S-AGENT, S-NOAPP, FR-7.7.2–7.7.3):** with Duo closed, `duo2 search` answers in 0.3 s (cold, model load included; the POC's bar is 0.25 s). Under Seatbelt (`scripts/check-sandbox.sh`) and in Claude's real sandbox (Haiku, `sandbox.enabled` and nothing else) it returns the right result and writes nothing to Duo's folder or the caches.
- **Sessions are told** about `duo2 search` (prefer it to grep across projects; read only the lines it points to; scores are relative) through the generated session guidance (FR-7.7.6).
- **Not in M1:** sessions, memory and `CLAUDE.md` as sources (P2); the search UI (design-gated: ⇧⌘A, DL-46); duplicate-content folding (FR-7.4.5); user exclusions (FR-7.1.7); file watching (the indexer runs after workspace changes, at most once a minute).
- 107 checks pass.

## F-35 · Spikes S13–S15: Core ML search embedding passes all three P0 gates (2026-10-03)

Geoff approved fetching the model (2026-10-03). `Spikes/S13CoreML` (conversion and parity, Python) and `Spikes/S14Embed` (Swift: tokenizer, queries, sandbox, throughput).

**S13, conversion and parity (SRCH Q3): pass.**
- `BAAI/bge-small-en-v1.5` at the POC's pinned revision `5c38ec7c`, fetched with checksums (`PROVENANCE.json`); its `tokenizer.json` is byte-identical to the POC's. Converted with coremltools 9.0, **torch pinned to 2.7.0 and transformers to 4.46.3** (transformers 5 emits `new_ones`, which coremltools can't convert).
- **Parity, using the POC's own CLI** (its ingest, chunking and ranking; only the model call swapped through a `sitecustomize` hook), on its fixtures and 7 golden queries:

| Variant | Golden top-1 | Top-5 order = ONNX | Max score diff |
|---|---|---|---|
| ONNX (the POC) | 7/7 | — | — |
| Core ML fp32 (CPU, or all units) | 7/7 | 7/7 | 0 at the POC's printed precision |
| Core ML fp16 (all units) | 7/7 | 7/7 | 0.0005 |
| Core ML fp16 (CPU + Neural Engine) | 7/7 | 7/7 | 0.0017 |

- **fp16 first came out NaN:** transformers masks padding with float32's minimum, which is −∞ in fp16. Masking with −10⁴ (the classic BERT value) fixes it with no effect at fp32. Tolerance proposed for the ship gate: every golden top-1 unchanged and scores within 0.005.
- **Reproducible:** two conversions give byte-identical `weight.bin` and an identical program; `Manifest.json` (random UUIDs), the conversion-date metadata and protobuf map order differ. Provenance should checksum the weights and the canonical program, not package bytes.

**S14, queries inside Claude's sandbox (SRCH Q2): pass.**
- `MLModel.compileModel` compiles the `.mlpackage` at runtime in 52–67 ms, **no Xcode** (it writes to the temp folder, so the app compiles, not the sandboxed CLI). The CLI loads the precompiled `.mlmodelc`.
- **A Swift WordPiece** matches Hugging Face `tokenizers` on 27/27 texts: golden queries, every fixture file, accents, CJK, emoji, fullwidth, ligatures, control characters.
- **Swift Core ML vectors vs the POC's ONNX:** cosine 1.000000 (fp32), ≥ 0.9997 (fp16).
- **Seatbelt** (no network, writes only in the work folder): every model and compute unit works and writes nothing; but with `.all` (GPU path) Metal Performance Shaders tries to save a cache in the system temp folder, is refused, and the query takes 1.3 s instead of 0.3 s. **The CLI must pick its compute unit, never `.all`.**
- **Real Claude sandbox** (`sandbox.enabled`, Haiku running the binary): fp32 CPU, fp16 Neural Engine, GPU and all units all succeed; no files written under `~/Library/Caches` by it. **fp32 on the CPU is the query path:** load 15 ms, embed 6 ms, exact parity, no accelerators, no caches.

**S15, throughput and corpus (SRCH NFR-1, NFR-3): pass on this Mac (Apple M6, 32 GB).**

| Batch 32 × 300 tokens | CPU | GPU | Neural Engine | All |
|---|---|---|---|---|
| fp32, flexible shapes | 54/s | 237/s | 54/s | 234/s |
| fp16, flexible shapes | 108/s | **667/s** | 109/s | 665/s |
| fp16, enumerated shapes | — | 454/s | 5/s | 5/s |

- Flexible shapes never reach the Neural Engine (its numbers equal the CPU's), and a fixed-shape variant runs it badly (5/s): the model would need restructuring for the Neural Engine. **Indexing runs fp16 on the GPU: about 20× the POC's 34 chunks/s.**
- **Corpus on this Mac:** about 124,000 chunks (project files under `~/repos` ≈ 123,000; transcripts' message text ≈ 700), consistent with NFR-1's 10⁵. Backfill ≈ 3 minutes at 667/s, against ≈ 1 hour at the POC's speed. This isn't the reference (work) machine, and M6 isn't the slowest supported chip; both stay open.
- Mixed precision: the index (fp16) and queries (fp32) differ by cosine ≥ 0.9997. FR-7.3.8 makes the numerical configuration part of the index identity, so record it; ranking isn't affected at this tolerance.

## F-34 · Spikes S4 and S5: CodeMirror 6 live preview in a WKWebView (2026-10-03)

**Pass on everything checkable headless.** CodeMirror is vendored in `Vendor/codemirror` (Geoff, 2026-10-03: fetch it, vendor it): exact versions in the lockfile, a checked-in 528 KB bundle (`dist/cm6.js`) with its licences, rebuilt by `build.sh`. `Spikes/S4Editor` drives it from Swift.

| Check | Result |
|---|---|
| Unedited round trip, byte for byte | legacy `tasks.md` (385 KB; it was 1.2 MB when the plan was written), `about-duo.md` (HTML comments), a 1.2 MB file, a CRLF file: all identical. Open in 1–23 ms. |
| Bold on a selection | changes exactly the selection (+4 characters) |
| Edit in a CRLF file | keeps CRLF everywhere |
| Typing proxy, 1.2 MB file | p50 under 1 ms, p95 1 ms, max 3 ms (budget 16 ms) |
| WebContent RSS, human-paced typing | 41 MB empty, 102 MB with the 1.2 MB file, 129 MB after 1,200 characters at 30 ms each (budget 150) |
| External edit, no local edit | applied; the caret stays on its word |
| External + local edits in different places | merged (three-way, from the last saved text) |
| Overlapping edits | reported as a conflict; nothing applied |
| Agent insert | highlighted ("added by Claude", DL-5) |
| Find | selects the match |

What the spike taught:
- **CodeMirror's `doc.toString()` always joins with `\n`**; only `state.sliceDoc()` uses the configured line separator. Saves must use `sliceDoc()`, and merge diffs must be computed on `\n`-normalised text because CodeMirror counts a CRLF as one position. Mixed line endings can't round-trip and should open read-only (LR-30).
- **Never stringify the document per keystroke.** A dirty check doing `doc.toString() !== saved` cost about 280 MB of garbage over 300 burst keystrokes on the 1.2 MB file. `Text.eq` against the saved tree allocates nothing.
- **Burst-typing benchmarks overstate memory:** 300 back-to-back edits pushed RSS from 106 to 187 MB as a high-water mark that later paced typing barely moved. Human-paced typing is the fair measure. The live preview is the largest per-edit cost; decorations are now reused and rebuilt only when the doc, the viewport or the set of raw lines changes.
- **A hidden web view throttles its timers**, so paced tests are driven from Swift. **`callAsyncJavaScript` before the first navigation finishes never returns**, and **`WKWebViewConfiguration` is copied at init**: message handlers go on `webView.configuration`.
- **Still to check with Geoff at the keyboard:** spellcheck, dictation and Writing Tools inside the editor; the native caret and selection; native menu items driving `duo.exec` with `validateMenuItem`. **S6** (the `swift-markdown-engine` hedge) needs that package fetched; not done.

## F-33 · Spike S7: WKWebView local-only by default, with an allow list (2026-10-03)

**Passes** (`Spikes/S7WebView`, a throwaway package; `swift run` in that folder).

- **Two layers, both needed.** The navigation delegate refuses top-level loads to non-local hosts (and allows allow-listed ones); a `WKContentRuleList` blocks **subresources**, which the delegate never sees. With the rules, a local page's `<img src="https://example.com/…">` never produced a request (no resource-timing entry); without them it did.
- **Content-blocker rules:** block `^https?://`, then one `ignore-previous-rules` per local host. Regex disjunctions (`a|b`) are rejected ("Disjunctions are not supported yet"), and `unless-domain` keys on the *page's* domain, so it would let a local page pull anything. Allow-listed hosts are more `ignore-previous-rules` entries; the list is recompiled when it changes.
- **`isInspectable = true`** sets (the inspector itself needs Safari's Develop menu; not checked headless).
- **WebKit refuses some ports** ("Not allowed to use restricted network port"), and port 0 is one of them: the spike first read the listener's port before it was ready. Duo's local servers must use a known-good port and wait for ready.
- A width check on the blocked image passed with and without the rules, so it proved nothing; resource timing is the reliable test.

## F-32 · Spike S10, second half: `/cd` relocation and retention (2026-10-03)

- **`/cd` from a Duo terminal works** (interactive only): "Moved to …/onboarding-v3". Claude **moves the whole transcript** to the new folder's project directory (nothing left in the old one) and appends `{"type":"relocated","relocatedCwd":"<new folder>"}`; later records carry the new `cwd`, earlier ones keep the old.
- **Duo follows it:** each refresh works out where every filed session actually lives (the live beacon's cwd, else the directory its transcript is filed under), lists it there, and moves its index entry to the new project's `.duo/sessions.json` with `provenance: relocated-from:<old project>`. Verified live: the session moved from checkout-redesign's index to onboarding-v3's and shows under onboarding-v3. Pointers move; no transcript is rewritten (DL-41 R1).
- **The encoder's self-calibration broke on the relocated transcript:** its first `cwd` is the old folder but it lives under the new one's directory. Calibration now reads the last `relocatedCwd` (head and tail, 64 KB each) before falling back to the first `cwd`. 13/13 again plus the relocated file.
- **Retention:** `cleanupPeriodDays` is unset here (30-day default); 45 transcripts, the oldest 7.5 days. Any Claude process's sweep deletes old transcripts, Duo's included, so Duo can't fix this with its per-session settings. Logged as Q-18 with options; nothing built.
- 94 checks pass.

## F-31 · Spike S11: fork lineage comes from shared message ids (2026-10-03)

**Passes.** Haiku sessions in `.build/s11`: A, then B = `--resume A --fork-session`, then C = a fork of B.

- **No explicit link.** A fork's transcript has no "forked from" field. Claude copies the parent's records with the **same message `uuid`s and the same timestamps**, rewriting only `sessionId` (18 shared records for a one-turn parent).
- **Thread membership:** the first `user` record's `uuid` is the same across a thread, and it sits in the head of the file (a bounded read, LR-9).
- **Fork point:** the fork's first record of its own has a `parentUuid` pointing into the copied part.
- **Which session is the parent:** copied timestamps can't tell sessions apart, but each file's first record of any kind (`queue-operation`, `mode`) is stamped with that session's own start. Copies flow forward in time, so a session's own records are those no earlier-started session holds, and the parent is the latest-started earlier session holding the fork point.
- `ForkLineage` implements this; checks cover a fork, a sibling fork and a fork of a fork, and on the real transcripts it reports B ← A and C ← B. The thread UI waits for Phase G's design (§3.5).
- **A Haiku and a Sonnet session given ordinary tasks didn't use `duo2 session note`** (F-30's guidance). Narration stays optional; the hooks already give state and summaries.

## F-30 · The main window is AppKit now; duo2 talks back (2026-10-03)

- **No-window launches, cause narrowed:** with traces, the bad launches show `didFinishLaunching windows=0` and nothing at +3 s, so SwiftUI never made the `Window` scene's window. `.defaultLaunchBehavior(.presented)` and `.restorationBehavior(.disabled)` didn't help, and the watchdog's reopen (activate, then `applicationShouldHandleReopen`) fired and still produced no window. Re-bundling before each launch didn't reproduce it on demand (0 of 5).
- **Fix: Duo makes its one window in AppKit** at `didFinishLaunching`: an `NSWindow` hosting `RootView` in an `NSHostingController` with `sceneBridgingOptions = [.toolbars]` (the SwiftUI `.toolbar` still builds the toolbar), `.fullSizeContentView`, unified compact toolbar, and an app delegate for Dock reopen. The SwiftUI app keeps a `Settings` scene only to carry the menus (`DuoCommands`; the Go and View menus are present).
- **The hosting view must be laid out at the design size first** (`sizingOptions = []`, frame set before it joins the window). Otherwise the split view's first layout happens at SwiftUI's ideal size and keeps those proportions on resize: Home measured 382.5 pt wide instead of 340. With that, all six fixture captures are **0 pixels different** from the SwiftUI-window build.
- **`duo2 status`** (LR-53 orientation) and **`duo2 session note|next`** (LR-5): narration is stored in the project's `.duo/sessions.json` and shown as the card summary when the hooks give none. `duo2` identifies its session by `CLAUDE_CODE_SESSION_ID`, which Claude sets for its Bash children and which stays correct after `/clear`; `DUO_SESSION_ID` is the fallback.
- **Session guidance** goes to every session Duo starts through `--append-system-prompt`, generated from the command table. Haiku given a file-writing task didn't narrate; untested on the default model yet.
- **Permission cards name the file** for Write/Edit (`Allow Write to refunds-note.md?`), not just the tool.
- **A duplicated session row appeared once** in a dump (`home/Color preference question` twice) and didn't reproduce with ids printed. Applying a snapshot now keeps one row per session id.
- **Not checked yet:** pressing menu items. With the screen locked, macOS refuses Accessibility actions, so the menus could be listed but not pressed.
- 91 checks pass; `scripts/check-sandbox.sh` passes.

## F-29 · Spike S8: duo2 reaches Duo from inside Claude's sandbox (2026-10-03)

**Passes, with a different transport than DL-15 assumed.** Tested with sandboxed headless Haiku sessions (`sandbox.enabled: true`) and then reproduced without tokens under Seatbelt (`scripts/check-sandbox.sh`, Geoff's suggestion):

| Sandbox setting | Loopback TCP | Unix socket | Write to `$HOME` |
|---|---|---|---|
| default | blocked (EPERM) | blocked (EPERM) | blocked |
| `network.allowLocalBinding: true` | works | blocked | blocked |
| `network.allowedDomains: [localhost]` | blocked | — | — |
| `excludedCommands: [duo2]` + allow rule | blocked | — | — |
| `network.allowUnixSockets: [<socket>]` | — | **works for that path only** | blocked |

- **Claude's macOS profile** (from the binary's template) is deny-by-default and turns each allowed socket into `(allow network-outbound (remote unix-socket (subpath "<path>")))`; `allowUnixSockets` is honoured from managed, `--settings` and user settings, not project settings, so Duo's per-session file can grant it. Decision: DL-43.
- **Claude Code withholds its "device tools"** in a session whose sandbox allows any Unix socket or local binding (its own refusal strings say so). Duo's allowance therefore costs Duo-started sessions those tools when the user's sandbox is on (C-17).
- **`duo2`** (Foundation-only, in `Duo.app/Contents/Helpers`, on PATH in Duo terminals with `DUO_SOCKET`/`DUO_TOKEN`): `help`, `doctor`, `ping`, `needs-you`, `projects`, `open`, from one command table (LR-52). Wrong token refused; bad command exits 64; app unreachable exits 69 with a pointer to `doctor`. From a Duo terminal, Haiku ran `duo2 projects` with no approval prompt (`Bash(duo2:*)` is allowed per session) and got the live project list.
- **`/clear` (and `/resume`) change the session inside one process.** Duo kept the tab keyed to the old id and wrote the new session's hook events into the old file. Now hook events go to the file of the payload's `session_id` (first key only, so text in tool input can't redirect them), and each refresh re-keys a terminal whose process reports a new id, filing it in the same project with `provenance: continued-from:<old id>`. Verified live: `/clear` then a prompt gave a tab titled "Say hello", re-keyed and filed.
- **No-window launches (F-26) recurred twice** with the trace showing `didFinishLaunching windows=0` and none at +3 s. `.defaultLaunchBehavior(.presented)` and `.restorationBehavior(.disabled)` didn't stop it. A watchdog now activates the app and asks SwiftUI to reopen when no window is visible 0.5 s after launch; not yet seen firing (11 launches since, all with a window). The capture path's `exit()` now ends sessions and removes the endpoint first.
- 89 checks pass; `scripts/check-sandbox.sh` passes.

## F-28 · Disk reads can block: refresh off the main thread, stay out of protected folders (2026-10-03)

- **Reads in `~/Desktop`, `~/Documents` and `~/Downloads` block** until the macOS privacy prompt is answered. With the screen locked, `ls ~/Documents` from a Claude session hung until a 5 s alarm killed it, and a snapshot scan rooted at `~` never returned. `Pictures`, `Movies`, `Music` and `repos` answered at once.
- **The refresh ran on the main thread**, so a workspace in `~/Documents` (a common place for a PM's work) could freeze Duo on its first scan. It now builds the snapshot in a detached task, one at a time, and applies it on the main actor. Live mode starts from an empty snapshot, never the design fixture.
- **Discovery skips those protected folders** (and `Library`, `Pictures`, `Movies`, `Music`) when it meets them below the root. A workspace inside one is unaffected; the root itself is never skipped. A scan of `~` now takes 4 ms.
- **Cost of a refresh:** 2.5 ms for the 7-project demo workspace, 4–5 ms for `~/repos` and `~`, warm (first scan 8–28 ms); reading beacons 0.2 ms. The 2 s poll is cheap; file watching moves down the list.
- **Resumable count:** idle sessions with a live process are no longer counted in `n idle` / `n idle, resumable` (C-16).
- No trust dialog for a new session in `.build/ws/payments/checkout-redesign`: trust follows the enclosing git repo here (S1 saw it per folder outside a repo).
- **Home is remembered (DL-42):** the chosen Home folder is stored in `Duo/state.json`. Verified live: after a run chose `.build/ws/home`, adding a newer `zz-other/HOME.md` didn't move Home. The notice naming competing Homes, with "Use this one", isn't designed (§13) and isn't built.
- 85 checks pass.

## F-27 · Phase E3: session titles from the transcript (2026-10-03)

- **Beacons say whether a name is stable.** `nameSource: user` marks a `/rename` or Desktop title (stable); `derived` names (`home-38`, `repos-f7`) change per process. Duo uses the beacon name only when it is `user`.
- **Otherwise LR-6's ladder over the transcript:** `custom-title` → `ai-title` → `summary` → slash command (`<command-name>`) → first real prompt with harness tags stripped (meta records and tool results skipped) → short id. Claude writes `ai-title` records within the first turn ("Color preference question" for the S9-style test). Reads are the first 64 KB plus the last 256 KB, cached by size and mtime.
- **A session with no transcript is "New session"**: it was started and never used (F-25), so a short id would be the only alternative.
- Verified live: Home reads "Color preference question" across relaunches; the unused checkout-redesign session reads "New session". Review image: `docs/plan/review/phase-e/live-titles.png`. 84 checks pass.
- **The no-window launch (F-26) didn't recur** in six instrumented launches. Scripted runs now trace `init`, `didFinishLaunching`, `configure` and the window list at +3 s to stderr, so the next occurrence shows which step was missing.

## F-26 · Phase E2: hooks give the question, the answer and the review state (2026-10-03)

Every Claude session Duo starts or resumes gets `--settings <events>/<id>.settings.json`. Its hooks (SessionStart, UserPromptSubmit, PermissionRequest, PostToolUse, Notification, Stop, SessionEnd) append `{"at":…,"e":<payload>}` lines to `~/Library/Application Support/Duo/events/<id>.jsonl`. They print nothing, so they can't answer a prompt. Verified end to end on Haiku (DL-33) through `scripts/run-live.sh`, with the screen locked:

- **Needs you, with the verbatim question:** after an AskUserQuestion, the session read `needsYou`, question "Which color do you prefer?", options Red/Blue, within one 2 s refresh. The action column shows the card and the toolbar shows `1 need you`. Review image: `docs/plan/review/phase-e/live-needs-you.png` (Home sessions use the designed "Waiting in the Home terminal" card).
- **Ready for review:** after answering and moving to another project, the session read `readyForReview`, with the reply's first line as the summary (markdown bold stripped).
- **Seen mark:** looking at the session (its tab on screen during a refresh) writes `seen[id]` to `Duo/state.json`, and the next refresh shows it idle. Writes happen only when there is something to clear.
- **Resume keeps the finished turn.** The resumed process fires `SessionStart` (`source: resume`); the first version treated that as a new turn and lost "ready for review". Now only `UserPromptSubmit` clears it.
- **Claude's session names aren't stable:** the beacon `name` was `home-38`, then `home-0e`, `home-55`, `home-ea` across relaunches of the same session. Titles need the transcript (LR-6's title ladder) before they appear in the UI as names people will recognise.
- **A launch with no window (once):** one launch ran the live refresh with no window at all, so the scripted capture never fired and `open -W` waited forever. It didn't reproduce in five later launches. Like F-19, not explained; `scripts/run-live.sh` bounds every run and quits through Apple Events.
- 78 checks pass, including the real hook command run through `sh` with pretty-printed payloads.

## F-25 · Phase E: live workspace on real folders (2026-10-03)

`Duo --workspace <root>` builds the same snapshot the fixture provides from real sources and refreshes it every 2 s: `PROJECT.md`/`HOME.md` frontmatter (goal, health slug, next), topic from the parent folder, each project's `.duo/sessions.json`, and beacons. Verified on `.build/ws` (`scripts/make-demo-workspace.py`):

- **Projects, topics, health and next** render on the map from frontmatter alone. Review image: `docs/plan/review/phase-e/live-home.png`.
- **`+ New session`** mints an id, writes it to the project's index first (atomic, byte-equal writes skipped), then starts `claude --session-id <id>` in the folder. The session appears under the name Claude gives it (the beacon's `name`, e.g. `checkout-redesign-ba…`). Review image: `live-new-session.png`.
- **Sessions started outside Duo** appear in the project whose folder contains their `cwd` (resolved paths), without being written to the index.
- **A session that was never used can't be resumed.** Claude writes the transcript on the first message, so `--resume <id>` fails with "No conversation found with session ID". Duo now resumes only when `ClaudeStorage.transcript(sessionId:cwd:)` finds the file, and otherwise starts fresh with the same `--session-id`. Seen with the Home session after a relaunch; fixed and re-verified (the TUI starts in `~/…/.build/ws/home`).
- **Claude reports `idle` for a session sitting at its prompt.** The tab strips filtered on live states, so an open session lost its tab. Tabs now show live sessions plus any session Duo holds a terminal for (C-16).
- **Captures with the screen locked:** computer-use and `screencapture -l` both fail while the session is locked and the display asleep. Duo's frame-view fallback draws the panes but not the terminals' layers (blank white). `--then …,dump` with `open --stderr` reads the terminal text instead.
- **No orphans:** quitting through Apple Events leaves no `claude --session-id` / `--resume` processes.
- **Fixture mode is unchanged:** 0 differing pixels in all six states against HEAD before these changes. 58 checks pass (index round trip, byte-equal skip, snapshot attribution by cwd, archived sessions hidden, groups by id, counts).

## F-24 · Spike S10: the storage encoder calibrates against this machine (2026-10-03)

`ClaudeStorage.encode` (non-alphanumerics → `-`; over 200 characters → first 200 + `-` + base-36 `|Java hashCode|`) matches **13 of 13** folders in `~/.claude/projects`, with 0 collisions and 0 mismatches. It runs as a check (`DuoChecks`, 34 checks now) and is the self-calibration CONS §6.3 requires before any physical operation. No path here exceeds 200 characters, so the hash branch rests on the path-binding research's reproduction until a long-path session exists.

## F-64 · Duo opens on every session; Home is the container; Move into Home keeps sessions (2026-10-04)

- **Live by default (DL-82).** A plain launch lists every session in Claude's logs: 13 folders and 43 sessions on this Mac, grouped by parent folder (`~`, `~/repos`, `~/DuoAcceptance/…`). The fixture is only for `--state`/`--fixture`/capture runs. `--workspace none` runs live with no Home whatever Duo's state says (scripted runs); `--workspace <dir>` still sets Home for one run.
- **Projects outside Home are found from the sessions' folders:** a cwd at or under a folder with `PROJECT.md` (never the user's home folder or above) makes that folder a project, so `repo/src` sessions belong to `repo`.
- **Home is the root (DL-85):** a `HOME.md` at the root makes the root Home, and scanning carries on inside it. Home claims only sessions run in its own folder; a folder inside Home without a project file is listed as a folder, not swallowed by Home. Attribution is deepest-project-wins everywhere (it used to depend on scan order).
- **The map wraps (DL-83).** `ViewThatFits` over row layouts, most columns per row first. Columns need `idealWidth: 220`: without it a tile's untruncated path made every row "not fit" and the map fell to one column.
- **Move into Home, on fakes** (`~/DuoAcceptance/movetest`, two planted sessions, one run in a subfolder): `duo2 home set` → `duo2 project move-into-home notes-proj` moved the folder and both transcripts (Claude's buckets for the new paths), and the project still listed both sessions; `duo2 undo` put the folder and transcripts back. The migrator leaves **empty bucket folders** behind for both paths after a move and its undo; Claude ignores empty buckets, so they're only clutter (a sweep can come with the curation surface).
- **Scripted `duo2` against a private instance needs `DUO_TOKEN` as well as `DUO_SOCKET`**, both from `Application Support/Duo/endpoint-<pid>.json`. With only `DUO_SOCKET` set, `duo2` silently falls back to `endpoint.json`, the user's own Duo (C-18): a test's read-only `projects` reached Geoff's Duo this way. Test scripts must refuse to send unless both point at the private instance.
- 210 checks pass, including ten new ones for Home-at-root attribution, topics by folder and no-Home listing.

## F-65 · Session links, nested projects, first words, Open-then-past (2026-10-04)

Built from the decision path page (DL-87 to DL-91):
- **Session links.** `duo2://session/<id>`. Copy Link on every session's right-click menu, search's "Copy Markdown link" on a session result, and `duo2 session link <session>` give `[title](duo2://session/<id>)`. In the editor a click on a rendered link (its line not showing raw Markdown) opens it, as Obsidian's live preview does; ⌘-click opens from anywhere. Session links focus or resume the session, web links go to the browser, relative links to files open them in Duo. Opening a session linked from a note in the same project keeps the note on screen. A `duo2://session/…` URL opened from another app (the system routes the scheme to Duo) does the same. Live check on the acceptance fixtures' new task note (`checkout/tasks/exec-review-prep.md`): a synthetic click on the link resumed "Interview synthesis notes" with the note still open.
- **Nested projects** sit beside their outermost enclosing project in its column (`checkout/docs/inner` is in Payments). Discovery no longer stops at a project folder.
- **Untitled sessions**: the first prompt rung of the title ladder is quoted; with no prompt yet, `Session h:mm a`.
- **The session list** is built as sections (`SidebarRow.sections`): Needs you, Open (`hasOpenTerminal`), Today / This week by the wait text, Earlier as a fold, then the Archived fold. In fixture states nothing has a terminal open, so the target's "Working" section now shows under "Today" (`project-compare.png`), by decision.
- 215 checks pass (new: list order, nested topics, quoted first words, start-time names).

## F-66 · Tasks as notes with linked sessions (2026-10-04)

- `TaskNotes` reads `tasks/*.md` (title from `title:`, else the first `# ` heading, else the filename; `status:`; ids from `sessions:` items, links or bare) and edits only the `sessions:` key: appends to a block list, turns an inline list into a block list with the same items, adds the key before the closing fence, or adds a frontmatter block to a note with none. Everything else in the note stays byte for byte (checked), CRLF kept.
- In the snapshot a task is a `Fixture.Group` with `task:` set, built from the note's links to the project's sessions, so it folds, threads and sorts like a group (mixed by urgency, DL-93). A note linking no listed session isn't a row.
- Live check on the acceptance fixtures through a private instance: `duo2 task make <session> --title …` wrote `refunds/tasks/refund-edge-cases.md` and opened it; `duo2 task add` appended the second link; the list showed `Refund edge cases · task · 2`.
- 222 checks pass (8 new for task notes).

## F-67 · Resume offered an old session; a stray dot (2026-10-04)

- The console's "No session open" offered **Resume <first listed session>**, which in a project whose sessions came from history was the oldest (reading offered note 7 of 9). It now offers the most recently used one.
- A project with health but an empty `next:` showed `On track ·`. Empty parts are dropped.
- Found while checking the walk's updated cards on the fixtures (DL-96). The walk now has 101 features; four existing cards were rewritten for DL-83/DL-91 (folder columns, the Open-then-past list).

## F-68 · Restore on relaunch (LR-58) (2026-10-04)

- What's open is saved to `Application Support/Duo/restore-<home>.json`: the project on screen, each project's Claude session tabs (by id, in tab order), its open documents and right-pane tab, the console tab, Home's tab, and both left-pane collapse states. Written when it changes (at most every 5 s, from the refresh) and on quit, so a crash loses little.
- One file per Home (a hash of its path; `restore-no-home.json` without one): a run on another workspace, like the acceptance fixtures, neither reads nor replaces the user's.
- A file from a newer Duo, or one that doesn't decode, is ignored (versioned envelope, graceful downgrade).
- On launch, after the first snapshot: documents that still exist reopen; sessions resume by id, except any now running in another app (never two writers, LR-8) or no longer listed.
- Off in capture and scripted runs unless `DUO_RESTORE=1`. Live check on the fixtures, two launches: the first resumed a session in checkout and opened `tasks/exec-review-prep.md`, then quit; the second came back in checkout with that session resumed (`restore: reopened 1 session(s) in 1 project(s)`) and the note open.

## F-69 · Update notice until Sparkle (2026-10-04)

- Release builds ask GitHub (`/repos/dudgeon/duo-v2/releases/latest`, unauthenticated, 10 s timeout) 8 s after launch, never in capture runs. A newer release is offered once per version as a confirmation (Download opens its release page; Later remembers it in `DuoState.skippedUpdate`). Development builds (version 0.0.1) check only when asked.
- Duo › Check for Updates… and `duo2 update` always answer: up to date, newer (with the link), or couldn't reach GitHub. Live: `duo2 update` on a dev build answered "Duo 0.1.2 is available (this is a development build)".
- Versions compare numerically (`0.1.10` > `0.1.9`); a pre-release sorts below its release.

## F-70 · Tasks day to day (2026-10-04)

- **+ New task** beside + New session (and `duo2 task new <title> --project <p>`) writes `tasks/untitled-task.md` (or the title's slug) with `sessions: []` and opens it.
- **Tasks · n** fold under the session list: the project's open tasks with no listed session yet; a line each (box, title, status past `open`), opening the note; right-click for Open Task Note and **Status ▸**.
- **Status ▸** (task rows, task lines, `duo2 task status <task> <status>`): rewrites only `status:`; done or dropped adds `completed: <date>`, reopening removes it, so a reopened note is byte for byte what it was (checked). Done and dropped tasks leave the lists. Task rows show their status when past open.
- **Open tasks · n** at All projects, under Needs you and Ready for review: every open task across projects with its project and status; a click opens the project on the note.
- `duo2 task status` reads the notes from disk, not the snapshot: a task made a second earlier was "not found" (the snapshot refreshes every 2 s).
- Also: the stray `On track ·` dot was in the map tiles and search details too (F-67 fixed only the session list).
- Live on the fixtures: two new tasks in refunds (one set to waiting) showed in the Tasks fold; checkout's task set to review; All projects listed all three with status. 231 checks pass.

## F-71 · Browser tabs and the allow list (Phase K, ENH-8) (2026-10-04)

- A browser tab is a right-pane tab (`web:<id>` among the project's open documents) with its own web view on the **default** website data store, so allowed sites stay signed in. A plain bar (stand-in for DB-20): back, forward, reload/stop, the address field, Open in Browser. Tab title follows the page (KVO on `title`: navigation callbacks alone left "New Tab").
- **Allow list (DL-3):** `Application Support/Duo/allowed-sites.txt`, one host per line, comments kept; a host allows its subdomains; localhost and `*.localhost` always. A page from any other site isn't loaded: the tab says so with **Allow <host>** and **Open in Browser**. Frames inside an allowed page load freely; links to other sites go out through `openLink`.
- Links to allowed sites from Markdown notes and from local HTML pages now open in a browser tab beside them; others still open in the system browser.
- **New Browser Tab** ⌥⌘T (File, right-click `+`), **Open Location…** ⌘L (DL-99). `duo2 browser open [url]`, `browser allow <host>`, `browser sites`. Browser tabs come back on relaunch with the address they had (F-68's restore file gains `webTabs`).
- Live, private instance: `duo2 browser open localhost:8765` loaded a test page titled in the tab; `duo2 browser open example.com` showed the not-allowed state with both buttons. Allowing was checked against a temporary list, so Geoff's own allow list is untouched (empty). 236 checks pass.
- Not yet: the element picker and Send to Claude on web pages (they work on local HTML), page-driving verbs for Claude (LR-45), Google Docs reading (DL-7).

## F-72 · Browser tabs get the picker, Send to Claude and page driving (LR-44, LR-45) (2026-10-04)

- The picker, selection and element screenshots moved out of `HTMLViewer` into `PageHost`, which `HTMLViewer` and `WebTab` both adopt; the model asks for `visiblePage` (a browser tab, or local HTML), so the picker bar, Send Selection, the right-click Send / Select Element items and `duo2 html pick|element|selection|stop|reload` work on either.
- On browser tabs Duo's picker script and message handler live in `WKContentWorld.defaultClient`, apart from the site's own scripts: a page can't see `__duo` or post fake `picked` messages. Local HTML keeps the page world (it's the user's own file).
- Page driving for Claude: `duo2 browser read [selector]`, `click`, `fill`, `wait`, `screenshot`, `go`, `back`, `forward`, `tabs`, `close`, on the tab on screen or `--tab <id>`. They refuse on a page that isn't allowed. No arbitrary script (LR-45 lists eval; left out because these tabs carry the user's logins). `fill` sets the value through the element's native setter and fires input and change, so framework-bound fields notice.
- Live on a localhost form: read the page, filled `#name`, clicked `#go`, waited for `#out.done`, read "Hello, Geoff", saved a real screenshot of the page, picked `h1` (described with selector, text, box), listed the tab, and `browser go example.com` refused.
- Still open from LR-45: the accessibility-tree fallback for canvas apps (Google Docs, Sheets, Figma; DL-7), and keys. Web views draw blank in `--capture-window` captures (F-25), so screenshots come from WebKit's own snapshot.

## F-73 · Moves no longer leave empty Claude folders (2026-10-04)

- After a migration commits, the Claude buckets its moves emptied are removed; after an undo, the ones the undo emptied. Only a folder directly in Claude's `projects/`, only when nothing (but `.DS_Store`) is left. F-64 had found both buckets left behind after Move into Home and its undo.
- The first run of the new check caught a real bug: undoing a relocate moved the transcript back into a bucket the sweep had removed. Undo now recreates the bucket first. 238 checks pass.

## F-74 · A design system for Claude Design (2026-10-05)

- **How Claude Design reads one:**
  - The design agent opens a design system's `project/README.md` and `project/tokens.json` first, never the rendered page.
  - It copies the tokens into its own canvas, and mounts `window.<Namespace>` components when the README names a bundle.
  - Tokens must be **lists** (`{"tokens":[{"name","value","usage"}]}`, colours per theme). A DTCG name-to-value map is unreadable there: the family shows empty.
  - Names are unique across families, and each non-type family holds at most 60.
  - Component previews don't run without `components/bundle.js`. For a SwiftUI app it only declares the namespace (`window.Duo`), and the previews are static recreations from `tokens.css`.
- **Built:**
  - `docs/design/system/` mirrors the type's `project/` layout: a README brand book, Model, Surfaces and Working on Duo's design sections, 24 components (README plus preview, each starting with a status line), a cover, and four asset groups (Screens, Targets, Glyphs, Icons, 39 uploads).
  - It's published as https://claude.ai/artifact/QMapKeLYS3TVV36QKEc6MH. `design-system.json` in the repo keeps the index and its upload ids.
- **Generated, checked:**
  - `scripts/gen-design-system.py` writes the system's `tokens.json` (55 colours, 11 type styles, 28 spacing, 7 radii, 61 sizes, each with a usage note, Swift names kept) and the icon and glyph SVGs (exact path data, ink baked in) from `build-handoff/tokens.json`.
  - DuoChecks fails when they're stale.
- **Token cleanup:**
  - The frontmatter handoff's sizes and eight property icons are merged into `tokens.json`, plus the dash pattern and the folder and task marks.
  - The generator emits `DuoShadow` (the popover shadow, radius = blur ÷ 2) and `dashPattern`. The four literal popover shadows now use `.duoPopoverShadow()`.
  - `JumpField` is renamed `SearchField` (DL-80).
- **Screens on sample data only:**
  - `DUO_SUPPORT_DIR` stands in for Application Support (Duo's archive, state, journals, search index, socket). With `CLAUDE_CONFIG_DIR` set to a copy of the fixtures' buckets (`cp -Rp`, to keep dates), a capture shows nothing of the user's own sessions.
  - Without it, Duo's archive copies listed the user's real folders.
  - A fresh `CLAUDE_CONFIG_DIR` shows Claude Code's first-run and trust screens in terminals, so the All projects shot collapses the left pane.
- **Found while capturing:** a task row's name was squeezed to "Exec re…" by its pill and status. The name now has layout priority and the status gives way.
- **Docs:**
  - Status banners on the superseded handoffs and briefs (what changed, by which DL).
  - `docs/design/README.md` indexes every design doc with its status and the precedence.
  - `explorations/README.md` lists what decided each page.
  - CLAUDE.md points at the system.
- **Left:** about 200 literal paddings and frames in views (inventory: SearchView 80, ProjectPanes 35, AllProjectsPanes 30, …), and system fonts outside `duoText` in a few stand-ins (C-19).
## F-75 · The migrator's encoder self-calibration refused moves on a healthy machine (2026-10-04)

- **Observed (Geoff, work Mac):** Move into Home… stopped with "Duo's folder naming doesn't match Claude's here: -Users-…-Repos-aipm holds sessions from /Users/…/Repos/aipm/aipm-knowledge-base". The encoder was right; the check was wrong. `Migrator.calibrationProblem` was a second, older copy of the calibration that took one arbitrary transcript per bucket and compared its raw first `cwd`, ignoring `relocated` records (the F-32 fix only reached `ClaudeStorage.calibrate`). A bucket can rightly hold a session whose first cwd is elsewhere: a `/cd`'d session keeps its old head cwd, and a fork opens with its parent's records from the parent's folder (F-31).
- **Changed:** the migrator now uses `ClaudeStorage.calibrate` (now taking the projects folder), which passes a bucket when any of its transcripts records a cwd that encodes to its name: where it was filed after `/cd`, its first cwd, or its last. `planRelocate` and `planFolderMove` check calibration too, so a real mismatch is reported before the confirm dialog rather than as "Stopped and put back" after it. New check reproduces the fork and `/cd` cases (fails on the old code). 222 checks pass.

## F-76 · Slice 2 built to its screens (2026-10-05)

- **Built (DL-100):** the session list's task rows (task box, "status · n", no wait of their own) and indented Tasks fold; the map's OUTSIDE HOME section with path columns (`~/Desktop/…/interviews`); no-Home copy with Not Now (remembered in `state.json` as `homePromptDismissed`; the pane starts collapsed until a Home is chosen) and no session row; needs-you reasons (`· permission`, `· question`, `· plan to approve`), 6-line question clamp with "… more", "Nothing needs you."; **Move into Home** and **New project** as Duo's own sheets (`Shell/Sheets.swift`), drawn in the window under the toolbar with the map at 55%, never a system alert, so a scripted run can't block on one; the **properties block** in the editor (`duo-editor.js`): heading, ground block, muted names, a task note's status popup (native menu, writes `status:` and `completed:` in the buffer, F-70) and `+ Add`, session lines with live glyph and wait (states pushed from Swift as `window.__ctx`), and the glyph before session links in the text.
- **New verbs:** `duo2 project new <name> [--goal] [--into <topic>] [--session]`; `duo2 project move-into-home <p> --into <topic>`. Tried on the fixtures with a scratch config and support folder: both work, both undo, fixtures and buckets byte-identical after (`diff -rq` against a backup).
- **New tokens:** `size.sheet` (top 38, padding 20, widths 460 / 520, label column 96, row gap 12, field 24 × 8 padding, dimmed opacity 0.55). The slice said none; the sheets need them.
- **Measured:** the task note's block against `task-note.html` in a browser at 460: block top, edges, every row (22 pitch) and the rule land on the target's pixels; the status chip sits 1 pt right (a mono space where the target has a 6 pt gap). Window captures still can't draw web views (F-25), so the editor is checked in a browser page, not in `--capture-window`.
- **Parity scanner bug:** `// not an action:` never exempted anything: in `if let m = …, a || b` the `||` only runs when the `if let` binds. Fixed; view-only clicks (the clamp, the sheet's click-catcher) now say so.
- **Socket path limit:** a `DUO_SUPPORT_DIR` deep in the scratchpad gives a socket path over 104 characters and `duo2` refuses it. Use a short folder for scripted `duo2` runs.
- **Not built from DB-16:** type icons in the gutter, suggestions, Tab between values, the type menu, the date picker, invalid-YAML state, folding. The task-note target draws none of them; the frontmatter handoff still holds them.

## F-77 · The properties block, built (2026-10-05)

- **Built (DB-16, `frontmatter-handoff/`; brought in with S2-5, DL-100):** on every Markdown document with frontmatter, the block of `frontmatter.html`: fences in `text2`, a type icon in the gutter (text, list, number, checkbox, date, date and time, link, read from how the value is written), the value's control (a checkbox that rewrites `true`/`false`; a calendar button; a link folded to its underlined title away from the caret, with an open button), the fold chevron (remembered per document in `state.json`, `foldedProperties`), `+` for a new line. Tab and ⇧Tab move between values, Tab past the last starts a new line for a name, Tab on an empty new line removes it; ⌥esc offers suggestions (or the calendar on a date); ⌘↩ opens the line's link; ⌥↑ ⌥↓ move a line. The type menu (native, a tick on the current type) rewrites the value when it can; a value that isn't a date opens the calendar. Dates use the Mac's `NSDatePicker` in a popover and write the ISO form. Suggestions: names used in this project's notes and Home's (`PropertyCorpus`, read off the main thread at most once a minute), this project's first, most used first, `New property "…"` always last, with the key line; values used under the same name. Invalid YAML (an unclosed quote or list, a line that isn't a property) outlines the line, says `Not valid YAML · line n` in the heading and why under the block, and drops icons and controls from that line on; a name being typed on the caret's line isn't an error. A line Claude changed has the `selected` fill and "changed by Claude".
- **`duo2 doc prop list | get | set | remove | type`** works on the showing document through the editor; Claude's sets are highlighted and revertable like its other edits. Tried on the fixtures' checkout `PROJECT.md`: every verb, and the file on disk after autosave; restored after.
- **Measured** against `frontmatter.html` and `frontmatter-new.html` in a browser at 460: block top, every row, the gutter icons, the checkbox, the date and open buttons and the rule land on the target's pixels; the suggestion panel matches its rows, details (`list · 6 documents`), hairline and key line.
- **Two looks:** the approved task-note screen (S2-5) draws no fences, icons or chevron; `frontmatter.html` draws all three. Each is built to its own screen (CLAUDE.md: the screen wins); Q-33 asks whether task notes should take the general look.
- **Not built:** natural-language dates typed into a date's text ("next fri" turns into ISO only through the type menu or `duo2 doc prop type`), Return-on-empty-item ending a list, and the type menu's VoiceOver labels beyond the icon's. Format › Add Properties (frontmatter-none) waits for the menu bar's design (DB-26).

## F-78 · Moved and missing project folders (DB-8, LR-23) (2026-10-05)

- **Before:** a folder moved or deleted outside Duo made its sessions vanish from every list ("archive only"), and a moved project that carried its `.duo` list showed its sessions in the new place but they didn't resume: Claude files a session under the folder it ran in, and `--resume` from the new folder doesn't find it.
- **Now:** a folder that's gone keeps its tile, kind `missing`, with what happened: "Folder not found", "Moved to …" (found by another folder carrying its `.duo` list, or a folder of the same name, in Home or near the old place; `MissingFolders`, cached a minute), or "On “Disk”, not connected". Only recent ones (a session in the last 14 days), found ones and unmounted ones show; hidden and system paths never. Its sessions stay listed; their terminals don't start until it's located. A project whose sessions are still filed under where it was says how many.
- **Actions:** Use New Place, Locate Folder… (open panel), Reconnect Sessions…, Remove from Duo; `duo2 project reconnect <p> [--to <folder>]` and `duo2 project forget <folder>`. Reconnecting is `Migrator.planReconnect`: the sessions follow the folder the way Claude's /cd moves them, without moving the folder, journaled, verified, undoable. Resuming one stray session reconnects it first, automatically (journaled; `duo2 migrations` lists it).
- **Pulled forward:** "reconcile a moved project" was v1.1 (§3a). It's in v1 because the migrator was already built for Move into Home (DL-85) and without it a moved project's sessions don't resume, which fails v1's test (never lose a session).
- **Tried** on the fixtures with a scratch config: renamed → "Folder not found"; moved into Home's `research/` → "Moved to …/research/scratch"; `duo2 project reconnect scratch` moved both transcripts; `duo2 undo` put them back; fixtures and the scratch Claude folder byte-identical after. New check: reconnect maps nested paths, undoes, refuses a folder that isn't there.
- **Not done:** the Trash (macOS guards `~/.Trash`; listing it can raise a permission prompt, F-54), so "In the Trash" and Put Back from S3-2 wait. The look is a stand-in until S3-2 (Q-32).

## F-79 · Sessions Duo starts can message each other through Claude Code (2026-10-05)

- Duo strips the parent's `CLAUDE_CODE_*` (including its messaging socket and token) from children (`ChildEnvironment.make`), but each child binds **its own** cross-session inbox. Live beacons in `~/.claude/sessions/` for Duo-started sessions (e.g. `home-4d`, entrypoint `cli`, in the acceptance workspace) carry a `messagingSocketPath` and `peerFeatures: notify_idle, reply_across_default_dirs, artifact_yield`, on 2.1.289.
- So any session (in Duo or not) can `SendMessage` a Duo session by name, and `notify_when_idle` works. Claude Code delivers between tool calls, or **starts a new turn** when the target is idle; it's plain text and can't approve anything. Delivery is held when exactly one side bypasses permissions.
- Needs Claude Code ≥ 2.1.224 (`notify_when_idle` ≥ 2.1.236). The beacon's `version` and `peerFeatures` are enough to gate on; Duo doesn't decode either yet.
- Background for ENH-9 (director agent), `docs/research/director-agent.md`.

## F-80 · Search reads every Claude folder (DL-103) (2026-10-05)

- **Was:** after F-53, only folders with a PROJECT.md had their files searched; folders with sessions contributed their sessions alone, and `CLAUDE.md`-only folders weren't known to Duo.
- **Now:** `ProjectDiscovery.scanAll` finds `CLAUDE.md` folders in the same walk as projects (none inside a project or another `CLAUDE.md` folder, so a monorepo's nested ones don't each get a tile); `LiveSnapshot` lists those without sessions as folder entries; the indexer reads every folder on the map.
- **Found on the way:** Home's folder was indexed whole, so every project's files were stored twice (under the project and under Home), and a nested project's files the same. `FileSource.files(in:excluding:)` now leaves out the other searched folders inside a root; on the demo workspace Home covers 1 file, its own.
- **Guard widened:** `ProtectedFolders.neverFileRoot`: the home folder and every folder above it (`/`, `/Users`), so a session started there can't take in the disk. The protected-folder rule is unchanged: a folder Claude ran in inside Documents or Downloads is read, and may raise macOS's prompt once (it already could, through the CLAUDE.md check).
- **Checked:** 5 new checks (232 pass). Live, on `/tmp` with its own search folder: `ledger-tool` (a `CLAUDE.md`, no sessions) appears under its topic with "0 past sessions"; `duo2 search "how are pending flamingo entries matched to the bank"` returns its `reconcile.py` first; this worktree, where a session runs, was being indexed too.
- **Cost:** any folder Claude was started in is now indexed, scratch folders and parents of many repos included. Indexing stays throttled and recent-first.
## F-81 · File navigator scope, a spike (2026-10-05)

Full note: `docs/plan/spikes/file-navigator-scope.md`. Checked in the code and on a scratch workspace (no Claude turns).

- **Hidden files are never shown.** `LiveSnapshot.topLevelFiles` (`Live/LiveSnapshot.swift:347`) lists with `.skipsHiddenFiles`; `.env`, `.gitignore` and `.claude/` don't appear, and `duo2 files` reads the same list. The same listing stops silently at 3 levels and 200 entries, and folders can't be collapsed.
- **The navigator can't leave the project folder,** by design (DL-23, handoff §3.3: "rooted in the project's working directory") and by construction: tree entries and file verbs are paths relative to the project. Duo isn't App Sandboxed; the only OS limit is the privacy prompts for Desktop, Documents and the like (F-28, F-53).
- **No way to open an outside file as a tab.** Tabs (`openDocumentsByProject`, keyed by the project's display name, relative paths) do survive switching projects, in memory and on relaunch; the right pane goes back to Project on return (`open(project:)`).
- **Sizes:** outside files as tabs M (an explicit `file:`+absolute-path tab id; the editor already watches any path); a hidden-files toggle S on its own but M with collapsible, lazily listed folders and a skip list; browsing outside the folder L, not recommended; remembering the selected tab S.
- Questions Q-36 to Q-38; the `../` hole is C-20; the work is ENH-10.

## F-82 · The map with many projects, built (DL-104) (2026-10-05)

- **Built:** `MapLayout` (`AllProjects/MapLayout.swift`) decides what the map draws and in what order, as a pure function with checks: Home's ★ tile (`HomeTile`) heading the unlabelled column (a column of its own when no project sits directly in Home); Home's columns as tiles; outside Home, `ACTIVE OUTSIDE HOME` tiles for folders with a session that needs you or is working, then 24-pt rows by parent folder (`OutsideGroup`, `OutsideRow`), five a group then `+ n more`. A header (`MapHeader`) with `Filter folders` and a `Recent / Name` popup; View › Sort Projects By. The sort persists in `state.json` (`mapSort`).
- **Recency:** sessions now carry `lastActive` (ms; the same `since` that makes their wait text). Fixture sessions have none, so `MapLayout.minutesAgo` reads their wait text. A live session counts as now.
- **Settling:** the order is fixed on the first scan and on each arrival at All projects (`mapSettled`); a refresh while you look doesn't move tiles. Projects new since then use their current activity.
- **Grid:** `AdaptiveColumns` keeps three slots across, so a lone column, tile or group stays a column wide instead of spanning the map.
- **Measured:** `scripts/check-ui.sh map-many` against `many-projects-handoff/screens/map-many.html`: the filter, Home's tile (78.5–347), the next tile (359), the columns and the active tiles land on the target's pixels; the footer rule is 1 pt off (the toolbar's border). Rows were looked at in a one-off capture with Home's projects removed: groups, counts, times and `+ n more` as drawn.
- **Changed by decision:** `overview` and `flow-zoom-*` now draw the header and Home's tile in its own column, so Platform wraps to a second row at 1440; their targets predate DL-104. The first arrow key now focuses Home's tile.
- **Exempt in the comparison:** the action column (illustrative on the board), active tints (no terminals in fixture states), Home's goal wrapping (F-13).

## F-83 · Files in and out of the project, built (C-20, DL-105, DL-106, DL-107) (2026-10-05)

- **C-20 closed:** `AppModel.contained(_:in:)` refuses a path that `..` (or a leading `/`) takes outside the project; `liveFile`, restore and every file verb go through it (`fileURL`). Symlinks the user made inside a project are still followed.
- **DL-107:** leaving a project notes its console and right-pane tab (`lastConsoleTab`, `lastRightTab`); coming back shows them while they're still open, ahead of "the most urgent session". A named session or document still wins. The restore file now keeps every project's tabs, not only the one on screen.
- **DL-105:** View › Show Hidden Files (`state.json` `showHiddenFiles`; `duo2 view hidden on|off`). The tree is read lazily (`LiveSnapshot.treeFiles`): the top level, plus one directory read per open folder (`expandedFolders`; `duo2 view folder <f> open|close`), capped at 2,000 entries. Live folders start closed (Q-40); opening a document opens its folders. Dotfiles draw in `text2`. Never listed: `.git`, `.DS_Store`, `.duo`, `node_modules`, `build`, `.build`, `.claude/worktrees`. `duo2 files` keeps its three-level walk (new `--hidden`).
- **DL-106 (first half):** File › Open File… (⌘O, several at once), a drop from Finder on the right pane, and `duo2 doc open <any path>` open a file outside the project as a `file:<absolute path>` tab in the current project; inside the project it opens as itself; folders are refused. Such tabs survive switching projects and relaunch; HTML outside reads from its own folder. The tab's look is a stand-in (Q-39). Browsing up out of the project is not built.
- **Bug fixed on the way:** `topLevelFiles` cut the folder's path off each entry, but the enumerator reports `/private/var/…` for `/var/…` (and the like for any symlinked path), so every entry looked deeper than three levels and a symlinked project listed nothing below its top. It now uses the enumerator's depth.
- **New verbs:** `duo2 view sort recent|name`, `view filter [text]`, `view hidden on|off|toggle`, `view folder <f> open|close`. `docs/cli/duo2.md` regenerated.
- **Tried live** on a scratch workspace and config (no Claude turns): `hidden:on`, `folder:.claude`, a document, `open-file:/tmp/…/outside-notes.md`, another project, back: the outside file was the tab showing and loaded in the editor; `.env`, `.gitignore`, `.claude/settings.json` listed in `text2`, `.git` not. New scripted actions: `open-file:`, `hidden:`, `folder:`, `zoom-out`.
- **Not verified:** a real drag from Finder (scripted runs can't drag); whether the editor's web view takes the drop before the pane does.

## F-84 · Slice 3 built to its screens (2026-10-05)

- **S3-7, S3-3: Duo's own sheets, no system alerts.** `SheetCenter` queues `DuoQuestion`s (one at a time, hung from the toolbar like Move into Home): every confirmation (move, merge, new project from a session, reconnect, migrate, delete, uninstall) and every launch question (install consent, `.gitignore`, and the new legacy Duo notice: Disable backs up and records the backup for Settings › Restore; Not Now asks again only when what it finds changes; a partial disable says what's left). `info()` is a sheet too. Scripted runs still auto-answer (`DUO_AUTOCONFIRM`). Delete Session… now moves the transcript to the Trash (the design's promise); scratch folders are still removed outright so checks never fill the user's Trash.
- **S3-4: editor notices** as a bar under the tabs (`NoticeBar`, `size.notice`): conflict (with "Saving is paused until you choose"), removed, renamed, read only with the reason. A conflict's lines are outlined in the text with search's outline, labelled, and stay through typing until resolved. A rename made outside Duo is followed: the open file descriptor knows the new path (`F_GETPATH`), the tab and tree follow (`moved`), and the bar says so; a move to the Trash still reads as removed. A document left in conflict says "· conflict" on its tab.
- **S3-5: documents drawn** (`type.heading1` 18/24): H1/H2/H3 sizes, hanging list marks (• then – when nested, numbers as written), drawn task boxes with done items in `text2`, quotes with a bar, code blocks on `ground` with their language, inline code on `ground`, tables drawn as tables away from the caret (full width, wide ones scroll), images on their own line read by Duo from disk and handed to the page (a missing one is a dashed box naming the file), `---` as a hairline, blank lines 10 high so blocks sit 10 apart, Claude's deletions as "N lines removed by Claude · Show · Revert", and find in Duo's look ("2 of 5", ‹ › Done; replace is keys only). Measured against `editor-document.html` in a browser: matches but for wrap points.
- **S3-1: Settings** (`SettingsView`, `size.settings`): Claude Code (path, version, Choose…, Use Found One; a chosen path wins while it runs, LR-19), Home, the archive's size, notifications, duo2 everywhere (Install…/Remove…), legacy Duo (Disable…/Restore), allowed sites (Edit… opens the list). `duo2 settings [claude-path|notify|dock-badge]`.
- **S3-6: notifications and the Dock badge** (`AppModel+Notify`): needs you only, one per wait, never while Duo is in front or for the visible session; permission asked the first time it would notify; clicking opens the project with the card selected. Badge = sessions needing you. Both off in Settings.
- **S3-2's look** on the F-78 logic: the tile's lines and buttons, and the notice over the session list. The tile says "they open again once it's found" rather than the board's "they still open and resume", which wasn't true (sessions wait for the folder). "In the Trash" still waits (F-78).
- **Captured** on the fixtures (sample data only): the merge sheet, the legacy sheet (a scratch copy of the fixture legacy config), the conflict bar, the missing tile, and Settings drawn with `ImageRenderer` (`render-settings:`; ImageRenderer can't draw a scroll view, so the view has a non-scrolling mode). Fixtures restored and checked against a backup.
- **Also (DL-102):** task notes take the general properties look (Q-33).
- **Merged with the many-projects map (DL-104, F-82):** folders outside Home are now rows; a missing one keeps its full S3-2 tile among them (it needs its words and buttons), and the tile's buttons stack when the column is too narrow for both. Records renumbered on merge: this finding was F-79 (the director research took it first), the search branch's DL-101/F-78 are DL-103/F-80, the many-projects branch's DL-101–104, Q-34–39, F-79–81 and ENH-9 are DL-104–107, Q-35–40, F-81–83 and ENH-10.

## F-85 · In-app updates with Sparkle (2026-10-05)

- **Built (Phase L):** Sparkle 2.10.0 vendored (`Vendor/Sparkle/`, XPC services removed since Duo isn't sandboxed), linked by the `Duo` target only through `unsafeFlags` (`-F`, rpath `@executable_path/../Frameworks`), so DuoChecks and `duo2` don't load it. Release builds start `SPUStandardUpdaterController` on `releases/latest/download/appcast.xml` (daily, automatic checks on, no first-run question); Duo › Check for Updates… is Sparkle's. Development builds (0.0.1) and scripted runs never start it, and where it isn't running the GitHub notice (F-69) answers.
- **Signing:** the update key is an Ed25519 key in `~/.duo-signing/sparkle-ed25519.key`, made with CryptoKit because Sparkle's `generate_keys` stores keys in the keychain (a prompt would block an unattended release); `sign_update --ed-key-file` signs with it and the public key verified its signature. `release.sh` signs Sparkle's `Autoupdate`, `Updater.app` and the framework inside out with Developer ID and Hardened Runtime before the app, signs the DMG for Sparkle, and publishes `appcast.xml` with the release. Development bundles re-seal the framework ad hoc (removing the XPC services breaks its original seal).
- **Rehearsed** (`release.sh 0.1.6 --no-publish`): the app with Sparkle and the DMG were notarized (Accepted), Gatekeeper accepts both, the app launched from the DMG, and the appcast names build 133 with a verified signature.
- **The work Mac:** `duo2 update probe` (local, no Duo needed) checks the feed, the DMG's host, the install location and any proxy, with a verdict. The test plan is `docs/plan/spikes/sparkle-work-mac.md`; it needs 0.1.6 published (the first feed) and then 0.1.7 to update to.

## F-86 · A lone Home column no longer leaves the map two-thirds empty (2026-10-05)

- **Seen:** with every Home project directly in Home (no topic folders), All projects drew one tall stack of tiles down the left third, the rest of the pane blank. `AdaptiveColumns` fills three slots and pads a short row with empty slots, so one column stays a column wide (deliberate for outside groups, DL-104); Home's unlabelled column alone fell into the same case, which map-many never draws (it always has `payments` and `growth`).
- **Built (stand-in, Q-42):** `MapGrid` lays a lone unlabelled column out as a tile flow (`AdaptiveColumns` over the tiles, as `TileFlow` does for ACTIVE OUTSIDE HOME): Home's ★ tile, then the projects, then New project, three across, wrapping to two or one when narrow. The blank label row stays, so Home's tile keeps its place. Arrow keys still walk the tiles in order (up/down), as in ACTIVE OUTSIDE HOME.
- **Measured:** a capture on map-many's fixture with every Home project moved directly into Home and nothing outside, before and after (`build/ui/map-lone-column-before.png`, `-after.png`); `scripts/check-ui.sh map-many overview` unchanged; DuoChecks 256 passed.

## F-87 · Tasks: named on creation, renamed by their heading, started from (2026-10-05)

- **+ New task** opens the note with its heading's name ("Untitled task") selected and the editor holding the keyboard, so typing names the task. Only the button does this; `duo2 task new` doesn't take the keyboard from whoever has it.
- **A task's name is written twice,** `title:` and the `# ` heading (Make a Task and + New task write both), and the lists read `title:`. Renaming by the heading left the list on the old name. The editor now keeps them together: while they agree, a person's edit to either is made to the other in the same step (one undo); once they differ, each is left alone. Agents' edits (`duo2 doc edit`) and outside changes aren't followed. An emptied `title:` falls back to the heading, and quoted titles now unescape (`\"`, `\\`, `''`).
- **New Session in Task** (`duo2 task session <task>`): a Claude session in the task's project whose link is in the note's `sessions:` from its start, shown in the console. With the note open the link goes into the editor's buffer (as `+ Add` does); otherwise on disk. Its look is a stand-in (Q-43).
- **Bug found on the way:** adding a session in the editor to a new task (`sessions: []`) put an item under the inline list, which isn't YAML (`+ Add` had it too). The line now becomes a block list holding the old items and the new one, as `TaskNotes.adding` writes it.
- Checked live on a scratch workspace: real key events after + New task replaced the name, `title:` followed on disk and the Tasks fold read the new name; editing `title:` renamed the heading; New Session in Task from the menu path and from `duo2` linked the session and the task row read "1 session".

## F-88 · A folder that isn't a project listed no files (2026-10-05)

- **Found (Geoff):** a folder moved in Finder, opened in Duo, showed only its path under Files; Make a Project "fixed" it. The snapshot filled `projectFiles` for projects only, never for folder entries (DL-63), so their tree was empty, against DL-63's "keep working as is".
- **Fixed:** a folder entry's tree lists like a project's (lazily, the folders it has open), unless the folder is gone. Checked in DuoChecks.
- **Also:** inside a folder nothing said it wasn't a project; Make a Project was only on the map tile's right-click. A notice over the session list now says so and offers **Make a Project** (stand-in, Q-44). Captured on scratch data: `build/ui/folder-notice-live.png`.


## F-89 · Scripted runs never touch the real support folder (2026-10-05)

- **Why:** C-21. A run with `--workspace` and no `DUO_SUPPORT_DIR` rewrote Geoff's `state.json`. The rule that scripted runs set their own folder was honour-system only.
- **One place decides:** `SupportFolder` (`Sources/DuoControl/SupportFolder.swift`). The five copies of the lookup (state and events, endpoint and socket, archive, migration journals, search index) now read `SupportFolder.duo`.
  - `DUO_SUPPORT_DIR` set (not empty): that folder, always.
  - Any `LaunchOptions` flag (`--workspace`, `--state`, `--capture`, `--capture-window`, `--then`, `--fixture`, `--terminals`, `--gallery`, `--left`) and no `DUO_SUPPORT_DIR`: a fresh `/tmp/duo-XXXXXX` (`mkdtemp`). Short, so the socket path stays far under 104 characters (34 bytes with a private socket).
  - Neither: `~/Library/Application Support/Duo`, as before. AppKit's own `-NS…` flags don't count.
- **How:** `SupportFolder.prepareForLaunch()` is the first line of `DuoApp.init`. For a scripted run it makes the folder, exports `DUO_SUPPORT_DIR` (so terminals, hooks and `duo2` inside the instance inherit it) and prints one line on stderr: `Duo: scripted run without DUO_SUPPORT_DIR; using a temporary support folder, /tmp/duo-… (C-21, F-89)`. If the folder can't be made, Duo exits (73) rather than fall back to the real one.
- **Reaching the instance with `duo2`:** read the folder from the stderr line (`run-live.sh`'s fourth argument, `check-ui.sh`'s `build/ui/<state>.log`), then `DUO_SUPPORT_DIR=<folder> duo2 …`, with `DUO_SOCKET`/`DUO_TOKEN` unset. Its `endpoint.json` and `duo.sock` are in `<folder>/Duo`. Checked live: `duo2 ping` answered "Duo 36132, live, 0 projects".
- **The acceptance Duo keeps the real folder on purpose:** it is Geoff's working Duo during a walk, driven by `duo2` and `duo2://` links through the real `endpoint.json`. `scripts/acceptance/open-duo.sh` now passes `DUO_SUPPORT_DIR="$HOME/Library/Application Support"` explicitly. Every other scripted run is isolated.
- **Checked:**
  - DuoChecks (support folder section): the three cases; every flag `LaunchOptions` parses is in `scriptedFlags`; no other source file resolves `.applicationSupportDirectory`. A scripted launch in-process makes and exports the folder, and state, archive, journals, endpoint and terminals' environment follow it.
  - `scripts/bundle.sh`, `swift run DuoChecks` (278 passed), `NO_BUILD=1 scripts/check-ui.sh` (six states, each log naming its own `/tmp/duo-…`). A live `--workspace none --capture-window` run with no `DUO_SUPPORT_DIR` wrote only to its temporary folder.
  - The real `state.json` kept its mtime (Oct 5 06:29:05) throughout.
- **Not done:** temporary folders aren't deleted at quit, so a run can be inspected afterwards. `/tmp` is cleared at restart.

## F-90 · Inside a folder that isn't a project, as designed (2026-10-05)

- **Built (DL-110):** the line under a folder's name; the notice with Make a Project and Not Now (`FolderNotice`); the Project tab's offer (`FolderProjectTab`, Open CLAUDE.md when there is one); "Nothing has run in this folder yet." Not Now is kept by folder path in `state.json` (`notNowFolders`) and reaches the view as `Fixture.Project.notNow`, set by the snapshot. `duo2 project make <folder> --not-now`; the harness has `notnow:<folder>`.
- **Checked live on scratch data** (own `DUO_SUPPORT_DIR` and `CLAUDE_CONFIG_DIR`): the three states against the board, region by region (`build/ui/folder-*.png`); `duo2 project make tool --not-now` hid it and `duo2 undo` brought it back; `duo2 project make tool` wrote PROJECT.md.
- **Not in DuoChecks:** Not Now writes Duo's `state.json`, and DuoChecks reads the real one, so it is checked live instead.


## F-91 · The menu bar as drawn (2026-10-05)

- **Built (DL-108):** the bar reads Duo, File, Edit, Format, View, Project, Session, Go, Window, Help.
  - File, Go and View follow m2's mockup. New Task and New Project… join File. Toggle Right Pane and Next/Previous Pane are out of the menus until they're built.
  - Format follows m3: Code, Link… ⌘K, Heading ▸ 1–3, Task and Add Properties.
  - Project and Session follow m1 (`Navigation/ObjectMenus.swift`):
    - Project acts on the project you're in, or the focused tile at All projects.
    - Session acts on the console's Claude session, or else the selected row.
    - The Merge Into, Add to Task and Move to Project submenus are shared with the right-click menus.
  - Help follows m4: GitHub pages, with the new issue filled in but not sent.
  - Every item has a `duo2` verb. `doc format` takes `code`, `link`, `heading1–3`, `task` and `properties`; `End Session` is `session close`. The Help pages and full screen are in `Parity.uiOnly`.
- **SwiftUI's menu bar, learned:**
  1. A `CommandMenu` lands after View. Format has to fill the system's own Format menu (`CommandGroup(replacing: .textFormatting)`) to sit between Edit and View.
  2. `.disabled` on a `Menu` does nothing in the menu bar: AppKit auto-enables any item that has a submenu. With nothing to act on, Merge Into, Add to Task and Move to Project are plain dimmed items.
  3. AppKit doesn't add Enter Full Screen to a SwiftUI View menu. Duo makes it (⌃⌘F), and the title follows the window's full-screen notifications.
- **Link…** has no drawn popover. The selection becomes `[text]()` with the caret waiting for the address, or, with nothing selected, `[]()` with the caret waiting for the text. Heading and Task replace a line's leading mark; choosing the same one again takes it off.
- **Checked:**
  - Window captures don't draw the menu bar. A new harness action, `menus`, prints it as text (titles, chords, dimmed items, checkmarks). It was compared item by item with the walk's m1–m4 mockups at All projects, inside `checkout`, and with the editor focused: order, labels and chords all match.
  - The editor commands were checked in the editor page in a browser. Add Properties leaves the same state as `frontmatter-none` (an empty block with the most-used names on offer).
  - DuoChecks pass, including parity; `docs/cli/duo2.md` was regenerated.

## F-92 · New Session in Task as drawn: the hover + and the drafted prompt (2026-10-06)

- **Built (DL-112, `stand-ins-handoff/`):** hovering over a task row shows a + where its status or time sits (`NewSessionInTaskButton`), tooltip "New Session in Task". The task line (Tasks fold, Open tasks at All projects) takes the `selected` fill as drawn; the group-style task row shows the + at its trailing end with no fill (not drawn; its "status · n" gives way when space is short). Hover lives in the model (`AppModel.hoveredTaskRow`, set by `TaskRowHover`'s `onHover`), not in view state (DL-30). New tokens `size.rowAction` (18, radius 4, glyph 14). Shown only with live terminals.
- **Drafted, not sent:** `newSession(inTask:)` starts Claude with no first message, then `draft(_:into:)` waits for the session's beacon to read idle (up to two minutes, for a trust prompt) and types `TaskNotes.draft(path:)`, `@tasks/<note>.md ` (quoted if the name has a space, like Send to Claude's file references), as one bracketed paste (`TerminalSession.bracketed`). Nothing presses Return. Unlike Send to Claude it doesn't switch project or take the keyboard, since `duo2 task session` can start it from elsewhere; `duo2 task session` drafts too and says so.
- **Q-42 (DL-111):** no change; F-86 already builds both boards. The stand-in comment now cites DL-111.
- **A stand-in claude for scripted runs:** Settings' chosen claude (`claudePath` in the scratch support folder's `state.json`) can be a script that writes an idle beacon to `$CLAUDE_CONFIG_DIR/sessions/<pid>.json` and logs its arguments and every byte it receives. Duo then runs real terminals with no model, no credentials and no turn. DuoChecks uses one end to end (its own `DUO_SUPPORT_DIR` and `CLAUDE_CONFIG_DIR` under `/tmp`, put back afterwards).
- **Checked:**
  - DuoChecks (290 passed): the draft text, quoting, no line break from a note's name, the paste bytes; end to end, the session starts with no prompt argument, the terminal receives exactly `ESC[200~@tasks/exec-review-prep.md ESC[201~` and no CR or LF, the note links the session and the console shows it.
  - Live on scratch data (own `DUO_SUPPORT_DIR`, a `CLAUDE_CONFIG_DIR` with no credentials, the stand-in claude): `hover-task:` (a new harness action) captures of a task line and a group-style row, compared with `q43-hover` region by region (`build/ui/q43-hover-compare.png`): fill x 26–291 pt and 26 high, box at 35, the + centred 16 pt from the pane's edge, as the board. `task-session:` then `dump`: the prompt reads `> @tasks/pull-the-top-three-quotes.md `, the stand-in got the bracketed bytes and no Return, and the note's `sessions:` lists the session. `duo2 task session "Legal review of saved cards"` against that instance did the same.
  - `NO_BUILD=1 scripts/check-ui.sh`: six states produced.
- **Not checked:** the tooltip (it needs a real pointer); real Claude Code taking the paste at its prompt (Send to Claude already relies on that, DL-68).


## F-94 · Editing tables as Markdown, as decided (2026-10-06)

(F-93 is the director agent's update-flow finding.)

- **Built (DL-113, `tables-handoff/`):** Format › Table ▸ (Insert Table; Add Row Above/Below; Add Column Before/After; Delete Row, Delete Column; Align Column ▸ Left, Center, Right).
  - The bar over a table appears only while the caret is in it (`TableBarWidget`). Its Align ▾ and Delete ▾ are native menus (`EditorController.tableMenu`).
  - Tab and ⇧Tab move between cells, and Tab in the last cell adds a row. Return moves down a row, and adds one at the end.
  - `duo2 doc table insert|row-above|row-below|column-before|column-after|delete-row|delete-column|align-left|align-center|align-right|next|previous`.
  - The menu's row and column items dim unless the caret is in a table: the page reports `inTable` with each selection.
- **How:** `duo-editor.js` reads the table at the caret from the syntax tree (`tableAt`). It splits rows only on unescaped pipes (`splitRow`; the drawn table now does too) and writes the whole table back with the columns padded (`writeTable`), as one undoable change.
- **Guarding against other renderers (Geoff, on t1):**
  - An inserted table gets a blank line before and after, so it never joins a list or a paragraph.
  - A paste into a cell becomes one line: line breaks become `<br>` and `|` becomes `\|`. A list pasted into a cell stays as its text.
  - The drawn table shows `<br>` as a line break, as GitHub and Obsidian do.
- **Checked:**
  - In the editor page (browser): every command, Tab across the end, Return in the last row, a paste with a nested list and a pipe, escaped pipes kept through Add Column, and Insert after a list and mid-paragraph.
  - A document written that way (a nested list, then a table holding `\|`, a code span with `\|`, a pasted list, an empty row, then a second table followed by a list) was rendered by GitHub's GFM renderer (`gh api markdown`, sample text only). Both tables come out as tables with the right rows and cells, escaped pipes show as `|`, `<br>` breaks lines, and the lists stay outside the tables.
  - The bar was compared with `tables-bar` (`build/ui/tables-bar-compare.png`): the same buttons, 31 pt below the paragraph and 27 pt above the table. The heading spacing differs by a few points because the board simplified it; S3-5's document target governs that.
  - Live, on a scratch workspace with its own `DUO_SUPPORT_DIR`: the `menus` dump with the caret in a table shows Format › Table enabled. `duo2 doc table row-below`, `align-center` and `next`, then `doc save`, wrote the realigned table to disk; a bad word gives the usage line.
  - DuoChecks (290 passed) includes parity for every new item.
- **Not checked:** clicking the bar's buttons with a real pointer (they run the same commands), and Obsidian's renderer (it isn't installed here).
