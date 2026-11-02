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
<span style="color: {{text2}}">All projects</span>
<svg width="5" height="7" viewBox="0 0 8 10" aria-hidden="true"><path d="M2 1.5 6 5 2 8.5" fill="none" stroke="{{text2}}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"></path></svg>
<span style="font-weight: 600">{{project}}</span>
<sc-if value="{{showSwatch}}" hint-placeholder-val="{{ true }}"><span style="display: flex; align-items: center; gap: 2px; padding: 1px 3px; border-radius: 4px"><span style="width: 8px; height: 8px; border-radius: 50%; border: 1px solid {{controlEdge}}; background: {{swatch}}"></span><svg width="5" height="4" viewBox="0 0 10 6" aria-hidden="true"><path d="M1 1l4 4 4-4" fill="none" stroke="{{text2}}" stroke-width="1.5" stroke-linecap="round"></path></svg></span></sc-if>
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
<script type="text/x-dc" data-dc-script data-props='{"mode":{"editor":"enum","options":["light","dark"],"default":"light"},"colour":{"editor":"enum","options":IDS,"default":"sky"},"project":{"editor":"text","default":"refunds"},"$preview":{"width":520,"height":325}}'>
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
    const c = colours[mode][p.colour ?? 'sky'] ?? null;
    return {
      ground: c ? c[0] : b.ground, pane: c ? c[1] : b.pane, chatGround: c ? c[2] : b.chatGround, toolOutput: c ? c[3] : b.toolOutput,
      swatch: c ? c[4] : b.pane, showSwatch: true,
      page: b.pane, field: b.pane, chipBg: c && mode === 'light' ? b.pane : 'transparent', edgeLine: b.controlEdge,
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
      "hue": "h %g · %s" % (c["hue"], c["tier"]), "order": "#%d" % pos[c["id"]],
      "lg": L["ground"], "lp": L["pane"], "ls": L["swatch"], "dg": D["ground"], "dp": D["pane"], "ds": D["swatch"],
      "lightAll": " · ".join(L[k] for k in ("ground","pane","chatGround","toolOutputFill","swatch")),
      "darkAll": " · ".join(D[k] for k in ("ground","pane","chatGround","toolOutputFill","swatch")),
      "lightCr": "%s / %s · %s (%s → chip on white)" % (f2(L["minText"]), f2(L["minText2"]), f2(L["needsOnPane"]), f2(L["needsOnGround"])),
      "darkCr": "%s / %s · %s (%s)" % (f2(D["minText"]), f2(D["minText2"]), f2(D["needsOnPane"]), f2(D["needsOnGround"])),
    })
seq = [{"n": str(k+1), "name": byid[cid]["name"], "sw": byid[cid]["light"]["swatch"], "swd": byid[cid]["dark"]["swatch"]} for k, cid in enumerate(order)]
rl = R["roles"]
recipe = []
for role in ("ground","pane","chatGround","toolOutputFill","swatch"):
    recipe.append({"role": role,
      "la": "L %.3f  C %.3f" % tuple(rl["light"][role][0]), "lb": "L %.3f  C %.3f" % tuple(rl["light"][role][1]),
      "da": "L %.3f  C %.3f" % tuple(rl["dark"][role][0]), "db": "L %.3f  C %.3f" % tuple(rl["dark"][role][1])})
minT = min(min(c[m]["minText"] for m in ("light","dark")) for c in cols)
minT2 = min(min(c[m]["minText2"] for m in ("light","dark")) for c in cols)
minNP = min(c["light"]["needsOnPane"] for c in cols)
nh = P["needsYouHue"]
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
<span style="{LBL}">DECISION 4a′ · Q-441 · SUPERSEDES 4a · ENH-319 · DL-312</span>
<span style="font-size: 22px; line-height: 28px; font-weight: 600">Twelve window colours, light and dark [P]</span>
<span style="color: #5B636D; white-space: normal; max-width: 1480px">Geoff: “we will need more colors; at least 12 … I care less about which specific colors and more that they are cohesive and feel consistent with one another”. One recipe, twelve hues: every colour has the same OKLCH lightness and chroma for each surface, and the hues sit 22.5° apart on an arc from 92° to 339.5° that skips orange and red (needs-you is at {round(nh[0])}° in light, {round(nh[1])}° in dark). Neighbouring hues alternate two tiers, A lighter and softer, B deeper and richer, so neighbours differ in lightness and chroma as well as hue. Same coverage as 4a: ground (the toolbar), pane (sidebar, tab strips, right pane), chatGround and toolOutputFill take the colour; the console, cards, fields, the document's page, the selected row, text and needs-you never change. None stays the first window's colour.</span>
</div>

