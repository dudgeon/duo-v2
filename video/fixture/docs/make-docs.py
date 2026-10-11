#!/usr/bin/env python3
"""Builds the shelf-scan project's sample documents from ../world.json (sample data only, all invented):
docs/team-review-oct15.pptx, docs/beta-interview-synthesis.docx, research/interviews/p1..p8.md, PROJECT.md and content.json.
Run:  uv run --with python-pptx --with python-docx video/fixture/docs/make-docs.py"""
import json, pathlib
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.chart.data import CategoryChartData
from pptx.enum.chart import XL_CHART_TYPE, XL_LABEL_POSITION
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE
from docx import Document
from docx.shared import Pt as DPt, RGBColor as DRGB, Inches as DIn
from docx.oxml.ns import qn
from docx.oxml import OxmlElement


import datetime, io, zipfile
FIXED = datetime.datetime(2026, 10, 12, 18, 0, 0)
def stable_bytes(raw):
    """An Office zip (or a workbook embedded in one) with fixed timestamps, so unchanged content keeps the same bytes."""
    import re
    src = zipfile.ZipFile(io.BytesIO(raw)); out = io.BytesIO()
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for info in src.infolist():
            data = src.read(info.filename)
            if info.filename == "docProps/core.xml":
                data = re.sub(rb"(<dcterms:(created|modified)[^>]*>)[^<]*", lambda m: m.group(1) + b"2026-10-12T18:00:00Z", data)
            elif info.filename.endswith((".xlsx", ".docx", ".pptx")):
                data = stable_bytes(data)   # the chart's embedded workbook carries its own timestamps
            zi = zipfile.ZipInfo(info.filename, date_time=FIXED.timetuple()[:6]); zi.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(zi, data)
    return out.getvalue()
def stable(path):
    path = pathlib.Path(path); path.write_bytes(stable_bytes(path.read_bytes()))

here = pathlib.Path(__file__).parent
W = json.load(open(here.parent / "world.json"))
N = W["numbers"]; T = {t["id"]: t for t in W["testers"]}
pct = lambda x: round(x * 100)
causes = N["eval"]["causes"]
SHORT = {"tilted": "Tilted", "glare": "Glare", "thin": "Thin spines", "stacked": "Stacked", "other": "Other"}
prd_lines = (here / "docs" / "prd-v2.md").read_text().splitlines()

