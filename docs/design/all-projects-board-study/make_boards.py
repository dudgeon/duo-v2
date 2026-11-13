#!/usr/bin/env python3
"""Writes the All projects board study's canvas boards (canvas/project/*.dc.html) from one set of
sample data, so every board draws the same tile. Sample data only (the home-evolution study's names),
never anyone's real projects. Run: python3 make_boards.py <out-dir>"""
import html, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "canvas", "project")
CSS = open(os.path.join(HERE, "style.css")).read()
CANVAS = "https://claude.ai/artifact/7zdNWzWyfrCPDgGtBot5M4"
E = html.escape

# ---- sample data -------------------------------------------------------------------------------
# glyphs: dot needs you, ring working, dash idle/at prompt, dia to review
P = {
 "home": dict(name="home", star=True, topic="", path="~/work/home", goal="Triage, dispatch, status, personal ops",
              health="Home · 21 sessions", sessions=[("dot","Morning triage","1h"),("bub","Weekly status draft","at prompt",True),
              ("bub","Inbox sweep","2h")], more=18, act="pinned"),
 "checkout-redesign": dict(topic="payments", path="~/work/home/payments/checkout-redesign", goal="Cut guest-checkout abandonment 15% by Q1",
              health="On track · Exec review Oct 14", sessions=[("dot","PRD v2 edits","4m"),("bub","Teardown research","working",True)], act="pinned"),
 "onboarding-v3": dict(topic="growth", path="~/work/home/growth/onboarding-v3", goal="Lift day-7 activation to 40%",
              health="On track · Copy freeze Oct 6", sessions=[("dot","Copy review pass 2","12m"),("dia","Funnel SQL","")], act="pinned"),
 "q4-planning": dict(topic="", path="~/work/home/q4-planning", goal="Q4 plan signed off by staff", health="At risk · Draft due Oct 9",
              sessions=[("bub","Roadmap narrative","working",True)], act="now"),
 "pricing-experiment-q4": dict(topic="growth", path="~/work/home/growth/pricing-experiment-q4", goal="Decide Q4 pricing test",
              health="On track · Readout Oct 20", sessions=[("dia","Results readout","")], act="now"),
 "board-deck": dict(topic="~/Desktop", outside=True, path="~/Desktop/board-deck", goal=None, health="No project file",
              sessions=[("dot","Slide 7 numbers","9m")], act="now", noproj=True),
 "site": dict(topic="~/repos", outside=True, path="~/repos/site", goal=None, health="Has CLAUDE.md · no project file",
              sessions=[("bub","Fix footer links","working",True)], act="now", noproj=True),
 "vendor-review": dict(topic="", path="~/work/home/vendor-review", goal="Pick a fraud-scoring vendor", health="On track",
              sessions=[], last="3h", act="today"),
 "weekly-metrics": dict(topic="", path="~/work/home/weekly-metrics", goal="One page of numbers every Monday", health="On track · Next Mon",
              sessions=[], last="5h", act="today"),
 "api-deprecations": dict(topic="", path="~/work/home/api-deprecations", goal="Comms plan for v1 API sunset", health="Off track",
              sessions=[], last="4d", act="week"),
 "payments-api": dict(topic="~/repos", outside=True, path="~/repos/payments-api", goal=None, health="Has CLAUDE.md · no project file",
              sessions=[], last="2d", past=3, act="week", noproj=True),
 "research-notes": dict(topic="~/Documents", outside=True, path="~/Documents/research-notes", goal=None, health="No project file",
              sessions=[], last="6d", past=4, act="week", noproj=True),
 "refunds-api-spec": dict(topic="payments", path="~/work/home/payments/refunds-api-spec", goal="Ship refunds API spec to eng by Oct 10",
              health="At risk · Spec review Oct 8", sessions=[], last="2w", act="earlier"),
 "scripts": dict(topic="~/repos", outside=True, path="~/repos/scripts", goal=None, health="No project file", sessions=[], last="3w", past=1,
              act="earlier", noproj=True),
}
for k, v in P.items():
    v.setdefault("name", k)
    v.setdefault("star", False)
    v.setdefault("outside", False)
    v.setdefault("noproj", False)

