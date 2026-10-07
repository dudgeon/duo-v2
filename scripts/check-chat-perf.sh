#!/bin/zsh
# Chat mode's performance budget (DL-137, F-157): runs scripts/perf-chat.sh on the heavy generated
# session (82 MB, 95 turns, 3,600 tool calls) and fails if any phase is over its budget.
#
#   scripts/check-chat-perf.sh            build first
#   NO_BUILD=1 scripts/check-chat-perf.sh reuse build/Duo.app
#
# Budgets are main-thread stalls measured by the run's watchdog, with room for a busy Mac; before
# DL-137 the same run measured 2.9–3.5 s to open, 293 of 300 late scroll frames and 1.5–2.4 s
# stalls as replies arrived, and every reply pulled a scrolled-up feed to the bottom.
set -u
root=${0:A:h:h}
cd $root
[[ ${NO_BUILD:-} == 1 ]] || scripts/bundle.sh >/dev/null || exit 1
out=build/perf/check
rm -rf $out
scripts/perf-chat.sh $out --heavy >/dev/null 2>&1
python3 - $out/perf.log <<'PY'
import json, sys
ev = [json.loads(l) for l in open(sys.argv[1])]
def one(pred):
    m = [e for e in ev if pred(e)]
    return m[0] if m else None
opened = one(lambda e: str(e.get("watch", "")).startswith("follow"))
wheels = [e for e in ev if e.get("event") == "wheel"]
bottom = one(lambda e: e.get("watch") == "at-bottom")
up = one(lambda e: e.get("watch") == "scrolled-up")
rows = [
    ("opening a long chat: longest stall", opened and opened["stall_max_ms"], 600, "ms"),
    ("slow scroll: frames over 33 ms, of 300", wheels and wheels[0]["hitches_over_33ms"], 10, ""),
    ("fast flick: longest stall", len(wheels) > 1 and wheels[1]["stall_max_ms"], 250, "ms"),
    ("replies at the bottom: longest stall", bottom and bottom["stall_max_ms"], 600, "ms"),
    ("replies at the bottom: follows them (1 = yes)", bottom and (0 if bottom["follows_bottom"] else 1), 0, ""),
    ("a reply while scrolled up: longest stall", up and up["stall_max_ms"], 250, "ms"),
    ("a reply while scrolled up: follows it down (1 = yes)", up and (1 if up["follows_bottom"] else 0), 0, ""),
]
bad = 0
for name, got, budget, unit in rows:
    if got is None or got is False:
        print(f"✘ {name}: not measured"); bad += 1; continue
    ok = got <= budget
    bad += not ok
    print(f"{'✔' if ok else '✘'} {name}: {got:g}{unit} (budget {budget}{unit})")
if up: print(f"  (the view moved {abs(up['y_after'] - up['y_before'])} pt while scrolled up: the lazy stack's estimated height, ENH-23)")
print(f"{len(rows) - bad} within budget, {bad} over" + ("" if not bad else f"; see {sys.argv[1]}"))
sys.exit(1 if bad else 0)
PY