# ---------------------------------------------------------------- content
FOOT = "Little Shared Library · shelf-scan · team review Oct 15"
slides = [
    {"title": "Shelf scan v2", "subtitle": "Team review · Thu Oct 15 · Sam", "kind": "title"},
    {"title": "Where scans go wrong", "kind": "chart",
     "chart": {"label": f"Share of {N['eval']['wrong']} wrong reads (%)", "bars": [[SHORT[c["cause"]], pct(c["share"])] for c in causes]},
     "note": f"{pct(N['eval']['accuracy'])}% of spines read right; every miss lands in the catalog"},
    {"title": "What the eval found", "kind": "paragraph",
     # S7 (Geoff, 2026-10-11): one plain paragraph of findings that Claude turns into three bullets.
     "text": (f"Ravi's Sep 28 eval read {pct(N['eval']['accuracy'])}% of spines right across {N['eval']['photos']:,} photos from {N['eval']['shelves']} shelves. "
              f"Tilted spines caused {pct(causes[0]['share'])}% of the wrong reads and glare {pct(causes[1]['share'])}%, most of it at glass-door boxes. "
              f"With a review step in the prototype, testers got {pct(N['reviewTest']['accuracy'])}% of books right in a median {N['reviewTest']['medianReviewSeconds']} seconds a shelf."),
     "stat": f"{N['eval']['wrong']}", "statNote": f"wrong reads in {N['eval']['photos']:,} photos"},
    {"title": "What we heard from testers", "kind": "quotes",
     "quotes": ["“My own box has a book on it that isn’t there.” Denise, P3",
                "“Two wrong books and I stopped.” Owen, P8"],
     "stat": f"{N['stoppedAfterWrong']} of {N['sawWrongBook']}", "statNote": "testers who saw a wrong book stopped scanning"},
    {"title": "Proposal: review before add", "kind": "bullets",
     "bullets": ["Show every spine the scan found", "Flag the ones the model is unsure of", "Fix a miss in one tap", "Nothing is added until you tap “Add”", "Warn about glare before the photo"]},
    {"title": "Targets", "kind": "table", "rows": [[t["metric"], t["today"], t["target"]] for t in N["targets"]], "head": ["Metric", "Today", "Target"]},
    {"title": "Decision for Thursday", "kind": "bullets",
     "bullets": ["Auto-add: keep it for stewards at 95%+, or remove it until the model gets there?",
                 "Scan v2 into the November build", "Target: TestFlight Nov 2"]},
]
ps = W["prototypeShelf"]
content = {
    "$note": "The sample documents the intro video shows, in the shelf-scan project of the Little Shared Library demo world (../world.json, ../SCENARIO.md). S1 draws them in third-party windows; S2 opens the real files as Duo editor tabs. Both read this, so they always match. Written by make-docs.py. Sample data only.",
    "project": "shelf-scan",
    "folder": "~/work/little-shared-library/shelf-scan",
    "markdown": {"file": "docs/prd-v2.md", "source": "docs/prd-v2.md"},
    "prototype": {"file": "prototype/scan-review.html", "title": "Scan review — Little Shared Library",
                  "box": ps["box"], "found": ps["found"], "needLook": ps["needLook"], "spines": ps["spines"], "cta": ps["cta"]},
    "deck": {"file": "docs/team-review-oct15.pptx", "slides": slides},
    "doc": {
        "file": "docs/beta-interview-synthesis.docx",
        "title": "Shelf scan beta: interview synthesis",
        "byline": "Sam · 8 interviews · Sep 14–25, 2026",
        "pull": {"quote": "“The glass door throws the afternoon sun straight back at the camera. Then my own box has a book on it that isn’t there.”", "who": "Denise (P3), steward, Linden Street box"},
        "sections": [
            {"heading": "Summary", "body": "We talked to eight beta testers about shelf scan v1. Three of them (P3, P6, P8) stopped scanning after a wrong book was added to the catalog for them. Everyone liked the speed; nobody liked finding out later that a book on the shelf was not on the shelf."},
            {"heading": "What we heard", "quotes": [
                "“I scanned the Linden Street box and it put in Pervasive Games. We have never had that book.” (P3, Denise)",
                "“Two wrong books and I stopped. I don’t have time to audit it.” (P8, Owen)",
                "“If it showed me the list first I’d tap through it on the train.” (P1, Aisha)",
                "“The skinny paperbacks are always the ones it gets wrong.” (P6, Hal)"]},
            {"heading": "Themes", "bullets": [
                "A wrong book costs trust fast (P3, P6, P8)",
                "Glare from glass doors makes scanning unreliable (P3, P2)",
                "Testers want to check the list before it is saved (P1, P4, P7)",
                "Fixing a miss must take one tap (P4, P5, P7)"]},
            {"heading": "Recommendations", "body": "Add a review step: show every spine found, flag the unsure ones, fix a miss in one tap, and add nothing until the steward taps Add. Warn about glare before the photo. Keep auto-add off until accuracy reaches 95%."},
        ]},
    "terminals": [
        {"session": "Tighten PRD goals", "cwd": "~/work/little-shared-library/shelf-scan"},
        {"session": "Prototype scan review", "cwd": "~/work/little-shared-library/shelf-scan/prototype"},
        {"session": "Synthesis from interviews", "cwd": "~/work/little-shared-library/shelf-scan/research"},
    ],
}
ROOT = "/Users/sam/work/little-shared-library/shelf-scan"
goals = prd_lines[prd_lines.index("## Goals") + 1:prd_lines.index("## Goals") + 4]
gi = prd_lines.index("## Goals") + 1  # 1-based line number of the "## Goals" heading
content["desk"] = {
    "finder": {"parent": "little-shared-library", "hero": "shelf-scan", "folders": [
        ["beta-feedback", "Yesterday"], ["neighborhood-map", "Oct 9"], ["press-kit", "Aug 30"],
        ["seed-deck", "Jun 12"], ["shelf-scan", "Today"], ["steward-onboarding", "Oct 2"]]},
    "terms": {
        "term1": [
            {"k": "box", "cwd": ROOT},
            {"k": "user", "text": "Tighten the goals in docs/prd-v2.md: make each one measurable."},
            {"k": "tool", "name": "Update", "arg": "docs/prd-v2.md"},
            {"k": "out", "text": "Updated docs/prd-v2.md with 3 additions and 3 removals"},
            # The same edit terms/tighten-prd.ans shows in S2: the v1 goals out, the PRD's goals in.
            {"k": "diff", "n": gi + 1, "sign": "-", "text": "1. Fewer wrong books."},
            {"k": "diff", "n": gi + 1, "sign": "+", "text": goals[0]},
            {"k": "diff", "n": gi + 2, "sign": "-", "text": "2. Every scanned spine lands in the catalog with no extra taps."},
            {"k": "diff", "n": gi + 2, "sign": "+", "text": goals[1]},
            {"k": "diff", "n": gi + 3, "sign": "-", "text": "3. Fixing a missed book takes one tap."},
            {"k": "diff", "n": gi + 3, "sign": "+", "text": goals[2]},
            {"k": "say", "text": "Goal 1 now carries the baseline and the target."}],
        "term2": [
            {"k": "box", "cwd": ROOT + "/prototype"},
            {"k": "user", "text": "flag unsure spines with an amber outline and a \"Fix\" chip in prototype/scan-review.html"},
            {"k": "tool", "name": "Read", "arg": "scan-review.html"},
            {"k": "tool", "name": "Update", "arg": "scan-review.html"},
            {"k": "out", "text": "Updated scan-review.html with 5 additions"},
            {"k": "diff", "n": 83, "sign": "+", "text": "  .summary h3 .need { color: var(--amber); }"},
            {"k": "diff", "n": 86, "sign": "+", "text": "  .sec.warn { color: var(--amber); }"},
            {"k": "diff", "n": 109, "sign": "+", "text": "  .rc.lowish { color: var(--amber); }"},
            {"k": "diff", "n": 113, "sign": "+", "text": "  .flag .cover { width: 28px; height: 38px; }"},
            {"k": "diff", "n": 160, "sign": "+", "text": "          <div class=\"sec warn\">Needs a look <small>2</small></div>"},
            {"k": "say", "text": "Two spines are flagged. Tap Fix to pick the right title."}],
    },
    "zsh": {"user": W["user"]["shortUser"], "host": W["user"]["host"], "lastLogin": W["time"]["lastLogin"],
            "wrongCd": "cd ~/work/little-shared-libary/shelf-scan", "rightCd": "cd ~/work/little-shared-library/shelf-scan"},
    "clock": W["time"]["clock"], "url": "localhost:3000/scan-review",
    "prd": prd_lines[:11],
}
# S5: what Sam has typed in the composer before pasting Denise's feedback and screenshot; the cursor drag-selects `select`.
content["s5"] = {"draft": "Here's Denise's email and her screenshot from the Linden Street box. This is why auto-add has to wait.",
                 "select": "This is why auto-add has to wait."}
