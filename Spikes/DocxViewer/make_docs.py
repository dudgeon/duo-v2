"""Test Word documents for the .docx viewer spike, written by hand with the standard library
(python-docx can't write comments' threads, tracked changes, moves or fields anyway).

    python3 make_docs.py [out-dir]        # default: docs/

  basics.docx  headings and styles, nested bulleted and numbered lists, a TOC field, a header and
               a footer with PAGE / NUMPAGES fields, a footnote and an endnote, a page break and a
               landscape section.
  review.docx  comments from two authors with dates, a reply (commentsExtended paraIdParent), a
               resolved comment (done="1"), a comment over two paragraphs; tracked insertions and
               deletions by three authors, a formatting change (rPrChange), a paragraph-property
               change (pPrChange), a moved paragraph (moveFrom/moveTo), an inserted and a deleted
               paragraph mark, a tracked table-row insertion.
  layout.docx  a table with merged cells (gridSpan, vMerge) and shading, an inline PNG, a floating
               anchored PNG with square wrap, a two-column section, a text box (wps + VML fallback).

Every paragraph carries a w14:paraId (Word writes one on each), so the viewer and the outline can
name paragraphs the same way. Everything here is made up: this is a public repo.
"""
import os, struct, sys, zipfile, zlib
from xml.sax.saxutils import escape

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "docs")
os.makedirs(OUT, exist_ok=True)

NS = {
    "w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    "wp": "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing",
    "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
    "pic": "http://schemas.openxmlformats.org/drawingml/2006/picture",
    "mc": "http://schemas.openxmlformats.org/markup-compatibility/2006",
    "w14": "http://schemas.microsoft.com/office/word/2010/wordml",
    "w15": "http://schemas.microsoft.com/office/word/2012/wordml",
    "w16cid": "http://schemas.microsoft.com/office/word/2016/wordml/cid",
    "wps": "http://schemas.microsoft.com/office/word/2010/wordprocessingShape",
    "wp14": "http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing",
    "v": "urn:schemas-microsoft-com:vml",
    "o": "urn:schemas-microsoft-com:office:office",
    "w10": "urn:schemas-microsoft-com:office:word",
}
DECL = " ".join(f'xmlns:{k}="{v}"' for k, v in NS.items()) + ' mc:Ignorable="w14 w15 w16cid wp14"'
HEAD = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
CT = "application/vnd.openxmlformats-officedocument.wordprocessingml."

AUTHORS = {"A": ("Avery Reviewer", "AR"), "B": ("Blake Editor", "BE"), "C": ("Casey Counsel", "CC")}


# Attribute snippets with quotes, kept out of f-string expressions (Python 3.9 has no backslashes there).
GRIDCOL = '<w:gridCol w:w="%s"/>'
TYPE = '<w:type w:val="%s"/>'
ORIENT = ' w:orient="landscape"'
TIGHT = '<w:spacing w:after="0" w:line="240" w:lineRule="auto"/>'
RSTYLE = '<w:rStyle w:val="%s"/>'
EXTERNAL = ' TargetMode="External"'
PARENT = ' w15:paraIdParent="%s"'


class Ids:
    def __init__(self):
        self.para = 0x1A2B0001
        self.rev = 100
        self.doc_pr = 1

    def pid(self):
        self.para += 7
        return f"{self.para:08X}"

    def r(self):
        self.rev += 1
        return self.rev


ids = Ids()


