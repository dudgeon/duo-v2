import json, sys
P = json.load(open(sys.argv[1])); OUT = sys.argv[2]
cols = P["colours"]; order = P["order"]; R = P["recipe"]
byid = {c["id"]: c for c in cols}
# ---------- component ----------
colmap = {m: {c["id"]: [c[m][k] for k in ("ground","pane","chatGround","toolOutputFill","swatch")] for c in cols} for m in ("light","dark")}
ids = ["none"] + [c["id"] for c in cols]
comp = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Mini window, twelve colours</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<style>
body{margin:0}
</style>
</helmet>
<div style="width: 520px; height: 325px; box-sizing: border-box; display: flex; flex-direction: column; border: 1px solid {{edgeLine}}; border-radius: 8px; overflow: hidden; background: {{pane}}; color: {{text}}; font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif; font-size: 10px; line-height: 14px; white-space: nowrap">
<div style="display: flex; align-items: center; gap: 6px; height: 24px; flex: none; padding: 0 8px; border-bottom: 1px solid {{rule}}; background: {{ground}}">
<span style="display: flex; gap: 4px; margin-right: 4px"><span style="width: 7px; height: 7px; border-radius: 50%; background: #FF5F57"></span><span style="width: 7px; height: 7px; border-radius: 50%; background: #FEBC2E"></span><span style="width: 7px; height: 7px; border-radius: 50%; background: #28C840"></span></span>
<span style="color: {{crumb}}">All projects</span>
<svg width="5" height="7" viewBox="0 0 8 10" aria-hidden="true"><path d="M2 1.5 6 5 2 8.5" fill="none" stroke="{{crumb}}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"></path></svg>
<span style="font-weight: 600">{{project}}</span>
<sc-if value="{{showSwatch}}" hint-placeholder-val="{{ true }}"><span style="display: flex; align-items: center; gap: 2px; padding: 1px 3px; border-radius: 4px"><span style="width: 8px; height: 8px; border-radius: 50%; border: 1px solid {{controlEdge}}; background: {{swatch}}"></span><svg width="5" height="4" viewBox="0 0 10 6" aria-hidden="true"><path d="M1 1l4 4 4-4" fill="none" stroke="{{crumb}}" stroke-width="1.5" stroke-linecap="round"></path></svg></span></sc-if>
<span style="display: flex; align-items: center; gap: 4px; margin-left: 4px; padding: 0 5px; border: 1.5px solid {{needs}}; border-radius: 5px; background: {{chipBg}}; font-size: 9px; font-weight: 600; color: {{needs}}"><svg width="6" height="6" viewBox="0 0 10 10" aria-hidden="true"><circle cx="5" cy="5" r="5" fill="{{needs}}"></circle></svg>1 needs you</span>
<span style="display: flex; align-items: center; gap: 4px; width: 112px; height: 15px; box-sizing: border-box; margin-left: auto; padding: 0 5px; border: 1px solid {{rule}}; border-radius: 4px; background: {{field}}; color: {{text2}}; font-size: 8px">Search all projects<span style="margin-left: auto">⇧⌘A</span></span>
</div>
<div style="display: flex; flex: 1; min-height: 0">
<div style="width: 112px; flex: none; display: flex; flex-direction: column; gap: 2px; padding: 8px 6px; box-sizing: border-box; border-right: 1px solid {{rule}}; background: {{pane}}">
<span style="font-weight: 600; padding: 0 4px">{{project}}</span>
<span style="padding: 4px 4px 0; font-size: 7px; font-weight: 600; letter-spacing: 0.06em; color: {{needs}}">NEEDS YOU · 1</span>
<span style="display: flex; align-items: center; gap: 4px; height: 16px; padding: 0 4px; border-radius: 4px; background: {{selected}}"><svg width="6" height="6" viewBox="0 0 10 10" aria-hidden="true"><circle cx="5" cy="5" r="5" fill="{{needs}}"></circle></svg>Refund rules</span>
<span style="padding: 4px 4px 0; font-size: 7px; font-weight: 600; letter-spacing: 0.06em; color: {{text2}}">WORKING · 1</span>
<span style="display: flex; align-items: center; gap: 4px; height: 16px; padding: 0 4px; border-radius: 4px; background: {{activeTint}}"><svg width="6" height="6" viewBox="0 0 10 10" aria-hidden="true"><circle cx="5" cy="5" r="4" fill="none" stroke="{{text}}" stroke-width="1.5"></circle></svg>Policy diff</span>
<span style="padding: 4px 4px 0; font-size: 7px; font-weight: 600; letter-spacing: 0.06em; color: {{text2}}">IDLE · 1</span>
<span style="display: flex; align-items: center; gap: 4px; height: 16px; padding: 0 4px; color: {{text2}}"><svg width="6" height="6" viewBox="0 0 10 10" aria-hidden="true"><path d="M2 5h6" stroke="{{text2}}" stroke-width="1.6" stroke-linecap="round"></path></svg>Ops notes</span>
<span style="margin-top: auto; border-top: 2px solid {{rule}}; padding: 4px 4px 0; font-size: 7px; font-weight: 600; letter-spacing: 0.06em; color: {{text2}}">FILES</span>
<span style="height: 5px; width: 70px; margin: 3px 4px; border-radius: 2px; background: {{placeholder}}"></span>
<span style="height: 5px; width: 54px; margin: 3px 4px; border-radius: 2px; background: {{placeholder}}"></span>
</div>
<div style="flex: 1; min-width: 0; display: flex; flex-direction: column; background: {{chatGround}}">
<div style="display: flex; align-items: center; gap: 8px; height: 18px; flex: none; padding: 0 8px; border-bottom: 1px solid {{rule}}; background: {{pane}}; font-size: 8px"><span style="font-weight: 600">Refund rules</span><span style="color: {{text2}}">Policy diff</span><span style="color: {{text2}}">+</span></div>
<div style="display: flex; flex-direction: column; gap: 6px; padding: 8px 10px; font-size: 9px; line-height: 13px">
<span style="align-self: flex-end; padding: 3px 7px; border-radius: 7px; background: {{chatYou}}">Run the refund tests</span>
<span>Running the suite now.</span>
<span style="display: flex; flex-direction: column; gap: 1px; padding: 4px 6px; border: 1px solid {{rule}}; border-radius: 4px; background: {{toolOutput}}; font-family: 'SF Mono', ui-monospace, monospace; font-size: 8px; line-height: 11px"><span style="color: {{text2}}">Bash · npm test</span><span>41 passed, 0 failed</span></span>
<span>All 41 pass. The new rule is covered.</span>
<span style="color: {{text2}}; font-size: 8px">Worked for 12s</span>
</div>
</div>
<div style="width: 130px; flex: none; display: flex; flex-direction: column; border-left: 1px solid {{rule}}; background: {{pane}}">
<div style="display: flex; align-items: center; gap: 8px; height: 18px; flex: none; padding: 0 8px; border-bottom: 1px solid {{rule}}; font-size: 8px"><span style="font-weight: 600">rules.md</span><span style="color: {{text2}}">Browser</span></div>
<div style="flex: 1; display: flex; flex-direction: column; gap: 6px; margin: 6px; padding: 8px; border: 1px solid {{rule}}; border-radius: 4px; background: {{page}}">
<span style="font-weight: 600">rules.md</span>
<span style="height: 5px; width: 92px; border-radius: 2px; background: {{placeholder}}"></span>
<span style="height: 5px; width: 76px; border-radius: 2px; background: {{placeholder}}"></span>
<span style="height: 5px; width: 86px; border-radius: 2px; background: {{placeholder}}"></span>
<span style="height: 5px; width: 54px; border-radius: 2px; background: {{placeholder}}"></span>
</div>
</div>
</div>
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{"mode":{"editor":"enum","options":["light","dark"],"default":"light"},"colour":{"editor":"enum","options":IDS,"default":"blue"},"project":{"editor":"text","default":"refunds"},"$preview":{"width":520,"height":325}}'>
class Component extends DCLogic {
  renderVals() {
    const p = this.props;
    const base = {
      light: { ground: '#F3F4F6', pane: '#FFFFFF', chatGround: '#F3F4F6', toolOutput: '#F8F9FA', selected: '#E9ECEF', rule: '#C9CDD3', controlEdge: '#8B939C', text: '#1F2328', text2: '#5B636D', needs: '#C2410C', placeholder: '#D5D9DE', activeTint: '#E8F0FA', chatYou: '#DCE6F7' },
      dark: { ground: '#131518', pane: '#181A1E', chatGround: '#0C0D10', toolOutput: '#131518', selected: '#262A30', rule: '#2B2F36', controlEdge: '#6E7681', text: '#E6E8EB', text2: '#9AA1AB', needs: '#F97316', placeholder: '#2B2F36', activeTint: '#18222E', chatYou: '#22344F' }
    };
    // [ground, pane, chatGround, toolOutputFill, swatch], from palette/window_palette.py (Q-441)
    const colours = COLMAP;
    const mode = p.mode === 'dark' ? 'dark' : 'light';
    const b = base[mode];
    const c = colours[mode][p.colour ?? 'blue'] ?? null;
    return {
      ground: c ? c[0] : b.ground, pane: c ? c[1] : b.pane, chatGround: c ? c[2] : b.chatGround, toolOutput: c ? c[3] : b.toolOutput,
      swatch: c ? c[4] : b.pane, showSwatch: true,
      page: b.pane, field: b.pane, chipBg: c ? b.pane : 'transparent', crumb: c ? b.text : b.text2, edgeLine: b.controlEdge,
      selected: b.selected, rule: b.rule, controlEdge: b.controlEdge, text: b.text, text2: b.text2, needs: b.needs,
      placeholder: b.placeholder, activeTint: b.activeTint, chatYou: b.chatYou,
      project: p.project ?? 'refunds'
    };
  }
}
</script>
</body>
</html>
'''
comp = comp.replace("IDS", json.dumps(ids)).replace("COLMAP", json.dumps(colmap))
open(OUT + "/WinColour12.dc.html", "w").write(comp)

# ---------- board ----------
projects = ["checkout-redesign","vendor-review","pricing","ops-notes","refunds","onboarding","billing","search","mobile-app","data-export","support-bot","launch-plan"]
pos = {cid: i+1 for i, cid in enumerate(order)}
def f2(x): return "%.2f" % x
rows = []
for i, c in enumerate(cols):
    L, D = c["light"], c["dark"]
    rows.append({
      "id": c["id"], "name": c["name"], "project": projects[i],
      "hue": "h %g · %s" % (c["hue"], c["step"]), "order": "#%d" % pos[c["id"]],
      "lg": L["ground"], "lp": L["pane"], "ls": L["swatch"], "dg": D["ground"], "dp": D["pane"], "ds": D["swatch"],
      "lightAll": " · ".join(L[k] for k in ("ground","pane","chatGround","toolOutputFill","swatch")),
      "darkAll": " · ".join(D[k] for k in ("ground","pane","chatGround","toolOutputFill","swatch")),
      "lightCr": "%s · %s · %s" % (f2(L["textOnGround"]), f2(L["minText2"]), f2(L["needsOnPane"])),
      "darkCr": "%s · %s · %s" % (f2(D["textOnGround"]), f2(D["minText2"]), f2(D["needsOnPane"])),
    })
seq = [{"n": str(k+1), "name": byid[cid]["name"], "sw": byid[cid]["light"]["swatch"], "swd": byid[cid]["dark"]["swatch"]} for k, cid in enumerate(order)]
rl = R["roles"]
recipe = []
for role in ("ground","pane","chatGround","toolOutputFill"):
    recipe.append({"role": role,
      "la": "L %.3f  C ≤ %.3f" % tuple(rl["light"][role][0]), "lb": "L %.3f  C ≤ %.3f" % tuple(rl["light"][role][1]),
      "da": "L %.3f  C ≤ %.3f" % tuple(rl["dark"][role][0]), "db": "L %.3f  C ≤ %.3f" % tuple(rl["dark"][role][1])})
minT = min(min(c[m]["textOnGround"] for m in ("light","dark")) for c in cols)
minT2 = min(min(c[m]["minText2"] for m in ("light","dark")) for c in cols)
minNP = min(c["light"]["needsOnPane"] for c in cols)
DI = P["distance"]
data = json.dumps({"cols": rows, "seq": seq, "recipe": recipe}, ensure_ascii=False)

H = 2060
LBL = 'font-size: 11px; line-height: 16px; font-weight: 600; letter-spacing: 0.06em; color: #5B636D'
board = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Twelve window colours</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<style>
body{{margin:0}}
</style>
</helmet>
<div style="width: 1720px; height: {H}px; box-sizing: border-box; padding: 40px 48px; display: flex; flex-direction: column; gap: 20px; background: #F3F4F6; color: #1F2328; font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif; font-size: 13px; line-height: 20px">
<div style="display: flex; flex-direction: column; gap: 4px">
<span style="{LBL}">DECISION 4a′ · Q-441 · ROUND 2, DIRECTION C OF 4a″ · SUPERSEDES 4a · ENH-319 · DL-312</span>
<span style="font-size: 22px; line-height: 28px; font-weight: 600">Twelve window colours, light and dark [P]</span>
<span style="color: #5B636D; white-space: normal; max-width: 1480px">Geoff: “colors are meant to help rapidly distinguish between disparate windows”, and on 4a″ “c is good; the order should be all light, then all dark”. Six hues spread round the wheel, leaving out only the needs-you orange (h 22–64): Coral, Ochre, Green, Teal, Blue and Purple, each in a light and a deep step. The toolbar takes the colour at real chroma and its text moves from text2 to text. The sidebar, tab strips, right pane, chat and tool output take a pale tint of the same hue. The console, cards, fields, the document\'s page, the selected row, text and needs-you never change, and the needs-you chip keeps a solid fill on every coloured toolbar. Closest toolbars: {DI['light']['closest']} light ({DI['light']['pair'][0]}, {DI['light']['pair'][1]}), {DI['dark']['closest']} dark; {DI['light']['apart15']}% of pairs in light and {DI['dark']['apart15']}% in dark are 15 or more apart (OKLab ΔE ×100). On the first 4a′, no pair was.</span>
</div>

<span style="{LBL}">THE TWELVE: EACH HUE IN ITS LIGHT AND DEEP STEP; LIGHT APPEARANCE ABOVE, DARK BELOW [P]</span>
<div style="display: grid; grid-template-columns: repeat(12, minmax(0, 1fr)); gap: 12px">
<sc-for list="{{{{cols}}}}" as="c" hint-placeholder-count="12">
<div style="display: flex; flex-direction: column; gap: 6px">
<div style="display: flex; flex-direction: column; border: 1px solid #C9CDD3; border-radius: 6px; overflow: hidden">
<div style="height: 46px; background: {{{{c.lg}}}}"></div>
<div style="height: 18px; background: {{{{c.lp}}}}; border-top: 1px solid #C9CDD3"></div>
<div style="height: 46px; background: {{{{c.dg}}}}"></div>
<div style="height: 18px; background: {{{{c.dp}}}}; border-top: 1px solid #2B2F36"></div>
</div>
<span style="display: flex; justify-content: space-between; align-items: baseline"><span style="font-weight: 600">{{{{c.name}}}}</span><span style="color: #5B636D; font-size: 12px">{{{{c.order}}}}</span></span>
<span style="color: #5B636D; font-size: 12px; line-height: 16px">{{{{c.hue}}}}</span>
</div>
</sc-for>
</div>

<span style="{LBL}">THE ORDER NEW WINDOWS GET THEM IN [P]</span>
<div style="display: flex; flex-direction: column; gap: 8px">
<div style="display: flex; flex-wrap: wrap; align-items: center; gap: 4px">
<span style="display: flex; align-items: center; gap: 6px; height: 26px; padding: 0 10px; border: 1px solid #C9CDD3; border-radius: 13px; background: #FFFFFF"><span style="width: 12px; height: 12px; border-radius: 50%; border: 1px solid #8B939C; background: #FFFFFF"></span><span style="color: #5B636D">First window</span><span style="font-weight: 600">None</span></span>
<sc-for list="{{{{seq}}}}" as="s" hint-placeholder-count="12">
<span style="display: flex; align-items: center; gap: 6px"><svg width="10" height="10" viewBox="0 0 10 10" aria-hidden="true"><path d="M3 1.5 7 5 3 8.5" fill="none" stroke="#8B939C" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"></path></svg><span style="display: flex; align-items: center; gap: 5px; height: 26px; padding: 0 8px; border: 1px solid #C9CDD3; border-radius: 13px; background: #FFFFFF; font-size: 12px"><span style="color: #5B636D">{{{{s.n}}}}</span><span style="width: 12px; height: 12px; border-radius: 50%; border: 1px solid #8B939C; background: {{{{s.sw}}}}"></span><span style="font-weight: 600">{{{{s.name}}}}</span></span></span>
</sc-for>
</div>
<span style="color: #5B636D; white-space: normal; max-width: 1480px">A new window takes the first colour in this list that no open window has (DL-312): the six light steps first, then the six deep ones (Geoff), so the first six windows open in six different hues. Within each run the hues jump across the wheel, so consecutive windows are never neighbours. Blue comes first, as Sky did on 4a.</span>
</div>

<span style="{LBL}">LIGHT [P]</span>
<div style="display: grid; grid-template-columns: repeat(6, 260px); gap: 14px 12px">
<sc-for list="{{{{cols}}}}" as="c" hint-placeholder-count="12">
<div style="display: flex; flex-direction: column; gap: 4px">
<div style="width: 260px; height: 162px; overflow: hidden"><div style="transform: scale(0.5); transform-origin: top left; width: 520px; height: 325px"><dc-import name="WinColour12" mode="light" colour="{{{{c.id}}}}" project="{{{{c.project}}}}" hint-size="520px,325px"></dc-import></div></div>
<span style="display: flex; gap: 6px; align-items: baseline"><span style="font-weight: 600">{{{{c.name}}}}</span><span style="color: #5B636D; font-size: 12px">{{{{c.lg}}}}</span></span>
</div>
</sc-for>
</div>

<span style="{LBL}">DARK [P]</span>
<div style="display: grid; grid-template-columns: repeat(6, 260px); gap: 14px 12px">
<sc-for list="{{{{cols}}}}" as="c" hint-placeholder-count="12">
<div style="display: flex; flex-direction: column; gap: 4px">
<div style="width: 260px; height: 162px; overflow: hidden"><div style="transform: scale(0.5); transform-origin: top left; width: 520px; height: 325px"><dc-import name="WinColour12" mode="dark" colour="{{{{c.id}}}}" project="{{{{c.project}}}}" hint-size="520px,325px"></dc-import></div></div>
<span style="display: flex; gap: 6px; align-items: baseline"><span style="font-weight: 600">{{{{c.name}}}}</span><span style="color: #5B636D; font-size: 12px">{{{{c.dg}}}}</span></span>
</div>
</sc-for>
</div>

<div style="display: flex; flex-direction: column; border: 1px solid #C9CDD3; border-radius: 6px; background: #FFFFFF; font-size: 12px; line-height: 18px">
<div style="display: grid; grid-template-columns: 96px 84px 1fr 290px 1fr 230px; gap: 12px; padding: 6px 12px; border-bottom: 1px solid #C9CDD3; font-weight: 600; color: #5B636D"><span>Colour</span><span>Hue · step</span><span>Light ground · pane · chat · tool · swatch</span><span>Light: text on toolbar · text2 · needs-you on pane</span><span>Dark ground · pane · chat · tool · swatch</span><span>Dark: toolbar text · text2 · needs-you</span></div>
<sc-for list="{{{{cols}}}}" as="c" hint-placeholder-count="12">
<div style="display: grid; grid-template-columns: 96px 84px 1fr 290px 1fr 230px; gap: 12px; padding: 3px 12px; border-top: 1px solid #E9ECEF"><span style="font-weight: 600">{{{{c.name}}}}</span><span style="color: #5B636D">{{{{c.hue}}}}</span><span style="font-family: 'SF Mono', ui-monospace, monospace; font-size: 11px">{{{{c.lightAll}}}}</span><span>{{{{c.lightCr}}}}</span><span style="font-family: 'SF Mono', ui-monospace, monospace; font-size: 11px">{{{{c.darkAll}}}}</span><span>{{{{c.darkCr}}}}</span></div>
</sc-for>
<span style="padding: 6px 12px; border-top: 1px solid #C9CDD3; color: #5B636D; white-space: normal">The swatch is the toolbar colour. Text on a coloured toolbar is text (#1F2328 light, #E6E8EB dark), {minT:.2f}:1 or more; text2 (#5B636D, #9AA1AB) appears only on the pane, chat and tool output tints, where it is {minT2:.2f}:1 or more. Needs-you on the pane tint, where its section label sits, is {minNP:.2f}:1 or more in light. Proposed tokens: windowColour.&lt;name&gt;.light|dark.ground|pane|chatGround|toolOutputFill, and one rule: on a coloured toolbar, text2 is drawn as text.</span>
</div>

<div style="display: flex; gap: 20px">
<div style="flex: 3; display: flex; flex-direction: column; border: 1px solid #C9CDD3; border-radius: 6px; background: #FFFFFF; font-size: 12px; line-height: 18px">
<div style="display: grid; grid-template-columns: 130px repeat(4, minmax(0, 1fr)); gap: 12px; padding: 6px 12px; border-bottom: 1px solid #C9CDD3; font-weight: 600; color: #5B636D"><span>OKLCH recipe</span><span>Light appearance, light step</span><span>Light appearance, deep step</span><span>Dark appearance, light step</span><span>Dark appearance, deep step</span></div>
<sc-for list="{{{{recipe}}}}" as="r" hint-placeholder-count="5">
<div style="display: grid; grid-template-columns: 130px repeat(4, minmax(0, 1fr)); gap: 12px; padding: 3px 12px; border-top: 1px solid #E9ECEF; font-family: 'SF Mono', ui-monospace, monospace; font-size: 11px"><span style="font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif; font-size: 12px; font-weight: 600">{{{{r.role}}}}</span><span>{{{{r.la}}}}</span><span>{{{{r.lb}}}}</span><span>{{{{r.da}}}}</span><span>{{{{r.db}}}}</span></div>
</sc-for>
</div>
<div style="flex: 2; display: flex; flex-direction: column; gap: 6px; padding: 10px 14px; border: 1px solid #C9CDD3; border-radius: 6px; background: #FFFFFF; font-size: 12px; line-height: 18px; white-space: normal">
<span style="font-weight: 600">How it is derived, and how to add more</span>
<span>Hues 20° (Coral), 75° (Ochre), 135° (Green), 185° (Teal), 250° (Blue), 315° (Purple). They were picked by a search over every in-sRGB colour for the largest smallest distance between any two toolbars. Each surface takes its step\'s L, and chroma up to the cap or 92% of what sRGB holds at that L and hue, whichever is less.</span>
<span>Twelve can\'t all be 15 apart under any design (the best possible worst pair is about 8), so the project name in each toolbar is the second cue. To add colours, add a third step between light and deep before adding hues, then re-run docs/design/multi-window-studies/palette/window_palette.py.</span>
</div>
</div>
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":1720,"height":{H}}}}}'>
class Component extends DCLogic {{
  renderVals() {{
    return DATA;
  }}
}}
</script>
</body>
</html>
'''
open(OUT + "/ColourTwelve.dc.html", "w").write(board.replace("DATA", data))
print("ok", minT, minT2, minNP)
