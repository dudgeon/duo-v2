#!/bin/bash
# Test launches stay in the background (F-227): while a set of checks runs, the app that was
# frontmost stays frontmost, and no Duo this checkout built ever becomes the front app, shows in the
# Dock (an accessory: lsappinfo type UIElement) or reports itself active at a capture.
#
#   scripts/check-background.sh                    the check set: check-ui, check-chat, check-composer-focus
#   scripts/check-background.sh -- <cmd> [args…]   any other command (e.g. -- scripts/run-live.sh …)
#   TEXTEDIT=1 scripts/check-background.sh         first open a scratch TextEdit document as the front app
#                                                  (this takes focus once, before the run: Geoff's OK first)
#
# Reuses build/Duo.app (run scripts/bundle.sh first). Never touches Geoff's Duo: the checks it runs
# are isolated, and it only reads which app is in front (lsappinfo, no permission needed).
# Exit status: 0 when Duo never came forward, 1 otherwise.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
[ -x build/Duo.app/Contents/MacOS/Duo ] || { echo "run scripts/bundle.sh first"; exit 2; }
bin="$root/build/Duo.app/Contents/MacOS/Duo"
out="$(mktemp -d /tmp/duo-bg.XXXXXX)"
touch "$out/start"
# Only judge what this run starts (F-227): the Duos already running (Geoff's own, from this same build
# path) are written down now and never judged; so are logs from earlier runs (counted from their appended part).
baseline="$out/baseline-pids"; logs_before="$out/logs-before"
pgrep -f "^$bin" > "$baseline" 2>/dev/null || true
mkdir -p "$logs_before"; cp -p build/ui/*.log "$logs_before"/ 2>/dev/null || true
mode=set; [ "${1:-}" = "--" ] && mode=cmd

# <check-functions> (the pure helpers; tested in isolation by extracting this block)
proc_args() { ps -o command= -p "$1" 2>/dev/null; }   # a process's arguments (empty when unreadable or gone)

# is_test_duo <pid> <baseline-file>: succeeds only for a Duo this run started. Not one that was already
# running at the start, not one whose arguments can't be read, and not Geoff's workspace Duo (--workspace on
# ~/DuoAcceptance/workspace with no --state / --capture): when in doubt it is not judged.
is_test_duo() {
  local p="$1" base="$2" args
  grep -qx "$p" "$base" 2>/dev/null && return 1
  args=$(proc_args "$p") || return 1
  [ -n "$args" ] || return 1
  case "$args" in
    *"--workspace $HOME/DuoAcceptance/workspace"*)
      case "$args" in *--state*|*--capture*) ;; *) return 1 ;; esac ;;
  esac
  return 0
}

# new_trace_lines <log-dir> <snapshot-dir>: the 'trace capture' lines written since the snapshot. A log
# whose snapshot is a byte-for-byte prefix of it is read from the appended part only; a log that is new, or
# was recreated (the snapshot is not its prefix), is read whole.
new_trace_lines() {
  local f old osz nsz
  for f in "$1"/*.log; do
    [ -f "$f" ] || continue
    old="$2/$(basename "$f")"; nsz=$(wc -c < "$f" | tr -d ' ')
    if [ -f "$old" ]; then
      osz=$(wc -c < "$old" | tr -d ' ')
      if [ "$osz" -le "$nsz" ] && head -c "$osz" "$f" | cmp -s - "$old"; then
        tail -c +$((osz + 1)) "$f"; continue
      fi
    fi
    cat "$f"
  done | grep 'trace capture' || true
}
# </check-functions>

front() {   # pid bundle-id of the front app
  local asn info
  asn=$(lsappinfo front)
  info=$(lsappinfo info -only pid -only bundleid "$asn")
  printf '%s %s\n' "$(sed -n 's/.*pid = \([0-9]*\).*/\1/p' <<<"$info" | head -1)" "$(sed -n 's/.*bundleID="\([^"]*\)".*/\1/p' <<<"$info" | head -1)"
}

