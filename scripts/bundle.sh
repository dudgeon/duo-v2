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
bin="$(swift build -c "$config" --show-bin-path)/Duo"
[ -x "$bin" ] || { echo "Build failed: no $bin" >&2; exit 1; }

app="$root/build/Duo.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Duo"
cp "$root/docs/design/build-handoff/fixture.json" "$app/Contents/Resources/fixture.json"
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
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST
codesign --force --sign - "$app" >/dev/null 2>&1 || echo "warning: ad-hoc signing failed" >&2
echo "$app"
