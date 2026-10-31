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
#   SHAPE=history                                the shape that stalled 0.2.18-0.2.21 (F-442): All projects listing
#                                                400 sessions in 4 projects with 70 task notes each, a transcript
#                                                growing every 3 s as on a real ~/.claude
#
# Isolated: its own support and Claude config folders under /tmp, a stand-in claude, no login, no
# network; never the user's Duo. It runs in the background (F-227): the window is drawn but never
# shown and never takes focus, and macOS may skip drawing a window that isn't on screen, so a
# background run understates layout cost (F-208's trap). The visible gate, DUO_TEST_FOREGROUND=1,
# shows the window and may take focus: a release gate, run only with Geoff's OK (CLAUDE.md).
set -u
root=${0:A:h:h}
cd $root
[[ ${NO_BUILD:-} == 1 || -n ${APP:-} ]] || scripts/bundle.sh >/dev/null || exit 1
app=${APP:-$root/build/Duo.app}
secs=${SECONDS_RUN:-60}
fx=$(mktemp -d /tmp/d-scale-XXXX); fx=${fx:A}   # realpath: restore matches Home by its real path
stub=$fx/claude
printf '#!/bin/sh\nexec /usr/bin/python3 -I %s "$@"\n' "$root/scripts/scale-tui.py" > $stub; chmod +x $stub
if [[ ${SHAPE:-} == history ]]; then
  python3 scripts/make-scale-fixture.py $fx --projects 4 --sessions 400 --long 0 --tasks 70 --home-view list --claude $stub >/dev/null || exit 1
else
  python3 scripts/make-scale-fixture.py $fx --projects 6 --sessions 42 --long 3 --tabs 16 --chat --modes-chat --on-home --home-view board --claude $stub >/dev/null || exit 1
fi
if [[ ${DUO_TEST_FOREGROUND:-} == 1 ]]; then
  echo "⚠ DUO_TEST_FOREGROUND=1: this run shows a Duo window and may take focus for about $secs s (Geoff's OK first)"
else
  echo "background run (F-227): the window is drawn but not shown, so CPU may understate drawing; the visible gate is DUO_TEST_FOREGROUND=1 (Geoff's OK first)"
fi
env -u DUO_SUPPORT_DIR -u DUO_SOCKET -u DUO_TOKEN DUO_SUPPORT_DIR=$fx/sup CLAUDE_CONFIG_DIR=$fx/cfg DUO_AUTOCONFIRM=1 \
  $app/Contents/MacOS/Duo --workspace $fx/ws 2>$fx/stderr.txt &
pid=$!
: > $fx/cpu.txt
if [[ ${SHAPE:-} == history ]]; then   # live sessions write their transcripts, so the lists refresh
  ( while kill -0 $pid 2>/dev/null; do sleep 3; f=$(ls $fx/cfg/projects/*/*.jsonl | head -1); tail -1 $f >> $f; done ) &
  act=$!
fi
for ((t = 5; t <= secs; t += 5)); do sleep 5; echo "$t $(ps -o %cpu= -p $pid)" >> $fx/cpu.txt; done
running=$(pgrep -f "$root/scripts/scale-tui.py" | wc -l | tr -d ' ')
kill -TERM $pid; for i in {1..20}; do kill -0 $pid 2>/dev/null || break; sleep 1; done
kill -0 $pid 2>/dev/null && echo "✘ Duo didn't quit on SIGTERM within 20 s (pid $pid)"
[[ -n ${act:-} ]] && kill $act 2>/dev/null
pkill -f "$fx/claude" 2>/dev/null; pkill -f "$root/scripts/scale-tui.py" 2>/dev/null
python3 - $fx "$running" "$app" "${SHAPE:-}" <<'PY'
import json, os, sys
fx, running, app, shape = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
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
if shape == "history":   # no tabs to restore, and the growing transcript keeps the refresh busy: stalls only
    checks = checks[1:3]
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
