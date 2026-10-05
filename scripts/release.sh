#!/bin/bash
# Cuts a Duo release: build, Developer ID signing, notarization, a stapled DMG, then a GitHub release.
#
#   scripts/release.sh 0.1.0                    build HEAD, sign, notarize, tag v0.1.0, publish on GitHub
#   scripts/release.sh 0.1.0 --notes notes.md   release notes from a file (default: GitHub's generated notes)
#   scripts/release.sh 0.1.0 --draft            upload as a draft release
#   scripts/release.sh 0.1.0 --no-publish       stop after the verified DMG: no tag, no upload
#
# Builds from a clean worktree of HEAD, so uncommitted changes never ship and build/Duo.app is untouched.
# The git tag is the single version source (LR-61). Every build is launched before it ships (LR-61): once
# signed, and again from the mounted DMG. Signing material lives in ~/.duo-signing (its README.md says
# what each file is); DUO_SIGNING_DIR overrides it. Takes 10–20 minutes, most of it Apple's notary service.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

die() { echo "release: $*" >&2; exit 1; }
step() { echo; echo "== $*"; }

version="" notes="" draft="" publish=1
while [ $# -gt 0 ]; do
  case "$1" in
    --notes) notes="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"; shift ;;
    --draft) draft=1 ;;
    --no-publish) publish="" ;;
    -*) die "unknown option $1" ;;
    *) version="$1" ;;
  esac
  shift
done
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || die "usage: scripts/release.sh <x.y.z> [--notes file] [--draft] [--no-publish]"
tag="v$version"
[ -z "$notes" ] || [ -f "$notes" ] || die "no notes file at $notes"

signing="${DUO_SIGNING_DIR:-$HOME/.duo-signing}"
keychain="$signing/duo-signing.keychain-db"
profile="${DUO_NOTARY_PROFILE:-duo-notary}"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

step "Preflight"
commit="$(git rev-parse HEAD)"
echo "commit   $(git log -1 --format='%h %s' "$commit")"
[ -z "$(git status --porcelain --untracked-files=no)" ] || echo "note: the working tree has uncommitted changes; they are not in this release"
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && die "tag $tag already exists"
if [ -n "$publish" ]; then
  gh auth status >/dev/null 2>&1 || die "gh is not logged in (gh auth login)"
  [ -z "$(git ls-remote --tags origin "refs/tags/$tag")" ] || die "tag $tag already exists on origin"
  ! gh release view "$tag" >/dev/null 2>&1 || die "GitHub release $tag already exists"
  git branch -r --contains "$commit" | grep -q . || echo "note: $(git rev-parse --short "$commit") isn't on origin yet; pushing the tag uploads it"
fi
[ -f "$keychain" ] && [ -f "$signing/keychain-password" ] || die "no signing keychain in $signing (see its README.md)"
security unlock-keychain -p "$(cat "$signing/keychain-password")" "$keychain"
identity="$(security find-identity -v -p codesigning "$keychain" | awk '/Developer ID Application/ {print $2; exit}')"
[ -n "$identity" ] || die "no valid Developer ID Application identity in $keychain"
echo "identity $(security find-identity -v -p codesigning "$keychain" | awk -v h="$identity" '$2==h {$1=$2=""; print; exit}')"
xcrun notarytool history --keychain-profile "$profile" --keychain "$keychain" >/dev/null 2>&1 \
  || die "notary profile '$profile' doesn't work (see $signing/README.md)"
# Sparkle (in-app updates): its signing tool and the update key, both outside the repo.
sign_update="$signing/sparkle-bin/sign_update"
sparkle_key="$signing/sparkle-ed25519.key"
[ -x "$sign_update" ] && [ -f "$sparkle_key" ] || die "no Sparkle signing tool or key in $signing (see Vendor/Sparkle/README.md)"

