import json, sys
C = '\x1b['
BS = C + '127u'
three = [{'type': 'alpha beta gamma'}, {'nl': 1}, {'type': 'delta epsilon zeta'}, {'nl': 1}, {'type': 'eta theta iota'}]
long1 = ('The quick brown fox jumps over the lazy dog while the band plays on, and then it keeps '
         'running past the barn, the mill and the river until the sun goes down behind the hills.')
paste30 = '\n'.join(f'pasted line {i} of thirty' for i in range(1, 31))
cases = [
  {'name': 'B select all (3 lines), backspace', 'setup': three, 'ops': [{'dragBox': 'all'}, {'snap': 'sel'}, {'osc': 'copy on select'}, {'keys': [BS]}, {'snap': 'after'}, {'peek': 'text'}]},
  {'name': 'B select all (3 lines), Duo replaces: backspace then X', 'setup': three, 'ops': [{'dragBox': 'all'}, {'keys': [BS, 'X']}, {'peek': 'text'}]},
  {'name': 'B select all (wrapped + line), backspace', 'setup': [{'type': long1}, {'nl': 1}, {'type': 'second line'}], 'ops': [{'dragBox': 'all'}, {'snap': 'sel'}, {'osc': 'copy'}, {'keys': [BS]}, {'peek': 'text'}]},
  {'name': 'B select all with a placeholder, backspace', 'setup': [{'type': 'before '}, {'paste': paste30}, {'type': ' after'}], 'ops': [{'dragBox': 'all'}, {'osc': 'copy'}, {'keys': [BS]}, {'peek': 'text'}]},
  {'name': 'B select all, trailing blank line', 'setup': three + [{'nl': 1}], 'ops': [{'dragBox': 'all'}, {'keys': [BS]}, {'peek': 'text'}]},
  {'name': 'B select all, wide + emoji', 'setup': [{'type': '日本語のテキスト and émoji 👩‍💻 here'}, {'nl': 1}, {'type': 'next 👍'}], 'ops': [{'dragBox': 'all'}, {'osc': 'copy'}, {'keys': [BS]}, {'peek': 'text'}]},
  {'name': 'B from caret 5 left, then shift+left, shift+home, backspace', 'setup': three, 'ops': [{'dragBox': {'fromCaret': 5}}, {'keys': [C + '1;2D']}, {'snap': 'shift-left'}, {'keys': [C + '1;2H']}, {'snap': 'shift-home'}, {'keys': [BS]}, {'peek': 'text'}]},
  {'name': 'B selection, then shift+up (extend up)', 'setup': three, 'ops': [{'dragBox': {'fromCaret': 3}}, {'keys': [C + '1;2A']}, {'snap': 'shift-up'}, {'keys': [BS]}, {'peek': 'text'}]},
  {'name': 'B selection, then alt+shift+left (not bound)', 'setup': three, 'ops': [{'dragBox': {'fromCaret': 3}}, {'keys': [C + '1;4D']}, {'snap': 'alt-shift-left'}, {'keys': [BS]}, {'peek': 'text'}]},
  {'name': 'B selection, then plain left (collapses?)', 'setup': three, 'ops': [{'dragBox': {'fromCaret': 3}}, {'keys': [C + 'D']}, {'snap': 'left'}, {'keys': ['X']}, {'peek': 'text'}]},
  {'name': 'B selection, then fwd delete', 'setup': three, 'ops': [{'dragBox': {'fromCaret': 4}}, {'keys': [C + '3~']}, {'peek': 'text'}]},
]
json.dump(cases, open(sys.argv[1], 'w'))
print(len(cases))
