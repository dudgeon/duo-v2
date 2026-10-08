#!/usr/bin/env python3
"""Region numbers for the Word viewer's proof: how far a capture of the right pane is from its board,
region by region (the document's own text and fonts are exempt, so those regions aren't listed).

  python3 regions.py <board@2x.png> <capture-pane.png> <name>:<x>,<y>,<w>,<h>[:<shiftY>] ...

Coordinates are design points on the board (460x800, with its own 1 pt outer border; the capture is the pane
without it, so the capture is read 1 pt up and left). Each region is compared at the shift (up to SHIFT pt down or up, default 8, and 2 across) that fits best, and reported as the mean absolute difference per channel (0 to 255)
at that shift, and the shift: a region the same but placed 2 pt differently reads as 0.0 at shift 2.
"""
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[4] / "scripts"))
from pixels import read_png

import os
RANGE = int(os.environ.get("SHIFT", "8"))   # points of vertical shift to search: SHIFT=60 for a region the document's own text moved
bw, bh, bb, brows = read_png(sys.argv[1])
cw, ch, cb, crows = read_png(sys.argv[2])

def px(rows, bpp, x, y):
    return rows[y][x * bpp:x * bpp + 3]

def diff(x, y, w, h, dx, dy):
    tot = n = 0
    for yy in range(int(y * 2), int((y + h) * 2), 2):
        for xx in range(int(x * 2), int((x + w) * 2), 2):
            cx, cy = xx - 2 + dx * 2, yy - 2 + dy * 2     # board pixel -> capture pixel (1 pt outer border)
            if not (0 <= cx < cw and 0 <= cy < ch): tot += 255 * 3; n += 3; continue
            a, b = px(brows, bb, xx, yy), px(crows, cb, cx, cy)
            tot += sum(abs(a[i] - b[i]) for i in range(3)); n += 3
    return tot / n

for spec in sys.argv[3:]:
    name, box, *rest = spec.split(":")
    x, y, w, h = (float(v) for v in box.split(","))
    best = min(((diff(x, y, w, h, dx, dy), dx, dy) for dx in (-2, -1, 0, 1, 2) for dy in range(-RANGE, RANGE + 1)), key=lambda t: t[0])
    print(f"{name:28s} at 0: {diff(x, y, w, h, 0, 0):6.2f}   best {best[0]:6.2f} at shift ({best[1]:+d}, {best[2]:+d}) pt")
