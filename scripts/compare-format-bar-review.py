#!/usr/bin/env python3
"""Side-by-side of the review-in-bar captures and the approved board (DL-317), for looking at region by region.

    scripts/compare-format-bar-review.py [captures-dir]     → <captures-dir>/compare-<state>.png (mine above, target below)

The board (docs/design/markdown-toolbar-handoff/screens/png/review-in-bar@2x.png) is drawn at 2x; so are the captures. Each pair is
the right pane's top of the window: the tab strip, the bar and the first lines. Boxes are in the board's pixels.
"""
import sys, pathlib
from PIL import Image

root = pathlib.Path(__file__).resolve().parent.parent
cap = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else root / "build/format-bar-review")
board = Image.open(root / "docs/design/markdown-toolbar-handoff/screens/png/review-in-bar@2x.png").convert("RGB")
# capture name -> (board box (x0, y0, x1, y1) in board px, pane width in pt)
pairs = {
    "clean-light-460": ((96, 473, 1015, 800), 460),
    "marks-light-460": ((1096, 473, 2015, 800), 460),
    "suggest-light-360": ((2097, 473, 2816, 800), 360),
    "table-light-460": ((96, 1531, 1015, 1860), 460),
    "listening-dark-460": ((1096, 1531, 2015, 1860), 460),
    "menu-classic-460": ((2097, 1531, 3015, 2200), 460),
}
for name, (box, width) in pairs.items():
    f = cap / f"{name}.png"
    if not f.exists():
        print("missing", f); continue
    im = Image.open(f).convert("RGB")
    w, h = im.size
    pane = int(width * 2)
    mine = im.crop((w - pane, 80, w, 80 + (box[3] - box[1])))
    target = board.crop(box)
    out = Image.new("RGB", (max(mine.width, target.width), mine.height + target.height + 8), (255, 0, 255))
    out.paste(mine, (0, 0)); out.paste(target, (0, mine.height + 8))
    out.save(cap / f"compare-{name}.png")
    print("wrote", cap / f"compare-{name}.png")
