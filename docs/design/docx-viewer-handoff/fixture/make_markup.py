"""Test documents for the Google Docs look and for tracked changes and comments (DL-233). Sample text only.

    python3 make_markup.py [out-dir]        # default: this folder

  look/No styles.docx        no styles at all: nothing says a font, a size or a spacing
  look/Word defaults.docx    what Word 2013+ writes: Calibri 11, Calibri Light headings, its blues
  look/Google export.docx    the styles Google Docs writes on export: Arial 11, 1.15, Title 26, Subtitle 15, Headings 1-6
  look/Own fonts.docx        its own fonts and sizes everywhere (Georgia, Verdana): these must win over the defaults
  markup/Word markup.docx    Word: insertions, deletions, formatting and paragraph-property changes, a move, a
                             whole inserted and a whole deleted paragraph, a list item, a table row, comments with
                             replies, a resolved thread, a comment over two paragraphs, a comment on an insertion;
                             three authors
  markup/Google suggestions.docx
                             written the way Google Docs exports a document with suggestions and comments (w:ins /
                             w:del with the suggester's name and a date, rPrChange for a format suggestion, comments
                             with replies and one resolved, in comments.xml and commentsExtended.xml). Google Docs
                             could not be reached from here, so this is that XML written by hand, not an export.

Every paragraph carries a w14:paraId, as Word and Google write one on each.
The helpers are make_garden.py's (the part before its documents, and its comment helpers).
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = sys.argv[1] if len(sys.argv) > 1 else HERE
_src = open(os.path.join(HERE, "make_garden.py")).read()
_helpers = _src[: _src.index("# ---- the documents")] + _src[_src.index("def review_parts"): _src.index("def garden(")]
sys.argv = [sys.argv[0], OUT_DIR]
exec(compile(_helpers, "make_garden.py", "exec"))   # defines t, R, P, INS, DEL, Comments, cstart, cend, write_docx, STYLES, ...

import re as _re

AUTHORS.update({"A": ("Dana Writer", "DW"), "B": ("Morgan Editor", "ME"), "C": ("Riley Reviewer", "RR")})


def styles(defaults_rpr, defaults_ppr, styles_xml=""):
    return (HEAD + f'<w:styles {DECL}><w:docDefaults><w:rPrDefault><w:rPr>{defaults_rpr}</w:rPr></w:rPrDefault>'
            f'<w:pPrDefault><w:pPr>{defaults_ppr}</w:pPr></w:pPrDefault></w:docDefaults>'
            + style("Normal", "Normal", based=None, extra="<w:qFormat/>").replace("<w:style ", '<w:style w:default="1" ', 1)
            + style("DefaultParagraphFont", "Default Paragraph Font", kind="character", based=None).replace("<w:style ", '<w:style w:default="1" ', 1)
            + style("CommentText", "annotation text", rpr='<w:sz w:val="20"/>')
            + style("CommentReference", "annotation reference", kind="character", based="DefaultParagraphFont", rpr='<w:sz w:val="16"/>')
            + style("ListParagraph", "List Paragraph", ppr='<w:ind w:left="720"/><w:contextualSpacing/>')
            + styles_xml + "</w:styles>")


NO_STYLES = HEAD + f"<w:styles {DECL}/>"

# What Word writes for a new blank document (2013 to 2019: Calibri, Calibri Light headings).
WORD_STYLES = styles(
    '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/><w:sz w:val="22"/><w:szCs w:val="22"/>',
    '<w:spacing w:after="160" w:line="259" w:lineRule="auto"/>',
    style("Title", "Title", ppr='<w:contextualSpacing/>', rpr='<w:rFonts w:ascii="Calibri Light" w:hAnsi="Calibri Light"/><w:spacing w:val="-10"/><w:kern w:val="28"/><w:sz w:val="56"/>', extra='<w:next w:val="Normal"/><w:qFormat/>')
    + style("Heading1", "heading 1", ppr='<w:keepNext/><w:spacing w:before="240" w:after="0"/><w:outlineLvl w:val="0"/>', rpr='<w:rFonts w:ascii="Calibri Light" w:hAnsi="Calibri Light"/><w:color w:val="2F5496"/><w:sz w:val="32"/>', extra='<w:next w:val="Normal"/><w:qFormat/>')
    + style("Heading2", "heading 2", ppr='<w:keepNext/><w:spacing w:before="40" w:after="0"/><w:outlineLvl w:val="1"/>', rpr='<w:rFonts w:ascii="Calibri Light" w:hAnsi="Calibri Light"/><w:color w:val="2F5496"/><w:sz w:val="26"/>', extra='<w:next w:val="Normal"/><w:qFormat/>'))

# What Google Docs writes on export (Arial 11, 1.15; Title 26, Subtitle 15, Headings 1-6 at Google's sizes and greys).
def _g(sid, name, before, after, size, colour=None, italic=False, keep=True, outline=None, font=None):
    ppr = ("<w:keepNext/><w:keepLines/>" if keep else "") + f'<w:spacing w:before="{before}" w:after="{after}"/>' + (f'<w:outlineLvl w:val="{outline}"/>' if outline is not None else "")
    rpr = (f'<w:rFonts w:ascii="{font}" w:hAnsi="{font}"/>' if font else "") + ("<w:i/>" if italic else "") + (f'<w:color w:val="{colour}"/>' if colour else "") + f'<w:sz w:val="{size}"/><w:szCs w:val="{size}"/>'
    return style(sid, name, ppr=ppr, rpr=rpr, extra='<w:next w:val="Normal"/><w:qFormat/>')


GOOGLE_STYLES = styles(
    '<w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="Arial" w:cs="Arial"/><w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="en"/>',
    '<w:spacing w:line="276" w:lineRule="auto"/>',
    _g("Title", "Title", 0, 60, 52, keep=True)
    + _g("Subtitle", "Subtitle", 0, 320, 30, colour="666666", font="Arial")
    + _g("Heading1", "heading 1", 400, 120, 40, outline=0) + _g("Heading2", "heading 2", 360, 120, 32, outline=1)
    + _g("Heading3", "heading 3", 320, 80, 28, colour="434343", outline=2) + _g("Heading4", "heading 4", 280, 80, 24, colour="666666", outline=3)
    + _g("Heading5", "heading 5", 240, 80, 22, colour="666666", outline=4) + _g("Heading6", "heading 6", 240, 80, 22, colour="666666", italic=True, outline=5))

# Its own styles throughout: Georgia body at 12, Verdana headings, exact spacing.
OWN_STYLES = styles(
    '<w:rFonts w:ascii="Georgia" w:hAnsi="Georgia" w:eastAsia="Georgia" w:cs="Georgia"/><w:sz w:val="24"/><w:szCs w:val="24"/>',
    '<w:spacing w:after="240" w:line="360" w:lineRule="auto"/>',
    style("Title", "Title", rpr='<w:rFonts w:ascii="Verdana" w:hAnsi="Verdana"/><w:b/><w:color w:val="7030A0"/><w:sz w:val="48"/>', extra='<w:next w:val="Normal"/><w:qFormat/>')
    + style("Heading1", "heading 1", ppr='<w:keepNext/><w:spacing w:before="480" w:after="120"/><w:outlineLvl w:val="0"/>', rpr='<w:rFonts w:ascii="Verdana" w:hAnsi="Verdana"/><w:b/><w:color w:val="C00000"/><w:sz w:val="36"/>', extra='<w:next w:val="Normal"/><w:qFormat/>')
    + style("Heading2", "heading 2", ppr='<w:keepNext/><w:spacing w:before="240" w:after="60"/><w:outlineLvl w:val="1"/>', rpr='<w:rFonts w:ascii="Verdana" w:hAnsi="Verdana"/><w:i/><w:sz w:val="28"/>', extra='<w:next w:val="Normal"/><w:qFormat/>'))

PAGE = sect()
PLAIN_BODY = (P(R("Garden notes"), style="Title") + P(R("A short plan for the spring beds"), style="Subtitle")
              + P(R("Beds and crops"), style="Heading1")
              + P(R("The volunteers meet on Saturday to turn the beds, sort the seed packets and write down what each row will hold. "
                    "Beans go in after the last frost; peas can go in earlier, along the fence.")) + P(R("A second paragraph, to show the space between them."))
              + P(R("Where things grow"), style="Heading2") + P(R("Tomatoes on the south wall."))
              + P(R("Watering"), style="Heading3") + P(R("A rota on the shed door."))
              + P(R("Tools"), style="Heading4") + P(R("Fork, spade and a good hose."))
              + P(R("Seeds"), style="Heading5") + P(R("Kept in the tin."))
              + P(R("Notes"), style="Heading6") + P(R("Ask about the compost.")) + PAGE)


def look(name, styles_xml, title, body=PLAIN_BODY):
    global STYLES
    ids.__init__()
    STYLES = styles_xml
    write_docx(name, body, {}, [], [], title)


look("look/No styles.docx", NO_STYLES, "No styles")
look("look/Word defaults.docx", WORD_STYLES, "Word defaults")
look("look/Google export.docx", GOOGLE_STYLES, "Google export")
look("look/Own fonts.docx", OWN_STYLES, "Own fonts")


# ---- tracked changes and comments ---------------------------------------------------------------

def rpr_change(k, day, old=""):
    return f'<w:rPrChange w:id="{ids.r()}" {who(k, day)}><w:rPr>{old}</w:rPr></w:rPrChange>'


def word_markup():
    global STYLES
    STYLES = WORD_STYLES
    ids.__init__()
    c = Comments()
    c0 = c.add(0, "A", 1, "Is “forty” right? The spreadsheet says forty-two.")
    c1 = c.add(1, "B", 2, "Checked: forty-two. I'll fix it.", parent=c0)
    c.add(2, "C", 3, "Thanks both.", parent=c0)
    c3 = c.add(3, "B", 3, "This heading reads oddly.", done=True)
    c.add(4, "A", 4, "Agreed, renamed.", parent=c3, done=True)
    c.add(5, "C", 5, "Does this paragraph and the next say the same thing?")
    c.add(6, "A", 6, "Who is the third author here?")
    c.add(7, "C", 7, "A point comment, on no text.")
    c.add(8, "B", 8, "Why was this cut?")
    mv, mv2 = ids.r(), ids.r()
    tbl_rows = (f'<w:tr><w:tc><w:tcPr><w:tcW w:w="4680" w:type="dxa"/></w:tcPr>{P(R("Bed"))}</w:tc><w:tc><w:tcPr><w:tcW w:w="4680" w:type="dxa"/></w:tcPr>{P(R("Crop"))}</w:tc></w:tr>'
                f'<w:tr><w:trPr><w:ins w:id="{ids.r()}" {who("B", 9)}/></w:trPr><w:tc><w:tcPr><w:tcW w:w="4680" w:type="dxa"/></w:tcPr>{P(INS("B", 9, R("North")))}</w:tc>'
                f'<w:tc><w:tcPr><w:tcW w:w="4680" w:type="dxa"/></w:tcPr>{P(INS("B", 9, R("Kale")))}</w:tc></w:tr>'
                f'<w:tr><w:trPr><w:del w:id="{ids.r()}" {who("C", 9)}/></w:trPr><w:tc><w:tcPr><w:tcW w:w="4680" w:type="dxa"/></w:tcPr>{P(DEL("C", 9, "South"))}</w:tc>'
                f'<w:tc><w:tcPr><w:tcW w:w="4680" w:type="dxa"/></w:tcPr>{P(DEL("C", 9, "Leeks"))}</w:tc></w:tr>')
    table_xml = ('<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/><w:tblBorders>'
                 + "".join(f'<w:{s} w:val="single" w:sz="4" w:space="0" w:color="808080"/>' for s in ("top", "left", "bottom", "right", "insideH", "insideV"))
                 + '</w:tblBorders></w:tblPr><w:tblGrid><w:gridCol w:w="4680"/><w:gridCol w:w="4680"/></w:tblGrid>' + tbl_rows + "</w:tbl>")
    body = (P(R("Garden plan"), style="Title")
            + P(cstart(3), R("Beds and crops"), cend(3), style="Heading1")
            + P(R("The volunteers planted "), cstart(0, 1, 2), R("forty"), cend(0, 1, 2), R(" rows of beans in April."))
            + P(R("Dana inserted "), INS("A", 5, R("these words")), R(" and Morgan deleted "), cstart(8), DEL("B", 6, "some old words"), cend(8), R(" in this sentence."))
            + P(R("Riley "), cstart(6), INS("C", 7, R("(a third author)")), cend(6), R(" added text, and Morgan replaced "), DEL("B", 6, "three"), INS("B", 6, R("four")), R(" words."))
            + P(R("Morgan made "), R("this phrase bold", "<w:b/>" + rpr_change("B", 8)), R(" and "), R("this one not italic", rpr_change("C", 8, "<w:i/>")), R(" (formatting changes)."))
            + P(R("This paragraph was centred by Riley."), ppr=f'<w:jc w:val="center"/><w:pPrChange w:id="{ids.r()}" {who("C", 8)}><w:pPr/></w:pPrChange>')
            + P(R("Paragraphs"), style="Heading1")
            + P(cstart(5), R("This paragraph is commented along with the next one."))
            + P(R("It carries the end of the comment."), cend(5))
            + P(INS("A", 9, R("This whole paragraph was inserted by Dana.")), ppr="", mark_rpr=f'<w:ins w:id="{ids.r()}" {who("A", 9)}/>')
            + P(DEL("B", 9, "This whole paragraph was deleted by Morgan."), mark_rpr=f'<w:del w:id="{ids.r()}" {who("B", 9)}/>')
            + LI("A list item that stays.", 1, 0)
            + P(INS("C", 10, R("A list item Riley added.")), style="ListParagraph", ppr='<w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr>', mark_rpr=f'<w:ins w:id="{ids.r()}" {who("C", 10)}/>')
            + P(R("A point comment sits here"), '<w:commentRangeStart w:id="7"/>' + cend(7), R("."))
            + table_xml + P()
            + P(R("Moves"), style="Heading1")
            + P(R("First in order."))
            + P(f'<w:moveFromRangeStart w:id="{mv}" w:name="move1" {who("B", 12)}/>'
                f'<w:moveFrom w:id="{ids.r()}" {who("B", 12)}>{R("This paragraph was moved down by Morgan.")}</w:moveFrom>'
                f'<w:moveFromRangeEnd w:id="{mv}"/>')
            + P(R("Second in order."))
            + P(f'<w:moveToRangeStart w:id="{mv2}" w:name="move1" {who("B", 12)}/>'
                f'<w:moveTo w:id="{ids.r()}" {who("B", 12)}>{R("This paragraph was moved down by Morgan.")}</w:moveTo>'
                f'<w:moveToRangeEnd w:id="{mv2}"/>')
            + PAGE)
    parts, rels, ovr = review_parts(c.comments, c.ext, c.cids)
    write_docx("markup/Word markup.docx", body, parts, rels, ovr, "Word markup")


def google_suggestions():
    """Google's export: names as the suggester's display name, a date on each, no moves, no paragraph-mark revisions;
    comments in comments.xml with commentsExtended.xml for the replies and the resolved state."""
    global STYLES
    STYLES = GOOGLE_STYLES
    ids.__init__()
    c = Comments()
    c0 = c.add(0, "A", 1, "Should this say forty-two?")
    c.add(1, "B", 2, "Yes, fixing.", parent=c0)
    c2 = c.add(2, "C", 3, "Tidy up this sentence.", done=True)
    c.add(3, "B", 3, "Done.", parent=c2, done=True)
    body = (P(R("Garden notes"), style="Title") + P(R("Suggestions from Google Docs"), style="Subtitle")
            + P(R("Beds and crops"), style="Heading1")
            + P(R("The volunteers planted "), cstart(0), R("forty"), cend(0), R(" rows of beans in "), INS("A", 5, R("late ")), R("April."))
            + P(cstart(2), R("Peas "), DEL("B", 6, "can"), INS("B", 6, R("should")), R(" go in earlier"), cend(2), R(", along the fence."))
            + P(R("This phrase was "), R("made bold", "<w:b/>" + rpr_change("C", 7)), R(" by a suggestion."))
            + P(INS("C", 8, R("A whole sentence suggested by Riley.")), R(" "), DEL("A", 8, "A whole sentence Dana wants removed.")) + PAGE)
    parts, rels, ovr = review_parts(c.comments, c.ext, c.cids)
    write_docx("markup/Google suggestions.docx", body, parts, rels, ovr, "Google suggestions")


word_markup()
google_suggestions()
