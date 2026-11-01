import json, sys
C = '\x1b['
long1 = ('The quick brown fox jumps over the lazy dog while the band plays on, and then it keeps '
         'running past the barn, the mill and the river until the sun goes down behind the hills.')
paste30 = '\n'.join(f'pasted line {i} of thirty' for i in range(1, 31))
cases = [
  {'name': 'plain three lines, select across a new line',
   'setup': [{'type': 'alpha beta gamma'}, {'nl': 1}, {'type': 'delta epsilon zeta'}, {'nl': 1}, {'type': 'eta theta iota'}],
   'ops': [{'selectDelete': [6, 23]}]},
  {'name': 'plain, caret moved first (mid line 1)',
   'setup': [{'type': 'alpha beta gamma'}, {'nl': 1}, {'type': 'delta epsilon zeta'}, {'keys': [C + 'A', C + 'D', C + 'D']}],
   'ops': [{'selectDelete': [0, 5]}]},
  {'name': 'long wrapped line, select across the wrap',
   'setup': [{'type': long1}, {'nl': 1}, {'type': 'second line'}],
   'ops': [{'snap': 'wrapped'}, {'selectDelete': [40, 75]}]},
  {'name': 'wide and emoji',
   'setup': [{'type': '日本語のテキスト and émoji 👩‍💻 here'}, {'nl': 1}, {'type': 'next line'}],
   'ops': [{'selectDelete': [15, 26]}]},
  {'name': 'paste placeholder',
   'setup': [{'type': 'before '}, {'paste': paste30}, {'type': ' after'}],
   'ops': [{'snap': 'placeholder'}, {'peek': 'with placeholder'}, {'selectDelete': [9, 13]}]},
  {'name': 'paste placeholder, selection over it',
   'setup': [{'type': 'before '}, {'paste': paste30}, {'type': ' after'}],
   'ops': [{'selectDelete': [5, 10]}]},
  {'name': 'keys on a wrapped line',
   'setup': [{'type': long1}],
   'ops': [{'snap': 'end'}, {'keys': [C + '1;9D']}, {'snap': 'cmd-left'}, {'keys': [C + '1;9C']}, {'snap': 'cmd-right'},
           {'keys': [C + 'H']}, {'snap': 'home'}, {'keys': [C + 'F']}, {'snap': 'end-key'},
           {'keys': [C + '97;5u']}, {'snap': 'ctrl-a'}, {'keys': [C + '101;5u']}, {'snap': 'ctrl-e'},
           {'keys': [C + 'A']}, {'snap': 'up'}, {'keys': [C + 'A']}, {'snap': 'up2'}]},
  {'name': 'keys across lines: ctrl+backspace, alt+fwd delete, super up on line 1',
   'setup': [{'type': 'alpha beta gamma'}, {'nl': 1}, {'type': 'delta epsilon zeta'}, {'keys': [C + 'D'] * 3}],
   'ops': [{'keys': [C + '8;5u']}, {'snap': 'ctrl-bs'}, {'keys': [C + 'H', C + '3;3~']}, {'snap': 'alt-fwd-del at line start'},
           {'keys': [C + 'A', C + '1;9A']}, {'snap': 'super-up on line 1'}]},
]
json.dump(cases, open(sys.argv[1], 'w'))
print(len(cases))
