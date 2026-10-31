import json, sys
# Vim mode: the scratch config's editorMode is vim (run with CFG=s-vim). The case's clear leaves INSERT via 'i'.
C = '\x1b['
three = [{'type': 'alpha beta gamma'}, {'nl': 1}, {'type': 'delta epsilon zeta'}, {'nl': 1}, {'type': 'eta theta iota'}]
cases = [
  {'name': 'insert: footer', 'setup': three, 'ops': [{'snap': 'insert'}]},
  {'name': 'insert: up up home, X', 'setup': three, 'ops': [{'keys': [C + 'A', C + 'A', C + 'H', 'X']}, {'peek': 'text'}]},
  {'name': 'insert: down x2 end from row 0', 'setup': three + [{'keys': [C + 'A', C + 'A', C + 'H']}], 'ops': [{'keys': [C + 'B', C + 'B', C + 'F', 'X']}, {'peek': 'text'}]},
  {'name': 'insert: alt+d csi-u mid word', 'setup': three + [{'keys': [C + 'D'] * 6}], 'ops': [{'keys': [C + '100;3u']}, {'peek': 'text'}]},
  {'name': 'insert: ctrl+w then ctrl+_ undo', 'setup': three, 'ops': [{'keys': [C + '119;5u']}, {'snap': 'after ctrl+w'}, {'keys': ['\x1f']}, {'peek': 'text'}]},
  {'name': 'normal: footer', 'setup': three + [{'keys': ['\x1b']}], 'ops': [{'snap': 'normal'}]},
  {'name': 'normal: up up home, then i X', 'setup': three + [{'keys': ['\x1b']}], 'ops': [{'keys': [C + 'A', C + 'A', C + 'H', 'i', 'X']}, {'peek': 'text'}]},
  {'name': 'normal: down x2 end from row 0, then a X', 'setup': three + [{'keys': [C + 'A', C + 'A', C + 'H', '\x1b']}], 'ops': [{'keys': [C + 'B', C + 'B', C + 'F', 'a', 'X']}, {'peek': 'text'}]},
  {'name': 'normal: alt+d csi-u', 'setup': three + [{'keys': [C + 'D'] * 6, 'wait': 100}, {'keys': ['\x1b']}], 'ops': [{'keys': [C + '100;3u']}, {'snap': 'after'}, {'peek': 'text'}]},
  {'name': 'normal: dw then ctrl+_ undo', 'setup': three + [{'keys': ['\x1b', '0']}], 'ops': [{'keys': ['d', 'w']}, {'snap': 'after dw'}, {'keys': ['\x1f']}, {'peek': 'text'}]},
]
json.dump(cases, open(sys.argv[1], 'w'))
