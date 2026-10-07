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
- Since DL-114 (F-93) the confirmation is the update question (Later, Open Releases Page, and Install Now where Sparkle runs), and `duo2 update` also names the releases page and whether installing in place needs an administrator password.

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
- **Administrator prompts:** Sparkle asks for an administrator password whenever this account can't write Duo's app or its folder (a standard account and `/Applications`). Geoff hit it on 2026-10-06. Since DL-114 (F-93), Duo › Check for Updates… asks Duo's own question first, and on such an install Open Releases Page is the default, to install by hand. Sparkle's scheduled checks there ask that question instead of showing Sparkle's window.

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


## F-93 · Updating by hand from the releases page (2026-10-06)

- **Why:** DL-114. Geoff tested the in-app update and Sparkle asked for an administrator login. Sparkle asks whenever this account can't write Duo's app or the folder holding it (a standard account and `/Applications`), and its standard window can't take another button.
- **Built:**
  - **One writability test,** `InstallLocation` (`Sources/DuoControl/InstallLocation.swift`): write access to the app and its folder. `duo2 update probe`, `duo2 update` and the question all use it.
  - **Duo › Check for Updates…** asks GitHub first (`UpdateCheck.latest()`), then decides with `UpdateCheck.plan(latest:current:installWritable:sparkle:)`, which is pure.
    - A newer release gets Duo's question (`UpdateCheck.question`, on `SheetCenter`): "Duo 0.1.9 is available.", "You have 0.1.8.", then a line for the case, and **Later**, **Install Now**, **Open Releases Page**.
    - Not writable: "Installing it here needs an administrator password: this account can't replace Duo in `/Applications`. …", and Open Releases Page is the default.
    - Writable: Install Now is the default. It calls Sparkle's `checkForUpdates`, so Sparkle's own window then offers the update (and its notes) as before.
    - Without Sparkle (development and scripted builds) the question has Later and Open Releases Page only. This replaces F-69's Download/Cancel confirmation.
    - Up to date or GitHub unreachable: Sparkle's window answers as before (without Sparkle, Duo's notice as before).
    - Later remembers the version (`DuoState.skippedUpdate`, as F-69's Cancel did): the launch and scheduled checks don't ask about it again; the menu still does.
  - **Sparkle's scheduled checks:** an `SPUUpdaterDelegate` (`Sources/Duo/Updater.swift`) implements `updater(_:shouldProceedWithUpdate:updateCheck:)`. For a background check on an install this account can't replace, it asks Duo's question (once per version) and throws, which Sparkle documents as "the user is not shown this update nor is it downloaded or installed". Menu checks, and installs this account can replace, go on as Sparkle's.
  - **`duo2 update [--open]`:** three lines: what's newest, `Releases page: <url>` (the release's page, or every release's when GitHub didn't answer), and `Installed at <path>: installing in place needs (no) an administrator password …`. `--json` adds `latest`, `page`, `installedAt`, `needsAdmin`, `reachable`. `--open` opens the page. Install Now and Later are in `Parity.uiOnly`. `docs/cli/duo2.md` regenerated.
  - **Harness:** `ask-update:writable|admin|no-sparkle` asks the question for 0.1.9 over 0.1.8 in `/Applications` with its buttons only logged.
- **Checked:**
  - `swift run DuoChecks`, 308 passed. The new section feeds the plan with no network:
    - writable: Install Now is the default and no password is mentioned;
    - not writable: the password line names the folder and Open Releases Page is the default;
    - up to date and unreachable: no offer;
    - no Sparkle and development builds: no Install Now;
    - `duo2 update`'s text names the page and the password;
    - `--open` takes no value;
    - `InstallLocation` on a temporary app (replaceable) and on `/System/Applications/Calculator.app` (not replaceable).
  - Captures on the fixture, each run with its own `/tmp/duo-u-…` support folder: `build/ui/update-question-writable.png`, `-admin.png`, `-no-sparkle.png`, with the sheet cropped in `*-sheet.png`. Each is DuoQuestion's look, as the other questions are. Nothing draws this question to compare against (Q-47).
  - Live `duo2 update` and `--json` against a scratch instance (development build): "Duo 0.1.8 is available (this is a development build).", its page, and "installing in place needs no administrator password; this build doesn't update itself".
  - `NO_BUILD=1 scripts/check-ui.sh`: six states produced.
- **Not checked:**
  - The scheduled-check delegate and Install Now against a real Sparkle install. That needs a published release with a feed and a newer one to find, on an install this account can't write. Planned for the work-Mac spike (`docs/plan/spikes/sparkle-work-mac.md`) once 0.1.9 is out and 0.1.10 follows.
  - That Sparkle shows nothing at all for the declined background update. Its delegate documentation says so; it hasn't been seen on a real install.
- **Note:** dragging the new Duo into the same `/Applications` also needs an administrator password in Finder when the folder isn't this account's. The question doesn't suggest `~/Applications`; that's for Q-47.

## F-94 · Editing tables as Markdown, as decided (2026-10-06)

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

## F-95 · The editor's space above H2 and H3, as editor-document draws it (C-22, 2026-10-06)

- **Cause:** `editor-document` (slice 3) stacks blocks 10 apart and gives H2 and H3 `margin-top: 4px` on top. The editor gave headings only a font (a mark on the text), so there was nowhere to put the 4: every heading after the first sat 4 pt high, and everything under it with it. A drawn table had `margin: 4px 0`, which the target doesn't have; it hid the missing 4 under a table (Open questions landed right by accident) and put the table itself 4 low.
- **Built:**
  - A token, `space.gap.aboveDocumentHeading` = 4 (`DuoSpace.gapAboveDocumentHeading`, `gapAboveDocumentHeading` in the design system). The app hands it to the page as `--duo-heading-above`, beside the colours (`EditorController.tokenCSS`).
  - `duo-editor.js` puts a line class on each heading that starts its line (`duo-hl duo-hl1`…`6`). H2 to H6 lines take `padding-top: var(--duo-heading-above)`: padding, not margin, so CodeMirror measures the line with it. H1 takes none, as drawn. The space stays while the caret shows the heading's `## `, so nothing jumps.
  - The drawn table loses its margin: the blank lines around it give the 10, as drawn.
  - A DuoChecks check ties the page's rule to the token (291 passed).
- **Measured** in a browser page at the pane's width (460, under a 36 + 1 pt tab strip, colours from `tokens.json`), against the two targets. Text ink tops, in points from the pane's top, target / before / after:

  | | target | before | after |
  |---|---|---|---|
  | `editor-document` H1 | 64 | 64 | 64 |
  | its paragraph | 98.5 | 98.5 | 98.5 |
  | Thresholds (H2) | 152.5 | 148.5 | 152.5 |
  | Finance confirmed… | 183 | 179 | 183 |
  | `tables-bar` Thresholds (H2) | 101.5 | 97.5 | 101.5 |
  | Limits per path… | 132.5 | 128.5 | 132.5 |
  | the bar's buttons | 163.5 | 159.5 | 163.5 |
  | the table's rows | 190.5, 211, 230 | 186.5, 207, 226 | 190.5, 211, 230 |
  | Open questions (H3) | 284 | 276 | 284 |
  | its paragraph | 314 | 306 | 314 |

  On `tables-bar` the page now matches the board pixel for pixel, apart from the caret and the tab strip's labels (the harness strip has none). Line boxes agree too: on `editor-document` the Thresholds line's text starts at 148 against the target's 148 (144 before).
- **Still different on `editor-document`, not C-22:**
  - The "2 lines removed by Claude" row has `margin: 2px 0` of its own (`.duo-deleted-block`). The target puts it 10 from its neighbours, so in the editor it sits 2 low and the rest of the page 4 low: the table is at 248 against 244, Open questions at 345 against 341.
  - List and task items are 20 apart; the target draws them 22 apart (`gap: 2px`).
  - The first paragraph wraps before "See" where the target wraps after it (the inline code's padding).
- **The fixture states don't change** (window captures don't draw the web view, F-25). `scripts/samepng.py` gave 0 differing pixels for all six against captures from before.
- **Not checked live:** the `--state project` fixture never loads the editor page (`editor-js:` finds `about:blank`), so the token variable was checked by DuoChecks and the binary, not in the app's own web view.

## F-101 · A selection moved the text under it (C-25, 2026-10-06)

