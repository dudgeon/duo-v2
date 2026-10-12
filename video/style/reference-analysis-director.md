# Reference analysis: the director film

The director film is an explainer made of infographics and motion graphics on the paper ground (Geoff, 2026-10-12: "Paper throughout"). Its references are Anthropic's own Claude Code explainers on the @claude YouTube channel, which Geoff pointed us to ("go find the explainer video they did about the Claude Code Projects feature"). The marketing films on the @anthropic-ai channel were looked at first and set aside: they're talking heads, screen recordings and art-directed pieces, not explainers.

Downloaded for private study into `~/Library/Caches/duo-video/refs/director/`; never committed, never used in the film. Contact sheets at 2 fps (1 fps for the shorter two). **We take their grammar, never their content**: no copy, no imagery, no Anthropic type or marks.

| Film | Channel, length | Why |
|---|---|---|
| **Getting started with Claude Code Projects** (`omihvjf0A2k`) | @claude, 4:33 | The feature our film acknowledges; the house explainer format |
| **Building verification loops in Claude Code** (`mQZB0l-rhxE`) | @claude, 3:08 | The same series; its diagrams are the closest thing to what we need |
| **Mods in Claude Code** (`yUuFvL1lK4k`) | @claude, 3:21 | The same series; code as the picture, with a highlight that walks through it |

## What they do

| | What we saw | What we take |
|---|---|---|
| **Ground** | Warm off-white, flat, no grid (sampled `#F3F2EB`). Sections that change subject get one flat field of a darker warm tone (a beige card, "Hand off your manual checks"). UI floats on the ground with no desk and no window shadow, or on one flat blue field. | **Our paper ground already matches** (`#F4F2EC`), so we keep it, grid and all (house style). One darker warm field for the big turns (the problem, the tease); never a gradient. |
| **Type** | A serif display face for headings, set small, top left, with lots of air ("When to reach for a project", "Verifying a change"). Under it, a small sans list that builds one line at a time: each line arrives grey and darkens to ink as it's said. Node labels in a plain sans. | **Headings small and top left, never centred and large.** One display face for headings, our UI sans for labels and lists. **Lists build line by line, grey to ink, on the voice's words.** We don't copy their serif: it's Anthropic's brand face. Our display choice is a style-frame question. |
| **Colour** | Pastel fills that carry meaning, not decoration: grey-beige for the prompt (`#E5E4D9`), sage for the work steps (`#CBD4BD`), pale blue for checking (`#C2D1DD`); a pink tint for a failed check, sage for a pass. Arrows and lines in warm grey (`#75766C`). Ink for text. | **Colour is a role, kept the whole film**: one fill for Geoff (the PM), one for the director, one for workers, one for checks and reports. Pastel fills, warm-grey lines, ink text. Duo's needs-you orange stays the one accent, for "needs you". |
| **Diagrams** | Built from the idea itself, one node per spoken step: *Prompt → Gather context → Take action → Verify results*, each box arriving as it's named, then a loop-back arrow drawn last. A grid of empty outlined cells that fills with colour as checks run, column by column, labelled above (Tests, Type checks, Linters, Manual QA). Rounded rectangles with a small radius, no borders on filled nodes, no shadows, no icons. | **Every diagram is the mechanism, drawn as it's explained**: the tree of PM, director and sessions; the timeline; the grid of work done. **Counts are cells that fill, not numbers that spin.** Nodes are flat filled rounded rects; arrows are thin warm-grey lines with small solid heads, routed orthogonally with rounded corners. |
| **Pointing** | No markers or circles. Emphasis is the grey-to-ink change, a fill appearing, or a highlight band over a span of code that walks from token to token (Mods). A real cursor in the UI shots. | **Point by changing the thing itself**: fill a node, darken a line, walk a highlight. No callout rings (taste.md already bans them). |
| **Motion** | Calm. A node appears with a short fade and a few pixels of rise; arrows draw along their path; text types in a prompt box. Section changes are often cuts or dissolves to the presenter, which we can't use. Holds of 2 to 4 s on a finished picture. | **The same calm build, with no cuts**: each scene's last picture is the next one's first, and something carries across (the tree, the prompt card, the timeline). Arrows draw along their path; nodes rise a few pixels with a short fade; prompts type. |
| **Pace** | One idea on screen at a time; something new every 2 to 4 s while the voice talks; long holds on lists. | **2 to 4 s per new element, on the words.** |
| **Composition** | Content sits in the left or centre two-thirds; the right third is often empty. A diagram uses less than half the frame's height. | **Leave room**: diagrams at a comfortable size with margins, never edge to edge. |

## Rules from the motion-graphics article

Geoff's link (@0xMovez, 2026-09-27) is an X Article, "How to build motion design studio with Opus 5.5". Its point is that a prompt is 10% of a film and the harness is the rest. Most of its harness is what this pipeline already does: each frame is a pure function of time (`lint.mjs`), seeded noise only, banned defaults (taste.md), a reference before a look, and real assets. What we add for this film:

1. **Write the state list, not the vibe.** Before building a scene, list its states on the voice's timeline (which node, arrow or cell appears on which word). The Shot: note says what we see; `shots.json`'s beats are the state list.
2. **One shape never cuts.** Each scene's anchor shape (the director's node, the prompt card, the timeline) morphs in size, position and fill into the next scene; it isn't replaced.
3. **Springs, not easing curves.** Closed-form damped springs, so any frame can be drawn on its own. Snappy for nodes, heavier for big type and the camera; a tiny overshoot on UI-like nodes and none on type.
4. **Text enters after a morph starts and leaves before the next one.** No overlapping text during a swap.
5. **Critique before a full render.** Make a contact sheet of one frame per beat. Score it 1 to 10 on readability at phone size (360 px wide), motion, variety and sync with the voice. Fix the three worst problems, and repeat until each scores 8 or more. Only then render.
6. **The phone test.** Every label must read at 360 px wide; the smallest text is about 28 px at 1080p.

## Banned in this film

Everything in `reference-analysis.md`'s list, plus:
- **Icons as decoration**, such as robot heads, gears or sparkles for "AI". A session is a rounded rect with its task on it.
- **Org-chart clip art and stick figures.** Geoff is a node with his role on it, like every other node.
- **Spinning counters.** Numbers fill as cells, or are set once.
- **Superlatives on screen**, and any Claude-isms in on-screen words (Geoff, 2026-10-12).
