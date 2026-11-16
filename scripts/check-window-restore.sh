#!/bin/bash
# The window set survives a quit and relaunch (DL-351, C-153): an isolated Duo in the background on a scratch Home
# of three sample projects opens three windows (a project in two, All projects in one, each a colour), quits by
# SIGTERM (as ⌘Q), and relaunches on the same support folder; `duo2 window list --json` must read the same set
# with the same frames. Then one window's saved frame is moved off every screen, and the next relaunch must put it
# back on one. Nothing is shown (F-227), no Claude session starts, and Geoff's Duo is never reached (F-529).
#
#   scripts/check-window-restore.sh            build, then run
#   NO_BUILD=1 scripts/check-window-restore.sh reuse build/Duo.app
set -euo pipefail
export DUO_ISOLATED=1
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
[ -n "${NO_BUILD:-}" ] || scripts/bundle.sh >/dev/null
app="$root/build/Duo.app"
duo2="$app/Contents/Helpers/duo2"
work=$(mktemp -d /tmp/dwr-XXXX)
sup="$work/s" home="$work/home" out="${UI_OUT:-$root/build/window-restore}"
mkdir -p "$sup" "$work/config" "$out"
# Mods are written read-only; a run that fails part way leaves no Duo behind.
trap 'if [ -n "$pid" ]; then kill -TERM "$pid" 2>/dev/null || true; fi; chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"' EXIT
mkdir -p "$home"; printf -- '---\ntitle: Home\n---\n' > "$home/_HOME.md"
for p in alpha beta gamma; do mkdir -p "$home/$p"; printf -- '---\ntitle: %s\n---\n\n# %s\n' "$p" "$p" > "$home/$p/_PROJECT.md"; done
fail=0
pid=""
data="$sup/Duo"   # the instance's own folder: endpoint.json and restore-<key>.json

launch() {   # <tag>
  : > "$work/$1.log"
  open -g -n --env DUO_ISOLATED=1 --env "DUO_SUPPORT_DIR=$sup" --env "CLAUDE_CONFIG_DIR=$work/config" --env DUO_RESTORE=1 \
    --env DUO_HANG_LOG=0 --stdout /dev/null --stderr "$work/$1.log" "$app" --args --workspace "$home" -DuoWindowRestore "$1-$$"
  local i
  for ((i = 0; i < 120; i++)); do
    pid=$(pgrep -f "DuoWindowRestore $1-$$" | head -1 || true)
    [ -n "$pid" ] && grep -q "^live: " "$work/$1.log" 2>/dev/null && break   # the first refresh, which restores
    sleep 0.25
  done
  grep -q "^live: " "$work/$1.log" || { echo "$1: no refresh in 30 s"; tail -5 "$work/$1.log"; exit 1; }
  sleep 1
  export DUO_SOCKET DUO_TOKEN
  DUO_SOCKET=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["socket"])' "$data/endpoint.json")
  DUO_TOKEN=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["token"])' "$data/endpoint.json")
}
quit() {
  kill -TERM "$pid"
  local i; for ((i = 0; i < 120; i++)); do kill -0 "$pid" 2>/dev/null || return 0; sleep 0.25; done
  echo "Duo $pid still running 30 s after SIGTERM"; exit 1
}
summary() {   # number project colour frame per window, from window list --json
  python3 -c '
import json,sys
d=json.load(sys.stdin); ws=d if isinstance(d,list) else d.get("data", d.get("result", d))
for w in ws: print(w["number"], w.get("project","-"), w["colour"], ",".join(str(int(x)) for x in w.get("frame",[])))'
}

launch one
"$duo2" open alpha >/dev/null
"$duo2" window colour ochre >/dev/null
"$duo2" window new beta >/dev/null
"$duo2" window new >/dev/null
"$duo2" window colour deep-teal --window 3 >/dev/null
"$duo2" window list --json | summary > "$out/before.txt"
"$duo2" window list > "$out/before-list.txt"
quit
cp "$data"/restore-*.json "$out/restore-file.json" 2>/dev/null || true

launch two
"$duo2" window list --json | summary > "$out/after.txt"
"$duo2" window list > "$out/after-list.txt"
echo "before quit:"; sed 's/^/  /' "$out/before.txt"
echo "after relaunch:"; sed 's/^/  /' "$out/after.txt"
if [ "$(wc -l < "$out/before.txt")" -ge 3 ] && diff -q "$out/before.txt" "$out/after.txt" >/dev/null; then echo "window set restored: ok"
else echo "window set restored: FAIL"; fail=1; fi
grep "^restore:" "$work/two.log" | sed 's/^/  /'
quit

# A frame off every screen: move window 3's saved frame far right, relaunch, and it must be on a screen.
python3 - "$data" <<'EOF'
import json,glob,sys
f=[p for p in glob.glob(sys.argv[1]+"/restore-*.json") if not p.endswith(".v1.json")][0]
s=json.load(open(f)); w=s["windows"][2]; w["frame"][0]=20000; w["frame"][1]=20000; json.dump(s,open(f,"w"))
EOF
launch three
"$duo2" window list --json | summary > "$out/offscreen.txt"
frame3=$(awk '$1==3 {print $4}' "$out/offscreen.txt")
echo "window 3 saved at 20000,20000 opens at $frame3"
if [ -n "$frame3" ] && [ "${frame3%%,*}" -lt 10000 ]; then echo "off-screen frame moved on: ok"; else echo "off-screen frame moved on: FAIL"; fail=1; fi
quit
echo "check-window-restore: $([ $fail = 0 ] && echo pass || echo FAIL)"
exit $fail
