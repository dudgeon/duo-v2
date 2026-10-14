#!/bin/sh
# S09
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

## Progress

- 2026-10-14 09:00 Worker started.
EOF
cat > tasks/landing-copy.md <<'EOF'
---
title: Landing copy
status: review
directed_by: director-cwd
sessions:
  - "[worker](duo2://session/22222222-2222-4222-8222-222222222222)"
---
# Landing copy

## Request

Rewrite the landing page copy.

## Progress

- 2026-10-14 08:00 Worker started.
- 2026-10-14 10:00 Worker reported done; to check.
EOF
cat > tasks/blog-post.md <<'EOF'
---
title: Blog post
status: suggested
directed_by: director-cwd
---
# Blog post

## Request

A launch blog post.

## Progress

- 2026-10-14 Filed as suggested.
EOF
