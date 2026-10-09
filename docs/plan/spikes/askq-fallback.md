# AskUserQuestion drops chat mode to the terminal: what falls back, and why (F-243 to F-245, C-71, Q-159)

2026-10-08. Test session on Haiku 5.5; nothing fixed. Geoff: "I keep having an issue in chat mode where askUserQuestions force triggers terminal mode."

## Result

**Reproduced, with a cause.** A question falls back when one of its option descriptions has a line that starts `N. ` (a numbered list in the description, or one that wraps onto a line starting with a number). Chat mode reads that line as an extra option, the numbers stop being 1…n, and every Claude Code version except 2.1.291 to 293 sends the dialog to the terminal for good (DL-154). Reproduced on the installed **2.1.295** and on the work Mac's pinned **2.1.219**. No other AskUserQuestion shape fell back.

A second, separate fallback turned up on the way: 2.1.295's **"Allow this read outside the working directories?"** permission dialog reads as `unknown` (F-244). A question that comes after such a Read is stuck behind it.

## How it was run, and what that means

- Live Duo (the work tree's build, `/tmp/dq1` support folder, scratch `CLAUDE_CONFIG_DIR` and workspace, `DUO_SOCKET` and `DUO_TOKEN` for every `duo2` call), the real `claude` TUI, driven by the spike's scripted Messages API (`Spikes/chat-mode/mock.mjs`, port 18911). Sessions started with `duo2 session new --prompt "SCENARIO:<name>"`, state read with `duo2 session chat`, answers with `duo2 session chat answer`.
- **Zero Haiku turns were spent.** The brief asked for real Haiku turns; the scripted API drives the same TUI with the same screens at no token cost, which is why. Real turns would need a login, and the isolated Duo has none (no credentials copied); using Geoff's own config would add test sessions to his real history. If the director wants a few real turns anyway, the one worth running is a real Haiku turn asked for a question with numbered options in a description.
- I added one diagnostic: `ChatSession.fallBack` logs a `chat-fallback:` line to stderr with the reason, the screen kind, cols, rows, `shown`, version, trust, the pending tool, and the screen's rows (`ChatSession.swift`, `traceFallback`). The screens below come from it.
- Not done: the narrow and wide window cells (a background Duo can't be resized by `duo2`; the headless chat-live harness runs 100×34, 60×34 and 80×20 and passes), scrolled-up chat, text in the composer when the question arrives, a question after a plan-mode exit, "Other" text and Next/Submit on a multi-select (`duo2 session chat answer` takes a number only). The existing chat-live harness (`DUO_CHECKS=chat-live`) has cases for the last two; I did not run it.

## Matrix

"Stays" = chat showed the card and `answer` was accepted; no `chat-fallback` line. Version 2.1.295 unless noted.

| Case | Result |
|---|---|
| 1 question, single, 3 options (`ask1`) | stays (also 2.1.219) |
| 1 question, single, 2 options (`ask2`) | stays |
| 1 question, multi-select, 4 options (`askmulti1`) | stays; tick accepted |
| 2 multi-select questions (`askmulti4`) | stays |
| 4 questions, mixed (`ask4`), first answered, next drawn | stays (also 2.1.219) |
| long wrapping labels and descriptions (`asklong`) | stays |
| previews (`askpreview`) | stays (also 2.1.219) |
| backticks, wide characters, emoji in labels; multi-line question (`askodd`) | stays on 2.1.295 |
| `askodd`, description with newline-separated `1. install it` `2. import it` | **falls back on 2.1.219** (2.1.295 draws the newlines on one line) |
| description line starting `3. Third-party …` (`askdesc`) | **falls back on 2.1.295** |
| question after a Read inside the folder (`readask`) | stays |
| question after a Bash permission, allowed (`permask`) | stays |
| question after a streamed reply (`slowask`) | stays |
| Read outside the working directory, then a question (`readask` before the path fix) | **falls back: F-244, not a question** |

## The cases that fall back

### 1. A description line that starts "N. "

Logged: `chat-fallback: This dialog in Claude Code 2.1.295 doesn’t read like the versions chat mode was checked with, so here’s the terminal. | screen=question … cols=87 rows=53 shown=true version=2.1.295 trust=newer` (on 2.1.219 the same with 2.1.219).

Screen (2.1.295, `askdesc`; the full 53 rows are in `Spikes/chat-mode/screens/askq-fallback/desc-numbered-2.1.295.txt`):

```
 ☐ Rollout

Which rollout plan do you want?

❯ 1. Phased
     3. Third-party integrations come last, after the core is stable.
  2. All at once
     One release for everything
  3. Type something.
───────────────────────────────────────────────────────────────────────────────────────
  4. Chat about this

Enter to select · ↑/↓ to navigate · Esc to cancel
```

Screen (2.1.219, `askodd`, `desc-numbered-2.1.219.txt`): option 1's description is three lines, `Fast and small. Steps:` / `1. install it` / `2. import it`. 2.1.295 draws the same description on one line (`Steps:�1. install it�2. import it`), so it is safe there until a description wraps onto a numbered line.

### 2. "Allow this read outside the working directories?" (2.1.295)

Logged: `chat-fallback: Chat mode can’t show this screen, so here’s the terminal. | screen=unknown … pending=Read unknownSince=0.51`. Screen (`read-outside-2.1.295.txt`):

```
 Read outside the working directories
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
 Read(/…/ws/data.txt)
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
 Auto mode and the sandbox read outside the working directories without asking. …

 Allow this read outside the working directories?
 ❯ 1. Yes, and keep allowing any reads outside the working directories
   2. No, and block reads outside the working directories from now on
   3. No, and ask again next time
   4. Yes, but ask again next time

 Esc to cancel · Tab to amend
```

## Cause, in the code

1. **The parse.** `ChatScreen.swift:509` (`question()`): any line matching `^\s*(❯)?\s*(\d+)\.\s…` is appended as an option row, with no regard to indent. A description is indented under its option, so it should be a note (`note`), never a row.
2. **The gate.** `ChatScreen.swift:375` (`wellFormed`) requires the option numbers to be exactly 1…n (`:385`). `ChatSession.swift:145` (`dialogsVerified`) applies it to every version except the verified ones (`ChatScreen.swift` `verified: 2.1.291 to 293`; `trust(for:)` makes the rest `.newer`), and `evaluateFallback` (`ChatSession.swift:366`) turns a failure into `fallBack`, which is sticky (`ChatSession.swift:387`, DL-154).
3. **On a verified version** (291 to 293) there is no gate, so the extra rows would be answered by number: a wrong answer rather than a fallback. Not run.
4. **The second fallback.** `permissionQuestion` (`ChatScreen.swift:23`) only knows "Do you want to …?". The new wording gives `unknown`, and `ChatSession.swift:353` falls back after the 0.5 s grace with the generic message.

Best fix, for the Opus or Sonnet session: take as options only the rows at the option indent, counting up from 1 and stopping at the first break (or: a row whose indent is deeper than the option column is a note); accept "Allow this …?" as a permission question (or any question line directly above a numbered list with `Esc to cancel`). Q-159 asks whether to go further.

## New fixtures

`Spikes/chat-mode/screens/askq-fallback/` holds the three real screens (53 rows each, with the logged header values above). `Sources/DuoChecks/ChatAskqFallback.swift` has the checks, run on their own so the default suite stays green:

```
DUO_CHECKS=askq-fallback swift run DuoChecks      # today: 2 passed, 7 failed
```

They state what chat should do: the options are the ones Claude asked (`["Phased", "All at once"]`; the three of `askodd`), the dialog reads whole, `dialogsVerified` is true with no "doesn’t read like" fallback on 2.1.295 and 2.1.219, and the read-outside dialog reads as a permission with four options. When the fix lands they move into `chatChecks()`.

The scripted API gained `readask`, `permask`, `slowask`, `askodd`, `ask2`, `askmulti4`, `askdesc`, and its scenario lookup now works behind Duo's reminder blocks (F-245).

## Two things to know

- Once, a `duo2` call went without `DUO_SOCKET` and `DUO_TOKEN` and reached Geoff's own Duo: `sessions` listed his sessions (read-only) and `session new --project askq` failed with "no project 'askq'", so nothing was created there. Every later call carried both.
- The director's tip (use `build/Duo.app` unless Swift changes) was followed for the first runs; the trace needed a work-tree build.
