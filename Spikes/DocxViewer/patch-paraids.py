"""Stamps each rendered paragraph with its Word identity (docx viewer spike).

docx-preview 0.4.x reads w14:paraId only for comments (commentsExtended), not for body paragraphs.
Two small edits: parseParagraph keeps the attribute on the model, renderParagraph writes it to the
<p> as data-para-id. (@file-viewer/docx needs no patch: its exposeDisplayTargets option writes
data-office-target="word/document.xml#p:<paraId>" itself.)
"""
import sys

for path in sys.argv[1:]:
    src = open(path, encoding="utf-8").read()
    a = "    parseParagraph(node) {\n        var result = { type: DomType.Paragraph, children: [] };\n"
    b = "    renderParagraph(elem) {\n        var result = this.toHTML(elem, ns.html, \"p\");\n"
    if a not in src or b not in src:
        sys.exit(f"{path}: parseParagraph/renderParagraph not found: the bundle changed; update the patterns")
    src = src.replace(a, a + "        result.paraId = globalXmlParser.attr(node, \"paraId\");\n", 1)
    src = src.replace(b, b + "        if (elem.paraId) result.dataset.paraId = elem.paraId;\n", 1)
    open(path, "w", encoding="utf-8").write(src)
    print(f"patched {path}")
