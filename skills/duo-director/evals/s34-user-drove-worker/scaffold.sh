#!/bin/sh
# S34 (R1, the missed-turns failure, F-698): the user talked to a worker directly. Its last turn, which the
# user drove, ended on an offer ("If you agree, I'll pass this to the director") and no report ever came.
# The worker's session has ended. The note looks checked (the director read the worker's first report).
# The transcript is in .claude-config/projects/<this folder>/, where the wrapped duo2 reads Claude's sessions.
# Fails on main (2026-11-14): status skips a worker the user typed in, so nothing points the director at it.
lib=$(dirname "$0")/../_lib; . "$lib/setup.sh"; . "$lib/fixtures.sh"
wrap_duo2 CLAUDE_CONFIG_DIR=.claude-config
printf -- '---\ntitle: Team handbook\ngoal: keep the team handbook useful\n---\n# Team handbook\n' > PROJECT.md
mkdir -p tasks
sid=22222222-2222-4222-8222-222222222222
task_note handbook-study "Study how to split the handbook" in-progress "check_by: $(ago $((-2 * D)) '%Y-%m-%dT%H:%M:%S')
sessions:
  - \"[worker](duo2://session/$sid)\"
done_when: a study in tasks/handbook-study/study.md with a recommendation" \
  'Study whether the handbook should be split into smaller guides, and recommend.' \
  "$(ago $((5 * D)) '%Y-%m-%d %H:%M') Worker started." \
  "$(ago $((5 * D - 3 * H)) '%Y-%m-%d %H:%M') Checked: read the study; it recommends keeping one handbook."
mkdir -p tasks/handbook-study
printf '# Study\n\nRecommendation: keep one handbook, trim it.\n' > tasks/handbook-study/study.md
registry_worker tasks/handbook-study.md "$sid" 120
enc=$(pwd | sed 's/[^A-Za-z0-9]/-/g')
mkdir -p ".claude-config/projects/$enc"
t0=$(agoz $((5 * D)) '%Y-%m-%dT%H:%M:%S.000Z'); t1=$(agoz $((5 * D - H)) '%Y-%m-%dT%H:%M:%S.000Z')
t2=$(agoz $((4 * D)) '%Y-%m-%dT%H:%M:%S.000Z'); t3=$(agoz $((4 * D - 30)) '%Y-%m-%dT%H:%M:%S.000Z')
cwd=$(pwd)
cat > ".claude-config/projects/$enc/$sid.jsonl" <<EOF
{"type":"user","timestamp":"$t0","cwd":"$cwd","message":{"role":"user","content":"[director-cwd] You're the worker on the task whose note is $cwd/tasks/handbook-study.md, directed by director-cwd."}}
{"type":"assistant","timestamp":"$t1","message":{"role":"assistant","content":[{"type":"text","text":"Report: the study is in tasks/handbook-study/study.md. It recommends keeping one handbook and trimming it."}]}}
{"type":"assistant","timestamp":"$t1","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"SendMessage","input":{"to":"director-cwd","message":"Report: the study recommends keeping one handbook and trimming it."}}]}}
{"type":"user","timestamp":"$t2","cwd":"$cwd","origin":{"kind":"human"},"message":{"role":"user","content":"Actually I think we should split out an onboarding guide after all. New hires never read past page 3."}}
{"type":"assistant","timestamp":"$t3","message":{"role":"assistant","content":[{"type":"text","text":"That changes the recommendation: split out a short onboarding guide and keep the rest as the handbook. If you agree, I'll pass this to the director so it can start the split."}]}}
EOF
touch -t "$(ago $((4 * D - 30)) '%Y%m%d%H%M.%S')" ".claude-config/projects/$enc/$sid.jsonl"
