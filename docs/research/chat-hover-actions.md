# Hover actions on chat turns: rewind, fork, copy

Geoff, 2026-11-11: "in chat mode I want hover ui for rewind and fork; rewind has a button in claude desktop, but fork feels like a good fit too; while exploring, we should consider other ui elements, like copy (which would copy the agent turn or user turn as raw markdown)".

Research and design only; nothing is built. Task: `tasks/chat-hover-actions.md`. Records: F-652 (what Claude Code does), F-653 (what Duo does today, and the Claude desktop app), Q-505 to Q-509 (the decisions), ENH-342 (left for later). The canvas is https://claude.ai/artifact/HLHzGsZNpn3hS1KsZAZx71 (sources in `docs/design/chat-hover-actions-study/`); the decision walkthrough is `docs/research/chat-hover-actions-walkthrough/`.

**In one paragraph.** Claude Code already has everything needed, behind its own `/rewind` menu and three hidden flags, and both are the same on 2.1.284 (the work Mac's pin) and 2.1.316. Rewind removes a turn and everything after it, puts that prompt back in the input box, and can also put back the files Claude's own Edit and Write tools changed (not Bash's). A fork from an earlier turn has no interactive flag, but a whole fork followed by a conversation-only rewind in the copy gives exactly that, using only Claude's own mechanisms. Copy needs nothing from Claude. The one real piece of plumbing is that chat drops each record's `uuid` today and ignores `parentUuid`, so it can't name a turn to Claude, and after any rewind (even one typed in the terminal) it would still show the removed turns. Recommended: a quiet row under each turn on hover: **Copy, Rewind, Fork** on your messages, **Copy, Fork** on Claude's, Duo's own sheet before a rewind, and Duo drives Claude's menu.

## 1. What Claude Code does (F-652)

Checked 2026-11-10 on **2.1.284** (npm-installed into a scratch folder) and **2.1.316** (current here), each with a scratch `CLAUDE_CONFIG_DIR`, a dummy key and `ANTHROPIC_BASE_URL` on the repo's mock API (`scripts/director-harness/mock-api.mjs`), `--model claude-haiku-5-5`. The mock returns tool calls, so real turns ran that wrote files: "hello", "write A" (Write `a.txt`), "write B" (Write `b.txt`), "bash C" (Bash `echo > c.txt`). The TUI was driven headless (node-pty and a headless xterm), never on screen. No real login and no tokens.

### Rewind (tried on both)

- **`/rewind`** (aliases `/checkpoint`, `/undo`), or **Esc Esc with an empty input**, opens one menu. With text in the input, Esc Esc clears it instead.
- **Step 1, the list:** "Restore the code and/or conversation to the point before…", your earlier prompts oldest first, each with what it changed ("b.txt +1", or "No code changes" for the Bash turn), then "(current)". Arrows pick; "↑ 2 more" when it scrolls.
- **Step 2, the confirmation:** "Confirm you want to restore to the point before you sent this message:", the prompt quoted, then:
  1. Restore code and conversation
  2. Restore conversation
  3. Restore code
  4. Summarize from here
  5. Summarize up to here
  
  and Never mind. Without file changes: only 2, 4, 5. The words under it differ by version:
  
  | | 2.1.284 | 2.1.316 |
  |---|---|---|
  | Conversation line | "The conversation will be forked." | "This message and everything after it will be removed." |
  | Warning | "Rewinding does not affect files edited manually or via bash." | "Restored files go back whole, losing later changes by anyone. Bash changes to other files are not undone." |
- **Restore conversation:** the prompt goes back into the input box, ready to edit and send. The session keeps its id and its file. **Nothing is deleted from the JSONL:** the next prompt's `parentUuid` points at the record before the rewound turn, so the removed turns stay in the file as a dead branch. A later resume or fork follows the live chain only. No marker record is written.
- **Restore code:** files Claude made or changed with Write/Edit at or after that turn go back (made ones are deleted: `a.txt` and `b.txt` went). `c.txt`, made by Bash, stayed. The conversation is unchanged. Option 1 does both.
- **Where the copies live:** `‹config›/file-history/‹session id›/‹hash›@v‹n›`, indexed in the transcript by `file-history-snapshot` records keyed by the user message's uuid (`trackedFileBackups`) and `file-history-delta` records. On by default (`fileCheckpointingEnabled`; `CLAUDE_CODE_DISABLE_FILE_CHECKPOINTING` turns it off). `-p` runs don't snapshot by default.
- **Not covered,** per the docs (https://code.claude.com/docs/en/checkpointing) and the run: Bash's changes to files Claude never edited, edits outside Claude or by other sessions, most subagent edits, symlinks. Snapshots are kept for the last 100 checkpoints and swept with the transcript (`cleanupPeriodDays`).

### Fork (tried on both)

- **`claude --resume X --fork-session --session-id N`** works interactively and in `-p` on both: a new file with every record copied (same uuids), no `forkedFrom`. This is what Duo's Resume as a Fork already runs (`Terminals.swift:271`).
- **Hidden flags, on both:** `--resume-session-at ‹message uuid›` (cuts a resumed or forked session after that message; "No message found with message.uuid of: …" for a bad one; **"Ignored outside print mode"**, so it can't open an interactive session at a turn), its safety check `--resume-drops-turn`, and `--rewind-files ‹user message uuid›` (restores files and exits; needs `CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING=1`: 2.1.316 says "File rewinding is not enabled." without it, 2.1.284 silently does nothing). These are the Agent SDK's; they're undocumented for the CLI and could change.
- **`/branch [name]`** forks at the end only (its argument is a name), switches the terminal to the copy, and stamps `forkedFrom` (DL-227). **`/fork ‹directive›`** starts a background copy (F-344).
- **So a fork from an earlier turn, interactively,** is either a whole fork then a conversation-only rewind in the copy (Claude's own steps; not run end to end, see §5), or Duo writing a cut copy of the transcript itself.

### Transcript facts for Copy (tried)

- A typed prompt: `type: "user"`, `message.content` a string, `promptSource: "typed"`, `origin.kind: "human"`, a `promptId` shared with its turn's tool results, no `isMeta` or `toolUseResult`. With an image, `content` is blocks (text, image, text) and a companion `isMeta`, `turnCompanion` record follows.
- Claude's reply is several `assistant` records sharing one `message.id` (text, then tool_use, and so on).
- A turn must be found by walking `parentUuid` from the leaf, not by file order, because rewound branches stay in the file.
- 2.1.316 also writes `api-request*` records (with system prompts) into transcripts; 2.1.284 doesn't.
- Not seen: thinking records (the mock doesn't make them), a compact summary record, how a long paste is stored.

## 2. What Duo does today (F-653)

Read in code on `origin/main` dc8df8e9.

- **Chat is native SwiftUI** (`Chat/ChatView.swift`, `ChatRows.swift`), fed from the transcript tail (`ChatFeed`, `ChatIngest.record`), not from the screen. The screen reader (`ChatScreen`) gives state and dialogs.
- **Turns have no transcript ids.** `ChatYou.id` and `ChatTurn.id` are counters ("you-12"); `ChatIngest` reads neither `uuid` nor `parentUuid`. To rewind or fork at a turn, Duo has to keep each prompt's `uuid` (and the last assistant uuid of each reply).
- **Chat follows file order.** After a rewind (Duo's or one typed in the terminal), the removed turns stay in the feed, and a reload shows them again, because the dead branch is still in the file. This is a bug today for anyone who uses `/rewind` in a chat session, independent of this design.
- **Raw Markdown is kept:** your text in `ChatYou.text` (image tokens stripped, pictures as `images`), Claude's per text segment (`ChatText.markdown`), with tools, thinking and questions as other segments.
- **No per-turn actions exist.** No context menu, no hover row. The only hover in chat is the composer's picture and voice controls; the code block's Copy button is always shown (`ChatCopyButton`, 26×24) though DL-220 drew it on hover.
- **Keys:** ⌥⌘↑ and ⌥⌘↓ move between your messages (DL-242). Duo can press Esc and type slash commands into the TUI (`ChatKey`, `ChatSend`); it has no reader for the rewind menu, so sending `/rewind` from chat lands in the terminal fallback today.
- **Busy:** `chat.screen.kind == .busy` is the authority; the Stop button already keys off it.
- **Fork:** `ConsoleStates.resumeAsFork` mints the id (DL-14), runs the whole fork and selects it; `duo2 session fork <id>` exists. No turn argument anywhere.
- **The Claude desktop app** (5.1231.2, read from its bundle's strings, not run): its Code sessions have `rewindV2(sessionId, targetMessageUuid)`, `canRewindTo`, `rewindFiles(sessionId, userMessageUuid, dryRun)` (a dry run lists the files first), `undoRewind` and "rewind marks". Bug reports describe a "Rewind" button beside Copy on hover, clicked by accident with no confirmation (#99611), and a "Fork from here" on past user messages (#49954, #43755). I couldn't confirm what its single Rewind button restores.

## 3. What others show

| Product | On your message | On the reply | Notes |
|---|---|---|---|
| Claude desktop, Code | Rewind, Fork from here, Copy (hover) | Copy | Rewind has an undo, apparently no confirmation (reports, bundle) |
| claude.ai | Edit (pencil; branches, ‹ 1/2 ›), Copy | Copy, Retry, thumbs | Retry versions as 1/N (teardown) |
| ChatGPT | Edit | Copy, Regenerate, More › Branch in new chat | |
| VS Code Copilot | Restore Checkpoint (hover), asks first | | Files and later requests removed |
| Cursor | Restore Checkpoint | | Files only |
| Zed | Click to edit | Right-click: Copy as Markdown | |

Sources are in the web survey notes in §7.

## 4. The actions

Each needs Claude idle unless it says otherwise. Duo never edits a transcript.

| Action | What it does | How Duo does it | What can go wrong | Worth it |
|---|---|---|---|---|
| **Copy** (both) | Puts the turn on the clipboard as Markdown. Yours: as typed, pictures as `[Image #n]`. Claude's: its words (text segments joined by a blank line); no thinking, no tool calls (Q-509). | From `ChatLog`; no Claude involved. Works while Claude works. | A turn still streaming copies what's there so far: offer it only once a turn ends. | Yes. Cheap, no risk. |
| **Rewind** (yours) | Removes this prompt and everything after it, and puts the prompt back in the composer. Can also put back the files Claude changed (Q-506). | Duo's sheet first, then Duo drives Claude's own menu: Esc Esc (or `/rewind`), pick the prompt by its text and position, pick option 2 or 1, check each screen's words (both versions'), then carry Claude's prefilled input into chat's composer (Q-507). | Claude busy (disabled). A draft in the composer (kept; the rewound prompt waits until you clear it, stand-in). Code restore hits other sessions in the same folder ("losing later changes by anyone") and never undoes Bash. A turn older than the 100-checkpoint window has no code restore. A menu that doesn't match: chat shows it in the terminal (fallback), never guesses. Chat must then drop the removed turns (needs the leaf-chain fix). | Yes. It's the ask, and Claude has it. |
| **Fork from here** (both) | A new session that starts from this point, in a new tab next to this one. From your message: everything before it, with your prompt in the composer to change. From Claude's reply: everything up to and including it. | Whole fork with a minted `--session-id` (DL-14), then a conversation-only rewind in the copy, to this prompt or to the next one (Q-508). On the last reply: just the fork. Never restores code in a fork: both sessions share the folder. | Two sessions in one folder edit the same files (as any fork today). The rewind step in the copy is the risky part; if its menu doesn't match, the copy shows its terminal, uncut. The fork's own checkpoints: untested whether copied. | Yes. Desktop has it; it's the safe way to try another path. |
| **Edit and resend** | Your message, changed, sent again. | Rewind does it: the prompt comes back to edit. | | Folded into Rewind. |
| **Retry** | Ask the same again. | Rewind, then send unchanged. | Code isn't restored unless you ask. | Later (ENH-342): one click more than Rewind. |
| **Copy a code block** | | Exists (always shown; DL-220 drew it on hover). | | Done. |
| **Quote in the composer** | `> ` the turn into your draft. | `ChatLog` into the composer. | | Later (ENH-342). |
| **Send to a document** | Append the turn to an open note. | `duo2 send`. | | Later (ENH-342). |
| **Show in Terminal** | Scroll the terminal to that turn. | Terminal search. | Scrollback may not hold it. | No. |
| **Link to the turn** | `duo2://session/<id>#<uuid>` | DL-87's link plus an anchor. | Dead after a rewind. | Later (ENH-342). |

## 5. Not verified

- A whole fork followed by a rewind in the copy, end to end: each half was run, not the two together. Whether the copy's checkpoints come across (only matters if a fork ever restored code, which it won't).
- `--resume-session-at` in a TUI (the bundle says it's ignored).
- Restoring a file that existed before (only files Claude created were tested), Summarize from here, pasted text's storage, thinking records.
- What the desktop app's Rewind button restores.

These are the first job of any build: one scripted run on the mock per version, as in §1.

## 6. The design and the decisions

The canvas draws the row, each action's states, the sheets and keyboard reach, in the chat-mode handoff's look; every mark is [P]. Board by board:

1. **The row** (Q-505): on hover, a row of 22-high quiet buttons under the turn: under your bubble at its right edge, under Claude's card at its left; the meta line's time moves into the row. Your message: Copy · Rewind · Fork. Claude's: Copy · Fork. No row while a reply streams; Rewind and Fork dim with "When Claude finishes" while it works.
2. **Copy:** the icon turns to a check and "Copied" for 1.5 s.
3. **Rewind** (Q-506, Q-507): Duo's sheet, then the turns leave and the prompt is in the composer, with a note "Rewound to before ‹prompt›. Files are as they were." / "‹n› files put back."
4. **Fork** (Q-508): the new tab right of the original, focused, in chat, with the fork mark (DL-228); its feed ends at the point; the prompt in the composer when forked from your message.
5. **Copy, keys and duo2** (Q-509): the copied text for A and B. No new chord (DL-34 locks the map): ⌥⌘↑/↓ selects a message (DL-242) and shows its row, Tab reaches its buttons, and the Chat menu has Copy Message, Rewind to Before Message… and Fork from Message…; each turn also carries them as accessibility actions. Verbs: `duo2 session turns <id>`, `duo2 session copy-turn <id> <turn>`, `duo2 session rewind <id> <turn> [--code]` (shows Duo's sheet and waits, like `trust-folder`; no `--yes`), `duo2 session fork <id> [--at <turn>]`. A turn is its number in `session turns` or its uuid.

The decisions (recommendation first), each a Q row:

- **Q-505 Which actions, and where.** A: a hover row: Copy, Rewind, Fork on yours; Copy, Fork on Claude's (recommended). B: also Retry and Edit as their own buttons. C: Copy now, Rewind and Fork later.
- **Q-506 What Rewind restores.** A: Duo's sheet asks: Conversation only (default), or Code and conversation when that turn changed files, naming them and the Bash caveat (recommended). B: conversation only, always; code stays a terminal job. C: Claude's whole menu in Duo, Summarize included.
- **Q-507 How Duo rewinds.** A: Duo drives Claude Code's own menu after its sheet, checking each screen, falling back to the terminal when one doesn't match (recommended). B: Duo opens Claude's menu in the terminal for you to finish. C: Duo cuts the transcript itself and restarts the session (rejected by the research: Duo never edits transcripts, and `--resume-session-at` only works in print mode).
- **Q-508 Fork from a turn: how, and where it opens.** A: a whole fork, then a conversation-only rewind in the copy; a new tab right of the original, focused, prompt in the composer when forked from yours (recommended). B: the same, but the copy opens in the background and the original keeps focus. C: Fork only on the last reply (a plain fork), none on earlier turns.
- **Q-509 What Copy puts on the clipboard.** A: the turn's words as Markdown; Claude's text only, no thinking or tool calls (recommended). B: with each tool call as one line (`Ran npm test`, `Edited flows.md`). C: A, and ⌥-click for B.

## 7. Sources

- Spike scripts and screens: kept off the repo (scratch); method as in `docs/research/fork-handling.md`. The screens quoted above are the spike's.
- Claude Code docs: https://code.claude.com/docs/en/checkpointing, https://code.claude.com/docs/en/sessions.
- VS Code Copilot checkpoints: https://code.visualstudio.com/docs/copilot/chat/chat-checkpoints. Cursor: https://cursor.com/docs/agent/chat/checkpoints. Zed: https://zed.dev/docs/ai/agent-panel. claude.ai teardown: https://aiuxplayground.com/teardowns/claude/output.
- Claude desktop: bundle strings of `/Applications/Claude.app` 5.1231.2; issue reports #99611, #49954, #43755, #86916, #60121 (search snippets only).
