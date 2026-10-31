# Mac text editing and selection in the terminal's input box: study

Task: `tasks/terminal-text-selection.md`. Geoff, 2026-10-31 (verbatim): "improve the way text selection works in the terminal interface. If I select Command A, I would like it to only select all of the text within the composer pane. I would like to make Command and arrow buttons work effectively. For example, Home and End. And Command Shift arrow buttons work the way you would expect them to work in a mature app and not in a terminal. Please think through the full range of text selection commands that work in a mature Mac OS application. And identify strategies for bringing these into the terminal interface of Duo."

Research only: nothing is built until Geoff picks (DL-274). Records: F-470 to F-473, Q-358 to Q-361, C-134, ENH-300.

**In short.**
- **Movement already works.** On Claude Code 2.1.284 and 2.1.311 in Duo, these work today:
  - ⌘←/→, Home/End, ⌥←/→ and the Emacs keys move the cursor;
  - ⌥⌫ and ⌘⌫ delete.
- **What's missing is a selection the keyboard can make, and ⌘A.** Today ⌘A selects the whole terminal.
- **Claude Code already has a selection model, so Duo can drive it.** Since 2.1.292 Claude Code runs a fullscreen renderer by default: Geoff's settings name it, and 2.1.284 uses it too. That renderer has its own mouse selection. It draws the highlight, ⌫ deletes the selection, and ⇧-arrows extend it.
- **Recommendation:** strategy 2, after strategy 1's key fixes. Duo sends Claude the same mouse bytes a drag would, so Claude selects and draws its own highlight. Duo adds what's missing: ⌘A for the prompt only, ⇧⌘/⇧⌥ arrows, typing over a selection, cut and copy.
- **The riskiest step was prototyped headless on both versions, and works.**

---

## 1. What a mature Mac text field offers, and what each means in a multi-line prompt

The prompt is a multi-line field that wraps: a *line* below means a visual row; a *paragraph* means a hard line (between new lines).

| Command | Mac (NSTextView) | In Claude's prompt |
|---|---|---|
| ←/→ | a character; with a selection, collapse to its start/end | moves; nothing to collapse today |
| ↑/↓ | a row up/down, keeping the column; on the first/last row, to the start/end of the text | Claude: a row up/down; **on the first/last row it recalls the previous/next prompt** (history). A Mac-like ↑ on row 1 would steal history |
| ⌥←/→ | a word | a word |
| ⌘←/→ | start/end of the visual row | same (measured on a wrapped row) |
| ⌘↑/↓ | start/end of the whole text | Duo's All Projects owns ⌘↑ (DL-34); ⌘↓ is a row down, and history on the last row |
| Home/End (fn←/→) | AppKit scrolls the view and leaves the caret; most people (and Geoff's request) expect row start/end | row start/end |
| Page Up/Down | a page | Claude scrolls its transcript (fullscreen) |
| ⇧ + any of these | extends the selection from a fixed anchor | the whole selection model this study is about |
| ⌘A | selects everything in the field | must select only the prompt's text, not the screen |
| ⌫, ⌥⌫, ⌘⌫ | a character, a word back, to the row's start | same |
| fn⌫ (⌦), ⌥fn⌫ | a character forward, a word forward | ⌦ same; **⌥fn⌫ kills to the line's end in Claude** |
| ⌃K, ⌃Y | kill to the paragraph's end, yank | same (Claude's own kill ring) |
| ⌘Z, ⇧⌘Z | undo, redo | Claude's undo is ⌃_ ; it has no redo |
| ⌃A/E | paragraph start/end | same |
| ⌃F/B/N/P | char forward/back, row down/up | same |
| ⌃T | transpose | Claude: toggles its task list |
| ⌃O | open a line | Claude: opens the transcript |
| ⌃D, ⌃H | delete forward, backward | same |
| double-, triple-click | a word, a paragraph | Claude (fullscreen): a word, a row |
| drag, ⇧-click | select, extend | Claude (fullscreen): drag selects; ⇧-click doesn't reach it (SwiftTerm takes ⇧ for its own selection) |
| typing over a selection | replaces it | must replace it |
| ⌘C, ⌘X, ⌘V | copy, cut, paste | copy must give the prompt's text (no indents, no wrap breaks); paste works |
| drag text in/out | moves or copies text | Duo types dropped *file* paths (DL-117); text drags aren't handled |
| Services, Look Up (⌃⌘D) | on the selection | not offered by SwiftTerm |

