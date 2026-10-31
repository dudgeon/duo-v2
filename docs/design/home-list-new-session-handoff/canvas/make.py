#!/usr/bin/env python3
"""Writes the home-list-new-session handoff's screens (DL-262) from the canvas's ListPane logic.

  python3 docs/design/home-list-new-session-handoff/canvas/make.py

screens/list-1440-new-session.html: home-evolution-handoff's approved list-1440 with B's row added.
screens/states.html: B's row in every state, Light, Dark and Classic, as the canvas draws them.
The canvas sources are beside this file (*.dc.html); https://claude.ai/artifact/Ug3zdTyXjRTR5TWzyyMAMN
"""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
HANDOFF = os.path.dirname(HERE)
DESIGN = os.path.dirname(HANDOFF)
SCREENS = os.path.join(HANDOFF, "screens")

P = {
    "light": dict(ground="#F3F4F6", pane="#FFFFFF", selected="#E9ECEF", menuTarget="#D8DCE1", rule="#C9CDD3",
                  controlEdge="#8B939C", text="#1F2328", text2="#5B636D", needsYou="#C2410C"),
    "dark": dict(ground="#131518", pane="#181A1E", selected="#262A30", menuTarget="#2E3238", rule="#2B2F36",
                 controlEdge="#6E7681", text="#E6E8EB", text2="#9AA1AB", needsYou="#F97316"),
    "classic": dict(ground="#F0E9D6", pane="#FBF8EE", selected="#F2D9B8", menuTarget="#D4C8A6", rule="#D4C8A6",
                    controlEdge="#B8AB8E", text="#1A1410", text2="#7B6F58", needsYou="#B91C1C"),
}
ROBOT = ("M5 0h1v1h-1zM2 1h8v1h-8zM2 2h1v1h-1zM4 2h4v1h-4zM9 2h1v1h-1zM2 3h8v2h-8zM1 5h10v1h-10z"
         "M3 6h2v1h-2zM7 6h2v1h-2zM3 7h2v1h-2zM7 7h2v1h-2z")
UPDOWN = "M1 3.5 3.5 1 6 3.5M1 6.5 3.5 9 6 6.5"
PROJECTS = ["checkout-redesign", "refunds-api-spec", "fraud-rules-review", "pricing-experiment-q4", "onboarding-v3", "~/repos/site"]
FONT = "-apple-system,BlinkMacSystemFont,'SF Pro Text',system-ui,sans-serif"


NO_HOME = ("nohome", "nohomemenu", "tcc", "nodocs")


def row(c, st):
    """B's row (28 high, 1 dashed controlEdge, radius 6) and what hangs under it (DL-262: Home, else ~/Documents)."""
    hot = st in ("hover", "pressed")
    bg = c["menuTarget"] if st == "pressed" else (c["selected"] if hot else "transparent")
    ink = c["text"] if hot else c["text2"]
    menu = st in ("menu", "choose", "nohomemenu")
    pop_bg = c["selected"] if menu else c["pane"]
    pick = "Choose…" if st == "nodocs" else ("~/Documents" if st in NO_HOME else '<span style="font-size:11px">★</span>home')
    pick_ink = c["text2"] if st == "nodocs" else c["text"]
    html = (f'<div style="height:28px;box-sizing:border-box;display:flex;align-items:center;gap:8px;padding:0 6px 0 10px;'
            f'border:1px dashed {c["controlEdge"]};border-radius:6px;background:{bg};color:{c["text"]};font:13px/20px {FONT};white-space:nowrap">'
            f'<svg width="12" height="8" viewBox="0 0 12 8" style="flex:none"><path fill="{ink}" d="{ROBOT}"/></svg>'
            f'<span>New session</span><span style="color:{c["text2"]}">in</span>'
            f'<span style="display:inline-flex;align-items:center;gap:5px;height:20px;padding:0 6px 0 7px;box-sizing:border-box;'
            f'border:1px solid {c["rule"]};border-radius:5px;background:{pop_bg};color:{pick_ink};font-size:12px;line-height:16px">{pick}'
            f'<svg width="7" height="10" viewBox="0 0 7 10"><path d="{UPDOWN}" fill="none" stroke="{c["text2"]}" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/></svg></span>'
            f'<span style="flex:1"></span><span style="color:{c["text2"]};font-size:12px">⌘T</span></div>')
    note = {"tcc": "The first start here, macOS asks: “Duo” would like to access files in your Documents folder.",
            "nodocs": "There’s no ~/Documents on this Mac, so choose where it starts."}.get(st)
    if note:
        html += f'<div style="padding:4px 0 0 10px;font:12px/16px {FONT};color:{c["text2"]}">{note}</div>'
    if st == "hover":
        html += (f'<div style="margin:4px 0 0 30px;display:inline-block;padding:2px 7px;background:{c["pane"]};border:1px solid {c["rule"]};'
                 f'border-radius:4px;box-shadow:0 2px 8px rgba(0,0,0,.18);font:11px/16px {FONT};color:{c["text"]}">New Claude session ⌘T · in home</div>')
    if menu:
        tail = [("", p) for p in PROJECTS] + [None, ("", "Choose Another Folder…"), ("", "New Project…")]
        items = ([("✓", "~/Documents"), None] + tail + [("", "Choose Home Folder…")]) if st == "nohomemenu" \
            else [("✓", "★ home"), None, ("", "~/Documents")] + tail
        rows = []
        for it in items:
            if it is None:
                rows.append(f'<div style="height:1px;margin:4px 8px;background:{c["rule"]}"></div>')
                continue
            hi = st == "choose" and it[1].startswith("Choose Another")
            rows.append(f'<div style="display:flex;align-items:center;gap:6px;height:22px;padding:0 8px;border-radius:5px;'
                        f'background:{c["selected"] if hi else "transparent"}"><span style="width:12px">{it[0]}</span>{it[1]}</div>')
        html += (f'<div style="margin:4px 0 0 104px;width:220px;padding:5px;background:{c["pane"]};border:1px solid {c["rule"]};border-radius:10px;'
                 f'box-shadow:0 8px 24px rgba(0,0,0,.18);font:13px/20px {FONT};color:{c["text"]}">{"".join(rows)}</div>')
    return html


