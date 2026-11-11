# Chat turn actions decision walkthrough

The hover-actions study (`../chat-hover-actions.md`), narrated by Duo's house voice in nine chapters: three findings (why, what Claude Code does as F-652, what Duo has as F-653), five decisions (Q-505 which actions and where, Q-506 what Rewind restores, Q-507 how Duo rewinds, Q-508 fork from a turn, Q-509 what Copy copies), and a close. Each decision is recommendation first. The request is Geoff's own.

- `spec.json`: chapters, narration, cues and decisions.
- `make-scenes.py` writes `scenes/*.html` (a Duo chat pane with the study's row buttons, Claude's menu as a terminal, the sheet); `scenes.css` is the multi-window walkthrough's with the chat pane's additions at the end. Looks follow the canvas boards Row, Rewind, Fork, Copy.
- `page/`: the built page, ready to publish (`index.html`, `audio/*.mp3`, `publish.json`).
- `checks/`: the last headless check (`report.txt`), each chapter's end state at desktop and phone width, an option playing, and filmstrips of chapters that play.

Canvas: https://claude.ai/artifact/HLHzGsZNpn3hS1KsZAZx71 (sources in `docs/design/chat-hover-actions-study/`).

Rebuild with `node ~/.claude/skills/decision-walkthrough/build.mjs spec.json` (only changed lines are re-voiced, under the GPU lock; `.cache/` is not committed). Edit the scenes in `make-scenes.py`, then run `python3 make-scenes.py`. The director publishes the final page (DL-166), so answers reach director-duo-v2. Nothing is published yet.

The director publishes the final page (DL-166), so answers reach director-duo-v2. A worker's draft is at https://claude.ai/artifact/P77HtNBoU2NSZP6YK98Q7K.
