#!/usr/bin/env python3
"""Compare where colours change along a line in a build capture and its design target.

  scripts/edges.py <state> col X [col X ...] [row Y ...]

Build capture: build/ui/<state>.png (content below the toolbar). Target:
docs/design/build-handoff/screens/png/<state>@2x.png, shifted up by the toolbar (39 pt).
Prints edges (first point where colour changes) side by side, in points, flagging gaps over 1 pt.
"""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from pixels import read_png

TOP = 39  # toolbar 38 + its 1 pt border (findings F-10)
root = pathlib.Path(__file__).resolve().parent.parent
state = sys.argv[1]
build = read_png(root / f"build/ui/{state}.png")
target = read_png(root / f"docs/design/build-handoff/screens/png/{state}@2x.png")

def px(img, x, y):
    w, h, bpp, rows = img
    X, Y = int(x * 2), int(y * 2)
    if not (0 <= X < w and 0 <= Y < h): return None
    return tuple(rows[Y][X * bpp:X * bpp + 3])

def edges(img, mode, line, off):
    out, last = [], None
    n = 1440 if mode == "row" else 900 - TOP
    for i in range(n * 2):
        t = i / 2
        c = px(img, t, line + off) if mode == "row" else px(img, line, t + off)
        if c is None: break
        if last is not None and max(abs(a - b) for a, b in zip(c, last)) > 24:
            out.append((t, "#%02X%02X%02X" % c))
        last = c
    return out

args = sys.argv[2:]
for mode, v in zip(args[0::2], args[1::2]):
    v = float(v)
    b = edges(build, mode, v, 0)
    t = edges(target, mode, v, TOP)
    print(f"== {mode} {v:g}: build {len(b)} edges, target {len(t)}")
    for i in range(max(len(b), len(t))):
        bb = b[i] if i < len(b) else (None, "")
        tt = t[i] if i < len(t) else (None, "")
        d = "" if bb[0] is None or tt[0] is None else bb[0] - tt[0]
        flag = "  <<" if d == "" or abs(d) > 1 else ""
        print(f"  build {str(bb[0]):>7} {bb[1]:8}   target {str(tt[0]):>7} {tt[1]:8}   Δ {d}{flag}")
