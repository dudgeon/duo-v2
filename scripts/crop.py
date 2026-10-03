#!/usr/bin/env python3
"""Crop one region from a build capture and its target, side by side with their difference.

  scripts/crop.py <state> X Y W H [out.png]

Coordinates are design points in the content area (below the 39 pt toolbar). Writes
build/ui/crop-<state>-X-Y.png at 2x: TARGET | BUILD | DIFFERENCE (black = identical).
"""
import pathlib, struct, sys, zlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from pixels import read_png

TOP = 39
root = pathlib.Path(__file__).resolve().parent.parent
state = sys.argv[1]
x, y, w, h = (float(v) for v in sys.argv[2:6])
out = pathlib.Path(sys.argv[6]) if len(sys.argv) > 6 else root / f"build/ui/crop-{state}-{int(x)}-{int(y)}.png"
b = read_png(root / f"build/ui/{state}.png")
t = read_png(root / f"docs/design/build-handoff/screens/png/{state}@2x.png")

def region(img, oy):
    W, H, bpp, rows = img
    X0, Y0, PW, PH = int(x * 2), int((y + oy) * 2), int(w * 2), int(h * 2)
    res = []
    for r in range(PH):
        yy = Y0 + r
        line = bytearray()
        for c in range(PW):
            xx = X0 + c
            if 0 <= xx < W and 0 <= yy < H:
                line += rows[yy][xx * bpp:xx * bpp + 3]
            else:
                line += b"\x40\x40\x40"
        res.append(line)
    return res

rt, rb = region(t, TOP), region(b, 0)
gap = b"\x80\x80\x80" * 8
rows = []
for a, c in zip(rt, rb):
    d = bytes(abs(p - q) for p, q in zip(a, c))
    rows.append(b"\x00" + bytes(a) + gap + bytes(c) + gap + d)
W = (len(rt[0]) // 3) * 3 + 16
raw = b"".join(rows)
def chunk(k, data):
    return struct.pack(">I", len(data)) + k + data + struct.pack(">I", zlib.crc32(k + data) & 0xFFFFFFFF)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, len(rows), 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")
out.write_bytes(png)
print(out)
