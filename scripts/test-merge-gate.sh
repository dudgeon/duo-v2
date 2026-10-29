#!/bin/bash
# Tests merge-gate.sh's own machinery (DL-240, ENH-284): the run log, the retry that marks a gate FLAKY, a real
# failure, and the hygiene line, without building anything. Uses its own check tree and log, never the director's.
#   GPU_LOCK=<lock dir> scripts/test-merge-gate.sh
set -uo pipefail
: "${GPU_LOCK:?set GPU_LOCK to the lock folder of this machine}"
here="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/mg-test.XXXXXX")"
trap 'git -C "$here" worktree remove --force "$tmp/tree" >/dev/null 2>&1; rm -rf "$tmp"' EXIT
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $1"; fi; }
run() { MERGE_GATE_TREE="$tmp/tree" MERGE_GATE_LOG="$tmp/log.tsv" "$here/scripts/merge-gate.sh" HEAD; }

out="$(MERGE_GATE_ONLY=records,hygiene,selftest-flaky MERGE_GATE_SELFTEST=1 run)"; rc=$?
ok "passes with a flaky gate" '[ $rc -eq 0 ]'
ok "prints FLAKY" 'grep -q "^FLAKY selftest-flaky" <<<"$out"'
ok "prints the hygiene summary" 'grep -q "hygiene: " <<<"$out"'
ok "logs records ok" 'awk -F"\t" "\$3==\"records\" && \$4==\"ok\"{f=1} END{exit !f}" "$tmp/log.tsv"'
ok "logs FLAKY" 'awk -F"\t" "\$3==\"selftest-flaky\" && \$4==\"FLAKY\"{f=1} END{exit !f}" "$tmp/log.tsv"'
ok "skips gates not asked for" '! grep -q "bundle" <<<"$out"'

out="$(MERGE_GATE_ONLY=selftest-flaky MERGE_GATE_SELFTEST=1 MERGE_GATE_RETRY=0 run)"; rc=$?
ok "fails with retry off" '[ $rc -eq 1 ]'
ok "logs FAIL" 'awk -F"\t" "\$3==\"selftest-flaky\" && \$4==\"FAIL\"{f=1} END{exit !f}" "$tmp/log.tsv"'
ok "log has five tab-separated fields" '! awk -F"\t" "NF != 5" "$tmp/log.tsv" | grep -q .'

echo "merge-gate tests: $pass passed${fail:+, $fail failed}" | sed 's/, 0 failed//'
[ $fail -eq 0 ]
