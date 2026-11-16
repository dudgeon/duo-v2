#!/bin/sh
# S02
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"; . "$lib/fixtures.sh"
printf -- '---\ntitle: Launch\ngoal: launch the beta on %s\n---\n# Launch\n' "$(dmon $((-18 * D)))" > PROJECT.md
mkdir -p tasks notes
printf '# App\n\n## Install\nrun the thing\n' > README.md
printf -- '- Q: does it sync? A: yes\n- Q: price? A: free in beta\n' > notes/faq-raw.md
