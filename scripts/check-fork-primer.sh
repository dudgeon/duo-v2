#!/bin/bash
# Does a /fork-style copy of a Duo session carry the primer's line, and does its own session id reach Bash? (F-424, DL-256)
# A planted parent transcript is resumed with --fork-session under a scratch CLAUDE_CONFIG_DIR, a dummy key and a
# local stub API: no login, no real turn. The stub answers the first request with a Bash tool call that writes
# $CLAUDE_CODE_SESSION_ID and $DUO_SESSION_ID to a file, then ends the turn. Primer text comes from DuoChecks
# (DUO_PRIMER_ID), so it is exactly what Duo would append. CLAUDE_BIN picks the CLI (the work Mac pins 2.1.284).
# Output of an older CLI may carry a warning line first; the report reads the last JSON line.
# Prints whether the request carried the primer line and the launch id, and the ids the Bash child saw.
set -u
D=$(cd "$(dirname "$0")/.." && pwd)
W=/tmp/dfpr; rm -rf "${W:?}"; mkdir -p $W/proj $W/cfg
PROJ=$(cd $W/proj && pwd -P)
ENC=$(echo "$PROJ" | sed 's/[^A-Za-z0-9]/-/g')
B=$W/cfg/projects/$ENC; mkdir -p $B
P=11111111-1111-4111-8111-111111111111
BIN=${CLAUDE_BIN:-claude}
(cd "$D" && DUO_PRIMER_ID=$P swift run -q DuoChecks) > $W/primer.txt 2>/dev/null
python3 "$D/scripts/check-fork-primer.py" plant "$B" "$P" "$PROJ"
python3 "$D/scripts/check-fork-primer.py" serve "$W" &
SRV=$!
sleep 1
cd $PROJ
env -u ANTHROPIC_AUTH_TOKEN CLAUDE_CONFIG_DIR=$W/cfg ANTHROPIC_API_KEY=sk-ant-dummy ANTHROPIC_BASE_URL=http://127.0.0.1:47124 \
  CLAUDE_CODE_MAX_RETRIES=0 DISABLE_TELEMETRY=1 DISABLE_AUTOUPDATER=1 \
  perl -e "alarm 90; exec @ARGV" $BIN --resume $P --fork-session -p "run it" --model claude-haiku-5-5 --allowedTools Bash \
  --output-format json --append-system-prompt "$(cat $W/primer.txt)" > $W/out.txt 2>&1
echo "exit $? ($($BIN --version))"
kill $SRV
python3 "$D/scripts/check-fork-primer.py" report "$W" "$P"
