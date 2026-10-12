# Duo director film: script
<!-- Placeholder script so the film builds end to end before its real scenes exist. -->

## How to write it

- **A scene is a `###` heading,** like `### S1 · Title (about 10 s)`. Keep the `S` number at the front; it ties the scene to its shot in `shots.json`. The time is a target; the real length comes from the voice.
- **Each bullet under a scene is one voiceover line,** voiced and checked on its own. One sentence or clause per bullet; long lines get rushed.
- **`Topic:` is the scene's name in the topic list.** One short line under the heading. `Topic: same` keeps the previous scene's topic.
- **`Shot:` is a plain-English note of what we see.** Say what the viewer should notice, not how to animate it. Every Shot: note is a checklist: its `requires` items in `shots.json` name what builds each thing.
- **No shot ever cuts to the next.** Every scene after the first names its way in (`transitionIn`).
- **Only real things.** Say only what Duo actually does today.
- **Anything else** (a paragraph, a question, a `> note`) is ignored by the build.

### S1 · The director (about 10 s)

Topic: The director

- One session runs the others, so you only talk to one.

Shot: A paper card with the scene's title in ink, standing in for the director scene.

### S2 · Delegating (about 10 s)

Topic: Delegating

- It hands the work to new sessions and tells you when it's done.

Shot: The paper card carries on, with the next scene's title in ink.

## The voice

The narrator is Geoff's own voice, as for the intro film (README, "The voice"). The build reads this table: write the word as it appears in a line, and how it should be said.

| Written | Said |
| --- | --- |
| duo2 | duo two |
