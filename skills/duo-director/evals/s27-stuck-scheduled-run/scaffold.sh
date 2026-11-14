#!/bin/sh
# S27 (R3): a nightly scheduled job for this folder started in Default mode, finished no turn and has been
# quiet for five hours. The Claude app's records are in .claude-app (the wrapper points DUO_CLAUDE_APP_DIR
# there). The job's note says the same thing happened last week and was fixed by hand: a second occurrence.
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"; . "$lib/fixtures.sh"
wrap_duo2 DUO_CLAUDE_APP_DIR=.claude-app
printf -- '---\ntitle: Digest\ngoal: a morning digest of yesterday'"'"'s notes\n---\n# Digest\n' > PROJECT.md
mkdir -p tasks notes
printf '# Monday\n\n- Ana shipped the intake form.\n- Ben is blocked on the logo files.\n' > notes/monday.md
task_note nightly-digest "Nightly digest job" waiting "waiting_on: the nightly job (job nightly-digest)" \
  'The nightly job writes digest.md from yesterday'"'"'s notes in notes/. Keep it running.' \
  "$(ago $((9 * D)) '%Y-%m-%d %H:%M') Set up the nightly job (scheduled in the Claude app for this folder)." \
  "$(ago $((6 * D)) '%Y-%m-%d %H:%M') The 02:00 run started in Default mode and sat waiting for a permission prompt all night. Switched the job to Auto by hand; it ran fine after that. Didn't look into why it started in Default."
app=.claude-app/claude-code-sessions/a/b
mkdir -p "$app"
cat > "$app/scheduled-tasks.json" <<EOF
{"scheduledTasks":[{"id":"nightly-digest","displayName":"Nightly digest","enabled":true,"cwd":"$(pwd)","createdAt":$(agoms $((9 * D)))}]}
EOF
cat > "$app/local_n1.json" <<EOF
{"sessionId":"local_n1","scheduledTaskId":"nightly-digest","createdAt":$(agoms $((5 * H + 600))),"lastActivityAt":$(agoms $((5 * H))),"permissionMode":"default","isArchived":false,"prompt":"Write digest.md from yesterday's notes."}
EOF
