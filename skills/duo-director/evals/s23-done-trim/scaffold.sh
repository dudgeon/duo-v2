#!/bin/sh
# S23 (DL-209)
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"; . "$lib/fixtures.sh"
mkdir -p tasks notes
{ printf -- '---\ntitle: Launch\n---\n# Launch\n\n## Decisions\n\n- %s Beta first.\n\n## Done\n\n' "$(ago $((43 * D)) '%Y-%m-%d')"; i=1; while [ $i -le 20 ]; do printf -- '- %s Finished old task %d.\n' "$(ago $(((44 - i) * D)) '%Y-%m-%d')" $i; i=$((i+1)); done; } > PROJECT.md
cat > tasks/press-kit.md <<EOF
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

- $(ago 0 '%Y-%m-%d') Checked: all six assets present.
EOF
