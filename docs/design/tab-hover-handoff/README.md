# Tab hover fill handoff (DL-134)

Canvas: https://claude.ai/artifact/PEPNt2XyjyuWxYjG3ZofKN. Geoff chose A, as drawn, and right-pane tabs 24 apart (2026-10-07).

## Screens

- `screens/hover-fill-a.html`: A, chosen. Console and right-pane strips at rest, under the pointer (an unselected tab and the selected one), on the ×, and pressed.
- `screens/alternative-b.html`, `screens/alternative-c.html`: B (stronger) and C (full height). Not chosen.

## Spec

- While a closable tab shows its × (DL-126), a fill sits behind the × and the name. It is radius 5 and 24 high (`size.tabHover`), and reaches 7 past the glyph and the name. On the right pane it reaches 3 past the × box.
- `consoleHover` (#202329) on the console and Home; `ground` on the right pane. The selected tab gets it too.
- Drawn behind, so nothing moves; no fade. The × keeps DL-126's colours on top.
- Right-pane tabs are `gapPaneTabs` 24 apart (was 18).

## Build

`Project/TabClose.swift` `TabHoverFill` (F-149). `build-compare.png`: board A above the build's console and right-pane strips in the same five states.
