#!/usr/bin/env python3
"""Derive Duo's window base colours (Q-441, F-547, board 4a′ round 2) and check their contrast.

Six hues round the wheel (needs-you's orange left out), each in a light and a
deep step, so 12 colours. The toolbar (ground) takes the colour at real chroma:
  ground  = (L, min(cap, 92% of the sRGB limit at L, h)) from ROLES[mode]["ground"][step]
The reading surfaces (pane, chatGround, toolOutputFill) take a pale tint of the hue.
Text on a coloured toolbar is `text`; text2 sits only on the pale tints.
Run:  python3 window_palette.py            -> table, distances, contrast
      python3 window_palette.py --json     -> palette.json (tokens-ready)
"""
import json, math, sys

# Round 2 (Geoff, 2026-11-02, 4a″ C): colours chosen to tell windows apart, not to match.
# Six hues spread round the wheel, leaving out only the needs-you orange (h 22-64),
# each in a light step and a deep step. The toolbar (ground) carries the colour at
# real chroma; the reading surfaces take a pale tint of the same hue.
HUES  = [(20, "Coral"), (75, "Ochre"), (135, "Green"), (185, "Teal"), (250, "Blue"), (315, "Purple")]
STEPS = ["light", "deep"]
# Order new windows get them in (Geoff): all light, then all deep, hues in this order.
HUE_ORDER = [4, 1, 5, 2, 0, 3]          # Blue, Ochre, Purple, Green, Coral, Teal
GAMUT = 0.92                           # chroma = min(cap, 92% of the sRGB limit at L, h)
# (L, C cap) per role, per step [light, deep]
ROLES = {
 "light": {
  "ground":         [(0.86, 0.10), (0.72, 0.14)],
  "pane":           [(0.965, 0.018), (0.965, 0.018)],
  "chatGround":     [(0.945, 0.026), (0.945, 0.026)],
  "toolOutputFill": [(0.975, 0.012), (0.975, 0.012)],
 },
 "dark": {
  "ground":         [(0.50, 0.12), (0.36, 0.12)],
  "pane":           [(0.235, 0.022), (0.235, 0.022)],
  "chatGround":     [(0.180, 0.016), (0.180, 0.016)],
  "toolOutputFill": [(0.215, 0.020), (0.215, 0.020)],
 },
}
TEXT = {"light": {"text": "#1F2328", "text2": "#5B636D", "needsYou": "#C2410C"},
        "dark":  {"text": "#E6E8EB", "text2": "#9AA1AB", "needsYou": "#F97316"}}

def oklch_to_rgb(L, C, h):
    a, b = C*math.cos(math.radians(h)), C*math.sin(math.radians(h))
    l_ = L + 0.3963377774*a + 0.2158037573*b
    m_ = L - 0.1055613458*a - 0.0638541728*b
    s_ = L - 0.0894841775*a - 1.2914855480*b
    l, m, s = l_**3, m_**3, s_**3
    r = 4.0767416621*l - 3.3077115913*m + 0.2309699292*s
    g = -1.2684380046*l + 2.6097574011*m - 0.3413193965*s
    bb = -0.0041960863*l - 0.7034186147*m + 1.7076147010*s
    return r, g, bb
def enc(x):
    return 12.92*x if x <= 0.0031308 else 1.055*x**(1/2.4) - 0.055
def dec(x):
    return x/12.92 if x <= 0.04045 else ((x+0.055)/1.055)**2.4
def hexc(L, C, h):
    rgb = oklch_to_rgb(L, C, h)
    ok = all(-1e-4 <= v <= 1+1e-4 for v in rgb)
    return "#" + "".join("%02X" % round(max(0, min(1, enc(v)))*255) for v in rgb), ok
def lum(hx):
    r, g, b = (dec(int(hx[i:i+2], 16)/255) for i in (1, 3, 5))
    return 0.2126*r + 0.7152*g + 0.0722*b
def cr(a, b):
    x, y = sorted((lum(a), lum(b)))
    return (y+0.05)/(x+0.05)
