#!/bin/zsh
# The scale check (ENH-46, F-208): Duo launched in the shape that froze 0.2.5 on the work Mac, on
# an isolated instance: 42 sessions in 6 projects, 16 tabs restored in chat, Home in chat with
# Home's project on screen, and a stand-in Claude Code 2.1.219 whose sign-in screen flips with its
# prompt (scripts/scale-tui.py). Fails if CPU doesn't settle or the main thread stalls.
#
#   scripts/check-scale.sh                       build, then check build/Duo.app
#   NO_BUILD=1 scripts/check-scale.sh            reuse build/Duo.app
#   APP=<Duo.app> scripts/check-scale.sh         check another build (e.g. a release's, for a before/after)
#   SECONDS_RUN=60 (default)                     how long each launch runs
#
# Isolated: its own support and Claude config folders under /tmp, a stand-in claude, no login, no
# network; never the user's Duo. The window never takes focus; macOS may skip drawing it when it's
# covered, so a covered run understates layout cost (F-208's trap).
set -u
root=${0:A:h:h}
cd $root
[[ ${NO_BUILD:-} == 1 || -n ${APP:-} ]] || scripts/bundle.sh >/dev/null || exit 1
app=${APP:-$root/build/Duo.app}
secs=${SECONDS_RUN:-60}
fx=$(mktemp -d /tmp/d-scale-XXXX); fx=${fx:A}   # realpath: restore matches Home by its real path
stub=$fx/claude
printf '#!/bin/sh\nexec /usr/bin/python3 -I %s "$@"\n' "$root/scripts/scale-tui.py" > $stub; chmod +x $stub
python3 scripts/make-scale-fixture.py $fx --projects 6 --sessions 42 --long 3 --tabs 16 --chat --modes-chat --on-home --home-view board --claude $stub >/dev/null || exit 1
env -u DUO_SUPPORT_DIR -u DUO_SOCKET -u DUO_TOKEN DUO_SUPPORT_DIR=$fx/sup CLAUDE_CONFIG_DIR=$fx/cfg DUO_AUTOCONFIRM=1 \
  $app/Contents/MacOS/Duo --workspace $fx/ws 2>$fx/stderr.txt &
pid=$!
: > $fx/cpu.txt
for ((t = 5; t <= secs; t += 5)); do sleep 5; echo "$t $(ps -o %cpu= -p $pid)" >> $fx/cpu.txt; done
running=$(pgrep -f "$root/scripts/scale-tui.py" | wc -l | tr -d ' ')
kill -TERM $pid; for i in {1..20}; do kill -0 $pid 2>/dev/null || break; sleep 1; done
kill -0 $pid 2>/dev/null && echo "✘ Duo didn't quit on SIGTERM within 20 s (pid $pid)"
pkill -f "$fx/claude" 2>/dev/null; pkill -f "$root/scripts/scale-tui.py" 2>/dev/null
python3 - $fx "$running" "$app" <<'PY'
import json, os, sys
fx, running, app = sys.argv[1], int(sys.argv[2]), sys.argv[3]
rows = [l.split() for l in open(f"{fx}/cpu.txt") if len(l.split()) == 2]
late = [float(c) for t, c in rows if int(t) >= 15]
hangs = []
p = f"{fx}/sup/Duo/logs/hangs.jsonl"
if os.path.exists(p):
    hangs = [json.loads(l) for l in open(p) if l.strip()]
restored = next((l.strip() for l in open(f"{fx}/stderr.txt") if l.startswith("restore:")), "restore: (none)")
mean = sum(late) / len(late) if late else 999
long = [h["ms"] for h in hangs if h["ms"] >= 1000]
checks = [
    (f"CPU after launch settles: mean {mean:.1f}% after 15 s (budget 10%)", mean <= 10),
    (f"no stall of a second or more (stalls: {[h['ms'] for h in hangs]})", not long),
    (f"at most 2 stalls of 250 ms or more ({len(hangs)})", len(hangs) <= 2),
    (f"the restored tabs came back ({restored})", "parked" in restored or "reopened" in restored),
]
print(f"{app}: {restored}; {running} stand-in session(s) running at the end; CPU {[c for _, c in rows]}")
bad = 0
for name, ok in checks:
    print(("✔ " if ok else "✘ ") + name); bad += not ok
print(f"{len(checks) - bad} within budget, {bad} over")
sys.exit(1 if bad else 0)
PY
ok=$?
rm -rf $fx
exit $ok
