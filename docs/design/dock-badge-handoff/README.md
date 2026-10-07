# Dock badge slice 2: the Settings hint and the Dock menu

Status: approved by Geoff, 2026-10-07, as drawn (DL-144), by buttons on the PNGs in `screens/png/`. It answers Q-93 and builds ENH-24. The boards were drawn in a background session that had no Artifact tool, so there is no Design canvas (F-162); they follow the approved Settings screen (`slice3-handoff/screens/settings.html`) and the Duo design system.

## What each board settles

**`q93-notifications-off`, `q93-badges-off` (Q-93).** [G] When macOS hides what Duo's Notifications row asks for, a `text2` line goes under **Show the count on the Dock icon**, indented to the checkbox labels (`settings.checkboxIndent`, 22). The row's button, **Open Notification Settings…**, sits on the right like every Settings row's buttons.
- Notifications denied: "macOS has notifications off for Duo, so neither of these shows." Shown whether the boxes are ticked or not.
- Notifications allowed but badges off, with the Dock count on: "macOS has Badge application icon off for Duo, so the Dock shows no count." With the count off, the line and button go.
- Nothing hidden: the row is the approved S3-1 row, unchanged.
- The button opens System Settings › Notifications › Duo; its verb is `duo2 settings macos`. Duo reads the state each time Settings opens and after each change to a box.

**`dock-menu` (ENH-24).** [G] Right-clicking Duo's Dock icon shows a disabled **Needs you** header, then one item per waiting session titled "session · project · wait", longest wait first. It's the same list `duo2 needs-you` prints, Home and every project included. macOS's own items follow.
- Clicking an item brings Duo forward and opens that project with the session selected, as `duo2 open <project> <session>` does.
- With more than 9 waiting, the menu shows the first 9, then "N more need you…", which opens All projects (`duo2 go all`).
- With nothing waiting, Duo adds nothing.
- macOS draws the menu, so its look is exempt from pixel comparison.

## Tokens

`settings.checkboxIndent` = 22, added to `build-handoff/tokens.json`.
