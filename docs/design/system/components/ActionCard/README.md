A card in the All projects action column: a session that needs you, one pointing at Home, or one ready for review.

**Status:** Designed (no reply buttons, DL-29; the target's Approve / Reply… are not built). **In code:** `AllProjects/AllProjectsPanes.swift` `NeedsYouCard`, `HomePointerCard`, `ReviewCard`, `CardHeader`, `QuestionBox`.

**Anatomy:** padding `cardPadding` (10 12 12), 1 `rule` border (1.5 `text` when selected), `radiusCard`, contents `gapCardContent` (8) apart. The header: StateGlyph, session name in `bodyEmphasis`, wait at the right; the project in `text2`. Needs you adds the question verbatim in a QuestionBox (padding 8 10, 1.5 `needsYou` border) and `Open project`. A Home pointer is a dashed `controlEdge` card, padding 8 12: "← Waiting in the Home terminal". Review shows what it made ("wrote readout.md, 1.2k words") and `Review`.

**Behaviour:** click selects the card and highlights its row on the map; Open project zooms in on that session; Review zooms in with the deliverable open.

**Don't:** summarise or truncate the question (suggested cap: 6 lines with "more" on unselected cards); add reply buttons.
