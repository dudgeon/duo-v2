"""Build a synthetic 'Northwind Labs' reference template (template.pptx) from python-pptx's default.

Theme: custom colour scheme + theme fonts (major 'Avenir Next' = not a Google font, minor 'Inter' = Google font).
Master: accent bar (gradient), logo (theme-filled rounded rect + wordmark), title/body/dt/ftr/sldNum placeholders.
Layouts (10): Title, Section, Title + Bullets, Two Column, Big Number, Quote, Image + Caption, Table,
Title Only, Blank. Every layout has ftr (idx 11) and sldNum (idx 12).
"""
import copy, re, sys
from lxml import etree
from pptx import Presentation
from pptx.util import Emu
from pptx.opc.constants import RELATIONSHIP_TYPE as RT

NS = {'a': 'http://schemas.openxmlformats.org/drawingml/2006/main',
      'p': 'http://schemas.openxmlformats.org/presentationml/2006/main',
      'r': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'}
NSDECL = ' '.join(f'xmlns:{k}="{v}"' for k, v in NS.items())
W, H = 12192000, 6858000
M = 609600  # side margin

CLR = '''<a:clrScheme name="Northwind">
<a:dk1><a:srgbClr val="1B1F3B"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>
<a:dk2><a:srgbClr val="2E3A59"/></a:dk2><a:lt2><a:srgbClr val="F3F1EC"/></a:lt2>
<a:accent1><a:srgbClr val="0F7B6C"/></a:accent1><a:accent2><a:srgbClr val="E8833A"/></a:accent2>
<a:accent3><a:srgbClr val="5B5BD6"/></a:accent3><a:accent4><a:srgbClr val="D6455D"/></a:accent4>
<a:accent5><a:srgbClr val="2F9BD8"/></a:accent5><a:accent6><a:srgbClr val="8C9A2B"/></a:accent6>
<a:hlink><a:srgbClr val="5B5BD6"/></a:hlink><a:folHlink><a:srgbClr val="7A4FA0"/></a:folHlink>
</a:clrScheme>'''
FONT = '''<a:fontScheme name="Northwind">
<a:majorFont><a:latin typeface="Avenir Next"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>
<a:minorFont><a:latin typeface="Inter"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont>
</a:fontScheme>'''


def X(s):
    return etree.fromstring(f'<root {NSDECL}>{s}</root>')[0]


def ph(sid, name, typ, idx, x, y, w, h, prompt='', sz=None, bold=False, color=None, algn=None,
       anchor=None, italic=False, font=None, autofit='<a:normAutofit/>', bullets=True):
    t = f' type="{typ}"' if typ else ''
    i = f' idx="{idx}"' if idx is not None else ''
    rpr = ''
    if sz or bold or color or italic or font:
        attrs = (f' sz="{sz}"' if sz else '') + (' b="1"' if bold else '') + (' i="1"' if italic else '')
        inner = (f'<a:solidFill><a:schemeClr val="{color}"/></a:solidFill>' if color else '') + \
                (f'<a:latin typeface="{font}"/>' if font else '')
        rpr = f'<a:defRPr{attrs}>{inner}</a:defRPr>'
    ppr_attr = (f' algn="{algn}"' if algn else '') + ('' if bullets else ' marL="0" indent="0"')
    bu = '' if bullets else '<a:buNone/>'
    lst = f'<a:lstStyle><a:lvl1pPr{ppr_attr}>{bu}{rpr}</a:lvl1pPr></a:lstStyle>' if (rpr or ppr_attr or bu) else '<a:lstStyle/>'
    anc = f' anchor="{anchor}"' if anchor else ''
    body = (f'<p:txBody><a:bodyPr{anc}>{autofit}</a:bodyPr>{lst}<a:p><a:r><a:rPr lang="en-US"/>'
            f'<a:t>{prompt}</a:t></a:r></a:p></p:txBody>') if typ not in ('pic', 'tbl', 'chart') else ''
    if typ == 'sldNum':
        body = (f'<p:txBody><a:bodyPr{anc}/>{lst}<a:p><a:fld id="{{B6F15528-21DE-4FAA-801E-634DDDAF4B2B}}" '
                f'type="slidenum"><a:rPr lang="en-US"/><a:t>&lt;#&gt;</a:t></a:fld><a:endParaRPr lang="en-US"/></a:p></p:txBody>')
    return X(f'''<p:sp><p:nvSpPr><p:cNvPr id="{sid}" name="{name}"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>
<p:nvPr><p:ph{t}{i}/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x="{x}" y="{y}"/><a:ext cx="{w}" cy="{h}"/></a:xfrm></p:spPr>{body}</p:sp>''')


def deco_rect(sid, name, x, y, w, h, fill, geom='rect'):
    return X(f'''<p:sp><p:nvSpPr><p:cNvPr id="{sid}" name="{name}"/><p:cNvSpPr/><p:nvPr userDrawn="1"/></p:nvSpPr>
<p:spPr><a:xfrm><a:off x="{x}" y="{y}"/><a:ext cx="{w}" cy="{h}"/></a:xfrm><a:prstGeom prst="{geom}"><a:avLst/></a:prstGeom>{fill}<a:ln><a:noFill/></a:ln></p:spPr>
<p:txBody><a:bodyPr anchor="ctr"/><a:lstStyle/><a:p><a:endParaRPr lang="en-US"/></a:p></p:txBody></p:sp>''')


def deco_text(sid, name, x, y, w, h, text, sz, color, bold=False, font='+mj-lt', fill='<a:noFill/>', algn='l'):
    b = ' b="1"' if bold else ''
    return X(f'''<p:sp><p:nvSpPr><p:cNvPr id="{sid}" name="{name}"/><p:cNvSpPr txBox="1"/><p:nvPr userDrawn="1"/></p:nvSpPr>
<p:spPr><a:xfrm><a:off x="{x}" y="{y}"/><a:ext cx="{w}" cy="{h}"/></a:xfrm><a:prstGeom prst="roundRect"><a:avLst/></a:prstGeom>{fill}</p:spPr>
<p:txBody><a:bodyPr wrap="none" lIns="0" rIns="0" anchor="ctr"/><a:lstStyle/><a:p><a:pPr algn="{algn}"/><a:r><a:rPr lang="en-US" sz="{sz}"{b}>
<a:solidFill><a:schemeClr val="{color}"/></a:solidFill><a:latin typeface="{font}"/></a:rPr><a:t>{text}</a:t></a:r></a:p></p:txBody></p:sp>''')


GRAD = ('<a:gradFill rotWithShape="1"><a:gsLst><a:gs pos="0"><a:schemeClr val="accent1"/></a:gs>'
        '<a:gs pos="100000"><a:schemeClr val="accent3"/></a:gs></a:gsLst><a:lin ang="0" scaled="0"/></a:gradFill>')
SOLID = lambda c: f'<a:solidFill><a:schemeClr val="{c}"/></a:solidFill>'
LTYPE = {'Title': 'title', 'Section': 'secHead', 'Title + Bullets': 'obj', 'Two Column': 'twoObj', 'Big Number': 'cust',
         'Quote': 'cust', 'Image + Caption': 'picTx', 'Table': 'tbl', 'Title Only': 'titleOnly', 'Blank': 'blank'}
FY, FH = 6356350, 365125  # footer row


def footer(sid):
    return [ph(sid, 'Footer Placeholder', 'ftr', 11, 3962400, FY, 4267200, FH, 'Northwind Labs · Confidential', sz=1000, color='tx2', algn='ctr', autofit=''),
            ph(sid + 1, 'Slide Number Placeholder', 'sldNum', 12, 10363200, FY, 1219200, FH, sz=1000, color='tx2', algn='r')]


def set_tree(holder, name, shapes, bg=None):
    cSld = holder._element.find('p:cSld', NS)
    if name:
        cSld.set('name', name)
    old_bg = cSld.find('p:bg', NS)
    if old_bg is not None:
        cSld.remove(old_bg)
    if bg is not None:
        cSld.insert(0, X(f'<p:bg><p:bgPr>{bg}<a:effectLst/></p:bgPr></p:bg>'))
    tree = cSld.find('p:spTree', NS)
    for el in list(tree):
        if el.tag.split('}')[1] in ('sp', 'pic', 'grpSp', 'graphicFrame', 'cxnSp'):
            tree.remove(el)
    for s in shapes:
        tree.append(s)


def build(out):
    prs = Presentation()
    prs.slide_width, prs.slide_height = W, H
    m = prs.slide_master
    theme = m.part.part_related_by(RT.THEME)
    xml = theme.blob.decode()
    xml = re.sub(r'<a:clrScheme.*?</a:clrScheme>', CLR, xml, flags=re.S)
    xml = re.sub(r'<a:fontScheme.*?</a:fontScheme>', FONT, xml, flags=re.S)
    xml = xml.replace('name="Office Theme"', 'name="Northwind Labs"')
    theme._blob = xml.encode()

    TW = W - 2 * M
    set_tree(m, None, [
        deco_rect(20, 'Accent Bar', 0, 0, W, 91440, GRAD),
        deco_text(21, 'Logo Mark', M, 6400800, 320040, 274320, 'NW', 1000, 'bg1', True, fill=SOLID('accent1'), algn='ctr'),
        deco_text(22, 'Logo Wordmark', M + 400000, 6400800, 1800000, 274320, 'Northwind Labs', 1100, 'tx1', True),
        ph(2, 'Title Placeholder 1', 'title', None, M, 365125, TW, 1000000, 'Click to edit Master title style'),
        ph(3, 'Text Placeholder 2', 'body', 1, M, 1500000, TW, 4600000, 'Click to edit Master text styles'),
        ph(5, 'Footer Placeholder 4', 'ftr', 3, 3962400, FY, 4267200, FH, '', sz=1000, color='tx2', algn='ctr', autofit=''),
        ph(6, 'Slide Number Placeholder 5', 'sldNum', 4, 10363200, FY, 1219200, FH, sz=1000, color='tx2', algn='r'),
    ])
    # master text styles: title colour, bullets on accent1
    tx = m._element.find('p:txStyles', NS)
    for d in tx.iter('{%s}defRPr' % NS['a']):
        pass
    title_rpr = tx.find('p:titleStyle/a:lvl1pPr/a:defRPr', NS)
    title_rpr.set('sz', '3600'); title_rpr.set('b', '1')

    L = list(prs.slide_layouts)
    # drop the two vertical-text layouts
    for lay in L[10:]:
        prs.slide_layouts.remove(lay)
    L = list(prs.slide_layouts)
    half = (TW - 457200) // 2
    defs = [
        ('Title', [deco_rect(30, 'Brand Stripe', 0, 0, 304800, H, GRAD),
                   ph(2, 'Title 1', 'ctrTitle', None, M + 304800, 2130000, TW - 304800, 1470000, 'Presentation title', sz=4800, anchor='b'),
                   ph(3, 'Subtitle 2', 'subTitle', 1, M + 304800, 3700000, TW - 304800, 900000, 'Subtitle', sz=2000, color='tx2', bullets=False)]),
        ('Section', [ph(2, 'Title 1', 'title', None, M, 2900000, TW, 1300000, 'Section title', sz=4400, color='bg1', anchor='t'),
                     ph(3, 'Section Number 2', 'body', 1, M, 1700000, 3000000, 1100000, '01', sz=6000, bold=True, color='accent2', bullets=False)],
         SOLID('accent1')),
        ('Title + Bullets', [ph(2, 'Title 1', 'title', None, M, 365125, TW, 1000000, 'Title'),
                             ph(3, 'Content Placeholder 2', 'body', 1, M, 1500000, TW, 4600000, 'Bullets')]),
        ('Two Column', [ph(2, 'Title 1', 'title', None, M, 365125, TW, 1000000, 'Title'),
                        ph(3, 'Left Column', 'body', 1, M, 1500000, half, 4600000, 'Left'),
                        ph(4, 'Right Column', 'body', 2, M + half + 457200, 1500000, half, 4600000, 'Right')]),
        ('Big Number', [ph(2, 'Title 1', 'title', None, M, 365125, TW, 1000000, 'Title'),
                        ph(3, 'KPI Value', 'body', 13, M, 1700000, TW, 2200000, '00%', sz=13800, bold=True, color='accent1', bullets=False, algn='ctr', font='+mj-lt'),
                        ph(4, 'KPI Label', 'body', 14, M, 3950000, TW, 600000, 'What the number measures', sz=2400, bold=True, bullets=False, algn='ctr'),
                        ph(5, 'KPI Context', 'body', 15, M + 1524000, 4600000, TW - 3048000, 900000, 'Context', sz=1600, color='tx2', bullets=False, algn='ctr')]),
        ('Quote', [deco_text(30, 'Quote Mark', M, 900000, 1200000, 1400000, '“', 16600, 'accent2', True),
                   ph(3, 'Quote Text', 'body', 13, M + 1300000, 1500000, TW - 2600000, 2600000, 'Quote', sz=3200, italic=True, bullets=False, anchor='ctr'),
                   ph(4, 'Attribution', 'body', 14, M + 1300000, 4300000, TW - 2600000, 600000, '— Name, Role', sz=1800, color='accent1', bullets=False)]),
        ('Image + Caption', [ph(2, 'Title 1', 'title', None, M, 365125, TW, 1000000, 'Title'),
                             ph(3, 'Picture Placeholder 2', 'pic', 1, M, 1500000, 7000000, 4600000),
                             ph(4, 'Caption', 'body', 2, M + 7300000, 1500000, TW - 7300000, 4600000, 'Caption', sz=1600, bullets=False, anchor='b')]),
        ('Table', [ph(2, 'Title 1', 'title', None, M, 365125, TW, 1000000, 'Title'),
                   ph(3, 'Table Placeholder 2', 'tbl', 1, M, 1500000, TW, 4400000)]),
        ('Title Only', [ph(2, 'Title 1', 'title', None, M, 365125, TW, 1000000, 'Title')]),
        ('Blank', []),
    ]
    for lay, d in zip(L, defs):
        name, shapes = d[0], d[1]
        bg = d[2] if len(d) > 2 else None
        set_tree(lay, name, shapes + footer(10), bg)
        lay._element.set('type', LTYPE[name]); lay._element.set('preserve', '1')
        # remove python-pptx's showMasterSp quirks: keep master shapes visible except Title/Section
        if name in ('Title', 'Section'):
            lay._element.set('showMasterSp', '0')
    prs.core_properties.title = 'Northwind Labs template'
    prs.core_properties.author = 'Duo Decks prototype'
    prs.save(out)


if __name__ == '__main__':
    build(sys.argv[1] if len(sys.argv) > 1 else 'template.pptx')
