#!/bin/zsh
# Opens Duo on the acceptance workspace (rebuilding the app first if the sources changed).
set -e
cd "${0:A:h:h:h}"
[[ -d "$HOME/DuoAcceptance/workspace" ]] || python3 scripts/acceptance/fixtures.py
if [[ ! -x build/Duo.app/Contents/MacOS/Duo || -n "$(find Sources -newer build/Duo.app/Contents/MacOS/Duo -name '*.swift' | head -1)" ]]; then
  scripts/bundle.sh >/dev/null
fi
pgrep -xq Duo && osascript -e 'tell application id "com.dudgeon.duo" to quit' && sleep 2
open -n build/Duo.app --args --workspace "$HOME/DuoAcceptance/workspace"
sleep 3
osascript -e 'tell application id "com.dudgeon.duo" to activate'
echo "Duo is open on ~/DuoAcceptance/workspace"
