# Duo: chat polish — design handoff

Status: approved by Geoff, 2026-10-07 (DL-135, DL-136). Two changes to chat mode (`chat-mode-handoff`, DL-119), from Geoff's notes of 2026-10-07: chat showed more detail than the terminal for commands and tool calls, and the black bar over chat looked strange.

The boards were drawn on the Design canvas https://claude.ai/artifact/SSkofLgbK2jdNCKonuXPT2 with the Duo design system. Geoff chose by buttons; C1 and C2 were corrected after approval to one line a run (F-151). The approved boards are exported here as static HTML (`screens/`, listed in `screens/manifest.json`), with PNGs in `screens/png/` once compared. The canvas also keeps the bar options not chosen (B0, B1, B2, B4).

## Runs (DL-135): `collapsed`, `expanded`, `mixed`, `needs-you`

- **A run is every tool call between two pieces of Claude's text.** It is one line on the dotted thread, in the terminal's own words, and folded by default: `Ran 4 shell commands, read 3 files`. Each verb is semibold in `text`; the rest is `text2`.
- **Edits name their files** after a dot, as links, with the run's `+n −n`: `Edited 2 files, ran 1 shell command · prd-v2.md, flows.md +6 −3`.
- **A click opens the run in place**, 18 in, with no dots: a line a step, cut to one line. A command leads with Claude's own description (semibold), then the command in mono `text2`; with no description, the command in `text`. Reads in a row are one line, as before. A step opens to its output or diff with another click.
- **While a run is going**, the kinds done come first, then the one still going with `…` (`Searched for 1 pattern, read 2 files, searching for 1 pattern…`). The step in progress shows beneath on one line, in mono `text2`.
- **Never folded:** a step waiting on you (its own line with the filled dot and `needs you`; the review card docked below, unchanged), the review cards, Claude's questions, your answers, Claude's text, status lines.

## The candidates (DL-135): `output` … `paste`

Each board draws NOW and PROPOSED; build the PROPOSED half. The NOW half and the section labels are the board's, not the app's.

- `output` (K1): a command's output only on a click, still cut at 3 lines with Show n more lines.
- `edits` (K2): edits fold like the rest. A diff only on a click; over 12 lines it shows 12 and Show n more lines.
- `thinking` (K3): thinking between calls is inside the run, seen when it's opened. Thinking just before Claude's text stays its own line.
- `agents` (K4): a finished agent is one line, `Agent Survey cross-check · finished · 2m 14s · 18 tool uses ›`, opening to its message and Manage in Terminal…. A running agent keeps its own line, with a `text` ring and Manage in Terminal… at the end.
- `todos` (K5): every to-do update in a turn becomes one line, `To-dos · 3 of 5 done`, after the run of the latest update. It opens to the checklist: done filled and struck through, in progress semibold.
- `tools` (K6): MCP and housekeeping tools join runs, counted by server and kind: `used claude-in-chrome 5 times`, `loaded 2 tools`, `sent 1 message`. Opened, an MCP step leads with its server.
- `failed` (K7): the run stays folded; its line ends `· 1 failed` in `diffDelText`. Opened, the failed step shows `failed · exit n` and its error.
- `paste` (K8): your message over 12 lines shows its first 8 and Show all n lines.

## The bar (DL-136): `bar-thin`

While the selected tab is in chat mode, the console tab strip is 28 high on `ground` with a 1 `rule` under it. Tabs are SF Pro 12; the selected one is semibold in `text`, underlined 2 in `text`; the others are `text2`. The toggle is light: white, 1 `controlEdge`, the shown segment on `selected`, 22×16 segments. A terminal tab keeps today's dark strip.

## Behaviour a picture can't show

- Open and closed are reading state, kept per run while the chat is open, like the folds before (no `duo2` verb, DL-71's exemption for folds).
- A step waiting on you leaves its run and rejoins it once answered.
- Outputs and diffs are built only when their step is opened.

## Not drawn (stand-ins and questions)

- Q-87: B3 draws the tabs without their state glyphs. Stand-in: the strip keeps each tab's glyph in light chrome's colours.
- The run line's wording for tools the terminal has no word for (`used <server> n times`, `loaded n skills`) is Duo's.

## Exempt from the comparison

- Names, times and data are illustrative; the NOW halves of the candidate boards.
- The tab strip and the composer's hint line are the existing components (chat-mode-handoff).
- The candidate boards start at the feed: compare them from below the tab strip.
