# Chat's questions: why they are fragile, and a sounder way to carry them

2026-11-19, fix/chat-multi-question-fallback. Asked by Geoff after the 2026-11-17 fallback: "review all prior bug reports on this topic and think from first principles about the approach and whether or not it is sound. Then generate novel approaches to solve this issue and a testing approach."

Three things are in here: what 41 past failures say (the full table is `chat-questions-incident-catalogue.md`), why the present design keeps producing them, and a different channel for questions, tested on Claude Code 2.1.284 and 2.1.325 (scripts in `Spikes/chat-mode/hook-answer/`). It ends with the decisions that are Geoff's.

## 1. The short answer

- **The approach is not sound for questions.** To show and answer one AskUserQuestion, chat needs four independent things to agree inside 1.5 seconds: a correct reading of a terminal screen drawn for people, a hook event that arrives by a file Duo polls, a version of Claude Code whose drawing it recognises, and keystrokes that land on the screen it last read. Any one failing sends you to the terminal. Each past fix made one of the four a little more tolerant. None removed a dependency.
- **A question does not need the screen at all.** Claude Code will take the answer to an AskUserQuestion from a hook. A Duo hook can hand the request to Duo, wait while you answer on the card, and give Claude Code your answers. Nothing is read off the screen and nothing is typed into it. Tested on 2.1.284 and 2.1.325: the answers arrive exactly, for one question and for four tabbed ones.
- **The terminal's own dialog can stay up underneath**, so the question can still be answered in the terminal or from Remote Control on your phone, and whichever answer comes first wins. If the hook never runs (an organization's settings turn hooks off) or Duo isn't there, Claude Code just shows its dialog, as today.
- **This was ruled out in October on a wrong premise.** The chat-mode spike said a hook's answer "would *replace* the TUI's dialog, which DL-118 rules out". With the PermissionRequest hook it doesn't replace it. It is still a change to DL-118's wording ("their answers go back as keys to the real TUI"), so it is Geoff's decision (§7).

## 2. What the reports say

The catalogue has 41 distinct failures in chat's dialogs and screen reading since 2026-10-06, from about 68 findings.

| Layer that failed | Failures (primary) | With secondary |
|---|---|---|
| Reading the screen | 7 | 13 |
| Typing the answer as keys | 5 | 9 |
| Timing between sources | 5 | 7 |
| The hook's request late, lost, moved or absent | 5 | 5 |
| Terminal width and height | 4 | 6 |
| A rule that chose the terminal | 4 | 7 |
| A new CLI version drew it differently | 2 | 6 |
| Other, tests, not stated | 9 | |

What stands out:

- **13 of the 41 came from real use, and 6 of those from the work Mac.** Of the 8 field reports that were a question or dialog falling back, the cause was proved for 4. The other 4, including all three of the work Mac's (F-376, F-419, F-749), end with the trigger unknown. F-419 guarded four candidate paths; F-749 guarded two more. Geoff's "band-aid" is a fair reading of the record: the last two fixes covered every cause we could think of because we could not see which one happened.
- **No layer dominates.** A design with one weak part would show one tall bar. This one fails everywhere a little, which is what a chain of independent conditions does.
- **There is no count from the field.** Every fallback is logged on the Mac it happens on (`logs/chat-fallbacks.jsonl`), and the work Mac's log has never been read here. We do not know how often a question falls back for Geoff, or which rule fires most.
- **The closest precedent warned us.** F-103, on Omnara's first version, which also read prompts off the terminal: "the closest precedent… then was dropped in a relaunch. A warning about upkeep."

## 3. First principles: why it keeps breaking

What chat has to do for a question is small: get the questions Claude asked, show them, and get your answers to Claude. The present path does it like this (catalogue §3):

1. Claude Code draws its dialog. Chat reads the terminal's text 60 ms after output settles and must classify it as a question, by signatures kept per CLI version, at whatever width the hidden terminal has.
2. Claude Code runs Duo's hooks, which append the request to `events/<session id>.jsonl`. Chat polls that file every 150 ms (every 2 s off screen) and must find the request under the id it thinks the tab has.
3. The two must agree: the screen's question text must be the end of exactly one asked question, and every visible label the start of the asked label. They have 1.5 s (15 s while a long transcript loads).
4. You pick on the card. Chat re-reads the screen, moves Claude Code's cursor one arrow at a time, re-reading between arrows, and presses Return or a digit.
5. Any surprise at any step: the terminal, and it stays until you press Back to Chat (DL-154, DL-258).

