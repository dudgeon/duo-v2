#!/bin/bash
# The isolation guard, live (F-529, F-583, F-587, F-588): a real isolated Duo (build/Duo.app, in the background, its own
# short support folder, no CLAUDE_CONFIG_DIR) and its real duo2. Proves duo2 reaches only that instance and refuses
# every mistake (exit 64), including an endpoint deleted mid-run; that the instance confines Claude's config to its
# own folder and its children inherit DUO_ISOLATED=1; and that nothing in the account's ~/.claude/projects or the
# real Duo's endpoint changed. Never reaches the user's Duo: every duo2 call here is in a test context.
#   NO_BUILD=1 scripts/check-isolation-live.sh     (after scripts/bundle.sh)
set -u
export DUO_ISOLATED=1   # every duo2 here reaches only the test instance; refuses, never the user's Duo (F-529)
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
[ -n "${NO_BUILD:-}" ] || scripts/bundle.sh >/dev/null || { echo "bundle failed"; exit 2; }
app="$root/build/Duo.app"; duo2="$app/Contents/Helpers/duo2"
[ -x "$app/Contents/MacOS/Duo" ] && [ -x "$duo2" ] || { echo "run scripts/bundle.sh first"; exit 2; }

sup=$(cd "$(mktemp -d /tmp/duo-isl.XXXXXX)" && pwd -P)
real_projects="$HOME/.claude/projects"
real_endpoint="$HOME/Library/Application Support/Duo/endpoint.json"
before_projects=$(ls -1 "$real_projects" 2>/dev/null | shasum | cut -c1-12)
before_endpoint=$(shasum "$real_endpoint" 2>/dev/null | cut -c1-12)
fails=0 total=0
ok()   { total=$((total+1)); echo "ok   $1"; }
bad()  { total=$((total+1)); fails=$((fails+1)); echo "FAIL $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       | /' | tail -6; }
# d2 <env assignments…> -- <duo2 args…>: duo2 with only these Duo variables; prints "<code>|<output>"
d2() {
  local envs=()
  while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
  local out code
  out=$(env -u DUO_SOCKET -u DUO_TOKEN -u DUO_SUPPORT_DIR -u DUO_ISOLATED -u DUO_SESSION_ID -u CLAUDE_CODE_SESSION_ID \
        -u CLAUDE_CONFIG_DIR -u DUO_SEARCH_ROOT -u DUO_ARCHIVE_ROOT ${envs[@]+"${envs[@]}"} "$duo2" "$@" 2>&1); code=$?
  printf '%s|%s' "$code" "$out"
}

# The instance: the binary itself, in the background (a scripted launch is an accessory, never activates; F-227).
env -u DUO_SOCKET -u DUO_TOKEN -u DUO_SESSION_ID -u CLAUDE_CONFIG_DIR DUO_SUPPORT_DIR="$sup" DUO_AUTOCONFIRM=1 \
  "$app/Contents/MacOS/Duo" --state overview >"$sup/duo.log" 2>&1 &
pid=$!
trap 'kill -TERM $pid 2>/dev/null; sleep 1; chmod -R u+w "$sup" 2>/dev/null; rm -rf "$sup"' EXIT
for i in {1..60}; do [ -S "$sup/Duo/duo.sock" ] && [ -f "$sup/Duo/endpoint.json" ] && break; sleep 0.5; done
[ -f "$sup/Duo/endpoint.json" ] || { echo "FAIL the isolated Duo never wrote its endpoint"; cat "$sup/duo.log" | tail -5; exit 1; }
sock=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['socket'])" "$sup/Duo/endpoint.json")
token=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['token'])" "$sup/Duo/endpoint.json")

