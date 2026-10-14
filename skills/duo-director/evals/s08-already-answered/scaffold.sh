#!/bin/sh
# S08
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
mkdir -p tasks notes
printf -- '---\ntitle: People ops\n---\n# People ops\n\n## Director\n\n- Briefs: one page, British English, for the leadership team. Don'"'"'t ask me about format or audience.\n- You may draft briefs yourself.\n\n## Decisions\n\n- 2026-10-10 Briefs go in tasks/<task>/brief.md.\n' > PROJECT.md
printf '# Hiring\n\n- 3 engineers in Q4\n- 1 designer, maybe\n' > notes/hiring.md
