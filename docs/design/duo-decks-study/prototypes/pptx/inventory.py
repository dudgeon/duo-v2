"""Deterministic inventory of a .pptx, for template extraction (Duo Decks study).
Dumps theme (colours, fonts), master, every layout (placeholders with type/idx/name/geometry/font size/autofit,
plus decorative shapes) and every slide (layout, shapes, geometry, text, what each placeholder inherits from).
usage: inventory.py deck.pptx [--json]   (default: compact YAML-ish text)
"""
import json, sys
from lxml import etree
from pptx import Presentation
from pptx.opc.constants import RELATIONSHIP_TYPE as RT
from pptx.util import Emu

NS = {'a': 'http://schemas.openxmlformats.org/drawingml/2006/main',
      'p': 'http://schemas.openxmlformats.org/presentationml/2006/main'}


def emu_in(v):
    return None if v is None else round(Emu(v).inches, 2)


def geom(shp):
    return [emu_in(shp.left), emu_in(shp.top), emu_in(shp.width), emu_in(shp.height)] if shp.width is not None else None


def body_info(el):
    """autofit + first explicit font size found in lstStyle/defRPr or runs"""
    out = {}
    bp = el.find('.//a:bodyPr', NS)
    if bp is not None:
        for tag in ('normAutofit', 'spAutoFit', 'noAutofit'):
            n = bp.find(f'a:{tag}', NS)
            if n is not None:
                out['autofit'] = tag + (f" scale={n.get('fontScale')}" if n.get('fontScale') else '')
        if bp.get('anchor'):
            out['anchor'] = bp.get('anchor')
    tb = el.find('.//p:txBody', NS)
    el = tb if tb is not None else el
    for path in ('.//a:lstStyle/a:lvl1pPr/a:defRPr', './/a:rPr', './/a:endParaRPr'):
        r = el.find(path, NS)
        if r is not None and r.get('sz'):
            out['size_pt'] = int(r.get('sz')) / 100
            break
    lat = el.find('.//a:latin', NS)
    if lat is not None:
        out['font'] = lat.get('typeface')
    clr = el.find('.//a:solidFill/a:schemeClr', NS)
    if clr is not None:
        out['color'] = 'scheme:' + clr.get('val')
    else:
        clr = el.find('.//a:solidFill/a:srgbClr', NS)
        if clr is not None:
            out['color'] = '#' + clr.get('val')
    return out


def fill_info(shp):
    sp = shp._element.find('.//p:spPr', NS)
    if sp is None:
        return None
    if sp.find('a:gradFill', NS) is not None:
        stops = [c.get('val') for c in sp.findall('a:gradFill/a:gsLst/a:gs/*', NS)]
        return 'gradient(' + ','.join(stops) + ')'
    s = sp.find('a:solidFill/*', NS)
    if s is not None:
        return ('scheme:' if s.tag.endswith('schemeClr') else '#') + s.get('val')
    return None


def shape_kind(shp):
    if shp.is_placeholder:
        return 'placeholder'
    return {'GraphicFrame': 'graphicFrame', 'GroupShape': 'group', 'Picture': 'picture'}.get(
        type(shp).__name__, 'shape')


def describe(shp, with_text=False):
    d = {'name': shp.name, 'kind': shape_kind(shp), 'geom_in': geom(shp)}
    if shp.is_placeholder:
        pf = shp.placeholder_format
        d['ph'] = {'type': str(pf.type).split('.')[-1].split(' ')[0], 'idx': pf.idx}
    if shp.has_text_frame if hasattr(shp, 'has_text_frame') else False:
        d.update(body_info(shp._element))
        if with_text:
            paras = [('  ' * p.level) + ''.join(r.text for r in p.runs) for p in shp.text_frame.paragraphs]
            d['text'] = [t for t in paras if t.strip()]
            links = [r.hyperlink.address for p in shp.text_frame.paragraphs for r in p.runs if r.hyperlink.address]
            if links:
                d['links'] = links
    f = fill_info(shp)
    if f:
        d['fill'] = f
    if getattr(shp, 'has_table', False) and shp.has_table:
        t = shp.table
        d['table'] = {'rows': len(t.rows), 'cols': len(t.columns),
                      'style': shp._element.find('.//a:tableStyleId', NS).text
                      if shp._element.find('.//a:tableStyleId', NS) is not None else None}
        if with_text:
            d['cells'] = [[c.text for c in r.cells] for r in t.rows]
    if getattr(shp, 'has_chart', False) and shp.has_chart:
        ch = shp.chart
        d['chart'] = {'type': str(ch.chart_type).split('.')[-1].split(' ')[0],
                      'series': [s.name for s in ch.plots[0].series],
                      'categories': list(ch.plots[0].categories)}
    if type(shp).__name__ == 'GroupShape':
        d['children'] = [describe(c, with_text) for c in shp.shapes]
    return d


def theme(prs):
    t = prs.slide_master.part.part_related_by(RT.THEME)
    x = etree.fromstring(t.blob)
    cs = x.find('.//a:clrScheme', NS)
    colors = {c.tag.split('}')[1]: (c[0].get('val') or c[0].get('lastClr')) for c in cs}
    fs = x.find('.//a:fontScheme', NS)
    return {'name': x.get('name'), 'colors': colors,
            'fonts': {'major': fs.find('a:majorFont/a:latin', NS).get('typeface'),
                      'minor': fs.find('a:minorFont/a:latin', NS).get('typeface')}}


def inventory(path):
    prs = Presentation(path)
    m = prs.slide_master
    out = {'file': path, 'slide_size_in': [emu_in(prs.slide_width), emu_in(prs.slide_height)],
           'theme': theme(prs),
           'master': {'shapes': [describe(s) for s in m.shapes]},
           'layouts': [], 'slides': []}
    for lay in prs.slide_layouts:
        el = lay._element
        out['layouts'].append({
            'name': lay.name, 'type': el.get('type'),
            'showMasterShapes': el.get('showMasterSp') != '0',
            'background': 'own' if el.find('p:cSld/p:bg', NS) is not None else 'master',
            'placeholders': [describe(s) for s in lay.placeholders],
            'decoration': [describe(s) for s in lay.shapes if not s.is_placeholder]})
    for i, s in enumerate(prs.slides, 1):
        d = {'n': i, 'layout': s.slide_layout.name, 'shapes': [describe(sh, True) for sh in s.shapes]}
        if s.has_notes_slide and s.notes_slide.notes_text_frame.text.strip():
            d['notes'] = s.notes_slide.notes_text_frame.text
        out['slides'].append(d)
    return out


def yamlish(o, ind=0):
    pad = '  ' * ind
    if isinstance(o, dict):
        lines = []
        for k, v in o.items():
            if isinstance(v, (dict, list)) and v and not (isinstance(v, list) and all(not isinstance(x, (dict, list)) for x in v)):
                lines.append(f'{pad}{k}:')
                lines.append(yamlish(v, ind + 1))
            else:
                lines.append(f'{pad}{k}: {json.dumps(v, ensure_ascii=False)}')
        return '\n'.join(lines)
    if isinstance(o, list):
        lines = []
        for v in o:
            if isinstance(v, dict):
                inner = yamlish(v, ind + 1).lstrip()
                lines.append(f'{pad}- {inner}')
            else:
                lines.append(f'{pad}- {json.dumps(v, ensure_ascii=False)}')
        return '\n'.join(lines)
    return pad + json.dumps(o)


if __name__ == '__main__':
    inv = inventory(sys.argv[1])
    print(json.dumps(inv, indent=1, ensure_ascii=False) if '--json' in sys.argv else yamlish(inv))
