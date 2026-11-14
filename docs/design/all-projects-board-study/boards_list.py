# L1, L2: All projects › List grouped by project, with + New session per project (Geoff, 2026-11-13, second ask).
# Run by make_boards.py after boards.py.
LG = [
 ("home", True, "~/work/home", 21, [("dot","Morning triage","","1h"),("bub","Weekly status draft","","at prompt"),("bub","Inbox sweep","","2h")], 18),
 ("checkout-redesign", False, "~/work/home/payments/checkout-redesign", 3, [("dot","PRD v2 edits","Exec review prep","4m"),("bub","Teardown research","Exec review prep","working"),("bub","Checkout copy audit","","2d")], 0),
 ("board-deck", False, "~/Desktop/board-deck", 1, [("dot","Slide 7 numbers","","9m")], 0),
 ("onboarding-v3", False, "~/work/home/growth/onboarding-v3", 2, [("dot","Copy review pass 2","Launch copy","12m"),("dia","Funnel SQL","","40m")], 0),
 ("pricing-experiment-q4", False, "~/work/home/growth/pricing-experiment-q4", 1, [("dia","Results readout","Q4 readout","25m")], 0),
 ("q4-planning", False, "~/work/home/q4-planning", 2, [("bub","Roadmap narrative","Draft plan","working"),("bub","Q4 plan outline","Draft plan","3h")], 0),
 ("site", False, "~/repos/site", 1, [("bub","Fix footer links","","at prompt")], 0),
]

def lrow(s):
    g, name, task, wait = s
    t = f'<span class="mut" style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{"▢ " + E(task) if task else ""}</span>'
    return (f'<div style="display:grid;grid-template-columns:22px minmax(0,1fr) 220px 80px;align-items:center;height:24px;padding-left:22px">'
            f'{glyph(g)}<span style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis;font-weight:{600 if g == "dot" else 400}">{E(name)}</span>{t}'
            f'<span class="mut" style="text-align:right;font-size:12px">{E(wait)}</span></div>')

def ghead(name, star, path, count, hov=False, key=None, chevron="⌄", rowhov=False):
    """DL-341: at rest only a + (text2); hovering the button shows "+ New session" on a `selected` pill.
    rowhov: the pointer is on the header but not the button (the + stays a +)."""
    st = "★ " if star else ""
    bg = "background:#F3F4F6;" if rowhov else ""
    k = f' <span class="mut" style="font-size:11px">{key}</span>' if key else ""
    if hov:
        inner = f'<span style="font-size:14px;line-height:14px">+</span> New session{k}'
        bst = "background:#E9ECEF;color:#1F2328;padding:0 8px 0 6px;"
    else:
        inner = f'<span style="font-size:14px;line-height:14px">+</span>{k}'
        bst = "background:none;color:#5B636D;padding:0 4px;"
    return (f'<div style="display:flex;align-items:center;gap:8px;height:30px;border-top:1px solid #E9ECEF;margin-top:4px;padding:0 6px;{bg}border-radius:5px">'
            f'<span class="mut" style="width:12px">{chevron}</span><strong style="white-space:nowrap">{E(st + name)}</strong>'
            f'<span class="tp" style="max-width:300px">{E(path)}</span><span class="mut" style="font-size:12px">{count}</span>'
            f'<button type="button" style="margin-left:auto;border:0;border-radius:5px;height:22px;min-width:22px;font-family:inherit;font-size:12px;{bst}white-space:nowrap;display:flex;align-items:center;gap:4px;justify-content:center" '
            f'aria-label="New session in {E(name)}" title="New session in {E(name)} · {E(path)}">{inner}</button></div>')

def lgroup(gi, hov=False, last_row=False):
    name, star, path, count, rows, more = LG[gi]
    if last_row:
        out = (f'<div style="display:flex;align-items:center;gap:8px;height:30px;border-top:1px solid #E9ECEF;margin-top:4px;padding:0 6px">'
               f'<span class="mut" style="width:12px">⌄</span><strong>{E(("★ " if star else "") + name)}</strong><span class="tp">{E(path)}</span>'
               f'<span class="mut" style="font-size:12px">{count}</span></div>')
    else:
        out = ghead(name, star, path, count, hov=hov)
    out += "".join(lrow(s) for s in rows)
    if more:
        out += f'<div class="mut" style="height:24px;display:flex;align-items:center;padding-left:44px">{more} more ›</div>'
    if last_row:
        out += (f'<button type="button" style="display:grid;grid-template-columns:22px minmax(0,1fr);align-items:center;height:24px;margin-left:22px;width:calc(100% - 22px);'
                f'border:0;background:{"#E9ECEF" if hov else "none"};border-radius:4px;font-family:inherit;font-size:12px;color:{"#1F2328" if hov else "#5B636D"};text-align:left;padding:0">'
                f'<span style="text-align:center">+</span><span>New session in {E(name)}</span></button>')
    return out

def lhdr(group="Project"):
    return (f'<div class="hdr"><span class="seg"><span>Board</span><span class="on">List</span></span>'
            f'<span class="flt">Filter sessions</span><span style="margin-left:auto" class="newp">+ New project</span>'
            f'<span class="mut">Group</span><span class="pop">{E(group)} ⌃</span></div>')

newrow = ('<div style="border:1px dashed #8B939C;border-radius:6px;height:28px;flex:none;display:flex;align-items:center;gap:8px;padding:0 10px">'
          '<strong>New session</strong> in <span style="border:1px solid #C9CDD3;border-radius:5px;padding:0 6px">★ home ⌄</span><span class="mut" style="margin-left:auto">⌘T</span></div>')

fold_row = lambda text, top=True: (f'<div class="mut" style="height:30px;display:flex;align-items:center;gap:8px;{"border-top:1px solid #E9ECEF;margin-top:4px;" if top else ""}padding:0 6px">'
                                   f'<span style="width:12px">›</span>{E(text)}</div>')

