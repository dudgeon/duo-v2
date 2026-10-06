#!/usr/bin/env python3
"""Crops a chat-mode capture to its board (chat-mode-handoff): the console pane, or the window.

  scripts/chat-crop.py <capture.png> <out.png> X Y W H

Coordinates are design points in the content capture (below the toolbar), which is 2x.
"""
import pathlib, struct, sys, zlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from pixels import read_png

src, out = sys.argv[1], pathlib.Path(sys.argv[2])
x, y, w, h = (int(float(v) * 2) for v in sys.argv[3:7])
W, H, bpp, rows = read_png(src)
lines = []
for r in range(h):
    yy = y + r
    line = bytearray()
    for c in range(w):
        xx = x + c
        line += rows[yy][xx * bpp:xx * bpp + 3] if 0 <= xx < W and 0 <= yy < H else b"\x40\x40\x40"
    lines.append(b"\x00" + bytes(line))
def chunk(k, data):
    return struct.pack(">I", len(data)) + k + data + struct.pack(">I", zlib.crc32(k + data) & 0xFFFFFFFF)
out.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(b"".join(lines), 6)) + chunk(b"IEND", b""))
print(out)
