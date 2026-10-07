#!/bin/zsh
# Opens Duo on the acceptance workspace (rebuilding the app first if the sources changed).
set -e
cd "${0:A:h:h:h}"
# This quits every running Duo and opens Geoff's own (the real support folder). Only the main
# checkout may run it: a session's work tree that ran it once quit Geoff's Duo and every session in it.
if [[ "$PWD" == */.claude/worktrees/* && -z "${DUO_OPEN_FROM_WORKTREE:-}" ]]; then
  echo "open-duo.sh opens Geoff's own Duo and quits any other; it refuses to run from a work tree."
  echo "For a test instance use scripts/run-live.sh, or launch Duo with your own DUO_SUPPORT_DIR (CLAUDE.md)."
  exit 1
fi
if [[ -d "$HOME/DuoAcceptance/workspace" ]]; then python3 scripts/acceptance/fixtures.py --add; else python3 scripts/acceptance/fixtures.py; fi
if [[ ! -x build/Duo.app/Contents/MacOS/Duo || -n "$(find Sources -newer build/Duo.app/Contents/MacOS/Duo -name '*.swift' | head -1)" ]]; then
  scripts/bundle.sh >/dev/null
fi
if pgrep -xq Duo; then
  # SIGTERM quits like ⌘Q (sessions end, the document saves); AppleScript could raise an
  # Automation consent dialog, which blocks unattended runs (F-54).
  pkill -TERM -x Duo; for i in {1..10}; do pgrep -xq Duo || break; sleep 1; done
  # A dialog open in Duo cancels the quit; never start a second copy (they'd share one socket, C-18).
  if pgrep -xq Duo; then echo "Duo is still open (a dialog in it may be waiting). Answer it or quit Duo, then run this again."; exit 1; fi
fi
# The acceptance Duo is Geoff's working Duo during a walk (duo2 and duo2:// links reach it through the
# real endpoint.json), so it opts into the real support folder; other scripted runs get a temporary one (F-89).
open -n --env "DUO_SUPPORT_DIR=$HOME/Library/Application Support" build/Duo.app --args --workspace "$HOME/DuoAcceptance/workspace"
sleep 3
echo "Duo is open on ~/DuoAcceptance/workspace"
