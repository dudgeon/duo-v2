A question that needs more than a yes: Duo's own sheet, hung from the toolbar over the window.

**Status:** Designed (DL-100, slice2 `move-into-home.html`, `new-project.html`). **In code:** `Shell/Sheets.swift` (`SheetOverlay`, `MoveIntoHomeSheet`, `NewProjectSheet`, `SheetRow`, `SheetButtons`, `PlacePopup`, `SheetField`).

**Anatomy:** `ground`, `sheetPadding` (20), a 1 `rule` border, `radiusPopover` (10), `shadowPopover`, hung `sheetTop` (38) from the window's top. Move into Home is `sheetMoveWidth` (460), open at the top and rounded below; New project is `sheetNewProjectWidth` (520), rounded all round. A title in `bodyEmphasis`; text in `body`, paths in `mono`, warnings in `text2`. Fields are `sheetFieldHeight` (24) on `pane` with a `rule` border, radius 6, labels in a `sheetLabelColumn` (96) right-aligned `text2` column, rows `sheetRowGap` (12) apart. A place popup: the folder mark (New project only), the place (`Home (top level)` or `payments /`) and a down chevron. Buttons right-aligned: Cancel, then the default button with a `text` border and a semibold label. The map behind dims to `sheetDimmedOpacity` (0.55).

**Use:** Move into Home… (with Into: Home's top level or a topic folder) and New project (name, goal, In, the path it makes, "Start a Claude session in it"). Return is the default button, Escape cancels. Never a system alert: a scripted run can't block on it.

**Don't:** use a sheet for a plain yes/no confirmation (those stay standard sheets until DB-12/DB-36), or put a sheet over the terminal for something Claude asked.
