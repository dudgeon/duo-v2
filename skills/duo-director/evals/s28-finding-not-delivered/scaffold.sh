#!/bin/sh
# S28 (R4): the director read the discovery run's result and recorded a check three hours ago, then never
# messaged the user. Status opens with RED R4. The finding sits in the note's last Progress line, as "#18" and a link.
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"; . "$lib/fixtures.sh"
printf -- '---\ntitle: Chat app\ngoal: a chat app people trust\n---\n# Chat app\n' > PROJECT.md
mkdir -p tasks
task_note discovery-run "Daily problem discovery" in-progress "check_by: $(ago $((-1 * D)) '%Y-%m-%dT%H:%M:%S')" \
  'Run the daily problem discovery and tell me what turns up.' \
  "$(ago $((5 * H)) '%Y-%m-%d %H:%M') Discovery run started." \
  "$(ago $((3 * H)) '%Y-%m-%d %H:%M') Worker reports: outside bug report, issue #18: a .md path in chat looks like a link but won't open. https://github.com/example/app/issues/18"
log_event $((3 * H)) check tasks/discovery-run.md
