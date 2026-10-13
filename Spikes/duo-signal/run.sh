#!/bin/zsh
# The duo-signal spike's mod-alone run (ENH-70): the real claude TUI on a PTY against the chat-mode
# spike's mock API, a scratch config, no credentials and no tokens, with Mods/duo-signal passed by
# --plugin-dir as a read-only copy (F-280). Writes <out>/timeline.log (time.mjs) and signal.json.
#   Spikes/duo-signal/run.sh <work> <out> [steps.json] [--no-mod] [extra claude args...]
# <work> holds a copy of the chat-mode spike with its node_modules (npm install there once).
set -e
root=${0:A:h:h:h}
work=${1:A} out=${2:A}; shift 2
steps=${root}/Spikes/duo-signal/steps.json
[[ ${1:-} == *.json ]] && { steps=${1:A}; shift }
mod=1; [[ ${1:-} == --no-mod ]] && { mod=0; shift }
cp $root/Spikes/duo-signal/time.mjs $root/Spikes/chat-mode/mock.mjs $root/Spikes/chat-mode/scratch.sh $work/
rm -rf $out; mkdir -p $out
dir=$($work/scratch.sh $out/scratch)
plugin=()
if [[ $mod == 1 ]]; then
  cp -R ${MOD_SRC:-$root/Mods/duo-signal} $out/mod; chmod -R a-w $out/mod   # MOD_SRC: a broken copy, for the fault runs
  plugin=(--plugin-dir $out/mod)
fi
port=${MOCK_PORT:-8793}
(cd $work && MOCK_PORT=$port MOCK_CWD=$dir/ws MOCK_LOG=$out/mock.log node mock.mjs) &
mock=$!; trap "kill $mock 2>/dev/null; chmod -R u+w $out/mod 2>/dev/null" EXIT
sleep 0.5
cd $dir/ws
env -i HOME=$HOME PATH=$PATH TERM=xterm-256color LANG=en_US.UTF-8 \
  CLAUDE_CONFIG_DIR=$dir/cfg ANTHROPIC_BASE_URL=http://127.0.0.1:$port ANTHROPIC_API_KEY=sk-ant-mock-key-0000000000000000000 \
  DISABLE_AUTOUPDATER=1 DUO_SIGNAL_FILE=$out/signal.json CLAUDE_BIN=${CLAUDE_BIN:-claude} \
  node $work/time.mjs $steps $out --session-id $(uuidgen | tr A-Z a-z) $plugin "$@"
