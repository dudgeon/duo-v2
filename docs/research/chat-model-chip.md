# A clickable model selector in chat

Geoff, 2026-10-10: "Please explore if we can make a clickable model selector in chat mode." He also said he sees the model label under the composer during sessions and assumed he could click it.

This is research, not a decision. The canvas is https://claude.ai/artifact/RTgimxmSpPHxuUw4gMu7wJ, with options A, B and C and a card all three need. Every mark on it is a proposal [P].

## Answer

**It's feasible, on current Claude Code and on the work Mac's pinned 2.1.219.**
- **The model is known without spending a turn:**
  - at launch, from the SessionStart hook;
  - at once after a switch, from Claude Code's own result line in the transcript;
  - confirmed by every reply.
- **The effort level is on the TUI's screen**, on both versions.
- **A click can drive the switch safely** by sending `/model`, which opens the `/model` card DL-143 already built.
- **One gap first:** on any session that already has a conversation, Claude Code asks "Switch model?" after you pick. Chat can't read that question today, so it falls back to the terminal. That's true of the `/model` card as built now, before any chip.

**Recommendation: option A.** The label you already see (`Opus`, at the right end of the hint row) becomes a chip like the mode chip on the left, with an effort chip beside it. A click opens the `/model` (or `/effort`) card. The chip changes as soon as Claude Code prints its result.

## How it was checked

