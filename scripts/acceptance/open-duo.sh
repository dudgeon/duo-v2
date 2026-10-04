#!/bin/zsh
# Opens Duo on the acceptance workspace (rebuilding the app first if the sources changed).
set -e
cd "${0:A:h:h:h}"
if [[ -d "$HOME/DuoAcceptance/workspace" ]]; then python3 scripts/acceptance/fixtures.py --add; else python3 scripts/acceptance/fixtures.py; fi
if [[ ! -x build/Duo.app/Contents/MacOS/Duo || -n "$(find Sources -newer build/Duo.app/Contents/MacOS/Duo -name '*.swift' | head -1)" ]]; then
  scripts/bundle.sh >/dev/null
fi
if pgrep -xq Duo; then
  osascript -e 'tell application id "com.dudgeon.duo" to quit' >/dev/null 2>&1; sleep 2
  # A dialog open in Duo cancels the quit; never start a second copy (they'd share one socket, C-18).
  if pgrep -xq Duo; then echo "Duo is still open (a dialog in it may be waiting). Answer it or quit Duo, then run this again."; exit 1; fi
fi
open -n build/Duo.app --args --workspace "$HOME/DuoAcceptance/workspace"
sleep 3
osascript -e 'tell application id "com.dudgeon.duo" to activate'
echo "Duo is open on ~/DuoAcceptance/workspace"
