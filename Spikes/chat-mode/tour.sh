#!/bin/zsh
# Plays a scenario file against the real TUI (headless, no browser) and dumps each screen to <out>/.
#   ./tour.sh scenario-tour.json /tmp/tour
set -e
here=${0:A:h}
steps=${1:A} out=${2:A}
dir=$($here/scratch.sh)
cd $here
MOCK_CWD=$dir/ws MOCK_LOG=$out.mock.log node mock.mjs &
mock=$!; trap "kill $mock" EXIT
sleep 0.5
cd $dir/ws
env -i HOME=$HOME PATH=$PATH ${EDITOR:+EDITOR=$EDITOR} TERM=xterm-256color LANG=en_US.UTF-8 \
  CLAUDE_CONFIG_DIR=$dir/cfg ANTHROPIC_BASE_URL=http://127.0.0.1:8765 ANTHROPIC_API_KEY=sk-ant-mock-key-0000000000000000000 \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_AUTOUPDATER=1 \
  node $here/drive.mjs $steps $out --model ${DUO_MODEL:-claude-haiku-5-5} --session-id $(uuidgen | tr A-Z a-z)
