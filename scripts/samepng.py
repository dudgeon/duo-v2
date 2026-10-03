#!/usr/bin/env python3
"""Count differing pixels between two PNGs of the same size: scripts/samepng.py a.png b.png"""
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from pixels import read_png
a, b = read_png(sys.argv[1]), read_png(sys.argv[2])
if a[:2] != b[:2]: sys.exit(f"sizes differ: {a[:2]} vs {b[:2]}")
w, h, bpa, ra = a; _, _, bpb, rb = b
diff, ys = 0, []
for y in range(h):
    if ra[y] == rb[y] and bpa == bpb: continue
    for x in range(w):
        if ra[y][x*bpa:x*bpa+3] != rb[y][x*bpb:x*bpb+3]:
            diff += 1; ys.append(y)
print(f"{diff} pixels differ" + (f" (rows {min(ys)/2:g}–{max(ys)/2:g} pt)" if diff else ""))
