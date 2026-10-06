#!/bin/zsh
# Makes a scratch Claude config and workspace for the mock: no credentials, no tokens, nothing of yours.
# Prints the folder. The config trusts the workspace and approves only the dummy key below.
set -e
dir=${1:-${0:A:h}/scratch}
mkdir -p $dir/cfg $dir/ws
key=sk-ant-mock-key-0000000000000000000
ws=${dir:A}/ws
cat > $dir/cfg/.claude.json <<JSON
{"hasCompletedOnboarding":true,"theme":"dark","numStartups":5,
 "customApiKeyResponses":{"approved":["${key[-20,-1]}"],"rejected":[]},
 "projects":{"$ws":{"hasTrustDialogAccepted":true,"hasCompletedProjectOnboarding":true},
             "/private$ws":{"hasTrustDialogAccepted":true,"hasCompletedProjectOnboarding":true}}}
JSON
printf '# Notes\n\nFirst line.\n' > $dir/ws/notes.md
echo ${dir:A}
