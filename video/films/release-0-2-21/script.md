# Duo 0.2.21 release film: Review in Markdown
<!-- Synced from the script Doc at rev 8 on 2026-10-29 by pipeline/sync.mjs; edit the Doc, not this file. -->

Oct 28, 2026 · @Geoff Dudgeon

A film for the 0.2.21 release notes, under a minute, in your voice and the intro's style (the desk, the High Sierra wallpaper, the title card as its poster, outline traces, the camera moving through the real app, the score bed), with captions of each line. Each build reads this doc. The rules below are what the build understands; anything else is notes for us. I drafted the lines and Shot: notes overnight (Oct 28); edit anything, and I'll rebuild.

## How to write it

- **A scene is a `###` heading:** `### S1 · Title (about 20 s)`. Keep the `S` number at the front; it ties the scene to its shot. The time is a target; the real length comes from the voice.
- **Each bullet under a scene is one voiceover line,** voiced and checked on its own. One sentence or clause per bullet; long lines get rushed.
- **`Shot:` is a plain-English note of what we see.** Say what the viewer should notice, not how to animate it. I turn it into captures, camera moves and callouts.
- **Callouts:** if a line names a feature that should be pointed at, put the phrase in *italics*. That's where the cursor clicks and the outline lands.
- **Only real things.** Everything on screen is the real app on sample data (Sam's shelf-scan project, from the intro), so say only what Duo 0.2.21 actually does.
- **Anything else** (a paragraph, a question, a `> note`) is ignored by the build. Use it freely.
- **Every Shot: note is a checklist.** The build lists each thing a Shot: note asks for, and its report names anything not built yet. A stand-in is never silent.
- **No shot ever cuts to the next.** Every scene change is navigation in the app or a motion graphic where something carries across; the build refuses a plain cut or dissolve.
- **Topic:** is left out on purpose: in a film this short the topic list would cover the picture at every scene change (Q-296). Add `Topic:` lines to bring it back.

## The brief

|  |  |
| --- | --- |
| **One sentence** the viewer should remember | Markdown files in Duo now take comments and suggested edits, and @claude in a comment gets Claude to answer in the thread. |
| **Who it's for** | People who already use Duo, reading the 0.2.21 release notes; and anyone they pass the link to. |
| **Length** | Under a minute: about 120 words. |
| **How it should feel** (and what it must not feel like) | Like the intro: calm, real, you showing a friend what you built. Not a sales pitch, no superlatives. |

## Scenes

### S0 · Title (about 7 s)

- In 0.2.21 I added comments and suggested edits to Markdown files, a lot like Google Docs.

Shot: the intro's title card, built the same way: the Duo icon builds itself on the High Sierra wallpaper, then settles beside "Duo 0.2.21" and the line "Review in Markdown: comments, suggested edits and @claude", framed as one composition. That settled frame is the film's thumbnail. Then the words wipe back into the icon, the menu bar and Dock slide in, the icon drops into its Dock slot, and Duo's window opens out of the Dock onto the desk, on Sam's PRD with this morning's review in the margin.

### S1 · Comments (about 12 s)

- Comments sit in the *margin*, next to the text they're about,
- and when a thread's done, I can *close it and keep it*, or delete it.

Shot: the camera pushes in on the PRD in the right pane. On "margin" the outline traces the margin's cards (Ravi's and Lena's) beside their highlighted text. Then Sam adds one: the cursor drag-selects "Fixing a flagged book takes one tap", ⌥⌘M shows as keycaps, a comment card opens in the margin and "Lena, can you mock the one-tap fix for Thursday?" types into it, and the cursor clicks Post. On the second line the cursor clicks Lena's thread (answered already), its card opens with Close and Keep and Delete, the outline traces the two buttons on "close it and keep it", and the cursor clicks Delete on "delete": the thread goes and its text stays.

### S2 · @claude (about 16 s)

- If I mention @claude in a comment, it goes to the session I'm working in -- the *pill* shows which one --
- Claude makes the change and answers right in the thread.

Shot: still on the PRD. The cursor selects the glare requirement ("Warn about glare before the photo is taken…"), opens a comment and types "@claude can you make this one testable? Denise's feedback is in research/feedback." As @claude is typed, To and the session pill appear under the field ("Auto-add decision · at prompt"); on "pill" the outline traces it. The cursor clicks Post: the card says Sent. The camera moves left to the middle pane, where the comment arrives in the Auto-add decision chat as Duo sends it and Claude starts working; the card now says Claude is replying. On the second line the camera comes back to the editor: the requirement has changed in place, and Claude's reply sits in the thread, signed in Claude's green.

### S3 · Suggest Edits (about 10 s)

- With *Suggest Edits* on, my edits become suggestions -- and I can *accept* or *reject* each one.

Shot: the cursor clicks Suggest Edits in the review bar: its dot fills and the file gains its `suggest-edits: true` line. Sam changes "80% of scans" to "85%", and it shows as his suggestion, the old text struck through and the new underlined in his colour. On "accept" the pointer rests on Jo's suggestion (20 → 15 seconds), its label opens, and the cursor clicks Accept; on "reject" it does the same on Ravi's added words and clicks Reject.

### S4 · Example, cut for time: Markup (Q-301; rename to bring it back)

- The Markup menu switches to a simpler view when there's a lot going on.

Shot: the cursor opens Markup ⌄ in the review bar, with its real items (All Markup, Simple Markup, No Markup, Original, Show Closed Comments), and picks Simple Markup: the marks fold away and a bar in the left margin shows each changed line.

### S5 · Try it (about 6 s)

- It's all plain text in the file -- update Duo and give it a try.

Shot: the camera pulls back to the whole window, then Duo's window folds back into its Dock icon, and the title card comes back as it opened, with a last line under it: "Duo › Check for Updates…". Held about 3 s after the line.

## The voice

The narrator is your own voice, the fine-tuned VoxCPM2 clone the intro uses (DL-173). The build reads this table: write the word as it appears in a line, and how it should be said. Add a row whenever a line comes out wrong.

| Written | Said |
| --- | --- |
| 0.2.21 | zero point two point twenty-one |
| @claude | at Claude |
| duo2 | duo two |
