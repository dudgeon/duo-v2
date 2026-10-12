A feature's explanation, as the second tier after a plain help tag: a small popover with a picture, for a feature a new user won't guess. Tasks has the first one.

**Status:** Designed, not built (DL-172, `explanatory-tooltips-handoff/`). **In code:** none yet. A popover Duo draws, like search and the idle list; the build names the view.

**Anatomy:**
- **Frame:** 300 wide, `pane` fill, 1 `rule` border, `radiusPopover`, `shadowPopover`. Padding 14 16 12, with 10 between parts. A 12 arrow points at the trigger.
- **Title:** the feature's noun, in `title`.
- **Line:** what it is, 60 characters at most, in `body`.
- **Picture:** on `ground`, radius 6. It is drawn from Duo's own parts at small size, in the tokens, with numbered marks (16, filled `text`) tying it to the lines. It is decorative and hidden from VoiceOver.
- **Points:** two or three, each 90 characters at most. A lead-in of 2–5 words in `text` semibold, the rest in `text2`, 12/17.
- **Footer:** Learn more (text, underlined on hover) and Don't show again (`text2`).

**Behaviour:**
- **Opening:** a still pointer on the trigger shows the system help tag at about 1 s, then the Explainer 1.5 s later. A hover-opened Explainer never takes focus.
- **Placement:** above the trigger, or below when there's no room above. It never covers its own trigger.
- **Closing:** it stays while the pointer is on the trigger or on the Explainer. It closes 300 ms after the pointer leaves both, on Esc, on any click, or on typing or scrolling.
- **Dismissing for good:** once Don't show again is clicked, hover shows only the help tag. Settings › General › Show dismissed explanations again brings it back.
- **Keyboard and VoiceOver:** Help › Explain ‹Feature› opens it, with focus on Learn more. VoiceOver gets an Explain action.

**Copy:** sentence case and plain words. Name things the way Duo's UI names them.

**Do:**
- Keep the help tag as the real label.
- Keep the picture true to the real UI.

**Don't:**
- Use video, motion, the accent, fields or extra buttons.
- Put anything in it you need in order to get on.
- Use it on a disabled control or while a sheet or menu is open.
- Add an Explainer to another feature without a decision. Chat mode and Home are drawn on the canvas, not approved.
