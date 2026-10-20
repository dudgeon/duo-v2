#!/usr/bin/env python3
"""TARGET | BUILD images for the trust notice (DL-229): the boards are presentation boards, not app windows, so
compare.sh can't line them up; this crops each drawn region from the board PNG (screens/png, 2x) and the matching
region from the build's capture, scales both to one width, and stacks them side by side.
  scripts/trust-compare.py [build/ui]"""
import sys
from PIL import Image, ImageDraw
ui = sys.argv[1] if len(sys.argv) > 1 else "build/ui"
png = "docs/design/trust-notice-handoff/screens/png/"
K = 1.56  # the boards' PNGs are 3120 wide, the viewer shows 2000
def board(name, box):  # box in the 2000-wide view
    im = Image.open(png + name)
    return im.crop(tuple(int(v * K) for v in box))
def app(name, frac):  # frac: (x0, y0, x1, y1) fractions of the capture; negative y = from the bottom in px
    im = Image.open(f"{ui}/{name}.png"); w, h = im.size
    x0, y0, x1, y1 = frac
    return im.crop((int(w * x0), int(y0 if y0 >= 0 else h + y0), int(w * x1), int(y1 if y1 > 0 else h + y1)))
def pair(out, t, b, label):
    width = 1100
    def fit(im): return im.resize((width, max(1, int(im.height * width / im.width))))
    t, b = fit(t), fit(b)
    pad = 24
    canvas = Image.new("RGB", (width * 2 + 3 * pad, max(t.height, b.height) + 2 * pad + 20), (243, 244, 246))
    d = ImageDraw.Draw(canvas)
    d.text((pad, 4), "TARGET  " + label, fill=(60, 60, 60)); d.text((width + 2 * pad, 4), "BUILD", fill=(60, 60, 60))
    canvas.paste(t, (pad, pad + 20)); canvas.paste(b, (width + 2 * pad, pad + 20))
    canvas.save(f"{ui}/{out}.png"); print(out)
for w in ("1280x800", "1440x900"):
    # the console bar: a 40-pt strip under the terminal, over the pane's width
    px = (0.234, 0.641) if w == "1280x800" else (0.208, 0.68)   # the console pane's columns in the window
    barfrac = (px[0], -42 * 2, px[1], 0)
    pair(f"trust-offer-{w}-compare", board("01-where@2x.png", (52, 632, 974, 685)), app(f"trust-offer-{w}", barfrac), "01 where, Q2 A")
    pair(f"trust-trusted-{w}-compare", board("03-after@2x.png", (52, 506, 974, 558)), app(f"trust-trusted-{w}", barfrac), "03 after, Q3 A")
    pair(f"trust-failed-{w}-compare", board("03-after@2x.png", (52, 860, 974, 911)), app(f"trust-failed-{w}", barfrac), "03 failure")
    pair(f"trust-sheet-{w}-compare", board("02-action@2x.png", (143, 277, 857, 851)), app(f"trust-sheet-{w}", ((0.32, 0, 0.68, 0.53) if w == "1280x800" else (0.33, 0, 0.67, 0.45))), "02 sheet")
    pair(f"trust-chat-{w}-compare", board("01-where@2x.png", (52, 1185, 846, 1345)), app(f"trust-chat-{w}", (px[0], -150 * 2, px[1], 0)), "01 chat")