def png(w, h, fn):
    """A PNG from fn(x, y) -> (r, g, b), so the test needs no image files."""
    raw = b"".join(b"\x00" + b"".join(bytes(fn(x, y)) for x in range(w)) for y in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


# ---- run and paragraph helpers -------------------------------------------------------------

def t(text, tag="w:t"):
    return f'<{tag} xml:space="preserve">{escape(text)}</{tag}>'


def R(text="", rpr="", inner=None):
    body = inner if inner is not None else t(text)
    return f"<w:r>{f'<w:rPr>{rpr}</w:rPr>' if rpr else ''}{body}</w:r>"


def P(*runs, style=None, ppr="", pid=None, mark_rpr=""):
    pid = pid or ids.pid()
    props = (f'<w:pStyle w:val="{style}"/>' if style else "") + ppr + (f"<w:rPr>{mark_rpr}</w:rPr>" if mark_rpr else "")
    return (f'<w:p w14:paraId="{pid}" w14:textId="77777777">'
            f"{f'<w:pPr>{props}</w:pPr>' if props else ''}{''.join(runs)}</w:p>")


def LI(text, num, lvl, *more):
    return P(R(text), *more, style="ListParagraph", ppr=f'<w:numPr><w:ilvl w:val="{lvl}"/><w:numId w:val="{num}"/></w:numPr>')


def who(k, day):
    return f'w:author="{AUTHORS[k][0]}" w:date="2026-09-{day:02d}T{9 + day % 8:02d}:15:00Z"'


def INS(k, day, *runs):
    return f'<w:ins w:id="{ids.r()}" {who(k, day)}>{"".join(runs)}</w:ins>'


def DEL(k, day, text):
    return f'<w:del w:id="{ids.r()}" {who(k, day)}>{R(inner=t(text, "w:delText"))}</w:del>'


def fld(instr, cached):
    """A complex field: begin, instruction, separate, cached result, end."""
    return (R(inner='<w:fldChar w:fldCharType="begin"/>') + R(inner=t(" " + instr + " ", "w:instrText"))
            + R(inner='<w:fldChar w:fldCharType="separate"/>') + R(cached) + R(inner='<w:fldChar w:fldCharType="end"/>'))


def picture(rid, name, cx_px, cy_px, anchor=None):
    cx, cy = cx_px * 9525, cy_px * 9525
    n = ids.doc_pr; ids.doc_pr += 1
    graphic = (f'<a:graphic><a:graphicData uri="{NS["pic"]}"><pic:pic><pic:nvPicPr><pic:cNvPr id="{n}" name="{name}"/><pic:cNvPicPr/></pic:nvPicPr>'
               f'<pic:blipFill><a:blip r:embed="{rid}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
               f'<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic>')
    if anchor is None:
        d = (f'<wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="{cx}" cy="{cy}"/><wp:effectExtent l="0" t="0" r="0" b="0"/>'
             f'<wp:docPr id="{n}" name="{name}"/><wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>{graphic}</wp:inline>')
    else:
        d = (f'<wp:anchor distT="0" distB="0" distL="114300" distR="114300" simplePos="0" relativeHeight="251660288" behindDoc="0" locked="0" layoutInCell="1" allowOverlap="1">'
             f'<wp:simplePos x="0" y="0"/><wp:positionH relativeFrom="column"><wp:align>{anchor}</wp:align></wp:positionH>'
             f'<wp:positionV relativeFrom="paragraph"><wp:posOffset>0</wp:posOffset></wp:positionV>'
             f'<wp:extent cx="{cx}" cy="{cy}"/><wp:effectExtent l="0" t="0" r="0" b="0"/><wp:wrapSquare wrapText="bothSides"/>'
             f'<wp:docPr id="{n}" name="{name}"/><wp:cNvGraphicFramePr/>{graphic}</wp:anchor>')
    return R(inner=f"<w:drawing>{d}</w:drawing>")


def text_box(paras_dml, paras_vml, w_pt=220, h_pt=70):
    n = ids.doc_pr; ids.doc_pr += 1
    cx, cy = int(w_pt * 12700), int(h_pt * 12700)
    choice = (f'<w:drawing><wp:anchor distT="45720" distB="45720" distL="114300" distR="114300" simplePos="0" relativeHeight="251661312" behindDoc="0" locked="0" layoutInCell="1" allowOverlap="1">'
              f'<wp:simplePos x="0" y="0"/><wp:positionH relativeFrom="column"><wp:align>center</wp:align></wp:positionH>'
              f'<wp:positionV relativeFrom="paragraph"><wp:posOffset>0</wp:posOffset></wp:positionV>'
              f'<wp:extent cx="{cx}" cy="{cy}"/><wp:effectExtent l="0" t="0" r="0" b="0"/><wp:wrapTopAndBottom/>'
              f'<wp:docPr id="{n}" name="Text Box {n}"/><wp:cNvGraphicFramePr/>'
              f'<a:graphic><a:graphicData uri="{NS["wps"]}"><wps:wsp><wps:cNvSpPr txBox="1"/>'
              f'<wps:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
              f'<a:solidFill><a:srgbClr val="EAF2FB"/></a:solidFill><a:ln w="19050"><a:solidFill><a:srgbClr val="2F5597"/></a:solidFill></a:ln></wps:spPr>'
              f'<wps:txbx><w:txbxContent>{paras_dml}</w:txbxContent></wps:txbx>'
              f'<wps:bodyPr rot="0" vert="horz" wrap="square" lIns="91440" tIns="45720" rIns="91440" bIns="45720" anchor="t"/></wps:wsp>'
              f'</a:graphicData></a:graphic></wp:anchor></w:drawing>')
    fallback = (f'<w:pict><v:shapetype id="_x0000_t202" coordsize="21600,21600" o:spt="202" path="m,l,21600r21600,l21600,xe"><v:stroke joinstyle="miter"/><v:path gradientshapeok="t" o:connecttype="rect"/></v:shapetype>'
                f'<v:shape id="Text Box {n}" o:spid="_x0000_s10{n:02d}" type="#_x0000_t202" style="position:absolute;margin-left:0;margin-top:0;width:{w_pt}pt;height:{h_pt}pt;z-index:251661312;mso-position-horizontal:center;mso-position-horizontal-relative:text" fillcolor="#eaf2fb" strokecolor="#2f5597" strokeweight="1.5pt">'
                f'<v:textbox><w:txbxContent>{paras_vml}</w:txbxContent></v:textbox><w10:wrap type="topAndBottom"/></v:shape></w:pict>')
    return R(inner=f'<mc:AlternateContent><mc:Choice Requires="wps">{choice}</mc:Choice><mc:Fallback>{fallback}</mc:Fallback></mc:AlternateContent>')


def cell(content, w, tcpr=""):
    return f'<w:tc><w:tcPr><w:tcW w:w="{w}" w:type="dxa"/>{tcpr}</w:tcPr>{content}</w:tc>'


def shd(fill):
    return f'<w:shd w:val="clear" w:color="auto" w:fill="{fill}"/>'


def table(rows, grid):
    borders = "".join(f'<w:{s} w:val="single" w:sz="6" w:space="0" w:color="808080"/>' for s in ("top", "left", "bottom", "right", "insideH", "insideV"))
    return (f'<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="0" w:type="auto"/><w:tblBorders>{borders}</w:tblBorders>'
            f'<w:tblLook w:val="04A0" w:firstRow="1" w:lastRow="0" w:firstColumn="1" w:lastColumn="0" w:noHBand="0" w:noVBand="1"/></w:tblPr>'
            f'<w:tblGrid>{"".join(GRIDCOL % g for g in grid)}</w:tblGrid>{"".join(rows)}</w:tbl>')


def sect(landscape=False, cols=1, kind=None, hf=False):
    w, h = (15840, 12240) if landscape else (12240, 15840)
    refs = ('<w:headerReference w:type="default" r:id="rIdHeader1"/><w:footerReference w:type="default" r:id="rIdFooter1"/>' if hf else "")
    return (f'<w:sectPr>{refs}{TYPE % kind if kind else ""}'
            f'<w:pgSz w:w="{w}" w:h="{h}"{ORIENT if landscape else ""}/>'
            f'<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>'
            f'<w:cols w:num="{cols}" w:space="720"/><w:docGrid w:linePitch="360"/></w:sectPr>')


# ---- shared parts -----------------------------------------------------------------------------

def style(sid, name, kind="paragraph", based="Normal", ppr="", rpr="", extra=""):
    b = f'<w:basedOn w:val="{based}"/>' if based else ""
    return (f'<w:style w:type="{kind}" w:styleId="{sid}"><w:name w:val="{name}"/>{b}{extra}'
            f"{f'<w:pPr>{ppr}</w:pPr>' if ppr else ''}{f'<w:rPr>{rpr}</w:rPr>' if rpr else ''}</w:style>")


STYLES = (HEAD + f'<w:styles {DECL}>'
          '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/><w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="en-US"/></w:rPr></w:rPrDefault>'
          '<w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="259" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
          + style("Normal", "Normal", based=None, extra='<w:qFormat/>').replace("<w:style ", '<w:style w:default="1" ', 1)
          + style("Title", "Title", ppr='<w:spacing w:after="80"/>', rpr='<w:rFonts w:ascii="Calibri Light" w:hAnsi="Calibri Light"/><w:spacing w:val="-10"/><w:sz w:val="56"/>', extra='<w:next w:val="Normal"/><w:qFormat/>')
          + style("Heading1", "heading 1", ppr='<w:keepNext/><w:spacing w:before="360" w:after="120"/><w:outlineLvl w:val="0"/>', rpr='<w:b/><w:color w:val="2F5597"/><w:sz w:val="32"/>', extra='<w:next w:val="Normal"/><w:qFormat/>')
          + style("Heading2", "heading 2", ppr='<w:keepNext/><w:spacing w:before="240" w:after="80"/><w:outlineLvl w:val="1"/>', rpr='<w:b/><w:color w:val="2F5597"/><w:sz w:val="26"/>', extra='<w:next w:val="Normal"/><w:qFormat/>')
          + style("Heading3", "heading 3", ppr='<w:keepNext/><w:spacing w:before="160" w:after="40"/><w:outlineLvl w:val="2"/>', rpr='<w:i/><w:color w:val="1F3763"/><w:sz w:val="24"/>', extra='<w:next w:val="Normal"/><w:qFormat/>')
          + style("Quote", "Quote", ppr='<w:ind w:left="864" w:right="864"/><w:jc w:val="center"/>', rpr='<w:i/><w:color w:val="404040"/>')
          + style("ListParagraph", "List Paragraph", ppr='<w:ind w:left="720"/><w:contextualSpacing/>')
          + style("TOCHeading", "TOC Heading", based="Heading1", ppr='<w:outlineLvl w:val="9"/>')
          + style("TOC1", "toc 1", ppr='<w:tabs><w:tab w:val="right" w:leader="dot" w:pos="9350"/></w:tabs><w:spacing w:after="100"/>')
          + style("TOC2", "toc 2", ppr='<w:tabs><w:tab w:val="right" w:leader="dot" w:pos="9350"/></w:tabs><w:spacing w:after="100"/><w:ind w:left="220"/>')
          + style("Header", "header", ppr='<w:tabs><w:tab w:val="center" w:pos="4680"/><w:tab w:val="right" w:pos="9360"/></w:tabs><w:spacing w:after="0"/>')
          + style("Footer", "footer", ppr='<w:tabs><w:tab w:val="center" w:pos="4680"/><w:tab w:val="right" w:pos="9360"/></w:tabs><w:spacing w:after="0"/>')
          + style("FootnoteText", "footnote text", ppr='<w:spacing w:after="0"/>', rpr='<w:sz w:val="20"/>')
          + style("EndnoteText", "endnote text", ppr='<w:spacing w:after="0"/>', rpr='<w:sz w:val="20"/>')
          + style("CommentText", "annotation text", rpr='<w:sz w:val="20"/>')
          + style("FootnoteReference", "footnote reference", kind="character", based="DefaultParagraphFont", rpr='<w:vertAlign w:val="superscript"/>')
          + style("EndnoteReference", "endnote reference", kind="character", based="DefaultParagraphFont", rpr='<w:vertAlign w:val="superscript"/>')
          + style("CommentReference", "annotation reference", kind="character", based="DefaultParagraphFont", rpr='<w:sz w:val="16"/>')
          + style("Hyperlink", "Hyperlink", kind="character", based="DefaultParagraphFont", rpr='<w:color w:val="0563C1"/><w:u w:val="single"/>')
          + style("DefaultParagraphFont", "Default Paragraph Font", kind="character", based=None).replace("<w:style ", '<w:style w:default="1" ', 1)
          + style("TableGrid", "Table Grid", kind="table", based=None, ppr='<w:spacing w:after="0" w:line="240" w:lineRule="auto"/>')
          + "</w:styles>")


def numbering():
    def lvl(i, fmt, text, ind, font=None):
        rpr = f'<w:rPr><w:rFonts w:ascii="{font}" w:hAnsi="{font}" w:hint="default"/></w:rPr>' if font else ""
        return (f'<w:lvl w:ilvl="{i}"><w:start w:val="1"/><w:numFmt w:val="{fmt}"/><w:lvlText w:val="{text}"/><w:lvlJc w:val="left"/>'
                f'<w:pPr><w:ind w:left="{ind}" w:hanging="360"/></w:pPr>{rpr}</w:lvl>')
    bullets = [("•", "Symbol"), ("o", "Courier New"), ("▪", "Wingdings")]
    bul = "".join(lvl(i, "bullet", bullets[i % 3][0], 720 * (i + 1), bullets[i % 3][1]) for i in range(9))
    fmts = ["decimal", "lowerLetter", "lowerRoman"]
    dec = "".join(lvl(i, fmts[i % 3], f"%{i + 1}.", 720 * (i + 1)) for i in range(9))
    return (HEAD + f'<w:numbering {DECL}>'
            f'<w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="hybridMultilevel"/>{bul}</w:abstractNum>'
            f'<w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="hybridMultilevel"/>{dec}</w:abstractNum>'
            '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num><w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num></w:numbering>')


def notes(kind, items):
    tag = kind[:-1]  # footnote / endnote
    sep = (f'<w:{tag} w:type="separator" w:id="-1">{P(R(inner="<w:separator/>"), ppr=TIGHT)}</w:{tag}>'
           f'<w:{tag} w:type="continuationSeparator" w:id="0">{P(R(inner="<w:continuationSeparator/>"), ppr=TIGHT)}</w:{tag}>')
    st = "FootnoteText" if tag == "footnote" else "EndnoteText"
    ref = "FootnoteReference" if tag == "footnote" else "EndnoteReference"
    body = "".join(f'<w:{tag} w:id="{i}">{P(R(rpr=RSTYLE % ref, inner=f"<w:{tag}Ref/>"), R(" " + text), style=st)}</w:{tag}>' for i, text in items)
    return HEAD + f"<w:{kind} {DECL}>{sep}{body}</w:{kind}>"


def settings(track=False):
    return (HEAD + f'<w:settings {DECL}>{"<w:trackRevisions/>" if track else ""}<w:defaultTabStop w:val="720"/>'
            '<w:characterSpacingControl w:val="doNotCompress"/>'
            '<w:footnotePr><w:footnote w:id="-1"/><w:footnote w:id="0"/></w:footnotePr><w:endnotePr><w:endnote w:id="-1"/><w:endnote w:id="0"/></w:endnotePr>'
            '<w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>')


def write_docx(name, body, parts, rels, overrides, title):
    """parts: {path-in-zip: bytes|str}; rels: [(rId, type, target, external?)]; overrides: [(part, content-type)]."""
    doc = HEAD + f"<w:document {DECL}><w:body>{body}</w:body></w:document>"
    all_rels = [("rIdStyles", REL + "styles", "styles.xml"), ("rIdNumbering", REL + "numbering", "numbering.xml"),
                ("rIdSettings", REL + "settings", "settings.xml")] + rels
    rel_xml = HEAD + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' + "".join(
        f'<Relationship Id="{r[0]}" Type="{r[1]}" Target="{escape(r[2])}"{EXTERNAL if len(r) > 3 else ""}/>' for r in all_rels) + "</Relationships>"
    ovr = [("/word/document.xml", CT + "document.main+xml"), ("/word/styles.xml", CT + "styles+xml"),
           ("/word/numbering.xml", CT + "numbering+xml"), ("/word/settings.xml", CT + "settings+xml"),
           ("/docProps/core.xml", "application/vnd.openxmlformats-package.core-properties+xml")] + overrides
    types = (HEAD + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
             '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
             '<Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/>'
             + "".join(f'<Override PartName="{p}" ContentType="{c}"/>' for p, c in ovr) + "</Types>")
    core = (HEAD + '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" '
            'xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
            f'<dc:title>{escape(title)}</dc:title><dc:creator>Duo spike</dc:creator>'
            '<dcterms:created xsi:type="dcterms:W3CDTF">2026-09-01T09:00:00Z</dcterms:created></cp:coreProperties>')
    path = os.path.join(OUT, name)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", types)
        z.writestr("_rels/.rels", HEAD + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                   f'<Relationship Id="rId1" Type="{REL}officeDocument" Target="word/document.xml"/>'
                   '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>')
        z.writestr("docProps/core.xml", core)
        z.writestr("word/document.xml", doc)
        z.writestr("word/_rels/document.xml.rels", rel_xml)
        z.writestr("word/styles.xml", STYLES)
        z.writestr("word/numbering.xml", numbering())
        for p, data in parts.items():
            z.writestr(p, data)
    print("wrote", path)


