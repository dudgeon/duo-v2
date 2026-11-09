# Implicit state machines in Duo v2

2026-11-08 · branch `research/implicit-state-machines`, reviewed at main `58de7d80` · read-only: no code changed, no build, nothing run. The page for Geoff is [`implicit-state-machines/index.html`](implicit-state-machines/index.html); this file is the record for future sessions. Records: F-626, F-627, C-171, C-172, ENH-332, ENH-333, ENH-334. Decisions are Geoff's and come later.

**Method.** Six Sonnet sweeps by folder over `Sources/` (all of `DuoKit`, `DuoControl`, `DuoSearch`, `DuoDeck`, `duo2`), `Vendor/codemirror/src` and the scripts that hold state, and one over the whole findings log and concerns list. Every machine and bug below was then re-read by the reviewer at the lines cited, unless it's listed under [Not confirmed](#not-confirmed). Two sweep claims turned out wrong and were dropped (same section). **Nothing was run**: a "bug" here means the code path reads that way, and each needs a failing check before its fix.

**Counts** (non-`Debug` code, by grep, so approximate): 465 `Bool` properties or fields in `DuoKit`; 89 timers (59 `asyncAfter`, 17 `Task.sleep`, 13 `Timer.scheduledTimer`); 15 hand-rolled generation or revision counters. Most of the Bools are harmless. The list below is where they combine.

## Verdict

1. **A session has no single state.** The biggest finding. `SessionState` is only the five-value attention enum. Running, parked, detached, elsewhere, ending and ended live in separate sets and probes, read by at least nine deciders that disagree at the edges. About 36 logged incidents are in this area, the most of any.
2. **Chat is the most repeatedly patched.** Which surface shows (chat or terminal) has been fixed at least nine times (F-105, F-108, F-173, F-208, F-243, F-376, F-419, F-449, F-437), mostly by adding a timer. And six separate flags decide who may type into Claude's prompt.
3. **Where Duo went explicit, it worked.** F-264 turned three separate data-loss bugs in the editor into one enum and one token. `VoiceMachine` is 18 lines and fully tested. The approach is proven here; it just hasn't reached the worst places yet.
4. **DL-167 step 5 half happened.** See [below](#did-dl-167-step-5-happen).
5. **Don't flatten everything.** Of 24 machines, six are worth real work. The rest want a small tightening or nothing. A timer stays where the outside world truly gives no event (Claude Code's screen has no "finished drawing").

## Did DL-167 step 5 happen?

DL-167 step 5 asked for "one state machine for the Swift host, with generation tokens and a DuoChecks case".