## 2. What Claude Code's input box supports (2.1.311 and the work Mac's 2.1.284)

Measured, not read from docs: real Claude Code in a pty (node-pty + @xterm/headless). Each run used a scratch `CLAUDE_CONFIG_DIR`, a mock key and a dead API address. There was no login, no turn, and no visible window. Each key's bytes were sent into a three-line prompt, then a marker was typed and the box read back. `results/claude-keys.txt` has every case. Both versions answered every case the same way, in both keyboard modes (F-470).

**Its keybindings.** `keybindings.json` contexts and actions are the same in both versions:
- `Chat`: `chat:submit`, `chat:newline`, `chat:undo` (⌃_ / ⌃-), `chat:externalEditor` (⌃G), `chat:clearInput` (⌃L), `history:*`, …
- 2.1.311 adds ⇧↑/⇧↓ for effort and ⌃Y for "default to newer model". Both are feature-gated: neither did anything here, and ⌃Y still yanked.
- **No action moves the cursor or selects.** The text input's own keys are hard-coded: ⌃A/E/F/B/N/P/D/H/K/U/W/Y, ⌥B/F/D, ⌥⌫, Home/End, the arrows, Super+←/→ (line start/end), Super+⌫ (to line start).
- So `keybindings.json` can't add ⌘A or a selection. Geoff has no `keybindings.json` and no vim mode.

**A selection model exists, but only in the fullscreen renderer.** 2.1.292 and later run the fullscreen renderer by default (F-284). This is the alternate screen with mouse reporting 1000/1002/1003/1006, measured on both 2.1.284 and 2.1.311 with a clean environment. Geoff's `~/.claude/settings.json` has `"tui": "fullscreen"`. The renderer has a screen selection (the `Scroll` context's `selection:*` actions), measured on both versions (`results/claude-mouse-selection.txt`, F-471):
- **Mouse:**
  - a drag selects and draws it in Claude's theme colour;
  - double-click selects a word, triple-click a row;
  - a click places the caret.
- **Keys on a selection:**
  - ⇧←/→/↑/↓ and ⇧Home/⇧End extend a selection, but only one that already exists;
  - ⌫ or ⌦ deletes the selection when it lies inside the prompt;
  - ⌃C copies it.
- **Copying:** every selection is copied at once (OSC 52, which SwiftTerm writes to the Mac clipboard). The copy is screen text: continuation rows keep their 2-space indent, and a soft wrap becomes a line break.
- **Missing:**
  - no keyboard key starts a selection;
  - typing over a selection inserts at the old caret and drops the selection;
  - ⇧⌥←/→ moves the caret and leaves the selection;
  - ← with a selection moves from the caret rather than collapsing;
  - there's no cut;
  - a selection that runs into the transcript isn't deleted (⌫ deletes one character instead).

**Escape sequences.**
- **Kitty keyboard protocol:** both versions ask for it (`CSI ? u`) and push `CSI > 5 u`. SwiftTerm answers, so in Duo every modified key reaches Claude in CSI u form. Claude reads CSI u for every key above, and the legacy bytes too.
- **Bracketed paste** (2004): on.
- **Focus reports** (1004): on.
- **Mouse reporting:** fullscreen only.
- **Vim mode:**
  - INSERT behaves like the default editor for every key tested;
  - NORMAL gives keys their vim meanings (⌘← and ⌘⌫ act as `h`, ⌥← as `b`);
  - only the footer's `-- INSERT --` tells the two apart (`results/claude-keys-vim.txt`).

## 3. How Duo's terminal handles keys and selection today