NOTE_RELS = [("rIdFootnotes", REL + "footnotes", "footnotes.xml"), ("rIdEndnotes", REL + "endnotes", "endnotes.xml")]
NOTE_OVR = [("/word/footnotes.xml", CT + "footnotes+xml"), ("/word/endnotes.xml", CT + "endnotes+xml")]


def fn_ref(i):
    return R(rpr='<w:rStyle w:val="FootnoteReference"/>', inner=f'<w:footnoteReference w:id="{i}"/>')


def en_ref(i):
    return R(rpr='<w:rStyle w:val="EndnoteReference"/>', inner=f'<w:endnoteReference w:id="{i}"/>')


# ---- 1. basics --------------------------------------------------------------------------------

def basics():
    toc_entries = [("Introduction", 1, 1), ("Lists", 2, 1), ("Notes and fields", 2, 1), ("A landscape section", 1, 2), ("Wide content", 2, 2)]
    toc = (P(R("Contents"), style="TOCHeading")
           + P(R(inner='<w:fldChar w:fldCharType="begin"/>'), R(inner=t(' TOC \\o "1-3" \\h \\z \\u ', "w:instrText")), R(inner='<w:fldChar w:fldCharType="separate"/>'),
               R(toc_entries[0][0]), R(inner="<w:tab/>"), R(str(toc_entries[0][2])), style="TOC1")
           + "".join(P(R(e), R(inner="<w:tab/>"), R(str(pg)), style=f"TOC{lv}") for e, lv, pg in toc_entries[1:])
           + P(R(inner='<w:fldChar w:fldCharType="end"/>')))
    body = (P(R("Basics test document"), style="Title")
            + P(R("A made-up report to test how a viewer draws ordinary Word structure. ", ""), R("Bold", "<w:b/>"), R(", "), R("italic", "<w:i/>"), R(", "),
                R("underlined", '<w:u w:val="single"/>'), R(", "), R("red", '<w:color w:val="C00000"/>'), R(", "), R("highlighted", '<w:highlight w:val="yellow"/>'),
                R(", "), R("struck", "<w:strike/>"), R(", "), R("small caps", "<w:smallCaps/>"), R(" and "), R("Courier", '<w:rFonts w:ascii="Courier New" w:hAnsi="Courier New"/>'), R(" runs."))
            + toc
            + P(R("Introduction"), style="Heading1")
            + P(R("The garden on Example Street grew more beans than anyone wanted"), fn_ref(1), R(". The committee met twice"), en_ref(1), R(" and agreed to give the surplus away. "),
                f'<w:hyperlink r:id="rIdLink1" w:history="1">{R("A link to example.com", rpr=RSTYLE % "Hyperlink")}</w:hyperlink>', R("."))
            + P(R("Paragraph styles: this one is a Quote, centred and indented."), style="Quote")
            + P(R("This paragraph is justified and has a first-line indent so its layout is visible when the text wraps over more than one line of the page in the viewer."), ppr='<w:ind w:firstLine="720"/><w:jc w:val="both"/>')
            + P(R("Lists"), style="Heading2")
            + LI("Bullet one", 1, 0) + LI("Bullet one point one", 1, 1) + LI("Bullet one point one point one", 1, 2) + LI("Bullet two", 1, 0)
            + P(R("And a numbered list:"))
            + LI("First step", 2, 0) + LI("Sub-step a", 2, 1) + LI("Sub-step b", 2, 1) + LI("Sub-sub-step i", 2, 2) + LI("Second step", 2, 0) + LI("Third step", 2, 0)
            + P(R("Notes and fields"), style="Heading2")
            + P(R("This sentence has a second footnote"), fn_ref(2), R(" and today's page number is "), fld("PAGE", "1"), R("."))
            + P(R("Heading three under Notes"), style="Heading3")
            + P(R("The next thing is a page break."))
            + P(R(inner='<w:br w:type="page"/>'), R("This paragraph starts after a manual page break, on page 2 of the portrait section."))
            + P(R("The section ends here; the next one is landscape."), ppr=sect(hf=True))
            + P(R("A landscape section"), style="Heading1")
            + P(R("Wide content"), style="Heading2")
            + P(R("This section is 11 by 8.5 inches, landscape. A viewer that ignores sections draws it portrait. "
                  "This paragraph is long enough to show how wide the text column is when it wraps across the landscape page width."))
            + sect(landscape=True, hf=True))
    hdr = (HEAD + f'<w:hdr {DECL}>' + P(R("Basics test", "<w:b/>"), R(inner="<w:tab/>"), R("Example Street Garden"), R(inner="<w:tab/>"), R("CONFIDENTIAL", '<w:color w:val="C00000"/>'), style="Header") + "</w:hdr>")
    ftr = (HEAD + f'<w:ftr {DECL}>' + P(R(inner="<w:tab/>"), R("Page "), fld("PAGE", "1"), R(" of "),
                                         f'<w:fldSimple w:instr=" NUMPAGES ">{R("3")}</w:fldSimple>', style="Footer", ppr='<w:jc w:val="center"/>') + "</w:ftr>")
    parts = {"word/footnotes.xml": notes("footnotes", [(1, "Beans: mostly runner beans, some broad."), (2, "A second footnote, to check numbering.")]),
             "word/endnotes.xml": notes("endnotes", [(1, "Minutes of both meetings are in the shed.")]),
             "word/header1.xml": hdr, "word/footer1.xml": ftr, "word/settings.xml": settings()}
    rels = NOTE_RELS + [("rIdHeader1", REL + "header", "header1.xml"), ("rIdFooter1", REL + "footer", "footer1.xml"),
                        ("rIdLink1", REL + "hyperlink", "https://example.com/", True)]
    ovr = NOTE_OVR + [("/word/header1.xml", CT + "header+xml"), ("/word/footer1.xml", CT + "footer+xml")]
    write_docx("basics.docx", body, parts, rels, ovr, "Basics test")


