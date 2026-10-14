#!/bin/sh
# S10
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
printf -- '---\ntitle: Launch\ngoal: launch the beta on 1 Nov\n---\n# Launch\n' > PROJECT.md
mkdir -p tasks notes
mkdir -p .duo
printf '{"schema":1,"current":{"name":"director-launch-2","sessionId":"99999999-9999-4999-8999-999999999999","since":"2026-10-14T08:00:00-04:00"},"retired":[],"pending":[]}' > .duo/director.json
cat > tasks/press-kit.md <<'EOF'
---
title: Press kit
status: in-progress
directed_by: director-launch-2
sessions:
  - "[worker](duo2://session/11111111-1111-4111-8111-111111111111)"
---
# Press kit

## Request

Assemble the press kit.
EOF