def glyph(g):
    return f'<span class="g"><i class="{g}"></i></span>'

def srow(s):
    g, title, wait = s[0], s[1], s[2]
    cls = "sr open" if len(s) > 3 and s[3] else "sr"
    return f'<div class="{cls}">{glyph(g)}<span>{E(title)}</span><span class="w">{E(wait)}</span></div>'

def ns_row(p, mode="row", hov=False, key=None, label="New session"):
    """The tile's New session control. mode row: the footer row (T1); corner: a + in the name row (T2)."""
    cls = "ns hov" if hov else "ns"
    k = f'<span class="k">{key}</span>' if key else "<span></span>"
    return (f'<button type="button" class="{cls}" aria-label="New session in {E(p["name"])}" '
            f'title="New session in {E(p["name"])} · {E(p["path"])}"><b>+</b><span>{label}</span>{k}</button>')

def tile(key, *, path=True, ns="row", hov=False, focus=False, nskey=None, maxrows=3, extra="", width=None, nslabel="New session"):
    p = P[key]
    cls = "tile" + (" home" if p["star"] else "") + (" foc" if focus else "")
    st = f' style="width:{width}px"' if width else ""
    star = '<svg width="11" height="11" viewBox="0 0 12 12" aria-hidden="true" style="margin-right:4px;vertical-align:-1px"><path d="M6 .8l1.6 3.4 3.7.4-2.8 2.5.8 3.7L6 9 2.7 10.8l.8-3.7L.7 4.6l3.7-.4z" fill="#1F2328"></path></svg>' if p["star"] else ""
    corner = ""
    if ns == "corner":
        corner = ('<button type="button" aria-label="New session in ' + E(p["name"]) + '" style="margin-left:auto;width:20px;height:20px;border:1px solid '
                  + ('#8B939C' if hov else 'transparent') + ';border-radius:5px;background:' + ('#E9ECEF' if hov else 'none')
                  + ';color:#5B636D;font-size:15px;line-height:15px;padding:0;font-family:inherit">+</button>')
    out = [f'<div class="{cls}"{st}>',
           f'<div style="display:flex;align-items:center;gap:4px;min-width:0"><span class="tn">{star}{E(p["name"])}</span>{corner}</div>']
    if path:
        out.append(f'<div class="tp">{E(p["path"])}</div>')
    if p["goal"]:
        out.append(f'<div class="tg">{E(p["goal"])}</div>')
    out.append(f'<div class="th">{E(p["health"])}</div>')
    if p["sessions"]:
        out.append('<div class="ss">' + "".join(srow(s) for s in p["sessions"][:maxrows]) + "</div>")
        if p.get("more"):
            out.append(f'<div class="more">{p["more"]} more ›</div>')
    elif p.get("past"):
        out.append(f'<div class="quiet">{p["past"]} past sessions · {p["last"]}</div>')
    else:
        out.append(f'<div class="quiet">Nothing running · {p.get("last","")}</div>')
    out.append(extra)
    if ns == "row":
        if p["noproj"]:
            out.append('<div class="nsf">' + ns_row(p, hov=hov, key=nskey, label=nslabel)
                       + '<button type="button" class="mk">Make a Project</button></div>')
        else:
            out.append(ns_row(p, hov=hov, key=nskey, label=nslabel))
    elif ns == "none":
        pass
    else:
        out.append('<div style="height:6px"></div>')
    out.append("</div>")
    return "".join(out)

def grid(keys, n, **kw):
    return (f'<div class="grid" style="grid-template-columns:repeat({n},minmax(0,1fr))">' + "".join(tile(k, **kw) for k in keys) + "</div>")

def lab(text, count=None, rule=False, icon=False, extra=""):
    c = f" · {count}" if count is not None else ""
    ic = ('<svg width="12" height="11" viewBox="0 0 12 11" aria-hidden="true"><path d="M.75 1.75h3.6l1.2 1.3h5.7v6.2H.75z" fill="none" stroke="#5B636D" stroke-width="1.2"></path></svg>' if icon else "")
    r = '<span class="rl"></span>' if rule else ""
    return f'<div class="lab">{ic}<span>{E(text)}{c}</span>{r}{extra}</div>'

