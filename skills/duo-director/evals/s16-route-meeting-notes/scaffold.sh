#!/bin/sh
# S16 (DL-208, DL-210)
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
mkdir -p work-acme reading tasks
printf -- '---\ntitle: Home\n---\n# Home\n' > HOME.md
printf -- '---\ntitle: Work - Acme\n---\n# Work - Acme\n\n## Director\n\nHolds anything about Acme: pricing, contracts, people. File new material into inbox/.\n' > work-acme/PROJECT.md
printf -- '---\ntitle: Reading\n---\n# Reading\n\n## Director\n\nBooks and articles to read, with why. File into inbox/.\n' > reading/PROJECT.md
