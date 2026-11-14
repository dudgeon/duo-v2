# /btw in chat: why it falls back to the terminal, and what to do instead

Task: `tasks/btw-terminal-fallback.md` (Geoff, 2026-11-13: "/btw mode triggers fallback to terminal; do some experimentation to understand the problem, then propose solutions, incl design treatments and changes to functionality and handling"). Research and design only; nothing is built into the app beyond a failing check. Records: F-688 (what /btw does), F-689 (why chat falls back, and two faults with it), F-690 (the method and the check), Q-550 to Q-554 (the decisions), C-185 (the risk), ENH-353 (left for later).

- **Canvas:** https://claude.ai/artifact/L2NaLSyuma4dDhExA9SH4G (sources in `docs/design/btw-in-chat-study/project/`), boards 0 to 4.
- **Failing check:** `DUO_CHECKS=btw swift run DuoChecks` (`Sources/DuoChecks/BtwChecks.swift`): 8 pass, 11 fail, as they should until the fix.
- **Screens:** `Spikes/chat-mode/screens/btw-2.1.284/` and `btw-2.1.323/`.

**In one paragraph.** `/btw <question>` is Claude Code's side question: it runs at once, even while Claude works (it never queues), asks the model with the conversation as context but no tools, and draws a panel **in place of the input box and footer** until Esc. It writes nothing to the transcript and fires no UserPromptSubmit; the answer reaches Duo only on screen and in one `SubagentStop` hook with an empty `agent_type`. Chat's screen reader finds no input box under the panel, calls the screen unknown, and after half a second falls back with the named bar, because `/btw` has been on chat's "opens in the terminal" list since F-173. On the way it also leaves a Queued bubble that never clears, and the side answer can finish a running Agent card. **Recommended:** read the panel as its own screen kind and show it as a **side card docked in the composer's place** (where Claude Code puts it, so chat stays honest), keep a **quiet line** in the feed that reopens it for this run, let **typing close the card** and start your message, add **Fork…** once a run confirms what Claude Code's `f` does, and keep `/btw` as the way to ask, with its menu row saying what it does.

## 1. What /btw does, on 2.1.284 and 2.1.323 (F-688)

