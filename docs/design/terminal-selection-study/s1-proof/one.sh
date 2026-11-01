#!/bin/bash
# one.sh <mkcases.py> <tag> [rows]: runs the cases on two Claude Code builds and prints them (SHOW=<show*.py>).
# CLAUDE_311 and CLAUDE_284 name the binaries; run2.sh (the study's probe runner, in your scratch folder) sets the
# scratch CLAUDE_CONFIG_DIR, the mock key and a dead API address. CFG=s-vim picks a config with editorMode vim.
cd "${PROBE_DIR:-.}"
python3 $1 $2.cases.json
ROWS=${3:-30} bash run2.sh "$CLAUDE_311" $2.cases.json $2-311.json 2>/dev/null &
ROWS=${3:-30} bash run2.sh "$CLAUDE_284" $2.cases.json $2-284.json 2>/dev/null &
wait
for v in 311 284; do echo "==== $v"; python3 ${SHOW:-show6.py} $2-$v.json; done
