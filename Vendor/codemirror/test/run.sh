#!/bin/zsh
# Runs the editor module's checks that need no browser (critic.js: the CriticMarkup parse and Suggest Edits).
set -e
cd "${0:A:h}/.."
[[ -d node_modules ]] || npm ci --no-audit --no-fund
out="${TMPDIR:-/tmp}/duo-critic-test.cjs"
./node_modules/.bin/esbuild test/critic.test.mjs --bundle --platform=node --format=cjs --outfile="$out" --log-level=error
node "$out"