Checked 2026-11-13 on **2.1.284** (npm-installed into a scratch folder; the work Mac's pin) and **2.1.323** (newest here), each with a scratch `CLAUDE_CONFIG_DIR` and `HOME`, a dummy key, `ANTHROPIC_BASE_URL` on a copy of the chat spike's mock (`Spikes/chat-mode/mock.mjs`, plus a 30-line slow reply and a side-question reply), `--model claude-haiku-5-5`, driven headless with `Spikes/chat-mode/drive.mjs` at 100×34 with a hook logger on every event. No login, no tokens, nothing on screen. Three runs per version: /btw during a turn (fast and slow answers), /btw at the prompt, /btw with an Agent step running, and bare /btw.

**The command.** In both binaries it is `{type: "local-jsx", name: "btw", description: "Ask a quick side question without interrupting the main conversation", immediate: true, argumentHint: "[question]"}`. `immediate` is why it runs during a turn instead of queueing. The query is sent with a system reminder: "This is a side question from the user. You must answer this question directly in a single response … if answering would need reading files, running commands, or searching, say that can't be checked from a side question and suggest asking in the main conversation." Claude Code's own tip line advertises it: "Use /btw to ask a quick side question without interrupting Claude's current work". 2.1.323 adds `keepsScrollPosition`; otherwise the two behave the same in every run.

**The screen.** The panel replaces the input box and the footer (mode, `esc to interrupt`); its top is the effort rule drawn in `▔` (`▔▔▔ ◐ medium · /effort ▔`), never the `─` rule. Claude's turn keeps streaming above it.

```
▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔ ◐ medium · /effort ▔
    /btw what is two plus two
      · Answering…                                      (2.1.323, slow answer)
    Esc to close
```
```
    /btw what is two plus two
      BTW-ANSWER: the mock's side answer to "what is two plus two". It has bold and a second
      sentence.
    ↑/↓ to scroll · c to copy · f to fork · Esc to close
```
At the prompt it also lists earlier side questions: `⇧←/→ to browse · c to copy · f to fork · x to clear history · Esc to close`. Markdown's marks are dropped (`**bold**` shows as `bold`). After Esc the input box and footer come back as they were (busy, if Claude is still working). Bare `/btw` prints `⎿ Usage: /btw <your question>` (2.1.284). If the query fails or comes back empty, the answer reads "(No answer available for this side question. Try again, or ask in the main conversation.)" (from the binary; not provoked here).

**The transcript.** Nothing, on either version: not the question, not the answer, no system record. Prompt history (`history.jsonl`) keeps the typed `/btw …` line.

**Hooks.** No UserPromptSubmit and no SubagentStart. When the answer lands, one `SubagentStop`:
```json
{"hook_event_name": "SubagentStop", "agent_id": "a120d35719bfb7456", "agent_type": "",
 "last_assistant_message": "<the answer, as Markdown>", "agent_transcript_path": ".../subagents/agent-a120….jsonl",
 "prompt_id": "<the current turn's>", "stop_hook_active": false, "effort": {"level": "medium"}}
```
The `agent_transcript_path` is never written. The question isn't in the hook; it is on screen.

**Fork (`f`), not run.** The code has two paths: `spawnForkFromDirective(…, {forkOrigin: "btw"})`, which forks a background agent and prints "forked ‹name›", and otherwise `branchAndResume(…, {customTitle: "btw: ‹question›", extraMessages})`, which branches this session with the side exchange added. Which one runs depends on a flag not identified here. Q-553 asks for one mock run per version before Fork is built.

## 2. Why chat falls back (F-689)

1. **The reader returns unknown.** `ChatScreenReader.read` looks for the input box as "the last two full-width `─` rules with `❯` between them" (`Sources/DuoKit/Chat/ChatScreen.swift:355`); the panel has neither, nor any dialog signature, so it reaches `return ChatScreen(kind: .unknown, sig: "unknown")` at `ChatScreen.swift:454`.
2. **Unknown for the grace period falls back.** `evaluateFallback` waits `grace` 0.5 s (`ChatSession.swift:272`) and calls `fallBack(commandScreen() ?? .unknownScreen, rule: "command-screen")` (`ChatSession.swift:434`). Because the composer sent `/btw` within 20 s (`ChatSend.swift:50` sets `lastCommand`), the bar is the named one: "/btw opens in Claude Code's own screen. Esc closes it and brings chat back." After Esc the screen is busy or idle again and chat returns by itself.
3. **It's on the list on purpose.** `/btw` is in `terminalCommands` (`ChatScreen.swift:87`), so the `/` menu shows it as "Opens in the terminal" with the `>_` mark (`ChatComposerView.swift:159`). F-173 found its screen and put it there; nobody designed a chat form for it.

Two faults come with it:

- **A Queued bubble that never clears.** `send` records your message before Return with `queued: wasBusy` (`ChatSend.swift:49`). A `/btw` sent while Claude works shows as "Queued · Claude reads it when it's ready", but Claude's turn never reads it and no hook or transcript line ever echoes it (`ChatLog.prompt` is what clears `queued`), so it stays queued until a reload drops it. At the prompt it shows as an ordinary message and starts a turn timer for a turn that never comes.
- **The side answer finishes an Agent card.** `ChatIngest` hands every SubagentStop to `ChatLog.agentFinished` (`ChatIngest.swift:231`). Its guard for "Claude's own side agents stop without a start" only returns when no agent card is running (`ChatLog.swift:527`); with one running, the side answer's stop marks that card done with the side answer as its result (`ChatLog.swift:532–533`). Seen in the hook payload on both versions with an Agent step on screen (2.1.323, `06-panel-over-agent.txt`); the misfiling itself is shown by the check, not in a live Duo.

**Reproduced** by `Sources/DuoChecks/BtwChecks.swift` (`DUO_CHECKS=btw`), which fails until the fix: the six panel screens read unknown (6 fail); a `/btw` sent from chat while busy, on a scripted TUI showing each version's real screens, falls back with the named bar and leaves a queued bubble (4 fail); the hook payload finishes a running Agent card (1 fail). It isn't in the default run, so main stays green; the fix adds it there.

## 3. Proposals: functional

What a fix does, whichever look is chosen. Each piece is small and sits on parts that exist.

1. **Read the panel.** A new `ChatScreen.Kind.side`: the last `▔` rule (with or without the effort label) followed by an indented `/btw ` row, and a footer row ending `Esc to close` (`↑/↓ to scroll`, `c to copy`, `f to fork`, `⇧←/→ to browse`, `x to clear history` as its parts say). Parsed: the question, the state (answering when a spinner glyph and `Answering…` follow, else answered), the answer's screen text, which keys the footer offers, and the history position. Signatures go in `ChatSignatures` beside the others, verified on 2.1.284 and 2.1.323 with these screens; another 2.1.x is trusted while it reads like them (DL-155), else the terminal as today.
2. **Never fall back on it.** `.side` joins `.picker` as a screen chat draws: no unknown timer. Mode and busy carry over from the screen before it (as the `/` menu does, `ChatSession.apply`), so the tab stays "working" and the reply above keeps streaming. Drop `/btw` from `terminalCommands`.
3. **Send it as a command, not a message.** In `send`, a `/btw …` text isn't recorded as your bubble (`log.sent`) and doesn't set `turnStarted`; chat opens the side card in its "answering" state with the question instead. `lastCommand` is still set, so if the panel ever reads unknown the named bar stays the fallback.
4. **Take the answer from the hook.** A `SubagentStop` with an empty `agent_type`, no SubagentStart for its id, and a side card waiting, is the side answer: its `last_assistant_message` is the card's Markdown (it keeps what the screen drops). `agentFinished` ignores such a stop for agent cards whether or not one is running. The screen text stays the fallback when no hook comes (hooks off, a remote viewer).
5. **Keys go to Claude Code.** The card's buttons and keys send Claude Code's own: `c`, `f`, Esc, ↑/↓, ⇧←/→, `x`, each after re-reading the screen (as review cards do). Copy also puts the hook's Markdown on Duo's clipboard (Claude Code's `c` copies the plain text).
6. **After it closes** (Q-551): keep the exchange in `ChatLog` as a quiet item tied to where you asked; Show reopens the card from memory, without a new query.
7. **Typing closes it** (Q-552): with the card up, a printable key sends Esc, waits for the input box, then puts the key into the composer.
8. **duo2 (DL-71):** `duo2 session btw <id> "<question>"` (asks, shows the card if the session is in chat, waits, prints the answer; `--json`), `--close`, `--copy`, `--fork`; `duo2 session btws <id>`; `chat-state` gains `side`. Menu items: Chat › Ask a Side Question…, Copy Side Answer, Close Side Question.

Not proposed: answering side questions without Claude Code (a direct API call from Duo). DL-118 makes chat an overlay on the real TUI, never a second client, and Duo never picks a model.

## 4. Proposals: design (canvas https://claude.ai/artifact/L2NaLSyuma4dDhExA9SH4G)

In the chat-mode handoff's look, every mark [P]; no accent anywhere, since a side question never needs you.

- **Board 0** (https://claude.ai/artifact/L2NaLSyuma4dDhExA9SH4G, "0 · What /btw does, why chat falls back, the questions"): the findings above in one page.
- **Board 1, Q-550, where the answer shows:** today's fallback; **A, a side card docked in the composer's place** (pane, a 1 `controlEdge` edge, radius 12, section label "Side question · not part of the conversation", your question in `bodyEmphasis`, the answer as Markdown, Copy `c` · Fork… `f` · Close `esc`, "Claude keeps working above"); B, an aside in the feed with Duo closing the panel itself; C, a popover over the composer.
- **Board 2, A's states:** Answering (a still working ring, "Answering · 3s", Close only), a long answer that scrolls inside the card, Claude Code's "No answer available …" in `text2`, at the prompt with history ("2 of 2", ‹ ›, Clear history `x`), and over a running agent.
- **Board 3, Q-551 and Q-552:** after it closes, a quiet line "Side question: … · Show" (A), nothing (B), or kept across restarts (C); with the card up, typing closes it and starts your message (A), Duo closes the panel once answered (B), or a draft held by Duo (C).
- **Board 4, Q-554 and Q-553, keys and duo2:** `/btw` stays the way to ask with its menu row reading Claude Code's description (A) or also an "Ask aside" control while Claude works (B); Fork… after a run confirms what `f` does; the keys and verbs above.

## 5. Decisions for Geoff (console-ready cards, recommendation first)

Each card's link is the canvas board named; the canvas is https://claude.ai/artifact/L2NaLSyuma4dDhExA9SH4G.

- **Q-550 · Where should a side answer show in chat?** (board 1, https://claude.ai/artifact/L2NaLSyuma4dDhExA9SH4G)
  - **A (recommended): a side card in the composer's place**, as Claude Code puts its panel where its prompt was; the reply above keeps streaming.
  - B: an aside in the feed, with Duo closing Claude's panel itself.
  - C: a popover over the composer.
- **Q-551 · What stays once the side card closes?** (board 3)
  - **A (recommended): a quiet line where you asked, "Side question: … · Show", reopening it from Duo's memory while Duo runs.**
  - B: nothing, as Claude Code (its own history is one `/btw` away).
  - C: kept across restarts in Duo's support folder, searchable (ENH-353).
- **Q-552 · What happens to the composer while the card is up?** (board 3)
  - **A (recommended): the card holds its place; typing closes it (Esc to Claude Code) and starts your message with what you typed.**
  - B: Duo closes Claude's panel as soon as the answer is in.
  - C: Duo holds a draft under the card until it closes.
- **Q-553 · Fork from a side answer?** (board 4)
  - **A (recommended): a Fork… button, built after one mock run per version shows what Claude Code's `f` does (a background fork or a branch of this session).**
  - B: Fork stays a terminal job (the card hands over).
  - C: no Fork for now.
- **Q-554 · How do you ask?** (board 4)
  - **A (recommended): `/btw` in the composer; its `/` menu row reads Claude Code's description instead of "Opens in the terminal".**
  - B: A, plus an "Ask aside" control while Claude works.
  - C: typed only, menu row unchanged.

## 6. Before the build

- One mock run per version for `f` (Q-553) and for the synthetic "No answer available" path (point the mock's side reply at an error).
- The screens for narrow panes (60 columns and under; F-539) and 2.1.219 (the oldest 2.1.x DL-155 trusts), so the `.side` signature is checked where the footer is cut short.
- The hook path when a session runs with chat's hooks off (`DUO_CHECKS=btw` covers the hook; a live chat-live case should send `/btw` through a real Duo on the mock).
- Records numbered here: F-688 to F-690, Q-550 to Q-554, C-185, ENH-353.

## 7. Sources

- Claude Code's own strings, read from the 2.1.284 and 2.1.323 binaries (command definition, prompt, footer words, the fork paths).
- The runs: scratch only (job folder), method above; the kept screens are in `Spikes/chat-mode/screens/btw-2.1.*`.
- Duo: F-173/F-174 (slash commands in chat), DL-118/119 (chat is an overlay; review cards dock), DL-143 (pickers as cards), DL-154 (fallback stays), DL-155 (version trust), F-652/F-656 (the same mock method for rewind), DL-338 (Fork).
