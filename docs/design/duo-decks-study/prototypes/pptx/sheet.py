"""Render PDF pages to a contact sheet PNG: sheet.py <pdf> <out.png> [cols] [page-width-px] [first] [last]"""
import sys, fitz
from PIL import Image
pdf, out = sys.argv[1], sys.argv[2]
cols = int(sys.argv[3]) if len(sys.argv) > 3 else 5
pw = int(sys.argv[4]) if len(sys.argv) > 4 else 400
doc = fitz.open(pdf)
first = int(sys.argv[5]) if len(sys.argv) > 5 else 1
last = int(sys.argv[6]) if len(sys.argv) > 6 else doc.page_count
imgs = []
for i in range(first - 1, last):
    pg = doc[i]
    z = pw / pg.rect.width
    pix = pg.get_pixmap(matrix=fitz.Matrix(z, z))
    imgs.append(Image.frombytes('RGB', (pix.width, pix.height), pix.samples))
w, h = imgs[0].size
rows = (len(imgs) + cols - 1) // cols
sheet = Image.new('RGB', (cols * (w + 8) + 8, rows * (h + 8) + 8), (120, 120, 120))
for n, im in enumerate(imgs):
    sheet.paste(im, (8 + (n % cols) * (w + 8), 8 + (n // cols) * (h + 8)))
sheet.save(out, optimize=True)
print(out, sheet.size, doc.page_count)
