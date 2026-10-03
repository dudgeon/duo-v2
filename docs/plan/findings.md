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
