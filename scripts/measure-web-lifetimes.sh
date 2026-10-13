#!/bin/zsh
# WebKit processes and leaks around closing web content (codebase review task 3, C-83), on an
# ISOLATED Duo (its own short support folder and config, a scratch workspace; no Claude turn runs).
# Counts the WebContent processes the app is responsible for at launch, with three browser tabs,
# an HTML page and a deck open, and after closing them; then runs leaks(1) on the app.
# It times nothing, but run it under the exclusive lock so other sessions' WebKit work doesn't
# crowd the machine:  scripts/measure-web-lifetimes.sh <repo-or-worktree> <label>
#   GPU_LOCK=… <main>/scripts/gpu-lock.sh <name> scripts/measure-web-lifetimes.sh <tree> before
set -u
tree=${1:A}; label=${2:-run}
app=$tree/build/Duo.app
duo2=$app/Contents/Helpers/duo2
[[ -x $app/Contents/MacOS/Duo ]] || { echo "no $app: run scripts/bundle.sh in that tree first"; exit 2; }
root=/tmp/wlm-$label; rm -rf $root; mkdir -p $root/sup $root/cc $root/ws/Home $root/ws/work/garden
printf -- '---\ngoal: "Home"\n---\n\n# Home\n' > $root/ws/Home/HOME.md
g=$root/ws/work/garden
printf -- '---\ngoal: "Plan"\n---\n\n# garden\n' > $g/PROJECT.md
for i in 1 2 3; do printf '<!doctype html><title>page %s</title><h1>page %s</h1>\n' $i $i > $g/page$i.html; done
printf '<!doctype html><title>viewer</title><h1>local html</h1>\n' > $g/viewer.html
cp "${tree}/Spikes/PptxViewer/decks/garden.pptx" $g/deck.pptx

# Through LaunchServices, so the app is its own responsible process and its WebKit processes count as its
# own (a binary run from a shell is attributed to the shell's launcher).
open -g -n --env DUO_SUPPORT_DIR=$root/sup --env CLAUDE_CONFIG_DIR=$root/cc --env ANTHROPIC_MODEL=claude-haiku-5-5 \
  --stdout $root/duo.log --stderr $root/duo.log "$app" --args --workspace $root/ws
for i in {1..30}; do pid=$(pgrep -f -- "--workspace $root/ws" | head -1); [[ -n $pid ]] && break; sleep 1; done
[[ -n ${pid:-} ]] || { echo "the isolated Duo never started"; exit 1; }
ep=$root/sup/Duo/endpoint.json
for i in {1..60}; do [[ -f $ep ]] && break; sleep 1; done
[[ -f $ep ]] || { echo "the isolated Duo never wrote $ep"; kill -TERM $pid 2>/dev/null; exit 1; }
export DUO_SOCKET=$(python3 -I -c "import json,sys;print(json.load(open(sys.argv[1]))['socket'])" $ep)
export DUO_TOKEN=$(python3 -I -c "import json,sys;print(json.load(open(sys.argv[1]))['token'])" $ep)
d() { "$duo2" "$@" 2>&1; }

# WebContent processes whose responsible process is this app.
count() {
  python3 -I - $pid <<'PY'
import ctypes, subprocess, sys
app = int(sys.argv[1])
lib = ctypes.CDLL('/usr/lib/libSystem.B.dylib')
lib.responsibility_get_pid_responsible_for_pid.argtypes = [ctypes.c_int]
lib.responsibility_get_pid_responsible_for_pid.restype = ctypes.c_int
n = 0
for line in subprocess.run(['ps', '-axo', 'pid=,comm='], capture_output=True, text=True).stdout.splitlines():
    pid, _, comm = line.strip().partition(' ')
    if 'com.apple.WebKit.WebContent' in comm and lib.responsibility_get_pid_responsible_for_pid(int(pid)) == app:
        n += 1
print(n)
PY
}
say() { printf '%-22s WebContent=%s  rss=%s MB\n' "$1" "$(count)" "$(( $(ps -o rss= -p $pid) / 1024 ))"; }

sleep 8; say "launch"
d open garden >/dev/null; sleep 3; say "project open"
tabs=()
for i in 1 2 3; do
  out=$(d browser open file://$g/page$i.html); sleep 2
done
ids=($(d browser tabs | awk '{print $1}' | grep '^web:'))
d doc open $g/viewer.html >/dev/null; sleep 2
d doc open $g/deck.pptx >/dev/null; sleep 4
say "3 tabs + html + deck"
for id in $ids; do d browser close --tab $id >/dev/null; done
d doc close $g/viewer.html >/dev/null; d doc close $g/deck.pptx >/dev/null
sleep 10; say "closed"
echo "browser tabs left: $(d browser tabs | grep -c '^web:')"
leaks $pid 2>&1 | grep -E "^Process|leaks for|Physical footprint|total leaked" | sed 's/^/leaks: /'
kill -TERM $pid 2>/dev/null; for i in {1..10}; do kill -0 $pid 2>/dev/null || break; sleep 1; done
