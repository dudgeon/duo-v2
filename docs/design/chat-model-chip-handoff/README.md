# Chat model chip: the handoff

Geoff approved this on 2026-10-10 (DL-168), in the MODEL CHIP session: "Accept all three recs". The canvas is https://claude.ai/artifact/RTgimxmSpPHxuUw4gMu7wJ, and the research behind it is `docs/research/chat-model-chip.md`.

The two boards in `screens/` are the target, rendered at 2× in `screens/png/`. They are parts of the console pane in chat, 680 wide, in the look of `chat-mode-handoff/` (DL-119) and `chat-slash-handoff/` (DL-143).
- **Illustrative content:** the names and words on the boards. Every model name, effort word, option and result line is read from Claude Code at run time.
- **Not chosen:** B (a menu from the chip) and C (chips in the tab strip). They stay on the canvas only.

There are no new tokens. Everything uses `ground`, `pane`, `selected`, `rule`, `controlEdge`, `text`, `text2` and `borderDash`.

## The chips (`screens/chip.html`)

- **Where.** At the right end of chat's hint row, in place of today's model label. The effort chip comes first, then the model chip, with gap 8 (the hint row's spacing).
- **Look.** Each is the mode chip mirrored, as built in `ChatComposerView`: `chatMeta` in `text2`, padding 0 8, a capsule filled with `pane`, and a hairline border in `rule`.
- **Pointer over a chip.** The fill turns `selected`, the border `controlEdge` and the text `text`. The tooltip reads "Change model (/model)" or "Change effort (/effort)".
- **The model chip's words.** It shows the name Claude Code uses, not just the family:
  - names like `Opus 5.5`, `Sonnet 5` and `Haiku 4.5`;
  - an id is made into one (`claude-sonnet-5-5` → `Sonnet 5.5`, `claude-haiku-4-5-20251001` → `Haiku 4.5`);
  - an id that doesn't fit that pattern shows as given;
  - the newest of these sources wins:
    1. a `/model` result line in the transcript: "Set model to `X` …" or "Kept model as `X`", with backticks and ANSI bold removed (2.1.219 wraps the name in `ESC[1m … ESC[22m`);
    2. the model of each assistant reply (`message.model`);
    3. on a new session, the SessionStart hook's `model`. On a resumed one, the replayed transcript wins: a session-only switch persists across a reopen.
- **Unknown.** Before any of these sources, the chip reads `Model`.
- **The effort chip's words.** It shows the TUI's own glyph and word (`◐ medium`, `● high`), read from the screen:
  - 2.1.296 and later draw `◐ medium · /effort` in the input box's top rule;
  - 2.1.219 draws it at the right end of the footer line;
  - with neither on screen, there is no effort chip.
- **A click** sends `/model` or `/effort` into Claude's prompt, through the send path's checks, and DL-143's card docks in the composer's place. Rules for the click:
  - It acts only when the screen reads idle and Claude's prompt is empty: text there would turn `/model` into a message to Claude. Otherwise it sends nothing and says why, as other refused sends do.
  - It adds no bubble: the chip asked, not you. The result arrives as DL-143's quiet line, right-aligned with the ⎿ elbow.
  - The composer's draft is kept and comes back when the card sinks.
  - The model chip changes on the result line, before any reply.
- **While Claude works**, both chips wait, on every version. The border is dashed (`borderDash`, `rule`) and there's no fill. The tooltip reads "Change the model when Claude finishes" or "Change effort when Claude finishes". The reason is that 2.1.219 queues the command until the turn ends.

## Switch model? as a card (`screens/confirm.html`)

On a session that already has a conversation, This Session Only and Set as Default bring up Claude Code's own question (both versions; real screens in `docs/research/chat-model-chip-screens/`):

```
Switch model?
Your next response will be slower and use more tokens

This conversation is cached for the current model. Switching to Sonnet 5.5 means the full
history gets re-read on your next message.

❯ 1. Yes, switch to Sonnet 5.5
  2. No, go back
```

2.1.219 asks "Change effort level?" the same way. Chat used to fall back to the terminal here.

- **The frame.** It's the picker card's: `pane`, a 1.5 `text` border, radius 14, padding 14 16.
- **The head.** `MODEL · SWITCH MODEL?` (or `EFFORT · CHANGE EFFORT LEVEL?`) in `sectionLabel`. On the right: "Claude Code's own question, answered with its keys".
- **The body.**
  - The first line is in `bodyEmphasis`; the rest are in `text2`, joined as the screen wraps them.
  - The options are numbered rows, as the picker draws them.
  - **Nothing is highlighted**, because the TUI's cursor is a default, not your choice (DL-118).
- **Answering.**
  - Number keys and clicks answer, after re-reading the screen.
  - Cancel esc is the only button.
  - "No, go back" returns to the `/model` card.
- **A screen it can't read.** Anything chat doesn't read whole falls back to the terminal, as before.

## 2.1.219's /effort

- **What it draws.** The footer reads `←/→ to adjust · Enter to confirm · Esc to cancel`, so there's no session-only key. The slider has an `ultracode` stop after `max`, labelled `xhigh + workflows`.
- **How the card reads it.** It reads this screen too: the levels are low to max, without ultracode, and This Session Only is hidden.

## duo2 (DL-71)

- `duo2 session chat model [id]` and `duo2 session chat effort [id]` do what a click does, with the same checks.
- `duo2 session chat answer` answers the Switch model? card by its option number (DL-143's verb).
