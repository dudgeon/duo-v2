# PDF viewing decision walkthrough

The decision walkthrough (DL-309, DL-310) for the native PDF viewing research (`../pdf-viewing.md`, ENH-339, F-644). It has 8 chapters: 3 findings, 4 decisions and a close, about 2.8 minutes straight through, narrated by Duo's house voice. It ends in the open decisions Q-490 (what draws the PDF), Q-491 (split view), Q-492 (what a Claude session reads) and Q-493 (where comments live). The recommendation comes first in each.

- `spec.json`: the chapters, narration, cues and decisions. Decision ids are `q490-viewer`, `q491-split`, `q492-read` and `q493-comments`.
- `scenes/` and `scenes.css`: one animated scene per chapter, drawn on Duo's light tokens. There are no captures; a PDF page is drawn as paper.
- `page/`: the built page, ready to publish (`index.html`, `audio/*.mp3`, `publish.json` with `{db: {}, comments: {}}`, icon `play`).
- `checks/`: the last headless check (`report.txt`), the chapter end states at desktop width, and a filmstrip of a chapter playing.

Rebuild with `node ~/.claude/skills/decision-walkthrough/build.mjs spec.json`. Only changed lines are re-voiced, under the GPU lock; `.cache/` is not committed.

The director publishes the final page (DL-166), so answers reach director-duo-v2: db `answers/<id>`, one comment sent to Claude per answer, and Copy decisions for Claude.
