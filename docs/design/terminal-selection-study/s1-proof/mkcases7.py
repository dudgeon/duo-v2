import json, sys
C = '\x1b['
def lines(n): return [x for i in range(1, n + 1) for x in ({'type': f'line {i}'}, {'nl': 1})][:-1]
cases = [{'name': f'{n} lines', 'setup': lines(n), 'ops': [{'snap': 'end'}]} for n in (5, 8, 9, 10, 11, 12, 16, 40)]
cases.append({'name': '40 lines, down at the bottom of a scrolled box', 'setup': lines(40),
              'ops': [{'keys': [C + 'A'] * 20}, {'snap': 'mid'}, {'keys': [C + 'B'] * 25}, {'snap': 'after 25 down'}, {'keys': ['X']}, {'peek': 'text'}]})
json.dump(cases, open(sys.argv[1], 'w'))
