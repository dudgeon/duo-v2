#!/usr/bin/env python3
"""Generates scan-review.html (static markup; the shelf photos are inline SVG)."""
import sys, json, pathlib

HERE = pathlib.Path(__file__).resolve().parent
W = json.loads((HERE / "../../world.json").read_text())
SH = W["prototypeShelf"]
MIS = W["books"]["misread"]
OUT = sys.argv[1] if len(sys.argv) > 1 else str(HERE / "scan-review.html")
TEMPLATE = sys.argv[2] if len(sys.argv) > 2 else str(HERE / "scan-review.template.html")

SHELF_Y = 196  # shelf board top
W_TEAL = "#5fe3c8"
AMBER = "#ffb020"

# title, width, height, colour, text colour, tilt degrees
STYLE_LIST = [
    ("Middlemarch", 24, 128, "#7a2e2e", "#f1dcc0", 0),
    ("The Lantern Keeper", 20, 118, "#d9a441", "#3a2a0a", 0),
    ("Little Women", 26, 134, "#3b6b5e", "#efe6cf", 0),
    ("Salt Roads", 18, 110, "#e8e0d0", "#3b3a36", 5),
    ("Moby-Dick", 25, 140, "#23395b", "#e8d9b0", 0),
    ("A Field Guide to Small Birds", 28, 144, "#6b8e4e", "#fbf6e4", 0),
    ("Persuasion", 19, 124, "#b5533c", "#fbe9d8", 0),
    ("Bleak House", 22, 130, "#3d3d44", "#e9dcc0", 0),
    ("The Secret Garden", 27, 138, "#8a4f7d", "#f6e9f1", 0),
    ("Winter at Halloway", 21, 120, "#c9d6df", "#26384a", 0),
    ("Jane Eyre", 23, 132, "#a63d40", "#f6e3d3", 0),
    ("Ninety Bridges", 12, 116, "#e7c9a9", "#4a3321", 0),
    ("Treasure Island", 24, 128, "#1f6f78", "#f1e4bf", 0),
    ("Emma", 17, 112, "#f0d9d2", "#6a2c33", 0),
]

STYLE = {t: (w, h, c, tc, tl) for (t, w, h, c, tc, tl) in STYLE_LIST}
FALLBACK = [(22, 126, "#5b7a8a", "#f2ead8", 0), (20, 120, "#9a6b3c", "#f6e9d0", 0), (24, 132, "#6d4a6b", "#f3e6ee", 0)]
SPINES = []
for i, sp in enumerate(SH["spines"]):
    st = STYLE.get(sp["title"]) or FALLBACK[i % len(FALLBACK)]
    SPINES.append((sp["title"],) + tuple(st))
FLAGGED = [sp for sp in SH["spines"] if not sp["ok"]]
FLAGSET = {sp["title"] for sp in FLAGGED}
GLARE_TITLE = next((sp["title"] for sp in FLAGGED if sp.get("why") == "Glare"), FLAGGED[0]["title"] if FLAGGED else "")
FOUND_N, NEED_N = SH["found"], SH["needLook"]
BOX = SH["box"]

LINDEN_LIST = [
    ("Emma", 18, 112, "#f0d9d2", "#6a2c33", 0),
    ("Jane Eyre", 23, 132, "#a63d40", "#f6e3d3", 0),
    (MIS["truth"], 21, 126, "#b5533c", "#fbe9d8", 0),
    ("Great Expectations", 26, 138, "#4a4a2a", "#efe3b8", 0),
    ("Silas Marner", 20, 116, "#c9d6df", "#26384a", 0),
    ("The Wind in the Willows", 27, 142, "#3b6b5e", "#efe6cf", 0),
    ("Moby-Dick", 24, 136, "#23395b", "#e8d9b0", 0),
    ("Little Women", 25, 130, "#8a4f7d", "#f6e9f1", 0),
    ("Treasure Island", 24, 126, "#1f6f78", "#f1e4bf", 0),
    ("The Secret Garden", 26, 134, "#d9a441", "#3a2a0a", 0),
    ("Middlemarch", 24, 128, "#7a2e2e", "#f1dcc0", 0),
]
LINDEN = LINDEN_LIST


