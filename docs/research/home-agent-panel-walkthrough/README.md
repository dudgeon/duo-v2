# Home agent panel decision walkthrough

The Home agent panel study (`../home-agent-panel.md`), narrated by Duo's house voice in nine chapters: three findings (why now, what the column costs, five ways out), five decisions (Q-498 the panel's shape, Q-499 the launch start, Q-500 migration, Q-501 the sidebar button, Q-488 narrow-pane questions), and a close. About 2.1 minutes straight through. Each decision is recommendation first.

- `spec.json`: chapters, narration, cues and decisions.
- `make-scenes.py` writes `scenes/*.html` (a shared All projects window plus each chapter's callouts); `scenes.css` is the multi-window walkthrough's with this walkthrough's additions at the end. `assets/f648-launch.jpg` is F-648's capture (an isolated Duo on sample data).
- `page/`: the built page, ready to publish (`index.html`, `audio/*.mp3`, `assets/`, `publish.json`).
- `checks/`: the last headless check (`report.txt`), each chapter's end state at desktop and phone width, an option playing.

Sketches are on the canvas https://claude.ai/artifact/PBJttSgB17RzCn8WQQo6sF (boards C1, C2, A, B, D2; sources in `docs/design/home-agent-panel-study/`).

Rebuild with `node ~/.claude/skills/decision-walkthrough/build.mjs spec.json` (only changed lines are re-voiced, under the GPU lock; `.cache/` is not committed). The director publishes the final page (DL-166), so answers reach director-duo-v2. A worker's draft is at https://claude.ai/artifact/L3Pd83Fhyf4HjQcfvTuZct.
