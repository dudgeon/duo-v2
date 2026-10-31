import json, sys
C = '\x1b['
forty = [x for i in range(1, 41) for x in ({'type': f'line {i}'}, {'nl': 1})][:-1]
cases = [
  {'name': 'forty: up past the top, then down', 'setup': forty,
   'ops': [{'keys': [C + 'A'] * 39}, {'snap': 'top'}, {'keys': [C + 'A']}, {'snap': 'history'}, {'keys': [C + 'B']}, {'snap': 'down'}, {'keys': ['X']}, {'peek': 'text'}]},
  {'name': 'two lines: up past the top, then down', 'setup': [{'type': 'alpha beta'}, {'nl': 1}, {'type': 'gamma'}, {'keys': [C + 'A', C + 'D']}],
   'ops': [{'snap': 'top'}, {'keys': [C + 'A']}, {'snap': 'history'}, {'keys': [C + 'B']}, {'snap': 'down'}, {'keys': ['X']}, {'peek': 'text'}]},
]
json.dump(cases, open(sys.argv[1], 'w'))
