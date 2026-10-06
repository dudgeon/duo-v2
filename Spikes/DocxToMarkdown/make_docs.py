"""Synthetic Word documents for the .docx → Markdown spike (ENH-14). Run with python-docx:

    python3 make_docs.py <out-dir>

Each document exercises one kind of mess. Everything here is made up: this is a public repo.
python-docx can't write tracked changes, comments' anchors, footnotes or fields, so those parts
are patched into the XML directly (see `raw_*`)."""
import io, os, struct, sys, zipfile, zlib
from docx import Document
from docx.enum.text import WD_BREAK
from docx.oxml import parse_xml
from docx.oxml.ns import nsdecls, qn
from docx.shared import Pt, Inches, RGBColor

OUT = sys.argv[1] if len(sys.argv) > 1 else "docs"
os.makedirs(OUT, exist_ok=True)


def png(w, h, rgb):
    """A flat-coloured PNG, so the test needs no image files."""
    raw = b"".join(b"\x00" + bytes(rgb) * w for _ in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def body_font(doc, size=11, name="Calibri"):
    st = doc.styles["Normal"]
    st.font.size = Pt(size)
    st.font.name = name


# 1. clean: real heading styles, real lists, a real table, a link, bold/italic.
def clean():
    d = Document()
    d.add_heading("Quarterly Garden Report", 0)
    d.add_paragraph("This report covers the imaginary community garden on Example Street.")
    d.add_heading("Summary", 1)
    p = d.add_paragraph("Yields were ")
    p.add_run("up").bold = True
    p.add_run(" this season, and the ")
    p.add_run("tomatoes").italic = True
    p.add_run(" did best.")
    d.add_heading("What we planted", 2)
    for t in ["Tomatoes", "Beans", "Squash"]:
        d.add_paragraph(t, style="List Bullet")
    d.add_paragraph("Runner beans", style="List Bullet 2")
    d.add_heading("Steps for next year", 2)
    for t in ["Test the soil", "Order seeds", "Recruit volunteers"]:
        d.add_paragraph(t, style="List Number")
    d.add_heading("Harvest", 3)
    t = d.add_table(rows=3, cols=3)
    t.style = "Table Grid"
    for r, row in enumerate([["Crop", "Kilos", "Beds"], ["Tomatoes", "42", "4"], ["Beans", "17", "2"]]):
        for c, v in enumerate(row):
            t.cell(r, c).text = v
    add_link(d.add_paragraph("More at "), "https://example.com/garden", "the garden site")
    d.add_paragraph("A quote from a volunteer.", style="Quote")
    d.save(f"{OUT}/01-clean.docx")


def add_link(p, url, text):
    rid = p.part.relate_to(url, "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink", is_external=True)
    h = parse_xml(f'<w:hyperlink {nsdecls("w", "r")} r:id="{rid}"><w:r><w:rPr><w:rStyle w:val="Hyperlink"/></w:rPr><w:t>{text}</w:t></w:r></w:hyperlink>')
    p._p.append(h)


# 2. fake headings: Normal paragraphs made big and bold by hand, in three sizes.
def fake_headings():
    d = Document()
    body_font(d, 11)
    def big(text, size, bold=True, color=None):
        p = d.add_paragraph()
        r = p.add_run(text)
        r.font.size = Pt(size)
        r.bold = bold
        if color: r.font.color.rgb = RGBColor(*color)
    big("Volunteer Handbook", 24)
    d.add_paragraph("Welcome to the imaginary volunteer programme. This handbook explains how shifts work.")
    big("Getting started", 16, color=(0x1F, 0x4E, 0x79))
    d.add_paragraph("Sign up on the shared calendar and pick a shift that suits you.")
    big("Your first shift", 13)
    d.add_paragraph("Arrive ten minutes early. A lead will show you around.")
    big("What to bring", 13)
    d.add_paragraph("Gloves, water and a hat.")
    big("Safety", 16, color=(0x1F, 0x4E, 0x79))
    d.add_paragraph("Report any injury to the lead at once.")
    # A bold whole paragraph at body size: a run-in heading, or just emphasis? (ambiguous on purpose)
    p = d.add_paragraph(); p.add_run("Tools").bold = True
    d.add_paragraph("Return every tool to the shed.")
    # A bold sentence at body size that is not a heading: it ends with a full stop and is long.
    p = d.add_paragraph(); p.add_run("Never use the mower without a lead present, even if you have used one before.").bold = True
    # Body text that is merely a bit larger: a pull quote, not a heading.
    p = d.add_paragraph(); r = p.add_run("“Every hour helps.”"); r.font.size = Pt(14); r.italic = True
    d.save(f"{OUT}/02-fake-headings.docx")


# 3. fake lists: bullets and numbers typed as text, tabs after them, manual numbering 1.1.
def fake_lists():
    d = Document()
    body_font(d)
    d.add_paragraph("Things to pack:")
    for t in ["• Tent", "• Sleeping bag", "•\tTorch", "- Spare socks", "* Map"]:
        d.add_paragraph(t)
    d.add_paragraph("Route:")
    for t in ["1. Car park", "2. Ridge path", "3) Summit", "4.\tBack down"]:
        d.add_paragraph(t)
    d.add_paragraph("Sections:")
    for t in ["1.1 Planning", "1.2 Kit", "2.1 On the day"]:
        d.add_paragraph(t)
    d.add_paragraph("a) first option")
    d.add_paragraph("b) second option")
    # A paragraph that starts with a number but is not a list.
    d.add_paragraph("2026 was the first year we ran the walk.")
    d.save(f"{OUT}/03-fake-lists.docx")


# 4. layout table: a two-column table used to place a sidebar beside text, no header row.
def layout_table():
    d = Document()
    d.add_heading("Event Flyer", 1)
    t = d.add_table(rows=1, cols=2)
    left, right = t.cell(0, 0), t.cell(0, 1)
    left.text = "Join us for an imaginary picnic in the park."
    left.add_paragraph("Bring food to share. Games start at noon.")
    right.text = "When: Saturday"
    right.add_paragraph("Where: Example Park")
    right.add_paragraph("Cost: free")
    d.add_heading("Real data table", 2)
    t2 = d.add_table(rows=3, cols=2); t2.style = "Table Grid"
    for r, row in enumerate([["Game", "Time"], ["Sack race", "12:00"], ["Tug of war", "13:00"]]):
        for c, v in enumerate(row): t2.cell(r, c).text = v
    # A merged cell: Markdown tables can't merge.
    t3 = d.add_table(rows=2, cols=3); t3.style = "Table Grid"
    a = t3.cell(0, 0).merge(t3.cell(0, 1)); a.text = "Merged header"
    t3.cell(0, 2).text = "Other"
    for c, v in enumerate(["x", "y", "z"]): t3.cell(1, c).text = v
    d.save(f"{OUT}/04-layout-table.docx")


# 5. tracked changes: an insertion, a deletion, and a formatting change.
def tracked():
    d = Document()
    d.add_heading("Meeting Minutes", 1)
    p = d.add_paragraph("The committee agreed to ")
    ins = parse_xml(f'<w:ins {nsdecls("w")} w:id="1" w:author="Reviewer A" w:date="2026-01-01T00:00:00Z"><w:r><w:t xml:space="preserve">paint the shed and </w:t></w:r></w:ins>')
    p._p.append(ins)
    p.add_run("repair the fence")
    dele = parse_xml(f'<w:del {nsdecls("w")} w:id="2" w:author="Reviewer B" w:date="2026-01-02T00:00:00Z"><w:r><w:delText xml:space="preserve"> before winter</w:delText></w:r></w:del>')
    p._p.append(dele)
    p.add_run(".")
    # A whole deleted paragraph.
    p2 = d.add_paragraph()
    p2._p.append(parse_xml(f'<w:del {nsdecls("w")} w:id="3" w:author="Reviewer B" w:date="2026-01-02T00:00:00Z"><w:r><w:delText>This sentence was removed.</w:delText></w:r></w:del>'))
    d.add_paragraph("Next meeting: the first Monday.")
    d.save(f"{OUT}/05-tracked-changes.docx")


# 6. comments: python-docx ≥1.2 writes comments with anchors.
def comments():
    d = Document()
    d.add_heading("Budget Draft", 1)
    p = d.add_paragraph()
    r1 = p.add_run("We will spend fifty units on seeds.")
    d.add_comment(r1, text="Is fifty enough?", author="Reviewer A", initials="RA")
    p2 = d.add_paragraph()
    r2 = p2.add_run("And twenty on tools.")
    d.add_comment(r2, text="Check the tool library first.", author="Reviewer B", initials="RB")
    d.save(f"{OUT}/06-comments.docx")


# 7. images: an inline picture with alt text, and one without.
def images():
    d = Document()
    d.add_heading("Plot Map", 1)
    d.add_paragraph("The figure shows the bed layout.")
    d.add_picture(io.BytesIO(png(120, 60, (60, 140, 80))), width=Inches(2))
    # alt text: wp:docPr/@descr
    d.inline_shapes[0]._inline.docPr.set("descr", "Green rectangle standing for bed one")
    d.add_paragraph("And a second picture without alt text:")
    d.add_picture(io.BytesIO(png(40, 40, (200, 80, 60))), width=Inches(0.6))
    d.save(f"{OUT}/07-images.docx")


# 8. footnotes, a field, smart quotes, soft breaks used as spacing, a page break, symbols.
def footnotes_fields():
    d = Document()
    d.add_heading("Notes on Compost", 1)
    p = d.add_paragraph("Compost needs air")
    p._p.append(parse_xml(f'<w:r {nsdecls("w")}><w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr><w:footnoteReference w:id="1"/></w:r>'))
    p.add_run(" and water.")
    # A field: a PAGE field and a hyperlink field (HYPERLINK as a complex field).
    p = d.add_paragraph("See page ")
    for x in ['<w:r><w:fldChar w:fldCharType="begin"/></w:r>', '<w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>',
              '<w:r><w:fldChar w:fldCharType="separate"/></w:r>', '<w:r><w:t>1</w:t></w:r>', '<w:r><w:fldChar w:fldCharType="end"/></w:r>']:
        p._p.append(parse_xml(x.replace("<w:r>", f'<w:r {nsdecls("w")}>', 1)))
    p.add_run(" and the ")
    for x in ['<w:r><w:fldChar w:fldCharType="begin"/></w:r>', '<w:r><w:instrText xml:space="preserve"> HYPERLINK "https://example.com/compost" </w:instrText></w:r>',
              '<w:r><w:fldChar w:fldCharType="separate"/></w:r>', '<w:r><w:t>compost guide</w:t></w:r>', '<w:r><w:fldChar w:fldCharType="end"/></w:r>']:
        p._p.append(parse_xml(x.replace("<w:r>", f'<w:r {nsdecls("w")}>', 1)))
    p.add_run(".")
    d.add_paragraph("“Smart quotes” and ‘single ones’ — with an em dash… and an ellipsis.")
    # Soft line breaks used as paragraph spacing, and empty paragraphs as spacers.
    p = d.add_paragraph("First line")
    r = p.add_run(); r.add_break(); r.add_break()
    p.add_run("After two soft breaks")
    d.add_paragraph("")
    d.add_paragraph("")
    d.add_paragraph("After two empty paragraphs. Text with *asterisks* and _underscores_ and a # hash.")
    d.add_paragraph().add_run().add_break(WD_BREAK.PAGE)
    d.add_paragraph("After a page break.")
    d.save(f"{OUT}/08-footnotes-fields.docx")
    add_footnotes(f"{OUT}/08-footnotes-fields.docx", {1: "Turn it every week."})


def add_footnotes(path, notes):
    """python-docx has no footnote part; add word/footnotes.xml, its relationship and content type."""
    W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
    body = "".join(f'<w:footnote w:id="{i}"><w:p><w:r><w:footnoteRef/></w:r><w:r><w:t xml:space="preserve"> {t}</w:t></w:r></w:p></w:footnote>' for i, t in notes.items())
    xml = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:footnotes {W}>'
           '<w:footnote w:type="separator" w:id="-1"><w:p><w:r><w:separator/></w:r></w:p></w:footnote>'
           '<w:footnote w:type="continuationSeparator" w:id="0"><w:p><w:r><w:continuationSeparator/></w:r></w:p></w:footnote>'
           f'{body}</w:footnotes>')
    patch(path, {"word/footnotes.xml": xml},
          rels='<Relationship Id="rIdFn1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes" Target="footnotes.xml"/>',
          ctype='<Override PartName="/word/footnotes.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"/>')


