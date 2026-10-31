"""Generate the same 10-slide Northwind deck two ways from template.pptx:
  placeholder.pptx - each slide uses a named layout; text goes into placeholders by idx.
  absolute.pptx    - every slide on the Blank layout; free text boxes at the layout's EMU geometry,
                     explicit font names + RGB colours (what pptxgenjs/html2pptx-style generators emit).
  combined.pptx    - placeholder slides 1-10 followed by absolute slides 11-20 (one upload to Google).
"""
import copy, io, sys
from lxml import etree
from PIL import Image, ImageDraw
from pptx import Presentation
from pptx.util import Emu, Pt
from pptx.dml.color import RGBColor
from pptx.enum.dml import MSO_THEME_COLOR
from pptx.enum.shapes import MSO_SHAPE, MSO_CONNECTOR
from pptx.chart.data import CategoryChartData
from pptx.enum.chart import XL_CHART_TYPE, XL_LEGEND_POSITION
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.oxml.ns import qn

THEME_RGB = {'tx1': '1B1F3B', 'tx2': '2E3A59', 'bg1': 'FFFFFF', 'accent1': '0F7B6C', 'accent2': 'E8833A', 'accent3': '5B5BD6'}
HEAD, BODY = 'Avenir Next', 'Inter'
NOTES_ON = ('Title + Bullets',)  # notes on two slides only, to keep upload files small

CONTENT = [
    dict(layout='Title', title='Northwind Labs — Q3 Review', sub='Operations update for the leadership team · October 2026',
         notes='Open with the headline: growth held while costs fell. Keep this slide under 30 seconds.'),
    dict(layout='Section', title='Results', num='01', notes='Section divider. Pause here.'),
    dict(layout='Title + Bullets', title='What changed this quarter',
         bullets=[(0, 'Fulfilment moved to the new Riverside hub'), (1, 'Average delivery time fell from 3.1 to 2.4 days'),
                  (2, 'Largest gains on routes over 200 km'), (0, 'Two pilot customers signed annual contracts'),
                  (1, 'Pilot terms are in the shared plan (link)'), (0, 'Hiring paused for back-office roles'),
                  (0, 'Supplier audit finished two weeks early, with no major findings and three minor ones to fix by year end'),
                  (1, 'Packaging waste down 18 percent after the switch to recycled board')],
         link=(4, 'https://example.com/northwind/pilot-plan'), autofit=True,
         notes='Speaker notes with a second line.\nMention the Riverside opening date.'),
    dict(layout='Two Column', title='Before and after Riverside',
         left=['Three regional depots', 'Manual pick lists', 'Next-day cut-off at 14:00'],
         right=['One central hub', 'Scanner-driven picking', 'Next-day cut-off at 18:00'], notes='Compare left and right.'),
    dict(layout='Big Number', title='On-time delivery', num='97.2%', label='Orders delivered on time',
         ctx='Up from 91.5% in Q2, measured across 48,210 orders.', notes='The KPI slide.'),
    dict(layout='Quote', quote='The new hub paid for itself faster than any project we have run.',
         who='— Ada Park, Head of Operations (fictional)', notes='Quote slide.'),
    dict(layout='Image + Caption', title='Riverside hub floor plan', caption='Zones A–D: inbound, storage, picking and dispatch. Image generated for this test.',
         notes='Image slide.'),
    dict(layout='Table', title='Quarter at a glance',
         table=[['Metric', 'Q2', 'Q3', 'Change'], ['Orders', '44,900', '48,210', '+7.4%'],
                ['Cost per order', '$6.10', '$5.42', '−11.1%'], ['On-time', '91.5%', '97.2%', '+5.7 pt']], notes='Table slide.'),
    dict(layout='Title Only', title='Orders by month', chart=True, notes='Native chart slide.'),
    dict(layout='Title Only', title='How an order flows', diagram=True, notes='Grouped diagram standing in for SmartArt.'),
]


def make_png(path):
    im = Image.new('RGB', (480, 315), (243, 241, 236))
    d = ImageDraw.Draw(im)
    cols = [(15, 123, 108), (232, 131, 58), (91, 91, 214), (47, 155, 216)]
    for i, c in enumerate(cols):
        d.rectangle([20 + i * 115, 30, 120 + i * 115, 285], fill=c)
        d.text((60 + i * 115, 150), 'ABCD'[i], fill=(255, 255, 255))
    im = im.quantize(colors=8)
    im.save(path, optimize=True)


def layout(prs, name):
    for l in prs.slide_layouts:
        if l.name == name:
            return l
    raise KeyError(name)


