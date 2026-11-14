# Duo Decks P3 track A: the deck viewer's plumbing

Branch `build/duo-decks-viewer` (from main 9f5b18e2). No new visible surface: the deck preview is today's DeckViewer (its 44 bar, the slides, the picker bar) behind split view's `PreviewProvider`.

## What is built

- **`Sources/DuoKit/Deck/DeckPreview.swift`**
  - `DeckPreviewBuild.build(text:file:packDirs:)` is the pure part (DuoChecks run it): parse + check + export the editor's buffer to pptx bytes in memory (never a file), the anchor map (`slide N`, `slide N/slot`), problems (`.error` from the checker's problems, `.notice` from its notices; a missing pack is one error at line 2), comments (the review thread id on the narrowest slot or slide holding it, from `Review.parse`), and `shapes`: slide, then the drawn shape's OOXML id, to the slot name (recorded by the pptx writer as it writes, so it is the template's placeholder idx mapped to the slot).
  - `DeckPreview: PreviewProvider` (`kind .deck`), `canPreview` = `.md` with `type: deck`. `render(text:rev:)` is gated by `RevisionGate`, builds off the main thread, hands the bytes to the viewer and emits `anchorMap`, `problems`, `comments` with the revision. A deck with errors keeps the last good drawing (no bytes) and shows its errors. `reveal(anchor:)` goes to that slide (nothing when already current, and the resulting `current` is tagged `.reveal`, so it never echoes). A slide change in the page is `current(slide N, .user)`; a picked shape is `activate(slide N/slot, .user)` (or `slide N` for a shape that is no slot's).
  - `view` is an `NSHostingView` of the viewer's own bar, the slides and the picker bar (`DeckBar`, `DeckWebHost`, `DeckPickerBar`, unchanged), once `bind(path:file:model:)` gave it the app model; without a model (checks) it is the slides' web view alone.
- **DeckViewer**: `show(bytes:name:)` draws from memory (the `duo-deck:` scheme serves the bytes as `deck.pptx`), plus `onSlideChange` and `onPicked` hooks. **`Vendor/pptx-renderer/deck.js`/`deck.html`**: `__duo.refresh` draws the new deck in a hidden second host, then swaps it in and restores scroll and the current slide (no blink: the handoff's "draw first, then swap").
- **DuoDeck**: `Deck.check(source:deck:packDirs:)` and `Deck.export(checked:source:deck:)` take the buffer's text; the file versions are unchanged.
- **Registration**: `DeckPreviewRegistration.install(model:)` in `Sources/DuoKit/Deck/DeckPreviewRegistration.swift`, called from `DuoApp.init` right after `AppModel(...)` (one line in `Sources/Duo/DuoApp.swift`). It appends to `PreviewProviders.extra`, because `PreviewProviders.register(.deck, test:make:)` is on split-view-build's `fix/split-view-1101`, not on this base. When that merges, change `install()`'s body to `PreviewProviders.register(.deck, test: Self.test, make: { DeckPreview() })`. Split view's `previewKind(forTab:)` passes no frontmatter, so the test reads the file's first 4 KB itself (`frontmatterOf`, set by `install(model:)`).
- **Verbs** (`Actions.swift`, own commit; handled in `Sources/DuoKit/Deck/AppModel+DeckPreview.swift`), app verbs, so they ask Duo; the local `deck check|export|…` and `slide …` verbs are unchanged:

```
$ duo2 deck
decks/field-trial-review.md: slide 3 of 9 in the preview. The caret is in slide 3 (lines 28–38).
$ duo2 deck go 3
Slide 3 of 9. Source lines 28–38.
$ duo2 deck go next
Slide 4 of 9. Source lines 42–53.
$ duo2 deck pick
The picker is on: the user clicks a shape; run `duo2 deck pick` again to read it.
$ duo2 deck pick            (after a click)
Picked Content Placeholder 2 on slide 3, the value slot (source lines 31–32 of decks/field-trial-review.md).
$ duo2 deck pick 3/4        (selects the shape slide 3, id 4)
```
  The last two outputs are from the code path, not from a live run (the live run did not click).
- **DuoChecks**: `DUO_CHECKS=deckpreview` (`DeckP3aChecks.swift`, 30 checks, also worth adding to the full run): canPreview and the registered test, bytes equal the file export's, anchor map (slide 1 at line 8, slide 3's value at 31, slots inside slides), the policy's narrowest-anchor pick, problems (errors vs a notice for an empty slot, a missing pack), comment anchors (`slide 3/value`, thread `c1`; never in the export), shape id to slot checked against `Deck.inspect` of the export for every slot shape in the sample (22 shapes, 0 wrong), gate (older render dropped; map/problems/comments emitted once with their revision), the last good drawing kept on errors, and the three verbs resolving as app verbs. `DUO_CHECKS=deck` passes (187) after one check in `DeckP1Checks.swift` was widened to allow the three new app verbs.

## Blocked: the split tab does not host the provider yet

Split view's own files hardcode the deck as a stub, and I was told not to edit them. What split-view-build needs (the exact diff is `p3a-split-wiring.patch`, made against this base, 4 small edits):
1. `SplitState`: `@ObservationIgnored public lazy var deck = DeckPreview()`.
2. `SplitPreviewSide` (SideSplit.swift): `case .deck: WebPreviewView(web: model.splits.deck.view).background(DuoColor.pane)`.
3. `AppModel.startPreview`: for `.deck`, `splits.deck.bind(path:file:model: self)` and `splits.deck.emit = { policy?.accept($0) }`.
4. `AppModel.renderPreview`: `case .deck: splits.deck.render(text: text, rev: rev)`; `previewWebView(for:)`: `.deck` is `splits.deck.viewer.webView`.
With the new `register(...)`/"one provider per window" hook it is the same shape: make the provider with `make`, call `bind` when the tab opens, set `emit`.

I applied the patch locally, built, and ran the live proof below, then reverted `Sources/DuoKit/Split/*` and `AppModel+Split.swift`; none of it is committed. Without it `duo2 split <deck>` opens the split and the preview side is an empty `pane`; `duo2 deck` says "no deck is showing in split view".

Also not done (waiting on the editor side, md-bar-build's files): the 2 pt `controlEdge` anchor mark in the source margin (the editor draws it from `policy.map`), and click-on-slide to put the caret in its slot (`activate` reaches the policy; the editor must move the caret). `duo2 deck go` shows the slide's first line in the source with `duo.selectLines`, which also moves the caret there.

## Live proof (isolated, background)

Home `/tmp/p3a/ws` (`_HOME.md`), project `field-trials` (`_PROJECT.md`) with `decks/field-trial-review.md` and `templates/decks/northwind/`; a scratch `DUO_SUPPORT_DIR` and `CLAUDE_CONFIG_DIR`, `open -g`, no real turns, quit by SIGTERM to its pid. Through that instance's duo2 (its private socket, found because Geoff's Duo holds the shared one): `duo2 status` shows `Project field-trials`, `Right pane: decks/field-trial-review.md`; `duo2 split` shows `left: decks/field-trial-review.md, right: Slides, ratio 0.500, folded: false`; the `deck` outputs above are from it. Captures in `docs/design/duo-decks-handoff/proof/`: `compare-split-deck-light.png` (TARGET | BUILD | DIFFERENCE, the target cropped from `split-view-handoff/screens/png/split-deck.png` and scaled to 1440 × 900, as F-512 did), `build-light.png`, `build-dark.png`, `build-classic.png`, `target-split-deck.png`. `compare.sh` can't take a board with annotations, and no `pixels.py` diff was run.

Read region by region against the target:
- **Matches:** the strip (`field-trial-review.md ⧉ Slides`, the active name semibold, the split mark), the three-way layout (rail, console, source, slides), the preview side being the viewer's own bar (‹ › "Slide n of 9", Select Shape, Open With) with the 44 bar's height and rule, slide frames with a number above each and the current one semibold, the picker bar at the bottom while picking (build-light/dark/classic were captured with the picker on after `deck pick`), Dark and Classic following the theme (Classic's cream ground and tan Select Shape).
- **Differs, by design or not built:** the bar reads "Slide 4 of 9" because the preview side is wider than 460 here (the target is 470 and shows `3/10`; narrow it and the bar shortens as it does today); there is no Export button (the target's is a later design, so none was built); the target's source has the formatting bar and the `controlEdge` mark, neither of which exists on this base; the source shows the properties drawer and the real sample deck (9 slides), the target a mock (88%, 10 slides); the slide fonts are the viewer's fallback (serif) because northwind's fonts aren't embedded in the pack (the same as the pptx viewer today); the Dark capture's window chrome and the Classic source type are as split view slice 1 draws them.
- Nothing was measured with `scripts/pixels.py`.

## Stand-ins and notes

- The build ran with the wiring above; the committed branch alone cannot show the deck in a split tab.
- `show(bytes:)` names the page's title `field-trial-review.md`; the "Open With" menu in the bar is DeckBar's own, for the `.md` file.
- The exported bytes carry a source hash of the buffer text, so unsaved edits give different bytes than the saved file would, as intended.
- Timing of a render (parse, measured fit, export) on the sample deck was not measured under the exclusive lock; split view's rule 6 asks for it before merge.
- An isolated Duo launched with `--capture-window` listens on a private socket while Geoff's Duo is open; `duo2` reached Geoff's Duo before I set both `DUO_SOCKET` and `DUO_TOKEN` correctly (see the report: one `duo2 settings appearance light` reached his Duo).
