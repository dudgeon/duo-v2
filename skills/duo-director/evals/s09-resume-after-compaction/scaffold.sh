#!/bin/sh
# S09
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"; . "$lib/fixtures.sh"
printf -- '---\ntitle: Launch\ngoal: launch the beta on %s\n---\n# Launch\n' "$(dmon $((-18 * D)))" > PROJECT.md
mkdir -p tasks notes
cat > tasks/press-kit.md <<EOF
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

- $(ago $((2 * H)) '%Y-%m-%d %H:%M') Worker started.
EOF
cat > tasks/landing-copy.md <<EOF
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

- $(ago $((3 * H)) '%Y-%m-%d %H:%M') Worker started.
- $(ago $((1 * H)) '%Y-%m-%d %H:%M') Worker reported done; to check.
EOF
cat > tasks/blog-post.md <<EOF
---
title: Blog post
status: suggested
directed_by: director-cwd
---
# Blog post

## Request

A launch blog post.

## Progress

- $(ago 0 '%Y-%m-%d') Filed as suggested.
EOF
