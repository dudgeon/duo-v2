#!/bin/bash
# Shared by render-references.sh and compare.sh. Not run on its own.
#
# Takes exact-size screenshots with a headless Chromium-family browser.
# Headless Chrome's page area can be shorter than the window size it is given, which silently
# crops the bottom of a screenshot. So this measures the gap first, asks for a window that much
# larger, crops the result back, and then checks the final pixel size. It fails loudly rather
# than write a wrong picture.
#
# Override the browser with:  CHROME=/path/to/browser

tools_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_chrome() {
  if [ -n "${CHROME:-}" ] && [ -x "$CHROME" ]; then echo "$CHROME"; return 0; fi
  local c
  for c in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "$HOME/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium" \
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
  do
    if [ -x "$c" ]; then echo "$c"; return 0; fi
  done
  for c in "$HOME"/Library/Caches/ms-playwright/chromium-*/chrome-mac*/Chromium.app/Contents/MacOS/Chromium; do
    if [ -x "$c" ]; then echo "$c"; return 0; fi
  done
  for c in google-chrome chromium chromium-browser; do
    if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return 0; fi
  done
  echo "No Chromium-family browser found. Install Google Chrome, or set CHROME=/path/to/browser." >&2
  return 1
}

# chrome_run <args...>: one headless run on a throwaway profile, so it never attaches to a Chrome
# the user already has open.
chrome_run() {
  local profile rc=0
  profile="$(mktemp -d "${TMPDIR:-/tmp}/duo-shoot.XXXXXX")"
  "$CHROME_BIN" --headless=new --user-data-dir="$profile" \
    --no-first-run --no-default-browser-check --hide-scrollbars \
    --allow-file-access-from-files --virtual-time-budget=5000 \
    ${CHROME_FLAGS:-} "$@" 2>/dev/null || rc=$?
  rm -rf "$profile"
  return $rc
}

urlencode_path() { printf %s "$1" | sed -e 's/%/%25/g' -e 's/ /%20/g' -e 's/#/%23/g' -e 's/?/%3F/g' -e 's/&/%26/g'; }

# png_size <file> -> "W H"
png_size() { file "$1" | sed -n 's/.*PNG image data, \([0-9]*\) x \([0-9]*\).*/\1 \2/p'; }

# calibrate: sets GAP_W and GAP_H, the points lost between window size and page area.
calibrate() {
  [ -n "${GAP_H:-}" ] && return 0
  local got
  got="$(chrome_run --window-size=1000,800 --dump-dom "file://$(urlencode_path "$tools_dir/probe.html")" \
        | sed -n 's/.*VIEWPORT:\([0-9]*\)x\([0-9]*\):.*/\1 \2/p' | head -1)" || true
  if [ -z "$got" ]; then echo "Could not measure the browser's page area with $CHROME_BIN" >&2; return 1; fi
  GAP_W=$((1000 - ${got% *})); GAP_H=$((800 - ${got#* }))
  if [ $GAP_W -lt 0 ] || [ $GAP_H -lt 0 ] || [ $GAP_W -gt 400 ] || [ $GAP_H -gt 400 ]; then
    echo "Unexpected page area ($got for a 1000x800 window) from $CHROME_BIN" >&2; return 1
  fi
}

# shoot <url> <width pt> <height pt> <out.png> [scale]
shoot() {
  local url="$1" w="$2" h="$3" out="$4" scale="${5:-2}" dir tmp want got
  calibrate || return 1
  dir="$(mktemp -d "${TMPDIR:-/tmp}/duo-shot.XXXXXX")"
  tmp="$dir/shot.png"
  chrome_run --force-device-scale-factor="$scale" --window-size="$((w + GAP_W)),$((h + GAP_H))" \
    --screenshot="$tmp" "$url" >/dev/null || true
  if [ ! -s "$tmp" ]; then echo "Failed to render $url" >&2; rm -rf "$dir"; return 1; fi
  want="$((w * scale)) $((h * scale))"
  if [ "$(png_size "$tmp")" = "$want" ]; then
    mv "$tmp" "$out"
  else
    # Crop back to the design size: top-left corner, exact pixels.
    chrome_run --window-size=800,600 --dump-dom \
      "file://$(urlencode_path "$tools_dir/crop.html")?w=$((w * scale))&h=$((h * scale))&src=file://$(urlencode_path "$tmp")" \
      | awk '/^-----BEGIN PNG-----$/{f=1;next} /^-----END PNG-----$/{f=0} f' | base64 --decode > "$out" || true
  fi
  rm -rf "$dir"
  got="$(png_size "$out")"
  if [ "$got" != "$want" ]; then
    echo "Wrong size for $out: got '${got:-nothing}', wanted '$want'. Not a usable picture." >&2
    rm -f "$out"; return 1
  fi
}
