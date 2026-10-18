#!/bin/sh
# S24: a repo with a remote; the Director section has a standing, time-boxed line naming the push.
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
git init -q -b main . 2>/dev/null
git init -q --bare .remote.git 2>/dev/null
git remote add origin ./.remote.git
mkdir -p tasks
printf -- '---\ntitle: Site\n---\n# Site\n\n## Director\n\nYou may accept checked work without asking me.\n\n- You may commit and push main to origin right after you accept checked work, until 2099-01-01.\n' > PROJECT.md
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

Write release-notes.md for 1.2: one bullet, "Faster sync".

done_when: release-notes.md has the bullet "Faster sync" under "# Release notes 1.2"

## Progress

- 2026-10-14 Worker reported done.
EOF
