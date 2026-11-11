# Duo: Home's agent panel — design study

Status: **proposed, waiting on Geoff** (Q-498 to Q-501, and Q-488's recommendation). Every mark is [P]. Nothing is built.

The research is `docs/research/home-agent-panel.md`. The canvas is https://claude.ai/artifact/PBJttSgB17RzCn8WQQo6sF, with the Duo design system (its `tokens.json` installed on the canvas). The decisions go to Geoff as a decision walkthrough, `docs/research/home-agent-panel-walkthrough/`.

## Boards

| Board | What it shows |
|---|---|
| `Main` (00) | The ask, what the column costs, the five options, the recommendation |
| `c1-allprojects` (C1) | Recommended: All projects with no Home column and no sidebar button; Home's needs-you session as a full card with Open Home |
| `c2-homepage` (C2) | Home's page, the one place Home's agent runs, with a question at the console's width |
| `a1-settings` (A) | Settings › Home: "Show Home's agent at All projects" |
| `b1-startcard` (B) | The column's start card: Home's agent, Not Now, Start Home's Agent |
| `d2-wide` (D2) | The column at 480 |

`canvas/project/` holds the canvas's files as published (hand-written `.dc.html` boards, the index). Board labels and the yellow notes are the board's, not the app's; names and data are the home-evolution study's sample data.

## New marks, all [P]

- C1: no sidebar button at All projects; the middle takes the column's 340; a Home needs-you card with the question and **Open Home**.
- A: a checkbox row "Home's agent" in Settings › Home, with its sub text.
- B: the start card (title, two lines, Not Now and the default Start Home's Agent).
- D2: the column at 480 and the List without its task column at 1440.
