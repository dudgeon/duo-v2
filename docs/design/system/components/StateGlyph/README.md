A session's attention state as a shape: needs you, ready for review, working, idle, resolved.

**Status:** Designed (handoff §4.4). **In code:** `Sources/DuoKit/Design/StateGlyph.swift` (`StateGlyph(state, on: .light | .console(active:))`).

**Anatomy:** 9 pt square (`glyphSize`), drawn in a 10 × 10 box from the paths in `assets/Glyphs/`. Needs you is a filled circle in `needsYou` (`needsYouOnConsole` on the dark pane). Ready for review is a filled diamond, and working a 1.5 ring, both in `text`. Idle is a dash and resolved a check, both 1.6 stroke in `text2`. On the console, inactive tabs draw glyphs in `consoleText2`.

**Consumer provides:** the state, and where it sits (light chrome or the console, active or not).

**Do:** pair it with a visible label, or give the row a combined accessibility label ("PRD v2 edits, needs you, waiting 4 minutes"). Keep `gapGlyphToLabel` (6) before the label.
**Don't:** animate it (working is a still ring), tint it with anything but the tokens above, or use it as decoration.
