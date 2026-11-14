#!/usr/bin/env python3
"""Side-by-side of the formatting bar's captures and the approved board (DL-266), for looking at region by region.

    scripts/compare-format-bar.py [captures-dir]     → <captures-dir>/compare-<state>.png (mine above, target below)

The board (docs/design/markdown-toolbar-handoff/screens/png/bar@2x.png) is drawn at 2x; so are the captures. Each pair is the
right pane's top 120 pt: the tab strip, the bar and the first lines. Crop boxes are in the board's pixels.
"""
import sys, pathlib
from PIL import Image

root = pathlib.Path(__file__).resolve().parent.parent
cap = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else root / "build/format-bar")
board = Image.open(root / "docs/design/markdown-toolbar-handoff/screens/png/bar@2x.png").convert("RGB")
# state -> (capture name, board box (x0, y0, x1, y1) in board px, pane width in pt)
pairs = {
    "top-light": ("top-light", (1096, 397, 2015, 690), 460),
    "table-light": ("table-light", (96, 1458, 1015, 1750), 460),
    "table-narrow-light": ("table-narrow-light", (1096, 1458, 1815, 1750), 360),
    "listening-dark": ("listening-dark", (2096, 1458, 3015, 1750), 460),
    "nomic-classic": ("nomic-classic", (96, 2410, 1015, 2700), 460),
    "rest-light": ("rest-light", (96, 397, 1015, 690), 460),
}
for name, (capname, box, width) in pairs.items():
    f = cap / f"{capname}.png"
    if not f.exists():
        print("missing", f); continue
    im = Image.open(f).convert("RGB")
    w, h = im.size
    pane = int(width * 2)
    mine = im.crop((w - pane, 0, w, int(h * 0.0) + 300))
    # the capture's tab strip is at the window's top; the board's box starts at its tab strip too
    mine = im.crop((w - pane, 80, w, 80 + (box[3] - box[1])))
    target = board.crop(box)
    out = Image.new("RGB", (max(mine.width, target.width), mine.height + target.height + 8), (255, 0, 255))
    out.paste(mine, (0, 0)); out.paste(target, (0, mine.height + 8))
    out.save(cap / f"compare-{name}.png")
    print("wrote", cap / f"compare-{name}.png")
