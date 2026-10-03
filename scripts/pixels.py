#!/usr/bin/env python3
"""Sample colours and find edges in a PNG, with no dependencies (handoff §0.3: "sample the pixels").

  scripts/pixels.py IMG at X Y [X Y ...]       colour at points, in design points (2x images are halved)
  scripts/pixels.py IMG row Y                  where the colour changes along a horizontal line
  scripts/pixels.py IMG col X                  where the colour changes along a vertical line
  scripts/pixels.py IMG ... --offset-y 38      shift points (e.g. compare a content capture with a full target)

Coordinates are in points: for an @2x image, point (x, y) is pixel (2x, 2y).
"""
import struct
import sys
import zlib


def read_png(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos, idat, w = 8, b"", None
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
            assert depth == 8 and interlace == 0 and ctype in (2, 6), f"unsupported PNG (type {ctype}, depth {depth})"
            bpp = 3 if ctype == 2 else 4
        elif kind == b"IDAT":
            idat += body
        pos += 12 + n
    raw = zlib.decompress(idat)
    stride = w * bpp
    rows, prev = [], bytearray(stride)
    for y in range(h):
        f = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(bytes(line))
        prev = line
    return w, h, bpp, rows


def main():
    args = sys.argv[1:]
    off = 0
    if "--offset-y" in args:
        i = args.index("--offset-y"); off = float(args[i + 1]); del args[i:i + 2]
    path, mode, rest = args[0], args[1], [float(a) for a in args[2:]]
    w, h, bpp, rows = read_png(path)
    scale = 2 if w >= 2000 else 1

    def px(x, y):
        X, Y = int(x * scale), int((y + off) * scale)
        r = rows[Y][X * bpp:X * bpp + 3]
        return "#%02X%02X%02X" % tuple(r)

    if mode == "at":
        for x, y in zip(rest[0::2], rest[1::2]):
            print(f"({x:g},{y:g}) {px(x, y)}")
    elif mode in ("row", "col"):
        line = rest[0]
        n = int((w if mode == "row" else h) / scale)
        last, start = None, 0
        for t in [i / scale for i in range(int(n * scale))]:
            c = px(t, line) if mode == "row" else px(line, t - off)
            if c != last:
                if last is not None:
                    print(f"{start:7.1f}–{t:7.1f}  {last}")
                last, start = c, t
        print(f"{start:7.1f}–{n:7.1f}  {last}")


if __name__ == "__main__":
    main()
