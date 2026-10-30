# Session-to-session messaging for the director, tested

Geoff, 2026-10-28: "update for the director skill: the work machine now supports direct session to session/agent to agent messaging in claude code; are there opportunities to simplify the director skill to use this primative instead?" This note says what the messaging primitives actually do on the work Mac's Claude Code (**2.1.284**) and this Mac's (**2.1.311**), and proposes what the director can drop. Records: F-421 (what messaging does), F-422 (Duo bugs found on the way), Q-290 to Q-292 (Geoff's picks), C-121, DL-257.

**How it was tested.** These were real `claude` sessions on Haiku 5.5, about a dozen short turns, in a scratch folder (`build/dm-scratch` in this work tree). The scratch sessions were `claude --bg` in `auto` and in `default`, one `--bg --remote-control`, and one 2.1.284 run interactively in a pseudo-terminal, the way a Duo terminal runs Claude. They used the real `~/.claude`, because a scratch config isn't logged in and credentials are never copied. The tester was this session (`claude --bg`, auto, 2.1.311). Where a case couldn't be run (a bypass session: auto mode refused to start one; a second Desktop session), the rule comes from the CLI's own code, read in both binaries, and from director-duo-v2's transcript. The two binaries agree.

## 1. What the primitives do

| | Result | Same on 2.1.284? |
|---|---|---|
| **Permission classes** | The CLI sorts every session into one of two classes. **bypass**: `bypassPermissions`, or plan mode entered from bypass. **prompting**: everything else, `auto` and `default` included. A message within a class is delivered. A message across classes is **held** for the receiver's user to approve, and expires. It's tagged `from-mode="prompting"` or `"bypass"`. A `crossSessionInbound` setting (`accept` / `hold` / `refuse`) can override this; managed or repo settings can only tighten it. | Yes (same policy code; 2.1.284 also has `bypass-default` and `mode-unknown` holds) |
| **auto ↔ default** | Delivered both ways: T1 from me (auto) to `dm-default`, and its reply back. | Yes |
| **bg ↔ bg, bg + Remote Control** | Delivered. A Remote Control worker on this Mac is reached over the local socket like any other (T6). | n/a (RC worker ran on 2.1.311) |
| **Interactive TUI (as in a Duo terminal)** | Delivered both ways (T5, 2.1.284 run in a pty). Its beacon lists `peerFeatures: notify_idle, …`. | Yes, tested on 2.1.284 itself |
| **`to`** | The peer name from `ListAgents` is the session's `-n` name for `claude --bg -n` and `claude -n`. A reply by **name** works (T5, T6). | Yes |
| **`from`** | `uds:/tmp/cc-socks/<pid>.sock`: tied to the process, so it goes stale when that session restarts. Reply by name for anything later than "now". | Yes |
| **Busy receiver** | Queued; read at its next tool round, in the same turn (T8b answered inside T8a's turn). | Yes |
| **Stopped receiver** | `No agent named '…' is reachable`. Nothing is queued. | Yes |
| **`notify_when_idle`** | One-shot. The notice is **queued until the subscriber itself is idle** (none arrived during my long turn; all six came in a batch when I stopped), and it wakes an idle subscriber. It carries the start of the worker's last message («T2 done», «Sent T5-ACK …»). **Subscribing to a session that's already idle fires at once with its last turn** (T9), which is a cheap catch-up. It expires after some hours. The notice is held if the classes differ. | Yes (`notify_idle` peer feature) |
| **Held, then expired** | director-duo-v2, 2026-10-19: held at 21:18:43, "not approved before expiry" at 21:35:04, so **about 16 minutes**. | Same code |
| **Delivery notices** | For a session on this Mac, a `[Cross-session delivery notice]` says when a message is held, expires or is refused. For a Desktop, Remote Control (off-machine) or cloud session, nothing comes back. | Yes |
| **Waking a stopped bg worker** | `claude --bg --resume <full id> -- "<msg>"` wakes **the same session** "with its saved options (--remote-control, -n, --permission-mode, --model)". With **any** flag it "started a copy as <new id>" under a new name (T10). A short id opens the resume picker. | Yes: the help text and both notes are in 2.1.284 |

## 2. Why director-duo-v2 couldn't hear its workers

Its transcript's latest entries (60d72656, 2026-10-28) still say `permissionMode: bypassPermissions`. Every worker runs in `auto`. That is a class mismatch, so every report to it is held, and its sends to workers are held too ("held by that session … not approved before expiry", 10-19). Messaging itself is fine: **switch director-duo-v2 to Auto** (or start a fresh `claude -n director-duo-v2` in Auto) and messages flow both ways. Address workers by their `-n` names (`ListAgents` shows them); workers send to `director-duo-v2` by name.

## 3. Duo bugs found on the way (F-422)

1. **`send`'s background resume makes a copy.** Both `AppModel+DirectorSend.carry` and `directorSendOffline` pass `--remote-control <name>` with `--bg --resume`, so the CLI starts a renamed copy instead of waking the worker. The worker's name and its `.duo/director.json` link no longer match the session that got the message. Fix: no flags; its saved options already keep Remote Control.
2. **The `2.1.285+` gate on background resume is wrong.** 2.1.284 has it, so the work Mac fell through to a headless turn.
3. **DL-222's "status warns when modes differ" was never built.** No director code reads a permission mode.

## 4. Proposal

**The new happy path**, every session in a prompting mode (Auto), on 2.1.284 or later:

1. `duo2 director start` starts the worker (`claude --bg --remote-control`, as now).
2. The director reaches a live worker with `SendMessage(to: <worker name>, notify_when_idle: true)`. `duo2 director send` logs it and prints exactly that call.
3. The worker reports with `SendMessage(to: "director-<project>")` **by name**, and ends its turn with the report and a Progress line as before.
4. The director wakes on the message or the idle notice. The notice carries the worker's last words; it reads the full report (`duo2 session show`) only when the excerpt isn't enough.

**Remove:**

- **DL-199's Duo typing into an idle worker** (`duo-submit`, `SubmitGuard`) and **the queue** (`queued`, `deliverDirectorMessages`). A Duo-hosted worker takes messages like any other.
- `start` choosing `--in-duo` because the client has no messaging. Duo-hosted workers only when the user asks.
- The skill's five-rung waking ladder.
- "read every task's note and transcript on every wake" as the main channel.

**Keep as fallbacks, and when they fire:**

- **A stopped worker:** `claude --bg --resume <id> -- msg` with no flags (fixed). In Duo with Duo running, Duo reopens it in its tab (`duo-resume`). With background sessions off, a headless turn.
- **A class mismatch, or messaging refused** (`crossSessionInbound`, a denied SendMessage, a CLI older than 2.1.224): `status` says which and how to fix it ("switch this session to Auto"). Until it's fixed, hear back by reading notes and last messages, and `watch` under Monitor.
- **After a restart or compaction** (subscriptions die): `status`, then one `notify_when_idle` (no message) to each live worker, which catches up at once.
- **A `[Cross-session delivery notice]`** that says held, expired or refused: read that worker's note and last message.
- **A Desktop or off-machine Remote Control peer:** no delivery notice comes back, so for these, silence still isn't an answer.

**Unchanged:** nothing relies on `bypassPermissions` (DL-222); a worker's message is never the user's approval, and no untrusted text is relayed automatically (Never 1); the user typing in a worker pauses the director (DL-200), and `send` still refuses there.

**Duo changes:**

- `send`: the ladder becomes message → resume → ask the user.
- `status`: a messaging line that compares classes (this session's mode against each worker's last `permissionMode` in its transcript).
- `watch`: a fallback, which `status` names when messaging can't carry.
- DirectorChecks: the 2.1.284 behaviour as a recorded fixture.

## 5. Geoff's picks (2026-10-28, by buttons)

He took every recommendation: retire Duo's typing and queue (Q-290), messages first (Q-291), `watch` as a fallback, and director-duo-v2 to Auto (Q-292). The decision is DL-257. Duo's guarded Enter (`guardedSubmit`, `SubmitGuard`) stays, because Markdown review's @claude comments use it on the person's say-so (F-390). Only the director stops using it.

## 6. For director-duo-v2: how to start using it

1. Switch the session to **Auto** in the Claude app's mode picker, or restart it as `claude -n director-duo-v2` in Auto. Its transcript should then show `"permissionMode":"auto"`.
2. Address each worker by its `-n` name, as `ListAgents` shows it (for example `director-messaging`). Send with `notify_when_idle: true`.
3. Workers send to `director-duo-v2` by name. CLAUDE.md's build-session rule says so now.
4. Workers in Auto or Default are both fine. Only a session in `bypassPermissions` breaks the channel.
5. After a restart or compaction, subscribe again: `SendMessage(to: "<name>", notify_when_idle: true)` with no message. A Claude app session gets no delivery notice from a message sent to it, so it still can't take silence for an answer.
