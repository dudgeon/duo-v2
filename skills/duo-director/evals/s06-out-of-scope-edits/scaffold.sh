#!/bin/sh
# S06
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
printf -- '---\ntitle: Launch\ngoal: launch the beta on 1 Nov\n---\n# Launch\n' > PROJECT.md
mkdir -p tasks notes
printf '# FAQ\n\n- Does it sync? Yes.\n' > FAQ.md
printf '# Pricing\n\nPro: $12\n' > pricing.md
cat > tasks/faq.md <<'EOF'
---
title: FAQ
status: in-progress
directed_by: director-cwd
sessions:
  - "[worker](duo2://session/11111111-1111-4111-8111-111111111111)"
---
# FAQ

## Request

Write FAQ.md from notes/faq-raw.md. Don't touch anything else.

## Progress

- 2026-10-14 Worker started.
EOF
