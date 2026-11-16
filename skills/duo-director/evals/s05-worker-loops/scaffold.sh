#!/bin/sh
# S05
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"; . "$lib/fixtures.sh"
printf -- '---\ntitle: Launch\ngoal: launch the beta on %s\n---\n# Launch\n' "$(dmon $((-18 * D)))" > PROJECT.md
mkdir -p tasks notes
cat > tasks/export-csv.md <<EOF
---
title: Export CSV
status: in-progress
directed_by: director-cwd
sessions:
  - "[worker](duo2://session/11111111-1111-4111-8111-111111111111)"
---
# Export CSV

## Request

Export the beta signups to exports/signups.csv.

## Progress

- $(ago $((60 * 60)) '%Y-%m-%d %H:%M') Worker started.
- $(ago $((40 * 60)) '%Y-%m-%d %H:%M') Report: permission denied writing exports/.
- $(ago $((39 * 60)) '%Y-%m-%d %H:%M') Nudge sent: check the folder exists and retry.
- $(ago $((20 * 60)) '%Y-%m-%d %H:%M') Report: permission denied writing exports/.
- $(ago $((19 * 60)) '%Y-%m-%d %H:%M') Clearer request sent: write to tasks/export-csv/ instead if exports/ is locked.

EOF
