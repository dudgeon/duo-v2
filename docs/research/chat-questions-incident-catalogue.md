# Chat mode: AskUserQuestion / dialog incident catalogue

Source: `docs/plan/findings.md`, `docs/plan/concerns-and-questions.md`, `docs/design/decisions.md`, plus `docs/plan/spikes/chat-mode.md` where a finding points there. Worktree `chat-multi-question` at 096933e8, read 2026-11-19. Highest finding on this branch: F-752.

Conventions:
- "Field" means a person reported it from real use: Geoff's work Mac, Geoff's own Mac, or another user. "Test" means a build session's run, check or spike found it.
- "Removed cause" means the fix takes away the mechanism. "Instance" means it handles the case that was seen, or a listed set of cases, and leaves the general mechanism in place.
- Rows marked **(adj.)** are chat screen-read or send failures that are not dialogs. They are included because they share the same layers.
- Every layer assignment is my classification from the record's own wording. Primary layer first, secondary after "/".

---

## 1. Incident table (one row per distinct failure)

| # | Id(s) | Date | CLI version(s) | Where seen | Symptom the user saw | Root cause (plain) | Layer | Fix | Removed cause or instance? |
|---|---|---|---|---|---|---|---|---|---|
| 1 | F-104 | 2026-10-06 | 2.1.291 | Test (spike, mock API) | Input desyncs: after Esc Esc the TUI kept `/mod` and the next paste became `/modSCENARIO:long`; "a digit sent after a dialog closed lands in the prompt (`2SCENARIO:plan`)" | Keys sent to the TUI on the assumption of a screen state that had already changed | KEY-INJECTION / TIMING | Design rule: "paste only into an input that's empty…, check the echo, and re-check a dialog's signature right before sending its keys" | Removed (a guard on every send). It became the basis of the refusal rules |
| 2 | F-105 | 2026-10-06 | 2.1.291 | Test (spike, real login) | "every screen read as unknown" in a named session | A named session writes its name into the input box's top rule, so the rule pattern failed | SCREEN-READ | Pattern fixed in `screen.mjs`, then in the Swift port (F-108 lists "the named-session rule") | Removed |
| 3 | F-105, C-27, F-98 | 2026-10-06 | 2.1.291 | Test (spike, real login) | The reply "never got its end" (2 bad lines) | Hooks that fire together appended through `sh` + `printf` in pieces, so lines merged and the reader skipped them. "Duo's own hook command… has the same weakness" | HOOK-DELIVERY | One `syswrite` per event with O_APPEND (perl). DuoChecks fires 40 concurrent ~1 KB events (C-27) | Removed. F-419 still lists "A lost `PermissionRequest` line (two hooks writing at once, C-27)" as a path it guards against |
| 4 | F-105, F-208, DL-154 | 2026-10-06 | 2.1.291 | Test (spike) | Screen "blank for a moment at start and while the external editor runs, and reads as unknown" | Transient blank frames | TIMING | 500 ms wait for unknown to persist (F-105, F-108). Later "A blank screen reads as starting, so a session loading never falls back" (F-208, DL-154) | Removed for blank screens. Other short unknown moments still fall back (row 27) |
| 5 | F-105, F-444, F-445, Q-338 | Spike 2026-10-06; field 2026-10-30 | 2.1.291 (spike); 2.1.284, 2.1.311 measured (F-445); the field run's version is not stated | Spike test, then field (Geoff, a dev Duo on a new folder `~/VoiceTest`) | The first chat in a new folder went to the terminal. Geoff: "pretty big fail if the very first time a user sees the home chat it has a chat mode failure because of the trust dialogue" | The trust prompt had no signature, so it read as unknown | SCREEN-READ / POLICY | The reader reads it as kind `trust`. It never falls back: Duo's sheet asks, then answers with ↓ and Return after re-reading the screen. Another folder's question → `trust-other-folder`; an unreadable CLI → `trust-unreadable` | Removed for this screen |
| 6 | F-106 | 2026-10-06 | 2.1.291 | Test (spike PoC) | Other on multi-select typed a stray space | The PoC sent Space after Other on multi-select. Space edits the free-text row | KEY-INJECTION | Fixed in the PoC | Removed |
| 7 | F-106 | 2026-10-06 | 2.1.291 | Test (spike) | In short or narrow terminals "a long question scrolls its top (and the tab strip) off screen; labels wrap, so the screen shows only their start" | A narrow or short PTY | GEOMETRY | Matcher rule: "take text from the request and structure from the screen. A question matches if the visible text is the end of exactly one asked question and every visible label is the start of the asked label at that position" | Handled by rule. Proved only at 100×34, 60×34 and 80×20; later found to break at 38–43 columns (row 34) |
| 8 | F-103, F-106 | 2026-10-06 | 2.1.291 | Test (spike) | (No visible failure.) A declined question and "Chat about this" fire no hook, not even `Stop` | The CLI sends no Post or Denied hook for a refusal | HOOK-DELIVERY (absent) | Only the transcript's `tool_result` (`toolDenialKind: user-rejected`) records it, and chat reads that | Worked around (a second source) |
| 9 | F-110 | 2026-10-06 | 2.1.291 | Test (chat-live) | "every question was refused as 'not the one Claude asked'"; "nothing was ever sent wrongly" | A raw SwiftTerm buffer holds NULs where the TUI moved the cursor. The view's text converts them; the raw buffer didn't | SCREEN-READ | NUL is read as a space | Removed |
| 10 | F-175, F-176, C-49, DL-145, DL-155 | 2026-10-07 | 2.1.292, 2.1.293 | Geoff's CLI on this Mac; found during a build's live run (F-176) | "every permission, plan and question went to the terminal" ("Chat mode hasn't been checked with this version…") | The CLI auto-updated past the hand-kept `verified` list (fallback rule 3) | VERSION-DRIFT / POLICY | First, versions added to the list (instance). Then DL-145: a newer version is trusted "while its screens match". DL-155: any 2.1.x the same way | Removed (the policy changed, so an update needs no Duo release). The cost is that every version now depends on `wellFormed` (rows 15, 16) |
| 11 | F-208, F-292, DL-154 | 2026-10-07 (0.2.5) | 2.1.2xx (work Mac's pinned version; the stand-in TUI reports 2.1.219) | Field (Geoff's work Mac: `sample`, "Recent hangs: 25") | 100% CPU at launch, a 3.1 GB footprint, hangs | Sign-in and MCP OAuth screens read unknown, then prompt, then unknown, so 12–24 chats fell back and came back "many times a second". Each flip re-laid out the whole window | POLICY (auto-return) / OTHER (layout cost) | DL-154: a fallback is sticky until Back to Chat. Layout fixes (PaneSplit, slot sizing, ChatHug, `setVersion`) | Removed the flip loop, by making every automatic fallback permanent for the conversation. That is the source of row 27 |
| 12 | F-173 | 2026-10-07 | 2.1.292 | Test (real login, isolated Duo) | "`chat-state` read the question card as up, but the capture 1.5 s later showed the composer, not the docked card." Seen once, not reproduced | Not stated | not stated | None | Unknown. The symptom matches F-328's mechanism (row 25), but no record links the two |
| 13 | F-174 | 2026-10-07 | 2.1.292 | Test | A command screen (`/help`, `/sandbox`) left chat blank, with the session showing "needs you" | Fallback rules were skipped while `sending`/`composing`, and nothing re-judged a still screen afterwards | TIMING | Clearing either flag runs the rules (`didSet`) | Removed |
| 14 | F-174 | 2026-10-07 | 2.1.292 | Test | After `/clear`, the next message from the composer opened vim in the terminal | The hand-over was named by the session's new id. The helper looks under the launch id | OTHER (session identity) | `ChatSession.launchId` names every hand-over, peek and refusal file | Removed. Related to row 40: after `/clear`, hook events also move to a new id |
| 15 | F-243, F-246, F-247 | 2026-10-08 | 2.1.295; 2.1.219 | Field report (Geoff: "askUserQuestions force-trigger terminal mode"; machine not stated), reproduced here | AskUserQuestion went to the terminal: "This dialog in Claude Code <v> doesn't read like the versions chat mode was checked with". Sticky | An option description line starting "N. " (e.g. `3. Third-party …`, or 2.1.219 drawing `1. install it` on its own line) was parsed as an extra option, so the numbering broke and `wellFormed` failed | SCREEN-READ | `isOptionRow`: a numbered line is an option only if it is the next number and sits at the option column | Removed for questions. C-72: permission, plan and review rows (`options()`) still take every numbered line (open, Low) |
| 16 | F-243, Q-160, DL-164, F-248 | 2026-10-08 to 09 | 2.1.291–2.1.293 | Read from code (not run) | Would have been a **wrong answer**, not a fallback: "the extra rows are answered by their number" | Verified versions skipped the `wellFormed` gate | POLICY | DL-164: check `wellFormed` on every version | Removed (fails safe to the terminal) |
| 17 | F-244, F-246 | 2026-10-08 | 2.1.295 | Test ("Found by accident") | "Chat mode can't show this screen", and "A question that follows such a Read is stuck behind it" | A new permission title, "Allow this read outside the working directories?", didn't match `^\s*Do you want to .*\?` | VERSION-DRIFT / SCREEN-READ | Title pattern widened to `(Do you want to\|Allow\|Trust\|Would you like to)`, with each title in the 2.1.295 binary checked | Instance (an enumerated set). "A dialog whose title starts another way still reads unknown and falls back" |
| 18 | F-245 | 2026-10-08 | 2.1.295 | Test | No scenario ran in Duo | The mock read `SCENARIO:` from the last message, but Duo's hooks append a reminder block after it | TEST-GAP | The mock reads the latest prompt | Removed (in the test) |
| 19 | F-254 | 2026-10-09 | 2.1.219, 2.1.295 | Field (Geoff: "was rejected: message was not sent"; machine not stated) | A send fell to the terminal with "Chat mode didn't send your answer" (paste path), or was sent silently without the drafted task path (Ctrl+G path) | Words in Claude's prompt that the composer hadn't shown (a drafted `@tasks/…`) made the paste guard refuse, or the hand-over replaced them | KEY-INJECTION **(adj.)** | Unseen words are carried ahead of the text. The echo check expects `carried + words` | Removed for drafts. C-75: a dim suggestion could be carried on paste CLIs (row 22) |
| 20 | F-273 | 2026-10-09 | 2.1.296 (2.1.284+ behaviour) | Test (chat-live) | 4 chat-live failures; the dialogs "never appearing" | Auto mode is the default since 2.1.284, so no Bash or edit dialog appears. A `system` last message confused the mock. A prompt was merged into the refused tool result after an interrupt | TEST-GAP / VERSION-DRIFT | The suite cycles to manual mode; the mock fixed | Removed (in the test). The AskUserQuestion cases now run in auto mode |
| 21 | F-274 | 2026-10-09 | 2.1.219 | Test (chat-live against the work Mac's version) | **Wrong answer**: "Claude got `(no option selected) notes: keep it short` where you chose 'Side by side'" | Return inside the notes field sends the notes with no option on 2.1.219 | KEY-INJECTION / VERSION-DRIFT | `.notes`: press Esc, re-read (notes kept, cursor on the option, or refuse), then Return | Removed for that intent |
| 22 | F-303, F-112, C-75 | 2026-10-12 | 2.1.219 (paste path); 2.1.296 unaffected (Ctrl+G peek) | Test (duo-signal spike's scripted runs) | "didn't send your answer". The AskUserQuestion that followed "never came, so its answer fell back too ('the terminal shows idle, not a question')" | A dim prompt suggestion reads as typed text, because SwiftTerm gives no cell attributes (F-108). The paste then broke the echo check | SCREEN-READ / KEY-INJECTION | `promptIsSuggestion()`: type a space, re-read, Backspace | Workaround probe (keys sent to tell dim from typed). The underlying limit (no cell attributes, F-108) is unchanged |
| 23 | F-297 | 2026-10-12 | 2.1.296 | Test (duo-signal mod spike) | A `tool.check` mod hook that waited held the Bash dialog back 10 s. The engine then "**rejected the next AskUserQuestion** ('The user doesn't want to proceed')" | A slow hook at a gating site; the hooks worker was replaced | OTHER (mod hook) | The mod's hooks hold no I/O and no waits (a DuoChecks scan). The mod ships off by default (not shipped) | Removed for the spike's mod |
| 24 | F-311, ENH-145 | not stated (Q-192; ENH-145 logged 2026-10-14) | 2.1.219 | Test (measured) | With `disableAllHooks`, the card says only "Waiting for your answer"; chat mode needs SessionStart | Claude Code runs none of Duo's hooks, so the question's words and options (from PermissionRequest) are absent | HOOK-DELIVERY (absent) | None then. Later F-749 names it (`hooks-off`) | Not fixed. Q-599 recommends keeping the terminal |
| 25 | F-328, F-329 | 2026-10-17 (0.2.16, build 891) | 2.1.302 | Field (Geoff's Mac, the "Shop triage skill" session) | The question "appears as a no op". Flipping to the terminal and back showed the card. Before the fix, 7 of 10 live runs drew the card | `pendingRequest` was `@ObservationIgnored`. The screen (read 60 ms after a draw) usually lands before the hook (feed every 150 ms), and a waiting TUI doesn't repaint, so SwiftUI was never told | TIMING (race between sources) / OTHER (UI observation) | `pendingRequest` is observed. Proof: 10 of 10 on 2.1.302 and on 2.1.219 | Removed. "The chat checks and chat-live read `cardUp` directly", so they had missed it (TEST-GAP) |
| 26 | C-93 | 2026-10-17 | 2.1.302 | Test (chat-live) | chat-live fails 9 of 48: Ctrl+G cases, paste-on-send, a busy send, the "Switch model?" card | Not investigated. Possibly the sandboxed environment ("may be that environment") | not stated | None. Status "open" | Unknown |
| 27 | F-376, F-435, Q-328, DL-258 | 2026-10-28 | 2.1.219 | Field (Geoff's work Mac, two photos) | "Chat mode can't show this screen" bar over an ordinary idle prompt | The bar is sticky (DL-154). "one `unknown` moment longer than 0.5 s earlier in the conversation… leaves the bar over everything after." The fixture of the photographed screen reads idle. "the moment that triggered it isn't on screen" | POLICY (sticky) / SCREEN-READ (trigger unknown) | Diagnostics only: the report now carries the last 12 verdict changes and the current screen. Q-328 (auto-return short unknowns) was rejected by DL-258: "prevent the unknown screens instead" | Neither. The triggering screen is not identified. F-435 ranks `unknown-screen` the likeliest rule |
| 28 | F-419, Q-326, Q-327, DL-258 | 2026-10-29 (Duo 0.2.21 (1117)) | 2.1.284 (trust `newer`) | Field (Geoff's work Mac, photo) | "Can't match this dialog to what Claude asked" (`dialog-request-mismatch`) on a long question at 60 columns, right after an answered question; "request pending: none" | The feed hadn't read the request when the 1.5 s grace ran out. Four candidate paths: grace timer before feed timer after a stall (off-screen feed every 2 s); no hooks read while the transcript loads; the 256 KB attach window losing the turn's prompt; a lost PermissionRequest line | HOOK-DELIVERY / TIMING | `ChatFeed.catchUp` at grace; `peekRequest` during load and `loadingGrace` up to 15 s; keep an unanswered PermissionRequest in the window; PreToolUse also sets the request. The report gained a `hooks:` line | Instance. All four candidate paths are guarded, but "Which of the four paths hit Geoff isn't in the photo" |
| 29 | F-420 | 2026-10-29 | 2.1.284 | Field (Geoff's work Mac) | A skill (`/ask-data`) missing from chat's `/` menu | The mirror read a stale prompt while typing fast, so its edits stacked (`///ask-data`) | TIMING / KEY-INJECTION **(adj.)** | One mirror at a time, sending only the differing tail and waiting for the echo | Removed |
| 30 | F-437, Q-329 | 2026-10-30 | 2.1.284, 2.1.311, 2.1.296 inline | Test | (Would have been) a turn read as ended mid-turn while the `/` menu was up | Every renderer hides the busy marker under the `/` menu | SCREEN-READ **(adj.)** | Guard in `apply`: busy followed by idle with the menu up stays busy | Removed |
| 31 | F-449, F-456, Q-341 | 2026-10-30 | 2.1.311 | Field (Geoff's Debug report, Duo Dev voice test) | Two fallbacks in one second: `answer-refused` ("Claude's prompt changed in the terminal (it holds "")"), then `unknown-screen` | (1) The hand-over expected words, but the prompt had been emptied. (2) The hidden terminal kept its last on-screen size (87 columns). Switching to the 42-column pane narrowed it, and the alternate screen kept stale cells past the new width, so only one rule was found and the reader saw no input box | KEY-INJECTION / GEOMETRY | (1) A refusal over an empty prompt is handed over once more. (2) `ChatScreenReader.clip` clips rows to the width. F-456: the hidden view is sized to the chat pane (`holdHiddenSize`) | Removed for both mechanisms. Clipping "stays as the backstop" |
| 32 | F-539 | 2026-11-02 | 2.1.284, 2.1.316 | Field (Geoff's work Mac) | Chat looked idle through a long turn while the terminal showed the spinner | At 48 columns the footer is cut to `· esc …`, and busy came only from `esc to interrupt` | GEOMETRY / SCREEN-READ **(adj.)** | `spinnerActive` signature (a verb ending in `…`) | Removed. A rule over 179 captured screens checks it |
| 33 | F-640 (part 1) | 2026-11-10 | not stated for the report; 2.1.316 for the proof | Field (Oliver, through Geoff) | After a fallback on a question: a black, empty terminal; Back to Chat came straight back to it | Home's two terminal slots: the slot updated last took the view, even when out of sight | OTHER (view ownership) | `SlotView.takes`: only the slot on screen takes the view | Removed. The rule that fired for Oliver is "Not known" |
| 34 | F-640 (part 3), C-178, F-648, Q-488, DL-336, F-650 | 2026-11-10 to 11 | 2.1.316 | Test (chat-live at Home column sizes); prompted by Oliver's report and Geoff ("routinely fail") | Questions refused on answering, then the terminal: "the options on screen differ from what Claude asked" / "the question on screen is not the one Claude asked". At 43×49: 2 of 17 (both previews). At 38×49: 4 of 17 (also four questions, long wrapped labels) | The hidden terminal was held at the chat pane's width (F-456), so Claude drew questions at 38–43 columns, where the matcher fails | GEOMETRY / SCREEN-READ | F-650: the hidden view is held at `max(pane, heldMinColumns = 60)` columns (Q-488 (a), DL-336). 60×49 measured 17 of 17 (F-648) | Instance-by-avoidance. The matcher still fails narrow layouts. Q-488's row still reads "Not built" and says "consoles narrower than 60 columns remain (narrow windows, split view)", while F-650 says it was built. The records conflict |
| 35 | F-641 | 2026-11-10 | 2.1.316 | Test (`check-chat-narrow-live.sh`) | A question drawn at 43 columns was shown at 38, with a redraw at each switch | `applyHeldSize` didn't take off the mic margin (DL-264) | GEOMETRY | F-650 takes the margin off | Removed |
| 36 | F-648, F-650 | 2026-11-10 | stub | Test | Home's `claude` ran unseen in a closed column. "a trust question… sits in a closed pane" | Home session started at launch (DL-54) with its column closed (DL-315) | OTHER | DL-336: no Home session at launch | Removed |
| 37 | F-646 | 2026-11-10 | 2.1.316 | Test (live check) | A session sat on the first-run theme screen (chat-fallback dump shows it) | `CLAUDE_CONFIG_DIR=~/.claude` made Claude read `~/.claude/.claude.json` and start as a new install | OTHER | Drop `CLAUDE_CONFIG_DIR` when it names `~/.claude` | Removed |
| 38 | F-689, F-690, F-688, F-717, DL-344, F-731 | 2026-11-13 to 15 | 2.1.284, 2.1.323 | Not stated ("The 'unknown screen on 2.1.323' this week is the `/btw` panel", F-731) | `/btw` sent chat to the terminal ("/btw opens in Claude Code's own screen…") | The panel has no `─`-ruled input box, so it read unknown, then fell back after 0.5 s (`/btw` was on `terminalCommands`) | SCREEN-READ / POLICY | `ChatScreen.Kind.side`, mapped back to busy or idle underneath; no fallback | Removed for `/btw`. "Not checked: 60 columns and 2.1.219" |
| 39 | F-731, Q-587 | 2026-11-16 | 2.1.323, 2.1.325 | Test (mock gateway) | Full-screen notice "Auto mode can't check actions in this session" → terminal | The screen has no input box and no card. Appears "only when the server-side check isn't reachable (a gateway)" | POLICY (designed) / VERSION-DRIFT | None: "the designed behaviour for a screen chat has no card for". Q-587 open | Not fixed (by design) |
| 40 | F-749, F-750, Q-598, Q-599 | 2026-11-17 (Duo 0.2.30 (1815)) | 2.1.284 (field); reproduced on 2.1.284 and 2.1.325 | Field (Geoff's work Mac, photo, 65 × 94) | `dialog-request-mismatch` on a tabbed four-question AskUserQuestion (Audience, Form, Subject, Scope, Submit): "request pending: none, hooks: no event read yet" | Nothing reached the events file chat reads. Either Claude Code ran none of Duo's hooks (`disableAllHooks`, or managed `allowManagedHooksOnly`; Geoff: "this is a managed setting we don't control"), or `/clear`/`/resume` sent events to another session's file before Duo re-keyed the tab. Which one is unknown (Q-598). The transcript can't stand in: the `tool_use` lands only after the answer | HOOK-DELIVERY | When the grace runs out with no request, chat searches events files from the last two minutes for an unanswered AskUserQuestion in the same `cwd` containing the on-screen question. New rules `hooks-silent` and `hooks-off` (via `HookPolicy` reading managed sources except the policy helper) | Instance. The moved case is now handled; the hooks-off case still goes to the terminal, now with a named reason. Q-599 (screen-only card) is open, recommended "no" |
| 41 | F-751 | 2026-11-17 | 2.1.284, 2.1.325 | Test (load average ~11) | "couldn't reach 'Customers'" (2 of 5 runs) | Arrows 120 ms apart. A slow repaint left the screen unchanged, so the next arrow went from a stale cursor and landed on "Chat about this" | TIMING / KEY-INJECTION | Each arrow waits up to about a second more for the cursor to move | Instance (a longer bound). "one refusal was seen once more before it, under the same load, and none since" |

Not incidents, but relevant context:
- F-435 ranks the rules, from likeliest: `unknown-screen`; `dialog-request-mismatch`; `dialog-unreadable`; then `command-screen`, `answer-refused` and `handover`; then `version-unverified` and `picker-unverified-version`.
- F-731: 2.1.323 adds a fourth Bash option ("Yes, and switch to auto mode"), so No becomes 4. It reads fine because labels and numbers come from the screen.
- F-245: `duo2 session chat answer` takes a number, so "a multi-select can be ticked but not submitted, and 'Other' text can't be typed". Those cases run only headless.
- F-375 and F-752: the Debug report and the fallback log.

---

## 2. Counts

Primary layer per row (41 rows):

| Layer | Rows | Count |
|---|---|---|
| SCREEN-READ | 2, 5, 9, 15, 22, 30, 38 | 7 |
| VERSION-DRIFT | 10, 17 | 2 |
| HOOK-DELIVERY | 3, 8, 24, 28, 40 | 5 |
| TIMING | 4, 13, 25, 29, 41 | 5 |
| KEY-INJECTION | 1, 6, 19, 21, 31 | 5 |
| GEOMETRY | 7, 32, 34, 35 | 4 |
| POLICY | 11, 16, 27, 39 | 4 |
| TEST-GAP | 18, 20 | 2 |
| OTHER | 14, 23, 33, 36, 37 | 5 |
| not stated | 12, 26 | 2 |

Counting secondary layers too (each row counted once per layer it names):

| Layer | Count |
|---|---|
| SCREEN-READ | 13 |
| VERSION-DRIFT | 6 |
| HOOK-DELIVERY | 5 |
| TIMING | 7 |
| KEY-INJECTION | 9 |
| GEOMETRY | 6 |
| POLICY | 7 |
| TEST-GAP | 3 (rows 18, 20, plus F-328's checks reading `cardUp` directly) |
| OTHER | 7 |

Field vs. found by test:
- **Field reports: 13 rows**, namely 5 (Geoff dev Duo), 11, 15, 19, 25, 27, 28, 29, 31, 32, 33, 40, and 10 (Geoff's CLI on this Mac, found by a session).
  - Geoff's work Mac: rows 11, 27, 28, 29, 32, 40 (6).
  - Geoff's own Mac or a dev Duo: rows 5, 10, 25, 31 (4).
  - Machine not stated: rows 15, 19 (2).
  - Another user (Oliver): row 33 (1).
- **Found by test, spike or code reading: 27 rows.**
- **Source not stated: 1 row** (row 38's 2.1.323 "unknown screen this week").
- Field reports that are dialog/question fallbacks: rows 5, 15, 25, 27, 28, 31, 33, 40. Of these, **the root cause was proved for 5, 15, 25 and 31.** Rows 27, 28, 33 and 40 each end with the triggering cause not identified ("isn't on screen", "isn't in the photo", "Not known", Q-598).

---

## 3. The architecture as the findings describe it

### 3a. Sources chat depends on to show and answer one AskUserQuestion

1. **The TUI screen**, through SwiftTerm.
   - `visibleRowsText` gives text only, no cell attributes such as dim or colour (F-108).
   - Read 60 ms after the last output batch (`setProcessOutputHandler`) (F-108). Only the shown tab is read (`chatIsShown`, F-245).
   - Off-screen chats are dormant: `ChatFeed.tick` runs "one tick in 13 (every ~2 s)", and `wake()` catches up within 0.15 s (F-211).
   - Rows are clipped to the terminal width (F-449); NUL is read as space (F-110).
   - Signatures are per version, in `ChatSignatures`. The question signature is "Enter to select ·" with a ☐/☒ tab strip; the review page is "Review your answers" + "Ready to submit your answers?" (F-104).
2. **Hook events** from a per-session `--settings` file. Each event is one perl `syswrite` into `events/<id>.jsonl`, and the hooks print nothing (F-26, F-111, C-27).
   - The request comes from `PermissionRequest` (full `tool_input`, no `tool_use_id`) or, since F-419, from `PreToolUse` too.
   - Measured order: PreToolUse → PermissionRequest 13–45 ms apart (F-419); 31 ms in F-328's field log. `Notification` fires about 6 s later (F-103, F-328).
   - The feed reads hooks every 150 ms on screen (F-328) and every 2 s off screen (F-419, ENH-45).
   - At attach it reads the last 256 KB and replays from the turn's `UserPromptSubmit`; an unanswered PermissionRequest in the window is kept (F-419).
   - Chat hook names are gated on 2.1.152+ (F-111).
3. **Events files of other sessions**, for the F-749 lookup: "written in the last two minutes", same `cwd`, unanswered, containing the on-screen question.
4. **The transcript.**
   - History, and declines: `toolDenialKind: user-rejected` (F-106).
   - It is not a source for a pending question: "the question's `tool_use`… reach[es] the transcript only after the question is answered" (F-749).
5. **The CLI version**, from `claude --version` once per binary (F-108). Trust is verified, newer or unverified (F-176); any 2.1.x is trusted while `wellFormed` (DL-155, DL-164).
6. **The beacon** `sessions/<pid>.json`, to re-key a tab after `/clear` or `/resume` (`followSessionChanges`, F-29, F-750).
7. **Managed and user settings**, read by `HookPolicy` to name `hooks-off` (F-749). It reads the managed-settings file, the `managed-settings.d/*.json` drop-ins, the two MDM plists and `remote-settings.json`, but not the policy helper.
8. **SwiftUI observation** of `pendingRequest` and `cardUp` (F-328).
9. **Optional duo-signal mod.** It is off by default and not shipped. While fresh (under 1.5 s), it can set the request ahead of the hook (F-297).
10. **The hidden terminal's size.** It is held at `max(pane, 60)` columns while chat shows (F-650), and resized only after the pane keeps a size for 0.25 s (F-456).

### 3b. Conditions that must hold

To show the card:
- The CLI is 2.1.x (DL-155).
- The screen reads as kind `question`.
- It is `wellFormed`: "options numbered 1…n, one cursor row, a title or question" (F-176). The options must also pass F-246's next-number and option-column rule.
- A pending request exists and agrees (`requestAgrees`; `cardUp`, F-328).
- `questionIndex` matches: "the visible text is the end of exactly one asked question and every visible label is the start of the asked label at that position" (F-106). The current tab is shown "only by colour, so the current question is found by matching the screen's question text to the request" (F-106).
- SwiftUI is told when the request lands (F-328).
- The chat is the shown tab (F-245).

To answer:
- "The server checks the question and options against the pending `PermissionRequest`" (F-106).
- The same signature is re-read "right before the key" (F-104, F-110).
- The cursor moves "one arrow at a time, re-reading the cursor row" (F-106), 120 ms apart, with each arrow waiting "up to about a second more, until the cursor has moved" (F-751).
- "Any surprise refuses and falls back. A stale card is refused with no key sent" (F-106).
- Key specifics:
  - A digit picks and submits a single question (F-106).
  - Multi-select ends on Next/Submit and the review page (F-106).
  - Notes are entered with Esc, a re-read, then Return (F-274).
  - An option that takes text is refused through `duo2` (F-110).

### 3c. Fallback rules (names from F-375, F-444, F-749)

| Rule | Trigger | Timer / constant | Returns by itself? |
|---|---|---|---|
| `unknown-screen` | A screen chat can't name | "unknown for 500 ms" (F-108); "`grace` 0.5 s (`ChatSession.swift:272`)" (F-689). A blank screen counts as starting and never falls back (DL-154) | No (DL-154, DL-258) |
| `command-screen` | A named command's own screen (F-173) | Same grace | Yes, when it closes (DL-154; F-435 "they come back by themselves") |
| `dialog-unreadable` | A dialog that isn't `wellFormed` on any 2.1.x | At screen read | No |
| `version-unverified` | CLI not 2.1.x | — | No |
| `dialog-request-mismatch` | The hook's request doesn't agree with the screen | "1.5 s request-grace" (F-328, F-640). At grace, `ChatFeed.catchUp` reads hooks first (F-419). `loadingGrace` waits "up to 15 s" while the transcript loads (F-419). The moved-hooks lookup covers events files "written in the last two minutes" (F-749) | No (Q-326 rejected, DL-258) |
| `hooks-silent` | No hook ever read from the session and none found by lookup | At the request grace (F-749) | No |
| `hooks-off` | As above, and a setting turns hooks off (`disableAllHooks`, `allowManagedHooksOnly`) | Same | No |
| `picker-unverified-version` | A picker on an unverified version | — | No |
| `answer-refused` | "the screen and the request differ when you pick". Bar: "Chat mode didn't send your answer" (F-640) | At answer | Yes (F-435: "chat chose these… they come back by themselves") |
| `handover` | Amend in Terminal… | — | Yes (F-108, DL-154) |
| `trust-other-folder`, `trust-unreadable` | Trust question for another folder, or a CLI chat can't trust | — | not stated |

Other constants:
- Fallback log `logs/chat-fallbacks.jsonl`, capped at 256 KB, automatic fallbacks only (F-375). Each line holds a hash and the 8 rows nearest the verdict (DL-234).
- The Debug report carries a 40-entry transition list (F-375) and the last 12 verdict changes (F-376).
- Hook cost 5.5 ms median (F-111).
- duo-signal's timer is 100 ms, with a heartbeat every 500 ms (F-297).

---

## 4. Stated reasons for the current design

- **An overlay on the real TUI, never a replacement.** DL-118 (1): "it is **not** a headless, `-p` or SDK re-implementation."
- **Answers go back as keys, and chat never answers on the user's behalf.** DL-118 (2): it "**never circumvents human review**: permission prompts, plan approval, AskUserQuestion and confirmations stay the human's choice… their answers go back as keys to the real TUI; chat mode never answers, skips or pre-selects them."
- **Automatic fallback.** DL-118 (3): "Duo **falls back automatically** for any interaction chat mode can't reproduce faithfully; AskUserQuestion is to be tried hard before it falls back."
- **Hooks must print nothing and never decide.**
  - F-26: "They print nothing, so they can't answer a prompt."
  - Spike `chat-mode.md`: "Hooks only append to a file, so Duo never answers: the hook-decision route (`PermissionRequest` returning allow/deny) would *replace* the TUI's dialog, which DL-118 rules out." Hooks are "All observe-only."
  - F-103: MessageDisplay "can also transform or hide displayed text, so Duo's hook must keep printing nothing."
- **Exceptions in the records** (hooks that do output or decide):
  - `duo2 hook context` returns `additionalContext` at SessionStart and UserPromptSubmit (DL-116, F-111). It "always exits 0" because "Exit 2 from a UserPromptSubmit hook blocks the prompt" (F-98).
  - The pre-edit hook can deny Edit and Write; after F-290 it "denies only on a clear yes."
- **Why labels and structure come from the screen.**
  - F-104: "The cards use the **screen's verbatim option labels**: they vary by tool and setting."
  - F-105: `permission_suggestions` said `destination: session` while the TUI said "… from this project", which "confirms card labels must come from the screen."
  - F-106: "take text from the request and structure from the screen."
  - DL-119 (3): "Labels are Claude Code's own, read from its screen… nothing is pre-selected."
- **Why the request is required as well as the screen.**
  - Q-599: building from the screen alone would mean "DL-118's check that the screen agrees with Claude's request would be gone".
  - Q-327: a screen-only card "would lose multi-question tabs, previews and the review's full text, which come from the request."
- **Why fallbacks are sticky.**
  - DL-154 (after F-208's flip storm): "The terminal stays until you choose Back to Chat."
  - DL-258: "Chat-mode fallbacks are prevented, never papered over… The work is to find each fallback's cause and stop it happening."
- **Why `wellFormed` gates every version.** DL-164: "Answering a misread dialog by number picks the wrong answer silently; a fallback is visible and recoverable."
- **Why newer versions are trusted by their screens.** DL-145: "No Duo release is needed when Claude Code updates" (C-49).
- **Why the trust question is answered rather than predicted.** F-444: "Predicting them in Duo would either ask when Claude wouldn't, or miss a case… So Duo answers the screen."
- **Why only the CLI login is needed.** F-105: "Chat mode needs only the Claude Code CLI login. No API key, no SDK."

---

## 5. Alternatives already considered or ruled out

| Alternative | Verdict | Id |
|---|---|---|
| `-p`, `--output-format stream-json`, `--input-format`, Agent SDK, ACP | "Ruled out… They change how Claude runs and replace the TUI's review" | DL-118 alternatives; spike `chat-mode.md` "Ruled out"; F-103 prior art ("every rich chat GUI over Claude Code uses `-p`, stream-json or the SDK, which DL-118 rules out") |
| Prior-art GUIs: opcode, Crystal/Nimbalyst (`--permission-prompt-tool` MCP), VS Code panel (SDK `can_use_tool`), CloudCLI, Zed ACP, Vibe Kanban, Happy | Ruled out, or "Half" for Happy | Spike `chat-mode.md` prior-art table |
| Omnara v1 (PTY, JSONL tail, screen-scraped prompts) | "the closest precedent… then was dropped in a relaunch. A warning about upkeep" | F-103; spike |
| Hooks answering (`PermissionRequest` returning allow/deny) | Ruled out: it "would *replace* the TUI's dialog" | Spike `chat-mode.md`; F-26 |
| `permissionDecision: "defer"` | "requires non-interactive mode with the `-p` flag" and "is ignored in interactive sessions" | F-708 |
| Hooks as the director's only signal | "Hooks can only be a backstop", because hooks can be off (`hooks-off`, `pinned-219-strict`) | F-709 |
| Mods (`--plugin-dir`, 2.1.287+) | They load with no install; status lines push the footer (C-78); the session writes into the plugin folder, so Duo passes a copy | F-280 |
| duo-signal sensor mod | "works and fails safe, but buys little". The card comes up about 60 ms sooner (median 9 ms vs 72 ms); no busy lead; idle later; `SessionMode` never raised. "don't ship it now; keep the branch as the reference." Ship "if chat's screen reading breaks again in a way the footer search can't fix" | DL-183, F-297, ENH-70, Q-176, Q-189 |
| A mirror terminal fed from the PTY (for cell attributes) | "isn't needed, because the composer's truth is Ctrl+G's file" | F-108 |
| IDE bridge (websocket MCP) | "Not tried"; its protocol is undocumented | F-103; spike |
| Auto-return for short unknowns, or for a late request | Rejected | Q-328, Q-326, DL-258 |
| A card built from the screen alone when no request comes | "Not yet" | Q-327 |
| A card from the screen alone when hooks are off | Open, recommended "no" | Q-599 |
| Asking before starting in an untrusted folder | Rejected in favour of answering the screen | F-444 |
| Narrow panes: hold ≥60 columns, teach the matcher, or leave it | (a) chosen | Q-488, DL-336, F-650 |
| Growing hold (1–30 s) before returning from a fallback | "built, then replaced" by sticky | F-208, DL-154 |
| Transcript as the request source | Not possible: "chat has no request but the hooks'" | F-749 |
| Transcript or screen for state with hooks off (DL-199) | "not built"; ENH-145 | F-311 |
| `MessageDisplay` via `sh` + `perl` vs an `http` hook or helper | Suggested to measure; perl kept at 5.5 ms | Spike, F-111 |

---

## 6. Unknown, missing or inconsistent in the records

- **Which candidate cause hit the work Mac** in F-419 ("Which of the four paths hit Geoff isn't in the photo") and in F-749 (hooks never run vs. events moved; Q-598 open). The managed-settings path is "not ruled out". `HookPolicy` does not read the managed policy helper command.
- **Which rule fired for Oliver** (F-640), and his CLI version: "Not known".
- **The unknown moment behind F-376's sticky bar**: "isn't on screen". There is no work-Mac `chat-fallbacks.jsonl` here; F-435 says "No `chat-fallbacks.jsonl` exists on this Mac". There is **no field count by rule** in any record.
- **F-173's** one-off "card up but composer shown" (2.1.292): root cause not stated, and not linked to F-328.
- **C-93** (chat-live 9 of 48 on 2.1.302): "Not investigated".
- **F-750**: whether the logged-in work Mac's beacon follows `/clear` promptly "wasn't checked here" (the mock wrote no `<pid>.json`).
- **F-751**: one refusal seen under load even after the change. Whether the 1 s bound is enough on a slower or busier Mac is not stated.
- **C-72**: permission, plan and review rows still take every numbered line. Not seen in the field.
- **F-246**: a permission title starting with a word outside the list still reads unknown. Coverage of future titles is not stated.
- **F-717**: `/btw` "Not checked: 60 columns and 2.1.219".
- **Q-488 vs F-650**: the Q-488 row still says "Not built" and that consoles narrower than 60 columns remain, while F-650 says the hold at `max(pane, 60)` was built. Which reflects the code is not stated in the records.
- **Narrow layouts**: the matcher itself is still unproved below 60 columns (F-640: 38 and 43 columns fail 2–4 of 17). Whether any visible chat terminal (not hidden) can still be below 60 columns is not stated.
- **DL-154 vs DL-258**: DL-154 lets a command screen and a handover bring chat back. DL-258 says "DL-154 stands for every fallback… Nothing returns by itself". Whether `command-screen`, `handover` and `answer-refused` still return by themselves after DL-258 is not stated (F-435, dated before DL-258, says they do).
- **Timer for `trust-*`, `picker-unverified-version`, `version-unverified`**: not stated.
- **The work Mac's hook settings and managed policy**: not inspectable from this Mac (F-749, Q-598).
- **Real-login runs** of the newest question cases (F-749's `askvision` and the narrow sizes) were on the mock only; real-login coverage after F-112/F-106 (2.1.291) is not stated for later versions.
- **Fullscreen and Vim modes**, Tab-to-amend and "Chat about this" preview panes: F-104 lists them as "Not done… (fallback by rule, untested)". Later coverage is not stated.
