#!/usr/bin/env python3
"""One image from check-motion.sh's frames: a region of each, in time order, motion above and
Reduce Motion below, so a motion can be looked at as a filmstrip (DL-130).

  scripts/filmstrip.py build/motion/<name> X Y W H [out.png]

Coordinates are design points in the content area. Frames are build/motion/<name>/{motion,reduce}-<ms>.png.
Writes <dir>/strip.png (or out.png) at 2x, frames separated by a 4 px grey gap.
"""
import pathlib
import re
import struct
import subprocess
import sys
import tempfile
import zlib

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from pixels import read_png  # noqa: E402


def write_png(path, w, h, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")
    pathlib.Path(path).write_bytes(data)


def main():
    if len(sys.argv) < 6:
        sys.exit(__doc__)
    d = pathlib.Path(sys.argv[1])
    x, y, w, h = (int(float(v) * 2) for v in sys.argv[2:6])
    out = pathlib.Path(sys.argv[6]) if len(sys.argv) > 6 else d / "strip.png"
    gap = 8
    lanes = []
    for mode in ("motion", "reduce"):
        frames = sorted(d.glob(f"{mode}-[0-9]*.png"), key=lambda p: int(re.search(r"-(\d+)\.png$", p.name).group(1)))
        if frames:
            lanes.append(frames)
    if not lanes:
        sys.exit(f"no frames in {d}")
    cols = max(len(l) for l in lanes)
    W, H = cols * w + (cols - 1) * gap, len(lanes) * h + (len(lanes) - 1) * gap
    canvas = [bytearray([200, 200, 200] * W) for _ in range(H)]
    for li, frames in enumerate(lanes):
        for fi, f in enumerate(frames):
            # Crop with sips first: decoding a whole 2880-wide frame in Python is slow. (sips centres
            # the crop when the offset is 0,0, so it's at least 1.)
            with tempfile.TemporaryDirectory() as tmp:
                c = pathlib.Path(tmp) / "c.png"
                subprocess.run(["sips", "-s", "format", "png", "--cropOffset", str(max(y, 1)), str(max(x, 1)), "-c", str(h), str(w), str(f), "--out", str(c)],
                               check=True, capture_output=True)
                cw, ch, bpp, px = read_png(c)
            for r in range(min(h, ch)):
                line = px[r]
                src = bytearray()
                for i in range(min(w, cw)):
                    src += line[i * bpp:i * bpp + 3]
                dst_x = fi * (w + gap) * 3
                canvas[li * (h + gap) + r][dst_x:dst_x + len(src)] = src
    write_png(out, W, H, canvas)
    print(f"{out}  ({' | '.join(p.stem for p in lanes[0])}; Reduce Motion below)")


main()
