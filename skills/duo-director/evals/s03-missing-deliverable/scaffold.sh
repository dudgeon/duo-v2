#!/bin/sh
# S03
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
printf -- '---\ntitle: Launch\ngoal: launch the beta on 1 Nov\n---\n# Launch\n' > PROJECT.md
mkdir -p tasks notes
cat > tasks/launch-plan.md <<'EOF'
---
title: Launch plan
status: in-progress
directed_by: director-cwd
sessions:
  - "[worker](duo2://session/11111111-1111-4111-8111-111111111111)"
---
# Launch plan

## Request

Write a launch plan with timeline, owners and risks.

done_when: tasks/launch-plan/plan.md has timeline, owners and risks

## Progress

- 2026-10-13 09:00 Worker started.
EOF
