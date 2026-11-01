import json, sys
# DL-274's keys as Duo sends them, into real Claude Code (kitty mode), read back through Ctrl+G.
C = '\x1b['
three = [{'type': 'alpha beta gamma'}, {'nl': 1}, {'type': 'delta epsilon zeta'}, {'nl': 1}, {'type': 'eta theta iota'}]
long1 = ('The quick brown fox jumps over the lazy dog while the band plays on, and then it keeps '
         'running past the barn, the mill and the river until the sun goes down behind the hills.')
def lines(n): return [x for i in range(1, n + 1) for x in ({'type': f'line {i}'}, {'nl': 1})][:-1]
J = lambda d: {'duoJump': d}
cases = [
  {'name': 'cmd-up from the end of three lines', 'setup': three, 'ops': [J('start'), {'keys': ['X']}, {'peek': 'X at the start'}]},
  {'name': 'cmd-up from the first row', 'setup': three + [{'keys': [C + 'A', C + 'A']}], 'ops': [J('start'), {'keys': ['X']}, {'peek': 'X at the start'}]},
  {'name': 'cmd-down from the first row', 'setup': three + [{'keys': [C + 'A', C + 'A', C + 'D']}], 'ops': [J('end'), {'keys': ['X']}, {'peek': 'X at the end'}]},
  {'name': 'cmd-up on a wrapped prompt', 'setup': [{'type': long1}, {'nl': 1}, {'type': 'second line'}], 'ops': [J('start'), {'keys': ['X']}, {'peek': 'X at the start'}]},
  {'name': 'cmd-down on a wrapped prompt from its start', 'setup': [{'type': long1}, {'nl': 1}, {'type': 'second line'}, {'keys': [C + 'A'] * 4 + ['\x01']}], 'ops': [J('end'), {'keys': ['X']}, {'peek': 'X at the end'}]},
  {'name': 'cmd-up, 40 lines (box full, scrolled)', 'setup': lines(40), 'ops': [J('start'), {'keys': ['X']}, {'peek': 'X at the start'}]},
  {'name': 'cmd-down, 40 lines from the start', 'setup': lines(40) + [{'keys': [C + 'A'] * 39 + ['\x01']}], 'ops': [J('end'), {'keys': ['X']}, {'peek': 'X at the end'}]},
  {'name': 'cmd-up, 10 lines (box exactly full, nothing hidden)', 'setup': lines(10), 'ops': [J('start'), {'keys': ['X']}, {'peek': 'X at the start'}]},
  {'name': 'opt-fwd-delete (Alt+D CSI u) mid word', 'setup': three + [{'keys': [C + 'D'] * 6}], 'ops': [{'keys': [C + '100;3u']}, {'peek': 'theta lost "ta"'}]},
  {'name': 'cmd-z (ctrl+_) after ctrl+w', 'setup': three, 'ops': [{'keys': [C + '119;5u']}, {'keys': ['\x1f']}, {'peek': 'unchanged'}]},
]
json.dump(cases, open(sys.argv[1], 'w'))
