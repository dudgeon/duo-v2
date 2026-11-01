"""Make a pptx as small as possible for upload through a model's context (base64), keeping it valid OOXML:
short part names (all parts flat in ppt/), optional parts dropped (docProps, presProps, viewProps,
tableStyles, printerSettings, thumbnail, embedded chart workbooks), master text styles cut to 3 levels.
usage: lean.py in.pptx out.pptx"""
import posixpath, re, sys, zipfile
from lxml import etree

PR = 'http://schemas.openxmlformats.org/package/2006/relationships'
CT = 'http://schemas.openxmlformats.org/package/2006/content-types'
DROP_RT = ('/extended-properties', '/core-properties', '/presProps', '/viewProps',
           '/printerSettings', '/thumbnail', '/package')
src, dst = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
names = set(z.namelist())
ct = etree.fromstring(z.read('[Content_Types].xml'))
ctype = {o.get('PartName').lstrip('/'): o.get('ContentType') for o in ct.findall(f'{{{CT}}}Override')}
defaults = {d.get('Extension'): d.get('ContentType') for d in ct.findall(f'{{{CT}}}Default')}

def rels_name(part):
    d, f = posixpath.split(part)
    return posixpath.join(d, '_rels', f + '.rels')

# walk the relationship graph from the package root, keep what's reachable and not dropped
keep, rels = [], {}
todo = ['']
while todo:
    part = todo.pop()
    rn = '_rels/.rels' if part == '' else rels_name(part)
    if rn not in names:
        continue
    root = etree.fromstring(z.read(rn))
    lst = []
    for r in root:
        if r.get('TargetMode') == 'External':
            lst.append((r.get('Id'), r.get('Type'), r.get('Target'), True)); continue
        if r.get('Type').endswith(DROP_RT):
            continue
        tgt = posixpath.normpath(posixpath.join(posixpath.dirname(part), r.get('Target'))).lstrip('/')
        if tgt not in names:
            continue
        if 'notesMaster' in part and tgt.startswith('ppt/theme/'):
            tgt = 'ppt/theme/theme1.xml'  # notes master shares the slide theme (saves a part)
        lst.append((r.get('Id'), r.get('Type'), tgt, False))
        if tgt not in keep:
            keep.append(tgt); todo.append(tgt)
    rels[part] = lst

short = {}
counters = {}
for p in keep:
    if p == 'ppt/presentation.xml':
        short[p] = p; continue
    base = posixpath.basename(p)
    m = re.match(r'([a-zA-Z]+?)(\d*)\.(\w+)$', base)
    stem, num, ext = m.groups()
    key = {'slide': 's', 'slideLayout': 'l', 'slideMaster': 'm', 'theme': 't', 'notesMaster': 'nm',
           'notesSlide': 'n', 'chart': 'c', 'image': 'i'}.get(stem, stem[:2])
    short[p] = f'ppt/{key}{num}.{ext}'

NOTES_MASTER = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<p:notesMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><p:cSld><p:spTree>'
    '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
    '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Slide Image"/><p:cNvSpPr><a:spLocks noGrp="1" noRot="1" noChangeAspect="1"/></p:cNvSpPr>'
    '<p:nvPr><p:ph type="sldImg" idx="2"/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x="381000" y="685800"/>'
    '<a:ext cx="6096000" cy="3429000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:sp>'
    '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Notes"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>'
    '<p:nvPr><p:ph type="body" sz="quarter" idx="3"/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x="685800" y="4343400"/>'
    '<a:ext cx="5486400" cy="4114800"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
    '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:endParaRPr lang="en-US"/></a:p></p:txBody></p:sp>'
    '</p:spTree></p:cSld><p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" '
    'accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
    '<p:notesStyle><a:lvl1pPr><a:defRPr sz="1200"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill>'
    '<a:latin typeface="+mn-lt"/></a:defRPr></a:lvl1pPr></p:notesStyle></p:notesMaster>').encode()


def lean_xml(p, data):
    if 'notesMaster' in p:
        return NOTES_MASTER
    if 'slideMaster' in p:
        data = re.sub(rb'<a:lvl[4-9]pPr.*?</a:lvl[4-9]pPr>', b'', data, flags=re.S)
        data = re.sub(rb'<p:extLst>.*?</p:extLst>', b'', data, flags=re.S)
    if p == 'ppt/presentation.xml':
        data = re.sub(rb'<a:lvl[4-9]pPr.*?</a:lvl[4-9]pPr>', b'', data, flags=re.S)
        data = re.sub(rb'<p:extLst>.*?</p:extLst>', b'', data, flags=re.S)
    if 'charts/chart' in p:
        data = re.sub(rb'<c:externalData [^>]*>.*?</c:externalData>', b'', data, flags=re.S)
    return data

out = zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED, compresslevel=9)
types = etree.Element(f'{{{CT}}}Types', nsmap={None: CT})
for ext, t in (('rels', 'application/vnd.openxmlformats-package.relationships+xml'), ('xml', 'application/xml'),
               ('png', 'image/png')):
    etree.SubElement(types, f'{{{CT}}}Default', Extension=ext, ContentType=t)
for p in keep:
    t = ctype.get(p) or defaults.get(p.rsplit('.', 1)[-1])
    if not p.endswith('.png'):
        etree.SubElement(types, f'{{{CT}}}Override', PartName='/' + short[p], ContentType=t)
out.writestr('[Content_Types].xml', etree.tostring(types, xml_declaration=True, encoding='UTF-8', standalone=True))
for part, lst in rels.items():
    root = etree.Element(f'{{{PR}}}Relationships', nsmap={None: PR})
    here = posixpath.dirname(short.get(part, ''))
    for rid, typ, tgt, ext in lst:
        target = tgt if ext else posixpath.relpath(short[tgt], here or '.')
        e = etree.SubElement(root, f'{{{PR}}}Relationship', Id=rid, Type=typ, Target=target)
        if ext:
            e.set('TargetMode', 'External')
    name = '_rels/.rels' if part == '' else rels_name(short[part])
    out.writestr(name, etree.tostring(root, xml_declaration=True, encoding='UTF-8', standalone=True))
for p in keep:
    out.writestr(short[p], lean_xml(p, z.read(p)))
out.close()
print(dst, sum(i.compress_size for i in zipfile.ZipFile(dst).infolist()))