out="$root/build/release/$version"
rm -rf "$out"
mkdir -p "$out"
work="$(mktemp -d "${TMPDIR:-/tmp}/duo-release.XXXXXX")"
mnt=""
cleanup() {
  [ -z "$mnt" ] || hdiutil detach -quiet "$mnt" 2>/dev/null || true
  git -C "$root" worktree remove --force "$work/src" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

# Launches an app the way a user would and requires a captured frame (LR-61: a DMG that crashed on launch
# once passed signing and notarization). Capture runs use a private control socket (C-18).
launch_check() {
  local app="$1" png="$out/launch-$2.png" pid i
  rm -f "$png"
  open -W -n --stdout /dev/null --stderr "$out/launch-$2.log" "$app" --args --state overview --capture "$png" &
  pid=$!
  for ((i = 0; i < 120; i++)); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
  if kill -0 "$pid" 2>/dev/null; then kill "$pid"; die "launch check ($2): no window after 30 s (see $out/launch-$2.log)"; fi
  wait "$pid" || die "launch check ($2): the app failed (see $out/launch-$2.log)"
  [ -s "$png" ] || die "launch check ($2): no capture (see $out/launch-$2.log)"
  # Launching registers the copy for duo2:// links; leave those with the working build/Duo.app.
  "$lsregister" -u "$app" >/dev/null 2>&1 || true
  echo "launch check ($2): ok"
}

# Submits a file to Apple's notary service and waits; prints Apple's log on rejection.
notarize() {
  local file="$1" json="$out/notary-$(basename "$1").json" id status
  xcrun notarytool submit "$file" --keychain-profile "$profile" --keychain "$keychain" --wait --timeout 30m \
    --output-format json >"$json" || true
  id="$(plutil -extract id raw -o - "$json" 2>/dev/null || true)"
  status="$(plutil -extract status raw -o - "$json" 2>/dev/null || true)"
  echo "notary $(basename "$file"): ${status:-no answer} ${id:+($id)}"
  if [ "$status" != "Accepted" ]; then
    local where=""
    if [ -n "$id" ]; then
      xcrun notarytool log "$id" --keychain-profile "$profile" --keychain "$keychain" "$out/notary-log.json" >/dev/null 2>&1 || true
      where=" (the notary log is in $out/notary-log.json)"
    fi
    die "notarization of $(basename "$file") failed: $(cat "$json")$where"
  fi
}

step "Build $tag from a clean worktree"
git worktree add --detach --quiet "$work/src" "$commit"
(cd "$work/src" && scripts/bundle.sh release >/dev/null)
built="$work/src/build/Duo.app"
[ -x "$built/Contents/MacOS/Duo" ] || die "the release build failed"
# bundle.sh registers its app for duo2:// links; don't leave that pointing into a temporary folder.
"$lsregister" -u "$built" >/dev/null 2>&1 || true

app="$out/Duo.app"
ditto --norsrc "$built" "$app"
plist="$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count "$commit")" "$plist"
xattr -cr "$app"
echo "built $(file -b "$app/Contents/MacOS/Duo"), version $version ($(git rev-list --count "$commit"))"

step "Sign with Developer ID (Hardened Runtime, secure timestamp)"
# Inside out: Sparkle's helper, its updater app and the framework as bundles; then every other nested
# Mach-O (duo2 in Helpers); then the app.
spk="$app/Contents/Frameworks/Sparkle.framework"
if [ -d "$spk" ]; then
  for part in "$spk/Versions/B/Autoupdate" "$spk/Versions/B/Updater.app" "$spk"; do
    codesign --force --options runtime --timestamp --keychain "$keychain" --sign "$identity" "$part"
  done
fi
while IFS= read -r f; do
  file -b "$f" | grep -q Mach-O || continue
  codesign --force --options runtime --timestamp --keychain "$keychain" --sign "$identity" "$f"
done < <(find "$app/Contents" -type f -perm +111 ! -path "$app/Contents/MacOS/*" ! -path "$app/Contents/Frameworks/*")
codesign --force --options runtime --timestamp --keychain "$keychain" --sign "$identity" "$app"
codesign --verify --deep --strict "$app" || die "the signed app doesn't verify"
codesign -d --entitlements - --xml "$app" 2>/dev/null | grep -q get-task-allow && die "the app carries get-task-allow"
echo "signed and verified"
launch_check "$app" signed

step "Notarize and staple the app"
ditto -c -k --keepParent "$app" "$work/Duo.zip"
notarize "$work/Duo.zip"
xcrun stapler staple -q "$app" && xcrun stapler validate -q "$app" || die "stapling the app failed"
echo "app stapled"

step "Make, sign, notarize and staple the DMG"
dmg="$out/Duo-$version.dmg"
mkdir -p "$work/dmg"
ditto "$app" "$work/dmg/Duo.app"
ln -s /Applications "$work/dmg/Applications"
hdiutil create -quiet -volname "Duo $version" -srcfolder "$work/dmg" -fs HFS+ -format UDZO -ov "$dmg"
codesign --force --timestamp --keychain "$keychain" --sign "$identity" "$dmg"
notarize "$dmg"
xcrun stapler staple -q "$dmg" && xcrun stapler validate -q "$dmg" || die "stapling the DMG failed"
echo "DMG stapled"

step "Verify what a user downloads"
spctl -a -t open --context context:primary-signature -vv "$dmg" 2>&1 | grep -q "source=Notarized Developer ID" \
  || die "Gatekeeper doesn't accept the DMG: $(spctl -a -t open --context context:primary-signature -vv "$dmg" 2>&1)"
mnt="$work/mnt"
mkdir -p "$mnt"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mnt" "$dmg"
spctl -a -t exec -vv "$mnt/Duo.app" 2>&1 | grep -q "source=Notarized Developer ID" \
  || die "Gatekeeper doesn't accept the app in the DMG: $(spctl -a -t exec -vv "$mnt/Duo.app" 2>&1)"
xcrun stapler validate -q "$mnt/Duo.app" || die "the app in the DMG has no stapled ticket"
launch_check "$mnt/Duo.app" dmg
hdiutil detach -quiet "$mnt"
mnt=""
(cd "$out" && shasum -a 256 "Duo-$version.dmg" >"Duo-$version.dmg.sha256")
echo "Gatekeeper accepts the DMG and the app; $(cut -d' ' -f1 "$out/Duo-$version.dmg.sha256")"

step "Sparkle feed (appcast.xml)"
# One item: this version, its signed DMG on this release, notes from the notes file. The app reads
# releases/latest/download/appcast.xml, so a pre-release never reaches it.
edsig="$("$sign_update" --ed-key-file "$sparkle_key" -p "$dmg")"
length="$(stat -f %z "$dmg")"
build="$(git rev-list --count "$commit")"
notes_html="$(python3 - "$notes" <<'PY'
import html, re, sys
p = sys.argv[1] if len(sys.argv) > 1 else ""
text = open(p).read() if p else ""
out, inlist = [], False
def inline(t):
    t = html.escape(t)
    t = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", t)
    return re.sub(r"`(.+?)`", r"<code>\1</code>", t)
for line in text.splitlines():
    if line.startswith("- "):
        if not inlist: out.append("<ul>"); inlist = True
        out.append("<li>" + inline(line[2:]) + "</li>"); continue
    if inlist: out.append("</ul>"); inlist = False
    if line.startswith("## "): out.append("<h3>" + inline(line[3:]) + "</h3>")
    elif line.strip(): out.append("<p>" + inline(line) + "</p>")
if inlist: out.append("</ul>")
print("\n".join(out))
PY
)"
cat > "$out/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Duo</title>
    <link>https://github.com/dudgeon/duo-v2/releases</link>
    <item>
      <title>Duo $version</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
$notes_html
      ]]></description>
      <enclosure url="https://github.com/dudgeon/duo-v2/releases/download/$tag/Duo-$version.dmg" length="$length" type="application/octet-stream" sparkle:edSignature="$edsig"/>
    </item>
  </channel>
</rss>
XML
"$sign_update" --ed-key-file "$sparkle_key" --verify "$dmg" "$edsig" >/dev/null 2>&1 || die "the DMG's Sparkle signature doesn't verify"
echo "appcast for $version (build $build), DMG signed for Sparkle"

if [ -z "$publish" ]; then
  step "Done (not published)"
  echo "$dmg"
  exit 0
fi

step "Publish $tag on GitHub"
git tag -a "$tag" -m "Duo $version" "$commit"
git push --quiet origin "refs/tags/$tag"
args=(--verify-tag --title "Duo $version")
if [ -n "$notes" ]; then args+=(--notes-file "$notes"); else args+=(--generate-notes); fi
[ -z "$draft" ] || args+=(--draft)
[[ "$version" != *-* ]] || args+=(--prerelease)
url="$(gh release create "$tag" "$dmg" "$out/Duo-$version.dmg.sha256" "$out/appcast.xml" "${args[@]}")"
echo "$url"
