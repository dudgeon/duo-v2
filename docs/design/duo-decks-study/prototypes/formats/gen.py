"""Write the same 10-slide deck in several formats and count characters (tokens ~= chars/4)."""
import os, json
D = os.path.dirname(os.path.abspath(__file__))

slides = [
    ("title", "Q3 Platform Review", ["Platform team, October 2026"], "Welcome; set the agenda."),
    ("section", "Highlights", [], ""),
    ("bullets", "What we shipped", ["Voice input in every terminal", "Home list with New session row", "Faster chat pane on large transcripts"], "Lead with voice; it got the most use."),
    ("bullets", "Latency", ["p50 send-to-first-token down 40%", "p95 down 22%", "Idle CPU under 1%"], "Numbers are from the October sweep."),
    ("two", "Before and after", ["Manual session juggling", "Lost context on restart"], ["Projects group sessions", "Sessions resume by id"], ""),
    ("bullets", "Adoption", ["212 weekly users", "38% use voice weekly", "Median 6 sessions per project"], ""),
    ("section", "Next quarter", [], ""),
    ("bullets", "Priorities", ["Duo Decks: Markdown slides with templates", "Google Docs round trip", "Work Mac compatibility"], "Decks is the big bet."),
    ("bullets", "Risks", ["pptx fidelity in Google Slides", "Pinned Claude Code on work Macs"], ""),
    ("bullets", "Asks", ["Two design reviews per month", "Test decks from three teams"], "Close by asking for volunteers."),
]

def bl(xs, ind=""):
    return "\n".join(f"{ind}- {x}" for x in xs)

out = {}
# Pandoc
p = ["---\ntitle: Q3 Platform Review\nsubtitle: Platform team, October 2026\nnotes: Welcome; set the agenda.\n---\n"]
for k, t, a, *rest in slides[1:]:
    if k == "section": p.append(f"# {t}\n")
    elif k == "two": p.append(f"## {t}\n\n:::::: columns\n::: column\n{bl(a)}\n:::\n::: column\n{bl(rest[0])}\n:::\n::::::\n")
    else:
        s = f"## {t}\n\n{bl(a)}\n"
        if rest[0]: s += f"\n::: notes\n{rest[0]}\n:::\n"
        p.append(s)
out["pandoc.md"] = "\n".join(p)
# Marp
m = ["---\nmarp: true\ntheme: corporate\npaginate: true\n---\n\n<!-- _class: title -->\n\n# Q3 Platform Review\n\nPlatform team, October 2026\n\n<!-- Welcome; set the agenda. -->\n"]
for k, t, a, *rest in slides[1:]:
    if k == "section": m.append(f"<!-- _class: section -->\n\n# {t}\n")
    elif k == "two": m.append(f"<!-- _class: two-col -->\n\n## {t}\n\n<div class=\"cols\">\n<div>\n\n{bl(a)}\n\n</div>\n<div>\n\n{bl(rest[0])}\n\n</div>\n</div>\n")
    else:
        s = f"## {t}\n\n{bl(a)}\n"
        if rest[0]: s += f"\n<!-- {rest[0]} -->\n"
        m.append(s)
out["marp.md"] = "---\n\n".join(m)
# Slidev
sv = ["---\ntheme: corporate\nlayout: cover\n---\n\n# Q3 Platform Review\n\nPlatform team, October 2026\n\n<!--\nWelcome; set the agenda.\n-->\n"]
for k, t, a, *rest in slides[1:]:
    if k == "section": sv.append(f"---\nlayout: section\n---\n\n# {t}\n")
    elif k == "two": sv.append(f"---\nlayout: two-cols\n---\n\n# {t}\n\n{bl(a)}\n\n::right::\n\n{bl(rest[0])}\n")
    else:
        s = f"---\n\n# {t}\n\n{bl(a)}\n"
        if rest[0]: s += f"\n<!--\n{rest[0]}\n-->\n"
        sv.append(s)
out["slidev.md"] = "\n".join(sv)
# Duo-style sketch: each slide names a template and fills named slots
du = ["---\ndeck: Q3 Platform Review\ntemplates: \"[[Acme corporate]]\"\n---\n"]
for k, t, a, *rest in slides:
    tpl = {"title": "Title", "section": "Section", "bullets": "Title and Bullets", "two": "Two Column"}[k]
    s = f"---\n\n<!-- slide: {tpl} -->\n\n# {t}\n"
    if k == "title": s += f"\nsubtitle:: {a[0]}\n"
    elif k == "two": s += f"\n## Left\n\n{bl(a)}\n\n## Right\n\n{bl(rest[0])}\n"
    elif a: s += f"\n{bl(a)}\n"
    note = rest[-1] if rest and isinstance(rest[-1], str) else ""
    if note: s += f"\n> [!note]\n> {note}\n"
    du.append(s)
out["duo-sketch.md"] = "\n".join(du)
# python-pptx
py = ["from pptx import Presentation\nprs = Presentation('corporate.pptx')\nL = {l.name: l for l in prs.slide_layouts}\n"]
for k, t, a, *rest in slides:
    lay = {"title": "Title Slide", "section": "Section Header", "bullets": "Title and Content", "two": "Two Content"}[k]
    s = f"s = prs.slides.add_slide(L['{lay}'])\ns.shapes.title.text = {json.dumps(t)}\n"
    if k == "title": s += f"s.placeholders[1].text = {json.dumps(a[0])}\n"
    elif k == "two": s += f"s.placeholders[1].text = {json.dumps(chr(10).join(a))}\ns.placeholders[2].text = {json.dumps(chr(10).join(rest[0]))}\n"
    elif a: s += f"s.placeholders[1].text = {json.dumps(chr(10).join(a))}\n"
    note = rest[-1] if rest and isinstance(rest[-1], str) else ""
    if note: s += f"s.notes_slide.notes_text_frame.text = {json.dumps(note)}\n"
    py.append(s)
py.append("prs.save('deck.pptx')\n")
out["python-pptx.py"] = "\n".join(py)
# pptxgenjs (masters defined elsewhere)
js = ["const pptx = new (require('pptxgenjs'))();\nrequire('./masters')(pptx);\n"]
for k, t, a, *rest in slides:
    mas = {"title": "TITLE", "section": "SECTION", "bullets": "TITLE_BODY", "two": "TWO_COL"}[k]
    s = f"s = pptx.addSlide({{ masterName: '{mas}' }});\ns.addText({json.dumps(t)}, {{ placeholder: 'title' }});\n"
    if k == "two":
        s += f"s.addText({json.dumps([{'text': x, 'options': {'bullet': True}} for x in a])}, {{ placeholder: 'left' }});\n"
        s += f"s.addText({json.dumps([{'text': x, 'options': {'bullet': True}} for x in rest[0]])}, {{ placeholder: 'right' }});\n"
    elif k == "title": s += f"s.addText({json.dumps(a[0])}, {{ placeholder: 'subtitle' }});\n"
    elif a: s += f"s.addText({json.dumps([{'text': x, 'options': {'bullet': True}} for x in a])}, {{ placeholder: 'body' }});\n"
    note = rest[-1] if rest and isinstance(rest[-1], str) else ""
    if note: s += f"s.addNotes({json.dumps(note)});\n"
    js.append(s)
js.append("pptx.writeFile({ fileName: 'deck.pptx' });\n")
out["pptxgenjs.js"] = "\n".join(js)

for name, txt in out.items():
    open(os.path.join(D, name), "w").write(txt)
    print(f"{name:16} {len(txt):6} chars  ~{len(txt)//4:5} tokens  {txt.count(chr(10)):4} lines")