def add_footer_from_layout(slide):
    """python-pptx does not copy ftr/sldNum placeholders onto new slides; PowerPoint does when the
    'show footer' box is ticked. Clone the layout's so they appear."""
    for shp in slide.slide_layout.placeholders:
        if shp.placeholder_format.type is not None and shp.placeholder_format.idx in (11, 12):
            el = copy.deepcopy(shp._element)
            # slide copies keep only the ph reference; geometry is inherited
            spPr = el.find(qn('p:spPr'))
            for c in list(spPr):
                spPr.remove(c)
            lst = el.find('.//' + qn('a:lstStyle'))
            if lst is not None:
                for c in list(lst):
                    lst.remove(c)
            slide.shapes._spTree.append(el)


def fill_bullets(tf, items, link=None, rgb=False, size=None):
    tf.clear()
    for n, (lvl, text) in enumerate(items):
        p = tf.paragraphs[0] if n == 0 else tf.add_paragraph()
        p.level = lvl
        r = p.add_run()
        r.text = text
        if rgb:
            r.font.name = BODY
            r.font.size = Pt(size or [24, 20, 18][lvl])
            r.font.color.rgb = RGBColor.from_string(THEME_RGB['tx1'])
        if link and n == link[0]:
            r.hyperlink.address = link[1]


def set_autofit(tf, scale='77500', spc='20000'):
    bp = tf._txBody.find(qn('a:bodyPr'))
    for c in list(bp):
        bp.remove(c)
    na = etree.SubElement(bp, qn('a:normAutofit'))
    na.set('fontScale', scale); na.set('lnSpcReduction', spc)


def add_chart(slide, x, y, w, h):
    cd = CategoryChartData()
    cd.categories = ['Jul', 'Aug', 'Sep']
    cd.add_series('2025', (13100, 14020, 14900))
    cd.add_series('2026', (15200, 16010, 17000))
    gf = slide.shapes.add_chart(XL_CHART_TYPE.COLUMN_CLUSTERED, x, y, w, h, cd)
    ch = gf.chart
    ch.has_legend = True; ch.legend.position = XL_LEGEND_POSITION.BOTTOM; ch.legend.include_in_layout = False
    for s, col in zip(ch.series, (MSO_THEME_COLOR.ACCENT_3, MSO_THEME_COLOR.ACCENT_1)):
        s.format.fill.solid(); s.format.fill.fore_color.theme_color = col
    gf.name = 'Orders Chart'


def add_diagram(slide, x, y, w, h):
    steps = [('Order placed', MSO_THEME_COLOR.ACCENT_1), ('Picked', MSO_THEME_COLOR.ACCENT_3), ('Packed', MSO_THEME_COLOR.ACCENT_5), ('Delivered', None)]
    grp = slide.shapes.add_group_shape()
    grp.name = 'Order Flow Diagram'
    bw, gap = (w - 3 * 300000) // 4, 300000
    for i, (label, col) in enumerate(steps):
        bx = x + i * (bw + gap)
        s = grp.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, bx, y, bw, h)
        s.name = f'Step {i + 1}'
        if col is None:  # gradient, theme colours
            s.fill.gradient(); s.fill.gradient_angle = 90
            st = s.fill.gradient_stops
            st[0].color.theme_color = MSO_THEME_COLOR.ACCENT_2; st[1].color.theme_color = MSO_THEME_COLOR.ACCENT_4
        else:
            s.fill.solid(); s.fill.fore_color.theme_color = col
        s.line.fill.background()
        tf = s.text_frame; tf.text = label
        tf.paragraphs[0].runs[0].font.color.theme_color = MSO_THEME_COLOR.BACKGROUND_1
        tf.paragraphs[0].runs[0].font.bold = True
        if i < 3:
            c = grp.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, bx + bw, y + h // 2, bx + bw + gap, y + h // 2)
            c.line.color.theme_color = MSO_THEME_COLOR.TEXT_2; c.line.width = Pt(2)
            c.name = f'Arrow {i + 1}'
            ln = c.line._get_or_add_ln(); etree.SubElement(ln, qn('a:tailEnd')).set('type', 'triangle')


def style_table(tbl, rgb=False):
    for r, row in enumerate(tbl.rows):
        for cell in row.cells:
            for p in cell.text_frame.paragraphs:
                for run in p.runs:
                    run.font.size = Pt(16)
                    if rgb:
                        run.font.name = BODY


def ph_geom(lay, idx_or_type):
    for p in lay.placeholders:
        pf = p.placeholder_format
        if pf.idx == idx_or_type or str(pf.type).split('.')[-1].split(' ')[0].lower() == str(idx_or_type).lower():
            return p.left, p.top, p.width, p.height
    raise KeyError(idx_or_type)


