A PowerPoint deck in the right pane: its slides drawn, the slide on screen, and a picker that sends a shape to Claude.

**Status:** Designed (DL-125, `pptx-handoff/`), built (F-121). Drawing, no session and narrow panes designed (DL-132, `standins2-handoff/` `q68-drawing`, `q68-no-session`, `q68-narrow`): while drawing, "Drawing slides…" in `text2`, ‹ › and Select Shape dimmed and an empty numbered frame per slide; with no session, the picked bar says why and "use Send To" above its buttons, Send to Claude dimmed and Send To the default; under 460, `2/5` and the picker in two rows. **In code:** `Editor/DeckViewer.swift` (the web view and its messages), `Project/DeckView.swift` (DeckBar, DeckPickerBar, the fallback), `Vendor/pptx-renderer/` (the renderer and Duo's page around it).

**Anatomy:**
- **The bar** under the tabs, `deckBarHeight` 44 with a `rule` below, padding 0 20: ‹ and › (Duo buttons), **Slide n of N** in `body` (`Drawing…` in `text2` until it's drawn), then at the right **Select Shape** (shown pressed, `selected` fill, while picking) and **Open With ⌄**.
- **The slides** on `ground`, padding 16 20, each at the pane's width with a 1 `rule` round it and no shadow; its number above in `pill`-sized 11/16 `text2`, 6 above the slide, 16 between slides. The slide filling most of the pane is the current one: its number in `text` semibold.
- **Picking** (B): the shape under the pointer gets a 1 dashed `text` outline 3 outside it, its name on a `text` tag (radius 3, 11/18, `pane` text) above. **Picked** (C): a 1.5 solid `text` outline and the tag.
- **The picker bar** at the bottom, on `ground` with a `rule` above, padding 10 20: "Click a shape on a slide to select it. Esc to stop." and Cancel; once picked, **name** on slide n · “text”, "In group › group" in `text2`, then Send to Claude (default), Send To ⌄, Pick Another, and Cancel at the right.
- **Can't draw** (E): the notice bar (DocumentStateBar's look) "Duo can’t draw <name>: <why>." / "Quick Look shows what it can, read only. Claude can’t read its slides either." with Open With ⌄ and Show in Finder, over Quick Look.

**Behaviour:** what Claude receives is pasted into its prompt without Return (board D). Verbs: `duo2 slide`, `slide go`, `slide shapes`, `slide notes`, `slide pick`, `slide element`; `send element` sends the picked shape. Slide content is the renderer's, exempt from comparison.

**Motion (DL-130):** ‹ › scrolls to the slide (`motionSlide` 250 ms). Opening a deck and a scripted pick jump instead. The picker's outline glides between shapes (`motionOutline` 80 ms). With Reduce Motion, it's at once.
