import json, sys, os
C = '\x1b['
three = [{'type': 'alpha beta gamma'}, {'nl': 1}, {'type': 'delta epsilon zeta'}, {'nl': 1}, {'type': 'eta theta iota'}]
esc = [{'keys': ['\x1b']}] if os.environ.get('VIM') else []
mark = ['i', 'X'] if os.environ.get('VIM') else ['X']
markA = ['a', 'X'] if os.environ.get('VIM') else ['X']
def lines(n): return [x for i in range(1, n + 1) for x in ({'type': f'line {i}'}, {'nl': 1})][:-1]
cases = [
  {'name': 'up x2 then ctrl+a (csi-u)', 'setup': three + esc, 'ops': [{'keys': [C + 'A', C + 'A', C + '97;5u'] + mark}, {'peek': 'text'}]},
  {'name': 'from row 0: down x2 then ctrl+e (csi-u)', 'setup': three + [{'keys': [C + 'A', C + 'A']}] + esc, 'ops': [{'keys': [C + 'B', C + 'B', C + '101;5u'] + markA}, {'peek': 'text'}]},
  {'name': '12 lines (box full at 30 rows): up past the top, then down', 'setup': lines(12) + esc,
   'ops': [{'keys': [C + 'A'] * 12}, {'snap': 'history?'}, {'keys': [C + 'B']}, {'snap': 'back'}, {'keys': mark}, {'peek': 'text'}]},
]
json.dump(cases, open(sys.argv[1], 'w'))
