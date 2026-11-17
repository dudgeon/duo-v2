#!/bin/sh
# S07
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"; . "$lib/fixtures.sh"
printf -- '---\ntitle: Launch\ngoal: launch the beta on %s\n---\n# Launch\n' "$(dmon $((-18 * D)))" > PROJECT.md
mkdir -p tasks notes
mkdir -p onboarding
printf '# Welcome email draft\n' > onboarding/welcome.md
printf '# Checklist (old)\n' > onboarding/checklist.md
