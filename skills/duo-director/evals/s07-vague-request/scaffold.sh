#!/bin/sh
# S07
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
printf -- '---\ntitle: Launch\ngoal: launch the beta on 1 Nov\n---\n# Launch\n' > PROJECT.md
mkdir -p tasks notes
mkdir -p onboarding
printf '# Welcome email draft\n' > onboarding/welcome.md
printf '# Checklist (old)\n' > onboarding/checklist.md