if [ -n "${TEXTEDIT:-}" ]; then
  doc="$out/front.txt"; echo "check-background: this window stays in front" > "$doc"
  open -a TextEdit "$doc"; sleep 2
fi
before=$(front)
echo "front before: $before"

# Sample every 0.2 s: the front app, and how LaunchServices sees each Duo this checkout built.
(
  while :; do
    f=$(front)
    duos=""
    for p in $(pgrep -f "^$bin" 2>/dev/null); do
      is_test_duo "$p" "$baseline" || continue
      t=$(lsappinfo info -only applicationtype "$(lsappinfo find pid=$p)" 2>/dev/null | sed -n 's/.*type="\([^"]*\)".*/\1/p' | head -1)
      duos+=" $p:${t:-?}"
    done
    echo "$(date +%T) front=$f duos=[${duos# }]"
    sleep 0.2
  done
) > "$out/samples.txt" &
sampler=$!

if [ $mode = cmd ]; then
  shift; "$@"
else
  NO_BUILD=1 scripts/check-ui.sh
  NO_BUILD=1 scripts/check-chat.sh
  scripts/check-composer-focus.sh
fi
status=$?
sleep 1
kill "$sampler" 2>/dev/null; wait "$sampler" 2>/dev/null
after=$(front)
echo "front after: $after (the checks exited $status)"

fails=0
n=$(wc -l < "$out/samples.txt" | tr -d ' ')
launched=$(grep -o 'duos=\[[^]]*\]' "$out/samples.txt" | grep -o '[0-9]*:' | sort -u | wc -l | tr -d ' ')
duo_front=$(awk '{ split($2, f, "="); fp = f[2]; if (index($0, " " fp ":") || index($0, "[" fp ":") || $3 ~ /com\.dudgeon\.duo\.test/) print }' "$out/samples.txt")
types=$(grep -o 'duos=\[[^]]*\]' "$out/samples.txt" | grep -o '[0-9]*:[A-Za-z?]*' | grep -v ':?$' | sort -u)
# A Dock app that became an accessory once its code ran: only the main checkout's build (com.dudgeon.duo,
# no LSUIElement) does that, for the moment before Duo starts (F-228). One that stayed a Dock app fails.
in_dock="" flashed=""
for p in $(grep -v ':UIElement$' <<<"$types" | cut -d: -f1 | sort -u); do
  if grep -qx "$p:UIElement" <<<"$types"; then flashed+=" $p"; else in_dock+=" $p"; fi
done
active=$(new_trace_lines build/ui "$logs_before" | grep -c 'active=true' || true)
if [ -n "$duo_front" ]; then echo "✘ a test Duo became the front app:"; echo "$duo_front" | head -5; fails=1
else echo "✔ no test Duo became the front app ($n samples, $launched Duo launches seen)"; fi
if [ -n "$in_dock" ]; then echo "✘ a test Duo ran as a Dock app (pids$in_dock)"; fails=1
else echo "✔ every test Duo ran as an accessory (no Dock icon, no menu bar)"; fi
[ -z "$flashed" ] || echo "  note: pids$flashed were Dock apps until Duo's code ran (a main-checkout build, F-228)"
if [ "${before%% *}" != "${after%% *}" ]; then echo "✘ the front app changed: $before → $after"; fails=1
else echo "✔ the front app stayed in front ($after)"; fi
case "$before" in *com.apple.loginwindow*)
  echo "  ⚠ the screen was locked: nothing can come to the front, so the front-app proof holds only for a run with the screen unlocked" ;;
esac
if [ $mode = set ]; then
  if [ "$active" -gt 0 ]; then echo "✘ $active capture(s) found Duo active"; fails=1; else echo "✔ no capture found Duo active"; fi
fi
[ "$launched" -gt 0 ] || { echo "✘ the sampler saw no Duo launch at all"; fails=1; }
echo "samples: $out/samples.txt"
exit "$fails"
