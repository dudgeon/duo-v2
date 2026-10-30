#!/bin/bash
# The merge checks (docs/director/merging-and-records.md §2) as one command: the director's gate for a branch.
#   GPU_LOCK=<lock dir> scripts/merge-gate.sh <sha|branch>
# Checks <sha|branch> out detached in a check work tree (default <main checkout>/.claude/worktrees/director-check,
# or $MERGE_GATE_TREE; created if missing) and never builds in the main checkout's build/ (it is signed ad hoc and
# Geoff's Duo may run from it). Each gate runs under the MAIN checkout's gpu-lock.sh --shared, by its full path.
# Prints one line per gate ("ok", "FLAKY", "FAIL" or "SKIP", with seconds), and the log of each failed gate. Exits 1 if any
# gate failed. The timing checks (check-chat-perf, check-scale), the baseline comparison of the captures
# (samepng.py against the main without the merge) and check-launch-services.sh stay by hand.
# Gates: records, hygiene (warnings only: check-hygiene.py --summary, ENH-281 to ENH-285), bundle, DuoChecks,
# ui + chat + composer focus with the front-app check (check-background.sh), editor and deck checks (SKIP when
# playwright-core isn't at $PWC, default /tmp/pwc), the stand-in claude check (check-context.sh), and, only with
# MERGE_GATE_IDLE=1, the idle fitness function (check-scale.sh on the gate's own bundle, under the EXCLUSIVE lock,
# when the branch changes Sources/; ENH-286, opt-in until its budget is calibrated on debug builds).
# A failed gate runs once more (MERGE_GATE_RETRY=0 turns that off): a pass then prints FLAKY and counts as a pass.
# Every gate's result is appended to a machine-local log, $MERGE_GATE_LOG (default ~/Library/Logs/duo-dev/
# merge-gate.tsv: time, sha, gate, ok|FAIL|FLAKY|SKIP, seconds), which the weekly tidy-up reads (ENH-284).
# MERGE_GATE_ONLY=<gate,gate> runs just those gates (scripts/test-merge-gate.sh uses it).
set -uo pipefail
ref="${1:?usage: GPU_LOCK=<lock dir> scripts/merge-gate.sh <sha|branch>}"
: "${GPU_LOCK:?set GPU_LOCK to the lock folder of this machine (machine-local; the director gives it in each brief)}"
here="$(cd "$(dirname "$0")/.." && pwd)"
main="$(cd "$(git -C "$here" rev-parse --git-common-dir)/.." && pwd)"
lock="$main/scripts/gpu-lock.sh"
[ -x "$lock" ] || { echo "merge-gate: $lock is missing" >&2; exit 2; }
sha="$(git -C "$main" rev-parse --verify "$ref^{commit}")" || { echo "merge-gate: no such commit: $ref" >&2; exit 2; }
tree="${MERGE_GATE_TREE:-$main/.claude/worktrees/director-check}"
if [ -d "$tree" ]; then
  git -C "$tree" checkout -q --detach "$sha" || exit 2
else
  git -C "$main" worktree add -q --detach "$tree" "$sha" || exit 2
fi
log="$(mktemp -d "${TMPDIR:-/tmp}/merge-gate.XXXXXX")"
pwc="${PWC:-/tmp/pwc}"
echo "merge-gate: ${sha:0:12} in $tree (logs: $log)"
failed=0
runlog="${MERGE_GATE_LOG:-$HOME/Library/Logs/duo-dev/merge-gate.tsv}"
mkdir -p "$(dirname "$runlog")"
record() { printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${sha:0:12}" "$1" "$2" "$3" >>"$runlog"; }
wanted() { [ -z "${MERGE_GATE_ONLY:-}" ] || [[ ",$MERGE_GATE_ONLY," == *",$1,"* ]]; }
gate() {   # gate [--exclusive] <name> <command...>: one lock hold per try (shared unless --exclusive)
  local mode=--shared name start rc secs; [ "$1" = --exclusive ] && { mode=--exclusive; shift; }
  name="$1"; shift
  wanted "$name" || return 0
  start=$SECONDS
  (cd "$tree" && "$lock" $mode "merge-gate $name" "$@") >"$log/$name.log" 2>&1; rc=$?
  if [ $rc -ne 0 ] && [ "${MERGE_GATE_RETRY:-1}" != 0 ]; then
    (cd "$tree" && "$lock" $mode "merge-gate $name (retry)" "$@") >"$log/$name.retry.log" 2>&1 && rc=-1
  fi
  secs=$((SECONDS - start))
  if [ $rc -eq 0 ]; then
    printf 'ok    %-22s %ss\n' "$name" "$secs"; record "$name" ok "$secs"
  elif [ $rc -eq -1 ]; then
    printf 'FLAKY %-22s %ss (failed, then passed on retry: %s)\n' "$name" "$secs" "$log/$name.log"; record "$name" FLAKY "$secs"
  else
    printf 'FAIL  %-22s %ss (exit %s)\n' "$name" "$secs" "$rc"; failed=1; record "$name" FAIL "$secs"
    tail -n 15 "$log/$name.log" | while IFS= read -r l; do echo "      $l"; done
  fi
}
skip() { wanted "$1" || return 0; printf 'SKIP  %-22s %s\n' "$1" "$2"; record "$1" SKIP 0; }
gate records scripts/check-records.sh "$sha"
if wanted hygiene; then   # warnings only: never fails the gate
  python3 -I "$here/scripts/check-hygiene.py" --repo "$tree" --ref "$sha" --summary 2>&1 | while IFS= read -r l; do printf '%-6s%s\n' "" "$l"; done
  record hygiene ok 0
fi
[ "${MERGE_GATE_SELFTEST:-}" = 1 ] && gate selftest-flaky bash -c 'f="$1/selftest-flaky.mark"; [ -f "$f" ] && exit 0; touch "$f"; exit 1' _ "$log"
gate bundle scripts/bundle.sh
gate duochecks swift run DuoChecks
gate ui-chat-background env NO_BUILD=1 scripts/check-background.sh
if [ -f "$pwc/node_modules/playwright-core/package.json" ]; then
  gate editor env NO_BUILD=1 NODE_PATH="$pwc/node_modules" bash -c 'for c in scripts/check-editor-selection.mjs scripts/check-editor-motion.mjs scripts/check-deck-motion.mjs; do node "$c" || exit 1; done'
else
  skip editor "playwright-core not at $pwc (npm i playwright-core there)"
fi
gate stand-in-claude env NO_BUILD=1 scripts/check-context.sh
if [ "${MERGE_GATE_IDLE:-}" = 1 ]; then
  if git -C "$main" diff --name-only "refs/remotes/origin/main...$sha" -- Sources | grep -qv -e '^Sources/DuoChecks/' -e '^Sources/DuoKit/Debug/'; then
    gate --exclusive idle-scale env NO_BUILD=1 APP="$tree/build/Duo.app" scripts/check-scale.sh
  else
    skip idle-scale "no app change in Sources/"
  fi
fi
[ $failed -eq 0 ] && echo "merge-gate: all gates passed" || echo "merge-gate: FAILED (logs in $log)"
exit $failed
