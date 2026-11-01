"""Builds samples/import/grower-update.pptx: a small hand-made-looking deck to import (Duo Decks P2).

Made from the Northwind sample pack's pptx so it has real layouts, then slides added the way people
make them: some on real layouts (placeholders), some on Blank with loose text boxes.

  1  Title layout (ctrTitle, subTitle)
  2  Title + Bullets layout, with speaker notes
  3  Blank, loose boxes: a "big number" slide, a decoration bar
  4  Blank, the same slide a few points off, other numbers
  5  Blank, the same again, with an extra footnote box, and a modern comment
  6  Two Column layout
  7  Blank, a chart and a title box
  8  Blank, a title and a stray "Draft" box that maps nowhere, with notes
  A legacy comment is on slide 3.

usage: python gen_import_fixture.py northwind.pptx out.pptx   (needs python-pptx; run with uv or a venv)
"""
import sys, zipfile, shutil, re
from pptx import Presentation
from pptx.util import Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.dml import MSO_THEME_COLOR
from pptx.enum.shapes import MSO_SHAPE
from pptx.chart.data import CategoryChartData
from pptx.enum.chart import XL_CHART_TYPE

src, out = sys.argv[1], sys.argv[2]
tmp = out + '.tmp'
prs = Presentation(src)
layouts = {l.name: l for l in prs.slide_layouts}


def box(slide, name, x, y, w, h, text, size, bold=False, color=None):
    tb = slide.shapes.add_textbox(Pt(x), Pt(y), Pt(w), Pt(h))
    tb.name = name
    tf = tb.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]
    r = p.add_run()
    r.text = text
    r.font.size = Pt(size)
    r.font.bold = bold
    if color:
        r.font.color.theme_color = color
    return tb


def bar(slide, x, y, w, h):
    s = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Pt(x), Pt(y), Pt(w), Pt(h))
    s.name = 'Accent bar'
    s.fill.solid()
    s.fill.fore_color.theme_color = MSO_THEME_COLOR.ACCENT_2
    s.line.fill.background()
    return s


def big_number(title, value, label, context, dx=0, dy=0, footnote=None):
    s = prs.slides.add_slide(layouts['Blank'])
    bar(s, 36 + dx, 150 + dy, 6, 120)
    box(s, 'Title', 48 + dx, 40 + dy, 864, 50, title, 28, True)
    box(s, 'Value', 60 + dx, 150 + dy, 400, 120, value, 80, True, MSO_THEME_COLOR.ACCENT_1)
    box(s, 'Label', 60 + dx, 280 + dy, 700, 30, label, 18)
    box(s, 'Context', 60 + dx, 330 + dy, 760, 50, context, 16)
    if footnote:
        box(s, 'Footnote', 60 + dx, 470 + dy, 800, 20, footnote, 11)
    return s


# 1
s = prs.slides.add_slide(layouts['Title'])
s.shapes.title.text = 'Grower update, September'
s.placeholders[1].text = 'Field team, Northwind Labs'
# 2
s = prs.slides.add_slide(layouts['Title + Bullets'])
s.shapes.title.text = 'What we ran'
tf = s.placeholders[1].text_frame
tf.text = 'Three farms, 412 rows'
for t in ['Two weeks of unattended runs', 'Wet weather in week two']:
    tf.add_paragraph().text = t
s.notes_slide.notes_text_frame.text = 'Mention the three farms by name.'
# 3, 4, 5
s3 = big_number('Unattended rows', '86%', 'of rows finished with no one stepping in', 'Up from 61% in the spring trial, over 412 rows on three farms.')
big_number('Interventions per day', '3.2', 'on average, down from 9', 'Mostly gripper jams in the first week.', dx=3, dy=1)
s5 = big_number('Battery swaps', '1.4', 'per robot per shift', 'Plan for two spares per ten robots.', dx=6, dy=-3,
                footnote='Source: trial logs, three farms, Aug to Sep')
# 6
s = prs.slides.add_slide(layouts['Two Column'])
s.shapes.title.text = 'Spring and autumn'
s.placeholders[1].text_frame.text = 'Dry ground'
s.placeholders[2].text_frame.text = 'Wet ground'
# 7
s = prs.slides.add_slide(layouts['Blank'])
box(s, 'Title', 48, 40, 864, 50, 'Rows per day', 28, True)
cd = CategoryChartData()
cd.categories = ['Week 1', 'Week 2', 'Week 3']
cd.add_series('Rows', (120, 180, 240))
s.shapes.add_chart(XL_CHART_TYPE.COLUMN_CLUSTERED, Pt(60), Pt(120), Pt(800), Pt(360), cd).name = 'Rows chart'
# 8
s = prs.slides.add_slide(layouts['Blank'])
box(s, 'Title', 48, 40, 864, 50, 'What comes next', 28, True)
box(s, 'Stamp', 700, 480, 220, 24, 'Draft - not for circulation', 12)
s.notes_slide.notes_text_frame.text = 'Ask about the autumn dates.'
prs.save(tmp)

