# Home agent panel handoff (DL-336)

Geoff approved this on 2026-11-11 (DL-336, by button): Home's agent lives on Home's page only; there is no Home column at All projects and no Home session at launch.

Source: the Design canvas https://claude.ai/artifact/PBJttSgB17RzCn8WQQo6sF (study in `../home-agent-panel-study/`). Build brief: `docs/research/home-agent-panel-build-brief.md`.

## Screens (`screens/`, 1440×900, `png/*@2x.png`)

| screen | what it sets |
|---|---|
| `c1-allprojects` | All projects with no left pane and no sidebar button; the middle (List or Board) takes the 340 the column had; a Home session that needs you is an ordinary needs-you card (C1 draws its button "Open Home"; Q-502). |
| `c2-homepage` | Home's page is a project page as built, with ★ home's name. A check that it works like any project's, not a pixel target. |

C1 is a sketch on the home-evolution study's sample data, not a pixel target for the List: the List, rows, header and cards are as built (`../home-evolution-handoff/` `list-1440`, `needs-you`).

## Exempt

The yellow notes (the board's, not the app's) and the sample data.

## Files

`export.py` strips the canvas wrapper from the study's boards; `render.sh` renders `screens/png`. `checks/` holds the last comparison images from the build.

Do not edit `screens/`: they are a snapshot of the design canvas.
