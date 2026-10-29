#!/bin/zsh
# Runs the editor module's checks that need no browser (critic.js: the CriticMarkup parse and Suggest Edits; lists.js: ordered lists renumber).
set -e
cd "${0:A:h}/.."
[[ -d node_modules ]] || npm ci --no-audit --no-fund
out="${TMPDIR:-/tmp}/duo-critic-test.cjs"
./node_modules/.bin/esbuild test/critic.test.mjs --bundle --platform=node --format=cjs --outfile="$out" --log-level=error
node "$out"
out2="${TMPDIR:-/tmp}/duo-lists-test.cjs"
./node_modules/.bin/esbuild test/lists.test.mjs --bundle --platform=node --format=cjs --outfile="$out2" --log-level=error
node "$out2"
out3="${TMPDIR:-/tmp}/duo-atmenu-test.cjs"
./node_modules/.bin/esbuild test/atmenu.test.mjs --bundle --platform=node --format=cjs --outfile="$out3" --log-level=error
node "$out3"
