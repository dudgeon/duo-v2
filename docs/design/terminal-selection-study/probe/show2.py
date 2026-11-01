import json, sys
for c in json.load(open(sys.argv[1])):
    for s in c['snaps']:
        if s.get('name') == 'selectDelete':
            extra = '' if s.get('pass') else (s.get('align'), repr(s.get('expect'))[:160], repr(s.get('got'))[:160])
            print(f"{c['name'][:48]:48} caret={s.get('caret')} keys={s.get('keys')} pass={s.get('pass')}", extra)