Counted as conditions, the catalogue lists **7 that must hold to show the card and 5 more to answer it**, drawing on 10 sources. If each held 99.5% of the time, one question in 17 would fall back. The fixes since October each raised one of those numbers; the product of twelve stays stubborn.

Three structural faults, each visible in the record:

- **The screen is an interface for eyes, and it changes without notice.** 2.1.292, 2.1.293, 2.1.295, 2.1.296, 2.1.323 and 2.1.325 each changed something chat reads (F-175, F-176, F-244, F-284, F-731). The current tab of a multi-question dialog is shown "only by colour", which chat cannot see, so it infers the tab by matching text (F-106). Width matters: under 60 columns the matcher still fails 2 to 4 of 17 cases (F-640), so Duo holds the hidden terminal at 60 or more (F-650).
- **The request arrives by a side road.** It is written to a file named by a session id that changes under `/clear` and `/resume` (F-750), read by a poller that slows off screen and stops while a transcript loads (F-419), and it does not exist at all where an organization turns hooks off (F-749). The transcript is no substitute: the question reaches it only after it's answered (F-749).
- **The answer is typed blind.** Keys go to a program whose state chat knows only from the last screen it read. A slow repaint and an arrow is sent from a stale cursor (F-751); a dialog that closed and a digit lands in the prompt (F-104).

And one fault of policy: a fallback is the *safe* outcome by design (DL-164: "a fallback is visible and recoverable"), so every doubt is resolved toward the terminal. That is right for a permission prompt read off a screen. For a question whose full text Duo already holds, it makes the common case pay for the rare one.

## 4. What Claude Code offers instead (tested)

Claude Code's hooks can do more than observe. Two of them can answer an AskUserQuestion by returning the tool's input with an `answers` map added (`updatedInput`). Run against the spike's mock API, no login, in a pty at 94 columns, with a hook that waits and then answers (`Spikes/chat-mode/hook-answer/`):

| Test | 2.1.284 | 2.1.325 |
|---|---|---|
| **PreToolUse** hook returns `permissionDecision: allow` + `updatedInput.answers`, four tabbed questions, after 3 s | Claude receives all four answers ("User answered Claude's questions: … → Customers · … → Slides · …"). **The dialog is never drawn**; the TUI shows "running PreToolUse hook" | Same |
| **PermissionRequest** hook returns `decision: allow` + `updatedInput.answers`, after 3 s | Claude receives all four answers. **The dialog is drawn while the hook waits**, and closes when the hook answers | Same |
| PermissionRequest hook waiting 25 s; the question answered **in the terminal** at 6 s | The terminal's answer is taken at once (the turn goes on 4 s later); the hook's later answer is ignored | Same |
| PreToolUse hook returns `deny` with a reason | No dialog. Claude's tool result is the reason: "PreToolUse:AskUserQuestion hook error: The user declined to answer in Duo and wants to talk it over first." | Same |
| PreToolUse hook slower than its `timeout` (5 s) | The hook is abandoned and **Claude Code draws its own dialog** | Same |
| PreToolUse hook waiting 100 s (`timeout` 3600) | Answers arrive after 1 m 41 s | not run |
| **Esc** in the terminal while either hook waits | The question is declined and the hook process is ended | not run |
| Hooks off (`disableAllHooks`) | The dialog is drawn; no hook runs (F-749) | Same |

Not tested here: a multi-select answer and a free-text answer through the hook (the `answers` map is question → text, and the terminal itself records several picks as "Lint, Build", F-106); preview notes; Claude Code 2.1.219, Duo's floor; a wait of hours; a real login; what Remote Control shows while a PreToolUse hook holds the call. Each is a line in the build's proof (§6).

What this gives, set against §3's faults:

- **The request comes to Duo directly.** The hook is a process Claude Code starts with the request on its input. It can pass it to Duo over the control socket, as `duo2 hook pre-edit` already does for file edits. No file, no polling, no session id to follow: the hook runs inside the right process and carries the tab's launch id in its environment.
- **Nothing is read off the screen** to show a question, and nothing is typed to answer one. Version drift in how the dialog is drawn, width, colour-only tabs and stale cursors stop mattering for questions.
- **Failure falls toward the terminal's dialog, not away from the question.** No hook, a slow hook, no Duo: Claude Code asks in the terminal, as it does today.

