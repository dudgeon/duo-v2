# Working on Duo's design

How to design for Duo and hand the work back so it gets built as drawn.

## What wins

1. **The decision log** (`docs/design/decisions.md`, DL-n) wins over everything. Recent decisions that change older screens:
   - DL-80: no ⌘K; search's field reads `Search all projects ⇧⌘A`.
   - DL-82 to DL-85: every session on launch; Home is optional and the container of tracked projects.
   - DL-83, DL-89, DL-92: folder columns.
   - DL-87, DL-93: tasks are notes with linked sessions.
   - DL-90: untitled session names.
   - DL-91: the session list's sections.
   - DL-99: browser tab shortcuts.
2. **Approved target screens** are the literal target for anything visible, unless a decision changed them. They're in `docs/design/build-handoff/`, `search-handoff/`, `surfaces-handoff/` and `frontmatter-handoff/`. Each handoff's `screens/manifest.json` lists its screens.
3. **This system** describes 1 and 2 as built. Where it disagrees with either, they win; please point it out.
4. **The current brief** says what's wanted next: `docs/design/design-brief-slice-2.md` (S2-1 to S2-6). Behind it is the full list, `docs/design/design-brief-2026-10-04.md` (DB-1 to DB-39).

## Rules for new designs

- **Use the tokens.** Any new value goes in a `tokens-additions.json` beside your screens, with a usage note.
- **Keep one accent.** `needsYou` means needs you.
- **No reply buttons on cards.** The user answers in the session (DL-29).
- **Keep shortcuts on ⌘.** Changing the shortcut map needs a decision.
- **Questions are sheets on the window**, never app-modal alerts. Native menus, sheets and popovers sit above web views.
- **Everything needs a keyboard path and a `duo2` verb.** Design the menu item; the verb follows.
- **Draw the empty, error and loading states** as well as the full one. Use the sample world in `docs/design/build-handoff/fixture.json`, with folder names as the app shows them now:
  - a Home called `claude-home`;
  - topic folders `payments /` and `growth /`;
  - an outside column `~/repos /`.
- **Mark what you propose.** Write [P] for your proposal, [G] for Geoff's decision, [B] for the brief's requirement. Geoff decides the [P]s.

## Handing work back

Hand work back in the shape `docs/design/surfaces-handoff/` uses:
- **`screens/*.html`:** one per state, each with `design-size`, `design-kind` and `design-surface` metas.
- **`screens/manifest.json`:** every screen with its DB or S2 number, size and what it shows.
- **`README.md`:** what each screen settles, the [G]/[B]/[P] marks, and anything a picture can't show (behaviour, keyboard, edge cases).
- **`tokens-additions.json`:** new tokens only.
- **Fixture additions**, if the screens need sample data the fixture lacks.

Builders compare the app against each screen pixel by pixel (`scripts/check-ui.sh`). So draw at the design size, 1440 × 900 for the window, with real text, not lorem or placeholder bars.

## Where things live

| What | Where |
|---|---|
| Tokens (canonical) | `docs/design/build-handoff/tokens.json`. This system's `tokens.json` and Swift's `Tokens.swift` are generated from it. |
| Decisions | `docs/design/decisions.md` |
| Open questions | `docs/plan/concerns-and-questions.md` (Q-n) |
| Wanted but unscheduled | `docs/plan/enhancements.md` (ENH-n) |
| What was learned building | `docs/plan/findings.md` (F-n) |
| The app's views | `Sources/DuoKit/` (SwiftUI) |
| Design docs, with their status | `docs/design/README.md` |