def hex_to_oklch(hx):
    r, g, b = (dec(int(hx[i:i+2], 16)/255) for i in (1, 3, 5))
    l = (0.4122214708*r + 0.5363325363*g + 0.0514459929*b) ** (1/3)
    m = (0.2119034982*r + 0.6806995451*g + 0.1073969566*b) ** (1/3)
    s = (0.0883024619*r + 0.2817188376*g + 0.6299787005*b) ** (1/3)
    L = 0.2104542553*l + 0.7936177850*m - 0.0040720468*s
    A = 1.9779984951*l - 2.4285922050*m + 0.4505937099*s
    B = 0.0259040371*l + 0.7827717662*m - 0.8086757660*s
    return L, math.hypot(A, B), math.degrees(math.atan2(B, A)) % 360

def maxc(L, h):
    c = 0.0
    while hexc(L, c + 0.002, h)[1]: c += 0.002
    return c

def palette():
    out = []
    for hi, (h, name) in enumerate(HUES):
        for si, step in enumerate(STEPS):
            nm = name if step == "light" else "Deep " + name.lower()
            c = {"id": nm.lower().replace(" ", "-"), "name": nm, "hue": h, "step": step}
            for mode, roles in ROLES.items():
                c[mode] = {}
                for role, steps in roles.items():
                    L, cap = steps[si]
                    hx, ok = hexc(L, min(cap, maxc(L, h) * GAMUT), h)
                    c[mode][role] = hx
                c[mode]["swatch"] = c[mode]["ground"]
                d, t = c[mode], TEXT[mode]
                # Toolbar text is `text` on a coloured toolbar; text2 sits only on the reading surfaces.
                d["textOnGround"] = round(cr(t["text"], d["ground"]), 2)
                read = [d[r] for r in ("pane", "chatGround", "toolOutputFill")]
                d["minText"] = round(min(cr(t["text"], s) for s in read + [d["ground"]]), 2)
                d["minText2"] = round(min(cr(t["text2"], s) for s in read), 2)
                d["needsOnPane"] = round(cr(t["needsYou"], d["pane"]), 2)
            out.append(c)
    order = [out[hi * 2 + si]["id"] for si in range(2) for hi in HUE_ORDER]
    return out, order

def distances(pal, mode):
    import itertools
    def lab(hx):
        L, C, h = hex_to_oklch(hx); return (L, C*math.cos(math.radians(h)), C*math.sin(math.radians(h)))
    ds = sorted((math.dist(lab(a[mode]["ground"]), lab(b[mode]["ground"]))*100, a["name"], b["name"])
                for a, b in itertools.combinations(pal, 2))
    return ds

if __name__ == "__main__":
    pal, order = palette()
    if "--json" in sys.argv:
        dist = {m: {"closest": round(distances(pal, m)[0][0], 1),
                    "pair": distances(pal, m)[0][1:],
                    "apart15": round(100*sum(d[0] >= 15 for d in distances(pal, m))/len(distances(pal, m)))} for m in ("light", "dark")}
        print(json.dumps({"recipe": {"hues": HUES, "steps": STEPS, "roles": ROLES, "gamut": GAMUT},
                          "order": order, "distance": dist, "colours": pal}, indent=1, ensure_ascii=False))
        sys.exit()
    bad = []
    for c in pal:
        for m in ("light", "dark"):
            d = c[m]
            print("%-12s %-5s %-5s gr %s pa %s cg %s to %s | text on toolbar %.2f, text %.2f, text2 %.2f, needs on pane %.2f" % (
                c["name"], c["step"], m, d["ground"], d["pane"], d["chatGround"], d["toolOutputFill"],
                d["textOnGround"], d["minText"], d["minText2"], d["needsOnPane"]))
            if d["minText"] < 4.5 or d["minText2"] < 4.5: bad.append((c["name"], m))
    for m in ("light", "dark"):
        ds = distances(pal, m)
        print(m, "closest toolbars %.1f %s; pairs >= 15: %d%%" % (ds[0][0], ds[0][1:], 100*sum(d[0] >= 15 for d in ds)/len(ds)))
    print("order:", " > ".join(order))
    print("FAIL" if bad else "all text and text2 >= 4.5:1", bad)
