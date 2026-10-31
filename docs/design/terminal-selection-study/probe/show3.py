import json, sys
for c in json.load(open(sys.argv[1])):
    print('##', c['name'])
    for s in c['snaps']:
        if 'box' in s:
            b = s['box']
            if not b: print('   ', s['name'], 'NO BOX'); continue
            hi = [''.join(z['ch'] if z['hi'] else '·' for z in row if z['x'] >= 2).rstrip('·') for row in b['cells']]
            print('   ', s['name'], 'cursor', b['cursor'], 'rows', [r.replace('\xa0', ' ') for r in b['rows']], 'highlighted', [h for h in hi])
        elif 'clip' in s: print('   ', s['name'], s['clip'])
        elif 'text' in s: print('   ', s['name'], repr(s['text']))
