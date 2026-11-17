# Duo: the first-run welcome — design handoff

Status: approved by Geoff, 2026-11-16 (DL-348), by buttons on Q-532 to Q-536, after the study `docs/design/first-run-welcome-study/` (its README lists every board; A and C were not chosen). Canvas: https://claude.ai/artifact/1a6Lfh9dNwco7X5ksruKhJ. Target; building on `build/first-run-welcome`.

`screens/` are copies of the chosen boards (HTML, and `png/` at 1x and 2x). They are presentation boards: the window or card drawn inside each is the target. The yellow notes, `P` marks and board labels belong to the boards, not the app. Names and data are sample data.

## Targets

| Screen | Build |
|---|---|
| `B1-allprojects-fresh` | **The Getting started with Duo card** at the top of All projects › List (under the List \| Board header), on a new install only. Border `rule`, radius 8, `pane` fill, padding 14/16. Title 14 semibold, count "0 of 3 · all optional" 12 `text2`, **Hide** at the right. Lead line 13 `text2`. Three steps, each a row with a 14 box, a name (13 semibold), a `text2` line and its buttons at the right (step 1: Make a project…, Show me; step 2: New session, Show me; step 3: Show me). Then the director line: ○ (no box, no count), "**Later, a director.**" and its sentence, with **Watch the director film** and **Explain**. At the right, the intro film's poster (232 × 130, dark, ▶, "Watch the intro film"), "9 min 34 s · what Duo is for" and "Help › Getting Started brings this back." |
| `B2-card-progress` | **Ticked:** the box fills `text` with a white check; the name goes `text2`, struck through, regular weight; the line says what was done (step 1 "name · folder", step 2 "“first message” · in Chat. Terminal is one click on its tab."); Show me stays on step 2 only; the other buttons of ticked steps go. **Make a task…** (step 3) opens DL-147's guided sheet in the project last opened; with no project it reads Make a project first, greyed. **All three done:** a one-row card, a check, "That's the basics", "The guide has the rest: documents, Home, what needs you, getting around.", Open the guide, **Done**; under it the director line, "Help › Explain › Director." Done folds it away for good. **Hidden:** a 28-high notice "Getting started hidden. Help › Getting Started brings it back." with **Undo**, for 8 s (DL-147's notice, board 13), then nothing. |
| `B3-showme-chat` | **Show me** on step 2 goes into the project last used, selects a Claude tab (starting a session first when there is none), and opens the built Chat and Terminal Explainer on the pill, as Help › Explain Chat and Terminal does. Show me never moves anything the user didn't ask for; Esc closes the Explainer and returns to where they were. The window drawn is context (DL-253, DL-217). |
| `X1-help-menu` | **The Help menu, proposed:** Getting Started · Duo Guide · Watch the Intro Film · Watch the Director Film · — · Explain ▸ (Projects, Chat and Terminal, Tasks, Home, Director) · — · duo2 Reference · What's New in This Version · — · Report an Issue…. It replaces today's loose Explain Tasks and Explain Chat and Terminal (closes Q-522's stand-in, Q-535). Each Explain item opens on its control when that is on screen, else at the window's top centre. Director is listed even with no director. |
| `X2-explainers` | **Pictures and anchors** for Chat and Terminal (a terminal and the same turn as chat bubbles, marks 1 and 2; anchor: the pill), Director (a request, the director row, three workers; anchor: the director's pinned slot, once one exists; otherwise the card's Explain and Help › Explain › Director) and Home (a folder tree with _HOME.md and the projects, and an across-projects question; anchor: ★ home's tile or row at All projects, and Home's page title). The words are the built ones, unchanged. |
| `00-the-ask` | Context. Not a target. |

## Rules

- **New installs only (Q-533).** The test is F-673's: a support folder with neither `chat.json` nor `state.json`. The card is seeded once, at that moment, in Duo's own state (Application Support), never in a file the user owns. An existing install never sees it, except through Help › Getting Started. The install question (a sheet) still comes first; the card needs no answer.
- **Ticks come from the real action, wherever it happens** (a Duo button, ⌘T, `duo2`, Claude), never from clicking the step: step 1 a project opened or made; step 2 a session started (chat or terminal); step 3 a task made. A tick is kept; it never un-ticks.
- **It ends** at Hide (with Undo) or at Done after all three ticks. Help › Getting Started brings it back for anyone, new install or not, as it stands.
- **The director is a line, never a step or a tick** (Q-534). Nothing on screen pushes it where there is no director.
- **Show me** opens the existing DL-172 Explainer on the real control, or the Projects explainer (the left-nav round's, ENH-347) for step 1. Tasks: the New task row or the fold header; Chat and Terminal: the pill; Home: ★ home.
- Board view shows the same card above the map.

## Change

- `Sources/DuoKit/Live/HookEvents.swift` (`DuoState`): the card's own state, `gettingStarted` (shown, hidden, done, and which steps have ticked).
- `Sources/DuoKit/Chat/ChatSession.swift` (`ChatPrefs.load`): where a new install is recognised; seed the card there.
- New `Sources/DuoKit/Model/AppModel+GettingStarted.swift` (the model, the tick events, show, hide, undo, done) and `Sources/DuoKit/AllProjects/GettingStartedCard.swift` (the view), placed in `AllProjectsPanes.swift`.
- `Sources/DuoKit/Design/Explainer.swift`: the Home, Director and Chat and Terminal pictures (X2), and the anchors.
- `Sources/DuoKit/Navigation/Commands.swift`: Help › Getting Started and Explain ▸ (X1).
- `docs/design/build-handoff/tokens.json` only if a size here isn't a token already; regenerate with `scripts/gen-tokens.py` and `scripts/gen-design-system.py`. Use the existing tokens first (`rule`, `pane`, `text`, `text2`, `radiusControl`).

## duo2 (DL-71)

`duo2 getting-started show | hide | undo | state` and `duo2 explain <projects|modes|tasks|home|director>`, in `Sources/DuoControl/Actions.swift`. The card's buttons that already have verbs (`project new`, `session new`, `task new`, the films) keep them. Regenerate `docs/cli/duo2.md`.

## Checks

- DuoChecks: the new-install test (neither file → seeded; either file → not); each tick from its action and never from Show me; Hide, Undo, Done; Help › Getting Started re-shows on an existing install; ticks survive a relaunch.
- Fixture states: no ticks, one tick, two ticks, three (done), hidden, brought back; `scripts/check-ui.sh`, compared with `B1` and `B2` by `docs/design/build-handoff/tools/compare.sh`, region by region.
- Not pixel targets: the board backgrounds and frames, the yellow notes, the Help menu's chrome (macOS draws it), the poster's film frame (a stand-in until a still is made).
- Not drawn, so stand-ins with a question each: dark appearance, Classic, narrow windows (Q-591 to Q-594).
