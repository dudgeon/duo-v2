#!/bin/bash
# The release launch matrix (F-580, after the 0.2.23 launch hang, docs/plan/incidents/2026-11-03-launch-hang-0-2-23.md).
# Launches an app the way Finder does, through LaunchServices (`open -g -n`, launchd's environment, stdin /dev/null),
# in the conditions a user's Mac can have and this one doesn't, and requires each launch to finish (the app's
# "Duo: finished launching" line, written at didFinishLaunching by an isolated instance) within LIMIT seconds:
#   plain          as it is
#   no-claude      claude in none of the usual places, so the login shell is asked
#   shell-hangs    that, with a .zprofile that waits 40 s (a prompt, a keychain, a slow version manager)
#   shell-child    that, with a .zprofile that leaves a child holding the shell's output
#   shell-read     that, with a .zprofile that reads from the terminal
#   no-path        that, with PATH pointing nowhere
#   stale-endpoint a dead instance's endpoint.json and socket left in the support folder
#   second         a second instance on the same support folder while the first runs (a leftover Duo)
# Every launch is isolated: its own short DUO_SUPPORT_DIR and a scratch CLAUDE_CONFIG_DIR, in the background (an
# accessory, never frontmost, F-227), so Geoff's Duo and data are never touched. Each instance is quit with SIGTERM.
#   scripts/check-launch-matrix.sh <Duo.app> [case…]
# Exits 1 if any case fails. scripts/release.sh runs it on the signed app before notarizing.
set -u
export DUO_ISOLATED=1   # every duo2 here reaches only the test instance; refuses, never the user's Duo (F-529)
app=${1:?usage: check-launch-matrix.sh <Duo.app> [case…]}; shift
cases=${*:-plain no-claude shell-hangs shell-child shell-read no-path stale-endpoint second}
LIMIT=${LIMIT:-20}
work=$(mktemp -d /tmp/dlm-XXXX)
fail=0
trap 'chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"' EXIT   # mods are written read-only

# launch <tag> <support> [env…]: opens the app; prints nothing.
launch() {
  local tag=$1 sup=$2; shift 2
  local envs=(--env DUO_ISOLATED=1 --env "DUO_SUPPORT_DIR=$sup" --env "CLAUDE_CONFIG_DIR=$work/config")
  for e in "$@"; do envs+=(--env "$e"); done
  mkdir -p "$sup" "$work/config"
  open -g -n "${envs[@]}" --stdout /dev/null --stderr "$work/$tag.log" "$app" --args -DuoLaunchProbe "$tag-$$"
}
pid_of() { pgrep -f "DuoLaunchProbe $1-$$" | head -1; }
# finished <tag>: waits up to LIMIT s for the line; prints the seconds or nothing.
finished() {
  local i
  for ((i = 0; i < LIMIT * 4; i++)); do
    if grep -q "Duo: finished launching" "$work/$1.log" 2>/dev/null; then
      sed -n 's/.*finished launching in \([0-9.]*\) s.*/\1/p' "$work/$1.log" | head -1; return 0
    fi
    sleep 0.25
  done
  return 1
}
# quit <tag>: SIGTERM, then waits for it to end (a launch still stuck ends when its shell does).
quit() {
  local p i; p=$(pid_of "$1"); [ -n "$p" ] || return 0
  kill -TERM "$p" 2>/dev/null
  for ((i = 0; i < 240; i++)); do kill -0 "$p" 2>/dev/null || return 0; sleep 0.25; done
  echo "  warning: $1 (pid $p) still running 60 s after SIGTERM" >&2
}
result() {  # result <case> <seconds or empty> [detail]
  if [ -n "$2" ]; then echo "launch matrix $1: ok (${2} s)"
  else
    echo "launch matrix $1: FAIL, no finished launch in $LIMIT s${3:+ ($3)}"; fail=1
    local p; p=$(pid_of "$1"); [ -n "$p" ] && sample "$p" 1 2>/dev/null | grep -A14 "com.apple.main-thread" | sed 's/^/    /' | head -16
    tail -5 "$work/$1.log" 2>/dev/null | sed 's/^/    /'
  fi
}
zdot() {  # zdot <name> <.zprofile body>: a ZDOTDIR holding that .zprofile
  mkdir -p "$work/z-$1"; printf '%s\n' "$2" > "$work/z-$1/.zprofile"; echo "$work/z-$1"
}

for c in $cases; do
  sup="$work/s-$c"
  case $c in
    plain) launch "$c" "$sup" ;;
    no-claude) launch "$c" "$sup" "DUO_CLAUDE_CANDIDATES=" "ZDOTDIR=$(zdot "$c" ':')" ;;
    shell-hangs) launch "$c" "$sup" "DUO_CLAUDE_CANDIDATES=" "ZDOTDIR=$(zdot "$c" 'sleep 40')" ;;
    shell-child) launch "$c" "$sup" "DUO_CLAUDE_CANDIDATES=" "ZDOTDIR=$(zdot "$c" '(sleep 40 &)')" ;;
    shell-read) launch "$c" "$sup" "DUO_CLAUDE_CANDIDATES=" "ZDOTDIR=$(zdot "$c" 'read -r answer')" ;;
    no-path) launch "$c" "$sup" "DUO_CLAUDE_CANDIDATES=" "PATH=/nonexistent" "ZDOTDIR=$(zdot "$c" ':')" ;;
    stale-endpoint)
      mkdir -p "$sup/Duo"
      printf '{"socket":"%s","token":"stale","pid":99999}\n' "$sup/Duo/duo.sock" > "$sup/Duo/endpoint.json"
      : > "$sup/Duo/duo.sock"
      launch "$c" "$sup" ;;
    second)
      launch "$c-first" "$sup"; s1=$(finished "$c-first")
      [ -n "$s1" ] || { result "$c" "" "the first instance didn't finish"; quit "$c-first"; continue; }
      launch "$c" "$sup" ;;
    *) echo "unknown case $c"; fail=1; continue ;;
  esac
  s=$(finished "$c"); result "$c" "$s"
  # Not vacuous: with claude hidden and a shell that waits, the login shell really was asked (and given up on).
  if [ "$c" = shell-hangs ] && [ -n "$s" ] && [ -z "${NO_SHELL_PROOF:-}" ]; then
    for ((i = 0; i < 40; i++)); do grep -q "login shell" "$work/$c.log" && break; sleep 0.25; done
    grep -q "login shell" "$work/$c.log" || { echo "launch matrix $c: FAIL, the login shell was never asked (the case proves nothing)"; fail=1; }
  fi
  quit "$c"; [ "$c" = second ] && quit "$c-first"
done
exit $fail
