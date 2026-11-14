import json, sys
R = json.load(open(sys.argv[1])); OUT = sys.argv[2]
projects = ["checkout","vendor-review","pricing","ops-notes","refunds","onboarding","billing","search","mobile-app","data-export","support-bot","launch-plan"]
opts = []
meta = {
 'cur': ('A', 'As drawn on 4a′: pale tints', 'Toolbar L 0.90 to 0.94, chroma 0.03. Keeps text2 on the toolbar. Twelve hues 22.5° apart, no orange or red.', 'text2'),
 'o2':  ('B', 'Real colours, six hues × two depths', 'The toolbar becomes a real colour (chroma up to 0.14) in a light and a deep step, so depth tells apart what hue alone can\'t. Toolbar text moves from text2 to text. Still no orange or red.', 'text'),
 'o3':  ('C', 'As B, with coral and ochre allowed', 'As B, but the hues spread round the whole wheel except the needs-you orange itself (h 22–64 stays out). The needs-you chip keeps its ring and a solid fill (white in light, the dark pane in dark) on every coloured toolbar.', 'text'),
}
for k in ('cur','o2','o3'):
    r = R[k]; L, T, D, crumb = meta[k]
    cols = []
    for i, c in enumerate(r['cols']):
        cols.append({'name': c['name'], 'l': c['l'], 'd': c['d'], 'pl': c['pl'], 'pd': c['pd'], 'p': projects[i],
                     'crumbL': '#5B636D' if crumb == 'text2' else '#1F2328', 'crumbD': '#9AA1AB' if crumb == 'text2' else '#E6E8EB',
                     'chip': i % 4 == 0})
    opts.append({'letter': L, 'title': T, 'desc': D, 'cols': cols,
                 'stat': 'Closest pair %.1f light, %.1f dark · pairs easy to tell apart (ΔE ≥ 15): %d%% light, %d%% dark' % (r['light'][0], r['dark'][0], r['light'][1], r['dark'][1]),
                 'rec': L == 'C'})
data = json.dumps({'opts': opts}, ensure_ascii=False)
LBL = 'font-size: 11px; line-height: 16px; font-weight: 600; letter-spacing: 0.06em; color: #5B636D'
def strip(mode):
    g = '{{c.l}}' if mode == 'l' else '{{c.d}}'; t = '#1F2328' if mode == 'l' else '#E6E8EB'
    cr = '{{c.crumbL}}' if mode == 'l' else '{{c.crumbD}}'; rule = '#C9CDD3' if mode == 'l' else '#2B2F36'
    pane = '{{c.pl}}' if mode == 'l' else '{{c.pd}}'
    needs = '#C2410C' if mode == 'l' else '#F97316'; chipbg = '#FFFFFF' if mode == 'l' else '#181A1E'
    return f'''<div style="display: flex; flex-direction: column; border: 1px solid {rule}; border-radius: 5px; overflow: hidden">
<div style="display: flex; align-items: center; gap: 5px; height: 22px; padding: 0 7px; background: {g}; color: {t}; font-size: 10px; white-space: nowrap">
<span style="display: flex; gap: 3px; margin-right: 3px"><span style="width: 6px; height: 6px; border-radius: 50%; background: #FF5F57"></span><span style="width: 6px; height: 6px; border-radius: 50%; background: #FEBC2E"></span><span style="width: 6px; height: 6px; border-radius: 50%; background: #28C840"></span></span>
<span style="color: {cr}">All projects ›</span><span style="font-weight: 600">{{{{c.p}}}}</span>
<sc-if value="{{{{c.chip}}}}" hint-placeholder-val="{{{{ true }}}}"><span style="margin-left: auto; padding: 0 4px; border: 1.5px solid {needs}; border-radius: 4px; background: {chipbg}; color: {needs}; font-size: 8px; line-height: 12px; font-weight: 600">1 needs you</span></sc-if>
</div>
<div style="height: 6px; background: {pane}; border-top: 1px solid {rule}"></div>
</div>'''
board = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Telling windows apart</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<style>
body{{margin:0}}
</style>
</helmet>
<div style="width: 1720px; height: 920px; box-sizing: border-box; padding: 40px 48px; display: flex; flex-direction: column; gap: 20px; background: #F3F4F6; color: #1F2328; font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif; font-size: 13px; line-height: 20px">
<div style="display: flex; flex-direction: column; gap: 4px">
<span style="{LBL}">DECISION 4a″ · Q-441 · AFTER GEOFF'S NOTE ON 4a′</span>
<span style="font-size: 22px; line-height: 28px; font-weight: 600">Telling windows apart at a glance: three directions [P]</span>
<span style="color: #5B636D; white-space: normal; max-width: 1500px">Geoff on 4a′: “these are all far too similar … colors are meant to help rapidly distinguish between disparate windows”. Measured, he's right: on 4a′ no two toolbars are 15 apart (OKLab ΔE ×100, the dataviz method's line for easy to tell apart), and the closest are 1.9, about the smallest step anyone can see. Each column is twelve windows' toolbars, light and dark, with the pane tint below. Twelve colours can't all be 15 apart under any design, but the project name sits in every toolbar too, so the closest pair needs only to differ, not shout.</span>
</div>
<div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 24px">
<sc-for list="{{{{opts}}}}" as="o" hint-placeholder-count="3">
<div style="display: flex; flex-direction: column; gap: 10px; padding: 14px; border: 1px solid #C9CDD3; border-radius: 8px; background: #FFFFFF">
<span style="display: flex; align-items: baseline; gap: 8px"><span style="font-size: 16px; font-weight: 600">{{{{o.letter}}}} · {{{{o.title}}}}</span><sc-if value="{{{{o.rec}}}}" hint-placeholder-val="{{{{ true }}}}"><span style="padding: 0 6px; border: 1px solid #1F2328; border-radius: 4px; font-size: 11px; font-weight: 600">Recommended</span></sc-if></span>
<span style="color: #5B636D; white-space: normal; min-height: 60px">{{{{o.desc}}}}</span>
<span style="font-weight: 600; white-space: normal">{{{{o.stat}}}}</span>
<div style="display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px">
<div style="display: flex; flex-direction: column; gap: 5px"><span style="{LBL}">LIGHT</span>
<sc-for list="{{{{o.cols}}}}" as="c" hint-placeholder-count="12">{strip('l')}</sc-for></div>
<div style="display: flex; flex-direction: column; gap: 5px; padding: 0 6px 6px; border-radius: 6px; background: #0C0D10"><span style="{LBL}; color: #9AA1AB">DARK</span>
<sc-for list="{{{{o.cols}}}}" as="c" hint-placeholder-count="12">{strip('d')}</sc-for></div>
</div>
<div style="display: flex; flex-wrap: wrap; gap: 4px 10px; font-size: 11px; line-height: 16px; color: #5B636D">
<sc-for list="{{{{o.cols}}}}" as="c" hint-placeholder-count="12"><span>{{{{c.name}}}} {{{{c.l}}}}</span></sc-for>
</div>
</div>
</sc-for>
</div>
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":1720,"height":920}}}}'>
class Component extends DCLogic {{
  renderVals() {{
    return DATA;
  }}
}}
</script>
</body>
</html>
'''
open(OUT + '/ColourApart.dc.html', 'w').write(board.replace('DATA', data))
print('ok')