def patch(path, add, rels=None, ctype=None):
    zin = zipfile.ZipFile(path)
    items = {n: zin.read(n) for n in zin.namelist()}
    zin.close()
    for n, x in add.items(): items[n] = x.encode()
    if rels: items["word/_rels/document.xml.rels"] = items["word/_rels/document.xml.rels"].replace(b"</Relationships>", rels.encode() + b"</Relationships>")
    if ctype: items["[Content_Types].xml"] = items["[Content_Types].xml"].replace(b"</Types>", ctype.encode() + b"</Types>")
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for n, b in items.items(): z.writestr(n, b)


# 9. mixed mess: a styled Title, outline-level paragraphs without heading styles, a custom
# heading-like style, numbered headings (manual "1." before a fake heading), and nested real lists.
def mixed():
    d = Document()
    body_font(d, 10.5, "Georgia")
    d.add_paragraph("Allotment Rules", style="Title")
    # Outline level set on a Normal paragraph (w:outlineLvl): a heading to Word's navigator.
    p = d.add_paragraph("Membership")
    p._p.get_or_add_pPr().append(parse_xml(f'<w:outlineLvl {nsdecls("w")} w:val="0"/>'))
    d.add_paragraph("Anyone in the imaginary town can join.")
    # A custom style based on Heading 2 with a different name.
    st = d.styles.add_style("Section Head", 1)
    st.base_style = d.styles["Heading 2"]
    d.add_paragraph("Fees", style="Section Head")
    d.add_paragraph("Fees are due each spring.")
    # Manually numbered fake heading.
    p = d.add_paragraph(); r = p.add_run("3. Plot care"); r.bold = True; r.font.size = Pt(14)
    d.add_paragraph("Keep paths clear.")
    for t, s in [("Weeding", "List Bullet"), ("Paths", "List Bullet 2"), ("Edges", "List Bullet 3"), ("Water", "List Bullet")]:
        d.add_paragraph(t, style=s)
    # All caps body-size bold line: a common fake heading.
    p = d.add_paragraph(); r = p.add_run("DISPUTES"); r.bold = True
    d.add_paragraph("Talk to the secretary.")
    # Underlined text (no Markdown equivalent) and strike.
    p = d.add_paragraph("Underlined ")
    p.add_run("important").underline = True
    p.add_run(" and ")
    p.add_run("struck").font.strike = True
    p.add_run(" words, H")
    r = p.add_run("2"); r.font.subscript = True
    p.add_run("O.")
    d.save(f"{OUT}/09-mixed.docx")


# 10. a scan: pictures and no text (Duo refuses unless told to convert anyway).
def scan():
    d = Document()
    for rgb in [(200, 200, 200), (180, 180, 180)]:
        d.add_picture(io.BytesIO(png(60, 80, rgb)), width=Inches(3))
    d.save(f"{OUT}/10-scan.docx")


for f in [scan, clean, fake_headings, fake_lists, layout_table, tracked, comments, images, footnotes_fields, mixed]:
    f()
print("\n".join(sorted(os.listdir(OUT))))
