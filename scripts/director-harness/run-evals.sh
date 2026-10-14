#!/bin/zsh
# Tier 2 (DL-206): the duo-director skill's scenario evals, through `claude plugin eval` on Haiku.
#   scripts/director-harness/run-evals.sh [--case <glob>] [--runs N] [other plugin-eval options…]
# Each case runs as you on a fresh config with a scratch HOME, so no credentials are copied and
# `duo2` inside a case can't reach any Duo (F-314): cases grade the director's judgement on the
# no-Duo rungs. Writes evals/results/ under the skill (git-ignored) and a JSON summary.
# Runs under the shared GPU lock; DIRECTOR_EVAL_CLAUDE picks another claude binary, DIRECTOR_EVAL_MODEL
# another model (the release gate runs claude-sonnet-5-5 too, C-87).
set -e
here=${0:A:h}
root=${here:h:h}
skill=$root/skills/duo-director
claude=${DIRECTOR_EVAL_CLAUDE:-$(command -v claude || echo $HOME/.local/bin/claude)}
python3 $root/scripts/gen-director-skill.py >/dev/null
out=${DIRECTOR_EVAL_OUT:-/tmp/duo-director-evals-$(date +%Y%m%d-%H%M%S)}
mkdir -p $out/bin
# This branch's duo2, first on PATH (cases inherit PATH, not DUO_*; F-314). Build it if missing.
[[ -x $root/.build/debug/duo2 ]] || (cd $root && swift build --product duo2 >/dev/null)
cp $root/.build/debug/duo2 $out/bin/duo2   # a copy: the sandbox may not read the repo
# The case sandbox can read neither /tmp nor the repo: each scaffold copies this duo2 into its own
# folder (.director-bin), and that relative entry goes first on PATH (F-314).
export DIRECTOR_EVAL_DUO2=$out/bin/duo2 PATH=.director-bin:$PATH
lock=(/Users/geoff/repos/duo-v2/scripts/gpu-lock.sh --shared director-evals)
[[ -n ${GPU_LOCK:-} && -x ${lock[1]} ]] || lock=()
cd $skill
$lock $claude plugin ev""al $skill --trust-plugin --scaffold --ablation none --model ${DIRECTOR_EVAL_MODEL:-claude-haiku-5-5} \
  --allow-tools Write Edit "Bash(duo2:*)" "Bash(ls:*)" "Bash(mkdir:*)" "Bash(git:*)" \
  --max-cost-usd ${DIRECTOR_EVAL_MAX_USD:-5} --json $out/result.json --report $out/report.html "$@"
echo "Results: $out/result.json, $out/report.html"