<span style="{LBL}">THE TWELVE, IN HUE ORDER: LIGHT ABOVE, DARK BELOW [P]</span>
<div style="display: grid; grid-template-columns: repeat(12, minmax(0, 1fr)); gap: 12px">
<sc-for list="{{{{cols}}}}" as="c" hint-placeholder-count="12">
<div style="display: flex; flex-direction: column; gap: 6px">
<div style="display: flex; flex-direction: column; border: 1px solid #C9CDD3; border-radius: 6px; overflow: hidden">
<div style="display: flex; align-items: center; justify-content: center; height: 46px; background: {{{{c.lg}}}}"><span style="width: 22px; height: 22px; border-radius: 50%; border: 1px solid #8B939C; background: {{{{c.ls}}}}"></span></div>
<div style="height: 18px; background: {{{{c.lp}}}}; border-top: 1px solid #C9CDD3"></div>
<div style="display: flex; align-items: center; justify-content: center; height: 46px; background: {{{{c.dg}}}}"><span style="width: 22px; height: 22px; border-radius: 50%; border: 1px solid #6E7681; background: {{{{c.ds}}}}"></span></div>
<div style="height: 18px; background: {{{{c.dp}}}}; border-top: 1px solid #2B2F36"></div>
</div>
<span style="display: flex; justify-content: space-between; align-items: baseline"><span style="font-weight: 600">{{{{c.name}}}}</span><span style="color: #5B636D; font-size: 12px">{{{{c.order}}}}</span></span>
<span style="color: #5B636D; font-size: 12px; line-height: 16px">{{{{c.hue}}}}</span>
</div>
</sc-for>
</div>

