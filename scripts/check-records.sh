#!/bin/bash
# After a merge: every record id (F-n, C-n, Q-n, DL-n, ENH-n) in either parent must still be in the result.
# A conflict resolved to one side can drop a whole run of records (c6aa7c8 lost F-114 to F-119).
#   scripts/check-records.sh [merge-commit]   (default HEAD)
set -e
m=${1:-HEAD}
ids() {
  git show "$1:docs/plan/findings.md" 2>/dev/null | grep -oE '^## F-[0-9]+' || true
  git show "$1:docs/plan/concerns-and-questions.md" 2>/dev/null | grep -oE '^\| [CQ]-[0-9]+' || true
  git show "$1:docs/design/decisions.md" 2>/dev/null | grep -oE '^\| DL-[0-9]+' || true
  git show "$1:docs/plan/enhancements.md" 2>/dev/null | grep -oE '^\| ENH-[0-9]+' || true
}
# Any commit: no record id twice (a union merge keeps both copies of a row both sides edited).
if ! git rev-parse -q --verify "$m^2" >/dev/null; then
  dupes=$(ids "$m" | sort | uniq -d)
  [ -z "$dupes" ] && { echo "records ok (not a merge: duplicates only)"; exit 0; }
  echo "duplicated in $m:" $dupes; exit 1
fi
lost=$(comm -23 <( (ids "$m^1"; ids "$m^2") | sort -u) <(ids "$m" | sort -u))
dupes=$(ids "$m" | sort | uniq -d)
[ -z "$lost$dupes" ] && { echo "records ok"; exit 0; }
[ -n "$lost" ] && echo "lost in $m:" $lost
[ -n "$dupes" ] && echo "duplicated in $m:" $dupes
exit 1
