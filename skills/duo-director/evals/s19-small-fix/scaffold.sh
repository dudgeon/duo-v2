#!/bin/sh
# S19
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
printf -- '---\ntitle: Launch\ngoal: launch the beta on 1 Nov\n---\n# Launch\n' > PROJECT.md
mkdir -p tasks notes
mkdir -p docs
printf '# Guide\n\nYou will recieve an email.\n' > docs/guide.md