def toolbar(title="All projects", counts=True, width=None):
    c = ('<span class="cnt ny">● 4 need you</span><span class="cnt">◆ 2 to review</span><span class="cnt">○ 3 working</span><span class="cnt">– 14 idle</span>' if counts else "")
    return (f'<div class="tb"><div class="dots"><i></i><i></i><i></i></div><span class="cnt">▯</span><strong>{E(title)}</strong>{c}'
            f'<span class="srch">Search all projects ⇧⌘A</span><span class="cnt">▯▯</span></div>')

def header(group="Activity", flt="Filter projects", extra=""):
    return (f'<div class="hdr"><span class="seg"><span class="on">Board</span><span>List</span></span>'
            f'<span class="flt">{E(flt)}</span>{extra}<span style="margin-left:auto" class="newp">+ New project</span>'
            f'<span class="mut">Group</span><span class="pop">{E(group)} ⌃</span></div>')

def needs_you():
    return ('<div class="right">' + lab("Needs you", 4) +
      '<div class="card"><div style="display:flex;gap:6px;align-items:center">' + glyph("dot") + '<strong>Morning triage</strong><span class="mut" style="margin-left:auto">1h</span></div><span class="mut">★ home · question</span><div class="q">Send the weekly status as drafted?</div><div><span class="btn">Open Home</span></div></div>'
      '<div class="card"><div style="display:flex;gap:6px;align-items:center">' + glyph("dot") + '<strong>Slide 7 numbers</strong><span class="mut" style="margin-left:auto">9m</span></div><span class="mut">board-deck · permission</span><div class="q">Run python3 chart.py?</div><div><span class="btn">Open project</span></div></div>'
      '<div class="card"><div style="display:flex;gap:6px;align-items:center">' + glyph("dot") + '<strong>PRD v2 edits</strong><span class="mut" style="margin-left:auto">4m</span></div><span class="mut">checkout-redesign · question</span></div>'
      '<div class="card"><div style="display:flex;gap:6px;align-items:center">' + glyph("dot") + '<strong>Copy review pass 2</strong><span class="mut" style="margin-left:auto">12m</span></div><span class="mut">onboarding-v3 · permission</span></div>'
      + lab("Ready for review", 2) +
      '<div class="card"><div style="display:flex;gap:6px;align-items:center">' + glyph("dia") + '<strong>Results readout</strong></div><span class="mut">pricing-experiment-q4</span></div>'
      '</div>')

def ann(x, y, text, w=280):
    return f'<div class="ann" style="left:{x}px;top:{y}px;max-width:{w}px"><span class="pm">P</span> {text}</div>'

def note(x, y, text, w=280):
    """A board note that is not a proposal (context, today's facts)."""
    return f'<div class="ann" style="left:{x}px;top:{y}px;max-width:{w}px;background:#F3F4F6;border-color:#C9CDD3">{text}</div>'

def board(fname, title, w, h, inner):
    doc = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{E(title)}</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<style>
{CSS}
</style>
</helmet>
<div class="root" style="width:{w}px;height:{h}px">
{inner}
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":{w},"height":{h}}}}}'>
class Component extends DCLogic {{
renderVals() {{ return {{}}; }}
}}
</script>
</body>
</html>
'''
    with open(os.path.join(OUT, fname), "w") as f:
        f.write(doc)

def window(mid, w=1440, h=900, right=True):
    return toolbar() + '<div class="body"><div class="mid">' + mid + "</div>" + (needs_you() if right else "") + "</div>"

def fold(text):
    return f'<div class="row" style="color:#5B636D"><span>› {E(text)}</span><span></span><span></span></div>'

os.makedirs(OUT, exist_ok=True)
exec(open(os.path.join(HERE, "boards.py")).read())
exec(open(os.path.join(HERE, "boards_list.py")).read())
