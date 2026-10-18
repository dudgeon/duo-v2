#!/bin/sh
# S17: a repo with a remote; the Director section lets the director accept checked work, and says nothing about pushing.
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
git init -q -b main . 2>/dev/null
git init -q --bare .remote.git 2>/dev/null
git remote add origin ./.remote.git
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
