#!/usr/bin/env python3
# A hook that answers AskUserQuestion itself (spike): waits WAIT seconds, as Duo's card would while the user picks,
# then returns the answers in updatedInput. MODE=pre: PreToolUse permissionDecision allow; MODE=perm: PermissionRequest allow.
import json, os, sys, time
p = json.load(sys.stdin)
log = os.environ.get('HOOK_LOG')
if log:
    open(log, 'a').write(json.dumps({'at': time.time(), 'event': p.get('hook_event_name'), 'tool': p.get('tool_name'), 'phase': 'start'}) + '\n')
if p.get('tool_name') != 'AskUserQuestion':
    sys.exit(0)
time.sleep(float(os.environ.get('WAIT', '3')))
inp = p.get('tool_input') or {}
answers = {}
for q in inp.get('questions', []):
    opts = q.get('options', [])
    answers[q['question']] = opts[-1]['label'] if opts else 'typed'
upd = dict(inp); upd['answers'] = answers
mode = os.environ.get('MODE', 'pre')
if mode == 'pre':
    out = {'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'allow', 'permissionDecisionReason': 'answered in Duo', 'updatedInput': upd}}
elif mode == 'perm':
    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow', 'updatedInput': upd}}}
elif mode == 'deny':
    out = {'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'deny', 'permissionDecisionReason': 'The user declined to answer in Duo and wants to talk it over first.'}}
if log:
    open(log, 'a').write(json.dumps({'at': time.time(), 'phase': 'answered', 'mode': mode}) + '\n')
print(json.dumps(out))
