# Park sessions handoff (DL-192)

Canvas: https://claude.ai/artifact/9bwgqT41HWbkg72ihZ943j. Geoff chose, by buttons on 2026-10-13: the question lists the tabs (board 1, A), a pin on a Keep Running tab (board 2, A), and the verb "Park" (board 3).

## Screens

- `screens/memory-question.html`: the question Duo asks under critical memory pressure. A (chosen) lists the tabs; B (count only) was not chosen.
- `screens/keep-running-pin.html`: a Keep Running tab in the console strip. A (chosen) puts a pin after the name; B (menu check only) and C (pin on the tab and on the list row) were not chosen.
- `screens/menus.html`: the Session menu, a Claude tab's right-click menu, what Duo says after Park Background Sessions, and the `duo2` verbs.

## Spec

- **The question** is a `DuoQuestion` on `SheetCenter`, never a system alert.
  - Title: "Your Mac is low on memory. Park N idle sessions?"
  - Paragraph: "Parking ends Claude in tabs you aren’t looking at. Each tab stays, and its session picks up where it left off when you show it."
  - Items: one per tab. The tab's name, then at the right in `text2` its project and how long it has sat at its prompt (`checkout · 2h`). Past 6 tabs: the first 5, then "and N more".
  - Note, `control` in `text2`: "Tabs that are working, waiting on you, running something in the background, or set to Keep Running stay as they are."
  - Buttons: Not Now (cancel), then Park N Sessions (default).
- **When it's asked:**
  - On macOS's memory-pressure signal at `.critical`, when at least one tab can park. Once per episode: not again until pressure returns to normal and then goes critical again.
  - Never while another question is up. It waits its turn and is dropped if pressure has eased by then.
  - A scripted run (`DUO_AUTOCONFIRM`) takes the default and logs the question.
- **The pin:**
  - A 9 pt pin after the tab's name: stroke 1.3, round caps and joins, gap 6. It is `consoleText2`, or `consoleText` on the selected tab.
  - Tooltip "Keeps running: never parked". Accessibility: "‹name›, ‹state›, keeps running".
  - The state glyph stays where it is. Home's tabs get it too.
- **Menus:**
  - The Session menu gets Park Session, Park Background Sessions and Keep Running (checked when on), between Delete Session… and End Session.
  - A Claude tab's right-click menu gets Park Session and Keep Running above Close Tab.
  - Park Session is dimmed when the tab can't park; its tooltip says why.
- **After Park Background Sessions** Duo tells you what happened with its notice:
  - "Parked N sessions. Each picks up where it left off when you show it."
  - When some were kept: "Parked N sessions. M kept running: “‹name›” is ‹why›, …"
  - When none could park: "No idle sessions to park." and, when some were kept, why: "No idle sessions to park: “‹name›” is ‹why›."
- **A parked tab looks idle** (Q-136 stays open).

## Build

See F-308 (how Duo tells a tab can park) and F-309 (what survives a resume).