- **SwiftTerm's bytes for each Mac chord**: `results/swiftterm-bytes.tsv`, measured at Duo's pinned commit with the method of DuoChecks `return-chords`.
  - With the kitty flags (2.1.284+): ⌘ arrows → `CSI 1;9 A-D`, ⇧⌘ arrows → `CSI 1;10 …`, ⌥⌫ → `CSI 127;3u`, the ⌃ letters → `CSI n;5u`, Home/End → `CSI H`/`CSI F`.
  - Without them (2.1.219): ⌘← sends `ESC b` (a word back, SwiftTerm's `moveToLeftEndOfLine:`) and ⌘↑/↓ send nothing.
- **Duo's own keys:** `TerminalKeys` adds ⇧↩ (ESC CR without the protocol), ⌘↩ (CR, DL-241, F-393) and ⌘⌫ (^U).
  - Its comment says Claude doesn't read Super+Backspace. That's stale: both versions read it as delete-to-line-start (F-473).
- **Menu chords:** Duo's menus take ⌘A (Select All), ⌘C/⌘X/⌘V, ⌘Z/⇧⌘Z, ⌘↑ (All Projects), ⌥⌘←/→ (panes), ⇧⌘A (search), ⌘B/⌘I/⇧⌘X (Format), ⌘D, ⇧⌘D (voice).
  - A menu key never reaches Claude, even when its item is disabled; measured with an AppKit menu in the probe (F-473).
  - Unclaimed ⌘ chords pass through: ⌘←/→/↓, ⇧⌘←/→.
- **⌘A today:** SwiftTerm's `selectAll` selects the whole screen in Duo's highlight, and ⌘C then copies all of it.
- **The mouse:**
  - In fullscreen Claude, a click or drag goes to Claude: SwiftTerm forwards mouse events because `allowMouseReporting` is on and Claude asked for them.
  - ⇧-drag is SwiftTerm's own selection.
  - ⌘C copies SwiftTerm's selection. That selection is empty after a Claude drag, but Claude has already put its copy on the clipboard.
- **Chat mode reads the input box** from the screen (`ChatScreenReader`: the last two full-width rules with `❯` under the top one). Chat reads the prompt's exact text through Claude's external editor: Ctrl+G with `EDITOR=duo2 compose`, set for every Duo Claude session (`ChatSession.peekPrompt`, F-112).
  - In the terminal that peek blanks the screen while the editor runs: Claude leaves and re-enters the alternate screen. So it can't run on every copy unseen (`results/ctrl-g-peek.txt`, F-473).
- **The voice mic** (DL-264) sits in the 4-column margin Duo keeps right of the box, found by `InputBoxFinder` from the box's rules and prompt row. None of the strategies touch the margin.

## 4. Strategies, light to heavy

### Strategy 1: Mac keys, translated (light)

Duo maps the Mac chords that Claude gets wrong onto Claude's own keys, in `TerminalKeys`. It acts only for a Claude terminal with its input box up: no question or picker (`InputBoxFinder.questionShowing`), and not vim NORMAL.
- ⌘↓ → the prompt's end: ↓ once for each row below the caret (counted from the box), then End.
- ⌘↑ → the prompt's start, if Geoff gives ⌘↑ to the terminal over All Projects (Q-359).
- ⌥fn⌫ → `ESC d` (a word forward; Claude's own ⌥⌦ kills the whole line).
- ⌘Z → ⌃_ (Claude's undo) while a Claude terminal has the keyboard (Q-360: what ⌘Z does there today isn't known). ⇧⌘Z beeps, since Claude has no redo.
- ⌃T and ⌃O stay Claude's.

**Works:** every movement and deletion key in §1.
**Can't:** any selection, ⌘A, typing over a selection, cut.
**Risk to the TUI:** none; it only sends keys Claude already reads.
**2.1.284:** identical.
**Chat:** untouched (the composer is an NSTextView).
**Voice:** untouched.
**Vim:** off in NORMAL.
**Questions and pickers:** keys pass through untouched.
**Cost:** about a day (`TerminalKeys` and DuoChecks rows like `return-chords`).
**Recommendation:** do it first, whatever else is picked.

### Strategy 2: Claude's own selection, driven by Duo (medium) — recommended

Duo keeps a selection model of its own: an anchor and a focus, in the box's cells. It makes Claude select by sending the same SGR mouse bytes a drag would. Claude does the selecting and draws its own highlight, so **Duo draws nothing inside the terminal**.

- **⌘A:** a drag from the box's first text cell to one cell past its last character. Claude clamps it, and a drag ending *on* a wide last character misses it.
- **⇧-arrows:**
  - ⇧←/→/↑/↓ and ⇧Home/⇧End extend natively once a selection exists;
  - with none, Duo starts one with a drag from the caret;
  - ⇧⌥←/→ and ⇧⌘←/→/↑/↓: Duo moves Claude's caret with the plain key (Claude keeps the selection), reads where it landed, and drags again from the anchor.
- **⌫ / ⌦:** Claude deletes the selection.
- **Typing over a selection:** Duo sends ⌫ first, then the character.
- **⌘X:** copy, then ⌫.
- **⌘C:** the selection's text. Claude's OSC 52 copy is screen text, so Duo strips the continuation indent and, for soft wraps, either guesses from the row widths or reads the exact text through Ctrl+G with the flash hidden (Q-361).
- **←/→ with a selection:** collapse with a click at its start or end (Claude places the caret on a click).
- **Mouse:**
  - ⇧-click becomes a drag from the anchor;
  - Claude's own drags in the box are watched, so typing over them and ⌘X work too;
  - any other click clears Duo's state.
- **Clipboard:** Duo's own drags must not overwrite it. Their OSC 52 copy is dropped, which means taking SwiftTerm's `clipboardCopy` delegate (C-134).

**Prototype** (`results/strategy-b-synthetic-drag.txt`, 11 cases × 2 versions, F-472):
- **Passed on both versions:**
  - ⌘A then ⌫ emptied three-line, wrapped, placeholder and trailing-blank-line prompts;
  - ⌫ then X replaced the selection with "X";
  - ⇧←, ⇧Home and ⇧↑ extended it, and ⌫ deleted exactly that;
  - ⌦ deleted it;
  - with a wide emoji last, the drag had to end past it; it then passed.
- **Two places Claude falls short, where Duo must step in:**
  - ⇧⌥← moved the caret but kept the old selection;
  - ← moved from the caret instead of collapsing.

**Works:** every selection command in §1 except Services/Look Up and drag-and-drop of text. Undo is Claude's (one level per edit, no redo).
**Can't:**
- the inline renderer (`/tui default`) or vim NORMAL: there it falls back to strategy 1;
- a selection outside the prompt.
**Risk to the TUI:** none drawn. The risk is behavioural (C-134): this leans on Claude internals (the selection, `tryDelete`, click-to-caret, the clamp), which a Claude update can change.
- Mitigation: a pty probe per verified version in DuoChecks, like the chat signatures (DL-145); an unverified version gets strategy 1 only.
- A synthetic drag also races a real mouse, so a key selection owns the mouse until it ends.
**2.1.284:** identical in every case measured, if the work Mac runs fullscreen (Q-358).
**Chat:** untouched. A selection only adds a background colour, so `ChatScreenReader` reads the same text.
**Voice:** dictating over a selection replaces it (⌫ first), as on a Mac.
**Questions and pickers:** a dialog clears the selection, and arrows go to Claude.
**Cost:** 4 to 6 days, plus the per-version probe check.

### Strategy 3: Duo's own selection over the box (medium-heavy)

The same model as strategy 2, but Duo draws the highlight in a layer over the box's cells and edits by keys: it moves Claude's caret with ←/→ and deletes with ⌫. It maps cells to text by aligning the box's cells with the prompt's exact text (from Ctrl+G).

**Prototype** (`results/strategy-c-alignment.txt`, F-472):
- 6 of 6 selection deletes came out exactly right on both versions: across a new line, across a soft wrap, in CJK and ZWJ-emoji text, beside a paste placeholder, and over one.
- The first run failed 2 of 6 (an emoji xterm splits across cells; a placeholder that Ctrl+G returns as its full text). The aligner was fixed for both.

**Works:**
- the same commands as strategy 2;
- the inline renderer as well;
- a copy that is always exact.
**Can't:**
- a peek without a visible flash, unless Duo freezes the view for the ~100 ms;
- the user's own mouse selection in fullscreen stays Claude's, a second highlight model.
**Risk to the TUI:** Duo draws inside the terminal, which Geoff withdrew in DL-264. It needs a Design canvas (Light/Dark/Classic) and approval before a build.
**2.1.284:** identical.
**Chat, voice and vim:** as strategy 2.
**Cost:** 6 to 8 days plus the design round.

### Strategy 4: a native editor over the box (heavy)

On ⌘A, a ⇧-chord or a click in the box, Duo lifts the prompt through Ctrl+G (`duo2 compose` already does the handover). It edits the prompt in an NSTextView laid over the box in the console font, then writes it back. Afterwards it puts Claude's caret where the editor's was, with ←.

**Works:** everything in §1 natively: Services, Look Up, spelling, text drag-and-drop, real undo/redo.
**Can't:**
- keep Claude's TUI live while editing: Claude waits in the editor, its screen blank;
- match Claude's wrapping;
- avoid the lift's flash.
**Risk to the TUI:** the largest: Duo covers the box, and the box grows over the transcript as you type.
**2.1.284:** works (Ctrl+G returns cleanly from 2.1.269).
**Chat:** overlaps chat mode, which is already this editor with the TUI hidden.
**Voice:** dictates into the NSTextView.
**Vim:** lost while editing.
**Cost:** about two weeks.
**Recommendation:** no. Chat mode already offers it.

### Not a strategy: asking Claude Code through `keybindings.json`

Neither version has a cursor or selection action to bind in the prompt. The `selection:*` actions act only on an existing screen selection. Logged as ENH-300: ask Anthropic for prompt actions to select all, extend by word or line, and redo.

## 5. Key by key

Today = Duo 0.2.x on 2.1.311 (Geoff) with the fullscreen renderer; 2.1.284 measured the same in every row unless noted. S1–S4 = the strategies above. ✓ works as on a Mac · ✗ doesn't · ~ partly.

| Chord | Today | S1 keys | S2 Claude's selection, Duo-driven | S3 Duo's selection | S4 native editor | 2.1.284 |
|---|---|---|---|---|---|---|
| ← → | ✓ (no selection to collapse) | ✓ | ✓, collapses a selection | ✓, collapses | ✓ | same |
| ↑ ↓ | ✓; history on the first/last row | ✓ | ✓ | ✓ | ✓ | same |
| ⌥← ⌥→ | ✓ word | ✓ | ✓ | ✓ | ✓ | same |
| ⌘← ⌘→ | ✓ row start/end | ✓ | ✓ | ✓ | ✓ | same |
| ⌘↑ | ✗ All Projects (DL-34) | ✓ prompt start if Q-359 says so | same as S1 | same as S1 | ✓ | same |
| ⌘↓ | ✗ a row down | ✓ prompt end | ✓ | ✓ | ✓ | same |
| Home End | ✓ row start/end | ✓ | ✓ | ✓ | ✓ | same |
| Page Up/Down | scrolls Claude's transcript | same | same | same | in the editor | same |
| ⇧← ⇧→ | ✗ moves only | ✗ | ✓ | ✓ | ✓ | same |
| ⇧↑ ⇧↓ | ✗ nothing | ✗ | ✓ | ✓ | ✓ | same (2.1.311 has a gated effort binding here) |
| ⇧⌥← ⇧⌥→ | ✗ moves only | ✗ | ✓ (re-drag) | ✓ | ✓ | same |
| ⇧⌘← ⇧⌘→ | ✗ moves only | ✗ | ✓ (re-drag) | ✓ | ✓ | same |
| ⇧⌘↑ ⇧⌘↓ | not measured (no menu item; reaches Claude as `CSI 1;10A/B`) | ✗ | ✓ (re-drag) | ✓ | ✓ | — |
| ⇧Home ⇧End | ✗ moves only | ✗ | ✓ | ✓ | ✓ | same |
| ⌘A | ✗ the whole screen | ✗ | ✓ the prompt | ✓ the prompt | ✓ | same |
| ⌫ | ✓ | ✓ | ✓, deletes a selection | ✓ | ✓ | same |
| ⌥⌫ | ✓ word | ✓ | ✓ | ✓ | ✓ | same |
| ⌘⌫ | ✓ to row start (Duo's ^U) | ✓ | ✓ | ✓ | ✓ | same |
| fn⌫ (⌦) | ✓ | ✓ | ✓, deletes a selection | ✓ | ✓ | same |
| ⌥fn⌫ | ✗ kills to line end | ✓ word forward | ✓ | ✓ | ✓ | same |
| ⌃⌫ | ✓ a character | ✓ | ✓ | ✓ | ✓ | same |
| ⌃K ⌃Y | ✓ kill, yank | ✓ | ✓ | ✓ | ✓ | same |
| ⌘Z | ? Duo's Undo menu, not Claude's (Q-360) | ✓ Claude's undo (⌃_) | ✓ | ✓ | ✓ | same |
| ⇧⌘Z | ✗ | ✗ Claude has no redo | ✗ | ✗ | ✓ | same |
| ⌃A ⌃E | ✓ paragraph start/end | ✓ | ✓ | ✓ | ✓ | same |
| ⌃F ⌃B ⌃N ⌃P | ✓ | ✓ | ✓ | ✓ | ✓ | same |
| ⌃D ⌃H | ✓ | ✓ | ✓ | ✓ | ✓ | same |
| ⌃T | ✗ Claude's task list | same (kept) | same | same | ✓ transpose | same |
| ⌃O | ✗ Claude's transcript | same (kept) | same | same | ✓ | same |
| click | ✓ places the caret | ✓ | ✓, clears a selection | ✓ | ✓ | same |
| drag | ~ Claude selects, copies at once with indents | ~ | ✓ | ~ Claude's, beside Duo's | ✓ | same |
| double/triple-click | ✓ word / row (Claude) | ✓ | ✓ | ✓ | ✓ word / paragraph | same |
| ⇧-click | ✗ SwiftTerm's own selection | ✗ | ✓ extends | ✓ | ✓ | same |
| typing over a selection | ✗ inserts at the caret | ✗ | ✓ replaces | ✓ | ✓ | same |
| ⌘C | ~ Claude's copy-on-select; ⌘C copies SwiftTerm's | ~ | ✓ (Q-361 for wraps) | ✓ exact | ✓ | same |
| ⌘X | ✗ | ✗ | ✓ | ✓ | ✓ | same |
| ⌘V | ✓ bracketed paste | ✓ | ✓ replaces a selection | ✓ | ✓ | same |
| drag text in/out | ✗ (file paths only, DL-117) | ✗ | ✗ | ✗ | ✓ | same |
| Services, Look Up | ✗ | ✗ | ✗ | ✗ | ✓ | same |

## 6. The decision for Geoff (DL-274)

1. **Which strategy.**
   - **Recommended: 1 then 2.** The keys first; then Claude's own selection, driven by Duo, with no Duo marks in the terminal.
   - Alternatives:
     - 1 then 3 (Duo draws its own highlight; needs a design round);
     - 1 only;
     - 4 (not recommended).
2. **⌘↑ in a Claude terminal (Q-359).** Recommended: keep All Projects (DL-34), and give the prompt's start to ⌘↑ only while the box shows a multi-line prompt? Or always the prompt's start, as a Mac field does?
3. **Copy across soft wraps (Q-361).** Recommended: the screen text cleaned (indents stripped, wraps guessed from row widths), never the Ctrl+G flash. Or exact text with the view frozen for the peek.

No canvas yet. Strategies 1 and 2 add no Duo marks: strategy 2's highlight is Claude's own, the one a drag shows today. That's `rgb(38,79,120)` in Claude's dark theme, `rgb(180,213,255)` in its light theme, and ANSI cyan/blue in its ANSI themes. If Geoff leans to 3 or 4, their highlight or editor gets drawn on a Design canvas first (Light/Dark/Classic, every mark [P]).

## Files

- `probe/`: the probes.
  - `probe.mjs` and `mkcases.py`: keys into the prompt.
  - `probe2.mjs` with `mkcases2-4.py`: strategy 3's alignment, the mouse selection and strategy 2's synthetic drags. `show2.py` and `show3.py` print the results.
  - `keybytes/`: SwiftTerm's bytes per chord.
  - Run them from a scratch folder:
    - `npm i node-pty@1 @xterm/headless@6`;
    - `Spikes/chat-mode/scratch.sh <dir>` for the config;
    - set `WS`, `CLAUDE_CONFIG_DIR`, `ANTHROPIC_API_KEY=sk-ant-mock-key-0000000000000000000` and `ANTHROPIC_BASE_URL=http://127.0.0.1:9`;
    - for `probe2.mjs`, also `EDITOR=VISUAL=probe/peek.sh` and `PEEK_OUT`;
    - then `node probe.mjs <claude> kitty|legacy <cases.json> <out.json>`.
  - `keybytes/` builds with `swift build`, under the GPU lock `--shared`. Its `Package.swift` names the main checkout's SwiftTerm checkout.
- `results/`: the summarised runs quoted above.
