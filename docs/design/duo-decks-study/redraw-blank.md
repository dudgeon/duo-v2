# The deck preview went blank after an edit

The P3 walk (card "the slides redraw as you type") saw the slides pane under the deck bar blank grey in every capture taken after a valid edit; captures with no edit, or after an edit with a checker problem (no redraw: the last good drawing stays), drew the slides. The question was whether the redraw really left the pane empty or the capture (WebKit's snapshot, F-120) missed it.

**Verdict: a real bug, not a capture artefact.** There were two causes, and both are fixed.

## What the page's DOM showed

The probe is the harness action `deck-probe[:<label>]`, which prints `__duo.probe()` on stderr. It was run on an isolated background instance with the sample deck in a split tab, and `user-type:86%=>88%` made the edit. Each entry below gives the first three slides' `[width, height, top]` from `getBoundingClientRect`.

| | visible container | slides | slide tops | page height | visibility |
|---|---|---|---|---|---|
| before the edit | `#host`, relative | 9 | 16, 296, 576 | 2519 | visible |
| 1 s and 3 s after the edit (old code) | the element with id `spare`, relative | 9 | **796**, 1080, 1364 | **3331** | visible |
| after the edit (fixed) | `#host` | 9 | 16, 296, 576 | 2519 | visible |
| after a second, on-disk edit (fixed) | `#host` | 9 | 16, 296, 576 | 2519 | visible |

The new slides were drawn and visible, but they started a viewport (780 px) below the top of the pane. What filled the pane was the old drawing's element: hidden, empty, and `min-height: 100vh`. Waiting longer changed nothing (the 1 s and 3 s probes are the same), so this is not timing (hypothesis d). The containers were not left hidden or at zero size (a), and the renderer was not drawing lazily (b): `listMountStrategy` isn't windowed and the sample deck has fewer than 12 slides, so no animation-frame wait applies.

## Causes

1. **The hidden drawing stayed in the page's flow.** `.staged` hides the spare container with `position: absolute`, but pptx-renderer sets `container.style.position = "relative"` inline every time it renders, and `destroy()` doesn't clear it. The inline style beat the class, so after the swap the old host, now staged, sat in the flow above the new slides.
2. **Overlapping redraws** (hypothesis c, in the page). If `show(bytes:)` arrives while a refresh is still drawing (two edits close together, or a typed edit followed by a disk edit), both refreshes draw into the same `#spare`, and each swap clears the other's drawing. DuoChecks reproduced this with the serialization removed: zero slides in the visible container.

Also fixed: after a swap the visible container kept the id `spare`, so the stylesheet's `#host …` rules (16 px between slides, the slide's rule, the Make Templates grid) stopped applying to it.

## Fix (`Vendor/pptx-renderer/deck.html`, `deck.js`)

- `.staged { position: absolute !important; … }`, so a staged container never takes up space, whatever the renderer sets inline.
- On a swap, the ids move with the roles: the visible container is always `#host`.
- `__duo.open` and `__duo.refresh` run one at a time. A request that a newer one superseded while it waited is skipped, so the newest bytes always draw.

The redraw still has no flash: the new drawing is made while out of sight and swapped in, and the pane keeps its scroll and current slide. The scroll is restored with `scrollTo(0, y)` as before. This run did not check it live at a scrolled position, because both probes ran at the top.

## Proof

- `DUO_CHECKS=deckviewer`, in `DeckP3bChecks.swift`: an offscreen viewer is given the sample deck, then one edit, then two quick edits. It checks that slide 1's top is unchanged by a redraw, that the visible drawing has the newest text and all 9 slides, that the visible container is `#host` and visible, and that the page's height is unchanged. Without the CSS fix, three checks fail (top 816; height 2519 → 3319). Without the serialization, three fail (0 slides).
- Captures in Light, after `user-type:86%=>88%`: [before the fix](redraw-blank/before-fix-after-edit-light.png) (the pane is blank) and [after the fix](redraw-blank/after-fix-after-edit-light.png) (88%, with 62% from a later on-disk edit).
