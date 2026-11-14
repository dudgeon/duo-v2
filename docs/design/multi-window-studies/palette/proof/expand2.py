import json, re, sys
src = open(sys.argv[1]).read()
body = re.search(r'<x-dc>.*?</helmet>(.*)</x-dc>', src, re.S).group(1)
data = json.loads(re.search(r'return (\{.*\});\n  \}', src, re.S).group(1))
def look(ctx, p):
    p = p.strip()
    if p == 'true': return True
    v = ctx
    for k in p.split('.'): v = v[k]
    return v
def find_close(s, i, tag):
    depth = 0; pat = re.compile(r'<(/?)%s\b' % tag)
    for m in pat.finditer(s, i):
        depth += -1 if m.group(1) else 1
        if depth == 0: return m.start(), s.index('>', m.start()) + 1
def render(s, ctx):
    out = ''; i = 0
    while True:
        m = re.compile(r'<sc-(for|if)\b([^>]*)>').search(s, i)
        if not m:
            out += s[i:]; break
        out += s[i:m.start()]
        cs, ce = find_close(s, m.start(), 'sc-' + m.group(1))
        inner = s[m.end():cs]; attrs = dict(re.findall(r'([\w-]+)="([^"]*)"', m.group(2)))
        if m.group(1) == 'for':
            for it in look(ctx, attrs['list'].strip('{} ')):
                c = dict(ctx); c[attrs['as']] = it; out += render(inner, c)
        elif look(ctx, attrs['value'].strip('{} ')):
            out += render(inner, ctx)
        i = ce
    return re.sub(r'\{\{\s*([^}]+?)\s*\}\}', lambda m: str(look(ctx, m.group(1))), out)
html = render(body, data); assert '{{' not in html
open(sys.argv[2], 'w').write('<!doctype html><html lang="en"><head><meta charset="utf-8"><style>body{margin:0}</style></head><body>' + html + '</body></html>')
