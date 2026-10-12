#!/bin/zsh
# The duo-signal spike's live run (ENH-70): Duo itself, isolated and in the background, on a scratch
# workspace whose Home session talks to the chat-mode spike's mock API (no login, no tokens). Chat
# sends a long reply, a Bash permission and an AskUserQuestion; stderr gets chat-state and, with
# DUO_SIGNAL_TRACE, each change of screen, chat state, signal and request (signal-trace lines).
#   Spikes/duo-signal/live.sh <name> <out>     FLAG=1 (DUO_SIGNAL=1) or FLAG=0
#   CLAUDE=<path>  a claude to run instead (it is wrapped to log its arguments to <out>/argv.log)
#   APP=<Duo.app>  another build (main's, for the comparison)
# Isolated (CLAUDE.md): its own support folder and Claude config under /tmp, quit by SIGTERM to its pid.
set -u
root=${0:A:h:h:h}
name=$1 out=${2:A}
app=${APP:-$root/build/Duo.app}
fx=/tmp/dsg-$name
chmod -R u+w $fx 2>/dev/null; rm -rf $fx $out; mkdir -p $out
$root/Spikes/chat-mode/scratch.sh $fx >/dev/null
print -- '---\ngoal: "duo-signal spike"\n---\n\n# Home\n' > $fx/ws/HOME.md
print -- ${CFG_SETTINGS:-'{"permissions":{"defaultMode":"default"}}'} > $fx/cfg/settings.json   # CFG_SETTINGS: e.g. disableAllHooks, for the canary
mkdir -p $fx/sup/Duo
real=${CLAUDE:-$(command -v claude)}
print -- "#!/bin/sh\necho \"\$*\" >> $out/argv.log\nexec $real \"\$@\"" > $fx/claude; chmod +x $fx/claude
print -- "{\"claudePath\":\"$fx/claude\",\"home\":\"$fx/ws\"}" > $fx/sup/Duo/state.json
port=$((8820 + RANDOM % 100))
(cd $root/Spikes/duo-signal && MOCK_PORT=$port MOCK_CWD=$fx/ws MOCK_LOG=$out/mock.log node $root/Spikes/chat-mode/mock.mjs) >/dev/null 2>&1 &
mock=$!; trap "kill $mock 2>/dev/null" EXIT
sleep 0.5
then="wait:6,chat:on,wait:2,chat-state,chat-send:SCENARIO:long write a lot,wait:14,chat-state"
then+=",chat-send:SCENARIO:bash,wait:4,chat-state,chat-answer:1,wait:4,chat-state"
then+=",chat-send:SCENARIO:ask1,wait:4,chat-state,chat-ask:decline,wait:4,chat-state"
flag=(); [[ ${FLAG:-1} == 1 ]] && flag=(DUO_SIGNAL=1)
run() {   # run <capture> <then>
env -u DUO_SUPPORT_DIR -u DUO_SOCKET -u DUO_TOKEN -u DUO_SIGNAL DUO_SUPPORT_DIR=$fx/sup CLAUDE_CONFIG_DIR=$fx/cfg DUO_AUTOCONFIRM=1 \
  ANTHROPIC_BASE_URL=http://127.0.0.1:$port ANTHROPIC_API_KEY=sk-ant-mock-key-0000000000000000000 DISABLE_AUTOUPDATER=1 \
  ANTHROPIC_MODEL=claude-haiku-5-5 DUO_SIGNAL_TRACE=1 $flag \
  $app/Contents/MacOS/Duo --workspace $fx/ws --capture-window $1 --then "$2" 2>>$out/stderr.txt &
pid=$!
for i in {1..120}; do [[ -f $1 ]] && break; sleep 1; done
sleep 1
kill -TERM $pid 2>/dev/null; for i in {1..15}; do kill -0 $pid 2>/dev/null || break; sleep 1; done
}
# A first launch copies and validates the mod (F-297: it is remembered per claude and version), as
# Geoff's Duo would have on an earlier day; the second is the run, its Home session started at launch.
run $out/warm.png "wait:5"
: > $out/stderr.txt
run $out/final.png "$then"
cp $fx/sup/Duo/events/*.signal.json $out/ 2>/dev/null
ls $fx/sup/Duo/mods 2>/dev/null > $out/mods.txt
cp $fx/sup/Duo/mods/canary.json $out/ 2>/dev/null
# What duo2 doctor says about mods: this instance's support folder, and a socket that can't reach any Duo.
DUO_SUPPORT_DIR=$fx/sup DUO_SOCKET=/nonexistent DUO_TOKEN=none $app/Contents/Helpers/duo2 doctor 2>&1 | grep -A5 "^Claude Code mods" > $out/doctor.txt
grep -E "^(chat-state|  mode=|signal-trace|  step|  asked|  answer|  line)" $out/stderr.txt > $out/summary.txt
echo "$name: $(grep -c signal-trace $out/stderr.txt) trace lines; argv: $(head -c 300 $out/argv.log 2>/dev/null | tr '\n' ' ')"
