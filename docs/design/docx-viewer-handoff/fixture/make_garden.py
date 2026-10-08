"""The Word viewer's test documents (docx-viewer-handoff, slice 1), written by hand with the standard
library, adapted from Spikes/DocxViewer/make_docs.py. Everything here is made up: this is a public repo.

    python3 make_garden.py [out-dir]        # default: this folder

  board/Garden plan.docx    the document the boards draw (viewer@2x, markup@2x): a title, two headings,
                            a comment with a reply, a resolved comment, insertions and deletions by three
                            people, a formatting change and a move.
  full/Garden plan.docx     the same, with a "Watering" section after the moves that brings it to the
                            counts the fallback board's question and the Markup menu name: 12 tracked
                            changes, 4 comments; Avery 5, Blake 9, Casey 2.
  long/Long plan.docx       73 sections of body text with a few changes and comments, no saved page
                            breaks (as python-docx writes): the long-document proof.
  locked/Contract draft.docx  an OLE file, as Office saves a password-protected document (not a zip).
  damaged/Broken plan.docx    a zip cut short.

Every paragraph carries a w14:paraId, as Word writes one on each.
"""
import os, struct, sys, zipfile, zlib
from xml.sax.saxutils import escape

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
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


BODY_FONT, HEAD_FONT = "Georgia", "Helvetica Neue"
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
          '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Georgia" w:hAnsi="Georgia" w:eastAsia="Georgia" w:cs="Georgia"/><w:sz w:val="21"/><w:szCs w:val="21"/><w:lang w:val="en-US"/></w:rPr></w:rPrDefault>'
          '<w:pPrDefault><w:pPr><w:spacing w:after="150" w:line="315" w:lineRule="exact"/></w:pPr></w:pPrDefault></w:docDefaults>'
          + style("Normal", "Normal", based=None, extra='<w:qFormat/>').replace("<w:style ", '<w:style w:default="1" ', 1)
          + style("Title", "Title", ppr='<w:spacing w:after="150" w:line="420" w:lineRule="exact"/>', rpr='<w:sz w:val="33"/>', extra='<w:next w:val="Normal"/><w:qFormat/>')
          + style("Heading1", "heading 1", ppr='<w:keepNext/><w:spacing w:before="0" w:after="150" w:line="300" w:lineRule="exact"/><w:outlineLvl w:val="0"/>', rpr='<w:rFonts w:ascii="Helvetica Neue" w:hAnsi="Helvetica Neue"/><w:b/><w:color w:val="2F5496"/><w:sz w:val="23"/>', extra='<w:next w:val="Normal"/><w:qFormat/>')
          + style("Heading2", "heading 2", ppr='<w:keepNext/><w:spacing w:before="240" w:after="80"/><w:outlineLvl w:val="1"/>', rpr='<w:rFonts w:ascii="Helvetica Neue" w:hAnsi="Helvetica Neue"/><w:b/><w:color w:val="2F5597"/><w:sz w:val="24"/>', extra='<w:next w:val="Normal"/><w:qFormat/>')
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
    os.makedirs(os.path.dirname(path), exist_ok=True)
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


# ---- the documents ----------------------------------------------------------------------------

def review_parts(comments, ext, cids):
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
    return parts, rels, ovr


class Comments:
    def __init__(self):
        self.comments, self.ext, self.cids = [], [], []

    def add(self, cid, k, day, text, parent=None, done=False):
        pid = ids.pid()
        self.comments.append(f'<w:comment w:id="{cid}" {who(k, day)} w:initials="{AUTHORS[k][1]}">'
                             + P(R(rpr='<w:rStyle w:val="CommentReference"/>', inner="<w:annotationRef/>"), R(text), style="CommentText", pid=pid) + "</w:comment>")
        self.ext.append(f'<w15:commentEx w15:paraId="{pid}"{PARENT % parent if parent else ""} w15:done="{1 if done else 0}"/>')
        self.cids.append(f'<w16cid:commentId w16cid:paraId="{pid}" w16cid:durableId="{0x5A000000 + cid:08X}"/>')
        return pid


def cstart(*cs):
    return "".join(f'<w:commentRangeStart w:id="{c}"/>' for c in cs)


def cend(*cs):
    return "".join(f'<w:commentRangeEnd w:id="{c}"/>' + R(rpr='<w:rStyle w:val="CommentReference"/>', inner=f'<w:commentReference w:id="{c}"/>') for c in cs)


