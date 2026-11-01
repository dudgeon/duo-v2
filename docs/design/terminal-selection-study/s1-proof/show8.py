import json, sys
for c in json.load(open(sys.argv[1])):
    print('##', c['name'])
    for s in c['snaps']:
        if 'box' in s:
            b = s['box']
            print('   ', s['name'], b and b['cursor'], b and [r.replace('\xa0', ' ') for r in b['rows']])
            if 'footer' in c['name'] and s.get('screen'):
                print('      footer:', [l for l in s['screen'] if l.strip()][-2:])
        elif 'text' in s:
            print('   ', s['name'], repr(s['text'])[:90])
