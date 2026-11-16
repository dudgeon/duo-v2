#!/bin/zsh
# Plays scenario-325.json against a real claude (F-731..): ./run-extra.sh <claude-bin> <out> <settings-json|-> [claude args…]
# Copies the spike to /tmp first (a work tree's own .claude/settings would change the mode). Mock API, no tokens.
set -e
here=${0:A:h}; bin=$1 out=${2:A} settings=$3; shift 3
dir=/tmp/cs-extra-$$; src=/tmp/cs-extra-src-$$
rm -rf $dir $src; mkdir -p $dir; cp -R $here $src; rm -rf $src/scratch
$src/scratch.sh $dir >/dev/null
mkdir -p $dir/other
(cd $dir/other && /usr/bin/git init -q && echo x > a.txt && /usr/bin/git add a.txt && /usr/bin/git -c user.email=a@b -c user.name=n commit -qm init && echo y >> a.txt)
[[ $settings != - ]] && print -- "$settings" > $dir/cfg/settings.json
port=$((8700 + RANDOM % 90))
(cd $src && MOCK_PORT=$port MOCK_CWD=$dir/ws MOCK_OTHER=$dir/other MOCK_LOG=$out.mock.log node mock.mjs) >/dev/null 2>&1 &
mock=$!; trap "kill $mock; rm -rf $dir $src" EXIT
sleep 0.6
mkdir -p /tmp/fakehome
cd $dir/ws
env -i HOME=/tmp/fakehome PATH=$PATH TERM=xterm-256color LANG=en_US.UTF-8 CLAUDE_CONFIG_DIR=$dir/cfg ANTHROPIC_BASE_URL=http://127.0.0.1:$port \
  ANTHROPIC_API_KEY=sk-ant-mock-key-0000000000000000000 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_AUTOUPDATER=1 CLAUDE_BIN=$bin \
  node $src/drive.mjs $here/scenario-325.json $out --model claude-haiku-5-5 --session-id $(uuidgen | tr A-Z a-z) "$@"
