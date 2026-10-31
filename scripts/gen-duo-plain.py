"""Builds Duo's built-in deck template pack, "duo-plain" (Duo Decks P1, DL-268), and embeds it in Swift.

Dev-time only: run `uv run --with python-pptx python scripts/gen-duo-plain.py` after changing the design.
It writes Sources/DuoDeck/BuiltInPack.swift (the pptx as base64 beside the definition note), so nothing
has to be installed or found at run time: duo2 runs from Contents/Helpers with no resource folder.

Original, plain design: Inter for headings and text (a Google Font), a quiet palette, one accent rule.
Eight layouts as the Northwind sample (Title, Section, Title + Bullets, Two Column, Big Number, Quote,
Image + Caption, Table), every layout with a footer (idx 11) and slide number (idx 12). Derived from
the Northwind sample generator (docs/design/duo-decks-study/prototypes/pptx/gen_template.py): same
placeholder structure, new colours, fonts and artwork. The output is repeatable: the zip is rewritten
with fixed times and a fixed part order, and the properties that python-pptx fills are cleaned.
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

CLR = '''<a:clrScheme name="Duo Plain">
<a:dk1><a:srgbClr val="20242E"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>
<a:dk2><a:srgbClr val="4A5164"/></a:dk2><a:lt2><a:srgbClr val="F4F5F8"/></a:lt2>
<a:accent1><a:srgbClr val="3B5BDB"/></a:accent1><a:accent2><a:srgbClr val="F08C00"/></a:accent2>
<a:accent3><a:srgbClr val="0CA678"/></a:accent3><a:accent4><a:srgbClr val="E03131"/></a:accent4>
<a:accent5><a:srgbClr val="1098AD"/></a:accent5><a:accent6><a:srgbClr val="7048E8"/></a:accent6>
<a:hlink><a:srgbClr val="3B5BDB"/></a:hlink><a:folHlink><a:srgbClr val="7048E8"/></a:folHlink>
</a:clrScheme>'''
FONT = '''<a:fontScheme name="Duo Plain">
<a:majorFont><a:latin typeface="Inter"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>
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


SOLID = lambda c: f'<a:solidFill><a:schemeClr val="{c}"/></a:solidFill>'
LTYPE = {'Title': 'title', 'Section': 'secHead', 'Title + Bullets': 'obj', 'Two Column': 'twoObj', 'Big Number': 'cust',
         'Quote': 'cust', 'Image + Caption': 'picTx', 'Table': 'tbl', 'Title Only': 'titleOnly', 'Blank': 'blank'}
FY, FH = 6356350, 365125  # footer row


def footer(sid):
    return [ph(sid, 'Footer Placeholder', 'ftr', 11, 3962400, FY, 4267200, FH, '', sz=1000, color='tx2', algn='ctr', autofit=''),
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
    xml = xml.replace('name="Office Theme"', 'name="Duo Plain"')
    theme._blob = xml.encode()

    TW = W - 2 * M
    set_tree(m, None, [
        deco_rect(20, 'Accent Rule', M, 228600, 914400, 54864, SOLID('accent1')),
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
        ('Title', [deco_rect(30, 'Side Stripe', 0, 0, 228600, H, SOLID('accent1')),
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
    import datetime
    prs.core_properties.created = prs.core_properties.modified = datetime.datetime(2026, 1, 1)
    prs.core_properties.revision = 1
    prs.core_properties.title = 'Duo Plain'
    prs.core_properties.author = 'Duo'
    prs.core_properties.last_modified_by = 'Duo'
    prs.core_properties.comments = ''
    prs.save(out)


def clean(path):
    """Rewrite the zip repeatably: fixed order and times, no thumbnail, no stale slide-size type."""
    import zipfile
    zin = zipfile.ZipFile(path)
    names = sorted(n for n in zin.namelist() if 'thumbnail' not in n)
    out = {}
    for n in names:
        data = zin.read(n)
        if n == '[Content_Types].xml':
            data = re.sub(rb'<Default Extension="jpeg"[^>]*/>', b'', data)
        if n == '_rels/.rels':
            data = re.sub(rb'<Relationship [^>]*thumbnail[^>]*/>', b'', data)
        if n == 'ppt/presentation.xml':
            data = data.replace(b' type="screen4x3"', b'')
        out[n] = data
    zin.close()
    first = ['[Content_Types].xml']
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        for n in first + [n for n in names if n not in first]:
            zi = zipfile.ZipInfo(n, (1980, 1, 1, 0, 0, 0))
            zi.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(zi, out[n])


if __name__ == '__main__':
    import base64, os, tempfile
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    md = open(os.path.join(root, 'scripts', 'duo-plain.md')).read()
    tmp = os.path.join(tempfile.mkdtemp(), 'duo-plain.pptx')
    build(tmp)
    clean(tmp)
    blob = base64.b64encode(open(tmp, 'rb').read()).decode()
    lines = [blob[i:i + 120] for i in range(0, len(blob), 120)]
    swift = ['// Generated by scripts/gen-duo-plain.py; do not edit. Duo\'s built-in deck template pack (DL-268).',
             '', 'enum BuiltInPackData {',
             '    static let definition = #"""', md.rstrip('\n'), '"""#', '',
             '    static let pptxBase64 = """']
    swift += lines + ['"""', '}', '']
    open(os.path.join(root, 'Sources', 'DuoDeck', 'BuiltInPackData.swift'), 'w').write('\n'.join(swift))
    print('wrote BuiltInPackData.swift:', len(blob), 'base64 characters')
