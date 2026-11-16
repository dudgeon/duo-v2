#!/bin/sh
# S10
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"; . "$lib/fixtures.sh"
printf -- '---\ntitle: Launch\ngoal: launch the beta on %s\n---\n# Launch\n' "$(dmon $((-18 * D)))" > PROJECT.md
mkdir -p tasks notes
mkdir -p .duo
printf '{"schema":1,"current":{"name":"director-launch-2","sessionId":"99999999-9999-4999-8999-999999999999","since":"%s"},"retired":[],"pending":[]}' "$(agoz $((2 * H)) '%Y-%m-%dT%H:%M:%SZ')" > .duo/director.json
cat > tasks/press-kit.md <<EOF
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