def esc(s):
    return s.replace("&", "&amp;")


def shelf_svg(uid, spines, mode):
    """mode: 'review' (outlines + fix chips) or 'glare' (heavy glare, no overlays)"""
    o = []
    a = o.append
    a(f'<svg class="photo-svg" viewBox="0 0 360 236" preserveAspectRatio="xMidYMid slice" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Photo of a wooden book-sharing box with books on a shelf">')
    a("<defs>")
    a(f'<linearGradient id="{uid}wall" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#a7b6a3"/><stop offset="1" stop-color="#6f8574"/></linearGradient>')
    a(f'<linearGradient id="{uid}wood" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#b3855a"/><stop offset="1" stop-color="#8d6140"/></linearGradient>')
    a(f'<linearGradient id="{uid}back" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4a3626"/><stop offset="1" stop-color="#221811"/></linearGradient>')
    a(f'<linearGradient id="{uid}sp" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#fff" stop-opacity=".22"/><stop offset=".25" stop-color="#fff" stop-opacity="0"/><stop offset=".8" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".32"/></linearGradient>')
    a(f'<linearGradient id="{uid}gl" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset=".5" stop-color="#fff" stop-opacity="1"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>')
    a(f'<linearGradient id="{uid}glass" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#d9ecf2" stop-opacity=".16"/><stop offset="1" stop-color="#9cc3cf" stop-opacity=".06"/></linearGradient>')
    a(f'<radialGradient id="{uid}vig" cx=".5" cy=".5" r=".75"><stop offset=".6" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".38"/></radialGradient>')
    a(f'<filter id="{uid}blur" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="9"/></filter>')
    a(f'<filter id="{uid}soft"><feGaussianBlur stdDeviation="1.6"/></filter>')
    a(f'<clipPath id="{uid}int"><rect x="20" y="40" width="320" height="156"/></clipPath>')
    a("</defs>")
    # wall / foliage, blurred
    a(f'<rect width="360" height="236" fill="url(#{uid}wall)"/>')
    a(f'<g filter="url(#{uid}blur)" opacity=".85">')
    for cx, cy, r, c in [(18, 30, 34, "#58795a"), (60, 8, 26, "#6e9168"), (320, 20, 38, "#4f7152"), (350, 90, 30, "#7a9a73"),
                         (10, 150, 34, "#4d6b50"), (345, 190, 36, "#5c7d5d"), (190, 4, 30, "#8aa987"), (30, 225, 26, "#6a8b66")]:
        a(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{c}"/>')
    a("</g>")
    # post
    a('<rect x="170" y="226" width="20" height="14" fill="#5b4330"/>')
    # roof
    a('<polygon points="180,3 356,34 4,34" fill="#42604f"/>')
    a('<polygon points="180,3 356,34 4,34" fill="none" stroke="#2f4638" stroke-width="1.5"/>')
    for i in range(4):
        y = 12 + i * 6
        half = 82 + i * 28 + (i * 2)
        a(f'<line x1="{180 - half + 6}" y1="{y + 8}" x2="{180 + half - 6}" y2="{y + 8}" stroke="#2f4638" stroke-width=".8" opacity=".7"/>')
    a('<rect x="4" y="33" width="352" height="7" rx="1.5" fill="#35503f"/>')
    # box body
    a(f'<rect x="8" y="40" width="344" height="190" rx="3" fill="url(#{uid}wood)"/>')
    for i in range(7):
        a(f'<path d="M{10 + i * 49} 42 q4 90 -2 186" stroke="#5a3c24" stroke-width=".7" opacity=".16" fill="none"/>')
    # interior
    a(f'<rect x="20" y="40" width="320" height="156" fill="url(#{uid}back)"/>')
    a(f'<g clip-path="url(#{uid}int)">')
    # shelf light falloff
    a('<rect x="20" y="40" width="320" height="30" fill="#000" opacity=".25"/>')
    # spines
    x = 25.0
    pos = []
    for (t, w, h, col, tc, tilt) in spines:
        top = SHELF_Y - h
        cx = x + w / 2
        rot = f' transform="rotate({tilt} {x + (0 if tilt >= 0 else w):.1f} {SHELF_Y})"' if tilt else ""
        a(f'<g{rot}>')
        a(f'<rect x="{x:.1f}" y="{top}" width="{w}" height="{h}" rx="1.4" fill="{col}"/>')
        a(f'<rect x="{x:.1f}" y="{top}" width="{w}" height="{h}" rx="1.4" fill="url(#{uid}sp)"/>')
        a(f'<rect x="{x + 1:.1f}" y="{top + 6}" width="{w - 2}" height="1.4" fill="{tc}" opacity=".55"/>')
        a(f'<rect x="{x + 1:.1f}" y="{top + 9}" width="{w - 2}" height=".7" fill="{tc}" opacity=".4"/>')
        a(f'<rect x="{x + 1:.1f}" y="{SHELF_Y - 11}" width="{w - 2}" height="1.4" fill="{tc}" opacity=".55"/>')
        fs = min(9.2, w * 0.40, (h - 34) / (len(t) * 0.57))
        ty = top + 14 + (h - 34) / 2 + 6
        a(f'<text transform="translate({cx:.1f} {top + 13 + (h - 30) / 2:.1f}) rotate(90)" text-anchor="middle" dominant-baseline="central" font-family="Georgia, \'Times New Roman\', serif" font-weight="700" font-size="{fs:.1f}" fill="{tc}" letter-spacing=".2">{esc(t)}</text>')
        a("</g>")
        pos.append((t, x, w, h, tilt))
        x += w + 0.6
    # leaning book occlusion shadow
    a(f'<rect x="20" y="{SHELF_Y - 6}" width="320" height="6" fill="#000" opacity=".28"/>')
    a("</g>")
    # shelf board
    a(f'<rect x="14" y="{SHELF_Y}" width="332" height="12" fill="#a57850"/>')
    a(f'<rect x="14" y="{SHELF_Y}" width="332" height="2" fill="#d1a579" opacity=".8"/>')
    a(f'<rect x="14" y="{SHELF_Y + 10}" width="332" height="2" fill="#5a3c24" opacity=".5"/>')
    # lower panel
    a('<rect x="20" y="212" width="320" height="14" rx="2" fill="#80593a"/>')
    a('<rect x="24" y="215" width="312" height="8" rx="1.5" fill="none" stroke="#5a3c24" stroke-width=".8" opacity=".5"/>')
    # door frame / glass
    a(f'<rect x="20" y="40" width="320" height="156" fill="url(#{uid}glass)"/>')
    a('<rect x="20" y="40" width="320" height="156" fill="none" stroke="#6b4a2f" stroke-width="2.5"/>')
    a('<rect x="333" y="110" width="3.5" height="26" rx="1.7" fill="#d6cdbb"/>')
    a('<rect x="333" y="110" width="1.2" height="26" rx=".6" fill="#fff" opacity=".7"/>')

    if mode == "review":
        # glare streak over the glare-flagged spine
        for (t, px, w, h, tilt) in pos:
            if t == GLARE_TITLE:
                gx = px + w / 2
        a(f'<g clip-path="url(#{uid}int)" style="mix-blend-mode:screen">')
        a(f'<polygon points="{gx - 8:.0f},36 {gx + 46:.0f},36 {gx + 6:.0f},200 {gx - 48:.0f},200" fill="url(#{uid}gl)" opacity=".62"/>')
        a(f'<polygon points="{gx + 54:.0f},36 {gx + 64:.0f},36 {gx + 24:.0f},200 {gx + 14:.0f},200" fill="url(#{uid}gl)" opacity=".42"/>')
        a("</g>")
        a(f'<g clip-path="url(#{uid}int)"><polygon points="{gx - 2:.0f},36 {gx + 28:.0f},36 {gx - 12:.0f},200 {gx - 42:.0f},200" fill="#fff" opacity=".0"/></g>')
        # detections
        for (t, px, w, h, tilt) in pos:
            top = SHELF_Y - h
            flagged = t in FLAGSET
            col = AMBER if flagged else W_TEAL
            sw = 2.1 if flagged else 1.1
            rot = f' transform="rotate({tilt} {px + (0 if tilt >= 0 else w):.1f} {SHELF_Y})"' if tilt else ""
            a(f'<g{rot}><rect x="{px - 1.2:.1f}" y="{top - 1.6}" width="{w + 2.4}" height="{h + 2.6}" rx="3.2" fill="{"#ffb020" if flagged else "none"}" fill-opacity=".12" stroke="{col}" stroke-width="{sw}" stroke-opacity="{1 if flagged else .85}"/></g>')
        for (t, px, w, h, tilt) in pos:
            if t in FLAGSET:
                top = SHELF_Y - h
                cxp = px + w / 2
                a(f'<g><rect x="{cxp - 15:.1f}" y="{top - 22}" width="30" height="15" rx="7.5" fill="{AMBER}"/>'
                  f'<polygon points="{cxp - 3:.1f},{top - 7} {cxp + 3:.1f},{top - 7} {cxp:.1f},{top - 3.5}" fill="{AMBER}"/>'
                  f'<text x="{cxp:.1f}" y="{top - 11.2}" text-anchor="middle" font-family="-apple-system, system-ui, sans-serif" font-size="9" font-weight="700" fill="#3a2500">Fix</text></g>')
    else:
        # heavy glare: broad streaks, washed-out areas
        a(f'<g clip-path="url(#{uid}int)" style="mix-blend-mode:screen">')
        a(f'<polygon points="52,36 150,36 92,200 -6,200" fill="url(#{uid}gl)" opacity=".85"/>')
        a(f'<polygon points="168,36 214,36 168,200 122,200" fill="url(#{uid}gl)" opacity=".6"/>')
        a(f'<polygon points="236,36 330,36 292,200 198,200" fill="url(#{uid}gl)" opacity=".7"/>')
        a(f'<rect x="20" y="40" width="320" height="38" fill="#fff" opacity=".18"/>')
        a("</g>")
    # photo vignette + haze
    a(f'<rect width="360" height="236" fill="url(#{uid}vig)"/>')
    a("</svg>")
    return "".join(o)


# ---------------------------------------------------------------- content
SHELF = shelf_svg("a", SPINES, "review")
SHELF_V1 = shelf_svg("b", LINDEN, "glare")

FOUND = [(t, c, tc) for (t, w, h, c, tc, tilt) in SPINES if t not in FLAGSET]
CONF = {"Middlemarch": 99, "The Lantern Keeper": 97, "Little Women": 99, "Salt Roads": 91, "Moby-Dick": 99,
        "A Field Guide to Small Birds": 96, "Bleak House": 98, "The Secret Garden": 98, "Winter at Halloway": 95,
        "Jane Eyre": 99, "Treasure Island": 97, "Emma": 93}


def cover(c, tc, t, cls=""):
    return f'<span class="cover {cls}" style="background:{c};color:{tc}"><i></i></span>'


found_rows = []
for t, c, tc in FOUND:
    conf = CONF[t]
    low = conf < 95
    found_rows.append(
        f'<li class="row">{cover(c, tc, t)}<span class="rt">{esc(t)}</span>'
        f'<span class="rc{" lowish" if low else ""}">{conf}%</span>'
        f'<svg class="ck" viewBox="0 0 20 20"><path d="M5 10.5l3.2 3.2L15 6.8" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg></li>')

V1_BOOKS = [("Emma", "#f0d9d2", "#6a2c33"), ("Jane Eyre", "#a63d40", "#f6e3d3"),
            (MIS["matched"], "#1d2a3a", "#7fd0ff"),
            ("Great Expectations", "#4a4a2a", "#efe3b8"), ("Silas Marner", "#c9d6df", "#26384a"),
            ("The Wind in the Willows", "#3b6b5e", "#efe6cf"), ("Moby-Dick", "#23395b", "#e8d9b0"),
            ("Little Women", "#8a4f7d", "#f6e9f1"), ("Treasure Island", "#1f6f78", "#f1e4bf"),
            ("The Secret Garden", "#d9a441", "#3a2a0a"), ("Middlemarch", "#7a2e2e", "#f1dcc0")]
v1_rows = []
for t, c, tc in V1_BOOKS:
    cls = "tech" if t == MIS["matched"] else ""
    v1_rows.append(f'<li class="row v1row">{cover(c, tc, t, cls)}<span class="rt">{esc(t)}</span>'
                   f'<span class="added"><svg viewBox="0 0 20 20"><path d="M5 10.5l3.2 3.2L15 6.8" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>Added</span></li>')

BATT = '<svg class="sb-icons" viewBox="0 0 66 12"><g fill="currentColor"><rect x="0" y="8" width="3" height="4" rx=".8"/><rect x="5" y="5.5" width="3" height="6.5" rx=".8"/><rect x="10" y="3" width="3" height="9" rx=".8"/><rect x="15" y="0" width="3" height="12" rx=".8"/></g><path d="M29 4.2a8 8 0 0 1 11 0M31.2 6.8a5 5 0 0 1 6.6 0" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><circle cx="34.5" cy="9.6" r="1.5" fill="currentColor"/><rect x="44.5" y=".5" width="19" height="11" rx="3.2" fill="none" stroke="currentColor" opacity=".45"/><rect x="46" y="2" width="14" height="8" rx="2" fill="currentColor"/><rect x="64.2" y="4" width="1.6" height="4" rx=".8" fill="currentColor" opacity=".5"/></svg>'

CHEV = '<svg viewBox="0 0 12 20" width="11" height="18"><path d="M10 2L2 10l8 8" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>'


def chip(title, pct, best=False):
    return (f'<span class="chip{" best" if best else ""}">'
            + ('<svg viewBox="0 0 20 20"><path d="M5 10.5l3.2 3.2L15 6.8" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>' if best else '')
            + f'<b>{esc(title)}</b><em>{pct}%</em></span>')


def flagged(c, tc, read, why, spine, chips):
    return f'''<div class="flag">
  <div class="fh">{cover(c, tc, read)}<div class="ft"><div class="fr">Read as <q>{esc(read)}</q></div><div class="fw"><span class="dot"></span>{why} · spine {spine}</div></div><span class="skip">Skip</span></div>
  <div class="dym">Did you mean&hellip;</div>
  <div class="chips">{"".join(chips)}</div>
  <div class="fixrow"><button class="fix">Fix</button></div>
</div>'''


ALTS = {  # alternatives per flagged title: (title, confidence %), best first
    MIS["truth"]: [(MIS["truth"], 64), (MIS["matched"], 21), ("Persian Nights", 9)],
    "Ninety Bridges": [("Ninety Bridges", 71), ("Ninety Birds", 18), ("Nine Tides", 7)],
}
order = [sp["title"] for sp in SH["spines"]]
cards = []
for sp in FLAGGED:
    st = STYLE.get(sp["title"]) or FALLBACK[0]
    alts = ALTS.get(sp["title"]) or [(sp["title"], 70), (sp["read"], 20)]
    cards.append(flagged(st[2], st[3], sp["read"], sp["why"], order.index(sp["title"]) + 1,
                         [chip(t, p, i == 0) for i, (t, p) in enumerate(alts)]))
FLAGS = "".join(cards)

HTML = open(TEMPLATE).read()
HTML = (HTML.replace("@@SHELF@@", SHELF).replace("@@SHELF_V1@@", SHELF_V1)
        .replace("@@FOUND@@", "\n".join(found_rows)).replace("@@V1ROWS@@", "\n".join(v1_rows))
        .replace("@@FLAGS@@", FLAGS)
        .replace("@@BOX@@", BOX).replace("@@FOUND_N@@", str(FOUND_N)).replace("@@NEED_N@@", str(NEED_N))
        .replace("@@REST_N@@", str(FOUND_N - NEED_N)).replace("@@CTA@@", SH["cta"])
        .replace("@@V1_BOX@@", MIS["box"]).replace("@@V1_N@@", str(len(LINDEN))).replace("@@BATT@@", BATT).replace("@@CHEV@@", CHEV))
open(OUT, "w").write(HTML)
print("wrote", OUT, len(HTML))
