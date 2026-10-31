import json, sys
# S1's open facts: ↑ on the first row with history, a long prompt's box, ⌥d as CSI u, the wrap width.
C = '\x1b['
long1 = ('The quick brown fox jumps over the lazy dog while the band plays on, and then it keeps '
         'running past the barn, the mill and the river until the sun goes down behind the hills.')
url = 'see https://example.com/' + 'a' * 120 + ' end'
forty = [x for i in range(1, 41) for x in ({'type': f'line {i}'}, {'nl': 1})][:-1]
cases = [
  {'name': 'make history', 'setup': [{'type': 'an earlier prompt'}, {'keys': ['\r'], 'wait': 3000}, {'keys': ['\x1b', '\x1b'], 'wait': 500}], 'ops': [{'snap': 'after submit'}]},
  {'name': 'up on the first row, caret mid-row (history exists)', 'setup': [{'type': 'alpha beta gamma'}, {'nl': 1}, {'type': 'delta'}, {'keys': [C + 'A']}],
   'ops': [{'snap': 'row0'}, {'keys': [C + 'A']}, {'snap': 'after up'}, {'peek': 'text'}]},
  {'name': 'up on the first row, caret at col 0 (history exists)', 'setup': [{'type': 'alpha beta gamma'}, {'nl': 1}, {'type': 'delta'}, {'keys': [C + 'A', C + 'H']}],
   'ops': [{'keys': [C + 'A']}, {'snap': 'after up'}, {'peek': 'text'}]},
  {'name': 'down on the last row (history exists)', 'setup': [{'type': 'alpha beta gamma'}, {'nl': 1}, {'type': 'delta'}],
   'ops': [{'keys': [C + 'B']}, {'snap': 'after down'}, {'peek': 'text'}]},
  {'name': 'forty lines: the box', 'setup': forty, 'ops': [{'snap': 'end'}, {'keys': [C + 'A'] * 30}, {'snap': 'up30'}, {'keys': [C + 'A'] * 9}, {'snap': 'up39'}, {'keys': [C + 'H', 'X']}, {'snap': 'X at start?'}, {'peek': 'text'}]},
  {'name': 'alt+d csi-u, mid word', 'setup': [{'type': 'alpha beta gamma'}, {'keys': [C + 'D'] * 8}], 'ops': [{'keys': [C + '100;3u']}, {'peek': 'text'}]},
  {'name': 'alt+d csi-u, at a space', 'setup': [{'type': 'alpha beta gamma'}, {'keys': [C + 'D'] * 11}], 'ops': [{'keys': [C + '100;3u']}, {'peek': 'text'}]},
  {'name': 'alt+d csi-u, at a line end', 'setup': [{'type': 'alpha'}, {'nl': 1}, {'type': 'beta gamma'}, {'keys': [C + 'A', C + 'F']}], 'ops': [{'keys': [C + '100;3u']}, {'peek': 'text'}]},
  {'name': 'wrap: long1', 'setup': [{'type': long1}], 'ops': [{'snap': 'wrapped'}]},
  {'name': 'wrap: url', 'setup': [{'type': url}], 'ops': [{'snap': 'wrapped'}]},
  {'name': 'wrap: spaces', 'setup': [{'type': 'word ' * 30}], 'ops': [{'snap': 'wrapped'}, {'peek': 'text'}]},
]
json.dump(cases, open(sys.argv[1], 'w'))
print(len(cases))