<span style="{LBL}">THE ORDER NEW WINDOWS GET THEM IN [P]</span>
<div style="display: flex; flex-direction: column; gap: 8px">
<div style="display: flex; flex-wrap: wrap; align-items: center; gap: 6px">
<span style="display: flex; align-items: center; gap: 6px; height: 26px; padding: 0 10px; border: 1px solid #C9CDD3; border-radius: 13px; background: #FFFFFF"><span style="width: 12px; height: 12px; border-radius: 50%; border: 1px solid #8B939C; background: #FFFFFF"></span><span style="color: #5B636D">First window</span><span style="font-weight: 600">None</span></span>
<sc-for list="{{{{seq}}}}" as="s" hint-placeholder-count="12">
<span style="display: flex; align-items: center; gap: 6px"><svg width="10" height="10" viewBox="0 0 10 10" aria-hidden="true"><path d="M3 1.5 7 5 3 8.5" fill="none" stroke="#8B939C" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"></path></svg><span style="display: flex; align-items: center; gap: 6px; height: 26px; padding: 0 10px; border: 1px solid #C9CDD3; border-radius: 13px; background: #FFFFFF"><span style="color: #5B636D; font-size: 12px">{{{{s.n}}}}</span><span style="width: 12px; height: 12px; border-radius: 50%; border: 1px solid #8B939C; background: {{{{s.sw}}}}"></span><span style="font-weight: 600">{{{{s.name}}}}</span></span></span>
</sc-for>
</div>
<span style="color: #5B636D; white-space: normal; max-width: 1480px">A new window takes the first colour in this list that no open window has (DL-312), so two open windows never share one until all twelve are in use; then it goes round again. Each step is five places round the hue order, 112.5° on, and changes tier, so the colours a person meets one after another are always far apart. Sky comes first, as on 4a.</span>
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
<div style="display: grid; grid-template-columns: 96px 84px 1fr 290px 1fr 180px; gap: 12px; padding: 6px 12px; border-bottom: 1px solid #C9CDD3; font-weight: 600; color: #5B636D"><span>Colour</span><span>Hue · tier</span><span>Light ground · pane · chat · tool · swatch</span><span>Light: text / text2 · needs-you on pane (ground)</span><span>Dark ground · pane · chat · tool · swatch</span><span>Dark: same</span></div>
<sc-for list="{{{{cols}}}}" as="c" hint-placeholder-count="12">
<div style="display: grid; grid-template-columns: 96px 84px 1fr 290px 1fr 180px; gap: 12px; padding: 3px 12px; border-top: 1px solid #E9ECEF"><span style="font-weight: 600">{{{{c.name}}}}</span><span style="color: #5B636D">{{{{c.hue}}}}</span><span style="font-family: 'SF Mono', ui-monospace, monospace; font-size: 11px">{{{{c.lightAll}}}}</span><span>{{{{c.lightCr}}}}</span><span style="font-family: 'SF Mono', ui-monospace, monospace; font-size: 11px">{{{{c.darkAll}}}}</span><span>{{{{c.darkCr}}}}</span></div>
</sc-for>
<span style="padding: 6px 12px; border-top: 1px solid #C9CDD3; color: #5B636D; white-space: normal">Text and text2 figures are the lowest across all four coloured surfaces. Text (#1F2328 light, #E6E8EB dark) is {minT:.2f}:1 or more and text2 (#5B636D, #9AA1AB) {minT2:.2f}:1 or more on every one, light and dark. Needs-you on the pane shade, where its section label sits, is {minNP:.2f}:1 or more in light. On a light coloured toolbar it is under 4.5:1, so the needs-you chip keeps its white fill there (F-169), as on 4a. In dark every value passes. Proposed tokens: windowColour.&lt;name&gt;.light|dark.ground|pane|chatGround|toolOutputFill|swatch.</span>
</div>

<div style="display: flex; gap: 20px">
<div style="flex: 3; display: flex; flex-direction: column; border: 1px solid #C9CDD3; border-radius: 6px; background: #FFFFFF; font-size: 12px; line-height: 18px">
<div style="display: grid; grid-template-columns: 130px repeat(4, minmax(0, 1fr)); gap: 12px; padding: 6px 12px; border-bottom: 1px solid #C9CDD3; font-weight: 600; color: #5B636D"><span>OKLCH recipe</span><span>Light, tier A</span><span>Light, tier B</span><span>Dark, tier A</span><span>Dark, tier B</span></div>
<sc-for list="{{{{recipe}}}}" as="r" hint-placeholder-count="5">
<div style="display: grid; grid-template-columns: 130px repeat(4, minmax(0, 1fr)); gap: 12px; padding: 3px 12px; border-top: 1px solid #E9ECEF; font-family: 'SF Mono', ui-monospace, monospace; font-size: 11px"><span style="font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif; font-size: 12px; font-weight: 600">{{{{r.role}}}}</span><span>{{{{r.la}}}}</span><span>{{{{r.lb}}}}</span><span>{{{{r.da}}}}</span><span>{{{{r.db}}}}</span></div>
</sc-for>
</div>
<div style="flex: 2; display: flex; flex-direction: column; gap: 6px; padding: 10px 14px; border: 1px solid #C9CDD3; border-radius: 6px; background: #FFFFFF; font-size: 12px; line-height: 18px; white-space: normal">
<span style="font-weight: 600">How it is derived, and how to add more</span>
<span>Hue of colour i = 92° + 22.5° × i, for i = 0 to 11. Tier = A when i is even, B when odd. Each surface takes the tier's L and C at that hue. Every value is inside sRGB, and the chroma is capped by the narrowest hue, teal.</span>
<span>To add more, keep the recipe and put new hues halfway between the old ones (92° + 11.25° + 22.5° × i), giving 24 on the same arc, and give them a third tier between A and B. Then re-run the contrast check: docs/design/multi-window-studies/palette/window_palette.py.</span>
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
