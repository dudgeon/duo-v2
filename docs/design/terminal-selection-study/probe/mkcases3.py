import json, sys
C = '\x1b['
three = [{'type': 'alpha beta gamma'}, {'nl': 1}, {'type': 'delta epsilon zeta'}, {'nl': 1}, {'type': 'eta theta iota'}]
# Box rows: 0 'alpha beta gamma' (text from col 2), 1 'delta epsilon zeta', 2 'eta theta iota'.
drag = [['down', 0, 8], ['drag', 0, 10], ['drag', 1, 6], ['drag', 1, 9], ['up', 1, 9]]   # 'ta gamma\ndelt'
cases = [
  {'name': 'drag, then nothing', 'setup': three, 'ops': [{'mouse': drag}, {'snap': 'dragged'}, {'osc': 'after drag'}, {'peek': 'text'}]},
  {'name': 'drag, then backspace', 'setup': three, 'ops': [{'mouse': drag}, {'keys': [C + '127u']}, {'snap': 'bs'}, {'peek': 'text'}]},
  {'name': 'drag, then type X', 'setup': three, 'ops': [{'mouse': drag}, {'keys': ['X']}, {'snap': 'typed'}, {'peek': 'text'}]},
  {'name': 'drag, then shift+left x2', 'setup': three, 'ops': [{'mouse': drag}, {'keys': [C + '1;2D', C + '1;2D']}, {'snap': 'extended'}, {'keys': [C + '127u']}, {'peek': 'text after bs'}]},
  {'name': 'drag, then ctrl+c', 'setup': three, 'ops': [{'mouse': drag}, {'keys': [C + '99;5u']}, {'osc': 'ctrl+c'}, {'snap': 'after'}, {'peek': 'text'}]},
  {'name': 'drag, then cmd+c (if it reached Claude)', 'setup': three, 'ops': [{'mouse': drag}, {'keys': [C + '99;9u']}, {'osc': 'cmd+c'}, {'peek': 'text'}]},
  {'name': 'drag, then cmd+x (if it reached Claude)', 'setup': three, 'ops': [{'mouse': drag}, {'keys': [C + '120;9u']}, {'osc': 'cmd+x'}, {'peek': 'text'}]},
  {'name': 'click to place caret', 'setup': three, 'ops': [{'mouse': [['down', 0, 5], ['up', 0, 5]]}, {'snap': 'clicked'}, {'keys': ['X']}, {'peek': 'text'}]},
  {'name': 'double click word', 'setup': three, 'ops': [{'mouse': [['down', 1, 10], ['up', 1, 10], ['down', 1, 10], ['up', 1, 10]], 'gap': 40}, {'snap': 'dbl'}, {'osc': 'dbl'}, {'keys': [C + '127u']}, {'peek': 'text'}]},
  {'name': 'triple click line', 'setup': three, 'ops': [{'mouse': [['down', 1, 10], ['up', 1, 10], ['down', 1, 10], ['up', 1, 10], ['down', 1, 10], ['up', 1, 10]], 'gap': 40}, {'snap': 'tpl'}, {'osc': 'tpl'}, {'keys': [C + '127u']}, {'peek': 'text'}]},
  {'name': 'shift+click extends from caret', 'setup': three, 'ops': [{'mouse': [['sdown', 0, 6], ['sup', 0, 6]]}, {'snap': 'shift-click'}, {'keys': [C + '127u']}, {'peek': 'text'}]},
  {'name': 'drag beyond the box (into transcript)', 'setup': three, 'ops': [{'mouse': [['down', 1, 6], ['drag', 0, 4], ['drag', -2, 4], ['up', -2, 4]]}, {'snap': 'out'}, {'keys': [C + '127u']}, {'peek': 'text'}]},
  {'name': 'shift+right with no selection', 'setup': three, 'ops': [{'keys': [C + 'H', C + '1;2C', C + '1;2C']}, {'snap': 'shift-right'}, {'keys': [C + '127u']}, {'peek': 'text'}]},
]
json.dump(cases, open(sys.argv[1], 'w'))
print(len(cases))
