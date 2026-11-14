# A power user's Duo v1 feedback, checked against Duo v2

Research, 2026-11-02, branch `research/power-user-audit`, built from `1f974b71` (main, the 0.2.23 line). Geoff shared a summary of one power user's v1 requests (called "a power user (v1)" here; nothing identifying goes in this public repo). Each ask was **tested on a build of main**, not read off the docs. Records: F-534 to F-536, Q-426, Q-427, ENH-315 to ENH-317.

## The table

| # | Ask (v1) | Status in v2 | Evidence | Gap |
|---|---|---|---|---|
| 1 | **Terminal literacy**: Duo should be an on-ramp to real terminal fluency, not a GUI that insulates PMs from it. | **Addressed, by design** | Every session can be a real terminal or a chat: `duo2 session chat on\|off\|toggle`, a per-session toggle and a default (DL-258: a fallback to the terminal is never papered over, you flip back by hand). Classic style (DL-252) brings back v1's terminal look. ⇧⌘T opens a plain shell tab. Chat mode is the abstraction; the terminal is one click away, same Claude, same session. | None to build. The *on-ramp* part (something that teaches terminal habits) has no feature and nobody has asked for one. Whether it should be a goal is Geoff's; not asked as a question, since the current design already serves both kinds of user. |
| 2 | **Don't reinvent Google Drive** (comments, access control). | **By design, mostly** | Duo keeps documents as plain files and git; sharing and access control are left to Drive and GitHub. Review and comments in Markdown live in the file itself (DL-236, DL-237); no accounts, no permissions model. Word files open as Word files (DL-233), pptx and docx convert both ways (DL-123), and comment round-trips with Google are *left out on purpose* (DL-290, F-497, ENH-308). Duo Decks, the nearest thing to "building our own Slides", is hidden in release builds (DL-307). | Two soft spots: Duo's own comment threads (Markdown review, DL-236) are a small collaboration layer Drive already has; and ENH-307/308 (upload to Google Slides, comment round-trip) are the Drive bridge she'd want. Her point is strategic, so no change; Geoff may want to say it back to her. |
| 3 | **File auto-refresh**: a doc open in the editor picks up Claude's edits on disk; v1 also showed a diff banner for bigger changes. | **Addressed; the big-change banner is not** | Tested live (F-534): in-place edit and atomic-rename write both reach the editor in under 3 s, highlighted as Claude's. A 100 % rewrite also reloads silently with the change highlighted ([capture](power-user-v1-feedback/large-change-reload.png)). Unsaved edits plus an edit on other lines **merge**; an overlap shows the Keep Mine / Use Theirs bar, keeps both versions in history and pauses saving ([capture](power-user-v1-feedback/conflict-bar.png)). DL-77. | v1's "most of this document was replaced" banner (LR-32: Keep mine, Load new, View diff) has no v2 equivalent: a clean document that Claude rewrites wholesale changes with no notice beyond the highlight. Q-427, ENH-315. Small quirk: `duo2 doc status` says "unsaved edits" after a clean reload (F-534). |
| 4 | **Browser**: open web URLs in the system browser, not Duo's; Duo's browser for local files only. | **Addressed** (the default already is that) | DL-3: only files and localhost open in Duo; every other `http(s)` link goes to the system browser unless the host is on the allow list, which is **empty on a new install** (`duo2 browser sites`: "No sites allowed yet (localhost always is)"). Tested: `duo2 browser open https://example.com` made a tab that holds the page and offers *Allow* or *Open in Browser*, loading nothing. Links from a document, the chat, an HTML page and the terminal all route through `openLink` or the terminal's default handler (F-535). | No setting says "never use Duo's browser" (even for allowed sites); the terminal's link click always goes to the system browser, even for an allowed host. A user who opens ⌥⌘T on purpose still gets a Duo tab. Q-426, ENH-316. |
| 5 | **Voice dictation** (low priority): past about 90 s, Duo went blank or showed a terminal error. | **Not reproduced** (open for the real microphone) | Synthetic speech (macOS `say`, 129 s, 350 words) fed through the same recognizer at real-time pace, into the Markdown document and into the chat composer: all 25 phrases landed in both, no error, no blank, memory flat to falling (about 230 MB to 120 MB for the document run, 237 MB to 212 MB for the composer run) (F-536, [capture](power-user-v1-feedback/composer-after-129s.png)). | Not exercised: a real microphone (no mic on this Mac), the terminal-prompt target (needs a real Claude prompt on screen), Bluetooth route changes, a person's pauses (the only timer is "nothing heard for 15 s"). She never said which of the three targets she was in, nor which transcriber (Geoff's question to her, unanswered). ENH-317. |
| – | *Data point*: analysis to leadership deck through Claude and Duo. | Noted | A concrete PM job for Duo Decks (DL-267 and the P3 work), which is hidden in release builds for now (DL-307). | None: the unhide decision is Geoff's. |
| – | *Multi-window* (she uses it to switch between projects) | Separate worker | Researched in `docs/research/multi-window-2026-11.md` (F-537, plan and slices 0 to 3 on main); not built. | Not covered here. |

