# Duo 0.2.22 release film: Classic and voice input
<!-- Synced from the script Doc at rev 24 on 2026-11-01 by pipeline/sync.mjs; edit the Doc, not this file. -->

Oct 31, 2026 · @Geoff Dudgeon

A film for the 0.2.22 release notes, about a minute, in your voice and the intro's style (the High Sierra desk, the title card as its poster, outline traces, the camera moving through the real app on sample data, the score bed, captions in their own band). Classic gets about 15 s, voice input about 45 s. Each build reads this doc; edit anything and I'll rebuild.

## How to write it

- **A scene is a `###` heading:** `### S1 · Title (about 20 s)`. Keep the `S` number at the front; it ties the scene to its shot. The time is a target; the real length comes from the voice.
- **Each bullet under a scene is one voiceover line,** voiced and checked on its own.
- **`Shot:` is a plain-English note of what we see.** Every item in it is built, or the report says it isn't.
- **Callouts:** a phrase in *italics* is where the cursor clicks and the outline lands.
- **Only real things.** Everything on screen is the real app on sample data (Sam's shelf-scan project), so say only what Duo 0.2.22 does.
- **No shot ever cuts to the next.** Every scene change is navigation in the app or a motion graphic.
- **Anything else** (a paragraph, a `> note`) is ignored by the build.

## The brief

|  |  |
| --- | --- |
| **One sentence** the viewer should remember | Duo can look like v1 again, and you can talk to Claude in chat or the terminal, a phrase at a time, and nothing sends until you say so. |
| **Who it's for** | People who use Duo, reading the 0.2.22 release notes. |
| **Length** | About 60 s: Classic about 15 s, voice input about 45 s. |
| **How it should feel** | Like the intro and the 0.2.21 film: calm, real, you showing a friend. No superlatives. |

## Scenes

### S0 · Title (about 6 s)

- Two new things in this release.

Shot: the intro's title card: the Duo icon builds itself on the High Sierra wallpaper beside "Duo 0.2.22" and two lines, "Voice input, and Classic" over "A mic in chat and the terminal, and the v1 paper look". That settled frame is the thumbnail. The words wipe back, the icon drops into the Dock, and Duo's window opens out of it on Sam's shelf-scan project, in Light.

### S1 · Voice in chat (about 18 s)

- There's a *mic* in the chat box now --
- macOS waits to hear a whole phrase before writing it, so the words land a phrase at a time,
- and nothing sends till I press Return.

Shot: the camera pushes in on the Auto-add decision chat's composer and the mic at its right end. The cursor clicks the mic: it shows the level bars while it listens (DL-272), and the hint row keeps only the keys. This part is a recording of the real app running the real dictation: we hear you say "Can you check the glare cases against Denise's photos, and tell me which ones still fail?" and the words land in the composer as the recognizer settles them, a phrase at a time, with the real delay of a run on this Mac: the meter moves for a few seconds with nothing written, then the first phrase lands, then the second. Nothing is sent. On "press Return" the Return key shows as a keycap and the message goes into the chat.

### S2 · Voice in the terminal (about 15 s)

- In the terminal the mic sits beside Claude's prompt, or I hold *down Shift, Command and D* to talk.

Shot: the cursor clicks the Tighten PRD goals tab: Claude Code's terminal, with the small mic beside its input box. On "Shift-Command-D" the keys show held as keycaps; recorded from the real app, the mic turns into three level bars that move as you say "Add a glare warning to the scan screen, and keep it under ten words", and each phrase lands in Claude's prompt as it settles. The keys let go and the mic comes back. Nothing is sent.

### S3 · No microphone (about 5 s)

- With no mic connected, it goes faint and struck through.

Shot: back in the chat, the camera close on the composer: the mic is faint, with a line through it, as it is when no microphone is connected.

### S4 · Classic (about 13 s)

- If you miss the old look, *Classic* is under Settings, Appearance --
- warm paper, an orange line on the pane you're using, and the old Dock icon.

Shot: Duo's Settings window opens over the main window. The cursor clicks Appearance's menu (Match System, Light, Dark, Classic) and picks Classic: the main window turns to Classic's warm paper behind it, and so does Settings, whose line under Appearance reads "Classic: legacy Duo's warm paper look. Always light." The cursor closes Settings. On "orange line" the camera moves to the top of the middle pane, where the orange rule marks the pane in use; on "Dock icon" it pulls back to the desk, where Duo's icon in the Dock has the Classic colours.

### S5 · Try it (about 5 s)

- Update Duo and give it a try.

Shot: the camera pulls back to the whole window, which folds back into its Classic Dock icon, and the title card returns with the Classic icon with "Duo › Check for Updates…" under it. Held about 2 s after the line.

## The voice

The narrator is your own voice, the fine-tuned VoxCPM2 clone (DL-173). The dictation the app hears is your voice too, from the same model.

| Written | Said |
| --- | --- |
| 0.2.22 | zero point two point twenty-two |
| v1 | vee one |
| Shift-Command-D | shift command D |
