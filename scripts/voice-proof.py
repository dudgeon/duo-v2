#!/usr/bin/env python3
"""Voice input's side-by-sides (docs/design/voice-input-handoff/proof/): each chat state's TARGET snippet cropped
from composer@2x.png over the BUILD's composer crop (build/ui/chat-voice-<state>-board.png), both at 2x.

  scripts/voice-proof.py            every state it has a build for
"""
import os
import sys
from PIL import Image, ImageDraw

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
target = Image.open(f"{root}/docs/design/voice-input-handoff/screens/png/composer@2x.png").convert("RGB")
out = f"{root}/docs/design/voice-input-handoff/proof"
os.makedirs(out, exist_ok=True)
K = 1.44  # the page's displayed coordinates (2000 wide) to the @2x file's pixels
L, R = (39, 983), (1039, 1960)

# state: (target column, target y range in displayed px, build crop y range in the 1360 x ~1720 board)
states = {
    "rest": (L, (170, 275), "field"),
    "hover": (R, (170, 275), "field"),
    "listening": (L, (595, 697), "field"),
    "holding": (R, (326, 352), "line"),
    "finishing": (R, (438, 462), "line"),
    "done": (L, (831, 933), "field"),
    "download": (R, (748, 776), "line"),
    "denied": (R, (883, 912), "line"),
    "restricted": (R, (1018, 1118), "field"),
    "nomic": (R, (1230, 1252), "line"),
    "nolang": (R, (1262, 1283), "line"),
    "stopped": (R, (1292, 1314), "line"),
    "lost": (R, (1322, 1345), "line"),
}
for name, (col, (y0, y1), kind) in states.items():
    p = f"{root}/build/ui/chat-voice-{name}-board.png"
    if not os.path.exists(p):
        continue
    b = Image.open(p).convert("RGB")
    t = target.crop((int(col[0] * K), int(y0 * K), int(col[1] * K), int(y1 * K)))
    by0, by1 = (b.height - 175, b.height) if kind == "field" else (b.height - 62, b.height - 8)
    bc = b.crop((0, by0, b.width, by1))
    w = max(t.width, bc.width)
    img = Image.new("RGB", (w, t.height + bc.height + 56), (255, 255, 255))
    d = ImageDraw.Draw(img)
    d.text((6, 4), f"TARGET composer.html: {name}", fill=(0, 0, 0))
    img.paste(t, (0, 20))
    d.text((6, t.height + 30), f"BUILD chat-voice-{name}", fill=(0, 0, 0))
    img.paste(bc, (0, t.height + 46))
    img.save(f"{out}/{name}-compare.png")
    bc.save(f"{out}/{name}-build.png")
    print(name)