assert content["s5"]["select"] in content["s5"]["draft"] and content["s5"]["draft"].endswith(content["s5"]["select"])
(here / "content.json").write_text(json.dumps(content, indent=2, ensure_ascii=False) + "\n")

# ---------------------------------------------------------------- deck
INK, MUTED = RGBColor(0x24, 0x2B, 0x28), RGBColor(0x6E, 0x72, 0x6A)
ACC, PAPER, LINE = RGBColor(0x0F, 0x5C, 0x4D), RGBColor(0xF6, 0xF1, 0xE6), RGBColor(0xDD, 0xD5, 0xC2)
SOFT, CARD = RGBColor(0xB7, 0xCC, 0xC3), RGBColor(0xFF, 0xFD, 0xF8)
FONT = "Georgia"; SANS = "Helvetica Neue"

def text(slide, x, y, w, h, s, size, color=INK, bold=False, align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP, font=SANS):
    tb = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h)); tf = tb.text_frame; tf.word_wrap = True
    tf.vertical_anchor = anchor
    p = tf.paragraphs[0]; p.alignment = align; r = p.add_run(); r.text = s
    r.font.size, r.font.bold, r.font.name = Pt(size), bold, font; r.font.color.rgb = color
    return tb

def rect(s, x, y, w, h, fill, line=None, shape=MSO_SHAPE.RECTANGLE):
    r = s.shapes.add_shape(shape, Inches(x), Inches(y), Inches(w), Inches(h)); r.fill.solid(); r.fill.fore_color.rgb = fill
    if line: r.line.color.rgb = line
    else: r.line.fill.background()
    r.shadow.inherit = False
    if shape == MSO_SHAPE.ROUNDED_RECTANGLE: r.adjustments[0] = 0.05
    return r

