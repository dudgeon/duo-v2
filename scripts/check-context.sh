#!/bin/zsh
# ENH-16 (F-146): an isolated Duo starts a session in a project, with a stand-in `claude` (no
# turns spent) that runs the real SessionStart and UserPromptSubmit hooks from the settings file
# Duo gives it, with Claude Code's payloads, and keeps each hook's additionalContext. Checks what
# Claude would read about the project at start, on prompts, after a change to PROJECT.md, at
# compact, and when CLAUDE.md imports @PROJECT.md. Never touches the user's Duo: its own support
# folder, its own CLAUDE_CONFIG_DIR, and duo2 pointed at it with both DUO_SOCKET and DUO_TOKEN.
#   scripts/check-context.sh        exit 0 when every step reads as it should
set -u
cd "${0:A:h:h}"
S=$(cd "$(mktemp -d /tmp/ctx.XXXX)" && pwd -P)   # short: the socket's path must stay under 104
WS=$S/ws CFG=$S/cfg SUP=$S/sup OUT=$S/out
mkdir -p $WS/checkout/src $CFG/projects $CFG/sessions $SUP/Duo $OUT
print -- "# Home" > $WS/HOME.md
brief() { print -r -- "---"$'\n'"goal: $1"$'\n'"health: $2"$'\n'"next: $3"$'\n'"---"$'\n\n'"# checkout" > $WS/checkout/PROJECT.md }
brief "Ship the new checkout by November" at-risk "Fix the tax rounding bug"

# The stand-in: runs SessionStart (startup) as Claude Code does, then each command written to
# $S/cmd ("prompt", or "start compact|clear|resume"), saving the hooks' additionalContext.
cat > $S/claude <<'EOF'
#!/usr/bin/python3 -I
import json, os, subprocess, sys, time
args = sys.argv[1:]
sid = next((args[i + 1] for i, a in enumerate(args[:-1]) if a in ("--resume", "--session-id")), "")
settings = json.load(open(args[args.index("--settings") + 1]))
out, n = sys.argv[0].rsplit("/", 1)[0], 0
def fire(event, source=None):
    global n
    n += 1
    payload = {"session_id": sid, "cwd": os.getcwd(), "hook_event_name": event, "transcript_path": ""}
    if source: payload["source"] = source
    if event == "UserPromptSubmit": payload["prompt"] = "hello"
    texts = []
    for group in settings.get("hooks", {}).get(event, []):
        for h in group.get("hooks", []):
            t = time.time()
            try: r = subprocess.run(["/bin/sh", "-c", h["command"]], input=json.dumps(payload), capture_output=True, text=True, timeout=15)
            except subprocess.TimeoutExpired: r = subprocess.CompletedProcess([], 1, "", "timed out")
            open(f"{out}/hooks.log", "a").write(f"{n} {event} {time.time() - t:.2f}s exit {r.returncode} {r.stderr.strip()[:200]} :: {h['command'][-40:]}\n")
            if r.stdout.strip():
                texts.append(json.loads(r.stdout)["hookSpecificOutput"]["additionalContext"])
    open(f"{out}/out/{n}.tmp", "w").write("\n".join(texts))
    os.rename(f"{out}/out/{n}.tmp", f"{out}/out/{n}.txt")   # whole, so the script never reads half
print(f"stand-in claude {sid}", flush=True)
while not os.getcwd().endswith("/checkout"): time.sleep(1)   # Home's session, started at launch: idle
fire("SessionStart", "startup")
while True:
    cmd = f"{out}/cmd"
    if os.path.exists(cmd):
        c = open(cmd).read().split(); os.remove(cmd)
        fire("UserPromptSubmit") if c[0] == "prompt" else fire("SessionStart", c[1])
    time.sleep(0.1)
EOF
chmod +x $S/claude
print -r -- "{\"claudePath\":\"$S/claude\",\"root\":\"$WS\"}" > $SUP/Duo/state.json

env -u DUO_SOCKET -u DUO_TOKEN -u DUO_SESSION_ID DUO_SUPPORT_DIR=$SUP CLAUDE_CONFIG_DIR=$CFG \
  build/Duo.app/Contents/MacOS/Duo --workspace $WS 2> $S/duo.err &
duo=$!
trap 'kill -TERM $duo 2>/dev/null' EXIT
for i in {1..30}; do [[ -f $SUP/Duo/endpoint.json ]] && break; sleep 1; done
export DUO_SOCKET=$(python3 -c "import json;print(json.load(open('$SUP/Duo/endpoint.json'))['socket'])")
export DUO_TOKEN=$(python3 -c "import json;print(json.load(open('$SUP/Duo/endpoint.json'))['token'])")
duo2=build/Duo.app/Contents/Helpers/duo2
$duo2 session new --project checkout > /dev/null

fails=0 step=0
want() {  # want <n> <label> <exact text, or empty for none>
  for i in {1..100}; do [[ -f $OUT/$1.txt ]] && break; sleep 0.1; done
  local got=$(<$OUT/$1.txt 2>/dev/null)
  if [[ $got == "$3" ]]; then print "  ✔ $2"; else print "  ✘ $2\n    got:  ${got//$'\n'/$'\n'          }\n    want: ${3//$'\n'/$'\n'          }"; fails=$((fails+1)); fi
}
run() { step=$((step+1)); print -r -- "$*" > $S/cmd; }
P=$WS/checkout
P=${P#/private}   # Duo names folders as the user does: /tmp, not /private/tmp
full="Duo: This session is in the project “checkout” ($P). Its brief, from PROJECT.md (the user sees it on the project's tile in Duo):
- Goal: Ship the new checkout by November
- Health: at risk
- Next step: Fix the tax rounding bug"

print "project context, live (ENH-16, F-146)"
want 1 "startup: the project's name, folder, goal, health and next step" "$full"
run prompt; want 2 "a prompt with nothing changed: nothing" ""
brief "Ship the new checkout by November" on-track "Ship to 10% of traffic"
run prompt; want 3 "PROJECT.md edited: told once, on the next prompt" "Duo: The project's health is now “on track” (was “at risk”).
The project's next step is now “Ship to 10% of traffic” (was “Fix the tax rounding bug”)."
run prompt; want 4 "…and only once" ""
run start compact; want 5 "compact: the brief in full again" "${${full/at risk/on track}/Fix the tax rounding bug/Ship to 10% of traffic}"
print -- "@PROJECT.md" > $P/CLAUDE.md
run start resume; want 6 "CLAUDE.md imports @PROJECT.md: the name and folder only" "Duo: This session is in the project “checkout” ($P). Its CLAUDE.md imports PROJECT.md, so you already have its goal, health and next step."
run prompt; want 7 "…and a prompt after it: nothing" ""
print "$((7 - fails)) passed, $fails failed"
exit $((fails > 0))
