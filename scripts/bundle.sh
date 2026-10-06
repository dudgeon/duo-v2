#!/bin/bash
# Builds Duo and wraps it in build/Duo.app (no Xcode needed).
#
#   scripts/bundle.sh            debug build
#   scripts/bundle.sh release    release build
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
config="${1:-debug}"
cd "$root"

swift build -c "$config" --product Duo 2>&1 | grep -vE "ld: warning: search path" || true
swift build -c "$config" --product duo2 2>&1 | grep -vE "ld: warning: search path" || true
bin="$(swift build -c "$config" --show-bin-path)/Duo"
[ -x "$bin" ] || { echo "Build failed: no $bin" >&2; exit 1; }

app="$root/build/Duo.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Duo"
# duo2 lives in its own folder so terminals can put it on PATH without exposing Duo itself.
mkdir -p "$app/Contents/Helpers"
cp "$(dirname "$bin")/duo2" "$app/Contents/Helpers/duo2"
codesign --force --sign - "$app/Contents/Helpers/duo2" >/dev/null 2>&1 || true
# In-app updates (Vendor/Sparkle/README.md): the framework the app links, in Contents/Frameworks.
mkdir -p "$app/Contents/Frameworks"
ditto "$root/Vendor/Sparkle/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
# Its XPC services are removed (Duo isn't sandboxed), so re-seal it ad hoc, inside out.
spk="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
for part in "$spk/Autoupdate" "$spk/Updater.app" "$app/Contents/Frameworks/Sparkle.framework"; do
  codesign --force --sign - "$part" >/dev/null 2>&1 || echo "warning: ad-hoc signing $part failed" >&2
done
cp "$root/docs/design/build-handoff/fixture.json" "$app/Contents/Resources/fixture.json"
cp "$root/docs/design/many-projects-handoff/fixture.json" "$app/Contents/Resources/fixture-many.json"
rm -rf "$app/Contents/Resources/chat-fixtures"
cp -R "$root/docs/design/chat-mode-handoff/fixture-chat" "$app/Contents/Resources/chat-fixtures"   # chat-mode targets (ChatTargets)
# The document editor: vendored CodeMirror bundle and its page (F-34).
mkdir -p "$app/Contents/Resources/editor"
cp "$root/Vendor/codemirror/dist/cm6.js" "$root/Vendor/codemirror/dist/editor.html" "$app/Contents/Resources/editor/"
# The PowerPoint viewer (DL-125): the vendored renderer and Duo's page around it.
mkdir -p "$app/Contents/Resources/deck"
cp "$root/Vendor/pptx-renderer/deck.html" "$root/Vendor/pptx-renderer/deck.js" "$root/Vendor/pptx-renderer/pptx-renderer.js" "$app/Contents/Resources/deck/"
# The search model (DL-40, F-35): committed in parts, reassembled and verified here.
model="$root/Models/bge-small-fp16"
if [ -d "$model" ]; then
  dest="$app/Contents/Resources/search"
  mkdir -p "$dest"
  cp -R "$model/model.mlpackage" "$dest/bge-small-fp16.mlpackage"
  w="$dest/bge-small-fp16.mlpackage/Data/com.apple.CoreML/weights"
  cat "$w"/weight.bin.part* > "$w/weight.bin" && rm "$w"/weight.bin.part*
  want=$(awk '$2=="weight.bin"{print $1}' "$model/SHA256SUMS")
  have=$(shasum -a 256 "$w/weight.bin" | awk '{print $1}')
  [ "$want" = "$have" ] || { echo "search model weights don't match SHA256SUMS" >&2; exit 1; }
  cp "$model/vocab.txt" "$model/PROVENANCE.json" "$dest/"
fi
version="$(git -C "$root" describe --tags --always --dirty 2>/dev/null || echo dev)"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.dudgeon.duo</string>
  <key>CFBundleName</key><string>Duo</string>
  <key>CFBundleDisplayName</key><string>Duo</string>
  <key>CFBundleExecutable</key><string>Duo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.1</string>
  <key>CFBundleVersion</key><string>${version}</string>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>com.dudgeon.duo.walk</string>
    <key>CFBundleURLSchemes</key><array><string>duo2</string></array>
  </dict></array>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>SUFeedURL</key><string>https://github.com/dudgeon/duo-v2/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>0fPkvvQZd60xfPbyCUeLvHbFPGjB1RE1ngsmb1ubMmw=</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
</dict>
</plist>
PLIST
codesign --force --sign - "$app" >/dev/null 2>&1 || echo "warning: ad-hoc signing failed" >&2
# duo2:// links (the acceptance walk's Set up test) open this build.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app" >/dev/null 2>&1 || true
echo "$app"
