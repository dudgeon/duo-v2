#!/usr/bin/env python3
"""Derive Duo's window base colours (Q-441, F-547) and check their contrast.

Every colour is one OKLCH recipe at a different hue:
  hue_i  = H0 + i * STEP   (i = 0..N-1, an arc that skips orange and red)
  tier   = i % 2           (neighbouring hues alternate a lighter, softer tier A
                            and a deeper, richer tier B, so neighbours differ
                            in lightness and chroma, not only hue)
  role   = (L, C) from ROLES[mode][role][tier]
Run:  python3 window_palette.py            -> table
      python3 window_palette.py --json     -> palette.json (tokens-ready)
To add colours later, see ADDING in the README next to this file.
"""
import json, math, sys

H0, STEP, N = 92.0, 22.5, 12          # hues 92 .. 339.5
NAMES = ["Sand", "Pear", "Moss", "Sage", "Mint", "Teal",
         "Sky", "Cornflower", "Iris", "Lilac", "Orchid", "Mauve"]
# Order new windows get them in: step 5 of 12 (coprime, visits all twelve,
# each new colour 112.5 deg from the last), starting at Sky as 4a did.
ORDER_STEP, ORDER_START = 5, 6

# (L, C) per role, per tier [A, B]
ROLES = {
 "light": {
  "ground":         [(0.925, 0.026), (0.905, 0.036)],
  "pane":           [(0.975, 0.010), (0.968, 0.014)],
  "chatGround":     [(0.925, 0.026), (0.905, 0.036)],   # = ground, as in the base light scheme
  "toolOutputFill": [(0.955, 0.016), (0.942, 0.022)],
  "swatch":         [(0.740, 0.085), (0.640, 0.100)],
 },
 "dark": {
  "ground":         [(0.215, 0.022), (0.235, 0.030)],
  "pane":           [(0.240, 0.020), (0.260, 0.026)],
  "chatGround":     [(0.180, 0.016), (0.195, 0.022)],
  "toolOutputFill": [(0.215, 0.022), (0.235, 0.030)],   # = ground, as in the base dark scheme
  "swatch":         [(0.700, 0.085), (0.600, 0.100)],
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

def palette():
    out = []
    for i in range(N):
        h = H0 + i*STEP; t = i % 2
        c = {"id": NAMES[i].lower(), "name": NAMES[i], "hue": h, "tier": "AB"[t]}
        for mode, roles in ROLES.items():
            c[mode] = {}
            for role, tiers in roles.items():
                hx, ok = hexc(*tiers[t], h)
                assert ok, (NAMES[i], mode, role, "out of sRGB gamut")
                c[mode][role] = hx
            surf = [c[mode][r] for r in ("ground", "pane", "chatGround", "toolOutputFill")]
            c[mode]["minText"] = round(min(cr(TEXT[mode]["text"], s) for s in surf), 2)
            c[mode]["minText2"] = round(min(cr(TEXT[mode]["text2"], s) for s in surf), 2)
            c[mode]["needsOnPane"] = round(cr(TEXT[mode]["needsYou"], c[mode]["pane"]), 2)
            c[mode]["needsOnGround"] = round(cr(TEXT[mode]["needsYou"], c[mode]["ground"]), 2)
        out.append(c)
    order = [(ORDER_START + k*ORDER_STEP) % N for k in range(N)]
    return out, [out[i]["id"] for i in order]

if __name__ == "__main__":
    pal, order = palette()
    nh = hex_to_oklch(TEXT["light"]["needsYou"])[2]
    nhd = hex_to_oklch(TEXT["dark"]["needsYou"])[2]
    if "--json" in sys.argv:
        print(json.dumps({"recipe": {"H0": H0, "STEP": STEP, "N": N, "roles": ROLES,
                          "orderStep": ORDER_STEP, "orderStart": ORDER_START},
                          "needsYouHue": [round(nh, 1), round(nhd, 1)],
                          "order": order, "colours": pal}, indent=1))
        sys.exit()
    print("needs-you hue light %.1f dark %.1f; arc %.1f..%.1f" % (nh, nhd, H0, H0+(N-1)*STEP))
    bad = []
    for c in pal:
        for m in ("light", "dark"):
            d = c[m]
            print("%-11s %s %5.1f %-5s gr %s pa %s cg %s to %s sw %s | text %.2f text2 %.2f needs pane %.2f ground %.2f" % (
                c["name"], c["tier"], c["hue"], m, d["ground"], d["pane"], d["chatGround"], d["toolOutputFill"], d["swatch"],
                d["minText"], d["minText2"], d["needsOnPane"], d["needsOnGround"]))
            if d["minText"] < 4.5 or d["minText2"] < 4.5: bad.append((c["name"], m))
    print("order:", " > ".join(order))
    print("FAIL" if bad else "all text and text2 >= 4.5:1", bad)
