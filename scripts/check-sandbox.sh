#!/bin/zsh
# Runs duo2 under macOS Seatbelt (sandbox-exec) the way Claude Code's Bash sandbox does, without
# spending tokens (F-29). Starts Duo in fixture mode, then checks:
#   1. network denied (Claude's default)        → duo2 must fail with "Operation not permitted"
#   2. Claude's allowUnixSockets rule for Duo's socket → duo2 must reach Duo
#   3. writes outside the working folder stay blocked in both
# The network rule is copied from Claude Code's profile template:
#   (allow network-outbound (remote unix-socket (subpath "<socket>")))
set -u
root=${0:A:h:h}
cd "$root"
duo2="$root/build/Duo.app/Contents/Helpers/duo2"
[[ -x $duo2 ]] || { echo "run scripts/bundle.sh first"; exit 2; }
sock="$HOME/Library/Application Support/Duo/duo.sock"
work=$(mktemp -d)
pgrep -xq Duo && { echo "quit Duo first"; exit 2; }
open -n build/Duo.app --args --state overview
for i in {1..20}; do [[ -S $sock ]] && break; sleep 0.5; done
sleep 0.5

profile() {  # $1 = extra rules
  cat <<SB
(version 1)
(allow default)
(deny network*)
(deny file-write* (require-not (subpath "$work")))
(allow file-write* (literal "/dev/null") (literal "/dev/tty"))
$1
SB
}
run() {  # $1 = profile rules, then the command
  local rules=$1; shift
  (cd "$work" && sandbox-exec -p "$(profile "$rules")" "$@" 2>&1)
}

fail=0
out=$(run "" "$duo2" ping); code=$?
if [[ $code -ne 0 && $out == *"Operation not permitted"* ]]; then echo "✔ denied network: duo2 fails (EPERM)"; else echo "✘ denied network: expected EPERM, got $code: $out"; fail=1; fi
allow="(allow network-outbound (remote unix-socket (subpath \"$sock\")))"
out=$(run "$allow" "$duo2" ping); code=$?
if [[ $code -eq 0 && $out == Duo* ]]; then echo "✔ Duo's socket allowed: $out"; else echo "✘ socket allowed: expected success, got $code: $out"; fail=1; fi
out=$(run "$allow" "$duo2" needs-you); [[ $out == *"needs you"* || $out == *" / "* ]] && echo "✔ needs-you answers inside the sandbox" || { echo "✘ needs-you: $out"; fail=1; }
out=$(run "$allow" /usr/bin/touch "$HOME/duo-seatbelt-probe"); [[ -e $HOME/duo-seatbelt-probe ]] && { echo "✘ write outside the folder succeeded"; rm -f "$HOME/duo-seatbelt-probe"; fail=1; } || echo "✔ writes outside the working folder stay blocked"
out=$(run "$allow" /usr/bin/nc -z -w 2 127.0.0.1 22); [[ $? -ne 0 ]] && echo "✔ loopback TCP stays blocked" || { echo "✘ loopback TCP reachable"; fail=1; }

osascript -e 'tell application id "com.dudgeon.duo" to quit' >/dev/null 2>&1
rm -rf "$work"
exit $fail
