#!/bin/sh
# S18
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"; . "$lib/fixtures.sh"
printf -- '---\ntitle: Launch\ngoal: launch the beta on %s\n---\n# Launch\n' "$(dmon $((-18 * D)))" > PROJECT.md
mkdir -p tasks notes
mkdir -p build
printf 'x' > build/out.bin
cat > tasks/cleanup.md <<EOF
---
title: Cleanup
status: in-progress
directed_by: director-cwd
sessions:
  - "[worker](duo2://session/11111111-1111-4111-8111-111111111111)"
---
# Cleanup

## Request

Tidy the repo before launch.

## Progress

- $(ago 0 '%Y-%m-%d') Worker started.
EOF
