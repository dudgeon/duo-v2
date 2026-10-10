#!/usr/bin/env python3
"""Measures the chips on a capture and on the target (DL-168 proof): for the rows in a window, the bounding box of
what isn't the ground, and where each chip's border and fill sit along its middle row.

  scripts/chip-measure.py IMG Y0 Y1 [X0 [X1]]     pixel coordinates of an @2x image
"""
import importlib.util, sys
spec = importlib.util.spec_from_file_location("px", __file__.replace("chip-measure.py", "pixels.py"))
px = importlib.util.module_from_spec(spec); spec.loader.exec_module(px)
img, y0, y1 = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
x0 = int(sys.argv[4]) if len(sys.argv) > 4 else 0
x1 = int(sys.argv[5]) if len(sys.argv) > 5 else 10**6
w, h, bpp, rows = px.read_png(img)
x1 = min(x1, w)
def at(x, y): r = rows[y]; return tuple(r[x * bpp:x * bpp + 3])
bg = at(2, y0)
xs, ys = [], []
for y in range(y0, y1):
    for x in range(x0, x1):
        if at(x, y) != bg: xs.append(x); ys.append(y)
if not xs: print("nothing drawn"); sys.exit()
print(f"ground #{''.join('%02X' % c for c in bg)}; drawn x {min(xs)}..{max(xs)} y {min(ys)}..{max(ys)} (px)")
# the chips' left/right borders along the middle row: runs of the border colours
mid = (min(ys) + max(ys)) // 2
runs, cur = [], None
for x in range(x0, x1):
    c = at(x, mid)
    if c != bg and c != (255, 255, 255) and c != (0xE9, 0xEC, 0xEF):
        if cur is None: cur = [x, x, c]
        else: cur[1] = x
    else:
        if cur and cur[1] - cur[0] <= 1: runs.append((cur[0], '#%02X%02X%02X' % cur[2]))
        cur = None
print("border-ish verticals on y", mid, ":", ", ".join(f"{x}:{c}" for x, c in runs[:24]))
# vertical extent of each chip border at its centre column
