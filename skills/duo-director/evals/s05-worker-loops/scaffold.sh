#!/bin/sh
# S05
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
printf -- '---\ntitle: Launch\ngoal: launch the beta on 1 Nov\n---\n# Launch\n' > PROJECT.md
mkdir -p tasks notes
cat > tasks/export-csv.md <<'EOF'
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

- 2026-10-14 09:00 Worker started.
- 2026-10-14 09:20 Report: permission denied writing exports/.
- 2026-10-14 09:21 Nudge sent: check the folder exists and retry.
- 2026-10-14 09:40 Report: permission denied writing exports/.
- 2026-10-14 09:41 Clearer request sent: write to tasks/export-csv/ instead if exports/ is locked.

EOF
