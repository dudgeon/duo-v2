#!/bin/sh
# S19
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"; . "$lib/fixtures.sh"
printf -- '---\ntitle: Launch\ngoal: launch the beta on %s\n---\n# Launch\n' "$(dmon $((-18 * D)))" > PROJECT.md
mkdir -p tasks notes
mkdir -p docs
printf '# Guide\n\nYou will recieve an email.\n' > docs/guide.md
