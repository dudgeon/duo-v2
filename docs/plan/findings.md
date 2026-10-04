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
