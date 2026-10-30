#!/bin/zsh
# Usage: vi-run.sh <support dir> <then-actions...>  : an isolated background Duo that feeds recorded screens to a shell tab.
set -u
sup=$1; shift
then=${(j:,:)@}
rm -f /tmp/vi-t/done.png
mkdir -p $sup
cd /Users/geoff/repos/duo-v2/.claude/worktrees/voice-input
open -g -n --env DUO_SUPPORT_DIR=$sup --env CLAUDE_CONFIG_DIR=/tmp/vi-cc --env ANTHROPIC_MODEL=claude-haiku-5-5 --env DUO_VOICE_MIC_ON_SHELL=1 ${VI_ENV:+--env $VI_ENV} --stderr $sup.err build/Duo.app --args --workspace /tmp/vi-ws --window ${VI_WINDOW:-1600x1000} --capture-window /tmp/vi-t/done.png --then "$then"
for i in {1..150}; do [[ -f /tmp/vi-t/done.png ]] && break; sleep 1; done
sleep 2
pid=$(pgrep -f -- "--capture-window /tmp/vi-t/done.png" | head -1)
[[ -n $pid ]] && kill -TERM $pid
grep -a "voice-shot\|voice-sheet\|trace capture" $sup.err | cut -c1-300
