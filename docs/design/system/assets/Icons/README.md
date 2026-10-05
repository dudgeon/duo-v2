Icons are the drawn icons from `docs/design/build-handoff/tokens.json`, as SVGs. Each is a single stroke with round caps and joins. The ink is baked in, because `<img>` can't inherit colour: `text2` (#5B636D), except the chevrons (`text2`) and the console marks, which use `consoleText2` on the console in the app.

- `chevronRight`, `chevronDown`: disclosures and folds, 8 × 10 and 10 × 8.
- `searchFile`, `searchSession`: a search result's kind, 12 × 12.
- `shellPrompt`, `moreTabs`: a shell tab's mark and the console's overflow, on the console (DB-4).
- `propertyText` … `propertyOpen`: the properties block's type icons, 12 × 12, stroke 1.2 (DB-16, designed, not built).

These are SF Symbols, not files:
- `sidebar.left` (the left-pane toggle);
- `magnifyingglass` (search);
- `folder` (map column labels, stand-in);
- `square` (task lines, stand-in);
- `chevron.left`, `chevron.right`, `arrow.clockwise`, `safari` (the browser bar, stand-in).