- **Cause:** the live preview showed raw Markdown on every line a selection touched (`buildDecorations`, the properties block and the table's `blockDecorations` each built that set from `from`…`to`). As a drag or shift+arrow extended the selection, each line it reached switched to raw: a blank line grows from 10 to 20 (it loses `duo-blank`), a heading shows `## `, a drawn table becomes its source rows. The text moved while the mouse stood still, so the drag's end landed on whatever had moved under it: dragging from the first paragraph to "with a soft break" under Thresholds selected to the end of the heading line instead, 20 pt short (two blank lines grew). CodeMirror's heights were right throughout; clicks with no drag always landed.
- **Not F-95.** The same drags fail on v0.1.9 (`8b0ed15`, the commit before F-95's merge). v0.1.9 also had CodeMirror's heights 8 pt off below a table (the table's `margin: 4px 0` is invisible to CodeMirror's height map); F-95's removal of that margin fixed it, and the heading padding measures correctly.
- **Built:** `rawLines(state)` in `duo-editor.js`: the line of each selection's anchor shows raw Markdown, nothing else. A caret is unchanged (anchor = head); a selection keeps the look it had when it started, so selecting inside a table being edited keeps the table's source. Link clicks use the same set. Format › Heading and Task still apply to every selected line.
- **Checked:** `scripts/check-editor-selection.mjs` runs the built page in Chromium at 460 wide (F-25): 108 clicks at word starts, 42 drags down and up between them, 108 shift+down. It also compares CodeMirror's line tops with the drawn ones. Before: 6 of the 42 drags wrong on main (5 on v0.1.9, plus 5 lines off in its height map). After: all pass. With a caret, pages render byte for byte as before (five caret positions), so F-95's measurements against `editor-document` and `tables-bar` still hold.
- **Behaviour change:** selecting across a heading or a table no longer shows their Markdown; put the caret on the line to see it.
- **Not checked in WebKit:** Playwright's WebKit isn't installed; the cause and fix are in CodeMirror's decorations, not the engine.

## F-99 · Dragging files into terminals and onto the file tree (DL-117, 2026-10-06)

- **Path form: absolute, as Terminal.app gives.** Send to Claude (`AppModel+Send.swift` `filePayload`) writes an `@` reference relative to the session's folder; a drop doesn't use it. The terminal may be a shell that has `cd`'d anywhere, and Claude Code treats a plain dropped image path as the image (it attaches it), which an `@`-path doesn't do. So: `/abs/path` per item, backslash before every ASCII character a shell treats specially (space, quotes, `()[]{}$&;|<>*?!#=~^` and backtick), letters beyond ASCII left as they are (Terminal.app's form), separated by spaces, one trailing space. A name with a control character (a newline) is written whole as `$'…'` with `\n`, so nothing typed is ever a Return. It's sent as a bracketed paste when the program asked for one (zsh, Claude Code: read from SwiftTerm's `terminalStateSnapshot().bracketedPasteMode`, since its `Terminal` isn't public), else as typed text. `GuardedTerminalView` registers for file URLs; SwiftTerm had no drop support.
- **The tree is now a drag source:** each row drags its file URL on the map's drag card (F-51). That's what makes dragging from the tree into a terminal work, and it's also how **dragging within the tree** works: it didn't before (rows had no drag), and it falls out of the same drop, so it's built. Dragging a row out to Finder hands Finder the file; Finder decides move or copy there.
- **Drop targets:** a folder row is itself; a file row means its folder (as Finder's list view); the tree's empty area is the project root. While a drag is over one, `treeDropTarget` draws the stand-in highlight (Q-50) and the pointer shows move, or + for a copy from another volume (Q-51), or no-entry when every item would go into itself.
- **The rules** live in `Live/FileDrop.swift` (no main actor, checked by DuoChecks): a folder can't go into itself or its children; nothing replaces a folder holding the source; an item already in the folder stays put; a taken name throws unless answered (Keep Both: "name 2.ext", Finder's numbering; Replace: the old one to the Trash, never deleted, and brought back if the move fails). Across volumes it copies. Undo moves items back, trashes copies, and brings replaced items out of the Trash, stopping short of overwriting anything that has appeared since. **The boot disk's volumes all report one volume identifier** (the sealed system volume and Data are firmlinked), as Finder sees them, so DuoChecks tests the cross-volume rule on a 2 MB scratch HFS+ image (`hdiutil`, unmounted afterwards).
- **One move for all:** the tree drop, Move To… and `duo2 file move` go through the same plan and undo. Move To… and `duo2 file move` weren't undoable before; now they are (Edit › Undo, `duo2 undo`), and Move To… asks the clash question instead of failing. `duo2 file move` takes several paths and any path on the Mac (the Finder drop), and `--replace` / `--keep-both`; without one, a clash fails with a hint. Open tabs follow an item moved inside the project, and follow it back on undo.
- **Checks:** DuoChecks 335 passed (21 new: escaping with spaces, quotes, every shell character, unicode and emoji, several items, control characters; move, undo, clash with no answer, Keep Both, Replace and its undo, into itself, partial refusal, already there, the folder-holding-the-source case, cross-volume copy and its undo, the model's in-tree move with a tab following). `scripts/bundle.sh`; `NO_BUILD=1 scripts/check-ui.sh` unchanged (the fixture's tree has no live files, so no drag or drop). Live, on scratch folders under `/tmp` with their own support and config folders: drops from a stand-in Finder folder moved a file with a space and a folder; a clash asked and Keep Both made `a 2.md`; Cancel moved nothing; Replace and then Undo brought both files back; docs onto docs/sub was refused with a note; an open tab followed a move and came back on undo; two Undos put the disk back as it was. Into a shell, `drop-terminal:` typed `/tmp/dd-finder/Café\ 日本\ it\'s.md /tmp/dd-ws/proj/docs/b\ c.md /tmp/dd-ws/proj/docs/folder ` at the prompt and ran nothing. `duo2 file move` against that instance: clash refused with the hint, `--keep-both` made `a 2.md`, a folder into itself refused, a Finder folder moved, two `duo2 undo`s put both back.
- **Harness:** `drop-files:<folder|root>=<path>|<path>`, `drop-terminal:<path>|…`, `drop-hover:<folder|root|off>`, and `answer:<label>` presses a button on Duo's own question sheet. They call what the drop delegates call; a real pointer drag (AppKit's drag session, SwiftUI picking the innermost drop target over the tree's) isn't scriptable here, so Geoff should try one by hand at the acceptance walk.
- **Not done:** an outside file open as a `file:` tab (DL-106) that's dropped into the project keeps its old tab, which then shows the placeholder; Duo doesn't read ⌥ (copy) or ⌘ (move) during the drag as Finder does (Q-51).

## F-102 · Files that aren't text, and a PowerPoint viewer spike (C-26, Q-52, ENH-12, 2026-10-06)

- **The bug (C-26):** the right pane chose by extension only: `.html`/`.htm` got the HTML viewer and anything else with a dot went to the editor, so a `.pptx` showed its zip bytes as text. Now `FileKind.isBinary` (`Live/FileKind.swift`) is asked first:
  - by type: a system type that isn't text and conforms to image, PDF, presentation, spreadsheet, audio/video, archive, executable, font, database, disk image or package is binary without reading it;
  - by content, for everything else (including unknown and dynamic types): a NUL byte in the first 8 KB, or more than one byte in ten a control character text doesn't use.
  - Traps: the system calls `.ts` an MPEG-2 stream (so TypeScript is listed as code), SVG is an image that is also text (text wins), `.bin` is "MacBinary archive", and `.plist` can be either (sniffed).
- **The fallback (stand-in, Q-52):** nothing in the handoffs draws a "can't show this" state. `BinaryFileView` uses drawn parts: the S3-4 notice bar ("Read only: Duo can't edit a <kind>.") with **Open With** (the tree's submenu: apps, default first, Other…) and **Show in Finder**, over a `QLPreviewView` when Quick Look draws more than an icon for the type (PDF, images, Office, iWork, audio/video, RTF), else a "No preview" note on `pane`. Both verbs exist (`file open-with`, Show in Finder in `Parity.uiOnly`).
- **Quick Look's limits:**
  - `QLPreviewView` has no page or slide index, no selection, no hit-testing: the API is `previewItem`, `refreshPreviewItem`, `displayState` (opaque), `close`.
  - Apple's `Office.qlgenerator` (OfficeImport) still ships on macOS 27 and renders `.pptx` without Office.
  - It **gives no preview at all for a python-pptx deck with speaker notes** (`qlmanage -p`: "did not produce any preview"; the same deck without notes previews). The pane then shows Quick Look's file icon: no noise, but no slides either. Agents usually make decks with python-pptx.
  - Its pie chart came out as one solid disc, and it dropped picture and text-box rotation.
- **The spike (ENH-12):** `docs/plan/spikes/pptx-viewer.md`.
  - Recommendation: `@aiden0z/pptx-renderer` (Apache-2.0, active) in a WKWebView, patched by four lines so every shape's element carries its OOXML id.
  - The agent reads the same ids from the XML (`Spikes/PptxViewer/pptx_outline.py`).
  - The proofs of concept are in `Spikes/PptxViewer/`.
- **The agent's reader, started before the viewer (DL-121):** `Pptx.outline` (`Sources/DuoSearch/Pptx.swift`, so `duo2` can use it without the app) gives each slide's shapes (OOXML id, name, type, groups, text, box in slide pixels), tables as tab-separated rows, charts with kind and series, and speaker notes.
  - Foundation can't unzip, so it has a small zip reader: the central directory, then stored or raw DEFLATE through Compression's `COMPRESSION_ZLIB`. It refuses zip64, encryption and entries over 64 MB. The XML parser never resolves external entities.
  - Tested on a real PowerPoint deck (PPTXjs's `Sample_12.pptx`): 12 slides with tables, charts, SmartArt and media in 9 ms, with the same shape counts as the Python spike.
  - The Python spike's `.//a:ext` also matched an extension list's `a:ext` and crashed on that deck. Both versions now read only the shape's own `xfrm`.
  - No `duo2` verbs yet: they come with the viewer's slot.
 an off-screen or ordered-back window counts as occluded, so requestAnimationFrame never runs and ECharts/nv.d3 charts stay blank. A 2%-alpha floating window that ignores the mouse renders them (`snap.swift`).
- Checks: 372 pass (on main as of 97ff92b), including five for binary detection and six for the deck reader. `NO_BUILD=1 scripts/check-ui.sh` passes (its six states are unchanged). Live captures on scratch data (own `DUO_SUPPORT_DIR` and `CLAUDE_CONFIG_DIR`) are in `build/ui/c26-*.png`.

## F-103 · Chat mode spike: where a live session's structure comes from (ENH-13, DL-118, 2026-10-06)

Verified on Claude Code 2.1.291. The real interactive TUI ran on a PTY with a headless screen mirror, pointed at a local mock of the Messages API (`ANTHROPIC_BASE_URL`, a dummy key pre-approved in a scratch `CLAUDE_CONFIG_DIR`). No credentials and no tokens; every dialog was produced on demand. Full write-up: `docs/plan/spikes/chat-mode.md`.

- **`MessageDisplay` hook** (added 2.1.152, documented): fires per batch of newly completed lines while assistant text streams.
  - Payload: `message_id` (not the transcript's uuid or the API id), `index`, `final`, `delta`: the **raw Markdown**.
  - A 40-line answer: first flush at +0.30 s, one per line, final at +10.9 s.
  - It can also transform or hide displayed text, so Duo's hook must keep printing nothing.
- **The transcript lags by a whole content block.** One line per block, written when the block completes: the same answer landed at +10.99 s, all at once. In a normal session, assistant lines landed a median 2.9 s after their timestamp (max 126 s for a large tool call). Use it for history and for what hooks don't carry, not for streaming.
- **`PermissionRequest`** carries the full `tool_input` and `permission_suggestions`, but **no `tool_use_id`**: match it to its `PreToolUse` by tool and input.
  - For `ExitPlanMode` the input holds the plan text and `planFilePath`; the tool itself now takes no plan parameter (2.1.285 fixed hooks seeing a stale plan).
  - **A refused plan or declined question fires no Post/Denied hook.** Only the transcript's `tool_result` (`is_error`, `toolDenialKind: user-rejected`, `userFeedback`) records it.
- **Subagents** are backgrounded by default ("Backgrounded agent (↓ to manage)"). `SubagentStart`/`SubagentStop` give `agent_id` and `agent_transcript_path` (`<id>/subagents/agent-*.jsonl`). Claude's own side agents send `SubagentStop` with no start.
- `UserPromptSubmit.source` separates the user's prompts from injected ones (task notifications, loop and schedule wakeups). `Notification` (`permission_prompt`) comes about 6 s after a dialog appears.
- **The IDE bridge** (lock files, websocket MCP: `openDiff` → `FILE_SAVED`/`DIFF_REJECTED`/`TAB_CLOSED`, `selection_changed`, `at_mentioned`) is in the binary, but its protocol is undocumented. Not tried.
- **Prior art** (summary in the spike): every rich chat GUI over Claude Code uses `-p`, stream-json or the SDK, which DL-118 rules out. Omnara v1 (PTY, JSONL tail, scraped prompts, removed 2026-08) is the only real overlay.

## F-104 · Chat mode spike: answering the TUI with keys, and the composer (ENH-13, DL-118, 2026-10-06)

- **Every dialog was answered with keys, from the PoC page, and the TUI took them**:
  - permission prompts: digits 1–3, Esc;
  - plan approval: 1, 2, or 3 plus typed feedback, which Claude received as "the user said: …";
  - AskUserQuestion: arrows and Enter; Space toggles multi-select; → goes to the next question; type into "Type something"; then "Submit answers" on the review page. Esc = "declined";
  - interrupt: Esc; mode: Shift+Tab.

  The cards use the **screen's verbatim option labels**: they vary by tool and setting, e.g. "Yes, and always allow access to `<dir>` from this project", or for edits "Yes, and switch to accept edits …".
- **Screen signatures for 2.1.291** (`Spikes/chat-mode/screen.mjs`):
  - "Do you want to …?" + numbered options + "Esc to cancel" (permission);
  - "Ready to code?" + "Would you like to proceed?" (plan);
  - "Enter to select ·" with a ☐/☒ tab strip (question);
  - "Review your answers" + "Ready to submit your answers?" (review);
  - the input box between the last two full-width rules, with the footer under it (idle, busy via "esc to interrupt", mode).

  Anything else is unknown → terminal. Checked: the API-key prompt, `/model`.
- **Input desyncs reproduced:**
  - after Esc, Esc the TUI kept `/mod` in its input, and the next paste became `/modSCENARIO:long`;
  - Ctrl+U removes only one line of a multi-line input;
  - the input's placeholder (`Try "fix lint errors"`) is dim text that reads as typed input unless cell attributes are checked;
  - a digit sent after a dialog closed lands in the prompt (`2SCENARIO:plan`).

  So: paste only into an input that's empty in non-dim cells, check the echo, and re-check a dialog's signature right before sending its keys.
- **Ctrl+G is a desync-free composer** (`chat:externalEditor`; also `ctrl+x ctrl+e`). With `EDITOR` set to a stand-in:
  - the TUI handed its current half-typed input over as `/tmp/claude-…/claude-prompt-<id>.md`;
  - it took the replacement back exactly (multi-line), and Enter sent it.

  Cautions: `EDITOR` is inherited by Claude's Bash tool, so a helper must act only on `claude-prompt-*.md`; the 2.1.269 redraw fix gates it.
- **The mock-API tour is the version check.** `Spikes/chat-mode/tour.sh scenario-tour.json <out>` runs every dialog against the installed CLI in under 30 s and dumps each screen (the 2.1.291 baseline is `screens/tour-2.1.291/`). Running it on each new CLI (and on the work Mac's 2.1.219) is how dialog signatures stay verified (C-1).
- **Not done:** no real-model turns (no login in a scratch config); the IDE bridge; Tab-to-amend, "Chat about this" and preview panes (fallback); fullscreen and Vim modes (fallback by rule, untested).

## F-105 · Chat mode under the CLI login: real turns, and what the mock missed (ENH-13, DL-118, 2026-10-06)

- **Chat mode needs only the Claude Code CLI login. No API key, no SDK.**
  - The test ran as a user would: plain interactive `claude` under Geoff's normal CLI login (the TUI header read "Haiku 4.5 · Claude Max"), `--model claude-haiku-4-5-20251001`, a throwaway folder in `/tmp`.
  - No `ANTHROPIC_API_KEY` or `ANTHROPIC_BASE_URL`, no credentials read or copied; hooks only through a per-session `--settings` file.
  - About 10 short turns over two sessions, both archived with `duo2 session archive`.
  - Every hook fired as with the mock: `MessageDisplay`, `PermissionRequest` (Edit, Bash, AskUserQuestion, ExitPlanMode), `Notification` (`permission_prompt`, `idle_prompt`) and the rest.
- **Verified with the real model, answers given from the PoC page:**
  - a streamed Markdown reply;
  - edit and Bash permissions;
  - AskUserQuestion with two questions, multi-select, Other text and the review step;
  - plan approval, with option 3 feedback (Claude revised the plan) and then option 2;
  - an interrupt;
  - Ctrl+G compose (half-typed text out, composed text back, sent).

  The edit, review and plan dialogs are line for line the mock baseline's. Real screens: `Spikes/chat-mode/screens/real-cli-login-2.1.291/`.
- **What the mock missed:**
  - **A named session writes its name into the input box's top rule** (`──── add-second-line-notes ─`). The PoC's rule pattern then failed, and every screen read as unknown. Fixed in `screen.mjs`; the mock baseline still reads the same.
  - **Concurrent hooks interleave.** The final `MessageDisplay` and `Stop` fire together. With real ~1 KB payloads, `sh` + `printf` appended in pieces and the two lines merged (2 bad lines in session 1), so the reply never got its end.
    - Fix: one `write(2)` per event with O_APPEND. The PoC uses a `perl` `syswrite`, and a mock re-run had 0 bad lines.
    - **Duo's own hook command in `HookEvents.swift` has the same weakness** (F-23's reader already skips bad lines, losing those events). It should get the same fix.
  - **An interrupted text reply fires no hook**: no final `MessageDisplay`, no `Stop`, no `PostToolUseFailure`. Only the screen going busy → idle ("Interrupted · What should Claude do instead?") ends it.
  - **The screen is blank for a moment** at start and while the external editor runs, and reads as unknown. The fallback should wait for unknown to persist; the PoC waits 500 ms.
  - The first run in a new folder shows the trust prompt. It read as unknown, fell back to the terminal, and chat came back once it was answered.
  - `PermissionRequest.permission_suggestions` said `destination: session` while the TUI's option said "… from this project". That confirms card labels must come from the screen.
- Also seen: a real plan can be longer than the TUI's dialog shows, and the card showed all of it. The plan file lands in `~/.claude/plans/` as with any plan-mode session.

## F-106 · Chat mode: AskUserQuestion, every shape, answered faithfully (ENH-13, DL-118, 2026-10-06)

Geoff: "please be sure to test how askUserQuestions works in chat mode". Result: **no AskUserQuestion shape needs the terminal.** The detail is in the spike doc's "AskUserQuestion in depth".

- **The schema (2.1.291):**
  - 1–4 questions, each with a `header`, 2–4 options (`label`, `description`, optional `preview` for single-select only) and `multiSelect`;
  - answers come back as `answers` plus per-question `annotations` (`preview`, `notes`).
- **TUI behaviours the card must follow** (captured in `Spikes/chat-mode/screens/ask-2.1.291/`):
  - A digit picks and submits a single question at once.
  - Multi-select lists end in an unnumbered **Next**/**Submit** row, and even one multi-select question ends on the review page; review **Cancel** declines.
  - The free-text row ("Type something.") ticks itself on multi-select. ↑/↓ leave it with the text kept; ←/→ and Space edit the text. The first PoC card sent Space after Other on multi-select, which types a space; it is fixed.
  - A revisited single-select marks its choice with a trailing ✔.
  - The current question tab is shown only by colour, so the current question is found by matching the screen's question text to the request.
  - **Previews** use a different layout: options left, the focused preview boxed right (clipped `✂ n lines hidden` in a short terminal), no free-text row, an unnumbered "Chat about this", and `n` for notes.
  - "Chat about this" tells Claude "The user wants to clarify these questions…".
- **Short or narrow terminals:**
  - a long question scrolls its top (and the tab strip) off screen;
  - labels wrap, so the screen shows only their start;
  - the clipped preview box uses `├`.

  Fix: take text from the request and structure from the screen. A question matches if the visible text is the end of exactly one asked question and every visible label is the start of the asked label at that position.
- **Answering** (`Spikes/chat-mode/ask.mjs`): the card sends intents, not keys.
  - The server checks the question and options against the pending `PermissionRequest`.
  - It moves one arrow at a time, re-reading the cursor row, until it is on the clicked row; only then Enter, Space or `n`.
  - Any surprise refuses and falls back. A stale card is refused with no key sent.
- **Tested:** `asktest.sh` runs 13 end-to-end cases (single, Other, multi tick/untick/Other, four questions with going back to change an answer, long wrapped, preview, preview + notes, Chat about this, decline, review Cancel, stale card) at 100×34, 60×34 and 80×20 against the mock: **39/39 pass**, each checked against what Claude received.
- **Real Haiku under the CLI login** (no API key; session archived), from the page:
  - Other on a single question;
  - four mixed questions with a changed answer and Other on a multi-select (answers exactly as clicked);
  - previews with notes (Claude quoted the note);
  - Chat about this, then a composer follow-up;
  - a decline.
- **No hook for declines:** a declined question and "Chat about this" fire no hook, not even `Stop`. Only the transcript's `tool_result` (`toolDenialKind: user-rejected`, no `userFeedback`) records it.

## F-107 · Scripted instances re-ask the install question, and one installed into Geoff's home (C-28, 2026-10-06)

Geoff: "many sessions are spawning fresh instances of duo -- each has no state and is reasking the installation questions". The detail is in `docs/plan/spikes/scripted-instances.md`.

- **Why it re-asks:** install consent is kept in the support folder (`Duo/installed.json`). Since F-89 every scripted run starts with an empty one, so each **non-capturing** instance (`open -n build/Duo.app --args --workspace …`, no `--capture`) asks "Let Claude sessions outside Duo use it?" again, 1 s after launch.
- **What's safe:** capture runs (`check-ui.sh`, `run-live.sh`, any `--capture`/`--capture-window`) never ask. The sheet doesn't block `--then` or `duo2`; it is a SwiftUI sheet (F-54 holds).
- **What isn't:** the question's targets aren't in the support folder.
  - `~/.local/bin/duo2` is always the real one, unless `DUO_INSTALL_ROOT` is set.
  - CLAUDE.md and the skill follow `CLAUDE_CONFIG_DIR`, otherwise `~/.claude`.
  - A fresh manifest also forgets the user-edit guards (`blockHash`, `skillHash`, `blockRemovedByUser`).
- **It happened:** at 10:49 an instance from session `b04dc5aa` (session-task-context work tree) relinked Geoff's `~/.local/bin/duo2` into that work tree's build. Its scratch `CLAUDE_CONFIG_DIR` kept CLAUDE.md and the skill safe.
- **Focus:** `SheetCenter.ask` activates the app over whatever Geoff is using, with **Install** as the default button, so one stray Return installs.
- **Shared between instances:** `UserDefaults` (search recents), the bundle id's notifications, and the duo2 link. Sockets, endpoints and hooks are per folder.
- **Rule for the fix:** whether an instance is isolated is decided by its support folder, not its flags. Geoff's acceptance Duo is `--workspace` with the real folder, and must stay his.
## F-97 · The task right-click menu, and a task's file following its name (DL-115, C-24, 2026-10-06)

- **The menu (board A)** is one view, `TaskMenuItems` (`Model/AppModel+TaskMenu.swift`), on Tasks fold lines, Open tasks at All projects and group-style task rows. An archived task gets board B's shorter menu. Set Status ▸ is now native toggles, so macOS ticks the current status, and it reads "in progress" as drawn. Add Session ▸ lists the project's sessions not yet linked (the note's `+ Add` list). Move to Project ▸ lists projects only: a plain folder has no `tasks/`.
- **Archive** writes `archived: true` into the note; the snapshot leaves it out of the lists, the Tasks fold's count and task groups (its kept sessions list as themselves), and `ArchivedSessionsFold` shows it after the archived sessions, counting both. Search indexes it as before. `duo2 tasks` marks it `archived`.
- **One undo for a task and its sessions:** `registerUndo` can gather steps (`asOneUndo`), so Archive, Unarchive and Move with sessions undo as one step; redo too. DuoChecks hands undo steps to a recorder (`undoRecorder`) to run them without a window.
- **Delete** trashes the note (undo moves it back from the Trash) and, with sessions, deletes each one exactly as Delete Session… does: the delete was pulled out of its question into `applyDelete` / `deleteSessionNow`. A session running in Duo or elsewhere is skipped and named. Deleting an archived session now also drops it from the archived list.
- **The questions** go through `SheetCenter` as Duo questions (board C). With `DUO_AUTOCONFIRM` a scripted run logs them and takes the default. `duo2 task archive|move` take `--sessions` or `--keep-sessions` to answer without asking; with neither, and `duo2 task delete` always, the user answers in Duo (timeout 600 s).
- **A task's file follows its name (C-24).** `TaskNotes.renaming` changes `title:` and the heading where it says the old name, and `TaskNotes.pathForTitle` picks `tasks/<slug>.md`, `-2`, `-3`… (a note already at its name, numbered or not, stays). Rename from the menu selects the name in the note. After each refresh, `followTaskTitles` compares every task's title with the last one seen and moves any changed note. **When:** once the note is saved and nobody has typed in it for 3 s, so typing in the heading never moves the file mid-word; a note in conflict waits. Edits from Claude or on disk move it on the next refresh. `duo2 task rename` writes and moves at once, with one undo. The open note follows the move (`moved` / `EditorController.fileMoved`, which now also reconciles, so text written just before the move shows). No collision prompt and no lost edits. Tabs, the right pane's tab, tab restore (`openDocumentsByProject`, `lastRightTab`) and the hover all follow. Drafted `@tasks/<old>.md` text isn't changed.
- **Task links:** `duo2://task/<id>`, the id a lowercase UUID written once into the note's `id:` by Copy Link (`duo2 task link`). Clicking one opens the note in whichever project holds it now. Tasks are otherwise still found by project and path.
- **duo2:** `task rename | archive | unarchive | delete | move | link | reveal`; Mark Complete and Set Status are `task status`, Add Session is `task add`. `docs/cli/duo2.md` regenerated.
- **Checked:** DuoChecks (28 new: rename and undo, the file following a retitle, Archive with sessions kept and included (a running one skipped), one undo for all, Unarchive, Copy Link's id, Move with and without sessions and undo, Delete with and without sessions (a scratch transcript really deleted, the running one kept) and undo, and each question's default) — 335 passed, 0 failed. `NO_BUILD=1 scripts/check-ui.sh`: the fixture states as before. Live, on a scratch workspace with its own `DUO_SUPPORT_DIR`, `CLAUDE_CONFIG_DIR` and a stand-in claude (no turns): `--then task-menu:<path>` (a new harness action, the context menu printed as text through `NSHostingMenu`) matched boards A and B item for item; the three questions captured against board C (`build/ui/task-archive-question-live.png`, `task-delete-question-live.png`, `task-move-question-live.png`); a heading typed in the editor moved `pull-the-top-three-quotes.md` to `pull-four-quotes.md`, saved, no conflict, the tab and tree following (`build/ui/task-rename-follow-live.png`); every new `duo2 task` verb run against that instance.
- **Not drawn, built to the nearest board:** the Move question when a session is running (moving doesn't stop a session, so it isn't named); the archived task's line keeps the Tasks fold's line look.


## F-113 · Isolated instances ask no install question, take no focus and write nothing outside their folder (fixes C-28, 2026-10-06)

The spike's recommendation 1 and 2 (`docs/plan/spikes/scripted-instances.md`, F-107), built.

- **One test:** `SupportFolder.isIsolated`. An instance is isolated when its `DUO_SUPPORT_DIR` is set to anything but the real Application Support: a temporary folder (F-89) or an explicit other one. It doesn't look at the launch flags. So Geoff's Duo (`open-duo.sh`: `--workspace`, `DUO_SUPPORT_DIR` = the real folder) and a plain launch behave as before.
- **No questions:** `InstallPrompt.run` returns at once in an isolated instance (one stderr line, `install: skipped …`), so LegacyPrompt never runs either. `GitIgnoreOffer` is non-interactive there (`DUO_GITIGNORE_ANSWER` still answers it).
- **Installer guard:** `Installer.refusal` makes `install` and `uninstall` (the launch, `duo2 install`/`uninstall` and Settings) refuse with a line saying why, before reading anything, unless `DUO_INSTALL_ROOT` is set. The install-loop checks and walks set it, so they still pass.
- **No focus:** every `NSApp.activate` goes through `DuoFocus.take()`, which does nothing when isolated. That covers questions, notification clicks, the Home and Missing folder pickers, walk setup and the window's first show. The exceptions are the debug harness's `event:`/`keys:` steps, which need a key window. The window still opens, behind whatever has focus.
- **Dock icon kept** (activation policy unchanged). Not taking focus already removes the stray-Return risk. `check-ui.sh` captures are byte-identical to `origin/main`'s for all six states, and a `run-live.sh` capture works. The run-live window draws as inactive (grey traffic lights), because the app is never frontmost.
- **The hole the live test found:** Duo's terminals inherited `DUO_SUPPORT_DIR` from Duo's own process. `open-duo.sh` sets it to the real folder, and `open -n` passes the caller's environment on. So a test Duo launched from any of Geoff's sessions ran on his **real** folder: it took over `duo.sock` and `endpoint.json`, came to the front, and on quit deleted both. That left his running Duo unreachable by `duo2` until it restarts. (It happened during this fix's first live run: pid 5204, 11:05.) Now `ChildEnvironment.make` drops `DUO_SUPPORT_DIR` when it's the real folder, so a session's scripted launch gets a temporary folder. An isolated instance still passes its own folder down. This takes effect for sessions started after Geoff's Duo runs this build. Until then, launch test instances with `env -u DUO_SUPPORT_DIR`.
- **Proof (live, `open -n build/Duo.app --args --workspace /tmp/x` with no `DUO_SUPPORT_DIR`):** it used `/tmp/duo-o46pyw`, its own socket and `install: skipped`. It wrote no `installed.json`, the front app stayed Geoff's Duo (pid 22756), and it quit with SIGTERM. `~/.local/bin/duo2` → `.claude/worktrees/session-task-context/build/…/duo2` before and after (left as Geoff chose). `~/.claude/CLAUDE.md` and the duo2 skill have the same hashes before and after.
- **Left for later (spike §4.3):** search recents in shared `UserDefaults`, and cleaning up old `/tmp/duo-*` folders.

## F-98 · A session knows its task, and hook events written whole (DL-116, C-27, 2026-10-06)

- **Claude Code 2.1.291, checked against its hooks docs** (code.claude.com/docs/en/hooks, hooks-guide):
  - SessionStart's input carries `session_id`, `cwd`, `hook_event_name` and `source`: `startup`, `resume`, `clear`, `compact` (and `fork`).
  - SessionStart and UserPromptSubmit both take `{"hookSpecificOutput": {"hookEventName": …, "additionalContext": "…"}}`. Claude reads it as a system reminder, with nothing shown in the transcript. No length limit is documented; ours is a few lines.
  - **Exit 2 from a UserPromptSubmit hook blocks the prompt**, so `duo2 hook context` always exits 0 and prints nothing when it has nothing to say or can't reach Duo.
  - `/clear` gives a new `session_id` and fires SessionStart `clear` with it. Compaction keeps the id (`compact`), and so does `--resume <id>`. Hooks on one event run in parallel, and UserPromptSubmit's default timeout is 30 s (ours is 10 s, with an 8 s socket timeout).
- **How it's built:** the session's settings file (`HookEvents.settingsFile`) gives SessionStart and UserPromptSubmit a second hook, `duo2 hook context`, after the event logger. It sends `session task <id> --hook start|prompt` to Duo.
  - Duo reads the task notes at that moment (`TaskContext.entries`, every project's `tasks/*.md` linking the id). It renders the text and records what it told the session in `events/<id>.task.json`, so a prompt is told about a change once.
  - Changes pair tasks by `id:`, then by note. A lone task that went and a lone one that came are one task renamed or moved (C-24's rename moves the note; Move to Project changes its project).
  - With no task, and nothing told before, there's no output at all.
- **After `/clear`** Duo finds the session it replaced in this order:
  - the id of the Duo terminal the hook runs under (the hook's parent process, before Duo re-keys the tab, F-29);
  - otherwise the `continued-from:` provenance;
  - otherwise `DUO_SESSION_ID`.
  
  Duo then adds the new session's link to each of that session's notes: in the editor's buffer if the note is open there, otherwise on disk. It doesn't do this on `resume` or `fork`.
- **What Claude reads** (one task, at start; paths are relative to Claude's folder when the note is inside it, otherwise absolute):

      Duo: This session is attributed to the task “Exec review prep” (status: in-progress).
      Its note, tasks/exec-review-prep.md, is the task's brief: read it before working on the task, and record progress and decisions there. Duo manages the `sessions:` list in the frontmatter; leave it as it is.
      Check this any time with `duo2 session task`.

  With two tasks, it's one line per task, `- “Q4 plan” (status: open, archived, id: …): <path>`. On a prompt after a change, one sentence per change comes first, then the same listing:
  - "The task “Exec review prep” is now review (was in-progress)."
  - "This session was added to the task “Q4 plan”."
  - "The task “Q4 plan” was renamed “Q4 plan final”." followed by "Its note moved from … to …."
  - "The task “Launch” moved to the project other; its note is now …."
  - "… was archived."
  - "This session was removed from the task “Q4 plan” (tasks/q4-plan.md)."
  - "This session has no task now."
- **C-27, events written whole:** the event logger is now one perl `syswrite` per event to a file opened `>>` (`O_APPEND`). Newlines are folded, and the event goes to the payload's first-key `session_id`, as before. sh's `printf` had written ~1 KB payloads in pieces that interleaved when hooks fired together. `at` now has milliseconds.
- **Checked:**
  - **DuoChecks:** 378 pass. New checks cover start, prompt with no change, resume/compact, absolute paths outside the project, a second task plus a status change mid-session (told once), rename with a new id and archive, Move to Project, unlinked from both, no task meaning no output, linked mid-session, never told before, the settings file's hook order, and 40 concurrent ~1 KB events giving 40 lines that all parse.
  - `scripts/bundle.sh` passes, and `NO_BUILD=1 scripts/check-ui.sh` passes (nothing visible changed).
  - **Live:** a scratch Duo (own `DUO_SUPPORT_DIR`, scratch `CLAUDE_CONFIG_DIR`, `DUO_INSTALL_ROOT`, a clean environment) ran a stand-in `claude` that runs the real hook commands from Duo's settings file with sample payloads. No model was called.
  - The live run covered New Session in Task → start context; an unchanged prompt → nothing; `duo2 task add` + `task status` → told once; compact → full context; `/clear` → the new id linked into both notes and full context; unlinking by hand → told once.
- **Scripted runs:** a launch without `DUO_INSTALL_ROOT` relinked Geoff's `~/.local/bin/duo2` (F-107, C-28). Set it, as well as `DUO_SUPPORT_DIR` and `CLAUDE_CONFIG_DIR`, until F-113's isolation is in the running build.

## F-108 · Chat mode build: reading Claude Code's screen from SwiftTerm, and falling back (ENH-13, DL-118, 2026-10-06)

- **SwiftTerm gives a host the visible rows as text, not cell attributes.** `visibleRowsText(_:)` and `terminalStateSnapshot()` are public; the `Terminal` and its `CharData` (where `dim` lives) are internal, and process output reaches the renderer without passing the view's open `dataReceived` (an adapter feeds it directly). So the spike's "blank dim cells" trick for the input's placeholder (`Try "fix lint errors"`) isn't available. The placeholder is named instead, in the signature table (`inputPlaceholder`, `otherPlaceholder` for "Type something."), so a version that changes it is a table edit. A mirror terminal fed from the PTY was the alternative; it isn't needed, because the composer's truth is Ctrl+G's file, not the screen (F-104).
- **The output signal is `setProcessOutputHandler`**: called on the IO thread after each batch, with no state. `ChatSession` hops to the main thread and reads 60 ms after the last batch, as the spike did.
- **The screen reader is a port of `Spikes/chat-mode/screen.mjs`** (`Sources/DuoKit/Chat/ChatScreen.swift`), its patterns in `ChatSignatures` per CLI version. DuoChecks reads the spike's captured 2.1.291 screens with it: every dialog, the review page, typed Other, previews, a long wrapped question, the named-session rule, retry and interrupt lines, and `/model`, the trust prompt and the API-key prompt as unknown.
- **Fallback, as built:** unknown for 500 ms (a timer, so a single repaint is enough to fall back); a dialog on a CLI version the table wasn't verified on (2.1.219 on the work Mac, or anything newer than 2.1.291) shows the terminal with the version named; a handover (Amend in Terminal…) shows the same bar. Both come back by themselves when the TUI is at its prompt again; the toggle's terminal stays. Nothing is sent to the session by any of it (checked with a scripted TUI that logs keys).
- **The CLI version** comes from `claude --version` once per binary, off the main thread.
- `duo2`'s token in a long-running session goes stale when Duo is relaunched: the edit hook (`duo2 hook pre-edit`) then refuses every Write with "wrong token", even for a new file nobody has open. Seen in this build session; the shell wrote the file instead.

## F-109 · Chat mode build: native rendering, and one log from two sources (ENH-13, DL-119, 2026-10-06)

- **Chat renders natively in SwiftUI, not in a web view.** The spike left the choice open. Native wins here: F-25 means a web view doesn't draw in window captures, so a web chat could only be checked in a browser while every board here compares through `scripts/check-chat.sh` like any other surface; the type, colours and radii come straight from the generated tokens; number keys, ⌘[ / ⌘] and VoiceOver work without a JavaScript bridge; and there's no second web process per session. Markdown is parsed into blocks in Swift (`ChatMarkdown`: headings, paragraphs with soft breaks kept, nested lists, fenced code, tables, quotes, rules); inline text goes through Foundation's Markdown parser, and bare URLs and file paths (`docs/flows.md:42`) become links (`duo-file:`) that open in Duo's editor at the line.
- What native costs: a link inside a paragraph can't have its own tooltip (Q-57b), and inline code's fill has square corners.
- **One log, two sources, matched** (`ChatLog`, `ChatIngest`): prompts by text, tools by `tool_use_id`, reply text by content (a MessageDisplay stream and the transcript's later block). A PermissionRequest finds its step by tool and canonical input (it has no id, F-103). Fixture recordings (`docs/design/chat-mode-handoff/fixture-chat/`, written by `scripts/make-chat-fixtures.py` in the real formats) are played in time order through the same code, so the boards exercise the pipeline.
- **History:** on attach the transcript is read once; the last 50 turns show, with Earlier turns (Q-56c). Hook events are read from the start of the turn in progress (after the last Stop), so a reply already streaming isn't lost; matching drops what the transcript also has.
- **Today's hooks** (`HookEvents.names`: SessionStart, UserPromptSubmit, PermissionRequest, PostToolUse, Notification, Stop, SessionEnd) already give prompts, permission requests and finished tools. Until chat mode's events are added (MessageDisplay, PreToolUse for every tool, PostToolUseFailure, Subagent*, Pre/PostCompact, StopFailure; after duo-v2-a6's change lands), reply text comes from the transcript a block at a time: correct, not streamed.
- The boards draw a few values the token additions didn't list (Bash output fill `#F8F9FA`, 12.5 pt inline code, 11.5 pt diffs, radii 4, 8 and 10). They're tokens now (`toolOutputFill`, `chatInlineCode`, `chatDiff`, `radiusChat*`), read from the approved boards.

## F-110 · Chat mode build: answering from cards, proved against the real TUI (ENH-13, DL-118, F-106, 2026-10-06)

- **The spike's end-to-end test now runs on Duo's own code**: `DUO_SUPPORT_DIR=<scratch> DUO_CHECKS=chat-live swift run DuoChecks` (`Sources/DuoChecks/ChatLive.swift`). It starts the real `claude` in a headless SwiftTerm terminal (a `LocalProcess` feeding a `Terminal`, no view) against the spike's mock Messages API, with a scratch `CLAUDE_CONFIG_DIR` and Duo's own per-session hook settings. No credentials and no tokens. `ChatSession` reads the screen and the hooks exactly as it does in the app, and answers with intents. Each case checks what Claude received in its transcript.
- **Results on Claude Code 2.1.291:** all 13 AskUserQuestion cases (single, Other, multi tick/untick/Other, four questions with going back to change one, a long wrapped question, preview, preview with notes, Chat about this, decline, review Cancel, a stale card refused) pass at 100×34, 60×34 and 80×20: **39/39**, as the spike's 39/39. Also at 100×34: a Bash permission answered Yes (the command ran), an edit refused with No (`toolDenialKind: user-rejected`), a stale permission card refused with nothing sent, plan mode reached by the mode chip's Shift+Tab, and plan option 3's feedback received by Claude.
- **A raw SwiftTerm buffer has NULs where the TUI moved the cursor instead of writing spaces.** `BufferLine.translateToString` returns them (`1.\0Postgres`); the view's `visibleRowsText` converts them to spaces. The reader now treats NUL as a space, so both paths read the same. Before that, every question was refused as "not the one Claude asked", and nothing was ever sent wrongly.
- `duo2 session chat answer [id] <n|cancel>` presses an option's key on the dialog on screen through the same checks (verified CLI, the request agrees, the same signature right before the key). An option that takes text (plan option 3, Type something) is refused with "answer it in Duo or the terminal".

## F-111 · Chat mode's hook events, on a6's atomic writer (ENH-13, DL-118, C-27, 2026-10-06)

- **Added to Duo's per-session hooks** (`HookEvents.chatNames`): PreToolUse for every tool (beside the pre-edit hook's `Edit|MultiEdit|Write` entry, never instead of it), PostToolUseFailure, SubagentStart, SubagentStop, PreCompact, PostCompact, StopFailure and MessageDisplay. Each runs the same one-`syswrite` perl writer as the others (F-98, C-27), prints nothing, and keeps `duo2 hook context` on SessionStart and UserPromptSubmit.
- **Gated on Claude Code 2.1.152 or later** (MessageDisplay's release; the other events are older). An unknown hook name in a `--settings` file could make an older CLI reject the file, and with it every hook Duo relies on. The version is asked once per `claude` (`claude --version`, a fraction of a second) when the first session starts. The work Mac's 2.1.219 qualifies.
- **Cost, measured** (this Mac, 50 runs of the hook command with a ~300-byte PreToolUse payload): **5.5 ms each** (median; p90 5.7 ms) for `sh` + `perl` + one `syswrite`. A busy turn of 50 tool calls adds about 0.3 s of PreToolUse in total, against model calls that take seconds each. A 40-line streamed reply adds about 40 MessageDisplay runs (about 0.2 s, spread over the ten seconds it streams). They stay on for every session Duo starts, in chat or not: switching to chat mid-conversation (Q-53) shows the turn in progress only if its events were written, and a `--settings` file can't be swapped in a running session.
- **Verified end to end** (`DUO_CHECKS=chat-live`, real TUI, mock API): the reply streams through MessageDisplay while it's written and shows once, whole, after the transcript's block arrives and is matched. The hook's line carries a fractional `at` (`%.3f`); chat mode's reader takes either.

## F-112 · Chat mode's composer is Claude's own prompt, through Ctrl+G (ENH-13, F-104, 2026-10-06)

- **How it works.** Duo's Claude sessions get `EDITOR` and `VISUAL` set to `<Duo.app>/Contents/Helpers/duo2 compose`; the user's own values move to `DUO_USER_EDITOR` and `DUO_USER_VISUAL`. On Return in the composer, Duo re-reads the screen, which must be idle or busy, never a dialog. It then leaves `{text, basis}` in `<support>/compose/<session>.json` and presses Ctrl+G. The TUI runs the helper on its `claude-prompt-<id>.md`. The helper puts the text in, but only if the prompt still holds the basis (what the composer opened on), then exits; the TUI loads the text. Duo checks the echo on screen and presses Return.
- **Nothing is lost either way.** Text half-typed in the terminal is read off the screen when the composer opens and becomes its basis, so it carries over. If the prompt changed in the terminal meanwhile, the helper leaves it alone and says what it holds; Duo sends nothing and shows the terminal. A message sent while Claude works shows as Queued until Claude Code takes it (its prompt hook). With no hand-over waiting (Ctrl+G pressed in the terminal, Claude's Bash running `git commit`), the helper execs the user's own editor.
- **Claude Code runs `$EDITOR` without a shell**: it splits the value on spaces and takes quotes literally. `'/path/duo2' compose` was never run; `/path/duo2 compose` is. So the helper's path must have no spaces. When it does (an app copy in a folder with a space), or below 2.1.269 (the redraw fix), or with Ctrl+G rebound in `~/.claude/keybindings.json`, the composer pastes instead, into a prompt the screen shows empty.
- **`/` in the composer** types the same prefix into Claude's own prompt (only over an empty prompt or one it typed itself). The menu shown is Claude Code's own list, with its own descriptions, filtered as typed. Commands with a screen of their own (`/model`, `/config` …) are marked to open in the terminal. The hand-over replaces the prompt on send, so nothing stays behind.
- **Verified against the real TUI** (`DUO_CHECKS=chat-live`): a hand-over into an empty prompt, carry-over, the changed-in-the-terminal refusal (text kept, nothing sent), paste-on-send, a message sent while busy, and the `/` menu.
- **Claude Code puts a suggested next prompt in its input as dim text**, and the screen reader can't see dim (F-108). In the app the composer first opened holding "ok", which would also have made the next hand-over refuse. So the composer never trusts the screen's input: when it isn't empty, a **peek** (Ctrl+G, the helper copies Claude's buffer to `<session>.peek` and changes nothing) gives the real text. This happens when the composer takes focus and, when no basis is known, at send. Verified against the real TUI.
- Images pasted into the composer hand over to the terminal (Q-56e's stand-in). Files dropped in show as chips by name and send their full paths (DL-117).
- **Everything that isn't the composer behaves as if Duo weren't there** (DuoChecks, with the built `duo2`):
  - (a) A user with no EDITOR or VISUAL: the helper opens `vi`, which is what git and most programs fall back to.
  - (b) The user's EDITOR with arguments (`code --wait`, `subl -w`) and with a space in its path still runs through `DUO_USER_EDITOR`/`DUO_USER_VISUAL`, its arguments intact, VISUAL before EDITOR. The space must be quoted, as git already needs, because the value runs through `sh -c`. Git's own `core.editor`/`GIT_EDITOR` still come first for git, so a user who set them is untouched.
  - (c) Plain shell tabs keep the user's EDITOR; only Claude sessions get the helper (`ChildEnvironment.make(sessionID: nil)`).
  - (d) A `git commit` run by Claude's Bash tool (no terminal, no hand-over): the helper execs `vi`, which fails without a terminal, and git stops with "there was a problem with the editor" in about 2 s. That is the same as without Duo. Nothing interactive opens and nothing hangs.

- **Real login, Duo's code** (`DUO_CHECKS=chat-real`, 2026-10-06; Claude Code 2.1.291, Haiku, Geoff's CLI login, no API key, `/tmp/duo-chat-real`, hooks only through the per-session `--settings`): 12 of 14 passed. Passed: composer send through Ctrl+G; the Bash card with Claude Code's own labels, answered Yes (the command ran); an edit answered Yes (the file changed, the step kept its diff); AskUserQuestion with a multi-select and Other, where Claude received exactly what was clicked; plan mode from the chip; the whole plan on the card; feedback through option 3, which Claude used to revise the plan. The two misses were the model, not chat mode: Haiku asked for clarification instead of writing the Markdown, and the last (counting) prompt produced no reply before the run ended, so the interrupt wasn't exercised in that run. A second run of the interrupt alone (`DUO_CHAT_REAL_ONLY=interrupt`) found a real bug: Claude Code records an interrupt in its transcript as a user text block, `[Request interrupted by user]`, and chat showed it as your message. It now ends the reply with Interrupted instead; with that fixed, the interrupt passes under the real login. Sessions `dec37133`, `6506dd6b` and `b7b267ad` archived.
- The live suite now takes free ports for its mock: another session was running the spike's mock on 8765, and its answers made unrelated cases fail.

## F-114 · What Google Docs' Markdown import keeps (ENH-14, 2026-10-06)

Tested by importing Markdown into a Google Doc through Drive (the same as File → Open of a .md), looking at it in Duo's browser (`/mobilebasic` view), and exporting it back as Markdown and HTML. The table is in `docs/plan/spikes/docx-to-markdown.md`.
- **Clean:** headings 1–6, bold, italic, strikethrough, inline code, links (including autolinks and bare URLs), `\` hard breaks, tight nested lists (`-` at 2 spaces, `1.` at 3), task lists, GFM tables with alignment, block quotes, `---`, **footnotes (real Docs footnotes)**, and images from `https:` or `data:` URLs.
- **Lossy:** fenced and indented code become plain body text. Loose lists gain an empty paragraph between items. Two lists separated only by a blank line or `<!-- -->` merge and keep counting. Relative image paths aren't imported. Raw HTML tags are dropped (text kept), except `<sub>`, `<sup>` and `<br>`. Pandoc's `~sub~` turns into strikethrough.
- **So Duo's converter writes** GFM with no raw HTML: tight lists, Unicode sub/superscript digits, and no lone `~`. Its output for nine test documents round-tripped through Docs unchanged in substance.

## F-115 · Converting .docx to Markdown: pandoc, mammoth and our own (ENH-14, 2026-10-06)

Nine synthetic documents (`Spikes/DocxToMarkdown/make_docs.py`), run through pandoc 3.12, mammoth 1.13 and a Swift prototype (`Spikes/DocxToMarkdown/Docx.swift`, on `Pptx.Zip`). Outputs are in `Spikes/DocxToMarkdown/out/`; the comparison is in `docs/plan/spikes/docx-to-markdown.md`.
- **pandoc** converts semantic structure well, but infers nothing. It drops the Title paragraph, splits "List Bullet 2" into a separate list, and writes raw HTML for layout or merged tables, images, underline and sub/superscript. It is 192 MB (Duo.app is 94 MB) and GPL-2.0-or-later: bundling it is allowed as aggregation, but it must ship with its licence and an offer of source.
- **mammoth's** Markdown writer loses tables, flattens nesting, escapes every `.` and writes raw footnote anchors. Its HTML is fine, but would need an HTML → Markdown step on top.
- **Neither** infers headings from font size or bold, or lists from typed `•`/`1.`, and both drop comments silently.
- **Our own** handled all nine documents: headings from size, bold and outline level; typed lists; nesting by indent; layout tables unwrapped; tracked changes accepted or rejected; comments left out or kept as footnotes; images extracted with alt text; and a summary of what it did.
- **Word's "List Bullet 2/3" styles** are separate lists at ilvl 0 with a bigger indent, not deeper levels. Nest list items by indent within a run of items.

## F-116 · Opening a Word document as Markdown, built (ENH-14, DL-123, 2026-10-06)

Built to `docs/design/docx-handoff/` (the canvas https://claude.ai/artifact/YRWyEm4MHbxYYtnRVr55xp). Side-by-side comparisons: `docs/design/docx-handoff/build-compare.png`.
- **The converter** is `Sources/DuoSearch/Docx.swift`, on `Pptx.Zip` and its XML reader (the spike's prototype, F-115). It adds comments as endnotes (the default, DL-123), a failure for each case the bar names, progress and cancellation (`Task.checkCancellation` every 64 top-level blocks), and the summary split into what was done and what didn't come over. `Spikes/DocxToMarkdown/main.swift` now builds against the app's source, so there is one converter. Its outputs in `out/duo` are the golden copies DuoChecks compares.
- **Telling failures apart without opening the file:**
  - A password-protected .docx is not a zip. It's an OLE compound file (`D0 CF 11 E0`) holding an `EncryptedPackage` stream (its name is UTF-16LE in the directory).
  - An old .doc is the same container without that stream.
  - Anything else that isn't a zip is damaged.
  - A zip with no `word/document.xml` isn't a Word document.
  - "Only pictures" is judged after converting: the Markdown is empty once the image links are removed.
- **The app:** `Model/AppModel+Convert.swift`.
  - The work runs on a detached task, and the bar shows only after 0.5 s.
  - Files are written on the main actor: pictures first, then the .md, atomically.
  - The copy takes the .docx's tab.
  - Undo is one step. It moves the copy and its pictures to the Trash, and moves back anything Replace trashed (from `trashItem`'s resulting URL).
  - A copy that is unsaved in the editor (`dirty`) or changed on disk since is left, and Duo says why.
  - A leftover `<name>-images` folder with no .md is never written into: the new folder gets " 2".
- **The sheet's field:** `DuoQuestion.Field`, a class so the choices read what was typed, drawn with `SheetRow` and `SheetField`. A path-only `Item` with `detail` draws "edited 2d ago" at the right. Under `DUO_AUTOCONFIRM` the name-taken question takes the free name.
- **A `Menu` styled as the default button** (`.menuStyle(.button)` with `DefaultSheetButtonStyle`) loses its chevron. The label draws `chevron.down` itself.
- **The editor's web view draws in window captures only sometimes** (F-25). The first D and E captures showed the converted text; after `main` was merged in, none did, even for a two-line file, though `editor-state` showed the right buffer each time. Editor text is exempt from the comparison; check it with `editor-state`, or in a browser at the pane's width. **Explained and fixed in F-120:** the merge wasn't the cause; the later captures were taken with the test window covered by other windows, and a covered window's web views have nothing to draw. Captures now draw each web view from its own snapshot. Board D's summary line was recaptured from `Spikes/DocxToMarkdown/make_board_d.py` (headings, typed bullets, tracked changes, a comment, pictures). The first D used the clean document, which had nothing to summarise.
- **Checks:** 27 new, all passing. They cover:
  - golden output for the nine documents, stable on a second run, with no raw HTML;
  - headings by size and bold, never skipping a level; typed lists; nesting by indent; layout tables; tracked changes both ways; endnotes; pictures;
  - the five failures;
  - the app's flow: the copy and its tab, the free name, a second name with its own folder, one undo step each, an edited copy left, Replace, and a refused scan writing nothing.
  - The suite's three other failures:
    - `docs/cli/duo2.md` passes once regenerated.
    - Encoder self-calibration and live beacons are checks "on this machine", not in code this branch touches.
- **Live, on scratch data** (own `DUO_SUPPORT_DIR`, scratch `CLAUDE_CONFIG_DIR`): `duo2 file convert` converted, refused a taken name with the free name to pass, took `--as`, reported a password-protected file, and `duo2 undo` removed the copy. Captures are in `build/ui/docx-*.png`.
## F-117 · Google calls Duo's browser unsupported because a bare WKWebView doesn't say it's Safari (C-32, Q-65, 2026-10-06)

Spike: `docs/plan/spikes/browser-engine.md`.

- **Cause:** a WKWebView's default user agent ends at `AppleWebKit/605.1.15 (KHTML, like Gecko)`, with no `Version/x Safari/605.1.15`. Google Docs and Sheets then show "This browser version is no longer supported". Measured signed out, on a public Doc and a public Sheet: the banner with the default user agent, none with the Safari token. Google sign-in also downgrades the bare user agent to its basic "WebLiteSignIn" page, while the token gets Safari's normal page.
- **Fix (built):** `WebUserAgent.applicationName` is `Version/<installed Safari's major.minor> Safari/605.1.15`. On macOS 26 and later it falls back to the system's version, because Safari is numbered after the OS. `DuoWebView`'s initializer sets it, so the browser tabs, the HTML viewer and the editor all send it. DuoChecks checks the token and that no web view is made outside `DuoWebView`. Proved in a live isolated Duo: `duo2 browser read` on the Doc and the Sheet shows no banner.
- **Not an engine problem:** the tabs already run Safari's WebKit. CEF would add about 200 MB and a rewrite of PageHost and the browser verbs, and would fix nothing more.
- **Gaps that remain, Duo's own, not WebKit's:** no file chooser (`runOpenPanelWith`), no downloads, no print, and popups load in the same tab without their opener (Q-65). Sign-in past the email step, and editing, comments and paste in a doc, weren't tested without a scratch account.

## F-118 · Printing a WKWebView: run its print operation as a sheet, never with run() (DL-124, 2026-10-06)

- **WebKit's print view paginates without end under `NSPrintOperation.run()`.** Saving a one-heading page to PDF with `run()` grew the file past 300 MB in seconds, with the main thread stuck (the test instance had to be force-killed; SIGTERM couldn't reach it). `runModal(for: window, delegate:didRun:contextInfo:)` with the panels off prints the same page as one 13 KB page. So printing needs the tab on screen in a window; `duo2 browser print` says so when it isn't.
- **With no panel, `didRun` arrives on the print operation's own thread.** A `@MainActor` callback trapped on the executor check (SIGTRAP). It's `nonisolated` and hops to main.
- **`window.print()` does nothing in a WKWebView** (there's no public delegate for it). A page-world user script replaces it with a message to Duo (`duoPrint`), which prints as ⌘P does. A scripted run (`DUO_AUTOCONFIRM`) saves a PDF in the support folder instead of showing the panel.
- **Downloads:** `decidePolicyFor navigationAction` returns `.download` when `shouldPerformDownload` (the `download` attribute, blob links); `decidePolicyFor navigationResponse` does for attachments and types WebKit can't show. `WKDownloadDelegate` picks the name: `DownloadNaming.unique` (Finder's `name 2.ext`, `.tar.gz` kept whole). An isolated Duo saves into its support folder's `Downloads` (F-113); `DUO_DOWNLOADS_DIR` overrides.
- **Zoom:** `pageZoom` per tab, remembered per host (without `www.`, port kept) in `browser-zoom.json`, applied when a page commits. `BrowserWebView.performKeyEquivalent` takes ⌘= as well as ⌘+, since the menu's `+` needs ⇧ on most layouts.
- Tested on local pages only (scratch folder, `localhost:8765`), in an isolated Duo with its own support folder and a scratch config: three downloads named `report.csv`, `report 2.csv`, `report 3.csv`, a zip and a blob; `--pdf` and `window.print()`; ⌘= twice gave 125% and the bar's indicator; the site's zoom came back on the next page.

## F-119 · Popups and real clicks in Duo's browser tabs (DL-124, 2026-10-06)

- **A popup's web view must be made from the configuration WebKit passes to `createWebViewWith`;** that's what ties it to its opener. Replacing that configuration's `userContentController` with a new one is allowed and needed: the copy shares the opener's controller, so adding the `duoPage` handler again would clash, and its messages would reach the opener's tab. With its own controller, the popup gets the picker and print scripts. Measured: `window.open` → the child sees `window.opener` and its `postMessage` reaches the parent; the child's `window.close()` → `webViewDidClose` closes its tab and the pane goes back to the opener.
- **target=_blank without `rel=opener` has no `window.opener`**, as in Safari (implicit noopener). It still opens as a tab beside the page, marked as its popup. A popup or link to a site not on the allow list opens in the system browser (DL-3), as other links do.
- **Mouse events sent straight to the WKWebView (`mouseMoved`, `mouseDown`, then `mouseUp` 50 ms later) reach the page as trusted events**, even in an isolated Duo whose window isn't key. A button that ignores `!isTrusted` events saw "ignored a synthetic click" from element.click() and "trusted click" from `duo2 browser click`, at 100%, 125%, 150% and 50% zoom (the viewport point is scaled by `pageZoom × magnification`). If the tab isn't in a window or the centre isn't in view, the click falls back to element.click() and says so.
- **`duo2 browser upload <selector> <file…>`** queues the files and real-clicks the element; the next `runOpenPanelWith` takes them instead of showing the panel (one file when the input takes one). Measured: a multiple input got both files' contents, a single input one, a `webkitdirectory` input a folder's files. The user's own click gets `NSOpenPanel` as a sheet, with multiple selection and folders as the page asks.

## F-120 · Web views were blank in captures when the test window was covered, not because of a commit (F-25, F-116, C-28, C-32, 2026-10-06)

- **The cause is whether the window is on screen, not the code.** A web view's pixels come from WebKit's web process. While its window is on screen they're in the view's layers, and `--capture-window` (`cacheDisplay` on the frame view) draws them. Once the window is covered by other apps' windows, WebKit marks the page hidden (`document.visibilityState` is `hidden`), and within a few seconds the layers have nothing in them. Captures then show the pane's background. A locked screen should do the same, because a window can't be visible then; that wasn't tested, so as not to lock Geoff's screen.
- **Measured on a scratch workspace** (own `DUO_SUPPORT_DIR`, empty `CLAUDE_CONFIG_DIR`, a stand-in claude), with `open:proj,doc:Plain.md,wait:5` and a two-line `Plain.md`:
  - **Launched as `run-live.sh` does:** `open` brought the instance to the front, and the editor drew at every commit tried: 67b2df6, c967072, f79ea3b, 7253064 and main (7169ff9). `editor-state` showed the buffer each time.
  - **Launched with `open -g`,** so the window opened behind the front app's windows: the editor was blank at every one of those commits, and before C-28 (97ff92b) and at C-28 (61be782). With no `wait:` it sometimes still drew, because the page had painted before the window was marked covered.
  - **So no commit introduced it.** The user agent (c967072), the non-persistent store (f79ea3b), browser basics (7253064) and C-28's "never activate" (61be782) make no difference. Before C-28 the instance did ask to activate, but a background launch's request was refused all the same.
- **Why F-116's captures changed when `main` was merged in:** the first D and E captures (16:46) and the later ones (16:59 to 17:01, after the merge) used the same launch. Most likely the later ones were taken while other windows covered the test window. macOS gives an app launched by `open` the front only when it's willing to switch away from what the user is doing at that moment. This is inferred from the measurements above; the window's state at 17:00 wasn't recorded.
- **Fix (built):** `WindowCapture.withWebSnapshots` runs before both `--capture` and `--capture-window`. It finds every web view showing in the window and has WebKit paint each one with `takeSnapshot` (`afterScreenUpdates` off, since a hidden page has no screen updates to wait for). Each snapshot goes into its web view as an image view while the capture is taken, so anything drawn above the web view still draws above it. If a snapshot doesn't arrive within 5 s, the capture goes ahead without it and says so on stderr. This covers the editor, the HTML viewer and browser tabs alike.
  - **WKWebView's `visibleRect` reaches 37 pt up under the toolbar** (its obscured inset), past its bounds. The first version used it, and the snapshot covered the tab bar. The rect is now `visibleRect ∩ bounds`.
  - **The capture's trace line now says whether the window was on screen:** `trace capture onScreen=… active=… editorReady=…`.
- **Proof:**
  - With the window covered, before (main): `build/ui/f120-before.png`, editor blank. After: `build/ui/f120-after.png`, `# Plain` and its line drawn.
  - With the window in front, the snapshot and WebKit's own layers give the same picture: the same positions, with antialiasing differences in the glyphs only.
  - The six fixture states (`check-ui.sh`) are byte-identical to main's: 0 differing pixels each.
  - DuoChecks: 546 passed, 0 failed. `check-editor-selection.mjs`: pass.
- **C-32 still holds:** the fix doesn't touch the stores. A new harness action, `browser-cookies`, prints the visible tab's store: whether it's persistent, and each cookie's domain and name (never values). In an isolated Duo the store was `persistent=false`. After `https://example.com/` it held no cookies. After `https://www.google.com/` it held only the four that visit set (`AEC`, `NID`, `SEARCH_SAMESITE`, `__Secure-STRP`), none of Google's sign-in cookies, and the page showed "Sign in".
- **Seen on the way:**
  - **A `claude` that doesn't answer `--version` hangs Duo's main thread.** `ClaudeVersion.known` (chat mode) runs `claude --version` and waits for it to exit (`TerminalSession.hookArgs` → `ClaudeVersion.ask`, `waitUntilExit`). A stand-in claude that ignored `--version` hung a scripted instance at launch, and only killing the stand-in freed it. A real claude answers quickly, but a wedged one would freeze Duo. Stand-ins for scripted runs must answer `--version`.
  - **CLAUDE.md** still says web views don't draw in window captures (F-25). With this fix they do, editor included, whether or not the window is in front.

## F-126 · A closed terminal is kept, and read, until its process ends: SwiftTerm's teardown left Claude exiting for good (C-30, 2026-10-06)

- **What Geoff's Duo showed.** After the restart into pid 48703, restore resumed 6dc1c061, a622b677 and 1cb0e487 with their tabs, as LR-58 asks: they had terminals open when the old Duo quit, because the director had started them with `duo2 session new` and never closed them. Restore didn't start anything without a tab. Twenty seconds later the director ran `duo2 session close` on all three (its transcript, 20:03:10). Close ended them, and the second close said "isn't running in Duo" because the tab was already gone. They stayed in `?Es` (exiting, no tty), `kill -0` reached them, and archive refused.
- **Why they never finished exiting.** `TerminalStore.close` sent SIGTERM and dropped the terminal at once. Dropping the view deinitializes SwiftTerm's `LocalProcess` while the child still runs. That stops its reader and closes the read fd, but keeps a dup'd write fd on the PTY master until a waiter thread has reaped the child ("keep the master open until the child reaps"). Claude, the session leader, writes its last frame and runs its exit hooks; it then enters the kernel's exit with output in the terminal that nobody will read, and waits there, past SIGKILL. So the master is never released, and the child is never reaped. Evidence:
  - `lsof` on Geoff's Duo: one fd each on four PTYs (15,10 to 15,13), against two for every live terminal.
  - `sample` of it: five `swiftterm-child-reaper` threads blocked in `waitid`, which is SwiftTerm's deinit path.
  - The real `claude` (scratch config, not signed in, no turn spent), run in a bare PTY torn down as SwiftTerm does (stop reading, keep the master open, SIGTERM, SIGKILL 0.5 s later), sits in `?Es ??` for good. One read of the master and it becomes a zombie and is reaped.
  - A process that exits with output unread waits even when it's small, if it was written from a second thread as Node does.
- **Fix (built):**
  - **`TerminalStore` never lets a running terminal go.** `close`, `forget`, and a `rekey` onto a key that already has a terminal all go through `release`. It sends SIGTERM when closing and keeps the terminal in `closing`, still read, until SwiftTerm reports the process ended and reaped (`processTerminated`, now also `onGone`). Then it drops it.
  - **SIGKILL follows after `TerminalStore.killAfter`** (3 s) if the process is still there. Closing pids still count as Duo's, never "running elsewhere".
  - **An exiting process has ended.** `ProcessLiveness.isRunning` is `kill -0` and not a zombie and not past exit (`P_WEXIT`, by `sysctl`). `Beacon.readAll` uses it, so a session whose Claude is stuck exiting isn't live: archive takes it, and it isn't "running elsewhere".
  - **Close and Archive end a Duo child with no terminal** (`orphanPid`, `endOrphan`). This is a beacon whose process's parent is Duo but which isn't one of its terminals, so it shouldn't occur now. `duo2 session close` ends it ("which Duo was running without a tab") instead of "isn't running in Duo", and Archive ends it rather than refusing.
- **`pgrep -P` doesn't list a process in state E.** To watch children through their exit, list their pids first.
- **Proof:**
  - **`scripts/check-reap.sh`** runs an isolated Duo with its own support folder and `CLAUDE_CONFIG_DIR`, three fixture sessions copied in, and a stand-in `claude` that exits like a signed-in one: its goodbye frame from a writer thread, then a second of exit hooks. A restore file lists the three idle sessions; `duo2 session close` ends them; then it watches for 5 s.
    - On main, all three were exiting, with only SwiftTerm's write fd left on each PTY: Geoff's signature. In that run they were freed about a second later, by timing Geoff's didn't have.
    - With the fix, none was ever exiting, every PTY was released once its process ended, and archive took all three.
  - **DuoChecks** (`ReapChecks.swift`):
    - A child exiting with its output unread is reached by `kill -0` but isn't running, and its beacon doesn't count.
    - A closed terminal is held as closing, then reaped and let go.
    - One that ignores SIGTERM gets SIGKILL.
    - Re-keying onto a taken key closes the terminal there.
  - `swift run DuoChecks`: 593 passed, 0 failed, 12 of them new. `scripts/bundle.sh` and `NO_BUILD=1 scripts/check-ui.sh` pass; nothing visible changed.
- **Seen on the way: one chat check reads the environment it runs in.** "(c) a plain shell tab keeps the user's EDITOR" fails when DuoChecks runs from a session inside Duo: that session inherits `EDITOR`, `VISUAL` and `DUO_COMPOSE_DIR` from Duo's compose helper. Run DuoChecks with `env -u EDITOR -u VISUAL -u DUO_COMPOSE_DIR` there. (No longer needed: the check now builds its own environment, F-127.)
- **Geoff's stuck three stay until his Duo next quits.** Their PTYs close then, and they end. With this build, archive takes them before that.

## F-125 · `claude --version` is asked with a 2 s limit, never on the main thread at length (C-34, F-111, 2026-10-06)

- Chat mode's hooks are added only for a CLI of 2.1.152 or later (F-111), so a session start needs the version. It was asked synchronously with `waitUntilExit()` and no timeout. A stand-in that hung on `--version` froze Duo.
- Now `ClaudeVersion.ask` waits on the process's termination for at most 2 s (`ClaudeVersion.timeout`). Past that it sends SIGTERM, then SIGKILL after 0.5 s, and the version is unknown. Unknown means chat mode's hooks are off for that session: the safe default (chat mode then renders from the transcript, and its dialogs go to the terminal). Duo's own hooks stay on.
- Each binary's answer is cached, including "none", so a hung or broken `claude` costs at most 2 s once per run. Duo asks at launch on a background queue (`ClaudeVersion.warm`), so the first session normally finds it cached. Choosing another `claude` in Settings clears it. The async path (`ClaudeVersion.of`) goes through the same bounded `ask`.
- DuoChecks: a stand-in `claude` that sleeps forever is ended in 2.0 s with the version unknown; the second ask doesn't wait; the settings for that session have no MessageDisplay but keep Stop; a working stand-in still answers; no orphaned child remains.

## F-124 · The tab close button: hover in the model, and the right pane's spacing laid out by hand (DL-126, 2026-10-06)

- **Hover lives in the model** (`AppModel.hoveredTab`, `hoveredTabClose`; DL-30 allows no `@State`), set by `TabHover` on the tab and by the × itself. The × shows while either names the tab, so moving from a right-pane title onto its × (outside the title) doesn't lose it.
- **The right pane's tabs were an `HStack(spacing: 18)`.** To put the × in the gap without moving anything, each document tab now carries a 16 pt slot and a 1 pt gap before its title, and the strip is laid out with `spacing: 0` and leading padding of 18 minus the slot. With nothing hovered the six fixture states are byte-identical to `main`'s captures.
- **On the console the × takes the glyph's 9 pt (or the shell mark's 11 × 9) frame** and overflows it to 16 pt, so the tab's width never changes.
- **⌘W only ever closes the visible tab** (`closeVisibleSession`, or `closeDocument` when the editor has focus). The × closes any tab, so it calls the same pieces by key: `closeShell` for a shell, `closeSession` for a session (what the Ended bar's Close Tab does), `closeDocument` for a document or browser tab (the tab menu's Close Tab). None of them asks anything; that's Q-71.
- **Busy, for DL-127 (`AppModel+CloseTab.swift`):** a session is busy when its state is working; a shell when `tcgetpgrp` on its PTY isn't the shell's own pid (the same test that titles shell tabs), named by `ForegroundCommand.title`. Every close path (⌘W's `closeVisibleSession`, the ×'s `closeConsoleTab`, End Session) goes through `confirmClose`, which closes at once when idle. Harness: `ask-close:<tab key>` or `ask-close:shell=<command>` shows the question in a fixture state. DuoChecks start a real login shell, run `sleep 30` in it and see it turn busy.
- **Harness:** `hover-tab:<tab key or document path>[=close|press]` holds the pointer over a tab, on its ×, or pressing it (`pressedTabClose`), for captures. In fixture states a session's key is its name (`hover-tab:Teardown research`).


## F-121 · The PowerPoint viewer (ENH-12, DL-121, DL-125, 2026-10-06)

- **What's built** (target `docs/design/pptx-handoff/`, boards A to E):
  - A `.pptx`, `.pptm` or `.ppsx` opens in `DeckView` instead of Quick Look.
  - `DeckViewer` hosts the vendored renderer (`Vendor/pptx-renderer/`: @aiden0z/pptx-renderer 1.3.0, Apache-2.0, hash-pinned, with the four-line id patch) in a web view.
  - Duo serves the page, its scripts and the deck's bytes through its own `duo-deck:` scheme. ES modules from `file:` URLs aren't dependable in WKWebView, and the deck needn't be passed as base64.
  - The page (`deck.html`, `deck.js`) restyles the renderer's list: no shadow, a `rule` round each slide, its number above. It reports the slide filling most of the pane, runs the shape picker with HTMLPicker's protocol (`window.__duo` start, stop, freeze, describe, hideOutline), and moves with ‹ ›, Page Up and Page Down.
- **One identity, two ways.** The renderer stamps `data-duo-shape-id` (`p:cNvPr`) on every shape, picture, table, chart and group. `Pptx.outline` reads the same ids from the file. DuoChecks renders the four synthetic decks in a real `DeckViewer` and finds every outline shape drawn with the same slide, id, name and groups: 6, 6, 13 and the garden deck's. Picking slide 2's shape 7 gives the outline's box to the pixel.
- **Picking and sending reuse the HTML flow.**
  - `DeckViewer` adopts `PageHost`, so start, stop, Pick Another, the screenshot and `visiblePage` work as on HTML pages.
  - The page describes a shape in `SendFormat.Element`'s shape: tag `shape`, the slide, id and type as attributes, the groups as the trail, the box as the rect. `pickedShape` reads it back.
  - `SendFormat.shape` writes board D's text; `send element` and `selection` use it for a deck.
- **Verbs** (DL-71), in a new `slides` family:
  - `slide`: the deck and the slide on screen, with that slide's outline.
  - `slide go <n>|next|previous`: counts from the slide just asked for, not the page's last report.
  - `slide shapes [<file>] [n]` and `slide notes`: from the file, so they work on any deck, showing or not.
  - `slide pick [<slide>/<id>]` and `slide element`.
  - Select Shape and Pick Another are `slide pick`; ‹ › are `slide go`.
- **Can't draw (E).** It is decided before trying:
  - a `.pptx` that is an OLE file is how Office saves a password;
  - one whose zip or slide list won't read is damaged;
  - the renderer's own failure reads "it uses something the viewer can’t read";
  - a page that doesn't load ends in "Duo’s viewer didn’t load", never "Drawing…" for ever.
- **C-26's note, done:** `EditorController.open` refuses a file that isn't text, whoever asks. `duo2 doc read` on a deck says it isn't text and names `slide shapes` instead of returning bytes.
- **Hardening:**
  - The page carries a Content-Security-Policy: scripts only from `duo-deck:`, images and fonts from `blob:` or `data:`, nothing from the network. A violation is reported to `DeckViewer.blocked` and logged; DuoChecks expects none with charts drawn.
  - A link on a slide opens only if it's http, https or mailto.
- **New token:** `size.deckBarHeight` 44 (`gen-tokens.py` and `gen-design-system.py` list sizes by name, so both scripts gained the line).
- **Proved:**
  - `swift run DuoChecks`: 570 pass, 26 of them new for the viewer and verbs. `scripts/bundle.sh` and `NO_BUILD=1 scripts/check-ui.sh` pass, and the fixture states are unchanged.
  - Live captures on scratch data (own `DUO_SUPPORT_DIR` and `CLAUDE_CONFIG_DIR`, the synthetic Garden deck) compared with the boards: `build/ui/pptx-viewer-compare.png`, `pptx-picking-compare.png`, `pptx-picked-compare.png`, `pptx-fallback-compare.png`. The chrome lines up; slide content and Quick Look are exempt.
  - Every verb was driven with `duo2` against that instance.

## F-122 · Scripted runs of the deck viewer: what they show and don't (2026-10-06)

- **Charts stay blank in scripted captures.** The capture window isn't on screen (`trace capture onScreen=false`), so WebKit runs no requestAnimationFrame and ECharts never paints. The spike saw the same in an occluded window (F-102), and charts draw in a window on screen. Slide content is exempt from the comparison, and DuoChecks checks the chart's shape id, not its pixels.
- **`--then` runs only with a capture.** A long-lived scripted instance (no `--capture-window`) ignores its actions, so the live `duo2` test opened the deck with `duo2 open` and `duo2 doc open`.
- **The path Claude is given** is relative to the session on screen's folder (`displayPath`), as for HTML elements. With no session open it's absolute, as in the scratch run. Board D's `decks/Garden plan.pptx` is what a session in the project gets.
- **Charts in a window on screen:** launched with `open -n` (each scratch variable passed with `--env`, so nothing reaches the real support folder), the capture's trace reads `onScreen=true`, and slide 3's chart draws with its axes, bars and labels under the page's policy (`build/ui/pptx-chart-visible.png`).
- **The picker bar is layout, not overlay** (director's review): the slide list ends at the bar's top edge, so no slide draws under it. The first compare overlaid the bar and cut a fixed 100 pt off the bottom, which hid the bar's first line. The compares now find each bar's top rule in both images and align on it. Bar heights are 97.5 against the board's 99.5 pt (C) and 45.5 against 47.5 (B), within the Duo button's 2 pt.
- **With a session showing** (a stand-in `claude`, F-87's pattern, no model), the "use Send To" line is gone and the bar is as drawn.
- **Narrow panes** (`paneMinRight` 360): the count shortens to `2/5`, and the picker's buttons wrap to two rows, Send to Claude and Send To above Pick Another and Cancel. DuoChecks lays both bars out at 460 and 360 and checks they need no more than that (`build/ui/pptx-bars-360.png`, `pptx-bars-460.png`). A live capture can't show it: the capture path puts the panes back at their design widths, so the harness's `right-width:` moves the divider but the picture keeps 460.
- **A scripted pick** (`slide pick 2/7`, `slide-pick:`) scrolls to the shape's slide first. The page then reports the shape again, so its screenshot is taken where it now is, not where it was before the scroll.

## F-127 · Remote Control for sessions Duo starts: `duo2 session new --remote-control [name]` (DL-128, 2026-10-06)

- **The CLI.** `claude --help` on 2.1.292 lists `--remote-control [name]` ("Start an interactive session with Remote Control enabled (optionally named)") and `--remote-control-session-name-prefix <prefix>` (for auto-generated names; default the hostname). The installs on this Mac (2.1.288 to 2.1.292) all have the flag, so the first version that had it isn't known here. Duo therefore doesn't gate on a version number. It gates on the flag itself: `RemoteControl.supported` runs `claude --help` once per binary, bounded by `ClaudeVersion.timeout` (2 s, C-34), and caches the answer. A failed or hung `--help` counts as no. Duo warms the answer at launch beside the version (`DuoApp`), and Settings' Look Again (`ClaudeLocator.forget`) clears it. `ClaudeVersion.output` is the shared bounded runner. It reads the pipe while the process runs, since `--help` is long enough to fill a pipe that nobody reads.
- **What's passed.** `TerminalCommand.newClaude` and `.resumeClaude` carry an optional `remoteControl` name. `TerminalSession.start` appends `--remote-control <name>` after the hooks and the primer, before a first prompt, only when the gate allows it. A fork doesn't inherit it: a fork is a new session and wasn't asked for.
- **The default name** is the project and the first 8 characters of the id (`duo-v2 3f2a9c1e`). The brief offered "the session's title" first. A session that `session new` just started has no title yet (Duo shows `LiveSnapshot.untitled`), so only the project-and-id name is ever available at that point. A given name is passed as is.
- **How it's remembered (item 2).** It's kept in the project's session index (`.duo/sessions.json`), as `remoteControl` on the session's entry, beside note and next. It's written only when the flag was actually passed, so the index says what the session was *started with*. `AppModel.terminal(project:session:)` reads it from the index every time it starts a terminal for a filed session. That path covers restore on relaunch (LR-58), `duo2 session open`, clicking the session, and a session with no transcript yet being started again. A Duo restart therefore keeps it without needing the restore state to carry it. A move to another project (`apply` in AppModel+Organize) carries the field into the new entry. Before, it rebuilt the entry with only the provenance, and still drops note and next as it did before. Why the index rather than Duo's support folder: the index already travels with the project, and it's where the per-session facts live.
- **Reporting.** `sessions --json` and `session show --json` have `remoteControl`: the name, or null. `session show`'s text says `Remote Control: on, as "<name>"` or `off`. `session new`'s reply names it, or, on a claude without the flag, says "Claude Code 2.1.100 doesn't take --remote-control, so the session started without Remote Control." (JSON `remoteControlUnavailable`). In that case the session starts, and nothing is remembered.
- **Parsing.** `Invocation.optionalValues` (`remote-control`): the next word is the flag's value unless it starts with `--`. So `--remote-control --prompt hi` doesn't name the session "--prompt".
- **Checks** (`RemoteControlChecks.swift`; `DUO_CHECKS=remote-control` runs them alone; 18). They use stand-in claudes that log their argv in a scratch support and config folder: present with the default name, present and named, before `--prompt`, absent, the index and both reports, a resume after a "restart" (a fresh model whose session list doesn't carry the name, with a transcript so it really resumes) passing it again, `session open`, a session without it starting again without it, and an old claude (2.1.100, no flag in `--help`): starts without it, says so, remembers nothing. No real claude was started with the flag. `--remote-control` combined with `--resume` is assumed from the help ("start an interactive session") and isn't verified against a signed-in claude. The director's first real session will show it.
- **A check that failed inside Duo, now fixed.** ChatChecks' "(c) a plain shell tab keeps the user's EDITOR" read the environment DuoChecks ran in. Inside a Duo terminal, `EDITOR`/`VISUAL` are already `duo2 compose` and `DUO_COMPOSE_DIR` is set, so it failed there. `ChildEnvironment.make` now takes a `base` environment (Duo's own by default). The check passes fixed ones, with and without a user `EDITOR`/`VISUAL`, so it passes inside and outside Duo with no `env -u`.

## F-128 · Captures at other window sizes, and `right-width:` moved the wrong split (DB-25, DL-129, 2026-10-06)

- **`--window <w>x<h>`** (and `WINDOW=1280x800 scripts/check-ui.sh …`) runs a fixture capture at that window size instead of 1440×900. The content area is the size less the 39 pt toolbar, as at the design size. It is a scripted flag (`SupportFolder.scriptedFlags`).
- **`right-width:<pt>` moved the All projects split, not the project's.** Both altitudes stay alive (RootView keeps them side by side), and the harness took the first three-pane split it found, which is All projects'. That is why F-121 saw "the capture path puts the panes back": the project's split was never moved. It now takes the split for the altitude on screen (`paneSplits`), so `right-width:500` gives 300 | 480 | 500 in a capture.
- **What today's build did at 1280×800 before DL-129** (`docs/design/narrow-handoff/before/`): every pane shrank in proportion (project 266 | 605 | 408, All projects 302 | 675 | 302), though `PaneSplit` set holding priorities meant to keep the side panes. NSSplitView didn't honour them; the hosts use autoresizing rather than constraints, which is the likely reason (not proven). The delegate below replaces them. The map wrapped topics in rows of two, leaving a hole beside Home's tile. Search (960 wide) and the toolbar fitted.
- **New fixture states:** `narrow-project`, `narrow-project-hidden`, `narrow-project-min`, `narrow-overview`, `narrow-overview-hidden`, `narrow-search` (`Debug/NarrowTargets.swift`; the overview ones add `vendor-review` directly in Home and two topics, Research and Ops). Harness action `right:hidden|shown`.

## F-129 · The resize rule and the packed map (DL-129, 2026-10-06)

- **Resize:** `PaneSplit`'s delegate implements `splitView(_:resizeSubviewsWithOldSize:)`, so the side panes keep their width and the middle takes the change. Under the middle's minimum, the right pane gives way first and then the left, each down to its own minimum (`PaneWidths.resized`, checked in DuoChecks). The map's minimum is the token `paneMinimumProposed.map` 440 (it was a literal 400).
- **Captures against the narrow-handoff targets** (`build-narrow-*-compare.png`), all at 1280×800:
  - pane edges at exactly 300 | 520 | 460, 340 | 600 | 340, and 300 | 480 | 500 at the minimum;
  - search 160–1120 by 92–753, against the target's 752.
  - Differences are fixture content, not layout: the document's typography, and the map's group order. The build orders groups by the map's sort, Recent, so Ops and Research swap columns against the board, which assumed name order. The packing rule is the same.
- **Packing:** `PackedColumns` is a SwiftUI `Layout` (a protocol, not a macro). It measures each topic column at the column width and places it under the shortest column so far, leftmost on a tie (`MapPacking`, checked). The tile flows (the lone column and ACTIVE OUTSIDE HOME) still wrap in rows, as approved.
- **A project directly in Home is filed under the empty topic `""`**, which must be in `topics`, not under a nil topic: a nil-topic project is dropped from the map.

## F-130 · Sliding a pane without resizing the terminal on every frame (DL-129, 2026-10-06)

- NSSplitView doesn't animate `setPosition`, so the slide sets the panes' frames itself at 60 fps for `motion.paneToggle` (200 ms, ease-in-out), then collapses the pane for real. The resize rule waits while it runs (`isAnimatingPane`).
- **The terminal is held:** while `PaneMotion.running` is set, a terminal's slot keeps the terminal's frame and clips it (`clipsToBounds`). The slot lays out again when `PaneMotion.endedNotification` posts, so the PTY is resized once, at the end (LR-14).
- **A hidden pane remembers its width, not its divider position,** noted before the slide starts. Noting it after the slide caught a frame of about 0 and brought the pane back at nothing; a position would also go stale if the window is resized while the pane is hidden.
- **Panes restored on launch** (`pendingCollapse`) snap into place without a slide, as does everything under Reduce Motion (`accessibilityDisplayShouldReduceMotion`).
- **Not verified by capture:** that the 150 ms fade of a new tile (`.transition(.opacity.animation(…))`) runs when the map changes outside an animated transaction. The slide and the search fade can be seen in a live run, but a still capture can't show motion.

## F-132 · The peek in captures: a transient popover closes when Duo loses focus (C-35, 2026-10-06)

- **Cause:** the peek is SwiftUI's `.popover`, which AppKit shows as a transient NSPopover. A transient popover closes when its app resigns active, and SwiftUI then sets the binding to false (`model.peekOpen = false`), so the capture drew no popover. A test copy launched by `open` is often activated by LaunchServices, and it loses focus again when the user's own app takes it back. Hence missing in some runs and present in others. A copy that is never activated (`open -g`) keeps its popover; activation alone isn't the trigger, losing it is.
- **Reproduced on demand:** the harness action `deactivate` (`NSApp.deactivate()`, as a click into another app). `--state flow-zoom-3 --then deactivate` lost the popover every time before the fix (687,352 pixels differ from a good capture).
- **Fix:** in capture mode (`FixtureHarness.holdsPeek`), the popover's binding ignores the popover closing itself. `peekOpen` stays true and SwiftUI keeps the popover up. Esc, the chip and the scripted actions still close it through the model. No in-window stand-in is needed, so the capture still draws the real popover.
- **Proved:** each run compared with a known-good capture (`scripts/samepng.py`):
  - `--then deactivate` and `--then deactivate,wait:1,deactivate` (a second loss of focus after the popover settles): 0 pixels differ in 8 runs.
  - `NO_BUILD=1 scripts/check-ui.sh flow-zoom-3`: 0 pixels differ in 5 runs in a row, with Duo (Geoff's) in front.
  - DuoChecks passes.
- **Tried and dropped:** a fallback that closed and reopened the peek if the popover was missing just before capture. It never fired once `peekOpen` was held, so it isn't shipped.

## F-131 · Motion: one Reduce Motion flag, tokens with easings, and frames mid-motion (DL-130, Q-77, 2026-10-06)

- **One flag.** `MotionSettings.shared` (`Design/Motion.swift`, an `@Observable` class) holds `reduce`, read from `NSWorkspace.accessibilityDisplayShouldReduceMotion` and updated on `accessibilityDisplayOptionsDidChangeNotification`.
  - Every animation is built from a token through it: `DuoMotionToken.x.animation` (nil with Reduce Motion), `.duration`, `.delay` (kept with Reduce Motion: `rowHold` is time, not motion), `.css` for the web pages.
  - `.duoAnimation(.x, value:)` and `withDuoAnimation(.x) {}` wrap SwiftUI's.
  - Before this, the map's drag springs and the chat scroll ignored Reduce Motion, and only `RootView` read it.
  - DuoChecks fails if any other file reads the system setting or uses a spring.
- **Tokens:**
  - `motion` gains DL-130's 25 durations, and a new `motionEase` map gives each token `out`, `in`, `inOut` or `none` (the delay).
  - `gen-tokens.py` writes `DuoMotionToken` (seconds and ease) beside `DuoMotion`'s constants.
  - `gen-design-system.py` lists them all with their uses.
- **Proof without screencapture (Q-77).** Duo's own capture path (`cacheDisplay`) draws a SwiftUI animation's in-flight values, so frames can be taken mid-motion. Search's scrim at `DUO_MOTION_SCALE=10` read `#FFFFFF`, `#EBEBEC`, `#D2D3D4`, `#C0C1C2` and `#B7B8BA` at 0, 300, 600, 900 and 1500 ms.
  - `DUO_MOTION_SCALE=<n>` stretches every token n times. `DUO_REDUCE_MOTION=1|0` overrides the system setting.
  - `--then` gains `+<action>`, which runs 20 ms after the action before it (not 0.6 s), and `film:<prefix>:<ms>|<ms>|…`, which writes `<prefix>-<ms>.png` at those offsets. Frames land within about 2 to 120 ms of their time; the log says how late.
  - `scripts/check-motion.sh <name> <state> <setup> <trigger> [offsets]` runs a motion twice, with Reduce Motion off and on. A `live:<workspace>` state runs on real folders with an empty scratch `CLAUDE_CONFIG_DIR`, so sessions start signed out and spend nothing.
  - `scripts/filmstrip.py build/motion/<name> X Y W H` lays one region of every frame side by side, motion above and Reduce Motion below.
  - Harness actions `drag-lift:`, `drag-over:` and `drag-land:` set the map's drag state as a real drag would.
- **Drag and drop on tokens** (DL-130, item 4):
  - F-51's look is unchanged.
  - The source sinks and the target rises over `lift` (200 ms, ease-out, no spring); the landed fill and capsule take `landed` (400 ms). The capsule fades and no longer scales.
  - With Reduce Motion nothing scales, and the outline and shadow are there at once.
  - Proof: `build/motion/drag/strip.png`, on a live workspace (drag feedback exists only in live mode). The motion row rises across 0 to 1500 ms at scale 10. The Reduce Motion row is identical from 0 ms, at 100%.
- **Unchanged at rest:** overview, project, flow-zoom-1, 2 and 4, idle-list, and `sheet-move` capture identically (0 pixels differ) against origin/main's build.
- **Records:** F-132 on main was taken by the peek-capture fix, inside this branch's reserved range (F-131 to F-133), so this branch skips it.

## F-133 · Duo's sheets hang from the toolbar (DL-130, 2026-10-06)

- **`SheetOverlay` is always in the tree** and holds the sheet only while `sheetIsUp`. Inserted by RootView's `if`, a child's transition never ran: SwiftUI applies only the inserted parent's.
  - The sheet moves in from the top edge, `.transition(.move(edge: .top))`: `sheetIn` 200 ms ease-out going down, `sheetOut` 150 ms ease-in going up.
  - A mask starting at the hairline the sheet hangs from (1 pt above the content area) keeps it under the toolbar while it slides.
  - The map's dim to 55% runs on `scrimIn` / `scrimOut` inside its own pane, because each pane is its own hosting view.
- **The next queued question:**
  - `QuestionSheet(q).id(q.id)` fades, `sheetSwap` 120 ms, inside the sheet's container, which stays put, so it doesn't drop again.
  - A taller or shorter question changes the sheet's height at once.
- **Proof** (`scripts/check-motion.sh`, scale 10; strips in `build/motion/sheet-{in,out,swap}/strip.png`):
  - `sheet-move:` on overview slides down over 0 to 1.6 s;
  - `answer:OK` slides it up and it's gone by 1.2 s;
  - `ask-close:` then `ask-update:`, answering Cancel, cross-fades the close question into the update question in place.
  - With Reduce Motion, every frame from 0 ms is the end state.
- **Unchanged at rest** against origin/main's build (0 pixels differ):
  - overview, project and flow-zoom-1 to 4;
  - `sheet-move:`, `sheet-new:`, `ask-update:`, `task-archive:` and `ask-close:`.

## F-134 · The session list moves; folds turn; the list holds still under the pointer; folders list at once (DL-130, Q-79, Q-80, 2026-10-06)

- **One flat list.** The project's session list was a `ForEach` of sections, each with its own `ForEach` of rows, so a row that changed section was a different view: removed in one place, inserted in another.
  - It is now one `ForEach` of `SidebarItem`s (labels, gaps and rows, keyed `row/<id>`), so a row travels to its new place.
  - The animation is `.duoAnimation(.rowMove, value: <item ids>)` on the whole column, so the buttons and folds below move with it. Keyed to the ids, not the rows, it doesn't fire when only a wait time changes.
  - Rows fade in (`rowIn`) and out (`rowOut`). Changes come on the 2 s snapshot, outside any click's transaction, so the animation keys on the result, not the action.
  - Mid-move, a travelling row passes over the rows it crosses.
- **Held under the pointer (Q-80).**
  - `.onHover` on the list calls `AppModel.hoverSidebar`. Coming in, it notes each section's row ids (`sidebarHold`). While held, `SidebarRow.held(fresh, order:)` keeps listed rows in their noted section and place, with fresh state (glyph, wait). A new row joins its own section, so + New session shows at once, and a row that's gone, goes.
  - Leaving, the hold drops inside `withDuoAnimation(.rowMove)`, and rows travel to where they now belong.
  - A section's count follows the rows it lists while held.
  - DuoChecks checks `held`.
- **Folds turn.**
  - `Chevron` is `Animatable` with a `turn` from 0 (right) to 1 (down). The down chevron is the right one turned 90° about its centre, so mid-turn draws that rotation, and the ends draw the two original paths: pixel-identical at rest.
  - Every fold toggles inside `withDuoAnimation(.fold)`: groups, threads, Earlier and Older, Tasks, Archived, the map's archived projects, and file-tree folders.
  - A fold's rows use `.foldRows`. They fade in over the second half of `fold`, once the rows around them have moved. The file tree grows upward from the bottom of the pane, and rows fading in at once overlapped the rows still sliding.
- **Folders list at once (Q-79).** `toggleFolder` reads the tree the way the snapshot does (`LiveSnapshot.treeFiles` with the project's open folders) before asking for a refresh. The folder opens with its files, and the snapshot that follows finds nothing to change.
- **Harness:**
  - `session-state:<name>=<state>[@wait]`, `session-add:<name>=<state>@<wait>` and `session-remove:<name>` change the fixture as a snapshot would.
  - `sidebar-hover:on|off`.
  - `collapse:<key>`.
  - `expand:` and `folder:` now animate as a click does.
- **Proof** (scale 10; `build/motion/<name>/strip.png`, motion above and Reduce Motion below):
  - `row-move`: Teardown research to Needs you; it travels up, Today's label fades, the button slides.
  - `row-new`: a session added; it fades in while the row below slides down.
  - `fold`: PRD v2 collapsing; the chevron is mid-turn at 900 ms.
  - `hold`: the state changes with the pointer in; the row keeps its place with its new glyph, then travels when the pointer leaves.
  - `tree`: live, `folder:research`; the files are listed 20 ms after the click and fade in once the rows have moved.
  - Reduce Motion: every change is at once.
- **Unchanged at rest** against origin/main's build (0 pixels): overview, project, flow-zoom-1 to 4, the Archived fold open, idle-list, and a sheet. `collapse:` can't be compared: main's harness doesn't have it.

## F-135 · Mark Complete holds for 5 s; changes show before the snapshot, without flicker (DL-130, Q-78, 2026-10-06)

- **Mark Complete** (Geoff's change in DL-130):
  - The task's line shows at once checked (the box takes the properties block's check mark), struck through and in `text2`, with status `done`.
  - It stays for `rowHold` (5 s), then fades out (`rowOut`) while the lines below close up (`rowMove`).
  - ⌘Z or Mark Open during the hold keeps the line, unchecked.
  - `completingTasks` holds the line in the Tasks fold and in Home's open tasks (`listedTask`). Only a task that was listed open holds: one already done just stays done.
  - With Reduce Motion, the 5 s hold is kept (it's time, not motion), and the line then goes at once.
  - A task with sessions is a group row; it stays and reads `done · n`, as before.
- **Shown at once (Q-78):** `showNow` applies Archive and Unarchive (session and task), Set Status (and its undo), Mark Complete and + New task to the listed model as soon as the file is written. The lists animate by their own row ids. Text and marks change at once.
- **No flicker, and a gap fixed.** `refreshLive` does nothing while a snapshot is in flight, so the click's refresh was skipped, and the snapshot already in flight (read before the write) landed with the old state. Before this the click showed nothing until the next tick. With a change shown at once, the old state would have come back for a beat.
  - Now every shown change bumps `localChange`. A snapshot started before the latest bump is dropped, and a new one is read at once.
  - It logs `live: dropped a snapshot read before a change Duo had shown (Q-78)`.
  - Opening a folder (Q-79) bumps it too.
- **Proof** (live workspace, empty scratch `CLAUDE_CONFIG_DIR`, `build/motion/<name>/strip.png`):
  - `new-task` (scale 2): the task is in the fold 100 ms after + New task, fading in.
  - `complete` (scale 6): checked and struck through at 0 ms, held to 30 s (5 s × 6), gone after.
  - `complete-out` (`DUO_MOTION_HOLD=3`, scale 20): the fade and the lines closing up. Task lines are now opaque on the pane, so a sliding line covers the one leaving.
  - `complete-undo`: Mark Open 2 s in keeps the line, unchecked, past the hold.
  - `flicker`: `refresh` then Mark Complete 20 ms later, with frames every 100 to 500 ms for 11.5 s. The snapshot in flight was dropped in both runs (the log). Every frame shows the task checked until it leaves; none shows it unchecked again.
- **Session list polish** (the director, on slice 3): a row changing section is lifted above the rows it passes (`zIndex`, from `sidebarShown`), and every label and row is opaque on the pane, so no text overprints mid-move or mid-fold. Re-captured: `row-move`, `fold`.
- **Harness:**
  - `task-complete:<path>`, `task-open:<path>`, `archive-session:<name>` and `refresh`;
  - `DUO_MOTION_HOLD=<s>` sets `rowHold` for proof runs;
  - `BEFORE_EACH=<command>` in check-motion.sh puts a workspace's files back before each run.
  - Fixed: `filmstrip.py`'s crop at 0,0 (sips centres it).
- **DuoChecks:**
  - One task check rebuilt the archived list from `fixture.sessions` alone. Archiving now moves the session out at once, so it reads both lists.
  - Not verified by capture: archiving a session at once. The scratch workspace has no quiet session to archive without spending a turn; DuoChecks covers it.
- **Unchanged at rest** against origin/main's build (0 pixels): the ten fixture states, and a live Tasks fold cropped to the sidebar.

## F-136 · The chat review card rises in place of the composer and sinks after the answer (DL-130, 2026-10-06)

- **The card** (`ChatPane`):
  - When Claude's dialog comes up (`cardUp`), the review card moves up from the pane's bottom edge into the composer's place (`cardIn`, 200 ms ease-out) while the composer fades.
  - Once the screen shows Claude has the answer, it moves back down (`cardOut`, 150 ms ease-in) and the composer fades back.
  - `cardUp` comes from the screen scrape, outside any click's transaction, so the pane animates on `cardUp` itself.
- **No overprint:**
  - The card is opaque and sits above the composer (`zIndex`), and it moves without fading, so it covers the composer's text while they cross.
  - A first try faded the card as it moved, and "Reply to Claude" showed through it.
  - While leaving, the card draws its answered state (options greyed), because the screen has already changed.
- **The feed:**
  - It keeps the alignment chat mode already gives it: bottom while a card is up, top otherwise. A short conversation therefore slides down to sit above the card as it rises, and back up after.
  - Its scroll stays pinned to the bottom. Streaming and the Terminal/Chat swap are unchanged (DL-130: no motion).
- **Harness:** `chat-screen:<kind>` sets a fixture chat's screen, as if the dialog came or went.
- **Proof** (scale 10; `build/motion/card-{in,out}/strip.png`): `chat-permission-edit`, `chat-screen:idle` then `chat-screen:permission`. With Reduce Motion, every frame is the end state.
- **Unchanged at rest** against origin/main's build (0 pixels):
  - the chat boards window, text, permission-edit, plan, question-multi, question-review, composer and fallback;
  - overview and project.
- **Checks:** DuoChecks 627 and the chat checks (`DUO_CHECKS=chat`) 96 pass.

## F-137 · Tabs fade in and out while the strip slides; notice bars slide down from under the tabs (DL-130, 2026-10-06)

- **Tabs** (console strip, the right pane's strip, Home's strip):
  - A tab opening fades in (`tabIn`) and a tab closing fades out (`tabOut`). The rest of the strip, `+` and the chevron included, slides (`tabMove`), keyed on the tab ids, so a title change or a re-shortening doesn't animate.
  - Every tab and the `+` are opaque on their strip (`console` or `pane`). A first capture had the sliding `+` overprint the tab fading under it.
  - The hover × is unchanged: instant, as DL-126 says.
  - Tabs that move into or out of the `» n` menu fade like any other.
- **Notices** (`NoticeMotion`): the document's state bar (conflict, removed, renamed, read only, converted) and a browser tab's download notice slide down from under the tab strip, `noticeIn` 150 ms ease-out, pushing the document or page down; OK slides them back up, `noticeOut`. The container clips them, so they never draw over the tabs.
- **Left at once, on purpose:**
  - a bar that comes with its view: a binary file's or Word document's bar, or the deck that won't draw;
  - the chat fallback bar, which sits over a live terminal. Sliding it would resize the PTY on every frame (LR-14), so it appears at once.
- **Proof** (scale 10; `build/motion/<name>/strip.png`):
  - `tab-open` (`shell`): the shell's tab fades in, and `+` slides along, covering it.
  - `tab-close` (`close`): the tab fades out under the sliding `+`.
  - `notice` (live, `user-type:` then `disk-write:` on the same line, 20 ms apart): the conflict bar slides down over 0.4 to 1.6 s, pushing the document.
  - With Reduce Motion, every frame is the end state.
- **Unchanged at rest** against origin/main's build (0 pixels): overview, project, flow-zoom-1 to 4, shell-tab, the hover × on a console and a document tab, chat-window and narrow-project. DuoChecks 627 and the chat checks 96 pass.

## F-138 · Claude's highlight fades in and out in the editor (DL-130, 2026-10-06)

- **In:**
  - A new highlight (`duo-added`) also gets `duo-added-new`, which animates its background from nothing to `selected` over `motion.highlightIn` (200 ms, ease-out).
  - After that, a `settleAdded` effect gives the marks the plain class. CodeMirror recreates a mark's span whenever it redraws the line, so a class that kept the animation would fade in again on every redraw.
- **Out:**
  - The user's next edit clears the highlight at once, as before (DL-5): `addedField`, `changesField` and what Revert can put back are unchanged.
  - A separate `fadingField` draws a copy of the cleared ranges as `duo-added-fading`, which animates from `selected` to nothing over `motion.highlightOut` (600 ms, ease-in-out), then is removed.
- **Timings:**
  - They reach the page with the token CSS: `--duo-motion-highlight-in-ms` and `--duo-motion-highlight-out-ms`, from `DuoMotionToken`, so zero with Reduce Motion or `DUO_REDUCE_MOTION=1`, and scaled by `DUO_MOTION_SCALE`.
  - The page also checks `prefers-reduced-motion`, so a system change mid-session takes effect without a reload. The keyframes are added to the page once.
- **Proof in Chromium, not window captures.**
  - Duo's window captures snapshot the page (F-120), but WebKit doesn't advance page animations in a window that isn't on screen (F-102). The frames held the start colour, then jumped when the class changed.
  - `node scripts/check-editor-motion.mjs` (playwright-core, as check-editor-selection.mjs) runs the built page at the pane's width and samples the highlight every 50 ms. Opacity goes 0, .38, .69, .91, 1 over 200 ms in, and 1, .98, … .04, 0 over 600 ms out. With `reducedMotion: reduce`, the highlight is there at once and goes at once.
  - `film:` frames now snapshot web views too, as the final capture does: without it, the editor drew blank.
- **Unchanged at rest:**
  - project, flow-zoom-2 and flow-zoom-3 (0 pixels);
  - a live document with a settled highlight, cropped to the editor, against origin/main's build (0 pixels).
  - check-editor-selection passes (108 clicks, 42 drags, 108 shift+down). DuoChecks checks the page gets the timings.
- `Vendor/codemirror/dist/cm6.js` rebuilt with `build.sh` (`npm ci` from the lockfile); only this change differs.

## F-139 · The needs-you chip fades and its count rolls; a jump between projects fades the project up (DL-130, 2026-10-06)

- **The chip:**
  - It fades in and out in place (`chipIn`, keyed on whether anything needs you elsewhere); nothing before it in the breadcrumb moves.
  - Its count uses `.contentTransition(.numericText(value:))` with `motion.count`.
  - Captured (`FILM=filmw`, the whole window, since the chip is in the toolbar): `chip-out` fades over about 1.2 s at scale 10. `chip-count` shows the digit mid-roll at 150 ms, but the roll ends by 300 ms even at scale 10: the toolbar's numeric text transition appears to keep its own timing. It's short either way, and with Reduce Motion it's instant.
- **Project to project** (the peek's ⌘↩, the breadcrumb, search):
  - The project layout is one set of views, holding the terminals, so it can't cross-fade with itself. It drops to 0 at once and fades up over `altitude` (`projectShown`).
  - RootView's altitude animation is now keyed on All projects ↔ project alone. Keyed on the whole altitude, a jump between projects animated every change under it.
- **No cross-fade of one project into another:**
  - The first capture showed the old project's names and rows under the new ones. The list and tab animations (slices 3 and 6, keyed on row and tab ids) took a project switch for a mass of rows leaving and arriving.
  - The session column, the console strip and the right pane's strip now take the project as their identity (`.id`), so another project replaces them at once.
  - Re-captured `p2p`: blank at 0 ms, then only onboarding-v3, fading up. With Reduce Motion, at once.
- **Harness:** `filmw:` (and `FILM=filmw` for check-motion.sh) captures with the toolbar.
- **Unchanged at rest** against origin/main's build (0 pixels):
  - overview, project, flow-zoom-1 to 4, a jump to onboarding-v3, idle-list and chat-window;
  - window captures, with the toolbar and chip, of project and flow-zoom-3.
  - DuoChecks 628 pass.

## F-140 · The deck scrolls to a slide and the picker's outline glides (DL-130, 2026-10-06)

- **‹ › and Slide n:**
  - `go()` scrolls by script over `motion.slide` (250 ms, ease-in-out). CSS's smooth scroll has no duration.
  - Opening a deck at a remembered slide, and a scripted pick (`slide pick`, which reports where the shape is for its screenshot, F-121), jump at once.
- **A page with no animation frames still lands.** WebKit gives a page that isn't on screen no `requestAnimationFrame` (F-102), so the scroll would never finish there; a capture showed "Slide 3 of 5" over slide 1. A timer lands on the slide `slide + 150 ms` after the jump whatever happened. Re-captured in a live window: on slide 3 by 3 s at scale 10.
- **The outline** (picking) glides to the next shape: left, top, width and height over `motion.outline` (80 ms, ease-out), with its name tag. It appears where it lands, with no glide from where it last was.
- **Timings:** they reach the page through the same token script as the editor (`--duo-motion-slide-ms`, `--duo-motion-outline-ms`): zero with Reduce Motion. The page also honours `prefers-reduced-motion`.
- **Proof in Chromium:** `node scripts/check-deck-motion.mjs` serves the page with `Spikes/PptxViewer/decks/garden.pptx`. The test's copy of the page lets its policy name the local origin instead of `duo-deck:`.
  - scrollY from slide 1 to 3: 0, 6, 21, 81, 180, 245, 378, 474, 507, 544, 549 over about 250 ms;
  - the outline's top: 44, 57, 68, 77, 83, 85 over about 80 ms;
  - with `reducedMotion: reduce`, both are at their end from the first sample.
- **Unchanged at rest** against origin/main's build, live, cropped to the right pane (0 pixels): `slide-go:3`, picking with a hovered shape, and a picked shape. DuoChecks 628 pass.

## F-141 · Chat items fade in; drop targets light up; DL-130 closed out (2026-10-06)

- **Chat items:** a new item (your prompt, a tool card, Claude's reply) fades in where it lands (`messageIn`, keyed on the item count). Streaming text grows in place. Proof: `chat-in` (`chat-prompt:` harness on `chat-text`).
- **Drop targets:** a folder under a file drag, or the tree's empty area for the root, fades its highlight in (`dropIn`). Proof: `drop-in` (`drop-hover:docs`).
- With Reduce Motion both are at once. Unchanged at rest against origin/main's build (0 pixels): project, overview, chat-window, chat-text, chat-tools, chat-status, chat-composer and `drop-hover:docs`. DuoChecks 628 and the chat checks 96 pass.
- **DL-130 is built** (F-131, F-133 to F-141; F-132 is the peek-capture fix on main). The docs are updated:
  - `docs/design/motion-handoff/README.md`: built, and where the build departs from the boards;
  - `docs/design/README.md`: built;
  - the design system's README Motion section, a Motion row in `surfaces.md`, and a Motion line in twelve component READMEs (ArchivedFold, ChatMode, DeckViewer, DocumentStateBar, FileTree, NeedsYouChip, PaneTabs, ProjectTile, SessionList, SessionRow, Sheet, TaskLine).
  - The design-system artifact is for the walk session to republish.
- **Tools left for later motion work:**
  - `scripts/check-motion.sh` (with `FILM=filmw`, `BEFORE_EACH`, `live:`);
  - `scripts/filmstrip.py`;
  - `scripts/check-editor-motion.mjs` and `scripts/check-deck-motion.mjs`;
  - `DUO_MOTION_SCALE`, `DUO_MOTION_HOLD` and `DUO_REDUCE_MOTION`;
  - harness actions `film:`, `filmw:`, `+<action>`, `session-state:`, `session-add:`, `session-remove:`, `sidebar-hover:`, `collapse:`, `task-complete:`, `task-open:`, `archive-session:`, `refresh`, `chat-screen:`, `chat-prompt:`, `drag-lift:`, `drag-over:` and `drag-land:`.

## F-146 · A session is told its project's brief (ENH-16, 2026-10-06)

- **Built on DL-116's hook, nothing new installed.** `duo2 hook context` (SessionStart, UserPromptSubmit) now returns the project's lines first, then the task's, one blank line apart, as one `additionalContext`. `ProjectContext` (`Sources/DuoKit/Live/ProjectContext.swift`) reads `PROJECT.md` at each hook, never cached, and records what it told in `events/<id>.project.json`, beside the task's `<id>.task.json`, so a prompt is told about a change once.
- **Which project:** the one Duo files the session under, if it has a `PROJECT.md`; otherwise the nearest folder at or above Claude's folder with one (DL-82). A Home session, or one outside every project, is told nothing.
- **What Claude reads** at startup, resume, clear and compact (empty fields are left out):

      Duo: This session is in the project “checkout” (/Users/…/checkout). Its brief, from PROJECT.md (the user sees it on the project's tile in Duo):
      - Goal: Ship the new checkout by November
      - Health: at risk
      - Next step: Fix the tax rounding bug

  - A brand-new `PROJECT.md` (only `health: on-track`) gets one line: "Its PROJECT.md has no goal or next step yet."
  - **When the project's `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` imports it** (a line with `@PROJECT.md` or `@./PROJECT.md`; a mention without the `@` doesn't count), the guide's workaround, it's the name and folder only: "Its CLAUDE.md imports PROJECT.md, so you already have its goal, health and next step."
  - On a prompt after `PROJECT.md` changed, one line per field: "The project's health is now “on track” (was “at risk”).", "The project's goal was cleared (was “…”)." It's told even when CLAUDE.md imports the brief, since Claude read CLAUDE.md at start. A session that leaves the project, joins one or moves to another is told so once. A session started before this build hears it all on its next prompt.
- Only the three properties are passed, never the note's body; the guide (`docs/guide/projects.md`, "Claude is told the brief") keeps `@PROJECT.md` as the way to give Claude the whole note.
- **Checked:**
  - **DuoChecks:** 650 pass. 23 new checks cover start, an unchanged prompt, a subfolder, a session filed under the project, resume and compact, health and next changed (told once), goal cleared, imported (`@`, `@./`, a mention isn't an import), a change while imported, a new brief, never told, leaving, joining, moving, and joined with a task.
  - **Live:** `scripts/check-context.sh` runs an isolated Duo (its own support folder and `CLAUDE_CONFIG_DIR`) with a stand-in `claude` that runs the real hooks from Duo's settings file with Claude Code's payloads; no model was called. It checks startup, an unchanged prompt, an edit to `PROJECT.md` told once, compact, and resume with `@PROJECT.md`: 7 pass. Home's session, started at launch, is told nothing.
  - `scripts/bundle.sh` and `NO_BUILD=1 scripts/check-ui.sh` pass (nothing visible changed).

## F-147 · Open sessions say so on their tile (ENH-7, DL-133, 2026-10-06)

- **What was already there** (F-61): an open session (a terminal in Duo) is listed on its tile and tinted (`activeTint`), and the project's session list already said `at prompt` or `working` for one (DL-91). DB-33, the tint's look, was the open item. The director folded DB-33 into ENH-7, so DL-133 closes it.
- **Built:** one rule, `SessionState.waitText(_:open:)`, now drawn by both the session list and `TileSessionRow`. Open and idle reads `at prompt`; open and working reads `working`; needs you keeps its wait; ready for review shows no time. The tint stays on unselected open rows. The tile row's accessibility label says "open in Duo", and keeps "waiting ‹time›" only where the time still shows.
- **Harness:** `open-sessions:<name>+<name>` marks fixture sessions open (`fixtureActive`). Names are joined with `+` because `--then` splits on commas.
- **Checked:**
  - DuoChecks: 4 new checks of the rule, 654 pass in all.
  - A capture of the overview fixture with four sessions open, compared with the board: `docs/design/small-features-handoff/build-compare-tile.png`.
  - `NO_BUILD=1 scripts/check-ui.sh`: the fixture states are unchanged, since no session is open in them.

## F-148 · `@` for files and folders in chat's composer (ENH-3, DL-133, 2026-10-06)

- **Why only the composer.** Claude Code's own prompt already completes `@` in the terminal (its own list, folders too), and Duo draws nothing over the TUI. Chat mode's composer had no `@` at all.
- **Built:**
  - `Chat/FileMention.swift`:
    - the `@` word at the caret (at the start, or after white space or a dropped file's chip; an address like `geoff@example` isn't one);
    - matching, case-insensitive, up to 8: names that start with the query, then names that contain it, then paths that contain it, shallower first, then A–Z; a bare `@` lists the top level, folders first;
    - the project walk: Claude's folder at any depth, as the file tree lists it (no hidden files, `.git`, `node_modules`, `build`, `.duo`), capped at 5,000, off the main thread, cached for 10 s so typing doesn't walk again.
  - `ChatMentionMenu`: the `/` menu's look. ↑↓, ⏎ or tab adds, esc closes until the caret leaves that word. A click on a row is `// action: session chat`, as the `/` menu's rows are.
  - The chosen file goes in as `@path ` (relative; a folder ends in `/`), and every `@` mention in the field is set in mono, as the board draws it.
  - The hint line adds `@ files` (it drops before `/ commands` when narrow).
- **Claude Code expands a mention that comes through the composer.** Checked against 2.1.292 with no tokens: the real TUI ran on the spike's mock API with a scratch config, and the prompt was handed over through Ctrl+G with `EDITOR` writing the file, as `duo2 compose` does. Results:
  - `Summarise … @docs/flow.md` reached the API with the file's contents attached (a Read result in a system reminder).
  - `@docs/sub/` reached it with its listing (a Bash `ls` result).
- **Harness:** `chat-cwd:<folder>` (the fixture chat's folder), `chat-type:<text>` (typed into the real field, so its menus follow), and `chat-key:up|down|tab|return|esc`.
- **Checked:**
  - DuoChecks: 13 new checks covering the word at the caret, ranking, case, path matches, a bare `@`, no match, the cap, rows, the inserted text, and the walk's skips. 667 pass in all.
  - Live captures in the `chat-text` fixture against a scratch project: typing `@chec`, ↓ then tab, a folder with ⏎, no match, and esc. `docs/design/small-features-handoff/build-compare-composer.png` sets them beside the boards.
  - `NO_BUILD=1 scripts/check-chat.sh`: the boards are unchanged apart from the composer hint's `@ files`. `NO_BUILD=1 scripts/check-ui.sh` passes.

## F-142 · The app icon, built without Xcode (DL-131, 2026-10-07)

- **Drawn in code.** `scripts/gen-app-icon.swift` draws 2A′ with CoreGraphics on the canvas's 1024 grid. It writes `docs/design/icon-handoff/AppIcon.iconset/` (16 to 512 pt at 1x and 2x) and builds `AppIcon.icns` with `iconutil`. 16 and 32 pt use the small art; 128 pt and up the full art. The outputs are committed, so `bundle.sh` only copies them: `Contents/Resources/AppIcon.icns` and `CFBundleIconFile` = `AppIcon`. `release.sh` builds through `bundle.sh release`, so release DMGs carry it too.
- **Use the canvas's rounded squircle, not a superellipse.** A superellipse (n = 5) made the sides bulge and left a dot where the path closed. A rounded rect, radius 185 on 824, matches the approved board.
- **macOS keeps the icon as it is.** `NSWorkspace.icon(forFile:)` on the built app returns the new icon at 1024, 128, 32 and 16, with the small art at 32 and 16. macOS adds its own rim light and doesn't put it in a grey box. The render is `docs/design/icon-handoff/screens/build-proof-system-icon.png`.
- **`qlmanage -t` on the `.app` hung** (more than 2 min, killed). Use NSWorkspace for icon proofs instead.
- **No dark or tinted variants:** those need an Icon Composer `.icon` and `actool` (Q-81).

## F-155 · The icon ships in release builds; the old one comes from 0.2.2 and from apps started before the icon (DL-131, 2026-10-07)

- **0.2.2 has no icon.** It was cut before e29c7c4: no `AppIcon.icns`, no `CFBundleIconFile`, so macOS draws the generic app (grid on a white squircle). Any installed or Sparkle-updated copy shows that until the next release.
- **The release path carries it.** `bundle.sh release` in a fresh work tree of 7f131f8, then release.sh's own steps up to signing (`ditto --norsrc`, PlistBuddy, `xattr -cr`, Developer ID with Hardened Runtime, inside out): `codesign --verify --deep --strict` passes, `AppIcon.icns` is byte-identical to the handoff's and sealed in `CodeResources`, `CFBundleIconFile` = `AppIcon`. `NSWorkspace.icon(forFile:)` on the signed app (Finder) and `NSRunningApplication.icon` on it running (app switcher, Dock) draw 2A′ as in `icon-handoff/screens/build-proof-system-icon.png`; the Finder render differs from `build/Duo.app`'s by 4 antialiased pixels. Notarizing and stapling don't touch Resources. macOS 27 (26A428) draws the `.icns` without a grey box, so no asset catalog is needed to ship it.
- **Rebuilding in place is picked up at once.** `bundle.sh` removes and rewrites `build/Duo.app`, then runs `lsregister -f`: a 0.2.2 copy running from a folder, swapped for the new bundle underneath it, reported the new icon through `NSRunningApplication` straight away. Nothing more to touch or re-register.
- **What stays old is the running process.** An app sends its Dock tile and loads `NSApp.applicationIconImage` (About panel) when it starts, so a Duo launched before its bundle got the icon keeps the old tile until it quits. Quitting and reopening fixes it. Duo isn't kept in the Dock, so there's no stale persistent tile. Dock pixels weren't captured: screencapture(1) is off for scripted runs (F-54).
- **Asset catalog (`CFBundleIconName` + `Assets.car`) only buys dark, clear and tinted variants** (Q-81). `actool` isn't in the Command Line Tools (`xcrun --find actool` fails), so it would need Xcode or a prebuilt `Assets.car` committed from a machine that has it. Not needed to ship the icon.

## F-149 · The hovered tab's fill (DL-134, 2026-10-07)

- **`TabHoverFill`** (`Project/TabClose.swift`) draws a rounded fill in the tab's `.background`, padded outward with negative padding and framed 24 high, so the tab's size and its neighbours never change. It shows when `showsTabClose` does (the pointer on the tab or on its ×), so the fill and the × always come and go together. It's on the console's tabs, Home's sessions and shells, and the right pane's document and browser tabs. Project, group pages and a read-only session have no ×, so they get no fill.
- **The right pane's fill was hidden under the next tab.** Each right-pane tab is opaque (`.background(DuoColor.pane)`, so a tab fading out is covered as the others slide, DL-130), and its leading padding is part of its frame. The hovered tab's 7 pt reach on its right went under the next tab's padding, so the fill looked cut off. The hovered tab is now raised (`zIndex` 1). The console doesn't need this: its tabs are 18 apart and the frames don't include the gaps.
- **On the right pane the fill starts 3 before the × box**, not 7: the box already holds 4.5 of space around the 7 pt ×, so the glyph sits about 7.5 inside the fill's edge, which matches the 7 after the name. A document as the strip's first tab hangs its × 17 left of its title (DL-126), so its fill starts 0 from the strip's edge. The fixture never shows this, because Project always comes first.
- **Proof:** `docs/design/tab-hover-handoff/build-compare.png` puts board A above the build's two strips in the same five states (`hover-tab:` and `=close`/`=press` over `Teardown research`, `PRD v2 edits`, `PROJECT.md` and `docs/prd-v2.md`). Measured with `scripts/pixels.py`: the console fill is `#202329`, from y 6 to 30 in the 36 strip, 7 past the glyph; the right fill is `#F3F4F6`, 24 high. With nothing hovered, the only change from `main` is the right pane's 24 pt spacing.
- The boards in `screens/` are the canvas's `.dc.html` with their holes and loops expanded, so Chrome renders them without the canvas runtime.

## F-151 · Runs of tool calls, from real transcripts and the TUI (DL-135, 2026-10-07)

- **How long runs are.** In the last 80 sessions on Geoff's Mac (read-only tally of their transcripts): 3,253 runs of tool calls between pieces of Claude's text; 70% have two or more calls, 41% mix tools, and Bash is 7,070 of about 11,000 calls. Thinking blocks (7,922) sat between most calls, and each split the old thread in two.
- **The terminal's own words.** Claude Code's collapsed lines, as transcripts quote them: `Ran 4 shell commands`, `Read 3 files`, `Edited 2 files`, `Searched for 1 pattern, read 1 file, listed 1 directory, ran 1 shell command`: one combined line for a mixed run. The chat's run line copies that form (`ChatRuns.clauses`), with edits' file names and `+n −n` after a dot.
- **The boards disagreed.** C1 and C2 drew a line per kind; C3 and the candidates drew one combined line. Geoff chose one line (2026-10-07); C1 and C2 were corrected on the canvas and in `chat-polish-handoff`.
- **Grouping is a view of the log.** `ChatRuns.blocks` reads a turn's segments and never changes the log, so a step waiting on you leaves its run and rejoins it once answered, and a run keeps its first step's id (`run-<id>`) for its open state as steps arrive.
- **Bash's `description`** (Claude's one-line summary of a command) is in nearly every recent call; a run line leads with it and falls back to the command.
- **Built only when opened.** Outputs and diffs (a `Write` used to draw the whole file) build only when their step is opened, which helps chat's scrolling (fix/chat-perf).

## F-152 · The thin strip over chat (DL-136, 2026-10-07)

- **Which strip shows** follows `AppModel.consoleShowsChat`: the selected console tab is a Claude tab whose chat is showing. A chat that fell back to the terminal (or a shell tab) keeps the dark strip and `ConsoleRule`; so does the fallback bar's terminal.
- **28 includes the rule.** The board's strip is `height: 28px` with `box-sizing: border-box` and a 1 bottom border, so the strip is 27 and the rule 1 (`chatStripHeight − borderHairline`). Measured with `scripts/pixels.py`: the underline and the rule land on the board's rows.
- **The light toggle's border is outside its segments** (22×16 each inside a 1 border: 46×18), unlike the dark one's (26×20 with the border inside). Its right edge is 11 from the pane's edge, as drawn.
- **The hover fill (DL-134) stays** on the thin strip, in `selected` (`ground` would vanish on a `ground` strip), and the × uses the right pane's light colours.
- **Q-87's stand-in:** tabs keep their state glyphs in light colours (`StateGlyph(.light)`), so a waiting session's needs-you dot doesn't disappear while you chat. The board draws none.
- **Tab fitting** measures titles in `control` on the thin strip, so `» n` and the 24-character cut work the same as on the dark one.
- **Proof:** `docs/design/chat-polish-handoff/proof/chat-polish-bar-thin-compare.png`; the dark-strip boards (`toggle`, `fallback`) unchanged.

## F-157 · Chat mode's scrolling, measured on a long session (2026-10-07)

- **Why.** Geoff: "scroll performance for a long agent session in chat mode is really bad; very laggy with lots of spinning beach ball cursor." A beach ball is the main thread blocked for about 2 s, so this measures the main thread.
- **Fixture, generated.** `scripts/make-long-chat.py` writes a transcript shaped like Geoff's longest sessions without any of their text (the repo is public). The real ones have about 95 prompts, 3,500 tool calls (70% Bash), thinking before most calls, short text blocks and the odd long one, and 33 to 150 MB of transcript. The default is 16 MB. `--heavy` makes command output as large as the real ones', which gives 82 MB, 95 turns and 3,601 tool calls. The feed shows the last 50 turns (Q-56c): 100 items and 1,945 tool steps.
- **Harness.** `scripts/perf-chat.sh [out] [--heavy]` runs an isolated Duo (its own support and Claude config folders) in `chat-window`. The fixture chat follows the transcript through the real `ChatFeed`. `perf-*` actions (`Debug/ChatPerf.swift`) then:
  - open it;
  - scroll up from the bottom one step a frame, 40 pt (300 frames) and then 200 pt (a flick, 120 frames);
  - append live replies at the bottom (more of the same turn);
  - jump to the middle and append new turns.
  
  A background watchdog pings the main thread every 5 ms, so its waits are the stalls. `sample(1)` runs during each phase. Results are in `<out>/perf.log`.
- **Caveat.** The test window is never frontmost, and is often covered (F-113), so AppKit lays it out but may skip drawing. On Geoff's screen, frames cost more than these numbers.
- **Numbers, heavy fixture, two runs each:**

| Build | Open: longest stall | Slow scroll: frames over 33 ms (of 300) | Flick: longest stall | Live replies at the bottom (1.4 s of them): stalls total / longest | A reply while scrolled up | AppKit views in the feed | Peak memory |
|---|---|---|---|---|---|---|---|
| main today | 2.9–3.5 s | 292–293 (median frame 37 ms) | 122–125 ms (≈115 of 120 frames late) | 2.4–2.8 s / 1.5–2.4 s | yanked to the bottom; 1.0–1.3 s stall | 6,024 | 640–830 MB |
| chat polish's collapse (788ef16) | 2.3–2.9 s | 1 | 75 ms | 0.4–1.2 s / 0.18–0.41 s | yanked; 0.2–1.2 s | 184 | 355 MB |
| collapse + the quick fixes (F-158 to F-160) | 0.5–0.7 s | 1 | 74–93 ms | 0.2–0.45 s / 0.08–0.19 s | stays put; 5–41 ms | 172 | 352 MB |
| the quick fixes without the collapse | 0.6–1.2 s | 0–2 | 12–60 ms | 0.8 s / 0.21 s | stays put, but 2.0 s to tear down views (F-159) | 6,000+ | 500 MB |

- **Four causes, in order of harm:**
  1. **A whole-window Auto Layout pass every frame** (F-158).
  2. **An AppKit text field for every selectable `Text`** (F-159).
  3. **Opening parses the whole transcript on the main thread**, and the log's updates are quadratic (F-160).
  4. **Every new item scrolls to the bottom** and compares the whole feed (F-160).
- **The rows.** A `LazyVStack` row is a whole Claude turn. In a long agent turn that is hundreds of steps, so realizing or re-rendering one row is costly. The flick's remaining 75–93 ms hitches are this. The collapse makes these rows much smaller.

- **Built (DL-137, quick + deeper).** All of F-158 and F-160, and also:
  - the replay runs off the main thread too: `ChatLog` is no longer tied to the main actor, a scratch log is built in the background and `adopt`ed in one change, and `ChatIngest.record` has a nonisolated form;
  - Markdown blocks and inline attributed strings are cached by text (`ChatMemo`);
  - the follow-bottom rule is decided by your scrolling only: a change of offset alone decides, and one that comes with a height change can only say you've left (the lazy stack's re-estimate can clamp the offset to the end).
  
  Heavy fixture, on main with the collapse (e1b5635) and then with this build:

| Phase | main | this build |
|---|---|---|
| Open: longest stall | 2.0–2.9 s | 142–176 ms |
| Slow scroll: late frames | 1 of 300 | 1 of 300 |
| Flick: longest stall | 75 ms | 86–92 ms |
| New replies at the bottom (steady): longest stall | 62–78 ms | 64–71 ms |
| A reply while scrolled up | pulled to the bottom | stays |

- **What's left is the lazy stack's rows** (ENH-23a):
  - right after a jump to the bottom, appending can stall 0.4–0.5 s while SwiftUI re-estimates a giant row;
  - in 1 run of 3, a reply arriving while scrolled far up moved the view up to 13,000 pt, because the stack's estimate of the whole feed collapsed (138k to 333k pt between two moments).
  
  Both come from one row being a whole turn.
- **Proof:**
  - `scripts/check-chat-perf.sh`, the budget: open 600 ms, slow scroll 10 late frames, flick and replies 250 and 600 ms, and the follow decision. It passed 3 of 3.
  - DuoChecks: 685 pass. The off-main replay matches the main-thread one on all 13 boards.
  - `check-chat.sh` and `check-ui.sh`: all 33 captures are pixel-identical to main's.

## F-158 · SwiftUI sized the pane split with Auto Layout, walking every view in every pane (2026-10-07)

- `PaneSplit` (`Shell/PaneSplit.swift`) is an `NSViewRepresentable` with no `sizeThatFits`. So on every layout pass of the window's hosting view, SwiftUI asks it `systemLayoutSizeFittingSize:`. That builds a temporary Auto Layout engine from the constraints of every view under the split, all panes included, and throws it away (`_populateEngineWithConstraintsForViewSubtree`).
- **Cost.** With a long feed realized (6,000 AppKit views, F-159), it took 60% of the main thread while scrolling: 36 ms frames, 293 of 300 late.
- **Fix.** `sizeThatFits` returns the proposal, since the split always fills what it's offered. The same run then has 1 late frame of 300, with a median of 16.7 ms.
- Any representable that hosts SwiftUI content should say its size, or every view under it is walked on each layout pass.

## F-159 · Every selectable `Text` is an AppKit text field (2026-10-07)

- **What `.textSelection(.enabled)` costs.** On macOS it turns each `Text` into a `SelectionTextField` inside an `AppKitPlatformViewHost`. On today's main, two realized turns of the heavy fixture held 6,024 AppKit views: 2,167 text fields, their hosts, and 1,686 `_NSGraphicsView`s. Most were the lines of `Write` diffs, which drew the whole file, two text fields a line.
- **Creating them costs.** Discarding them costs more: `-[NSView _removeFromKeyViewLoop]` is linear in the siblings, so tearing down a large row is quadratic. That was the 2.0 s stall when a reply arrived while scrolled up.
- **The collapse fixes most of this.** It builds outputs and diffs only for opened steps, which cuts the realized feed to 172 views. With it, removing selection from every `Text` too gained little: 155 ms against 135 ms of stalls at the bottom. So selection stays as designed.

## F-160 · Opening a long chat blocked the main thread; new items always scrolled to the bottom (2026-10-07)

- **Open.** `ChatFeed.loadHistory` ran on the main thread, despite its comment. On the 82 MB fixture, a sample of the 1.3 s it took to read, parse and replay:
  - JSON parsing of the whole file: 26%;
  - `ChatLog.toolUse`/`updateStep`: 35%. They scanned every item for the step's id, and copied a turn's segments and steps on every change. That's quadratic in a long turn, and `toolUse` wrote the item back even when nothing changed.
  - `ISO8601DateFormatter` for each record's timestamp: 14%.
  - Drawing the first frame then took another 0.3–0.8 s.
- **Prototyped fixes:**
  - read and parse off the main thread, the tick leaving the transcript alone until then;
  - an index from step id to item;
  - changing turns in place (the item is lifted out first, so its arrays aren't shared);
  - parsing timestamps by hand.
  
  The longest stall went from 2.3–3.5 s to 0.5–0.7 s. What's left is the replay itself, still on the main thread: mostly `ChatToolDescriber.finish` splitting long command output into lines that are never drawn.
- **Memory.** The parsed history keeps every record for Earlier turns: about 350 MB for the 82 MB file. Keeping the lines unparsed until Earlier turns asks for them would save most of that.
- **New items scrolled to the bottom.** `ChatPane` scrolled to the bottom on every change to `chat.log.items`. So:
  - a reply that arrived while you read further up pulled you down;
  - SwiftUI compared the old and new feeds in full, every step's diff and output included, on every hook event.
  
  The prototype keeps you where you are unless you're at the bottom (`onScrollGeometryChange`), and watches the item count instead.
  - Open question: in one run of four, a jump to the middle that changed the content height at the same moment still counted as "at the bottom". The build needs a sturdier rule (scroll to the bottom once on load; otherwise decide from the offset alone), proved by the harness's scrolled-up phase.

- **Finer rows were tried, and didn't pay off (ENH-23a, Geoff: "if we should do the finer-rows approach, do it").** The prototype made each Claude turn a `Claude · 9:42` row plus one lazy row per card section, drawn on pieces of the card. All 33 captures were pixel-identical to main's. It is parked on `proto/chat-finer-rows` (88dd122). Heavy fixture, three runs of the budget check:

| Phase | slice 1 | finer rows |
|---|---|---|
| Flick: longest stall | 86–92 ms | 44–61 ms |
| Replies right after a jump to the bottom: longest stall | 184–470 ms | 279–808 ms |
| A reply while scrolled up: longest stall | 35–224 ms | 1.07–1.31 s |
| …and where the view ended | stays (decided by your scrolling) | at the bottom: the estimate collapsed under the view (624k to 312k pt), 3 of 3 |
| AppKit views realized | 172 | 50 |

  - **Why it lost.** About 1,850 rows are rebuilt on each event (18–20 ms in a debug build). SwiftUI then compares the realized rows' card sections deeply, and invalidates their subgraphs.
  - **The bigger problem is the estimate.** With small rows and very large ones mixed, the lazy stack's estimate of the feed's height swings harder, so the view lands somewhere else after a jump.
  - A SwiftUI lazy stack can't be given row heights. A container that caches measured heights (ENH-23b, NSTableView/NSCollectionView) is the way to remove the jump stalls and the shifting.
- **Release builds** (what Geoff runs; everything above was a debug build). Heavy fixture, two runs each, main with the collapse (e1b5635) and then with slice 1:

| Phase | e1b5635 | slice 1 |
|---|---|---|
| Open: longest stall | 1.06–1.14 s | 133–169 ms |
| Slow scroll: late frames | 1 of 300 | 1 of 300 |
| Flick: longest stall | 80–86 ms | 84–86 ms |
| Replies at the bottom (steady): longest stall | 63–70 ms | 66–72 ms |
| Replies right after a jump to the bottom: longest stall | 544–677 ms | 410–690 ms |
| A reply while scrolled up | pulled to the bottom; 260–281 ms | stays; 0–74 ms |

- **Guard.** The log a chat draws (`ChatSession.log`, `drawn`) asserts that it's only changed on the main thread. A scratch log for a replay isn't held to that. DuoChecks checks which log is which.

- **On Geoff's longest real session** (2026-10-07, C-39): a 155 MB transcript, 95 prompts, with the last 50 turns showing 135 items and 1,943 steps. `PERF_TRANSCRIPT=<copy> scripts/perf-chat.sh` followed a copy in the scratch folder, which was deleted afterwards; nothing of it was committed. Release builds, two runs each:

| Phase | e1b5635 | with DL-137 |
|---|---|---|
| Open: longest stall | 1.50–1.59 s | 95–116 ms (the chat fills in 1.0–1.2 s) |
| Slow scroll: late frames | 2 of 300 | 2 of 300 |
| Flick: longest stall | 54–55 ms | 41–42 ms |
| Replies right after a jump to the bottom: longest stall | 524–749 ms | 707–776 ms |
| A reply while scrolled up | pulled to the bottom; 206–393 ms | stays; 12–49 ms |

  The open freeze and the pull to the bottom are gone. What's left matches the generated session: about 0.5–0.8 s right after a jump to the bottom, from the lazy stack (ENH-23b).

## F-161 · macOS draws a Dock badge only for an app allowed badges in Notification Center (2026-10-07)

`NSApp.dockTile.badgeLabel` was set to the right count, but macOS never drew it. Once an app is known to Notification Center, the Dock shows its `badgeLabel` only if its **Badge application icon** setting is on, and that setting exists only for an app that asked for `.badge`. Duo asked for `[.alert, .sound]` (S3-6), so it never had one.

Read from an isolated test build, which shares Geoff's bundle id (`com.dudgeon.duo`, C-40) and so reads the same settings, read-only through `duo2 settings`: **notifications off (denied), badges not asked yet.** So on this Mac nothing about Duo's attention signals reaches him: no badge and no notifications, however `dockBadge` and `notifyNeedsYou` are set. Geoff runs the ad-hoc-signed `build/Duo.app` here; the work Mac's Developer ID install has its own settings.

`requestAuthorization` prompts only while the status is not determined; afterwards it returns the earlier answer without a prompt and registers any new options, so asking again with `.badge` is quiet (Apple: "Asking permission to use notifications"). DL-138 asks again once per run, at the moment Duo would notify. Whether macOS turns a newly registered Badges switch on for an already-allowed app couldn't be tested without a prompt on Geoff's Mac: the manual check below settles it.

Check by hand: in System Settings › Notifications › Duo, turn on Allow notifications and Badge application icon; with a session waiting and Duo in the background, the Dock icon shows the count `duo2 needs-you` lists.
