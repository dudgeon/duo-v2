#!/bin/zsh
# Tier 2 (DL-206, DL-352): the duo-director skill's scenario evals, through `claude plugin eval` on Haiku.
#   scripts/director-harness/run-evals.sh [--changed [REF]] [--full] [--case <glob>]… [--max-usd N] [--runs N]
#                                         [--include-retired] [--fresh] [--list] [other plugin-eval options…]
# Spends only where an edit could change the answer (DL-352; Geoff, 2026-11-16: "If we are not editing the skills I
# don't know why we'd repeatedly eval"):
#   --changed [REF]  (the default, REF defaults to the merge base with main) runs the cases whose mapped skill sections,
#                    reference files, code or own files (eval-map.json) differ from REF. Nothing changed: nothing runs.
#   --full           every case that has no cached result for this exact revision (a release that ships skill changes).
#   --case <glob>    just those cases (repeatable).
#   --max-usd N      a hard cap on the round's real cost, runs plus judges (default 0.50, or DIRECTOR_EVAL_MAX_USD).
#                    The run stops before the next case once it is reached (exit 3).
#   --runs N         runs per case (default 1; a case that misses is rerun with 3, as DL-349 says, if the cap allows).
#   --include-retired  also the cases eval-map.json retires (they failed on main too; Sonnet-bar cases, DL-330).
#   --fresh          ignore cached results.   --list  print the plan and stop (spends nothing).
# Results are cached per case by what it depends on (eval-select.py); an unchanged case is never run twice, and the
# cache is also the baseline: a changed case is shown beside what it scored at REF when that was cached.
# Each case runs as you on a fresh config with a scratch HOME, so no credentials are copied and `duo2` inside a case
# can't reach any Duo (F-314). Writes a JSON summary under $out. Runs under the shared GPU lock;
# DIRECTOR_EVAL_CLAUDE picks another claude binary, DIRECTOR_EVAL_MODEL another model (the release gate runs
# claude-sonnet-5-5 too, C-87).
set -e
here=${0:A:h}
root=${here:h:h}
skill=$root/skills/duo-director
sel=$here/eval-select.py
mode=changed base="" cases=() cap=${DIRECTOR_EVAL_MAX_USD:-0.50} runs=1 flags=() rest=()
while (( $# )); do
  case $1 in
    --changed) mode=changed; if [[ -n ${2:-} && $2 != --* ]]; then base=$2; shift; fi ;;
    --full) mode=full ;;
    --case) cases+=($2); shift ;;
    --max-usd) cap=$2; shift ;;
    --runs) runs=$2; shift ;;
    --include-retired|--fresh) flags+=($1) ;;
    --list) flags+=($1) ;;
    *) rest+=($1) ;;
  esac
  shift
done
model=${DIRECTOR_EVAL_MODEL:-claude-haiku-5-5}
main=$(git -C $root worktree list --porcelain | sed -n '1s/^worktree //p')
cache=${DIRECTOR_EVAL_CACHE:-${main:-$root}/.build/director-eval-cache}
selargs=(--root $root --model $model --cache $cache)
if (( ${#cases} )); then for c in $cases; do selargs+=(--case $c); done
elif [[ $mode == full ]]; then selargs+=(--full)
else
  [[ -n $base ]] || base=$(git -C $root merge-base HEAD main 2>/dev/null || echo HEAD)
  selargs+=(--base $base)
fi
plan=$(python3 $sel plan $selargs ${flags:#--list})
print -r -- $plan | awk -F'\t' '{printf "  %-9s %-34s %s\n", $1, $2, $3}'
todo=(${(f)"$(print -r -- $plan | awk -F'\t' '$1=="run"{print $2}')"})
(( ${#todo} )) || { echo "Nothing to run: no case's inputs changed (or each has a cached result). Spent \$0.00."; exit 0 }
if (( ${flags[(Ie)--list]} )); then echo "${#todo} case(s) would run."; exit 0; fi
python3 $root/scripts/gen-director-skill.py >/dev/null
claude=${DIRECTOR_EVAL_CLAUDE:-$(command -v claude || echo $HOME/.local/bin/claude)}
out=${DIRECTOR_EVAL_OUT:-/tmp/duo-director-evals-$(date +%Y%m%d-%H%M%S)}
mkdir -p $out/bin
# This branch's duo2, first on PATH (cases inherit PATH, not DUO_*; F-314). Build it if missing.
[[ -x $root/.build/debug/duo2 ]] || (cd $root && swift build --product duo2 >/dev/null)
cp $root/.build/debug/duo2 $out/bin/duo2   # a copy: the sandbox may not read the repo
# The case sandbox can read neither /tmp nor the repo: each scaffold copies this duo2 into its own
# folder (.director-bin), and that relative entry goes first on PATH (F-314).
export DIRECTOR_EVAL_DUO2=$out/bin/duo2 PATH=.director-bin:$PATH
# The lock script is the main checkout's (CLAUDE.md: never a work tree's copy).
lock=(${main:-$root}/scripts/gpu-lock.sh --shared director-evals)
[[ -n ${GPU_LOCK:-} && -x ${lock[1]} ]] || lock=()
cd $skill
spent=0 stopped=() results=()
run_case() {   # <case> <runs>: one case, bounded by what is left of the cap (runs are about two thirds of the real cost)
  local c=$1 n=$2 left=$(( cap - spent ))
  $lock $claude plugin ev""al $skill --trust-plugin --scaffold --ablation none --model $model --case $c --runs $n \
    --allow-tools Write Edit "Bash(duo2:*)" "Bash(ls:*)" "Bash(mkdir:*)" "Bash(git:*)" "Bash(python3:*)" \
    --max-cost-usd $(printf %.3f $(( left * 0.66 ))) --json $out/$c.$n.json $rest >/dev/null || true
  [[ -f $out/$c.$n.json ]] || return 0
  results+=($out/$c.$n.json)
  spent=$(python3 $here/eval-cost.py --total $results)
}
for c in $todo; do
  if (( spent >= cap )); then stopped+=($c); continue; fi
  run_case $c $runs
done
# DL-349: three runs on any miss, while the cap allows.
if (( runs < 3 )); then
  for f in $results; do
    c=${${f:t}%.*.json}
    (( spent >= cap )) && continue
    python3 $here/eval-cost.py --missed $f && run_case $c 3
  done
fi
(( ${#results} )) || { echo "No case ran."; exit 2 }
python3 $here/eval-cost.py --merge $out/result.json $results   # later files (the 3-run reruns) replace a case's first run
python3 $sel store $selargs --revision $(git -C $root rev-parse HEAD) $out/result.json >/dev/null
# The real cost: costUsd is the agent's runs only; the judges are billed apart (F-740).
python3 $here/eval-cost.py $out/result.json
if [[ -n $base ]]; then
  echo "Against $base (cached results only):"
  for c in $todo; do
    printf "  %-34s now %s, at %s %s\n" $c "$(python3 $here/eval-cost.py --rate $out/result.json $c)" $base "$(python3 $sel baseline $selargs --base $base $c)"
  done
fi
printf "Spent: \$%.2f of the \$%.2f cap (runs plus judges).\n" $spent $cap
echo "Results: $out/result.json"
if (( ${#stopped} )); then echo "STOPPED at the cap; not run: ${stopped}"; exit 3; fi
