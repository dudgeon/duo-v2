#!/bin/zsh
# The PoC page against the mock API: http://127.0.0.1:8780. Ctrl-C to stop.
#   ./start.sh            mock replies (type SCENARIO:<name> in a prompt: md ask askmulti read plan agent long err bash)
#   ./start.sh --real     your own Claude login, a throwaway workspace, Haiku (DUO_MODEL); spends tokens
set -e
here=${0:A:h}
dir=$($here/scratch.sh)
cd $here
if [[ ${1:-} == --real ]]; then
  exec node server.mjs --cwd $dir/ws --run $dir/run -- --model ${DUO_MODEL:-claude-haiku-4-5-20251001}
fi
MOCK_CWD=$dir/ws MOCK_LOG=$dir/mock.log node mock.mjs &
mock=$!; trap "kill $mock" EXIT
sleep 0.5
env CLAUDE_CONFIG_DIR=$dir/cfg ANTHROPIC_BASE_URL=http://127.0.0.1:8765 ANTHROPIC_API_KEY=sk-ant-mock-key-0000000000000000000 \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_AUTOUPDATER=1 \
  node server.mjs --cwd $dir/ws --run $dir/run ${=SERVER_ARGS:-} -- --model claude-haiku-4-5-20251001