| Asked for | Status | Evidence |
|---|---|---|
| One document lifecycle | **Yes, for the core** | `EditorController.Phase` (`closed, opening, open, conflict, removed`), `DocumentEditor.swift:57-66`; `conflict` and `removedOnDisk` derive from it (`:71`, `:91`) |
| Generation tokens | **Yes, and it worked** | `generation` (`:68`) is captured by `resolve`, `recreate`, `load`, `saveNow`, `applyNoteEdit`, `reconcile` and the watcher's settle. Bumped only where the document changes (`:213`, `:262`, `:802`) |
| A transition function | **No** (not asked for by name, but it's what "one machine" needs) | `phase` has 14 assignments, all in the one file, each deciding for itself (`:217, 263, 294, 306, 325, 353, 364, 380, 387, 740, 746, 764, 768, 803`). Nothing says which moves are legal |
| One state | **Partly** | Outside `phase`: `dirty` (10 writes), `readOnlyReason` (6), `diskBytes` (7), `kept`, `switchingTo`, `pending`, `pageReady`, `previewing`, `conflictLines`, `renamedTo`, and four copies of "what's on disk" (Swift `diskBytes`, `kept[url].base`, JS `base`, JS `held[id].base`) |
| A DuoChecks case | **No** | DuoChecks only waits for `phase == .open`. No check asserts a transition or a dropped reply. The proof is `scripts/check-editor-host.sh`: real, valuable, one app launch per case, 19 assertions when F-264 wrote it |

**Judgement.** The hard part was done and it held: the fault F-44, F-52 and F-263 shared hasn't recurred as such. What's missing is the cheap part: one place that moves `phase`, and a logic check that needs no web view.

## The machines

Severity is for the user (U), the developer (D) and the architecture (A): H, M or L. "Writes" counts non-`Debug` assignment sites. Remedy is one of **leave**, **tighten** (a small change: one enum, one writer) or **make explicit** (an enum with associated values, a transition function, a check per transition).

### Serious

#### 1. Session life (U H, D H, A H): make explicit, ENH-333

What state is this session in? Inferred states: listed, starting, running (with attention: working, needs you, ready, idle), parked, detached fork, running elsewhere, ending, ended by itself, archived, replaced (rekeyed by `/clear`, split by `/branch`).

- **Deciders:** `Fixture.Session.state` and `liveProcess`; `terminals.existing(key)` with `.exited`, `.isLiveClaude`; `parkedTabs` (`AppCore.swift:313`); `detachedForks` (`:316`); `liveElsewhere` (`:333`); `DuoState.archivedSessions`; `workerFacts` (`Director.swift:178`); `ParkCheck.why` (`Parking.swift:48`); `busy` (`AppModel+CloseTab.swift:14`); `hasOpenTerminal` (`Shells.swift:13`); `tabSessions` (`AppModel.swift:314-320`, an OR of four things minus a fifth).
- **Writes:** `parkedTabs` 4 (`AppModel+Park.swift:80`, `AppModel+Restore.swift:157`, `AppModel+Control.swift:1516`, `AppModel+DirectorSend.swift:207`). `consoleTab` 34, `homeTab` 31.
- **Tell:** `fixture = fixture` as a "please redraw" (`AppModel.swift:655`, and after park, rekey, close), and `endedRevision`, an integer bumped by hand so views notice a terminal ended.
- **Rekey is a hand-kept list, twice:** `followSessionChanges` (`AppModel.swift:617-638`) moves chats, terminals and each window's tab; `splitBranch` (`AppModel+Forks.swift`) moves a different set, and only for the calling window.
- **Incidents:** F-126, F-208, F-210, F-360, F-405; about 36 in the log.
- **Bugs:** a, b below.
- **Remedy:** a derived, read-only `SessionLife` enum and one function that computes it from today's stores, with every decider moved onto it; one writer for parked (cleared on wake); one `rekeySession(old, new)` covering every per-session map. Then a check per transition.

#### 2. A terminal tab's process (U M, D M, A H): make explicit, ENH-333

States: not started, running, closing (we signalled, not reaped), ended by itself, missing Claude, gone. Lives in `exited` (`Terminals.swift:210`, 3 writes), `ended` (`:310`), `missingClaude` (`:308`), `hasProcess` (`:318`), the store's `closing` (`:606`), `ProcessWatcher.sessions`, closures `onEnded`, `onGone`, and a 3 s `killAfter`.

- Representable and wrong: `exited == true` while the process is alive, which is true after every `terminate()` until reaping (`:329-332`). `hasOpenTerminal` and `ParkInputs.hasTerminal` read `!exited`, so they say "not running" while a pid is alive.
- 4 flags make 16 combinations; 6 are meaningful.
- **Incident:** F-126 (C-30): three sessions stuck exiting, archive refused. The state "closing" didn't exist, and adding it was the fix.
- **Remedy:** one `TerminalLife` enum replacing the flags; the session life reads it.

#### 3. Chat surface: chat or terminal (U H, D H, A M): make explicit, ENH-334

States: chat; fallback (automatic, handed over, command); terminal by choice; with hidden grace sub-states. Lives in `mode`, `fallback`, `screen`, `pendingRequest`, `sending`, `composing`, `unknownSince`, `disagreeSince`, `unknownTimer`, `lastCommand`, `trustAsked`, `versionKnown` (`ChatSession.swift:134-145, 221-227, 254-255, 275-276, 493-496`).

- **Good already, and to keep:** `fallBack` is one entry with a named rule; `noteTransition` logs every move; `showsChat` is derived; `ChatScreen.Kind` has an exhaustive switch; `evaluateFallback` is nearly a transition function already (`:411-488`).
- **Weak:** one timer slot serves three purposes (`unknownTimer`, `:420`, `:437`, `:448`), and `:437` overwrites without cancelling, leaving a stray re-evaluation. Two clocks (`Date()` and the fixture-overridable `now`). `backToChat` clears `unknownSince` but not `disagreeSince` (`:565-570`).
- **Incidents, fixed repeatedly:** F-105, F-108, F-173, F-174, F-208, F-243, F-244, F-246, F-376, F-419, F-437, F-449, F-456; Q-257, Q-328. F-419 is the shape of it: a 1.5 s grace fired before the feed had read the hook, and the fix added a second grace of up to 15 s.
- **Checks:** good outcome checks (`ChatChecks`, `ChatRequestChecks`, `ChatFallbackReportChecks`); nothing covers the timer slot.
- **Remedy:** make `evaluateFallback` pure, `(state, event, clock) -> (state, effects)`. Short step, because it's most of the way there.

#### 4. The prompt channel: who is typing into Claude's prompt (U H, D H, A M): make explicit, ENH-334

Send, carry, answer, paste, the `/` mirror and peek all type into one real prompt. States: free, sending, editor open, placed, carrying, carried. Lives in `sending` (23 writes, a bare Bool that twelve operations set and clear), `composing` (6), `carryPending`, `carrying`, `carried`, `movedVoice` (`ChatSession.swift:140-144`), `ui.composerBasis`, `ui.heldTokens`, `ui.addingPicture`, `mirroring`, `mirrorNext`, and files on disk as handshake (`handoverFile`, `refusedFile`, `peekFile`, `ChatSend.swift:90-111`). Polling stands in for events: 50 × 100 ms, 30 × 100 ms, 7 × 150 ms, 250 ms settles.

- **Tell:** `peekPrompt` saves and restores `wasSending` (`ChatSend.swift:195`, `:217`), because the author knew the Bool can't be nested; `send`'s `defer { sending = false }` doesn't.
- **Incidents:** F-452 (a passage reached Claude about three times, keys dead), F-485, F-420, F-303, F-254.
- **Bugs:** j, k below.
- **Remedy:** one owner of the prompt, a queue with one job at a time and an enum for what it's doing. `mirrorSlash` (F-420) is the existing pattern to grow from.

#### 5. Editor document (U H, D M, A M): tighten

See [DL-167 step 5](#did-dl-167-step-5-happen). **Bugs:** i, m below. **Other:** `readOnlyReason` and `previewing` can outlive what set them; the crash path (`:208-222`) resets some loose state by hand and not `previewing`, `conflictLines`, `renamedTo` or `isDeck`; `pageReady` is checked at 4 of about 28 `run()` sites, and `run` turns a failure into `done(nil)` silently. **Remedy:** a private `move(to:)` with the legal moves in one place; fold `switchingTo`, `kept` conflict and `readOnlyReason` into the state where they belong; a check on a fake page with no WebKit. Medium.

#### 6. Split room and the pane slide (U M, D H, A M): tighten

Opening a split takes room and closing gives it back. Lives in `splits.taken` (5 writes in `AppModel+Split.swift`), `needsReconcile`, `peek`, `resizeSettle`, `leftCollapsedProject` (8 writes), AppKit's own pane widths, and in the view `placed`, `isAnimatingPane`, `savedWidths`, `pendingCollapse`, `queuedCollapse`, `PaneMotion` (`PaneSplit.swift:188-198`).

- Two truths for "sidebar folded": `taken.foldedSidebar` and `leftCollapsedProject`.
- **Timers as states:** `applyRightWidthSoon(after: 0.35)` (`AppModel+Split.swift:221`, `:346`) waits out a slide rather than listening for its end, though `PaneMotion` already knows when slides end. 0.25 s resize settle (`:234`). `main.async` as "after the restore opens its project" (`:328`).
- **Incidents, recurring:** F-9, F-130, F-501, F-527, F-531, F-532.
- **Good already:** `SplitRoom.plan`, `PaneWidths.resized` and the slide's own request queue are pure or explicit, and checked.
- **Remedy:** the room as one enum (none, taking, held, restoring); replace 0.35 s with the slide's end. Medium.

### Modest

| # | Machine | States (inferred) | Where it lives | What goes wrong | Remedy |
|---|---|---|---|---|---|
| 7 | **Sheets, forms, overlays** | none; one form; a question; search, peek or idle list up | `SheetCenter.queue`, six form optionals (`AppModel.swift:352-366`), priority as an `if` chain (`Sheets.swift:20-26`), `sheetIsUp`; each key handler repeats `!sheetIsUp, !search.isOpen, !peekOpen, !idleOpen` (`PaneFocus.swift:67, 78, 93`) | Bug l. A new overlay missed in one list is a bug. Incidents F-51, F-54, F-62, F-84, F-132 | Tighten: one `overlay` enum; answers carry the question's id |
| 8 | **Selection and right pane** | Project, a group, a document, a web tab | `rightTab` (33 writes, a string as a sum type, `AppModel.swift:122`), `selectedFile` (27) kept in step by hand, `consoleTab` (34) | The pair can disagree. Incidents F-346, F-347 | Tighten: a `RightTab` enum; one `select` |
| 9 | **Live refresh** | idle, reading, dropped-and-rereading | `refreshing` (`AppModel.swift:423`, `:478`), `localChange` token, `RefreshPacer` | Bug p. F-135's flicker fixed by the token, which is sound | Tighten: a watchdog on `refreshing` |
| 10 | **Restore at launch** | not applied, applied, saving | `restoreApplied`, the file on disk, `lastRestoreSave`, `lastRestoreData` | Bug d. F-208, F-212, F-558 (saved Bools outvoted a new default), F-531 | Tighten: keep what couldn't be restored |
| 11 | **Chat feed loading** | loading first, live, loading earlier | `loading`, `history`, `historyStart`, `transcriptPos` (`ChatFeed.swift`); no token | Bug c. Four sources write `pendingRequest` with no precedence | Tighten |
| 12 | **The dictation run** | around the explicit `VoiceState` | `target`, `holding`, `heldSince`, `heldPhrases`, `documentBegun`, `generation` (8 bumps), `waiting` | 9 direct `state =` writes bypass `VoiceMachine.next` (`VoiceInput.swift:165, 402, 445, 471, 505, 539, 552, 587, 600`), and `finishedRun()` by hand on about 9 paths. `expireLine` compares by value (`:587`), so an old timer can clear a new, identical failure. F-452, F-519, F-536 | Tighten: route through the machine; the enum stays |
| 13 | **Repo busy** | idle, fetching, stepping | `RepoView.busy`, `repoRefreshing`, `repoChecked` | Bug h. `repoStep` doesn't check `busy`, so operations can overlap | Tighten: `busy` out of the snapshot |
| 14 | **Search modal and index** | closed, empty, searching, results, none, rebuilding | `SearchUI.phase` (9 writes) plus `stillSearching`, `generation`, `queryTask`, `isOpen`; `SearchService.running`, `engine` | Bugs e, f. No check touches `SearchUI`. Index "complete or stale" is derived from a table, which is sound | Tighten |
| 15 | **Word and deck viewer load** | loading, ready, failed | `state`, `loaded`, `pending`, `deadline`, `dormant`, `stamp`; `stale` written, never read (`DocxViewer.swift:169`) | Bug s. Deck's redraw queue and `RevisionGate` are the good pattern to copy | Tighten: a token per open |
| 16 | **Review delivery** | queued, sent, replying, replied, not delivered | Real enum (`AppModel+ReviewSend.swift:11`), `reviewSending` | Bug q. `sent` has no timeout, only the 14-day purge | Tighten, small |
| 17 | **Focus routing** | keyboard in console, editor, page, sidebar | `webFocus`, `editors.active`, `activePane`, AppKit's first responder; `keyboardInRightPane` ORs three | F-479, F-495 (⌘W ended the wrong thing), F-257, F-258. `activePane` falls back when hidden, which is good | Leave until 7 is done |
| 18 | **Browser tab** | deferred, loading, blocked, downloading, uploading | `blocked`, `deferred`, `running`, `active`, `pendingUpload` (`BrowserTabs.swift`) | `pendingUpload` doubles as the result of a 1 s timeout. F-299 | Leave |
| 19 | **Chat scroll follow** | following, detached | `followsBottom`, `followPending`, `follows` log (`ChatView.swift:122-234`) | The F-225 breaker detaches until a later scroll. F-157, F-160, F-225, F-226, F-540 | Leave: two states, and the recurrences were SwiftUI's, not the flags' |

### Small: leave

| # | Machine | Note |
|---|---|---|
| 20 | **Tool step status** (`ChatLog.swift:120`) | A real enum with no guard: a late hook can set a `.done` background agent back to `.running` (`ChatIngest.swift:157`). One guard if it ever shows |
| 21 | **Trust notice** (`AppModel+Trust.swift:6`) | Real enum plus an orthogonal `dismissed`. Fine |
| 22 | **Control socket** (`ControlServer.swift:39`) | Bug t. The endpoint and pid checks are good; F-606 and F-113 were isolation, since fixed |
| 23 | **Word conversion** (`AppModel+Convert`) | Four dictionaries keyed by tab; "task present" means running. Works |
| 24 | **Task title follow** (`TaskMenu.swift:136-164`) | `seen` is updated before the move, so a failed rename isn't retried. Small |

## Bugs this review turned up

F-627. Each is from reading the code at these lines; **none was run**. Severity is my read of what a user would see.

| | What the user would see | Where | Sev |
|---|---|---|---|
| a | **⌘W on a tab restored at launch doesn't close it.** The process ends, the tab stays and comes back parked, and it's resumed next launch. The tab's own Close and `duo2 session close` remove it. Two close paths, one writer missing | `AppModel.swift:647-656` lacks `parkedTabs.remove`; `AppModel+Control.swift:1516` has it. Nothing clears `parkedTabs` on wake (`:1509-1513`), and `tabSessions` keeps the tab (`AppModel.swift:318`); saved at `AppModel+Restore.swift:83` | M |
| b | **`/clear` drops Keep Running and moves the tab.** The id changes; `keepRunningIDs` and `consoleTabOrder` aren't rekeyed, so the pin is lost and a hand-placed tab goes to the end | `AppModel.swift:631-636`; `AppModel+Park.swift:15`; `AppModel+TabOrder.swift:15` | M |
| c | **Earlier turns makes newer turns vanish.** Live turns aren't in `history`, and the reload replaces the whole list. Filed 2026-10-12 as bug 6 of the codebase review; still there | `ChatFeed.swift:74`, `:97`, `:103`, `:190`; `ChatLog.swift:242` | H |
| d | **A document tab can be forgotten for good.** If its file can't be seen at launch (a drive not mounted, iCloud not downloaded), restore skips it and the next save overwrites the file without it | `AppModel+Restore.swift:131-136`, `:145`, `:93-97`, `:118` | M |
| e | **Search can answer after it closed.** Close and reopen within a query's time, and the old results land under an empty field. `closeSearch` and `reset` don't change `generation` | `AppModel+Search.swift:28-33`, `:182`; `SearchModel.swift:216-220` | L |
| f | **Rebuild Index can stick.** `.rebuilding` stays until a keystroke; a pass in flight reinstalls the old engine over the rebuild | `AppModel+Search.swift:395-399`; `SearchService.swift:60`, `:69-73` | L |
| g | **One command can block every later move.** `migrate undo` on a delete marks it `.reverting`, then refuses; `interrupted()` then blocks all migrations. I found no way out | `Migrator.swift:354-356`, `:84`, `:259`; `AppModel+Migrate.swift:57` | M |
| h | **"Getting the latest…" can vanish mid-merge.** A refresh already reading lands with the old `busy`. A forced refresh during one returns at once, so `done` sees pre-step state | `AppModel+Repo.swift:15`, `:19`, `:27`, `:45`, `:86` | L |
| i | **A document remembered in Source opens in preview on launch.** `pending` runs `show` before `sendSourceModes` on the first page load | `DocumentEditor.swift:200-201`, `:371`; `duo-editor.js:2122`, `:2660` | L |
| j | **A second Return during a send may type twice.** `send` has no `guard !sending`; `openPicker` and `attachClipboardImage` do. The composer isn't cleared until after Return | `ChatSend.swift:33-44`, `:55`, `:161`; `ChatPaste.swift:141`; `ChatComposerView.swift:385-389`, `:708` | M |
| k | **Words can leave the composer unseen.** Come back to chat during a carry, and the carry still finishes: composer emptied, `carried` set, and nothing fills it until the next toggle | `ChatCarry.swift:18-33`, `:67-70`, `:80-94` | M |
| l | **A double answer could answer the next question.** `answer` removes the queue's first without checking it's the question answered, then runs the old choice's action | `DuoQuestion.swift:151-154`, `:299-319` | M |
| m | **A keystroke can count as saved.** `markSaved` bases on the current buffer, not the bytes written. A few-millisecond window; heals on the next edit or on quit | `duo-editor.js:2665`; `DocumentEditor.swift:611` | L |
| n | **Back to Chat from a mismatch bar bounces at once.** `disagreeSince` isn't cleared, so the grace has already passed, though the comment promises one | `ChatSession.swift:565-570`, `:440` | L |
| o | **A stray re-evaluation.** `unknownTimer` is overwritten uncancelled | `ChatSession.swift:437` | L |
| p | **The session lists could freeze for good.** `refreshing` is reset only in `apply`; if the detached read hangs (F-28 says they can), no refresh ever runs again | `AppModel.swift:421-423`, `:478` | M |
| q | **The review send's in-flight guard opens early.** `reviewSending` is removed right after starting a send that finishes 0.35 s later. Safe only because the refresh is every 2 s | `AppModel+ReviewSend.swift:146-148`; `AppModel+DirectorSend.swift:158` | L |
| r | **An old 6 s timer clears a new, identical failure line.** | `VoiceInput.swift:587` | L |
| s | **A Word file can take the previous file's comments.** A late `ready` isn't tied to the open that asked | `DocxViewer.swift:166-176`, `:307-317` | L |
| t | **A dead `duo2` socket isn't noticed.** The handler ignores everything but `.ready` | `ControlServer.swift:39` | L |

## Already explicit, and done well

Leave these alone, and copy them.

- **`VoiceMachine.next`** (`VoiceLogic.swift:47`): a pure function; events that make no sense leave the state alone. Tested without a microphone (`VoiceChecks.swift:8-26`).
- **`Migrator`** (`Migrator.swift:31`): a journalled state enum, written ahead, each step saved, verified before commit. Its one gap is bug g.
- **`ParkCheck.why`** and `ParkPressure` (`Parking.swift`): pure, ordered, injectable.
- **`EditorController.phase` plus `generation`:** the worked example.
- **`SessionSelection`** (`SessionSelection.swift`): a value type with a private inside.
- **`PreviewPolicy`, `RevisionGate`** (`PreviewProvider.swift`): revision gates, with an origin enum to stop echo loops.
- **`RepoStatus`, `RepoLine`:** derived fresh, never stored: `merging` is `MERGE_HEAD` on disk.
- **Suggest Edits** (`critic.js:156-168`): the state is a line in the file, so it can't disagree with the buffer.
- **The search index's coverage table:** "complete" is computed, not remembered.
- **`scripts/gpu-lock.sh`:** a documented protocol on the filesystem, with its own check. It earned it: F-294, F-296, F-298, F-510.
- **`ChatSession.fallBack`, `noteTransition`:** one door, and a log of who came through it.

## Plan

**First three, in this order:**

1. **ENH-332: the small refusals batch (small: about 2 days of Sonnet).** Bugs a, b, c, d, g, j, k, l, p, each with a failing check first; the rest as they're passed. *Why first:* users see it at once, the risk is small, and it needs no design. It also proves the check style the next two lean on.
2. **ENH-333: one answer to "what state is this session in?" (medium: 3 to 4 days).** `TerminalLife` replaces the terminal's flags; a read-only `SessionLife` is derived from today's stores; deciders move onto it one at a time; one writer for parked; one rekey. *Why second:* it has the most incidents and everything reads it. It starts read-only, so it can land without behaviour changing. It should be done before a third thing grows on `tabSessions`.
3. **ENH-334: the chat surface and the prompt channel (medium to large: about 5 days, in two slices).** First the surface as a pure function with a fake clock; then one owner of the prompt. *Why third:* the most repeatedly patched, and every chat user feels it, but it's the riskiest, since it sits on Claude Code's screens. It's safer once the session under it holds still.

**Then, as they come up:** finish the editor (a `move(to:)`, a fake-page check; medium). Split room on events rather than 0.35 s (medium, next time it's touched). One overlay enum (small to medium). `RightTab` enum (medium). Route dictation through its machine (small).

**A house rule to consider** (small): two flags on one object that constrain each other become an enum; a new timer's comment names the event it stands in for. This is Geoff's call, and if he wants it, it goes in `CLAUDE.md`.

**Don't:** adopt a state-machine library or framework; rewrite in one go; touch the items in the done-well list; remove timers where Claude Code's screen gives no event (the 500 ms "unknown must persist" exists for a real reason, F-108), though those timers should still be named states.

**What it costs.** Explicit machines are more code at the start and a refactor can regress what works; chat especially has many small lessons encoded in those flags. A new state needs a decision, which is the point, but slows a quick fix. That's why the plan moves one machine at a time, read-only first, keeping each existing check green.

## Not confirmed

- **Sweep claims I re-read and dropped.** A question for a closed window doesn't block the queue: `model(for:)` falls back to the key window (`AppCore.swift:54`). `applyRestore` returning early for another root doesn't overwrite anything: the restore file is per root.
- **Read by a sweep, not by me:** "Look Again" leaving a tab `missingClaude`; `repointState` not rewriting restore paths after a project move; a nameless session's detached fork never reattaching; `deckApply` reverting typing made between pick and apply (`deck.js:355` has no base check, but I didn't trace the pick).
- **Dictation across a document switch.** The page's `dictating` isn't reset by `show`, but Swift routes phrases by target key; I didn't read that router, so I can't say a phrase lands in the wrong document.
- **Incident counts per surface** are a Sonnet reader's approximate tally over about 530 log entries. I checked the F-ns quoted here, not the tally.
- **Nothing was run,** so severity is judgement, and a real run may show a guard I missed.