def states():
    cells = []
    plan = [("rest", t) for t in ("light", "dark", "classic")] + \
           [(s, "light") for s in ("hover", "pressed", "menu", "choose")] + [("menu", "dark")] + \
           [("nohome", t) for t in ("light", "dark", "classic")] + \
           [("nohomemenu", "light"), ("tcc", "light"), ("nodocs", "light")]
    names = {"rest": "With a Home · rest", "hover": "Hover (system tooltip)", "pressed": "Pressed", "menu": "The popup (system menu)",
             "choose": "Choose Another Folder… (then the system folder panel)", "nohome": "No Home · rest",
             "nohomemenu": "No Home · the popup", "tcc": "First start in Documents: macOS asks, in Duo's name",
             "nodocs": "No Home and no ~/Documents: no default"}
    for st, t in plan:
        c = P[t]
        cells.append(f'<div style="display:flex;flex-direction:column;gap:8px"><div class="cap">{names[st]} · {t.title()}</div>'
                     f'<div style="background:{c["pane"]};border:1px solid {c["rule"]};border-radius:8px;padding:16px;height:340px;box-sizing:border-box">'
                     f'{row(c, st)}</div></div>')
    return ('<!DOCTYPE html>\n<html lang="en"><head>\n<meta charset="utf-8">\n<meta name="design-size" content="1600x2000">\n'
            '<meta name="design-kind" content="board">\n<meta name="design-surface" content="home-list-new-session">\n'
            '<!--\nDL-262 · B\'s New session row in every state. Written by canvas/make.py from the canvas\n'
            'https://claude.ai/artifact/Ug3zdTyXjRTR5TWzyyMAMN (ListPane.dc.html, dflt="docs"). A picture written in HTML.\n-->\n'
            '<title>Duo · New session row · states</title>\n<style>body{margin:0}.cap{font:600 11px/16px ' + FONT +
            ';letter-spacing:.66px;text-transform:uppercase;color:#5B636D}</style>\n</head>\n<body>\n'
            f'<div style="width:1600px;box-sizing:border-box;padding:40px;background:#F3F4F6;font:13px/20px {FONT};'
            'display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:28px 32px">' + "".join(cells) + '</div>\n</body></html>\n')


def window():
    src = open(os.path.join(DESIGN, "home-evolution-handoff", "screens", "list-1440.html")).read()
    anchor = '<div style="flex:1;min-height:0;overflow:hidden"><div class="row" style="margin-top:8px;border:1px solid #C2410C'
    assert src.count(anchor) == 1, "list-1440's needs-you line moved: update the anchor"
    c = P["light"]
    added = f'<div style="margin:8px 8px 0">{row(c, "rest")}</div>'
    src = src.replace(anchor, anchor.replace('<div class="row"', added + '<div class="row"', 1), 1)
    src = re.sub(r"<!--.*?-->", "<!--\nDL-262 · All projects › List with B's New session row, 1440×900. Written by\n"
                 "home-list-new-session-handoff/canvas/make.py: home-evolution-handoff's approved list-1440 with the row\n"
                 "added above the needs-you line. Everything else is that screen's.\n-->", src, count=1, flags=re.S)
    src = src.replace('<meta name="design-surface" content="home-evolution">', '<meta name="design-surface" content="home-list-new-session">')
    return re.sub(r"<title>.*?</title>", "<title>Duo · All projects › List with New session · 1440×900</title>", src, count=1)


os.makedirs(SCREENS, exist_ok=True)
open(os.path.join(SCREENS, "list-1440-new-session.html"), "w").write(window())
open(os.path.join(SCREENS, "states.html"), "w").write(states())
json.dump([
    {"name": "list-1440-new-session", "size": "1440x900", "kind": "target",
     "title": "All projects › List with B's New session row (DL-262)", "from": "home-evolution-handoff/screens/list-1440.html + the row"},
    {"name": "states", "size": "1600x2000", "kind": "board",
     "title": "B's row: with a Home (rest, hover, pressed, popup, Choose Another Folder…) and without (~/Documents, popup, macOS's Documents prompt, no ~/Documents); Light, Dark, Classic",
     "from": "ListPane.dc.html (dflt docs)"},
], open(os.path.join(SCREENS, "manifest.json"), "w"), indent=1)
print("wrote", SCREENS)
