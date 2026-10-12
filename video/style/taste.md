# What Geoff has rejected, and what he chose

Read this before proposing any look, transition, callout or voice for the intro video. Each entry below is a direction Geoff gave in review between 10 and 12 Oct 2026, in his words where we have them. It's here so the direction travels with the repo, not only in one session's memory.

## The rule under all of them

Generic defaults read as made by AI. The motion references Geoff sent (three articles on motion design for product films) make one point: a model falls back on safe defaults unless it's given a reference to analyse and a director's brief. So:
- analyse a reference (palette, type, composition, pacing, motion, texture) before proposing a style;
- prefer real assets (Apple's own wallpapers, the real app on sample data) over drawn imitations;
- show two or three crafted options as real frames or motion from the film, not quick variations;
- design on a Design canvas with the Duo design system.

## Standing references

- **"Dynamic workflows in Claude Managed Agents"** (Claude Developers, Oct 9, 2026, https://x.com/claudedevs/status/2108591328732856655). Geoff, 2026-10-12: "Save this link/video as a future style reference — esp the animation style." Its grammar is in `reference-analysis-director.md`: one persistent actor, ink line art, hollow-to-filled states, diagrams made of the data, morphs and fan-ins instead of cuts, and captions that darken while their line is current.

## Looks

| Rejected | His words | Chosen instead |
|---|---|---|
| Generated wallpapers, four rounds | "really bad", "low effort", "not visually interesting" | Real Apple nature wallpapers: High Sierra |
| Box callouts: spotlight, ring, lift, brackets | "extremely low effort", "sloppy and amateur" | An outline that traces the real UI ("the outline is better than before") |
| Reference-language callout studies: a marker loop, a mini window, both | "all low effort and bad", then "still just visually boring and bad; I don't want the feature pop out" | Never pop a feature out into a window or lift it. Research real motion-design technique, then show motion, not stills |
| The v2 prototype: a pan instead of the morph he wrote, PowerPoint and Word left out, a basic browser page | "My script explicitly said I wanted an animated transition…" | What the Shot: note says, built as written; a stand-in is announced up front |

## Cuts

- **No shot ever cuts to the next, and a plain crossfade counts as a cut.** If the next shot is somewhere else in the app, get there by using the app: pull back to show where to click, click, then push in. If it's a new idea, use a motion-graphics transition. His words for S8: "this is the point where duo should fade away".

## Shot: notes

- **A Shot: note is a spec, not a suggestion.** Every item in it is built, or the report says it isn't, up front. A quiet substitute reads as ignoring what he wrote.

## The poster

- **The still a player shows before play is the title card.** His words: "be sure the thumbnail/still view of the video (on this run and all future runs) is the title card, showing the icon, title, and sub-title — even if this is just one frame that disappears when the user presses play". The film's frame 0 is S0's settled frame (Film.tsx draws it at the first scene's `poster` time), `out/thumbnail.png` is the same frame and is the file's cover art, and the build fails if frame 0 isn't the title card.

## Words on screen

- **The S0 line under "Duo":** "descriptive and expansive", with no superlatives or subjective adjectives. He then wrote his own line.

## The voice

| Rejected | His words | Chosen instead |
|---|---|---|
| The first designed voices | "sterile", "too high pitched" | M2, a baritone |
| M2 | "somber"; asked for "20% more upbeat" | Round 1's B, brighter |
| Round 1's B | "too deep; we can go even quicker, say 10%" | B-light-133 at tempo 1.1 (the house voice) |
| The house voice | (he wanted his own) | A clone of his voice: zero-shot Qwen (DL-171), then the fine-tuned VoxCPM2 (DL-173) |

Before sending a voice, check its pitch and expressiveness.
