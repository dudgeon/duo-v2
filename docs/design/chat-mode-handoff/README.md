# Duo: chat mode — design handoff

Status: approved by Geoff, 2026-10-06 (DL-119), not built. Chat mode is a readable view of the real Claude Code TUI in the console pane, under DL-118's rules: an overlay, never a replacement; human review stays the human's; the terminal is one click away, and Duo falls back to it by itself. The feasibility research is `docs/plan/spikes/chat-mode.md` (F-103 to F-106).

**Changed by decision (DL-135, 2026-10-07):** tool steps no longer show one line each, open by default. Runs of tool calls fold to one line; see `chat-polish-handoff`. The threads in `window`, `tools`, `plan` and the permission boards are amended by it.

The boards were drawn on the Design canvas https://claude.ai/artifact/FtWkK77NhsW5DAF8ZQ1KWd with the Duo design system. Geoff chose on the canvas, by comment and in one round of questions. The approved boards are exported here as static HTML, with PNGs in `screens/png/`; `screens/manifest.json` lists them. The canvas also keeps the directions not chosen: Feel A (dark), B, B2 (Paper), B3 (Rounded), C (all mono), toggles 2 and 3, and separations 1 to 4.

## What the boards settle

**The look** (`window`):
- **B4, "Trail", on a grey ground (Sep 1b).** The transcript sits on `ground`, so chat mode stands apart from the white session list and editor on either side. The dark tab strip stays as built.
- **Your messages** are on the right, in a `chatYou` blue bubble, left-justified, at most 440 wide. The bottom-right corner is sharp (3) and the others 14, so it reads as a speech bubble. Your Markdown is rendered (bold, code, lists). Above it, `You · 9:41`.
- **Claude's replies** are one white card per turn, `Claude · 9:42` above it. The bottom-left corner is sharp, mirroring yours. The card spans the column with 36 kept free on the right; Geoff asked for half the first board's skew, since replies run longer than prompts.
- **Tool steps** sit on a dotted thread at the top of Claude's card. Each step is a bold verb and its object (files are links), with a small open dot.
- **Type:** SF Pro 14/22 in bubbles and cards; headings 16/24 semibold; mono 12/19 for code, paths and commands; meta lines 12/16 in `text2`. Lists are plain bullets. Geoff rejected pills for bullets (B4's first draft).

**The toggle** (`toggle`): a compact pill at the right end of the console tab strip, with two icon segments, `>_` for Terminal and a chat bubble for Chat. Each has a tooltip and an accessible label. It belongs to the selected Claude tab; a shell tab doesn't show it.

**Assistant text** (`text`):
- Markdown streams in line by line, with a caret, and `Writing · 14s · Esc to interrupt` below the card.
- Thinking shows folded (`› Thought for 6s`), once its block is complete.
- File paths are links: a click opens the file in Duo's editor, at the line when one is given; the tooltip names the file and line.
- Web links open as Duo does today. Code blocks have a copy icon (labelled Copy). Tables are ruled lightly.

**Tool cards** (`tools`):
- Read, Search and Fetch are one line each, folded (›).
- Edit opens to a diff drawn from the request's old and new text: line numbers, `diffDel` and `diffAdd` fills, and `+n −n` counts.
- Bash opens to its command and output, with long output cut at a few lines and `Show n more lines`.
- A failed tool says `failed · exit n` and shows its error in `diffDelText`.
- A background agent shows its final message, its time and tool count, and **Manage in Terminal…** (the agents manager falls back).

**Human review** (`permission-edit`, `permission-bash`, `plan`, `question-*`):
- While Claude waits on you, the review card is **docked at the bottom, in the composer's place**, as Claude Code's dialog replaces its prompt. It has a 1.5 `needsYou` border and `NEEDS YOU · <kind>` in words. The tab's glyph is the needs-you dot.
- **Every option label is Claude Code's own, read from its screen, never a fixed list.** The boards show the real wording from 2.1.291, e.g. `Yes, and switch to accept edits (auto-approve file edits and common file commands) for this session (shift+tab)` and `Yes, and always allow access to <dir> from this project`.
- Each option shows its key (1, 2, 3). **Nothing is pre-selected.** A click or a number key sends that option's key to the TUI.
- **Cancel (esc)** sends Esc. **Amend in Terminal…** (Tab to amend) and **Approve with Feedback in Terminal…** (shift+tab on plan option 3) are the two that hand over to the terminal.
- The step waiting on you is marked `needs you` in Claude's card. An answer shows afterwards as a small reply of yours: `You chose 1 · Yes for the edit to prd-v2.md`.
- **Plan approval:** the whole plan as Markdown (the TUI clips it), in a box that scrolls. **Open plan in Duo** opens the plan file in the editor. Option 3, **Tell Claude what to change**, is an inline field with **Send ⏎**.
- **AskUserQuestion**, all in chat (F-106):
  - Question tabs; ☒ marks an answered one, and a click or **‹ Back** returns to change an answer.
  - Checkboxes (multi-select) or radios (single), each with its description.
  - **Type something** for your own answer: **Add** on multi-select, **Answer ⏎** on single.
  - **Next ⏎**, then the review page: **Review your answers**, **Submit answers**, **Cancel**.
  - Previews show **every option side by side**, where the TUI shows one at a time; a **Notes** field goes with **Choose with Notes ⏎**.
  - **Chat about this** closes the question and moves focus to the composer (`question-chat-decline`). **Decline (esc)** leaves `You declined Claude's questions`.
  - Long questions and labels wrap.

**The composer** (`composer`):
- It shows **Claude's own prompt** (through Claude Code's Ctrl+G editor, F-104), so text typed in the terminal carries over and nothing is lost either way.
- Return sends; ⇧Return adds a line. Below it are the mode chip (`⏸ manual mode`, `⏵⏵ accept edits on`; a click cycles it, as shift+tab does) and the hints.
- Files dropped in go in as their full paths (DL-117) and show by name.
- `/` opens the command list with Claude Code's own descriptions. A command with its own screen (`/model`, `/config` …) is marked with the terminal icon and opens in the terminal.
- While Claude works, a message you send waits as `Queued`, faded, and **Stop (esc)** sits beside the field.