def base(prs, title, n):
    s = prs.slides.add_slide(prs.slide_layouts[6])
    s.background.fill.solid(); s.background.fill.fore_color.rgb = PAPER
    rect(s, 0, 0, 13.333, 0.18, ACC)
    text(s, 0.8, 0.55, 11.7, 1.2, title, 40, INK, True, anchor=MSO_ANCHOR.MIDDLE, font=FONT)
    rect(s, 0.8, 6.95, 11.73, 0.02, LINE)
    text(s, 0.8, 7.0, 9, 0.3, FOOT, 11, MUTED)
    text(s, 11.9, 7.0, 0.63, 0.3, str(n), 11, MUTED, align=PP_ALIGN.RIGHT)
    return s

prs = Presentation(); prs.slide_width, prs.slide_height = Inches(13.333), Inches(7.5)
for n, sl in enumerate(slides, 1):
    k = sl["kind"]
    if k == "title":
        s = prs.slides.add_slide(prs.slide_layouts[6]); s.background.fill.solid(); s.background.fill.fore_color.rgb = ACC
        rect(s, 0.9, 2.35, 1.2, 0.08, RGBColor(0xE8, 0xB9, 0x4A))
        text(s, 0.9, 2.55, 11.5, 1.6, sl["title"], 60, RGBColor(255, 255, 255), True, anchor=MSO_ANCHOR.BOTTOM, font=FONT)
        text(s, 0.9, 4.4, 11.5, 0.6, sl["subtitle"], 24, RGBColor(0xCF, 0xE3, 0xDA))
        text(s, 0.9, 6.9, 9, 0.3, "Little Shared Library", 12, RGBColor(0xCF, 0xE3, 0xDA))
        continue
    s = base(prs, sl["title"], n)
    if k == "chart":
        ch = sl["chart"]; cd = CategoryChartData(); cd.categories = [b[0] for b in ch["bars"]]; cd.add_series(ch["label"], [b[1] for b in ch["bars"]])
        gf = s.shapes.add_chart(XL_CHART_TYPE.COLUMN_CLUSTERED, Inches(0.8), Inches(1.9), Inches(8.2), Inches(4.8), cd); chart = gf.chart
        chart.has_legend = False; chart.has_title = True; chart.chart_title.text_frame.text = ch["label"]
        r0 = chart.chart_title.text_frame.paragraphs[0].runs[0]; r0.font.size = Pt(15); r0.font.color.rgb = MUTED; r0.font.name = SANS; r0.font.bold = False
        pl = chart.plots[0]; pl.gap_width = 55; pl.has_data_labels = True
        pl.data_labels.font.size = Pt(18); pl.data_labels.font.bold = True; pl.data_labels.position = XL_LABEL_POSITION.OUTSIDE_END
        ser = pl.series[0]; peak = max(b[1] for b in ch["bars"])
        for i, b in enumerate(ch["bars"]):
            pt = ser.points[i]; pt.format.fill.solid(); pt.format.fill.fore_color.rgb = ACC if b[1] == peak else SOFT
        chart.value_axis.visible = False; chart.value_axis.has_major_gridlines = False
        chart.category_axis.tick_labels.font.size = Pt(15); chart.category_axis.format.line.color.rgb = LINE
        rect(s, 9.4, 2.3, 3.3, 3.0, CARD, LINE, MSO_SHAPE.ROUNDED_RECTANGLE)
        big, rest = sl["note"].split(" ", 1)
        text(s, 9.6, 2.45, 2.9, 1.1, big, 56, ACC, True, font=FONT)
        text(s, 9.6, 3.7, 2.9, 1.5, rest, 17, INK)
    elif k == "quotes":
        y = 1.95
        for q in sl["quotes"]:
            body, who = q.rsplit("” ", 1); body += "”"
            rect(s, 0.8, y, 0.08, 1.35, ACC)
            text(s, 1.1, y - 0.05, 7.3, 1.0, body, 26, INK, font=FONT)
            text(s, 1.1, y + 0.95, 7.3, 0.4, who, 16, MUTED)
            y += 1.95
        rect(s, 9.0, 2.2, 3.7, 3.5, CARD, LINE, MSO_SHAPE.ROUNDED_RECTANGLE)
        text(s, 9.15, 2.5, 3.4, 1.2, sl["stat"], 48, ACC, True, align=PP_ALIGN.CENTER, font=FONT)
        text(s, 9.3, 3.9, 3.1, 1.5, sl["statNote"], 18, INK, align=PP_ALIGN.CENTER)
    elif k == "paragraph":
        text(s, 0.9, 2.1, 7.7, 4.4, sl["text"], 24, INK, font=FONT)
        rect(s, 9.0, 2.2, 3.7, 3.5, CARD, LINE, MSO_SHAPE.ROUNDED_RECTANGLE)
        text(s, 9.15, 2.5, 3.4, 1.2, sl["stat"], 54, ACC, True, align=PP_ALIGN.CENTER, font=FONT)
        text(s, 9.3, 3.9, 3.1, 1.5, sl["statNote"], 18, INK, align=PP_ALIGN.CENTER)
    elif k == "table":
        rows = [sl["head"]] + sl["rows"]
        tbl = s.shapes.add_table(len(rows), 3, Inches(0.8), Inches(2.1), Inches(11.7), Inches(3.6)).table
        for ci, w in enumerate([6.5, 2.6, 2.6]): tbl.columns[ci].width = Inches(w)
        for ri, row in enumerate(rows):
            for ci, v in enumerate(row):
                cell = tbl.cell(ri, ci); cell.text = v; cell.fill.solid()
                cell.fill.fore_color.rgb = ACC if ri == 0 else (CARD if ri % 2 else PAPER)
                cell.vertical_anchor = MSO_ANCHOR.MIDDLE
                r = cell.text_frame.paragraphs[0].runs[0]; r.font.name = SANS
                r.font.size = Pt(20 if ri == 0 else 24); r.font.bold = ri == 0 or ci == 2
                r.font.color.rgb = RGBColor(255, 255, 255) if ri == 0 else (ACC if ci == 2 else INK)
    else:
        tb = s.shapes.add_textbox(Inches(0.9), Inches(2.1), Inches(11.4), Inches(4.5)); tf = tb.text_frame; tf.word_wrap = True
        for i, b in enumerate(sl["bullets"]):
            p = tf.paragraphs[0] if i == 0 else tf.add_paragraph(); p.space_after = Pt(18)
            r = p.add_run(); r.text = "•  " + b; r.font.size, r.font.name = Pt(30), FONT; r.font.color.rgb = INK