# 1. The named instance answers, three ways.
r=$(d2 DUO_ISOLATED=1 DUO_SUPPORT_DIR="$sup" -- ping); [[ ${r%%|*} == 0 && ${r#*|} == Duo* ]] && ok "DUO_ISOLATED=1 + DUO_SUPPORT_DIR: the instance answers" || bad "support folder" "$r"
r=$(d2 DUO_ISOLATED=1 DUO_SOCKET="$sock" DUO_TOKEN="$token" -- ping); [[ ${r%%|*} == 0 ]] && ok "DUO_ISOLATED=1 + its socket and token: the instance answers" || bad "socket and token" "$r"
r=$(d2 DUO_SUPPORT_DIR="$sup" -- ping); [[ ${r%%|*} == 0 ]] && ok "DUO_SUPPORT_DIR alone (a test context): the instance answers" || bad "support alone" "$r"

# 2. Every mistake refuses with exit 64.
for case in "DUO_ISOLATED=1" "DUO_SOCKET= DUO_TOKEN=" "DUO_ISOLATED=1 DUO_SOCKET=$sock" "DUO_ISOLATED=1 DUO_SOCKET=$sock DUO_TOKEN=wrong" \
            "DUO_SUPPORT_DIR=$sup DUO_SOCKET=/tmp/elsewhere/Duo/duo.sock DUO_TOKEN=$token" "DUO_ISOLATED=1 DUO_SUPPORT_DIR=$HOME/Library/Application Support"; do
  read -r -a vars <<<"$case"
  [[ $case == *"Application Support" ]] && vars=(DUO_ISOLATED=1 "DUO_SUPPORT_DIR=$HOME/Library/Application Support")
  r=$(d2 "${vars[@]}" -- status); [[ ${r%%|*} == 64 && ${r#*|} == *refused* ]] && ok "refused: ${case//$sup/<sup>}" || bad "not refused: $case" "$r"
done
r=$(d2 DUO_ISOLATED=1 -- director status); [[ ${r%%|*} == 64 ]] && ok "an offline verb (director status) with no instance named: refused, not run on ~/.claude" || bad "director status offline" "$r"
r=$(d2 DUO_ISOLATED=1 -- search-status); [[ ${r%%|*} == 64 ]] && ok "search-status with no instance named: refused before reading any index" || bad "search-status" "$r"

# 3. The instance reads only its own folders (F-583).
grep -q "isolated: no CLAUDE_CONFIG_DIR given" "$sup/duo.log" && ok "the instance says Claude's config is its stand-in" || bad "no confinement line in its log" "$(tail -5 "$sup/duo.log")"
# (ps shows only the environment at exec; the instance sets its own at launch, so read its line and folder.)
grep -qF "Claude's config is $sup/Duo/claude-config" "$sup/duo.log" && [ -d "$sup/Duo/claude-config" ] && ok "Claude's config (inherited by its terminals, Claude and duo2) is $sup's stand-in folder" || bad "stand-in config folder" "$(grep isolated "$sup/duo.log")"
r=$(d2 DUO_ISOLATED=1 DUO_SUPPORT_DIR="$sup" -- doctor)
[[ ${r#*|} != *"Library/Application Support/Duo"* ]] && ok "doctor names none of the real support folder's archive or files" || bad "doctor reaches the real folder" "$(printf '%s' "${r#*|}" | grep 'Application Support')"
r=$(d2 DUO_ISOLATED=1 DUO_SOCKET="$sock" DUO_TOKEN="$token" -- search-status)
[[ ${r#*|} != *"Library/Application Support"* ]] && ok "search-status reads the instance's index (via its socket's folder), not the real one" || bad "search-status" "$r"

# 4. Deleted mid-run: the endpoint goes, duo2 refuses rather than finding another Duo.
mv "$sup/Duo/endpoint.json" "$sup/Duo/endpoint.json.away"
r=$(d2 DUO_ISOLATED=1 DUO_SUPPORT_DIR="$sup" -- ping); [[ ${r%%|*} == 64 ]] && ok "endpoint.json deleted mid-run (support folder): refused" || bad "deleted endpoint, support" "$r"
r=$(d2 DUO_ISOLATED=1 DUO_SOCKET="$sock" DUO_TOKEN="$token" -- ping); [[ ${r%%|*} == 64 ]] && ok "endpoint.json deleted mid-run (socket and token): refused" || bad "deleted endpoint, socket" "$r"
mv "$sup/Duo/endpoint.json.away" "$sup/Duo/endpoint.json"
kill -TERM $pid; for i in {1..20}; do kill -0 $pid 2>/dev/null || break; sleep 0.5; done
r=$(d2 DUO_ISOLATED=1 DUO_SOCKET="$sock" DUO_TOKEN="$token" -- ping); [[ ${r%%|*} == 64 ]] && ok "the instance quit: refused, no fallback" || bad "after quit" "$r"

# 5. The account's own data is untouched.
[[ $(ls -1 "$real_projects" 2>/dev/null | shasum | cut -c1-12) == "$before_projects" ]] && ok "~/.claude/projects: no bucket added or removed" || bad "~/.claude/projects changed during the run"
[[ $(shasum "$real_endpoint" 2>/dev/null | cut -c1-12) == "$before_endpoint" ]] && ok "the real Duo's endpoint.json: unchanged" || bad "the real endpoint changed during the run (another Duo restarted?)"
echo "$((total-fails))/$total passed"
[ $fails -eq 0 ]
