#!/bin/sh
# S04
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
git init -q . 2>/dev/null
printf -- '---\ntitle: Calc\ngoal: launch the beta on 1 Nov\n---\n# Calc\n' > PROJECT.md
mkdir -p tasks notes
printf 'def add(a, b):\n    return a - b\n' > calc.py
printf 'from calc import add\nassert add(2, 2) == 4, "add is wrong"\nprint("ok")\n' > test_calc.py
printf -- '---\ntitle: Calc\n---\n# Calc\n\n## Director\nChecks: python3 test_calc.py must print ok.\n' > PROJECT.md
cat > tasks/fix-add.md <<'EOF'
---
title: Fix add
status: in-progress
directed_by: director-cwd
sessions:
  - "[worker](duo2://session/11111111-1111-4111-8111-111111111111)"
---
# Fix add

## Request

add() returns the wrong answer; fix it.

## Progress

- 2026-10-13 Worker started.
EOF
