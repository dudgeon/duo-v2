#!/bin/zsh
# C-30 (F-126): an isolated Duo restarts on a restore file that lists three idle sessions, then
# `duo2 session close` ends them. Reports every child Duo leaves exiting (state E) or unreaped,
# and whether `duo2 session archive` takes them. A stand-in `claude` (no turns spent) that, like
# Claude Code, writes to its terminal as it exits. Never touches the user's Duo: its own support
# folder, its own CLAUDE_CONFIG_DIR, and duo2 pointed at it with both DUO_SOCKET and DUO_TOKEN.
#   scripts/check-reap.sh        exit 0 when nothing is left behind
set -u
cd "${0:A:h:h}"
S=$(cd "$(mktemp -d /tmp/c30.XXXX)" && pwd -P)   # short: the socket's path must stay under 104
WS=$S/ws CFG=$S/cfg SUP=$S/sup
mkdir -p $WS/checkout $CFG/projects $CFG/sessions $SUP/Duo
print -- "# Home" > $WS/HOME.md
cp -Rp ~/DuoAcceptance/workspace/payments/checkout/PROJECT.md $WS/checkout/

# Three fixture sessions, refiled under the scratch project.
src=$(ls ~/.claude/projects/-Users-geoff-DuoAcceptance-workspace-payments-checkout/*.jsonl | head -1)
proj=$WS/checkout
bucket=$CFG/projects/${proj//[^A-Za-z0-9]/-}
mkdir -p $bucket
ids=()
for n in 1 2 3; do
  id=$(uuidgen | tr A-Z a-z); ids+=$id
  cp -p $src $bucket/$id.jsonl
  old=$(basename $src .jsonl)
  sed -i '' -e "s|$old|$id|g" -e "s|/Users/geoff/DuoAcceptance/workspace/payments/checkout|$WS/checkout|g" $bucket/$id.jsonl
done

# The stand-in: a beacon like Claude's, idle at a prompt. On TERM or HUP it does what a signed-in
# Claude Code does: writes its goodbye frame (from a writer thread, as Node does) and runs its exit
# hooks, which take a while. A process that exits with output its terminal never reads waits in the
# kernel (state E) until someone reads it, or the terminal closes: no one reaps it till then.
cat > $S/claude <<'EOF'
#!/usr/bin/python3 -I
import json, os, signal, sys, threading, time
args = sys.argv[1:]
sid = next((args[i + 1] for i, a in enumerate(args[:-1]) if a in ("--resume", "--session-id")), "")
with open(os.path.join(os.environ["CLAUDE_CONFIG_DIR"], "sessions", f"{os.getpid()}.json"), "w") as f:
    json.dump({"pid": os.getpid(), "sessionId": sid, "cwd": os.getcwd(), "status": "idle", "kind": "interactive", "entrypoint": "cli"}, f)
print(f"stand-in claude {sid}", flush=True)
def bye(*_):
    time.sleep(0.1)
    threading.Thread(target=lambda: os.write(1, b"goodbye " * 100_000), daemon=True).start()
    time.sleep(float(os.environ.get("STANDIN_HOOKS", "2")))
    os._exit(0)
signal.signal(signal.SIGTERM, bye); signal.signal(signal.SIGHUP, bye)
while True: time.sleep(0.2)
EOF
chmod +x $S/claude
# CHECK_REAP_CLAUDE=<path> runs a real claude instead: with the scratch config it isn't signed in,
# so it sits at its first-run screen and spends nothing.
print -r -- "{\"claudePath\":\"${CHECK_REAP_CLAUDE:-$S/claude}\",\"root\":\"$WS\"}" > $SUP/Duo/state.json
python3 - "$WS" "$SUP/Duo" "${ids[@]}" <<'EOF'
import json, sys
ws, sup, ids = sys.argv[1], sys.argv[2], sys.argv[3:]
h = 1469598103934665603
for ch in ws: h = ((h ^ ord(ch)) * 1099511628211) & (2**64 - 1)
def b36(n):
    s = ""
    while True:
        n, r = divmod(n, 36); s = "0123456789abcdefghijklmnopqrstuvwxyz"[r] + s
        if n == 0: return s
state = {"version": 1, "root": ws, "project": ws + "/checkout", "leftCollapsedAllProjects": False, "leftCollapsedProject": False,
         "projects": [{"folder": ws + "/checkout", "sessions": ids, "documents": [], "consoleTab": ids[0], "rightTab": "Project"}]}
json.dump(state, open(f"{sup}/restore-{b36(h)}.json", "w"))
EOF

env -u DUO_SOCKET -u DUO_TOKEN -u DUO_SESSION_ID DUO_SUPPORT_DIR=$SUP CLAUDE_CONFIG_DIR=$CFG \
  build/Duo.app/Contents/MacOS/Duo --workspace $WS 2> $S/duo.err &
duo=$!
for i in {1..30}; do [[ -f $SUP/Duo/endpoint.json ]] && break; sleep 1; done
export DUO_SOCKET=$(python3 -c "import json;print(json.load(open('$SUP/Duo/endpoint.json'))['socket'])")
export DUO_TOKEN=$(python3 -c "import json;print(json.load(open('$SUP/Duo/endpoint.json'))['token'])")
duo2=build/Duo.app/Contents/Helpers/duo2
for i in {1..30}; do [[ $(pgrep -P $duo | wc -l) -ge 4 ]] && break; sleep 1; done
sleep 3
grep restore: $S/duo.err
pids=$(pgrep -P $duo | paste -sd, -)   # pgrep skips a process that's exiting, so keep the list
masters() { lsof -p $duo 2>/dev/null | awk '/ptmx/ {print $4 "@" $6}' | tr '\n' ' ' }
print "pty masters Duo holds (fd@device): $(masters)"
print "children after restore:"; ps -o pid,stat,tty,command -p $pids 2>/dev/null | cut -c1-110

for id in $ids; do print "close ${id:0:8}: $($duo2 session close $id 2>&1 | tail -1)"; done
# Watch for 5 s: a child seen in state E is exiting with nobody reading its terminal.
seen=0
for i in {1..25}; do
  e=$(ps -o stat= -p $pids 2>/dev/null | grep -c E)
  (( e > 0 )) && { (( seen < e )) && seen=$e; print "  +$((i * 2))00 ms: $e exiting, Duo holds $(masters)"; }
  sleep 0.2
done
print "pty masters Duo holds: $(masters)"
print "children after close:"; ps -o pid,ppid,stat,tty,command -p $pids 2>/dev/null | cut -c1-110
left=$(ps -o pid=,stat= -p $pids 2>/dev/null | awk '$2 ~ /[EZ]/' | wc -l | tr -d ' ')
for id in $ids; do print "archive ${id:0:8}: $($duo2 session archive $id 2>&1 | tail -1 | cut -c1-80)"; done

kill -TERM $duo; for i in {1..15}; do kill -0 $duo 2>/dev/null || break; sleep 1; done
print "children seen exiting after close: $seen; still exiting or unreaped: $left"
(( seen == 0 && left == 0 )) && { rm -rf $S; exit 0 }
print "kept $S for a look"; exit 1