prs.save(here / content["deck"]["file"]); stable(here / content["deck"]["file"])

# S7: the paragraph slide as Duo's picker sends it, `duo2 slide shapes` for it, and the deck after Claude runs
# EDIT_PY (the same code its Bash row shows), written to ../s7/ for the video's after state.
PARA = next(n for n, sl in enumerate(slides, 1) if sl["kind"] == "paragraph")
def outline(slide, number):
    px = 914400 / 96
    lines = [f"Slide {number}:"]
    for sh in slide.shapes:
        kind = "chart" if getattr(sh, "has_chart", False) and sh.has_chart else ("table" if getattr(sh, "has_table", False) and sh.has_table else "shape")
        lines.append(f"  {sh.shape_id}  {sh.name} ({kind}) {round(sh.width / px)}×{round(sh.height / px)} at ({round(sh.left / px)}, {round(sh.top / px)})")
        if sh.has_text_frame and sh.text_frame.text:
            lines += ["      " + l for l in sh.text_frame.text.split("\n")]
    return "\n".join(lines)
sl3 = prs.slides[PARA - 1]
pick = next(sh for sh in sl3.shapes if sh.has_text_frame and sh.text_frame.text == slides[PARA - 1]["text"])
px = 914400 / 96
EDIT_PY = f"""from pptx import Presentation
from pptx.util import Pt
path = "docs/team-review-oct15.pptx"
prs = Presentation(path)
tf = next(s for s in prs.slides[{PARA - 1}].shapes if s.shape_id == {pick.shape_id}).text_frame
font = tf.paragraphs[0].runs[0].font
size, name, color = font.size, font.name, font.color.rgb
sentences = [s.strip() + "." for s in tf.text.split(". ") if s.strip()]
sentences[-1] = sentences[-1].rstrip(".") + "."
tf.clear()
for i, s in enumerate(sentences):
    p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
    p.space_after = Pt(18)
    r = p.add_run(); r.text = "•  " + s
    r.font.size, r.font.name = size, name
    r.font.color.rgb = color
prs.save(path)
print(f"slide {PARA}: {{len(sentences)}} bullets")
"""
s7 = here.parent / "s7"; s7.mkdir(exist_ok=True)
import os, shutil, subprocess, sys, tempfile
with tempfile.TemporaryDirectory() as t:
    os.makedirs(os.path.join(t, "docs")); shutil.copy(here / content["deck"]["file"], os.path.join(t, "docs", "team-review-oct15.pptx"))
    out = subprocess.run([sys.executable, "-c", EDIT_PY], cwd=t, capture_output=True, text=True, check=True).stdout
    after = pathlib.Path(t) / "docs" / "team-review-oct15.pptx"
    (s7 / "team-review-oct15.after.pptx").write_bytes(stable_bytes(after.read_bytes()))
    after_outline = outline(Presentation(after).slides[PARA - 1], PARA)
