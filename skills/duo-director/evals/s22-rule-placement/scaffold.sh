#!/bin/sh
# S22 (DL-207)
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
mkdir -p alpha/tasks
printf -- '---\ntitle: Home\n---\n# Home\n\n## Projects\n\n- alpha\n' > HOME.md
printf -- '---\ntitle: Alpha\n---\n# Alpha\n' > alpha/PROJECT.md