def garden(name, full):
    """The boards' document. `full` adds the Watering section (see the docstring for the counts)."""
    ids.__init__()
    c = Comments()
    c0 = c.add(0, "A", 1, "Is \u201cforty\u201d right? The spreadsheet says forty-two.")
    c.add(1, "B", 2, "Checked: forty-two. I'll fix it.", parent=c0)
    c.add(2, "B", 3, "Typo here, fixed.", done=True)
    if full:
        c.add(3, "A", 4, "Which rota is this: the spring one?")
    mv, mv2 = ids.r(), ids.r()
    body = (P(R("Garden plan"), style="Title")
            + P(R("Beds and crops"), style="Heading1")
            + P(R("The volunteers planted "), cstart(0, 1), R("forty"), cend(0, 1), R(" rows of beans in April."))
            + P(R("Avery inserted "), INS("A", 5, R("these words")), R(" and Blake deleted "), DEL("B", 6, "some old words"), R(" in this sentence."))
            + P(R("Casey "), INS("C", 7, R("(a third author)")), R(" added text, and Blake replaced "), DEL("B", 6, "three"), INS("B", 6, R("four")), R(" words."))
            + P(R("Blake made "), R("this phrase bold", f'<w:b/><w:rPrChange w:id="{ids.r()}" {who("B", 8)}><w:rPr/></w:rPrChange>'),
                cstart(2), R(" (a formatting change)"), cend(2), R("."))
            + P(R("Moves"), style="Heading1")
            + P(R("First in order."))
            + P(f'<w:moveFromRangeStart w:id="{mv}" w:name="move1" {who("B", 12)}/>'
                f'<w:moveFrom w:id="{ids.r()}" {who("B", 12)}>{R("This paragraph was moved down by Blake.")}</w:moveFrom>'
                f'<w:moveFromRangeEnd w:id="{mv}"/>')
            + P(R("Second in order."))
            + P(f'<w:moveToRangeStart w:id="{mv2}" w:name="move1" {who("B", 12)}/>'
                f'<w:moveTo w:id="{ids.r()}" {who("B", 12)}>{R("This paragraph was moved down by Blake.")}</w:moveTo>'
                f'<w:moveToRangeEnd w:id="{mv2}"/>'))
    if full:
        body += (P(R("Watering"), style="Heading1")
                 + P(cstart(3), R("Watering is "), INS("A", 9, R("done by rota")), R(" every evening"), cend(3), DEL("C", 10, ", at dawn"), R("."))
                 + P(R("The hose "), DEL("B", 11, "leaks"), R(" and "), INS("A", 11, R("needs a new washer")), R(".")))
    body += sect()
    parts, rels, ovr = review_parts(c.comments, c.ext, c.cids)
    write_docx(name, body, parts, rels, ovr, "Garden plan")


LOREM = ("The volunteers met on Saturday to turn the beds, sort the seed packets and write down what each row would "
         "hold this year. Beans go in after the last frost; peas can go in earlier, along the fence. ")


def long_doc(name, sections=73):
    """73 sections of about a page each: headings, body text, a few changes and comments, and no w:lastRenderedPageBreak."""
    ids.__init__()
    c = Comments()
    body = P(R("Long plan"), style="Title")
    cid = 0
    for i in range(1, sections + 1):
        body += P(R(f"Section {i}"), style="Heading1")
        for j in range(7):
            body += P(R(LOREM * 3))
        if i % 9 == 0:
            body += P(cstart(cid), R("This sentence carries a comment."), cend(cid), R(" "), INS("A", 5, R("And this one was added.")), R(" "), DEL("B", 6, "And this one was cut."))
            c.add(cid, "A", 1 + i % 20, f"Comment on section {i}.")
            cid += 1
    body += sect()
    parts, rels, ovr = review_parts(c.comments, c.ext, c.cids)
    write_docx(name, body, parts, rels, ovr, "Long plan")


garden("board/Garden plan.docx", full=False)
garden("full/Garden plan.docx", full=True)
long_doc("long/Long plan.docx")
# A password-protected document is an OLE compound file, not a zip; a damaged one is a zip cut short.
os.makedirs(os.path.join(OUT, "locked"), exist_ok=True)
with open(os.path.join(OUT, "locked/Contract draft.docx"), "wb") as f:
    f.write(bytes([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) + "EncryptedPackage".encode("utf-16-le") + b"EncryptionInfo made up for a test" + bytes(2048))
os.makedirs(os.path.join(OUT, "damaged"), exist_ok=True)
whole = open(os.path.join(OUT, "board/Garden plan.docx"), "rb").read()
open(os.path.join(OUT, "damaged/Broken plan.docx"), "wb").write(whole[: len(whole) // 2])