# comments, added by hand to the zip: legacy on slide 3, modern (threaded) on slide 5
P = 'http://schemas.openxmlformats.org/presentationml/2006/main'
RT = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
zin = zipfile.ZipFile(tmp)
parts = {n: zin.read(n) for n in zin.namelist()}
zin.close()


def add_rel(part, rid, typ, target):
    rp = part.rsplit('/', 1)[0] + '/_rels/' + part.rsplit('/', 1)[1] + '.rels'
    x = parts[rp].decode()
    x = x.replace('</Relationships>', f'<Relationship Id="{rid}" Type="{typ}" Target="{target}"/></Relationships>')
    parts[rp] = x.encode()


def add_ct(part, ct):
    x = parts['[Content_Types].xml'].decode()
    x = x.replace('</Types>', f'<Override PartName="/{part}" ContentType="{ct}"/></Types>')
    parts['[Content_Types].xml'] = x.encode()


parts['ppt/commentAuthors.xml'] = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<p:cmAuthorLst xmlns:p="{P}">'
    '<p:cmAuthor id="0" name="Sam Rivera" initials="SR" lastIdx="1" clrIdx="0"/></p:cmAuthorLst>').encode()
add_ct('ppt/commentAuthors.xml', 'application/vnd.openxmlformats-officedocument.presentationml.commentAuthors+xml')
add_rel('ppt/presentation.xml', 'rId900', RT + '/commentAuthors', 'commentAuthors.xml')
parts['ppt/comments/comment1.xml'] = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<p:cmLst xmlns:p="{P}">'
    '<p:cm authorId="0" dt="2026-10-20T09:15:00.000" idx="1"><p:pos x="10" y="10"/><p:text>which farms?</p:text></p:cm></p:cmLst>').encode()
add_ct('ppt/comments/comment1.xml', 'application/vnd.openxmlformats-officedocument.presentationml.comments+xml')
add_rel('ppt/slides/slide3.xml', 'rId900', RT + '/comments', '../comments/comment1.xml')

P188 = 'http://schemas.microsoft.com/office/powerpoint/2018/8/main'
A = 'http://schemas.openxmlformats.org/drawingml/2006/main'
parts['ppt/authors.xml'] = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<p188:authorLst xmlns:a="{A}" xmlns:r="{RT}" xmlns:p188="{P188}">'
    '<p188:author id="{11111111-2222-3333-4444-555555555555}" name="Priya Shah" initials="PS" userId="priya@example.com" providerId="None"/>'
    '<p188:author id="{66666666-7777-8888-9999-000000000000}" name="Sam Rivera" initials="SR" userId="sam@example.com" providerId="None"/>'
    '</p188:authorLst>').encode()
add_ct('ppt/authors.xml', 'application/vnd.ms-powerpoint.authors+xml')
add_rel('ppt/presentation.xml', 'rId901', 'http://schemas.microsoft.com/office/2018/10/relationships/authors', 'authors.xml')
parts['ppt/comments/modernComment_104_1.xml'] = (
    f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<p188:cmLst xmlns:a="{A}" xmlns:r="{RT}" xmlns:p188="{P188}">'
    '<p188:cm id="{AAAAAAAA-0000-0000-0000-000000000001}" authorId="{11111111-2222-3333-4444-555555555555}" created="2026-10-21T14:30:00.000">'
    '<p188:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US"/><a:t>Is the footnote needed on every slide?</a:t></a:r></a:p></p188:txBody>'
    '<p188:replyLst><p188:reply id="{BBBBBBBB-0000-0000-0000-000000000001}" authorId="{66666666-7777-8888-9999-000000000000}" created="2026-10-22T08:05:00.000">'
    '<p188:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US"/><a:t>Only here; the others cite it above.</a:t></a:r></a:p></p188:txBody></p188:reply></p188:replyLst>'
    '</p188:cm></p188:cmLst>').encode()
add_ct('ppt/comments/modernComment_104_1.xml', 'application/vnd.ms-powerpoint.comments+xml')
add_rel('ppt/slides/slide5.xml', 'rId901', 'http://schemas.microsoft.com/office/2018/10/relationships/comments', '../comments/modernComment_104_1.xml')

with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for n in sorted(parts, key=lambda n: (n != '[Content_Types].xml', n)):
        z.writestr(zipfile.ZipInfo(n, (2026, 10, 31, 12, 0, 0)), parts[n], zipfile.ZIP_DEFLATED)
import os
os.remove(tmp)
print('wrote', out)
