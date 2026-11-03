import json, re, sys
proj = sys.argv[1]; out = sys.argv[2]
pal = json.load(open(sys.argv[3]))
def body(path):
    s = open(path).read()
    return re.search(r'<x-dc>.*?</helmet>(.*)</x-dc>', s, re.S).group(1)
def look(ctx, path):
    v = ctx
    for k in path.strip().split('.'):
        v = v[k]
    return v
def holes(s, ctx):
    return re.sub(r'\{\{\s*([^}]+?)\s*\}\}', lambda m: str(look(ctx, m.group(1))) if m.group(1) not in ('true',) else 'true', s)
def win_vals(mode, colour, project):
    base = {
      'light': dict(ground='#F3F4F6', pane='#FFFFFF', chatGround='#F3F4F6', toolOutput='#F8F9FA', selected='#E9ECEF', rule='#C9CDD3', controlEdge='#8B939C', text='#1F2328', text2='#5B636D', needs='#C2410C', placeholder='#D5D9DE', activeTint='#E8F0FA', chatYou='#DCE6F7'),
      'dark': dict(ground='#131518', pane='#181A1E', chatGround='#0C0D10', toolOutput='#131518', selected='#262A30', rule='#2B2F36', controlEdge='#6E7681', text='#E6E8EB', text2='#9AA1AB', needs='#F97316', placeholder='#2B2F36', activeTint='#18222E', chatYou='#22344F')}
    b = base[mode]
    c = next((x[mode] for x in pal['colours'] if x['id'] == colour), None)
    v = dict(b)
    if c:
        v.update(ground=c['ground'], pane=c['pane'], chatGround=c['chatGround'], toolOutput=c['toolOutputFill'], swatch=c['swatch'])
    else:
        v['swatch'] = b['pane']
    v.update(showSwatch=True, page=b['pane'], field=b['pane'], chipBg=b['pane'] if c else 'transparent', crumb=b['text'] if c else b['text2'], edgeLine=b['controlEdge'], project=project)
    return v
WIN = body(proj + '/WinColour12.dc.html')
def expand_win(s):
    s = re.sub(r'<sc-if[^>]*>(.*?)</sc-if>', r'\1', s, flags=re.S)
    return s
def render_import(m, ctx):
    attrs = dict(re.findall(r'(\w[\w-]*)="([^"]*)"', m.group(0)))
    a = {k: holes(v, ctx) for k, v in attrs.items()}
    return holes(expand_win(WIN), win_vals(a['mode'], a['colour'], a['project']))
src = open(proj + '/ColourTwelve.dc.html').read()
data = json.loads(re.search(r'return (\{.*\});\n  \}', src, re.S).group(1))
B = body(proj + '/ColourTwelve.dc.html')
def for_block(m):
    lst, var, inner = m.group(1), m.group(2), m.group(3)
    parts = []
    for item in data[lst]:
        ctx = dict(data); ctx[var] = item
        x = re.sub(r'<dc-import[^>]*></dc-import>', lambda mm: render_import(mm, ctx), inner)
        parts.append(holes(x, ctx))
    return ''.join(parts)
B = re.sub(r'<sc-for list="\{\{(\w+)\}\}" as="(\w+)"[^>]*>(.*?)</sc-for>', for_block, B, flags=re.S)
assert '{{' not in B and 'sc-' not in B, re.findall(r'.{40}\{\{.{30}', B)[:3]
open(out, 'w').write('<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Board 4a′ static proof</title><style>body{margin:0}</style></head><body>' + B + '</body></html>')
print('ok')
