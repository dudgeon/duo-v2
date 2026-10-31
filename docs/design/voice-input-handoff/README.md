# Voice input: the handoff

Geoff approved this on 2026-10-30 (DL-261), on the canvas https://claude.ai/artifact/3JgWhruXuK21r826nGG4JW and by buttons. The recognizer is Apple's, on device, with no model of Duo's own (DL-260). The research behind it is `docs/research/voice-input.md`; its Parakeet recommendation was not taken.

The four boards in `screens/` are the target, rendered at 2× in `screens/png/`. The canvas sources are in `canvas/`. The terminal boards A to E there are context, not targets: A's delivery (a phrase at a time) and C's placement C3 were chosen and are drawn together on `terminal.html`.

There are no new tokens. Everything uses `pane`, `ground`, `selected`, `rule`, `controlEdge`, `text`, `text2`, `chatGround`, `console`, `consoleRule`, `consoleText`, `consoleText2` and `tuiInputBorder`. The mic is SF Symbol `mic` (the boards draw a stand-in stroke), 14 pt in chat and 12 pt on the console.

> **Amended by DL-264 (Geoff, 2026-10-30).** The terminal mic is not on the bottom rule: it is today's subtle mark in a 4-column margin Duo keeps beside Claude's input box, centred on the box's text rows (`proof/dl264-*.png` are the target captures; `screens/terminal.html` is kept as drawn, for its states and failure modes). With no microphone, the mic stays, faint and struck through, with the tooltip "No mic detected · connect one to use transcription" (DL-265, which replaced DL-264's hidden). Return and Esc while dictating: DL-263.

## Screens

| Screen | What it settles |
|---|---|
| `composer.html` | The chat mic inside the field (B; A, the hint-row chip, is not chosen) and every state: at rest and hovered, listening, holding ⇧⌘D, finishing, done, while Claude works, the speech model downloading, the microphone off, blocked by a profile, and the stopped and can't-start lines. |
| `composer-appearances.html` | Listening in Light, Dark and Classic. |
| `first-press.html` | Duo's sheet before macOS asks, the usage strings, and what Duo shows for each permission state. |
| `terminal.html` | The terminal mic on Claude's input box's bottom rule; listening; the box growing; no box on screen; the failure modes the build tests. |

## Behaviour (what a picture can't show)

**The engine** (`Voice/`, DL-260).
- SpeechAnalyzer with SpeechTranscriber (macOS 26), progressive results. Where it has no model for the locale, SFSpeechRecognizer with `requiresOnDeviceRecognition`.
- `AVAudioEngine` input, converted to the analyzer's format. No audio is written to disk.
- States: idle → (asking) → preparing (model download) → listening → finishing → idle; plus unavailable, denied, restricted and failed. Each has a line on `composer.html`.
- Volatile results are partials; finalized results are settled phrases.

**Chat.**
- Words go in at the caret: settled text in `text`, the volatile tail in `text2` (replaced in place as it changes). The whole dictation is one undo group.
- Typing while listening finishes the dictation, then types.
- Return while listening finishes, lets the last words land, then sends (DL-263, amending DL-261's "Return keeps the text"); in the terminal it presses Claude's Return after the last phrase is pasted. Esc discards the dictation (not Claude's turn). Stop still stops Claude.

**Terminal.**
- Each settled phrase is one bracketed paste (`TerminalSession.bracketed()`, as `duo2 send text`), with a space between phrases. The volatile tail is never sent.
- Duo never presses Return on its own: Return pressed while dictating finishes, lets the last phrase land, then presses Claude's Return (DL-263). Esc ends the dictation and doesn't reach Claude (DL-263).
- Before each paste Duo reads the screen. Claude's input box must be on screen; a question or picker must not be.
- When a question appears, listening stops, the unsent words go to the clipboard, and a tooltip-style notice shows at the mic's last place for 6 s: "Voice input stopped: Claude asked a question. Your words are on the clipboard."
- While Claude works with its prompt on screen, phrases go in as typing does.
- A shell tab has no mic, since it has no input box. ⇧⌘D still pastes phrases at the shell's prompt.

**The terminal mic's placement** (the exception to "Duo draws nothing inside the terminal", DL-261).
- **Where.** The input box is the lowest run of rule rows (box-drawing characters) with Claude's prompt marker above. The mic lies on its bottom rule, its right edge 2 columns in from the right corner.
- **Its patch.** A 24 × 18 `console` patch breaks the rule.
- **When it hides.** It hides on any frame where those cells hold anything but rule characters, where no box is found, or where the view is scrolled back from the bottom.
- **Re-anchoring.** It re-anchors on every screen update: the box growing, a slash or @ menu, a resize, a font zoom.
- **Clicks.** Only its own rect takes clicks.

**Keys and menu.**
- **⇧⌘D, Edit › Start Voice Input / Stop Voice Input** (amends DL-34). Duo's item is named apart from macOS's Start Dictation….
- A tap toggles. Held past 0.3 s it is hold-to-talk, ending on release.
- It acts on the focused session: chat's composer or the terminal.

**Permissions** (DL-260).
- The first press shows Duo's sheet (SheetCenter). Continue asks macOS for the microphone, and for Speech Recognition only on the fallback.
- Not Now asks nothing.
- Denied: "Duo can't use the microphone." with Open Privacy Settings. Restricted: the mic dashed with the administrator line.
- Scripted and isolated runs never ask. `duo2 voice start` says the microphone isn't available.
- Release signing gains `com.apple.security.device.audio-input`, `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription`, with the strings on `first-press.html`.

**`duo2` (DL-71).**
- `duo2 voice start|stop|status [id]` does what the mic does.
- `duo2 voice file <audio> [id]` feeds an audio file through the same path into the session's composer or prompt. It is the scripted twin the checks use.
- The mic button, the terminal mic and the menu item name `voice start` / `voice stop`.

## Tests the build owes (Geoff: "test to make sure it does not occlude other text … and other failure modes")

- DuoChecks for the state machine, the phrase splitter (settled vs volatile), the paste text, and the input-box finder.
- The finder runs on recorded screens from 2.1.219, 2.1.284 and the latest: empty box, multi-line box, text to the edge, slash menu, @ menu, a permission question, `/model`'s picker, scrolled back, a narrow pane, the effort label in the top rule. Every case asserts the mic's cells are rule characters or the mic is hidden.
- A live check feeds a recorded audio file through `duo2 voice file` into an isolated Duo. It runs on Haiku for any Claude turn and never touches the real microphone.
