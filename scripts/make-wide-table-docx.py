# A Word document with a table wider than the right pane (460 px), for the wide-table board of
# scripts/check-docx.sh and for `duo2 doc screenshot` (Q-258, F-378).
#   python3 -I scripts/make-wide-table-docx.py <out.docx>
import sys, zipfile
out = sys.argv[1]
W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
def cell(w, t, bold=False):
    r = '<w:rPr><w:b/></w:rPr>' if bold else ''
    return f'<w:tc><w:tcPr><w:tcW w:w="{w}" w:type="dxa"/></w:tcPr><w:p><w:r>{r}<w:t>{t}</w:t></w:r></w:p></w:tc>'
def para(t, style=None):
    s = f'<w:pPr><w:pStyle w:val="{style}"/></w:pPr>' if style else ''
    return f'<w:p>{s}<w:r><w:t>{t}</w:t></w:r></w:p>'
cols = [2000, 2000, 2000, 2400, 2400]   # 10800 twips = 540 pt, wider than a 460 px pane
rows = [("Bed", "Crop", "Planted", "Watch for", "Volunteer"), ("North 1", "Beans", "April 12", "Slugs", "Dana"), ("North 2", "Squash", "April 19", "Mildew", "Priya"), ("South 1", "Kale", "May 3", "Aphids", "Marcus")]
tbl = '<w:tbl><w:tblPr><w:tblW w:w="10800" w:type="dxa"/><w:tblBorders>' + ''.join(f'<w:{s} w:val="single" w:sz="4" w:color="888888"/>' for s in ['top', 'left', 'bottom', 'right', 'insideH', 'insideV']) + '</w:tblBorders><w:tblLayout w:type="fixed"/></w:tblPr><w:tblGrid>' + ''.join(f'<w:gridCol w:w="{c}"/>' for c in cols) + '</w:tblGrid>'
for i, r in enumerate(rows):
    tbl += '<w:tr>' + ''.join(cell(w, t, i == 0) for w, t in zip(cols, r)) + '</w:tr>'
tbl += '</w:tbl>'
body = para("Garden plan", "Title") + para("Beds and crops", "Heading1") + para("The volunteers planted the north beds in April. The table below lists each bed with its crop, the planting date, what to watch for and who looks after it. This paragraph is long enough to wrap onto several lines at the width of the pane, which is the point: text flows at the pane while the table keeps its own widths.") + tbl + para("Volunteers water on Saturdays. Anything else goes in the notes below.")
for i in range(40):
    body += para(f"Note {i + 1}: a line to make the document taller than one screen so that the full page capture has more than one piece to join.")
body += '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
doc = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {W}><w:body>{body}</w:body></w:document>'
ct = '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'
rels = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('[Content_Types].xml', ct)
    z.writestr('_rels/.rels', rels)
    z.writestr('word/document.xml', doc)
