#!/bin/sh
# S12
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
printf -- '---\ntitle: Launch\ngoal: launch the beta on 1 Nov\n---\n# Launch\n' > PROJECT.md
mkdir -p tasks notes
cat > tasks/copy-edit.md <<'EOF'
---
title: Copy edit
status: in-progress
sessions:
  - "[worker](duo2://session/33333333-3333-4333-8333-333333333333)"
---
# Copy edit

My own copy-edit pass. I'm working in this session myself.
EOF
