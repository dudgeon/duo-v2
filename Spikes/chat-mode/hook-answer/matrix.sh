#!/bin/zsh
# matrix.sh: every variant, both versions; prints what the hook did, whether the dialog drew, and what the screen said after.
R=${0:A:h}/run.sh
V5=$HOME/.local/share/claude/versions/2.1.325; V4=/tmp/cc284/node_modules/.bin/claude
one() { # tag bin mode wait [timeout]
  zsh $R $2 $1 $3 $4 ${5:-600} 2>&1 | tail -3
  python3 - $1 <<'PY'
import re,sys
b=open('/tmp/dmq-ha-%s/out/raw.bin' % sys.argv[1],'rb').read().decode('utf8','replace')
t=re.sub(r'\x1b\[[0-9;?]*[a-zA-Z]','',b)
s=t[t.rfind('SCENARIO'):]
m=[x for x in ['User answered','declined','Done.','hook','timed out','error','denied','blocked'] if x in s]
i=max(s.find('User answered'), s.find('PreToolUse:'), 0)
print('  marks:', m); print('  tail:', re.sub(r'\s+',' ',s[-420:]))
PY
}
for spec in "$@"; do one ${=spec} & done; wait
