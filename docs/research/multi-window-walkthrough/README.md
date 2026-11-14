# Multi-window decision walkthrough

The first decision walkthrough (DL-309, DL-310): the multi-window research, round 3 (`../multi-window-2026-11.md`), narrated in 11 chapters (4 findings, 6 decisions, a close; 3.0 minutes straight through) by Duo's house voice, ending in the open decisions Q-99, Q-429, Q-431 and Q-435 (three parts). Q-428 is narrated as settled (DL-308). It replaces those cards on the round 3 review page https://claude.ai/artifact/AH33RCyja4xoCDUihYndZo; Q-426 and Q-427 stay there.

- `spec.json`: the chapters, narration, cues and decisions. The decision ids match the review page's (`q99-when`, `q429-scope`, `q431-home`, `q435-palette`, `q435-new`, `q435-classic`).
- `scenes/` and `scenes.css`: one animated scene per chapter, on Duo's tokens and board 4a's window colours; `assets/`: two sample-data captures from the design system.
- `page/`: the built page, ready to publish: `index.html`, `audio/*.mp3`, `assets/`, and `publish.json`, which lists the files and capabilities (`{db: {}, comments: {}}`, icon `play`).
- `checks/`: the last headless check (`report.txt`), every chapter's end state at desktop width, the phone at 375 px, and frames from chapters 2 and 3 while they play.

Rebuild with the user-level skill (`~/.claude/skills/decision-walkthrough`, its SKILL.md has the steps): `node ~/.claude/skills/decision-walkthrough/build.mjs spec.json`. Only changed lines are re-voiced, under the GPU lock; `.cache/` is not committed.

The director publishes the final page (DL-166), so answers reach director-duo-v2: db `answers/<id>`, a comment sent to Claude per answer, and Copy decisions for Claude. A worker's draft is at https://claude.ai/artifact/HwMUZyk8Lj4zxJ7q9wKmR6.
