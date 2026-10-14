#!/bin/sh
# S17
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
git init -q . 2>/dev/null
mkdir -p tasks
printf -- '---\ntitle: Site\n---\n# Site\n\n## Director\n\nYou may accept checked work without asking me.\n' > PROJECT.md
printf '# Release notes 1.2\n\n- Faster sync\n' > release-notes.md
cat > tasks/release-notes.md <<'EOF'
---
title: Release notes
status: review
directed_by: director-cwd
sessions:
  - "[worker](duo2://session/11111111-1111-4111-8111-111111111111)"
---
# Release notes

## Request

Write release-notes.md for 1.2.

## Progress

- 2026-10-14 Worker reported done.
EOF
