#!/bin/bash
# Which kind of Duo build a checkout makes (F-198), for scripts/bundle.sh and scripts/check-launch-services.sh:
#
#   scripts/bundle-kind.sh [checkout]    prints main, release or test (default: this script's checkout)
#
#   main     the repository's main checkout (the folder holding the .git that `git rev-parse --git-common-dir`
#            names): bundle id com.dudgeon.duo, owns duo2:// links, registered with Launch Services.
#   release  a build for scripts/release.sh (DUO_RELEASE_BUILD=1): com.dudgeon.duo and duo2://, as installed
#            releases are, but never registered from the build folder.
#   test     everything else (session work trees, bisect and base checkouts in /tmp, scratchpads): bundle id
#            com.dudgeon.duo.test, no duo2:// scheme, never registered. macOS can't open one for com.dudgeon.duo
#            or a duo2:// link, whatever it has indexed (the 2026-10-07 relaunch opened a work tree's build).
set -euo pipefail
dir="$(cd "${1:-$(dirname "$0")/..}" && pwd -P)"
if [ "${DUO_RELEASE_BUILD:-}" = 1 ]; then echo release; exit 0; fi
top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || { echo test; exit 0; }
common="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || { echo test; exit 0; }
top="$(cd "$top" && pwd -P)"
# A linked work tree's common dir is the main checkout's .git; the main checkout's own .git is its own.
gitdir="$(git -C "$dir" rev-parse --path-format=absolute --git-dir)"
[ "$(basename "$common")" = .git ] && [ "$(cd "$(dirname "$common")" && pwd -P)" = "$top" ] \
  && [ "$(cd "$gitdir" && pwd -P)" = "$(cd "$common" && pwd -P)" ] || { echo test; exit 0; }
# A clone made for a bisect or a base build is a main checkout too, of its own .git: it's a test build when
# its origin is a folder on this Mac or it lives in a temporary or Claude folder.
origin="$(git -C "$dir" config --get remote.origin.url 2>/dev/null || true)"
case "$origin" in /*|file:*|.*) echo test; exit 0 ;; esac
tmp="$(cd "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P || echo /private/tmp)"
case "$top/" in /private/tmp/*|/tmp/*|/private/var/folders/*|"$tmp"/*|"$HOME"/.claude/*) echo test; exit 0 ;; esac
echo main
