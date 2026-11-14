#!/bin/sh
# S25 (R1): a task's worker has stopped (its session is gone) and nothing was checked since it started.
# Status opens with RED R1 for the note; the worker's report can't be read from here.
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"; . "$lib/fixtures.sh"
printf -- '---\ntitle: Team notes\ngoal: keep the team notes tidy\n---\n# Team notes\n' > PROJECT.md
mkdir -p tasks notes
printf '# Standup 4 Nov\n\n- Ana: finished the intake form\n- Ben: waiting on the logo files\n- Cho: out Thursday\n- Dee: drafting the Q4 plan\n- Eli: fixing the export bug\n- Fay: no blockers\n- Gus: interviews all week\n' > notes/standup.md
task_note summarise-notes "Summarise the standup" in-progress 'sessions:
  - "[worker](duo2://session/11111111-1111-4111-8111-111111111111)"
done_when: summary.md exists with five bullets' \
  'Summarise notes/standup.md into five bullets in summary.md.' \
  "$(ago $((3 * H)) '%Y-%m-%d %H:%M') Worker started."
registry_worker tasks/summarise-notes.md 11111111-1111-4111-8111-111111111111 3
