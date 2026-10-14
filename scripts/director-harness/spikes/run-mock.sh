#!/bin/zsh
# Runs a real `claude` against the mock API with a scratch config: no credentials, no tokens.
#   run-mock.sh <claude-binary> <turns.json> <out-dir> <seconds> "<prompt>" [-p] [claude args…]
# With -p it's a print-mode run; otherwise an interactive TUI in a PTY (pty-run.mjs).
# Needs NODE_PATH to reach node-pty and @xterm/headless for the interactive mode.
set -e
here=${0:A:h}
path=(/opt/homebrew/bin $path)
export NODE_PATH=${NODE_PATH:-${DIRECTOR_HARNESS_NODE:-$HOME/.cache/duo-director-harness}/node_modules}
bin=$1 turns=${2:A} out=${3:A} secs=$4 prompt=$5; shift 5
mkdir -p $out/cfg $out/ws
port=$((8800 + RANDOM % 900))
key=sk-ant-mock-key-0000000000000000000
ws=$out/ws
# RUN_MOCK_FLAGS='{"flag":true}' seeds the scratch config's cached feature flags, standing in for
# what the server would send a signed-in account (the mock has no flag service).
flags=${RUN_MOCK_FLAGS:-}
print -r -- "{${flags:+\"cachedGrowthBookFeatures\":$flags,}\"hasCompletedOnboarding\":true,\"theme\":\"dark\",\"numStartups\":5,\"customApiKeyResponses\":{\"approved\":[\"${key[-20,-1]}\"],\"rejected\":[]},\"projects\":{\"$ws\":{\"hasTrustDialogAccepted\":true,\"hasCompletedProjectOnboarding\":true},\"/private$ws\":{\"hasTrustDialogAccepted\":true,\"hasCompletedProjectOnboarding\":true}}}" > $out/cfg/.claude.json
# RUN_MOCK_USER_SETTINGS='{…}' becomes the scratch config's settings.json (user scope).
[[ -n ${RUN_MOCK_USER_SETTINGS:-} ]] && print -r -- $RUN_MOCK_USER_SETTINGS > $out/cfg/settings.json
MOCK_SCRIPT=$turns MOCK_LOG=$out/mock.jsonl MOCK_PORT=$port node $here/../mock-api.mjs > $out/mock.out 2>&1 &
mock=$!; trap "kill $mock 2>/dev/null" EXIT
sleep 0.5
cd $ws
common=(HOME=$HOME PATH=$PATH TERM=xterm-256color LANG=en_US.UTF-8 NODE_PATH=${NODE_PATH:-}
  CLAUDE_CONFIG_DIR=$out/cfg ANTHROPIC_BASE_URL=http://127.0.0.1:$port ANTHROPIC_API_KEY=$key
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_AUTOUPDATER=1
  ${flags:+CLAUDE_CODE_GB_DISK_CACHE_WHEN_TELEMETRY_OFF=1} ${=RUN_MOCK_ENV:-})
if [[ $1 == -p ]]; then
  shift
  env -i $common perl -e 'alarm shift; exec @ARGV' $secs $bin -p "$prompt" --model claude-haiku-5-5 "$@" > $out/print.txt 2>&1 || true
else
  env -i $common CLAUDE_BIN=$bin node $here/../pty-run.mjs $out $secs "$prompt" --model claude-haiku-5-5 "$@"
fi
