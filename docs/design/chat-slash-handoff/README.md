# Chat slash commands: the handoff

Approved by Geoff, 2026-10-07 (DL-143), by buttons on the canvas https://claude.ai/artifact/EGcF7Qx5ga6EXwkKZVh44a; no canvas comments. It answers Q-105 and Q-106, raised by F-173 (every slash command run through chat on Claude Code 2.1.292).

The six boards in `screens/` are the target (`screens/png/` at 2×). They are boards of the console pane, 680 wide, in the chat look of `chat-mode-handoff/` (DL-119) and `chat-polish-handoff/` (DL-135, DL-136). Names, times and numbers are illustrative. Every word from Claude Code (results, option labels, descriptions, categories) is read from its transcript or screen at run time, never from these files. The canvas also has options that weren't chosen: B (the terminal's text verbatim), C (first line and See in Terminal), G (the terminal docked in chat) and M2 (two-line menu rows). They aren't exported.

No new tokens: everything uses `ground`, `pane`, `selected`, `rule`, `controlEdge`, `text`, `text2`, `chatYou`, `toolOutputFill` and the console colours.

## Q-105: what a command prints (A) [G]

`screens/output.html`, `screens/context.html`.

- **The mark.** Every command result is led by Claude Code's own `⎿`, drawn as a 10×10 elbow (stroke 1.4, round caps, `text2`). It replaces F-174's ✓ stand-in, which reads wrong on "Kept model as Haiku 4.5" or "Resume cancelled". Results sit right-aligned under your bubble: they answer you, not Claude.
- **One line** (`<local-command-stdout>` with one line, or a `system`/`local_command` record): a quiet line, 12/16 `text2`, gap 8 after the elbow. Examples: `/rename`, `/plan`, `/model` after its card or screen, `/resume` cancelled, `/mcp`, `/diff`, `/reload-*`, `/color`, `/focus`.
- **Several lines** (`/output-style`, `/list-agents`, `/agents`, `/context all`, `/debug`): an output block 440 wide (at most `chatBubbleMax`). It has the elbow, then `toolOutputFill`, a 1 `rule` border, radius 6, padding 8 12, `mono` 12/19 in `text`, verbatim with its spacing kept. Up to 8 lines show whole. Longer shows 6 and Show n more lines, as tool output does (DL-135).
- **`/context`**: a `pane` box with the same border and radius, padding 10 12 12, 440 wide.
  - **Top line:** `Context usage` (13/20 semibold), then the model's name (`text2`). Right-aligned: `84k / 200k tokens · 42%` (tabular figures). The model's full id is the name's tooltip.
  - **The bar:** 8 high, radius 4, on `selected`. The used categories fill it in the order the screen lists them, in greys stepped by lightness: the first `text`, the second `text2`, the third `controlEdge`. A fourth or later category takes `controlEdge` too, and its legend entry names it. A category under 1% is still 2 wide. Never the accent.
  - **The legend:** 12/18 `text2`, a 9×9 radius-2 swatch with gap 6, then `Name · 1.4k`. Two columns, or one at the narrowest console (480). Free space has a `selected` swatch with a `rule` edge.
  - **Under the legend:** the skills line from the screen (`13 skills · 1.5k tokens`). `/context all to expand` isn't repeated.
  - **Where the numbers come from:** the grid isn't in the transcript, so chat reads the TUI's lines as the command prints. If they don't parse, the block shows the lines verbatim as an output block.
  - **Reopened later** (relaunch, or replay after the tab closed): Claude Code didn't keep the grid, so the result is a quiet line: `Context usage was shown here at 11:32. Run /context again to see it now.` While the tab stays open, the box stays.

## Q-106: commands with a screen of their own (E, with D's bar) [G]

`screens/model-card.html`, `screens/effort-card.html`, `screens/fallback-named.html`.

