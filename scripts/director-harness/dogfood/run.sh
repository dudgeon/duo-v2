#!/bin/zsh
# Dogfood check (Geoff, 2026-10-15): does the vanilla duo-director skill, as written, find duo-v2's
# rules in PROJECT.md's ## Director (and a file that section points to) and follow them? The rules
# live in the fixture, not in any skill: the console route (D1, real wording; D2, a console it can
# reach), decisions as DL-n rows (D3), and "Geoff's asks start at once" (D4).
#
#   scripts/director-harness/dogfood/run.sh [--ref <git ref>] [--duo2 <binary>] [--case <name>]… [plugin-eval options…]
#
# The skill under test is skills/duo-director/SKILL.md at --ref (default feature/duo-director), copied
# unchanged; --duo2 is a duo2 built from the same ref (default: this checkout's .build/debug/duo2).
# DOGFOOD_MODEL picks the director's model (default Sonnet), DOGFOOD_MAX_USD the cost ceiling,
# DOGFOOD_OUT the output folder. Each case runs as you on a fresh config with a scratch HOME (F-314);
# nothing reaches a real Duo or the real console, and the HTML report isn't published.
# Runs under the shared GPU lock when GPU_LOCK is set.
set -e
here=${0:A:h}
root=$(git -C $here rev-parse --show-toplevel)
ref=feature/duo-director
duo2=$root/.build/debug/duo2
cases=()
while [[ $1 == --ref || $1 == --duo2 || $1 == --case ]]; do
  case $1 in
    --ref) ref=$2 ;;
    --duo2) duo2=$2 ;;
    --case) cases+=($2) ;;
  esac
  shift 2
done
[[ -x $duo2 ]] || { echo "no duo2 at $duo2 (build it at $ref, or pass --duo2)" >&2; exit 2 }
claude=${DOGFOOD_CLAUDE:-$(command -v claude || echo $HOME/.local/bin/claude)}
out=${DOGFOOD_OUT:-/tmp/duo-director-dogfood-$(date +%Y%m%d-%H%M%S)}
plugin=$out/duo-director
mkdir -p $plugin/evals
git -C $root show "${ref}:skills/duo-director/SKILL.md" | sed 's/{{FORMAT}}/1/' > $plugin/SKILL.md
[[ -s $plugin/SKILL.md ]] || { echo "no skill at ${ref}" >&2; exit 2 }
if (( ${#cases} )); then
  cp -R $here/evals/_lib $plugin/evals/
  for c in $cases; do cp -R $here/evals/$c $plugin/evals/; done
else
  cp -R $here/evals/. $plugin/evals/
fi
cp $duo2 $plugin/evals/_lib/duo2
# Cases inherit PATH, not DUO_*; each scaffold copies duo2 into the case's .director-bin (F-314).
export PATH=.director-bin:$PATH
# The lock script is the main checkout's (CLAUDE.md: never a work tree's copy): git's first work tree.
main=$(git -C $root worktree list --porcelain | sed -n '1s/^worktree //p')
lock=(${main:-$root}/scripts/gpu-lock.sh --shared director-dogfood)
[[ -n ${GPU_LOCK:-} && -x ${lock[1]} ]] || lock=()
cd $plugin
$lock $claude plugin ev""al $plugin --trust-plugin --scaffold --ablation none --no-publish \
  --model ${DOGFOOD_MODEL:-claude-sonnet-5-5} \
  --allow-tools Write Edit "Bash(duo2:*)" "Bash(ls:*)" "Bash(mkdir:*)" "Bash(git:*)" \
    "Bash(scripts/console.sh:*)" "Bash(./scripts/console.sh:*)" "Bash(sh scripts/console.sh:*)" \
  --max-cost-usd ${DOGFOOD_MAX_USD:-6} --output-dir $out/results --json $out/result.json --report $out/report.html "$@"
echo "Results: $out/result.json, $out/report.html (skill from $ref)"
