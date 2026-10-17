#!/bin/bash
# The merge checks (docs/director/merging-and-records.md §2) as one command: the director's gate for a branch.
#   GPU_LOCK=<lock dir> scripts/merge-gate.sh <sha|branch>
# Checks <sha|branch> out detached in a check work tree (default <main checkout>/.claude/worktrees/director-check,
# or $MERGE_GATE_TREE; created if missing) and never builds in the main checkout's build/ (it is signed ad hoc and
# Geoff's Duo may run from it). Each gate runs under the MAIN checkout's gpu-lock.sh --shared, by its full path.
# Prints one line per gate ("ok", "FAIL" or "SKIP", with seconds), and the log of each failed gate. Exits 1 if any
# gate failed. The timing checks (check-chat-perf, check-scale), the baseline comparison of the captures
# (samepng.py against the main without the merge) and check-launch-services.sh stay by hand.
# Gates: records, bundle, DuoChecks, ui + chat + composer focus with the front-app check (check-background.sh),
# editor and deck checks (SKIP when playwright-core isn't at $PWC, default /tmp/pwc), the stand-in claude check
# (check-context.sh).
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
gate() {   # gate <name> <command...>: one shared-lock hold per gate
  local name="$1" start rc; shift
  start=$SECONDS
  (cd "$tree" && "$lock" --shared "merge-gate $name" "$@") >"$log/$name.log" 2>&1; rc=$?
  secs=$((SECONDS - start))
  if [ $rc -eq 0 ]; then
    printf 'ok    %-22s %ss\n' "$name" "$secs"
  else
    printf 'FAIL  %-22s %ss (exit %s)\n' "$name" "$secs" "$rc"; failed=1
    tail -n 15 "$log/$name.log" | while IFS= read -r l; do echo "      $l"; done
  fi
}
gate records scripts/check-records.sh "$sha"
gate bundle scripts/bundle.sh
gate duochecks swift run DuoChecks
gate ui-chat-background env NO_BUILD=1 scripts/check-background.sh
if [ -d "$pwc/node_modules" ]; then
  gate editor env NO_BUILD=1 NODE_PATH="$pwc/node_modules" bash -c 'for c in scripts/check-editor-selection.mjs scripts/check-editor-motion.mjs scripts/check-deck-motion.mjs; do node "$c" || exit 1; done'
else
  printf 'SKIP  %-22s playwright-core not at %s (npm i playwright-core there)\n' editor "$pwc"
fi
gate stand-in-claude env NO_BUILD=1 scripts/check-context.sh
[ $failed -eq 0 ] && echo "merge-gate: all gates passed" || echo "merge-gate: FAILED (logs in $log)"
exit $failed