- **`/model` and `/effort` get a picker card in chat**, docked in the composer's place like a review card (DL-119 §3), rising with `motionCardIn` and sinking with `motionCardOut`.
  - The frame is `pane`, a 1.5 `text` border (not `needsYou`: you asked for this, and Claude isn't waiting on you), radius 14, padding 14 16. The head is `MODEL · /MODEL` in `sectionLabel`; for /model only, the right side adds "Claude Code's own picker, answered with its keys" in `control` `text2`.
  - **/model:** the screen's description, then one row per option, with its number key (18×18, as the review card's), the name semibold and the description in `text2`. The row under the TUI's cursor (❯) is highlighted (`selected`, `text` border). It starts on the model in use, which keeps Claude Code's ✔. The screen's footnote follows (`○ Effort not supported for Haiku`). The buttons are Set as Default ⏎, This Session Only s and Cancel esc.
  - **/effort:** Faster … Smarter, then five segments in a 1 `controlEdge` frame, radius 6: low, medium, high, xhigh, max. The TUI's ▲ marks one (`selected`, semibold). The buttons are Confirm ⏎, This Session Only s and Cancel esc, with `←/→ to adjust` on the right.
  - **Keys (DL-118):** a number, a click or ↑↓ moves the TUI's own cursor (for /effort, ← and → until the TUI's marker is there, re-reading after each key). Nothing is chosen until ⏎, s, Esc or a button. Each key goes only after re-reading the screen, and the same picker must still be up, or the card goes and the terminal shows with its bar.
  - **After:** the card sinks, and the result arrives as A's quiet line (`Kept model as Haiku 4.5`). The composer's model label follows the TUI, as now.
  - **When:** only for the /model and /effort screens chat recognises on a verified CLI version (`ChatSignatures`). Anything else falls back.
  - **`duo2`:** `duo2 session chat answer [id] <n|low|medium|high|xhigh|max|cancel> [--session-only]`. It extends the existing verb (DL-71), and with `--session-only` it presses s instead of Return.
- **Every other screen** (`/config`, `/permissions`, `/resume`, `/help`, `/usage`, `/status`, `/skills`, `/btw`, `/fast`, `/sandbox`, `/hooks`, `/memory`, `/plugin`, `/rewind`, …) goes to the terminal with DL-119 §6's bar, which now names the command and the way out:
  - A screen that takes a choice: `/permissions opens in Claude Code's own screen. Esc closes it and brings chat back.`
  - A screen that only shows (`/usage`, `/status`, `/help`, `/skills`, `/release-notes`): `/usage shows in Claude Code's own screen. Esc closes it and brings chat back.`
  - `/config` and `/resume`: `… Esc clears the search, then closes it.`
  - The command is `mono` 12 in the bar's 13/20 text. Back to Chat is unchanged.
  - The generic sentence stays for screens chat didn't start (sign-in, folder trust, an unrecognised dialog).
  - While a screen you opened from chat is up, the tab and session row show no needs-you dot: you're on it.

## Q-106: the `/` menu (M1) [G]

`screens/menu.html`.

- **Rows:** the TUI's own, 3 to 5 as it shows them. Under the last row is `↑↓ for more · tab completes` in `control` `text2`, padding 3 10 2.
- **The name column** is as wide as the longest name among the rows shown: at least 122 (the approved board), at most 280. Descriptions take the rest and cut their tail.
- **A plugin's prefix** (`/design:`, `/product-management:`) is `text2`, and the skill's name is `text`. Over 280, the prefix is cut in its middle (`/cowork-plugin-man…:`) and the skill's name stays whole. The full name is the row's tooltip, and what goes into the prompt is always the full name.
- **The terminal mark** goes from `/model` and `/effort`, which now open as cards. Every other screen command keeps "Opens in the terminal" and the mark (`ChatSignatures.terminalCommands`).

## Not in this round

- ENH-30: more chat cards (`/fast`, `/permissions`) and read-only panels (`/usage`, `/status`, `/help`) drawn in chat.
- Home's pane, if it gets chat (design/home-evolution), follows the same rules.