- **Setup.**
  - Headless runs of the real TUI (`Spikes/chat-mode/drive.mjs`) against the scripted mock API (`mock.mjs`).
  - Scratch `CLAUDE_CONFIG_DIR`s, no login and no tokens.
  - Both versions: the installed **2.1.296** and **2.1.219** (`/tmp/ts219`, the work Mac's pin).
- **What was checked.**
  - The mock logs each request's `model` (plus `output_config` and `thinking` in a probe copy). That is the ground truth for which model Claude Code actually uses.
  - Each run kept the screens, the transcript, `settings.json` before and after, and hook payloads from a hook on all 28 event names.
- **Where the evidence is.** The screens a build needs are in `chat-model-chip-screens/`: Switch model?, `/effort` and the idle footer, on each version, with scratch paths shortened to `~/scratch/ws`. Everything else stayed in this session's scratchpad.
- **The mock's limits.** It can't show capability gating, so "Effort not supported for Haiku" (seen in real runs, F-173) didn't appear. The picker's rows also differ from a subscription login's: prices are shown, and the aliases differ.

## 1. Can Duo know the current model?

| Source | 2.1.296 | 2.1.219 | When |
|---|---|---|---|
| **SessionStart hook** `model` | ✓ id (`claude-sonnet-5-5`) | ✓ id | At launch, before any prompt. Duo's chat feed already reads SessionStart payloads (`ChatFeed.swift`). |
| **Transcript, `/model` result** | `<local-command-stdout>Set model to `Sonnet 5.5` for this session only</local-command-stdout>`; Esc gives a `system`/`local_command` record "Kept model as `Haiku 5.5`" | Same records; the name is wrapped in ANSI bold (`\u001b[1mSonnet 5\u001b[22m`), and a custom id shows raw | At once, before any reply |
| **Transcript, assistant `message.model`** | ✓ | ✓ | Each reply (what chat reads today) |
| **Transcript, `model` attachment** on each user turn (`identity.marketingName: "Haiku 5.5"`) | ✓ | — | Each prompt |
| **Welcome banner** ("Haiku 5.5 · API Usage Billing") | ✓ | ✓ (a raw id for custom models) | At start; scrolls away |
| **Idle footer** | never | never | — |
| **`/status`** | `Model: claude-sonnet-5-5` | same | A screen of its own; costs a round trip |
| **settings.json `model`** | written only by Set as Default, or `/model <x>` (an alias, `"sonnet"`) | same | Says nothing about this session |

- **What's true after "This Session Only":** the transcript record. The next request uses the new model on both versions, and no settings are written.
- **After a reopen** (`--resume`, no flag): the request uses the session's last model (Sonnet after a session-only switch), on both versions. A `--model` flag on resume wins over it. Duo never passes `--model` (DL-153), so the transcript's last model is the truth.
- **Not verified:** whether SessionStart's `model` on resume reports that last model. A build should prefer the replayed transcript on resume and take SessionStart's value only for a new session.
- **Names differ by version.** On 2.1.219 "Sonnet" is Sonnet 5 (`claude-sonnet-5`) and the default is Opus 5 (1M context). On 2.1.296 they are Sonnet 5.5 and Opus 5.5. The chip should show the name Claude Code prints (`Opus 5.5`, `Sonnet 5`), or for an id, a name made from it. Not just the family, as now (`ChatIngest.swift`: `Opus`).
- **Effort:**
  - **On screen, both versions.** 2.1.296 draws `◐ medium · /effort` in the input box's top rule; 2.1.219 draws `● high · /effort` at the right end of the footer line.
  - **In hooks.** PreToolUse, PostToolUse and Stop payloads carry `effort: {"level": …}` on both versions.
  - **In the request.** It travels as `output_config.effort`.
  - **What `/status` shows.** No effort line.

So the chip's model comes from the latest of: SessionStart, a `/model` result record, an assistant reply. Its effort comes from the screen, with the hooks as a check. None of this spends a turn or sends a key.

## 2. Can a click drive the switch safely?

**Send `/model` and reuse the DL-143 card** (A and C). Through the existing send path, that means: re-read the screen, check Claude's prompt is empty, paste or hand over, check the echo, then Return.
- **Idle, empty prompt:** the picker opens and the card docks. Same on both versions; the picker's title and footer are the same, so `ChatSignatures` reads it.
- **Text in Claude's prompt:** `hello` followed by `/model` just appends, and Return would send `hello /model` to Claude as a message. So the chip must refuse unless the screen shows Claude's prompt empty. Duo's own composer draft is separate and stays; the card takes the composer's place and gives it back.
- **Mid-turn:**
  - **2.1.296** opens the picker (and `/model x`'s dialog) while the reply streams.
  - **2.1.219 queues the command** ("Press up to edit queued messages"), so the picker opens only after the turn.
  - Recommendation: the chip waits while Claude works, on every version ("Change the model when Claude finishes").
- **"Switch model?" with history.** On a session that has a conversation, This Session Only or Set as Default brings up:

  ```
  Switch model?
  Your next response will be slower and use more tokens

  This conversation is cached for the current model. Switching to Sonnet 5.5 means the full
  history gets re-read on your next message.

  ❯ 1. Yes, switch to Sonnet 5.5
    2. No, go back
  ```

  - **On both versions.** On 2.1.219, `/model sonnet` raises the same dialog.
  - **What happens in Duo now.** `ChatScreen` has no signature for it (it isn't a permission question; reading the code, nothing matches `Switch model?`), so chat falls back to the terminal mid-flow. That's the case for the DL-143 card today too.
  - **The fix.** The canvas board "Switch model? as a card" draws it as a review card in the picker's frame, keeps Claude Code's words and pre-selects nothing (DL-118). 2.1.219's `/effort low` has the same kind of question ("Change effort level?").
- **A Duo menu that picks directly (B).** There's no list without opening `/model`'s screen, so B still opens it behind a popover.
  - **Typing `/model <name>` isn't a shortcut.** It always saves the default for new sessions, and its aliases mean different models on different versions.
  - **So B is the same key path as A**, with a second surface for one screen, plus Esc handling when you click away.
- **The colour-only highlight (C-77)** affects only the `/` menu. The chip sends the whole command, so it's unaffected.

## 3. Effort

`/effort` exists on both versions, but the screens differ:
- **2.1.296:** `←/→ to adjust · Enter to confirm · s for this session only · Esc to cancel`, plus an `Ultracode off · Tab to toggle` control. This version's settings write is per model (`modelSettings.<id>.effortLevel`).
- **2.1.219:** `←/→ to adjust · Enter to confirm · Esc to cancel`, so **no session-only** choice. The slider adds `ultracode / xhigh + workflows` after max. Its settings write is top-level `effortLevel`.

DL-143's effort card reads only the 2.1.296 footer. **On 2.1.219 `/effort` falls back to the terminal today.** An effort chip is cheap: it reads the footer, and its click sends `/effort` the same way. On 2.1.219 it either needs a second footer pattern (with no This Session Only button, and an `ultracode` stop the card must not offer as a level), or it opens the terminal there.

## 4. Options (canvas)

| | What | For | Against |
|---|---|---|---|
| **A (recommended)** | The label becomes a chip like the mode chip, mirrored on the right, with `◐ medium` beside it; a click opens the DL-143 card | Where Geoff already looks and clicks; reuses the card, keys and checks as built; smallest change | Chat only (the terminal has the TUI's own `/model`) |
| B | The chip opens a menu (the `/` menu's look) of the rows read from `/model`'s screen | Lighter, anchored to the click | A second surface over the same hidden screen; the screen's description and footnotes don't fit; Esc on click-away; more states |
| C | Chips in the console tab strip by the Terminal/Chat pill, in both modes | Model visible on terminal tabs too | Crowds the strip at 480; Duo chrome over a terminal reporting TUI state; moves the label from where it is |

All three need the "Switch model?" card.

## 5. Cost, risk and `duo2`

- **A, about one Sonnet build session.**
  - The chip view replaces the label in `ChatComposerView`.
  - The model comes from SessionStart, `/model` result records (with backticks and ANSI stripped) and replies. Effort comes from the input rule or footer, by version.
  - A click sends `/model` or `/effort` through `send` with an empty-prompt check, waits while busy, and leaves no bubble.
  - Plus the "Switch model?" signature and card, and 2.1.219's effort footer.
  - **Risks:** a version that renames the result line (the chip then updates on the next reply, as today), or the confirmation's wording changing (it falls back to the terminal). Both are covered by the per-version signature table and chat-live.
- **B, about two build sessions.** A's work, plus the popover, keeping the picker open behind it, Esc on dismiss, and keyboard focus.
- **C, about two build sessions.** A's work, plus a terminal-mode path (typing into a terminal Duo doesn't chat-read) and the strip's narrow layout.
- **`duo2` (DL-71).** `duo2 session chat model [id]` and `duo2 session chat effort [id]` open the card, as a click does, with the same checks. Answering stays `duo2 session chat answer` (DL-143), which gains `yes`/`back` for the confirmation, or plain option numbers. `duo2 session show` could add `model` and `effort` lines (cheap, from the same state).
- **Tests.** Add the "Switch model?" and 2.1.219 effort screens to `ChatChecks`, and a chip case to chat-live at the three sizes on 2.1.296 and 2.1.219.

## Decisions for Geoff

1. **Which option:** A (recommended), B or C.
2. **An effort chip too:** yes (recommended), or model only.
3. **While Claude works:** the chip waits (recommended, the same on every version), or it opens at once where the CLI allows it (2.1.296).