**Status lines** (`status`):
- Compaction is a divider: `Conversation compacted · earlier turns are summarised for Claude`.
- A background agent finishing gets a quiet line.
- An interrupt shows `Interrupted · What should Claude do instead?` with the composer ready.
- A retry shows Claude Code's own status, e.g. `529 Overloaded · Retrying in 2s · attempt 4/10`.

**Falling back** (`fallback`):
- **Automatic:** when chat mode can't name the screen (sign-in, trust, `/model`, `/config`, anything new), or the screen and the request disagree, the pill flips to Terminal. A light bar over the terminal says `Chat mode can't show this screen, so here's the terminal. Chat comes back when it closes.`, with **Back to Chat**.
- **Chosen:** Amend in Terminal and the like show the same bar with what to do.
- Chat returns by itself when it left by itself. When the user chose the terminal, it stays.

## Behaviour a picture can't show

- **Keys, never decisions** (DL-118): every answer is the key Claude Code expects. Before sending, Duo re-reads the screen, and sends only if the same dialog is still up (F-104, F-106). If it isn't, nothing is sent and the terminal shows. Hooks never decide anything.
- **Number keys** answer a review card, as in the TUI. Return does nothing until an option has been chosen or moved to with the arrows. Esc cancels or declines.
- **⌘[ / ⌘]** go to your previous and next message while the chat has focus (DL-119; DL-34 entry). Stepping through every turn wasn't chosen.
- **The mode for a new session** is the one you used last (Geoff). Each session remembers its own mode after that.
- **Switching** never restarts anything: chat is a second view of the same terminal. The proposal for what stays on screen when switching (`Switch` on the canvas) is Q-53.
- Every new control needs a `duo2` verb (DL-71). Names are proposed in Q-53.

## Not drawn (stand-ins and questions)

- Q-53: switching mid-conversation, and the `duo2` verbs.
- Q-54: ⌘[ ⌘] and a browser tab's Back and Forward.
- Q-55: how findable your latest message is in `chatYou` blue.
- Q-56: dark appearance; Markdown heading levels other than one; images pasted into the composer (they fall back for now); a session with long history loading; panes narrower than 560.

## Exempt from the comparison

- Names, times and data are illustrative.
- The /model screen in `fallback` is shortened. The terminal there is Claude Code's own.
- The tab strip is the existing component.
- If chat renders in a web view (the build's choice; the research's open question), check it in a browser at the pane's width (F-25).