## Test 3 in detail: outside changes to an open document

Isolated Duo (own support folder, scratch config, stand-in `claude`, `open -g` style launch, never Geoff's Duo). A Markdown note open in the editor; the file written on disk by a script the way Claude's Edit and Write tools do (in place; temp file renamed over it).

| Step | What happened |
|---|---|
| Small change in place, no unsaved edits | In the editor within 3 s, highlighted. No banner. |
| Small change by atomic rename | Same. |
| 100 % rewrite, no unsaved edits | Reloaded and highlighted; **no banner** (v1 showed one above half). |
| Unsaved edit, outside change on other lines | Merged: both there, nothing asked. |
| Unsaved edit and an outside change on the same line | Bar "Changed on disk where you're editing (line N). Both versions are kept. Saving is paused until you choose", with **Use Theirs** and **Keep Mine**; the line is marked "changed on disk". History keeps `conflict-mine` and `conflict-theirs`. |

## Test 4 in detail: where a link goes

| From | Goes to | How known |
|---|---|---|
| A link in a Markdown note or a task | the system browser, unless the host is on the allow list, then a Duo tab beside the note | code (`AppModel.openLink`, DL-3) |
| A link in the chat | the same function (`openChatLink`) | code |
| A link in a local HTML page | the same function (`onLinkOut`); the page itself loads nothing remote (DL-175) | code |
| A link clicked in terminal output | SwiftTerm's default handler: the system browser, always | code (`TerminalView.openDefaultLink`) |
| `duo2 browser open <site>` or ⌥⌘T and an address | a Duo tab; a site not on the list shows *Allow* or *Open in Browser* and loads nothing | **live** |
| `duo2 browser sites` | the list; empty by default, localhost implied | **live** |

Settings › Browser has one control: *Allowed sites*, whose Edit… opens the plain list file. DL-99 added ⌥⌘T and ⌘L; DL-124 added uploads, downloads, print, popups, zoom for allowed sites. No click was made on a real link, because that would launch the system browser and take focus; the routing above is from the code and the checks, and the live part shows the browser tab's side.

## Test 5 in detail: long dictation without a microphone

How: `duo2 voice file` (and the harness's `voice-file:`) runs an audio file through the real `VoiceInput` and the real recognizer (SpeechAnalyzer), at the pace it was spoken (`DUO_VOICE_FILE_REALTIME=1`), with `DUO_VOICE_TRACE=1`. The audio: 25 sentences from macOS `say`, 129 s, 350 words.

| Target | Result |
|---|---|
| Markdown document (`--doc`, the formatting bar's path) | Listening for the whole file, 674 recognizer results, words arriving a phrase at a time, the last phrase ("number 25") in the document, state back to off. No error line, no blank. |
| Chat composer | Same: the composer's text ends at "number 25", state idle, no error; the screenshot shows the composer scrolled to the end. |
| Memory | Document run: 229 MB while listening, then 118 to 125 MB after the recognizer let go at about 80 s. Composer run: 236 MB, then 213 to 218 MB. No growth. |

This says the *software* path past 90 s is sound with a steady stream of speech. It does not say her case is fixed: see the table's gap.

## Where this leaves the open items

- Q-426 and Q-427 are for Geoff.
- Nothing was changed in the app. The one thing that looks like a bug (the status text) is cosmetic and not certain enough to touch.
