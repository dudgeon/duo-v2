#!/bin/sh
# S02
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
printf -- '---\ntitle: Launch\ngoal: launch the beta on 1 Nov\n---\n# Launch\n' > PROJECT.md
mkdir -p tasks notes
printf '# App\n\n## Install\nrun the thing\n' > README.md
printf -- '- Q: does it sync? A: yes\n- Q: price? A: free in beta\n' > notes/faq-raw.md
