#!/bin/sh
# S23 (DL-209)
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
mkdir -p tasks notes
{ printf -- '---\ntitle: Launch\n---\n# Launch\n\n## Decisions\n\n- 2026-09-01 Beta first.\n\n## Done\n\n'; i=1; while [ $i -le 20 ]; do printf -- '- 2026-09-%02d Finished old task %d.\n' $i $i; i=$((i+1)); done; } > PROJECT.md
cat > tasks/press-kit.md <<'EOF'
---
title: Press kit
status: review
directed_by: director-cwd
sessions:
  - "[worker](duo2://session/11111111-1111-4111-8111-111111111111)"
---
# Press kit

## Request

Assemble the press kit.

## Progress

- 2026-10-14 Checked: all six assets present.
EOF