(s7 / "deck-shape.json").write_text(json.dumps({
    "slide": PARA, "count": len(slides), "id": pick.shape_id, "name": pick.name, "type": "shape",
    "text": pick.text_frame.text, "box": [round(pick.left / px), round(pick.top / px), round(pick.width / px), round(pick.height / px)],
    "slideSize": [1280, 720], "outline": outline(sl3, PARA), "afterOutline": after_outline, "editPy": EDIT_PY, "editOut": out}, indent=1, ensure_ascii=False) + "\n")

# ---------------------------------------------------------------- docx
d = content["doc"]; doc = Document()
sec = doc.sections[0]; sec.left_margin = sec.right_margin = DIn(1.1); sec.top_margin = sec.bottom_margin = DIn(1)
st = doc.styles
GREEN = (0x0F, 0x5C, 0x4D)
def style(name, size, color=None, bold=None, italic=None, font="Arial"):
    f = st[name].font; f.name = font; f.size = DPt(size)
    rpr = st[name].element.get_or_add_rPr(); rf = rpr.find(qn("w:rFonts"))
    for a in ("w:asciiTheme", "w:hAnsiTheme", "w:eastAsiaTheme", "w:cstheme"):
        if rf is not None and rf.get(qn(a)) is not None: del rf.attrib[qn(a)]
    if bold is not None: f.bold = bold
    if italic is not None: f.italic = italic
    if color:
        f.color.rgb = DRGB(*color)
        cc = rpr.find(qn("w:color"))
        for a in ("w:themeColor", "w:themeShade", "w:themeTint"):
            if cc.get(qn(a)) is not None: del cc.attrib[qn(a)]