def placeholder_deck(prs, png, only=None):
    for i, c in enumerate(CONTENT, 1):
        if only and i not in only: continue
        s = prs.slides.add_slide(layout(prs, c['layout']))
        P = {p.placeholder_format.idx: p for p in s.placeholders}
        L = c['layout']
        if 'title' in c and 0 in P:
            P[0].text = c['title']
        if L == 'Title':
            P[1].text = c['sub']
        elif L == 'Section':
            P[1].text = c['num']
        elif L == 'Title + Bullets':
            fill_bullets(P[1].text_frame, c['bullets'], c.get('link'))
            set_autofit(P[1].text_frame)
        elif L == 'Two Column':
            fill_bullets(P[1].text_frame, [(0, t) for t in c['left']])
            fill_bullets(P[2].text_frame, [(0, t) for t in c['right']])
        elif L == 'Big Number':
            P[13].text = c['num']; P[14].text = c['label']; P[15].text = c['ctx']
        elif L == 'Quote':
            P[13].text = c['quote']; P[14].text = c['who']
        elif L == 'Image + Caption':
            pic = P[1].insert_picture(png); P[2].text = c['caption']
        elif L == 'Table':
            rows = c['table']
            gf = P[1].insert_table(len(rows), len(rows[0]))
            for r, row in enumerate(rows):
                for k, v in enumerate(row):
                    gf.table.cell(r, k).text = v
            style_table(gf.table)
        if c.get('chart'):
            add_chart(s, Emu(609600), Emu(1500000), Emu(10972800), Emu(4600000))
        if c.get('diagram'):
            add_diagram(s, Emu(609600), Emu(2700000), Emu(10972800), Emu(1400000))
        add_footer_from_layout(s)
        if c['layout'] in NOTES_ON: s.notes_slide.notes_text_frame.text = c['notes']


def tb(slide, geom, text, size, color='tx1', bold=False, italic=False, font=BODY, align=None, anchor=None, name=None):
    x, y, w, h = geom
    t = slide.shapes.add_textbox(x, y, w, h)
    if name: t.name = name
    tf = t.text_frame; tf.word_wrap = True
    if anchor: tf.vertical_anchor = anchor
    tf.text = text
    for p in tf.paragraphs:
        if align: p.alignment = align
        for r in p.runs:
            r.font.size = Pt(size); r.font.bold = bold; r.font.italic = italic; r.font.name = font
            r.font.color.rgb = RGBColor.from_string(THEME_RGB[color])
    return t


