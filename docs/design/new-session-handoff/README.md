# New session pill handoff (DL-253)

Canvas: https://claude.ai/artifact/58jBVfGCNHjNcrFtaa2HVj, page "New session buttons". Geoff, 2026-10-30: placement 4 and the Antenna robot without its mouth. A v1 user missed v1's new-tab cluster (ENH-044: Clawd | › | collapse, one click each).

## Screens

- `screens/chosen-placement-4.html`: **the target.** States A–F at 2×:
  - A: the console with few tabs, a Claude tab selected;
  - B: many tabs, with the overflow count;
  - C: a shell tab selected (no toggle; the shell half shown hovered);
  - D and E: the light strip over chat, with few and with many tabs;
  - F: Home with no tabs (the Claude half shown hovered);
  - and the spec cards.

  States A to C and F fill in what the placement board didn't draw. They follow its rules and are stand-ins until Geoff looks (Q-325).
- `screens/robot-antenna.svg`: the mark, 12 × 8, filled in `currentColor`, eyes cut out.
- Context, not targets:
  - `screens/placements-1-to-4.html`: the four placements, few and many tabs;
  - `screens/pill-options.html`: the pill variants;
  - `screens/today-and-v1.html`: v2 today and v1's cluster (the strip PNGs beside this README are real captures).

## Spec

- **The mode toggle rides on the selected tab** (it replaces the toggle at the strip's edge, chat-mode-handoff `toggle`).
  - It shows only on the selected tab, and only for a Claude session that has a chat (today's `ChatToggle` condition).
  - It sits 4 pt after the name (after the Keep Running pin, DL-192), outside the tab's hover fill (DL-134).
  - Segments are 20 × 16 on the console and 18 × 14 on the light strip, with a 1 pt border (`tuiInputBorder` / `controlEdge`) and `radiusControl` 6. The shown mode keeps today's fills.
  - The close × still takes the glyph's place (DL-126). A shell tab never shows a toggle.
- **`+` then the pill end the strip**, after any overflow count, at the strip's right padding.
  - `+` is a 1.5 stroke mark, 8 pt before the pill.
  - The pill's segments are 26 × 20 on the console and 22 × 16 light, with a hairline between them, the same border and radius.
  - The robot (left) runs `duo2 session new`, ⌘T; the shell (right) runs `duo2 shell new`, ⇧⌘T. One click each.
  - The chevron and its menu go (surfaces-handoff §139 changed).
  - With no tabs (Home's empty strip), the pill sits at the strip's start.
- **Colours.** Marks in `consoleText2` / `text2`. On hover the segment fills `consoleRule` / `selected` and its mark turns `consoleText` / `text`. No orange.
- **Tooltips:** “New Claude session ⌘T · in <project>” and “New shell ⇧⌘T · in <folder, ~ abbreviated>”.
- **A new session opens in the mode its setting says** (no change; Geoff, 2026-10-29).
- **The robot** is a filled 12 × 8 pixel mark, a one-off exception to the design system's stroke-only icon rule (DL-253). Put it in tokens.json's `icon` block, so gen-design-system exports it.
- **Build note:** draw both pills from one shared segmented-pill component in `Design/Components.swift`. A mode pill shows its chosen segment; an action pill shows hover only.
