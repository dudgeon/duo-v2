#!/bin/zsh
# Runs duo2 under macOS Seatbelt (sandbox-exec) the way Claude Code's Bash sandbox does, without
# spending tokens (F-29). Starts an ISOLATED Duo in fixture mode (its own short DUO_SUPPORT_DIR and
# a scratch CLAUDE_CONFIG_DIR, so it never collides with the user's Duo and needs no "quit Duo
# first"), then checks:
#   1. network denied (Claude's default)        → duo2 must fail with "Operation not permitted"
#   2. Claude's allowUnixSockets rule for Duo's socket → duo2 must reach Duo
#   3. writes outside the working folder stay blocked in both
#   4. the pre-edit hook inside the sandbox (F-108, C-80): fails open on a denied socket, a stale
#      token or a file Duo doesn't have open; a stale environment endpoint falls back to endpoint.json
# The network rule is copied from Claude Code's profile template:
#   (allow network-outbound (remote unix-socket (subpath "<socket>")))
set -u
root=${0:A:h:h}
cd "$root"
duo2="$root/build/Duo.app/Contents/Helpers/duo2"
[[ -x $duo2 ]] || { echo "run scripts/bundle.sh first"; exit 2; }
# The socket path must stay under 104 characters, so the support folder is short.
support=$(cd "$(mktemp -d /tmp/d-sbx.XXXXXX)" && pwd -P)   # real path: Seatbelt matches /private/tmp, not the /tmp link
mkdir -p "$support/cc"
sock="$support/Duo/duo.sock"
work=$(mktemp -d)
export DUO_SUPPORT_DIR=$support CLAUDE_CONFIG_DIR=$support/cc
unset DUO_SOCKET DUO_TOKEN
# Run the binary itself, in the background: a scripted launch is an accessory and never activates (F-227).
"$root/build/Duo.app/Contents/MacOS/Duo" --state overview >"$support/duo.log" 2>&1 &
duo_pid=$!
for i in {1..40}; do [[ -S $sock ]] && break; sleep 0.5; done
[[ -S $sock ]] || { echo "✘ the isolated Duo never opened $sock"; kill -TERM $duo_pid 2>/dev/null; rm -rf "$support" "$work"; exit 1; }
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

# The pre-edit hook (DL-78) inside the sandbox: Claude's tool must run (exit 0, no output) whenever
# Duo can't or won't make the edit (C-80, F-108).
hookin="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$work/not-open.md\",\"content\":\"x\"}}"
hook() {  # $1 = profile rules, $2... = env assignments
  local rules=$1; shift
  (cd "$work" && echo "$hookin" | env "$@" sandbox-exec -p "$(profile "$rules")" "$duo2" hook pre-edit 2>&1)
}
out=$(hook "" X=1); code=$?
[[ $code -eq 0 && -z $out ]] && echo "✔ hook: socket denied by the sandbox, Claude's write runs" || { echo "✘ hook with the socket denied: $code: $out"; fail=1; }
out=$(hook "$allow" X=1); code=$?
[[ $code -eq 0 && -z $out ]] && echo "✔ hook: a file Duo doesn't have open, Claude's write runs" || { echo "✘ hook, file not open: $code: $out"; fail=1; }
out=$(hook "$allow" DUO_SOCKET="$sock" DUO_TOKEN=stale-token); code=$?
[[ $code -eq 0 && -z $out ]] && echo "✔ hook: a stale token falls back to endpoint.json and the write runs" || { echo "✘ hook with a stale token: $code: $out"; fail=1; }
out=$(run "$allow" env DUO_SOCKET="$sock" DUO_TOKEN=stale-token "$duo2" ping); code=$?
[[ $code -eq 0 && $out == Duo* ]] && echo "✔ a stale environment token falls back to endpoint.json" || { echo "✘ stale environment token: $code: $out"; fail=1; }
out=$(run "$allow" env DUO_SOCKET="$support/gone.sock" DUO_TOKEN=stale-token "$duo2" ping); code=$?
[[ $code -eq 0 && $out == Duo* ]] && echo "✔ a dead environment socket falls back to endpoint.json" || { echo "✘ dead environment socket: $code: $out"; fail=1; }

# Quit by SIGTERM (Duo quits as with ⌘Q), never AppleScript: it can raise an Automation prompt (F-54).
kill -TERM "$duo_pid" 2>/dev/null
sleep 1

# Search (SRCH FR-7.7.2-3): read-only, no app, no network, writes nothing, Claude's default sandbox.
# Needs an index in the scratch support folder; set DUO_SANDBOX_INDEX to a copy of one to run it.
if [[ -n ${DUO_SANDBOX_INDEX:-} && -f $DUO_SANDBOX_INDEX ]]; then
  mkdir -p "$support/Duo/search"; cp "$DUO_SANDBOX_INDEX" "$support/Duo/search/index.sqlite"
  marker=$work/.marker; touch $marker; sleep 1
  out=$(run "" "$duo2" search tides and the moon -k 1 --json); code=$?
  if [[ $code -eq 0 && $out == *'"results"'* && $out == *tides* ]]; then echo "✔ duo2 search works in the default sandbox, app closed"; else echo "✘ search in sandbox: $code $out"; fail=1; fi
  changed=$(find "$support" -newer $marker -type f 2>/dev/null | head -3)
  [[ -z $changed ]] && echo "✔ search wrote nothing" || { echo "✘ search wrote: $changed"; fail=1; }
else
  echo "- search: no index in the scratch folder (set DUO_SANDBOX_INDEX to a copy of one); skipped"
fi
rm -rf "$work" "$support"
exit $fail
