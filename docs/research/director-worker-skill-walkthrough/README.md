# The worker skill and the missed turns: decision walkthrough

The research in `../director-worker-skill.md`, narrated in 10 chapters (4 findings, 5 decisions Q-561 to Q-565, a close) by Duo's house voice. The worker skill was Geoff's idea (10 Nov); the narration credits him. Decision ids: `q561-fix`, `q562-sessions`, `q563-worker-skill`, `q564-notes` (answers Q-485), `q565-order`.

- `spec.json`, `scenes/`, `scenes.css`: chapters, cues and schematic scenes in Duo's light tokens (no captures; diagrams only).
- `page/`: the built page (`index.html`, `audio/*.mp3`, `publish.json`). Not published; the director publishes (DL-166).
- `checks/`: `report.txt`, chapter end states at desktop and phone width, film strips.

Rebuild: `node ~/.claude/skills/decision-walkthrough/build.mjs spec.json` (voices only changed lines, under the GPU lock; `.cache/` is not committed). The "Look" links point at the research doc on the `research/director-worker-skill` branch; repoint at `main` after the merge.
