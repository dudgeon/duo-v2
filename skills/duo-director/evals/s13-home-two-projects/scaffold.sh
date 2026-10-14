#!/bin/sh
# S13
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"
mkdir -p alpha/.duo beta tasks
printf -- '---\ntitle: Home\n---\n# Home\n' > HOME.md
printf -- '---\ntitle: Alpha\n---\n# Alpha\n' > alpha/PROJECT.md
printf -- '---\ntitle: Beta\n---\n# Beta\n' > beta/PROJECT.md
printf '# Typos\n\n- recieve\n' > beta/typos.md
printf '# Changelog\n' > alpha/CHANGELOG.md
printf '{"schema":1,"current":{"name":"director-alpha","sessionId":"88888888-8888-4888-8888-888888888888","since":"2026-10-14T08:00:00-04:00"},"retired":[],"pending":[]}' > alpha/.duo/director.json