## 5. Approaches

### A. The question hook, dialog kept (recommended)

A PermissionRequest hook for AskUserQuestion, `duo2 hook ask`, in the per-session settings Duo already writes:

1. Claude asks. Claude Code draws its dialog and starts the hook with the request.
2. The hook connects to Duo's socket and sends the request with the tab's launch id. Duo shows the question card from the request alone: every question, header, option, description, multi-select flag and preview, exactly as asked.
3. You answer on the card. Duo replies to the hook; the hook prints the answers; Claude Code closes its dialog and goes on.
4. If you answer in the terminal or from your phone instead, Claude Code goes on at once; Duo sees the tool finish (PostToolUse) or the hook's connection close, and takes the card down.
5. Decline on the card returns a deny with your words. Esc in the terminal ends the hook; Duo takes the card down.
6. If the hook can't reach Duo it prints nothing and exits; the dialog is simply up, and today's path (read the screen, answer with keys) or the terminal handles it.

Why the dialog-kept variant: it keeps the terminal true (DL-118's overlay idea: the real session shows the real question), keeps Remote Control working, and makes a timeout or a crashed Duo cost nothing. The PreToolUse variant (no dialog at all) is cleaner on screen but hides the question from the terminal and probably from the phone, and a timeout would make the dialog appear late.

What it removes, by the catalogue's layers: screen reading, version drift, geometry, key injection and timing all leave the question path; hook delivery shrinks to "the hook runs or it doesn't". What stays: the hook must be allowed to run. Where an organization forbids it, chat is where it is today, with the bar now saying why (F-749).

What it costs: DL-118 (2) says answers "go back as keys to the real TUI"; F-26 and the spike say Duo's hooks "print nothing". This hook prints, on your click and never otherwise: nothing is pre-selected, skipped or answered for you. The pre-edit hook already decides (it can deny an edit), so it is not the first. It needs a decision that replaces the words "as keys" with the intent behind them (§7).

Size: one hook verb, one socket request that stays open, the card fed from the request instead of the screen, and the old path kept behind it. A Sonnet build of a few days after a short Opus plan.

### B. The same hook for permissions and plan approval (later)

PermissionRequest fires for every permission dialog and for ExitPlanMode, and can return allow or deny (and, for "always allow", permission updates). So the same channel could carry Yes / No / plan approval. Harder than questions: the option labels come only from the screen (F-105: the request said `destination: session` where the screen said "from this project"), and 2.1.325 added a fourth option the request doesn't describe (F-731). Suggest: questions first; then permissions as Yes / No from the hook with anything richer left to the terminal dialog; measure before going further.

### C. Keep reading the screen, but make it the fallback only

Whatever is decided, the present path should stop being the main one for questions and become the path for sessions where the hook can't run. Then its remaining faults (below 60 columns, new versions) hit only those sessions.

### D. A card from the screen alone where hooks are forbidden (Q-599)

On a Mac whose organization turns hooks off, neither today's path nor A can work, because both need a hook. The only source left is the screen. A screen-only card for single questions is feasible (the reader already takes the question, options and descriptions); a tabbed question would fill in as you move through it. It gives up the check that the screen matches Claude's request, because there is no request to match. Worth deciding only once we know the work Mac's hooks are in fact off (Q-598); if they are, this is the difference between chat answering questions there and never doing so.

### E. Considered, not recommended

- **Running Claude headless** (`-p`, stream-json, the Agent SDK's `can_use_tool`): every other chat GUI does this and gets questions as data. It replaces the terminal session, which DL-118 rules out, and gives up `/` commands, the CLI login path as built, and Terminal mode as the same session.
- **Duo's own question tool over MCP**, with AskUserQuestion disallowed: Duo would own the whole exchange, but it changes what Claude sees and does in Duo against everywhere else, and an organization can forbid MCP servers as easily as hooks.
- **The duo-signal mod** (F-297): gives the request about 60 ms sooner and nothing else; it still needs the screen and the keys.
- **Tolerating more** (longer graces, auto-return): each has been tried or rejected (Q-326, Q-328, DL-258); they trade a visible failure for a wrong or flapping one.

## 6. Testing approach

Today's tests are strong on cases we thought of (chat-live: about 100 checks a version) and silent on the rest; and nothing tells us what happens in the field. Five parts, cheapest first:

1. **A contract test per Claude Code version, run when a version appears.** The hook's contract is small and can be stated: allow + answers reaches Claude for single, multi-select, free text, four questions and preview notes; a terminal answer wins a race; deny carries its reason; a timeout leaves the dialog; Esc ends the hook; hooks off draws the dialog. `Spikes/chat-mode/hook-answer/matrix.sh` is the seed. It needs no login and no Duo, takes about a minute a version, and can run from the existing nightly discovery agent against each new release, so a break is known before Geoff's CLI updates. The work Mac's pin (2.1.284) and Duo's floor (2.1.219) stay in the matrix.
2. **Generated questions, not hand-written ones.** A generator makes AskUserQuestion inputs across the schema: 1 to 4 questions; 2 to 4 options; multi-select or not; labels and descriptions with numbers at line starts (F-243), parentheses, quotes, emoji, CJK, 150-character lines (F-419); previews. Each is asked through the mock, answered through Duo's real code with a random valid answer, and the test compares what Claude received with what was picked. A few hundred a run, seeded so a failure replays. For the kept screen path, the same generator at widths 40 to 200 and heights 20 to 65.
3. **Faults injected on purpose.** The same end-to-end run with: Duo's socket slow or gone; Duo quit while a question waits; the question answered in the terminal mid-pick; `/clear` or `/resume` just before; hooks off; the Mac loaded (F-751 appeared at load average 11); two sessions asking the same question in one folder. The pass condition is never "no fallback": it is "the question was answered correctly, or the terminal's dialog was up and the bar said why".
4. **A count from the field, kept on the Mac.** Every question gets one line in a local ledger: asked, shown as a card or not, answered where (card, terminal, phone), how long, and the rule if it fell back. `duo2 doctor` and the Debug report print the totals ("questions this week: 212; card 209; terminal 3: hooks-silent 3"). Nothing leaves the Mac; Geoff photographs or saves it as now. This turns "it feels brittle" into a number per release, and names the rule to fix next. It is the piece the record most lacks.
5. **A release gate with a real login.** A handful of real Haiku turns before a release (one question, four tabbed, multi-select, decline), in an isolated instance, approved as the other real-login tests are. The mock has missed real behaviour before (F-105).

The target to hold a release to: with hooks allowed, **no question reaches the terminal** in the generated and fault runs, and the field ledger shows the same.

## 7. Decisions for Geoff

Recorded as Q-600 to Q-604 (in this order); the findings are F-753 to F-755; the tests are ENH-361 and ENH-362. Q-599 is folded into Q-604.

1. **May a Duo hook carry your answer to a question?** That is approach A: the answer you click on Duo's card goes to Claude Code through the hook instead of as keystrokes. The terminal's dialog stays up and answerable. It amends DL-118 (2)'s "as keys" and the "hooks print nothing" rule, for AskUserQuestion only. **Recommended: yes.**
2. **Dialog kept, or hidden?** Kept (PermissionRequest): the terminal and Remote Control still show the question; a failure costs nothing. Hidden (PreToolUse): the terminal shows only "running hook" while you answer in Duo. **Recommended: kept.**
3. **The field ledger** (testing part 4): a local count of every question's outcome, shown in `duo2 doctor` and the report. **Recommended: yes, and first, since it also tells us what the work Mac's hooks do.**
4. **Permissions and plan approval by the same hook** (approach B). **Recommended: after questions have run a release, Yes / No only.**
5. **A screen-only card where hooks are forbidden** (approach D, Q-599). **Recommended: decide after Q-598 or the ledger says whether the work Mac's hooks run.**

## 8. What this study did not do

- No real login and no real turn: every run is the mock API. No Duo code was changed for approach A; the hook in the spike is a stand-alone script.
- The untested cells in §4, above all 2.1.219 and Remote Control.
- The work Mac: its events folder, its managed settings and its fallback log were not available, so whether hooks run there is still open (Q-598). If they don't, A helps every other Mac and not that one; D or a change to the organization's settings is what would.
- The catalogue's layer for each failure is a classification from the records' wording, made by a research pass and spot-read, not re-derived from code.