# ---- 2. review --------------------------------------------------------------------------------

def review():
    comments, ext, cids = [], [], []

    def comment(cid, k, day, text, parent=None, done=False):
        pid = ids.pid()
        comments.append(f'<w:comment w:id="{cid}" {who(k, day)} w:initials="{AUTHORS[k][1]}">'
                        + P(R(rpr='<w:rStyle w:val="CommentReference"/>', inner="<w:annotationRef/>"), R(text), style="CommentText", pid=pid) + "</w:comment>")
        ext.append(f'<w15:commentEx w15:paraId="{pid}"{PARENT % parent if parent else ""} w15:done="{1 if done else 0}"/>')
        cids.append(f'<w16cid:commentId w16cid:paraId="{pid}" w16cid:durableId="{0x5A000000 + cid:08X}"/>')
        return pid

    def cstart(*cs):
        return "".join(f'<w:commentRangeStart w:id="{c}"/>' for c in cs)

    def cend(*cs):
        return "".join(f'<w:commentRangeEnd w:id="{c}"/>' + R(rpr='<w:rStyle w:val="CommentReference"/>', inner=f'<w:commentReference w:id="{c}"/>') for c in cs)

    c0 = comment(0, "A", 1, "Is “forty” right? The spreadsheet says forty-two.")
    comment(1, "B", 2, "Checked: forty-two. I'll fix it.", parent=c0)
    comment(2, "B", 3, "Typo here, fixed.", done=True)
    comment(3, "A", 4, "These two paragraphs say the same thing; merge them?")

    mv = ids.r()
    mv2 = ids.r()
    body = (P(R("Review test document"), style="Title")
            + P(R("Comments"), style="Heading1")
            + P(R("The volunteers planted "), cstart(0, 1), R("forty"), cend(0, 1), R(" rows of beans in April."))
            + P(R("The shed was "), cstart(2), R("painted"), cend(2), R(" green in May. (This comment is resolved.)"))
            + P(cstart(3), R("Watering was done by rota every evening."))
            + P(R("Every evening, someone on the rota watered the beds."), cend(3))
            + P(R("Tracked changes"), style="Heading1")
            + P(R("Avery inserted "), INS("A", 5, R("these words ")), R("and Blake deleted "), DEL("B", 6, "some old words "), R("in this sentence."))
            + P(R("Casey "), INS("C", 7, R("(a third author) ")), R("added text, and Blake replaced "), DEL("B", 6, "three"), INS("B", 6, R("four")), R(" words."))
            + P(R("Blake made "), R("this phrase bold", f'<w:b/><w:rPrChange w:id="{ids.r()}" {who("B", 8)}><w:rPr/></w:rPrChange>'),
                R(" and "), R("this one italic and red", f'<w:i/><w:color w:val="C00000"/><w:rPrChange w:id="{ids.r()}" {who("B", 8)}><w:rPr><w:b/></w:rPr></w:rPrChange>'), R(" (formatting changes)."))
            + P(R("Avery centred this paragraph (a paragraph-property change)."), ppr=f'<w:jc w:val="center"/><w:pPrChange w:id="{ids.r()}" {who("A", 9)}><w:pPr/></w:pPrChange>')
            + P(INS("A", 10, R("Avery inserted this whole paragraph.")), mark_rpr=f'<w:ins w:id="{ids.r()}" {who("A", 10)}/>')
            + P(DEL("C", 11, "Casey deleted this whole paragraph."), mark_rpr=f'<w:del w:id="{ids.r()}" {who("C", 11)}/>')
            + P(R("Moves"), style="Heading2")
            + P(R("First in order."))
            + P(f'<w:moveFromRangeStart w:id="{mv}" w:name="move1" {who("B", 12)}/>'
                f'<w:moveFrom w:id="{ids.r()}" {who("B", 12)}>{R("This paragraph was moved down by Blake.")}</w:moveFrom>'
                f'<w:moveFromRangeEnd w:id="{mv}"/>', mark_rpr=f'<w:moveFrom w:id="{ids.r()}" {who("B", 12)}/>')
            + P(R("Second in order."))
            + P(f'<w:moveToRangeStart w:id="{mv2}" w:name="move1" {who("B", 12)}/>'
                f'<w:moveTo w:id="{ids.r()}" {who("B", 12)}>{R("This paragraph was moved down by Blake.")}</w:moveTo>'
                f'<w:moveToRangeEnd w:id="{mv2}"/>', mark_rpr=f'<w:moveTo w:id="{ids.r()}" {who("B", 12)}/>')
            + P(R("A table with a tracked row"), style="Heading2")
            + table([
                "<w:tr>" + cell(P(R("Bed", "<w:b/>")), 3000) + cell(P(R("Crop", "<w:b/>")), 3000) + "</w:tr>",
                "<w:tr>" + cell(P(R("1")), 3000) + cell(P(R("Beans")), 3000) + "</w:tr>",
                f'<w:tr><w:trPr><w:ins w:id="{ids.r()}" {who("A", 13)}/></w:trPr>'
                + cell(P(INS("A", 13, R("2")), mark_rpr=f'<w:ins w:id="{ids.r()}" {who("A", 13)}/>'), 3000)
                + cell(P(INS("A", 13, R("Squash (row inserted by Avery)")), mark_rpr=f'<w:ins w:id="{ids.r()}" {who("A", 13)}/>'), 3000) + "</w:tr>",
                "<w:tr>" + cell(P(R("3")), 3000) + cell(P(R("Peas")), 3000) + "</w:tr>",
            ], [3000, 3000])
            + P(R("End of the review test."))
            + sect())
    w15 = f'xmlns:w15="{NS["w15"]}" xmlns:mc="{NS["mc"]}"'
    people = (HEAD + f'<w15:people {w15} xmlns:w="{NS["w"]}">' + "".join(
        f'<w15:person w15:author="{n}"><w15:presenceInfo w15:providerId="None" w15:userId="{n}"/></w15:person>' for n, _ in AUTHORS.values()) + "</w15:people>")
    parts = {"word/comments.xml": HEAD + f"<w:comments {DECL}>{''.join(comments)}</w:comments>",
             "word/commentsExtended.xml": HEAD + f'<w15:commentsEx {DECL}>{"".join(ext)}</w15:commentsEx>',
             "word/commentsIds.xml": HEAD + f'<w16cid:commentsIds {DECL}>{"".join(cids)}</w16cid:commentsIds>',
             "word/people.xml": people, "word/settings.xml": settings(track=True)}
    rels = [("rIdComments", REL + "comments", "comments.xml"),
            ("rIdCommentsEx", "http://schemas.microsoft.com/office/2011/relationships/commentsExtended", "commentsExtended.xml"),
            ("rIdCommentsIds", "http://schemas.microsoft.com/office/2016/09/relationships/commentsIds", "commentsIds.xml"),
            ("rIdPeople", "http://schemas.microsoft.com/office/2011/relationships/people", "people.xml")]
    ovr = [("/word/comments.xml", CT + "comments+xml"), ("/word/commentsExtended.xml", CT + "commentsExtended+xml"),
           ("/word/commentsIds.xml", CT + "commentsIds+xml"), ("/word/people.xml", CT + "people+xml")]
    write_docx("review.docx", body, parts, rels, ovr, "Review test")


