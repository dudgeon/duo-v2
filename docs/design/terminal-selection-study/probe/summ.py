import json, sys
BASE = ['alpha beta gamma', 'delta epsilon zeta', 'eta theta iota']
def text(box):
    if not box: return None
    out = []
    for i, l in enumerate(box):
        l = l.replace('\xa0', ' ')
        if i == 0 and l[:2] in ('❯ ', '> '): l = l[2:]
        elif l.startswith('  '): l = l[2:]
        out.append(l)
    return out
def describe(after):
    t = text(after)
    if t is None: return 'BOX GONE'
    joined = '\n'.join(t)
    if '¶' not in joined: return 'no marker: ' + ' / '.join(t)
    r = next(i for i, l in enumerate(t) if '¶' in l); c = t[r].index('¶')
    plain = [l.replace('¶', '') for l in t]
    note = f'cursor L{r+1}:{c}'
    if plain != BASE: note += '  text: ' + ' / '.join(plain)
    return note
tags = sys.argv[1:]
res = {t: json.load(open(f'{t}.json')) for t in tags}
names = [c['name'] for c in res[tags[0]]['cases']]
for i, n in enumerate(names):
    cells = []
    for t in tags:
        c = res[t]['cases'][i]
        d = describe(c['after'])
        if c['before'] and text(c['before']) != BASE: d = 'BAD SETUP ' + d
        cells.append(d)
    if len(set(cells)) == 1: print(f'{n:34} | all: {cells[0]}')
    else: print(f'{n:34} | ' + ' | '.join(f'{t[2:]}: {x}' for t, x in zip(tags, cells)))
for t in tags: print(t, res[t]['pushes'])
