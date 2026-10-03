#!/usr/bin/env python3
"""Where the ink (dark or saturated pixels) is in a region, in build vs target.

  scripts/ink.py <state> X Y W H [--light]

Prints the first and last rows and columns with ink, in content points, for both images.
Use it to compare text placement: a region around one line of text gives its ink box.
--light finds light ink on a dark background (the console).
"""
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from pixels import read_png
TOP = 39
root = pathlib.Path(__file__).resolve().parent.parent
args = [a for a in sys.argv[1:] if not a.startswith("--")]
light = "--light" in sys.argv
state = args[0]; x, y, w, h = (float(v) for v in args[1:5])

def box(img, oy):
    W, H, bpp, rows = img
    ys, xs = [], []
    for r in range(int(h * 2)):
        Y = int((y + oy) * 2) + r
        for c in range(int(w * 2)):
            X = int(x * 2) + c
            p = rows[Y][X * bpp:X * bpp + 3]
            lum = (p[0] * 299 + p[1] * 587 + p[2] * 114) / 1000
            if (lum > 140) if light else (lum < 150):
                ys.append(r / 2); xs.append(c / 2)
    if not ys: return None
    return (y + min(ys), y + max(ys) + 0.5, x + min(xs), x + max(xs) + 0.5)

b = box(read_png(root / f"build/ui/{state}.png"), 0)
t = box(read_png(root / f"docs/design/build-handoff/screens/png/{state}@2x.png"), TOP)
print(f"target ink y {t[0]:g}–{t[1]:g}  x {t[2]:g}–{t[3]:g}" if t else "target: no ink")
print(f"build  ink y {b[0]:g}–{b[1]:g}  x {b[2]:g}–{b[3]:g}" if b else "build: no ink")
if b and t: print(f"Δ top {b[0]-t[0]:+g}  bottom {b[1]-t[1]:+g}  left {b[2]-t[2]:+g}  right {b[3]-t[3]:+g}")
