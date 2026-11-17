#!/bin/sh
# S14
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"; . "$lib/fixtures.sh"
printf -- '---\ntitle: Launch\ngoal: launch the beta on %s\n---\n# Launch\n' "$(dmon $((-18 * D)))" > PROJECT.md
mkdir -p tasks notes
printf '# FAQ\n\n- Does it sync? Yes.\n- Price? Free in beta.\n' > FAQ.md
printf -- '- Q: does it sync? A: yes\n- Q: price? A: free in beta\n' > notes/faq-raw.md
cat > tasks/faq.md <<EOF
---
title: FAQ
status: in-progress
directed_by: director-cwd
sessions:
  - "[worker](duo2://session/11111111-1111-4111-8111-111111111111)"
---
# FAQ

## Request

Write FAQ.md from notes/faq-raw.md.

done_when: FAQ.md answers every question in notes/faq-raw.md

## Progress

- $(ago 0 '%Y-%m-%d') Worker started.
EOF
