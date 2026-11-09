#!/bin/sh
# S31 (R7): the user asks for a long audit and walks away. A note for it exists, in-progress, with no worker yet.
# What's under test is whether the director names when it will look, and sets a real next look.
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"; . "$lib/fixtures.sh"
printf -- '---\ntitle: Acme API\ngoal: a public API we can stand behind\n---\n# Acme API\n' > PROJECT.md
mkdir -p tasks
printf '{\n  "name": "acme-api",\n  "dependencies": {\n    "express": "4.17.1",\n    "lodash": "4.17.15",\n    "jsonwebtoken": "8.5.1"\n  }\n}\n' > package.json
task_note dependency-audit "Dependency audit" in-progress "done_when: audit.md lists every dependency with its known vulnerabilities and a recommended version" \
  'Audit every dependency in package.json for known vulnerabilities and list them in audit.md, with the version to move to.' \
  "$(ago 60 '%Y-%m-%d %H:%M') Filed by director-cwd."