style("Title Char", 22, GREEN, True); style("Heading 1 Char", 17, GREEN, True)   # the renderer reads linked character styles too
style("Normal", 11.5); style("Title", 22, GREEN, True); style("Heading 1", 17, GREEN, True)
style("List Bullet", 11.5); style("Quote", 11.5, (0x37, 0x41, 0x3D), None, True)
st["Heading 1"].paragraph_format.space_before = DPt(20)
doc.add_paragraph(d["title"], style="Title")
p = doc.add_paragraph(d["byline"]); p.runs[0].font.color.rgb = DRGB(0x6E, 0x72, 0x6A)
doc.add_heading("In their words", level=1)
pq = doc.add_paragraph(); r = pq.add_run(d["pull"]["quote"]); r.font.size = DPt(21); r.font.italic = True; r.font.name = "Georgia"; r.font.color.rgb = DRGB(*GREEN)
pq.paragraph_format.left_indent = DIn(0.25); pq.paragraph_format.space_after = DPt(2)
bd = OxmlElement("w:pBdr"); lf = OxmlElement("w:left")
for k_, v_ in (("val", "single"), ("sz", "24"), ("space", "10"), ("color", "0F5C4D")): lf.set(qn("w:" + k_), v_)
bd.append(lf); pq._p.get_or_add_pPr().append(bd)
pw = doc.add_paragraph(); pw.paragraph_format.left_indent = DIn(0.25); rr = pw.add_run("— " + d["pull"]["who"]); rr.font.size = DPt(11); rr.font.color.rgb = DRGB(0x6E, 0x72, 0x6A)
for s_ in d["sections"]:
    doc.add_heading(s_["heading"], level=1)
    if "body" in s_: doc.add_paragraph(s_["body"])
    for q in s_.get("quotes", []): doc.add_paragraph(q, style="Quote")
    for b in s_.get("bullets", []): doc.add_paragraph(b, style="List Bullet")
doc.save(here / d["file"]); stable(here / d["file"])

# ---------------------------------------------------------------- PROJECT.md
(here / "PROJECT.md").write_text("""---
goal: "Scan v2: fewer than 3% wrong books in the catalog"
health: on-track
next: "Team review Thu Oct 15"
---
# shelf-scan

Shelf scan lets a steward photograph a book box and add what is on the shelf to the catalog. v1 adds every spine it reads, and about one in five is wrong. v2 adds a review step so nothing is added until the steward has looked.

- PRD: [docs/prd-v2.md](docs/prd-v2.md)
- Deck for Thursday: [docs/team-review-oct15.pptx](docs/team-review-oct15.pptx)
- Interview synthesis: [docs/beta-interview-synthesis.docx](docs/beta-interview-synthesis.docx)
""")

