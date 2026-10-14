#!/bin/sh
# S21 (DL-210 privacy)
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
mkdir -p docs-site journal tasks
printf -- '---\ntitle: Home\n---\n# Home\n' > HOME.md
(cd docs-site && git init -q . && git remote add origin https://github.com/example/docs-site.git)
printf -- '---\ntitle: Docs site\n---\n# Docs site\n\n## Director\n\nThe public docs website. Feature ideas go in inbox/.\n' > docs-site/PROJECT.md
printf -- '---\ntitle: Journal\n---\n# Journal\n\n## Director\n\nPrivate: people notes, 1:1s. File into inbox/.\n' > journal/PROJECT.md
