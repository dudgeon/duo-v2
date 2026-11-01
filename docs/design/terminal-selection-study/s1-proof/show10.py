import json, sys
for c in json.load(open(sys.argv[1])):
    out = []
    for s in c['snaps']:
        if s.get('name', '').startswith('duoJump'): out.append(' '.join(s['log']))
        elif 'text' in s and s.get('name', '').startswith('peek'):
            t = s['text'] or ''
            out.append(f"{s['name'][5:]}: {t[:28]!r}…{t[-22:]!r}" if len(t) > 52 else f"{s['name'][5:]}: {t!r}")
    print(f"{c['name'][:52]:52} | " + ' | '.join(out))
