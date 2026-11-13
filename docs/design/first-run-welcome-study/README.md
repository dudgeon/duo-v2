# Duo: the first-run welcome — design study

Status: **study, waiting on Geoff** (Q-532 to Q-536). Nothing built. Asked for in DL-339 (Q-511: "a designed first-run welcome as the next canvas round"), after Aram's first-use feedback (`docs/research/aram-feedback.md` §2).

The canvas is https://claude.ai/artifact/1a6Lfh9dNwco7X5ksruKhJ, with the Duo design system (its `tokens.json` installed on the canvas). `canvas/project/` holds its files as published (hand-written `.dc.html` boards and the index). `today/` holds captures of today's app from an isolated, background run (F-680). Board labels and the yellow notes belong to the boards, not the app; names and data are sample data.

## What it has to teach

Chat vs terminal; projects vs sessions vs tasks; that a director exists, without forcing it (Geoff on Q-512). And how a user gets back to it. It reuses the teaching layer on main (ENH-345): Help › Duo Guide and both films, the guide pages, the explainers (DL-172's component, with the built words).

## Boards

| Board | What it shows |
|---|---|
| `Main` (00) | The ask, the three directions, the decisions with recommendations, what it reuses, the overlap with the left-nav round |
| `b1-allprojects-fresh` (B1) | **Recommended.** Getting started with Duo at the top of All projects on a new install: three optional steps (open or make a project; start a session; make a task) with Show me, the director as a line to know about, the intro film's poster, Hide |
| `b2-card-progress` (B2) | The card at 2 of 3 (ticked steps say what was done), all done ("That's the basics", Open the guide, Done), hidden (notice with Undo) |
| `b3-showme-chat` (B3) | Show me on step 2: the project, its Claude tab, the Chat and Terminal explainer open on the pill, with its picture |
| `a1-welcome-sheet` (A1) | A Welcome to Duo sheet at first launch: three panels (sessions in chat or terminal; projects and tasks; a director, when you want one), the film, Start using Duo |
| `c1-first-session` (C1) | No welcome: four first meetings (All projects/Home, a project, a Claude tab, the Tasks section) each open their explainer once by themselves |
| `c2-director-hint` (C2) | No welcome: a one-time director hint in a project's sidebar at the fourth open session; Explain and the film, no Start |
| `x1-help-menu` (X1) | Any direction: Help today and proposed (Getting Started first, Explain ▸ with all five explainers) |
| `x2-explainers` (X2) | Any direction: pictures and anchors for Chat and Terminal (the pill), Director (the director's slot), Home (★ home at All projects), built words unchanged |

## New marks, all [P]

- B: the Getting started card (title, count, Hide, lead, three steps with box, name, line and buttons, the director line with ○, the poster), its ticked, done and hidden states; Show me's routing.
- A: the Welcome to Duo sheet and its three panels.
- C: explainers opening themselves at four first meetings; the director hint card.
- X1: Help › Getting Started and Explain ▸.
- X2: the three pictures and the Director and Home anchors.

## Overlap with the left-nav round

`design-projects-left-nav` (Q-527 to Q-531, ENH-349) owns where projects live in the window and the Projects explainer (ENH-347). Here, step 1's Show me and C1's second frame open that explainer, drawn dashed as a placeholder; it isn't redrawn. If a project list returns to the left, the card stays in the middle.

## Behaviour a picture can't show

- The card's steps tick wherever the action happens (a Duo button, ⌘T, duo2, Claude), like DL-147's card. Its state is Duo's (Application Support), never a file the user owns.
- New installs only, by the same test as F-673 (no `state.json`). The install question still comes first as a sheet; the card needs no answer.
- duo2 (DL-71): `getting-started show|hide`, `explain <tasks|modes|home|director|projects>`.
