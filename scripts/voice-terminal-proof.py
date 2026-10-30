#!/usr/bin/env python3
"""The terminal mic's pixel proof (docs/design/voice-input-handoff/proof/terminal-*): for each shot the harness's
`voice-shot:<png>` wrote (<png> with the mic, <png>.bare.png without), measure that the mic's rect covers only the
rule's pixels, that it draws nothing outside its rect, and that it is absent on the hidden cases.

  scripts/voice-terminal-proof.py <dir with s-<case>.png ...>   (cases: name=label pairs below)
Writes proof/terminal-<case>-compare.png (TARGET panel over BUILD crop) and prints the numbers.
"""
import os
import sys
from PIL import Image, ImageChops, ImageDraw

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = sys.argv[1] if len(sys.argv) > 1 else "/tmp/vi-t"
out = f"{root}/docs/design/voice-input-handoff/proof"
os.makedirs(out, exist_ok=True)
target = Image.open(f"{root}/docs/design/voice-input-handoff/screens/png/terminal@2x.png").convert("RGB")
K = 1.44
panels = {  # displayed coordinates of terminal.html's four panels
    "rest": (39, 149, 975, 357), "listening": (1025, 149, 1961, 357),
    "grows": (39, 525, 975, 741), "question": (1025, 525, 1961, 690),
}
# case: (label, target panel, mic expected)
cases = {
    "a-219-idle": ("2.1.219 empty box", "rest", True),
    "b-284-slash": ("2.1.284 slash menu open", "rest", True),
    "c-paste": ("2.1.2xx pasted text", "grows", True),
    "d-284-perm": ("2.1.284 permission question", "question", False),
    "e-296-idle": ("2.1.296 empty box", "rest", True),
    "f-296-slash": ("2.1.296 slash menu", "rest", True),
    "g-296-effort": ("2.1.296 /effort picker", "question", False),
    "h-edge": ("text to the right edge, two-line box", "grows", True),
    "j-listen": ("listening: the mic filled, a phrase already in the prompt", "listening", True),
    "i1": ("scrolled to the bottom (box in view)", "rest", True),
    "i2": ("scrolled back 3 lines (box in view)", "question", False),
}
BG = None


def ink(img, box):
    """Pixels in box that differ from the console colour."""
    global BG
    px = img.load()
    n = []
    for y in range(box[1], box[3]):
        for x in range(box[0], box[2]):
            p = px[x, y]
            if sum(abs(p[i] - BG[i]) for i in range(3)) > 40:
                n.append((x, y))
    return n


rows = []
for name, (label, panel, want) in cases.items():
    key = name.split("-")[0] if name.startswith("i") else name
    f = f"{src}/s-{name if not name.startswith('i') else name}.png"
    if not os.path.exists(f):
        continue
    with_mic = Image.open(f).convert("RGB")
    bare = Image.open(f + ".bare.png").convert("RGB")
    BG = bare.getpixel((bare.width - 5, bare.height - 5))
    diff = ImageChops.difference(with_mic, bare).convert("L").point(lambda v: 255 if v > 8 else 0)
    bbox = diff.getbbox()
    shown = bbox is not None
    line = f"{name:14} {label:42} mic {'shown' if shown else 'hidden'} (wanted {'shown' if want else 'hidden'}) {'OK' if shown == want else 'FAIL'}"
    if shown:
        # The patch is `console`, so only its glyph differs from the bare shot: the rect is the glyph's centre, 24 x 18 pt.
        cx, cyy = (bbox[0] + bbox[2]) // 2, (bbox[1] + bbox[3]) // 2
        bbox = (cx - 24, cyy - 18, cx + 24, cyy + 18)
        w, h = (bbox[2] - bbox[0]) / 2, (bbox[3] - bbox[1]) / 2
        # Ink in the bare terminal under the mic's rect: only the rule (rows that are ink across ~the whole rect).
        pts = ink(bare, bbox)
        by_row = {}
        for x, y in pts:
            by_row.setdefault(y, []).append(x)
        width = bbox[2] - bbox[0]
        rule_rows = [y for y, xs in by_row.items() if len(xs) >= 0.9 * width]
        stray = [(x, y) for x, y in pts if y not in rule_rows]
        # The rule's right end: the last ink pixel on the rule row, to the right of the rect.
        ry = rule_rows[0] if rule_rows else (bbox[1] + bbox[3]) // 2
        bpx = bare.load()
        end = max((x for x in range(bare.width) if sum(abs(bpx[x, ry][i] - BG[i]) for i in range(3)) > 40), default=0)
        gap = (end + 1 - bbox[2]) / 2
        cy = (bbox[1] + bbox[3]) / 2
        line += (f"\n               rect {w:.0f}x{h:.0f} pt at ({bbox[0] / 2:.0f},{bbox[1] / 2:.0f}); rule rows under it {len(rule_rows)}, stray ink pixels under it {len(stray)}; "
                 f"mic centre {abs(cy - (min(rule_rows) + max(rule_rows) + 1) / 2) / 2 if rule_rows else -1:.1f} pt from the rule's centre; right edge {gap:.1f} pt from the rule's end")
        if stray:
            line += " FAIL"
        crop = with_mic.crop((max(0, bbox[0] - 760), max(0, bbox[1] - 330), min(with_mic.width, bbox[2] + 180), min(with_mic.height, bbox[3] + 90)))
    else:
        crop = with_mic.crop((0, 0, 1020, 420))
    print(line)
    x0, y0, x1, y1 = panels[panel]
    t = target.crop((int(x0 * K), int(y0 * K), int(x1 * K), int(y1 * K)))
    img = Image.new("RGB", (max(t.width, crop.width), t.height + crop.height + 44), (255, 255, 255))
    d = ImageDraw.Draw(img)
    d.text((6, 4), f"TARGET terminal.html panel: {panel}", fill=(0, 0, 0))
    img.paste(t, (0, 18))
    d.text((6, t.height + 24), f"BUILD {name}: {label}", fill=(0, 0, 0))
    img.paste(crop, (0, t.height + 40))
    img.save(f"{out}/terminal-{name}-compare.png")
    crop.save(f"{out}/terminal-{name}-build.png")
