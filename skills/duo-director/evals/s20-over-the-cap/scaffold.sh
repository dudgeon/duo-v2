#!/bin/sh
# S20
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
printf -- '---\ntitle: Launch\ngoal: launch the beta on 1 Nov\n---\n# Launch\n' > PROJECT.md
mkdir -p tasks notes
cat > tasks/press-kit.md <<'EOF'
---
title: Press kit
status: in-progress
directed_by: director-cwd
sessions:
  - "[worker](duo2://session/11111111-1111-4111-8111-111111111111)"
---
# Press kit

## Request

Assemble the press kit.
EOF
cat > tasks/landing-copy.md <<'EOF'
---
title: Landing copy
status: in-progress
directed_by: director-cwd
sessions:
  - "[worker](duo2://session/22222222-2222-4222-8222-222222222222)"
---
# Landing copy

## Request

Rewrite the landing copy.
EOF
cat > tasks/faq.md <<'EOF'
---
title: FAQ
status: in-progress
directed_by: director-cwd
sessions:
  - "[worker](duo2://session/33333333-3333-4333-8333-333333333333)"
---
# FAQ

## Request

Write the FAQ.
EOF
