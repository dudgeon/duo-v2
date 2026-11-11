# First-use feedback: decision walkthrough

The research in `../aram-feedback.md`, narrated in 10 chapters (4 findings, 5 decisions, a close) by Duo's house voice, ending in the open decisions Q-510 to Q-514. The findings are Aram's, a Duo user, and the narration credits him by name (Geoff, 2026-11-11).

- `spec.json`: the chapters, narration, cues and decisions. Decision ids: `q510-mode`, `q511-onboarding`, `q512-director`, `q513-claude`, `q514-spelling`.
- `scenes/` and `scenes.css`: one animated scene per chapter, drawn with Duo's light tokens. No captures: the windows, menus and sheets are schematic, and the welcome, the sample project and the empty director slot are stand-ins, not designs.
- `page/`: the built page: `index.html`, `audio/*.mp3`, and `publish.json` (`{db: {}, comments: {}}`, icon `play`).
- `checks/`: the last headless check (`report.txt`) and the chapter end states at desktop and phone width.

Rebuild with the user-level skill (`~/.claude/skills/decision-walkthrough`): `node ~/.claude/skills/decision-walkthrough/build.mjs spec.json`. Only changed lines are re-voiced, under the GPU lock; `.cache/` is not committed.

Answers reach director-duo-v2: db `answers/<id>`, a comment sent to Claude per answer, and Copy decisions for Claude. The decision cards' "Look" links point at the research doc on the `research/aram-feedback` branch; repoint them at `main` once it merges.

Published as a worker draft at Geoff's request (2026-11-11): https://claude.ai/artifact/7HjjjCFhzPhMST6RGo2kmS (private until he shares it).
