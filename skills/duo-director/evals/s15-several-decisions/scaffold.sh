#!/bin/sh
# S15
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
printf -- '---\ntitle: Launch\ngoal: launch the beta on 1 Nov\n---\n# Launch\n' > PROJECT.md
mkdir -p tasks notes
mkdir -p tasks/launch
printf '# Open decisions\n\n1. Launch day: Tuesday 1 Nov or Thursday 3 Nov (Tuesday gives a week before the conference).\n2. Beta size: 50 or 200 testers (support can handle about 80).\n3. Pricing page live at launch or a week later.\n' > tasks/launch/decisions.md