# ---------------------------------------------------------------- interviews
I = {
 "P1": dict(date="Sep 14", ctx="Aisha passes the Northgate Station box twice a day on her commute and scans it standing on the platform, one hand on her bag. She has scanned about thirty shelves since August.",
   did=["Opened the app on the platform and pointed it at the top two shelves.", "Watched the list fill in and tapped Save before her train came.", "Showed us a shelf where three of fourteen books were wrong."],
   quotes=["I scan it on the way to the train. If it showed me the list first I’d tap through it right there.", "I don’t mind fixing one or two. I mind not knowing which ones to fix."],
   obs=["Scans in under a minute, mostly one-handed.", "Wants the unsure books flagged rather than checking every spine.", "Took part in the Oct 12 review prototype test."]),
 "P2": dict(date="Sep 15", ctx="Gerald taught for thirty-one years and stewards the Elm Park box. He keeps a paper list of what is in it and compares the app against it.",
   did=["Scanned the Elm Park box in the morning, in good light.", "Checked the result against his paper list, line by line.", "Counted two wrong books out of fourteen and corrected them by hand in the catalog."],
   quotes=["I check every one. Old habit. Two of them were just wrong.", "In the afternoon the door catches the sun and it’s hopeless."],
   obs=["Careful and slow; would happily review a list.", "Noticed glare on the door before we did.", "Does not trust auto-add for other stewards."]),
 "P3": dict(date="Sep 17", ctx="Denise stewards the Linden Street box, which has a glass door. She scans after work, when the afternoon sun hits it.",
   did=["Scanned her box at 4:30pm; the result had Pervasive Games on it.", "Told us a neighbour came looking for it.", "Tried three angles; the glare did not go away."],
   quotes=["The glass door throws the afternoon sun straight back at the camera. Then my own box has a book on it that isn’t there.", "I scanned Persuasion and it put in Pervasive Games. We have never had that book. A neighbour walked over for it.", "I can’t scan my box at all after four."],
   obs=["Stopped scanning after the wrong book.", "Glare is her main problem, not speed.", "Her long written feedback is in research/feedback/denise-p3.txt."]),
 "P4": dict(date="Sep 18", ctx="Marco has two kids under six and borrows picture books from the Riverside Playground box most weekends.",
   did=["Browsed the box shelf on the map.", "Tried scanning the picture-book shelf, which is mostly thin spines.", "Gave up on one title and typed it in."],
   quotes=["The skinny ones, the board books, it can’t read those.", "If fixing it is one tap I’ll do it. If it’s a form, no."],
   obs=["Thin spines are the common miss on his shelf.", "Wants fixing to be one tap.", "Took part in the Oct 12 review prototype test."]),
 "P5": dict(date="Sep 21", ctx="Priya reads about two books a week and checks the map every day for what is new in Elm Park.",
   did=["Walked us through how she uses the map.", "Scanned a shelf as a favour to the steward.", "Pointed out a book that appeared twice on the map."],
   quotes=["I trust the map because it’s usually right. When it’s wrong once, I wonder about all of it.", "Let me fix a book in one tap and I’ll fix them all."],
   obs=["A heavy consumer of the catalog; wrong books hit her hardest.", "Cares about trust more than speed.", "Wants a quick way to pick the right title from a few matches."]),
 "P6": dict(date="Sep 22", ctx="Hal took over the Cooper Lane box three weeks ago. He is new to stewarding and scans it every few days.",
   did=["Scanned the box twice in one afternoon.", "Found a wrong book from the first scan still in the catalog.", "Stopped after the second scan."],
   quotes=["The skinny paperbacks are always the ones it gets wrong.", "I added a wrong book and had no idea until a neighbour told me. I stopped scanning after that."],
   obs=["Stopped scanning after a wrong book was added for him.", "Wants to see what the scan found before saving.", "Took part in the Oct 12 review prototype test."]),
 "P7": dict(date="Sep 24", ctx="June is a student who uses the Northgate Library box between lectures. She scans occasionally.",
   did=["Scanned a shelf on her phone between classes.", "Skipped the check because it looked fine.", "Later found one wrong title when she searched."],
   quotes=["I’d look at the list if it was quick. It’s a check, not homework.", "Tell me which ones to look at and I’ll look at those."],
   obs=["Will review only if it is fast.", "Wants unsure books highlighted.", "Took part in the Oct 12 review prototype test."]),
 "P8": dict(date="Sep 25", ctx="Owen lives by the Riverside Allotments box and was an enthusiastic scanner in August. He has not scanned since early September.",
   did=["Showed us the last scan he made.", "Explained why he stopped.", "Agreed to try a review step if we build one."],
   quotes=["Two wrong books and I stopped. I don’t have time to audit it.", "I’d rather add nothing than add rubbish."],
   obs=["Stopped scanning after two wrong books.", "Would come back if he could check before adding.", "Typical of the 46 of 148 testers who stopped after a wrong book."]),
}
out = here / "research" / "interviews"; out.mkdir(parents=True, exist_ok=True)
for pid, i in I.items():
    t = T[pid]
    lines = [f"# {pid} {t['name']}", "", f"- Date: {i['date']}, 2026", f"- Box: {t['box']}", f"- Who: {t['who']}", "- Interviewer: Sam", "",
             "## Context", i["ctx"], "", "## What they did"] + [f"- {x}" for x in i["did"]] + ["", "## In their words"] + [f"> “{q}”" for q in i["quotes"]] + ["", "## Observations"] + [f"- {x}" for x in i["obs"]] + [""]
    (out / f"{pid.lower()}.md").write_text("\n".join(lines))
print("ok")
