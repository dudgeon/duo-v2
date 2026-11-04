#!/usr/bin/env python3
"""pixdiff.py <olddir> <newdir> <outdir> [--tol N]: compare same-named PNGs; write <name>-cmp.png (old | new | diff)
for every pair that differs, and print one line per file: name, size, % pixels differing, bounding box (points)."""
import sys, os
from PIL import Image, ImageChops

args = sys.argv[1:]
tol = 8
if "--tol" in args:
    i = args.index("--tol"); tol = int(args[i + 1]); del args[i:i + 2]
old, new, out = args
os.makedirs(out, exist_ok=True)
names = sorted(set(f for f in os.listdir(old) if f.endswith(".png") and "-cmp" not in f) | set(f for f in os.listdir(new) if f.endswith(".png") and "-cmp" not in f))
for n in names:
    po, pn = os.path.join(old, n), os.path.join(new, n)
    if not (os.path.exists(po) and os.path.exists(pn)):
        print(f"{n}: MISSING in {'old' if not os.path.exists(po) else 'new'}")
        continue
    a, b = Image.open(po).convert("RGB"), Image.open(pn).convert("RGB")
    if a.size != b.size:
        print(f"{n}: SIZE differs old={a.size} new={b.size}")
        w, h = min(a.size[0], b.size[0]), min(a.size[1], b.size[1])
        a, b = a.crop((0, 0, w, h)), b.crop((0, 0, w, h))
    d = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v > tol else 0)
    bbox = d.getbbox()
    cnt = sum(1 for v in d.getdata() if v)
    pct = 100.0 * cnt / (a.size[0] * a.size[1])
    sc = 2 if a.size[0] >= 2000 else 1
    if bbox:
        box = tuple(int(v / sc) for v in bbox)
        w, h = a.size
        comp = Image.new("RGB", (w * 3 + 20, h), (255, 0, 255))
        comp.paste(a, (0, 0)); comp.paste(b, (w + 10, 0)); comp.paste(d.convert("RGB"), (2 * w + 20, 0))
        comp.save(os.path.join(out, n.replace(".png", "-cmp.png")))
        print(f"{n}: DIFF {pct:.3f}% bbox={box}")
    else:
        print(f"{n}: identical")
