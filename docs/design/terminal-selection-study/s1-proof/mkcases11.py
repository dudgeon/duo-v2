import json, sys
C = '\x1b['
cases = [
  {'name': '/model picker', 'setup': [{'type': '/model'}, {'keys': ['\r'], 'wait': 1500}], 'ops': [{'snap': 'picker'}, {'keys': [C + 'B']}, {'snap': 'after down'}, {'keys': ['\x1b']}]},
  {'name': '/effort picker', 'setup': [{'type': '/effort'}, {'keys': ['\r'], 'wait': 1500}], 'ops': [{'snap': 'picker'}, {'keys': ['\x1b']}]},
]
json.dump(cases, open(sys.argv[1], 'w'))