popup = ('<div style="position:absolute;left:930px;top:84px;width:200px;background:#FFFFFF;border:1px solid #C9CDD3;border-radius:7px;box-shadow:0 6px 20px rgba(31,35,40,.16);padding:5px;font-size:13px;z-index:3">'
         '<div style="padding:3px 8px 3px 22px">Recent</div><div style="padding:3px 8px;background:#D8DCE1;border-radius:4px">✓&nbsp;&nbsp;Project</div>'
         '<div style="height:1px;background:#E9ECEF;margin:4px 0"></div><div style="padding:3px 8px 3px 22px">Show Archived</div></div>')

l1_mid = (lhdr() + newrow + '<div style="display:flex;flex-direction:column">' + lgroup(0) + lgroup(1, hov=True) + lgroup(2) + lgroup(3) + lgroup(4) + lgroup(5) + lgroup(6) +
          fold_row("Quieter projects · 6") + fold_row("Archived · 3", top=False) + '</div>')
l1 = window(l1_mid) + popup + \
  '<div class="tip" style="left:860px;top:294px">New session in checkout-redesign<br><span style="color:#C9CDD3">~/work/home/payments/checkout-redesign</span></div>' + \
  ann(1092, 588, "<strong>Group ⌄ › Project</strong>, beside Recent (View › Group Sessions By; <code>duo2 view list group recent|project</code>). Each project is a header with its name, its folder and the count. At the right end there's only a <strong>+</strong> in text2. Hovering it opens it to <strong>+ New session</strong> on a <code>selected</code> pill, and the tooltip names the project and folder (DL-341, Q-546).", 336) + \
  ann(1092, 762, "Projects go newest activity first (pinned first, if Q-541 is yes). Within a project, sessions go newest first, five then \"n more\". Projects with nothing this week fold into Quieter projects. A row's project column shows its task instead. The dashed row stays, for any other folder (DL-341, Q-547).", 336)
board("L1-list-by-project.dc.html", "L1 · List grouped by project [P]", 1440, 900, l1)

l2 = f'''
<div style="padding:28px 32px;display:flex;flex-direction:column;gap:18px;height:100%;box-sizing:border-box">
<div class="h2">L2 · The project header's +: its states (DL-341: a + at rest, "New session" on hover)</div>
<div style="display:grid;grid-template-columns:1fr 1fr;gap:22px 32px">
<div style="display:flex;flex-direction:column;gap:6px;min-width:0"><span class="lab">Rest: a + only</span>{lgroup(1)}</div>
<div style="display:flex;flex-direction:column;gap:6px;min-width:0"><span class="lab">Pointer on the +: it opens to "+ New session"</span>{lgroup(3, hov=True)}</div>
<div style="display:flex;flex-direction:column;gap:6px;min-width:0"><span class="lab">Pointer elsewhere on the header: the + stays a +</span>{ghead("q4-planning", False, "~/work/home/q4-planning", 2, rowhov=True)}</div>
<div style="display:flex;flex-direction:column;gap:6px;min-width:0"><span class="lab">A project's header or row selected: + ⌘T</span>{ghead("q4-planning", False, "~/work/home/q4-planning", 2, key="⌘T")}</div>
<div style="display:flex;flex-direction:column;gap:6px;min-width:0"><span class="lab">L1 · a folder with no project file</span>{lgroup(2)}<span class="mut" style="font-size:12px">It starts in the folder, and Claude asks its own trust question.</span></div>
<div style="display:flex;flex-direction:column;gap:6px;min-width:0"><span class="lab">L1 · folded</span>{ghead("pricing-experiment-q4", False, "~/work/home/growth/pricing-experiment-q4", 1, chevron="›")}<span class="mut" style="font-size:12px">A folded project keeps its button.</span></div>
</div>
<div class="txt" style="max-width:1300px"><strong>Geoff, 2026-11-13 (DL-341):</strong> "header right end; button could be more subtle; + button or other new session icon, and words 'new session' on mouseover". So at rest the header shows only a + in text2, at the same 22-point target. Hovering the + widens it to "+ New session" on a <code>selected</code> pill, growing leftward, and the tooltip adds the project and its folder. Its accessibility label is always "New session in ‹project›". The verb is <code>duo2 session new --project &lt;p&gt;</code> (or <code>--folder</code>), and the button opens the project's page on the new session, as the tile's does. With a project's header or one of its rows selected, ⌘T starts the session in that project, and the + shows ⌘T beside it; otherwise ⌘T starts where the dashed row says. The last-row alternative is set aside.</div>
</div>'''
board("L2-header-button.dc.html", "L2 · The header's +: its states [P]", 1440, 900, l2)

idx = json.load(open(idx_path))
base = [k for k in idx["boards"] if not k.startswith("L")]
y = max(idx["boards"][k]["y"] + idx["boards"][k]["h"] for k in base) + 343
idx["boards"]["L1-list-by-project.dc.html"] = {"x": 0, "y": y, "w": 1440, "h": 900, "title": "L1 · List grouped by project, + New session per project [P]"}
idx["boards"]["L2-header-button.dc.html"] = {"x": 1520, "y": y, "w": 1440, "h": 900, "title": "L2 · The header's +: its states [P]"}
idx["order"] = [o for o in idx["order"] if not o.startswith("L")] + ["L1-list-by-project.dc.html", "L2-header-button.dc.html"]
idx["notes"]["h4"] = {"x": 0, "y": y - 240, "text": "The List grouped by project", "kind": "title1", "maxW": 2960}
json.dump(idx, open(idx_path, "w"), indent=1, ensure_ascii=False)
print("wrote L1, L2")