# ---- 3. layout --------------------------------------------------------------------------------

def layout():
    grad = png(240, 140, lambda x, y: (40 + x * 200 // 240, 90 + y, 200 - x * 120 // 240))
    rings = png(140, 140, lambda x, y: (230, 120, 40) if ((x - 70) ** 2 + (y - 70) ** 2) // 400 % 2 == 0 else (250, 230, 200))
    head = shd("2F5597")
    W = '<w:color w:val="FFFFFF"/><w:b/>'
    rows = [
        '<w:tr><w:trPr><w:tblHeader/></w:trPr>' + "".join(cell(P(R(h, W)), 2200, head) for h in ("Region", "Q1", "Q2", "Q3")) + "</w:tr>",
        "<w:tr>" + cell(P(R("North (merged down)")), 2200, '<w:vMerge w:val="restart"/>' + shd("DEEAF6") + '<w:vAlign w:val="center"/>')
        + cell(P(R("10")), 2200) + cell(P(R("12")), 2200) + cell(P(R("14")), 2200) + "</w:tr>",
        "<w:tr>" + cell(P(), 2200, "<w:vMerge/>" + shd("DEEAF6")) + cell(P(R("11")), 2200) + cell(P(R("13")), 2200) + cell(P(R("15")), 2200) + "</w:tr>",
        "<w:tr>" + cell(P(R("South")), 2200) + cell(P(R("Q1 and Q2 merged across")), 4400, '<w:gridSpan w:val="2"/>' + shd("E2EFD9")) + cell(P(R("9")), 2200) + "</w:tr>",
        "<w:tr>" + cell(P(R("Total (three columns merged)", "<w:b/>"), ppr='<w:jc w:val="right"/>'), 6600, '<w:gridSpan w:val="3"/>' + shd("FFF2CC"))
        + cell(P(R("75", "<w:b/>")), 2200, shd("FFF2CC")) + "</w:tr>",
    ]
    lorem = ("Text flows around the floating picture on the right. The picture is anchored to this paragraph with square wrapping, "
             "so a faithful viewer puts it at the right margin and wraps these lines beside it rather than above or below it. ")
    col = ("This is the two-column section. The text continues from the bottom of the first column to the top of the second, "
           "as in a newsletter. A viewer that ignores w:cols draws it as one wide column. ")
    body = (P(R("Layout test document"), style="Title")
            + P(R("A table with merged cells and shading"), style="Heading1")
            + table(rows, [2200, 2200, 2200, 2200])
            + P(R("An inline picture"), style="Heading1")
            + P(R("Before the picture "), picture("rIdImg1", "Gradient", 240, 140), R(" after the picture, on the same line."))
            + P(R("A floating picture"), style="Heading1")
            + P(picture("rIdImg2", "Rings", 140, 140, anchor="right"), R(lorem * 3))
            + P(R("A text box"), style="Heading1")
            + P(text_box(P(R("Inside a text box", "<w:b/>")) + P(R("Blue fill, blue border, centred, wrap top and bottom.")),
                         P(R("Inside a text box", "<w:b/>")) + P(R("Blue fill, blue border, centred, wrap top and bottom."))),
                R("This paragraph anchors the text box; the box should sit centred above or around it."))
            + P(R("Two columns follow."), ppr=sect())
            + P(R("Two columns"), style="Heading2") + P(R(col * 4)) + P(R(col * 3))
            + P(R("End of the two-column section."), ppr=sect(cols=2, kind="continuous"))
            + P(R("Back to one column after a continuous section break."))
            + sect(kind="continuous"))
    rels = [("rIdImg1", REL + "image", "media/image1.png"), ("rIdImg2", REL + "image", "media/image2.png")]
    write_docx("layout.docx", body, {"word/media/image1.png": grad, "word/media/image2.png": rings, "word/settings.xml": settings()}, rels, [], "Layout test")


basics()
review()
layout()
