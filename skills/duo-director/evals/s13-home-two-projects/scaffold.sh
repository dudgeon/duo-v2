#!/bin/sh
# S13
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"; . "$lib/fixtures.sh"
mkdir -p alpha/.duo beta tasks
printf -- '---\ntitle: Home\n---\n# Home\n' > HOME.md
printf -- '---\ntitle: Alpha\n---\n# Alpha\n' > alpha/PROJECT.md
printf -- '---\ntitle: Beta\n---\n# Beta\n' > beta/PROJECT.md
printf '# Typos\n\n- recieve\n' > beta/typos.md
printf '# Changelog\n' > alpha/CHANGELOG.md
printf '{"schema":1,"current":{"name":"director-alpha","sessionId":"88888888-8888-4888-8888-888888888888","since":"%s"},"retired":[],"pending":[]}' "$(agoz $((2 * H)) '%Y-%m-%dT%H:%M:%SZ')" > alpha/.duo/director.json
