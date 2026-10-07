#!/bin/bash
# macOS only ever opens Geoff's Duo (F-198): only the main checkout's build and installed releases are
# com.dudgeon.duo in Launch Services, and they alone take duo2:// links.
#
#   scripts/check-launch-services.sh            the build rules, then this Mac's Launch Services
#   scripts/check-launch-services.sh --rules    the build rules only (no Launch Services state; for any Mac)
#   scripts/check-launch-services.sh --clean    first unregister every com.dudgeon.duo app that isn't allowed
#
# Allowed for com.dudgeon.duo: <main checkout>/build/Duo.app and anything under /Applications or
# ~/Applications. Release outputs (build/release/<v>/Duo.app) stay unregistered. Nothing is launched or deleted.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
mode="${1:-}"
fails=0
ok() { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fails=$((fails + 1)); }

common="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)"
main="$(cd "$(dirname "$common")" && pwd -P)"
main_app="$main/build/Duo.app"

# --- The build rules: which checkouts make com.dudgeon.duo builds.
kind() { DUO_RELEASE_BUILD= "$root/scripts/bundle-kind.sh" "$1"; }
[ "$(kind "$main")" = main ] && ok "the main checkout ($main) builds com.dudgeon.duo" || bad "the main checkout isn't kind main: $(kind "$main")"
[ "$(DUO_RELEASE_BUILD=1 "$root/scripts/bundle-kind.sh" "$main")" = release ] && ok "DUO_RELEASE_BUILD=1 makes a release build" || bad "DUO_RELEASE_BUILD=1 isn't kind release"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/duo-ls.XXXXXX")"
trap 'git -C "$main" worktree remove --force "$scratch/wt" >/dev/null 2>&1 || true; rm -rf "$scratch"' EXIT
git -C "$main" worktree add --detach --quiet "$scratch/wt" HEAD
[ "$(kind "$scratch/wt")" = test ] && ok "a fresh work tree builds com.dudgeon.duo.test" || bad "a fresh work tree is kind $(kind "$scratch/wt")"
git init --quiet "$scratch/clone" && git -C "$scratch/clone" remote add origin "$main"
[ "$(kind "$scratch/clone")" = test ] && ok "a local clone builds com.dudgeon.duo.test" || bad "a local clone is kind $(kind "$scratch/clone")"
mkdir -p "$scratch/plain"
[ "$(kind "$scratch/plain")" = test ] && ok "a folder outside git builds com.dudgeon.duo.test" || bad "a plain folder is kind $(kind "$scratch/plain")"
# bundle.sh takes the bundle id, the duo2:// scheme and registration from the kind, and registers only main.
b="$root/scripts/bundle.sh"
grep -q '<key>CFBundleIdentifier</key><string>${bundle_id}</string>' "$b" && ! grep -q '<string>duo2</string></array>$' <(sed -n '/<<PLIST/,/^PLIST/p' "$b") \
  && ok "bundle.sh's Info.plist takes its id and URL scheme from the kind" || bad "bundle.sh's Info.plist hard-codes the id or the duo2 scheme"
[ "$(grep -c 'lsregister" -f' "$b")" = 1 ] && grep -B1 'lsregister" -f' "$b" | grep -q 'kind" = main' \
  && ok "bundle.sh registers only a main build" || bad "bundle.sh registers builds other than main"
# This checkout's own build, if there is one, is the kind it should be.
if [ -f "$root/build/Duo.app/Contents/Info.plist" ]; then
  want=com.dudgeon.duo; [ "$(kind "$root")" = test ] && want=com.dudgeon.duo.test
  have="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$root/build/Duo.app/Contents/Info.plist")"
  scheme="$(/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes:0" "$root/build/Duo.app/Contents/Info.plist" 2>/dev/null || true)"
  [ "$have" = "$want" ] && ok "this checkout's build is $have" || bad "this checkout's build is $have, not $want (rebuild with scripts/bundle.sh)"
  if [ "$want" = com.dudgeon.duo.test ]; then
    [ -z "$scheme" ] && ok "this checkout's build doesn't claim duo2://" || bad "this checkout's test build claims $scheme://"
  fi
fi
[ "$mode" = --rules ] && { [ "$fails" = 0 ] && echo "launch services rules ok" || echo "$fails failed"; exit "$((fails > 0))"; }

# --- This Mac: every app Launch Services has for com.dudgeon.duo.
allowed() { [ "$1" = "$main_app" ] || [[ "$1" == /Applications/* ]] || [[ "$1" == "$HOME/Applications/"* ]]; }
registered() {
  "$lsregister" -dump 2>/dev/null | awk '
    /^-+$/ { if (id == "com.dudgeon.duo" && path != "") print path; id = ""; path = "" }
    /^path:/ { sub(/^path:[ \t]+/, ""); sub(/ \(0x[0-9a-f]+\)$/, ""); path = $0 }
    /^identifier:/ { id = $2 }
    END { if (id == "com.dudgeon.duo" && path != "") print path }' | sort -u
}
if [ "$mode" = --clean ]; then
  while IFS= read -r p; do
    allowed "$p" && continue
    "$lsregister" -u "$p" >/dev/null 2>&1 || true
    echo "unregistered $p"
  done < <(registered)
fi
while IFS= read -r p; do
  allowed "$p" && ok "registered: $p" || bad "registered but not allowed: $p (scripts/check-launch-services.sh --clean)"
done < <(registered)
# What Launch Services would open, asked without opening anything.
res="$(swift "$root/scripts/ls-resolve.swift" com.dudgeon.duo "duo2://session/check")"
for k in id-default url-default; do
  p="$(awk -v k="$k" '$1 == k { sub(/^[^ ]+ /, ""); print; exit }' <<<"$res")"
  if [ -z "$p" ]; then bad "$k: nothing (is $main_app built?)"
  elif allowed "$p"; then ok "$k: $p"
  else bad "$k: $p"; fi
done
while IFS= read -r p; do
  [ -n "$p" ] || continue
  allowed "$p" || bad "claims duo2://: $p"
done < <(awk '$1 == "url" { sub(/^[^ ]+ /, ""); print }' <<<"$res")
[ "$fails" = 0 ] && echo "launch services ok" || echo "$fails failed"
exit "$((fails > 0))"