def absolute_deck(prs, png, number_offset=0, only=None):
    blank = layout(prs, 'Blank')
    for n, c in enumerate(CONTENT, 1):
        if only and n not in only: continue
        s = prs.slides.add_slide(blank)
        lay = layout(prs, c['layout'])
        L = c['layout']
        g = lambda k: ph_geom(lay, k)
        if L == 'Section':  # layout background -> a full-bleed rectangle
            r = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, prs.slide_width, prs.slide_height)
            r.fill.solid(); r.fill.fore_color.rgb = RGBColor.from_string(THEME_RGB['accent1']); r.line.fill.background(); r.name = 'Background'
        if L == 'Title':
            tb(s, g(0), c['title'], 48, bold=True, font=HEAD, anchor=MSO_ANCHOR.BOTTOM, name='Title')
            tb(s, g(1), c['sub'], 20, 'tx2', name='Subtitle')
        elif L == 'Section':
            tb(s, g(0), c['title'], 44, 'bg1', bold=True, font=HEAD, name='Title')
            tb(s, g(1), c['num'], 60, 'accent2', bold=True, name='Section Number')
        elif 'title' in c:
            tb(s, g(0), c['title'], 36, bold=True, font=HEAD, anchor=MSO_ANCHOR.MIDDLE, name='Title')
        if L == 'Title + Bullets':
            t = s.shapes.add_textbox(*g(1)); t.name = 'Bullets'; t.text_frame.word_wrap = True
            fill_bullets(t.text_frame, c['bullets'], c.get('link'), rgb=True)
            for p in t.text_frame.paragraphs:  # text boxes have no bullets: add them explicitly
                pPr = p._p.get_or_add_pPr(); lvl = p.level
                pPr.set('marL', str(342900 + lvl * 457200)); pPr.set('indent', '-342900')
                etree.SubElement(pPr, qn('a:buFont')).set('typeface', 'Arial')
                etree.SubElement(pPr, qn('a:buChar')).set('char', '•')
            set_autofit(t.text_frame)
        elif L == 'Two Column':
            for k, key in ((1, 'left'), (2, 'right')):
                t = s.shapes.add_textbox(*g(k)); t.text_frame.word_wrap = True
                fill_bullets(t.text_frame, [(0, x) for x in c[key]], rgb=True)
        elif L == 'Big Number':
            tb(s, g(13), c['num'], 138, 'accent1', bold=True, font=HEAD, align=PP_ALIGN.CENTER, name='KPI Value')
            tb(s, g(14), c['label'], 24, bold=True, align=PP_ALIGN.CENTER)
            tb(s, g(15), c['ctx'], 16, 'tx2', align=PP_ALIGN.CENTER)
        elif L == 'Quote':
            tb(s, (Emu(609600), Emu(900000), Emu(1200000), Emu(1400000)), '“', 166, 'accent2', bold=True, font=HEAD)
            tb(s, g(13), c['quote'], 32, italic=True, anchor=MSO_ANCHOR.MIDDLE)
            tb(s, g(14), c['who'], 18, 'accent1')
        elif L == 'Image + Caption':
            x, y, w, h = g(1)
            pic = s.shapes.add_picture(png, x, y, w, h)  # stretched to the frame, like html2pptx output
            tb(s, g(2), c['caption'], 16, anchor=MSO_ANCHOR.BOTTOM)
        elif L == 'Table':
            rows = c['table']; x, y, w, h = g(1)
            gf = s.shapes.add_table(len(rows), len(rows[0]), x, y, w, Emu(400000 * len(rows)))
            for r, row in enumerate(rows):
                for k, v in enumerate(row):
                    gf.table.cell(r, k).text = v
            style_table(gf.table, rgb=True)
        if c.get('chart'):
            add_chart(s, Emu(609600), Emu(1500000), Emu(10972800), Emu(4600000))
        if c.get('diagram'):
            add_diagram(s, Emu(609600), Emu(2700000), Emu(10972800), Emu(1400000))
        if L not in ('Title', 'Section'):
            tb(s, (Emu(3962400), Emu(6356350), Emu(4267200), Emu(365125)), 'Northwind Labs · Confidential', 10, 'tx2', align=PP_ALIGN.CENTER, name='Footer Text')
            num = tb(s, (Emu(10363200), Emu(6356350), Emu(1219200), Emu(365125)), '', 10, 'tx2', align=PP_ALIGN.RIGHT, name='Slide Number Text')
            p = num.text_frame.paragraphs[0]._p
            for r in p.findall(qn('a:r')): p.remove(r)
            fld = etree.SubElement(p, qn('a:fld')); fld.set('id', '{B6F15528-21DE-4FAA-801E-634DDDAF4B2B}'); fld.set('type', 'slidenum')
            rpr = etree.SubElement(fld, qn('a:rPr')); rpr.set('lang', 'en-US'); rpr.set('sz', '1000')
            etree.SubElement(fld, qn('a:t')).text = str(n + number_offset)
        if c['layout'] in NOTES_ON: s.notes_slide.notes_text_frame.text = c['notes']


def strip(prs):
    # drop the default template's thumbnail to keep files small
    pkg = prs.part.package
    for rel in list(pkg._rels.values()) if hasattr(pkg, '_rels') else []:
        if rel.reltype.endswith('/thumbnail'):
            pkg._rels.pop(rel.rId)


def prune_layouts(prs, keep=()):
    """Drop layouts no slide uses, except those named in keep (to test whether unused layouts survive)."""
    used = {id(s.slide_layout) for s in prs.slides}
    for l in list(prs.slide_layouts):
        if id(l) not in used and l.name not in keep:
            prs.slide_layouts.remove(l)


if __name__ == '__main__':
    tpl = sys.argv[1] if len(sys.argv) > 1 else 'template.pptx'
    make_png('floor.png')
    # full local decks (rendered with LibreOffice)
    for kind in ('placeholder', 'absolute'):
        prs = Presentation(tpl)
        (placeholder_deck if kind == 'placeholder' else absolute_deck)(prs, 'floor.png')
        prs.core_properties.title = f'Northwind Q3 — {kind}'
        prs.save(f'{kind}.pptx')
    # small upload files (base64 passes through the model's context and long strings get mis-copied,
    # so each file holds 1-3 slides and only the layouts it needs)
    for name, kind, only, keep in (('P1', 'placeholder', {1, 2}, ('Two Column', 'Table')),  # 2 unused layouts kept
                                   ('P2', 'placeholder', {3}, ()),
                                   ('P3', 'placeholder', {5, 6}, ()),
                                   ('P4', 'placeholder', {7, 8}, ()),
                                   ('C1', 'placeholder', {9, 10}, ()),
                                   ('A1', 'absolute', {1, 3, 5}, ())):
        prs = Presentation(tpl)
        (placeholder_deck if kind == 'placeholder' else absolute_deck)(prs, 'floor.png', only=only)
        prune_layouts(prs, keep)
        prs.core_properties.title = f'Northwind Q3 {name}'
        prs.save(f'{name}.pptx')
    print('ok')
