"""The agent's side of the docx viewer spike: what `duo2 doc outline|comments|changes` would print,
read straight from the .docx with the standard library (no renderer).

    python3 docx_outline.py <file.docx> [outline|comments|changes|json]

Every paragraph is named by its w14:paraId, the same id @file-viewer/docx stamps on the rendered
<p> (data-office-target="word/document.xml#p:<paraId>"), so a paragraph the user picks and the one
Claude reads or edits are the same. Paragraphs without a paraId (files not saved by Word 2010+)
fall back to their part and index ("document.xml#12"), which is stable only until an edit.
"""
import json, re, sys, zipfile
import xml.etree.ElementTree as ET

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
W14 = "{http://schemas.microsoft.com/office/word/2010/wordml}"
W15 = "{http://schemas.microsoft.com/office/word/2012/wordml}"
CHANGE = {"ins": "insert", "del": "delete", "moveFrom": "move-from", "moveTo": "move-to"}


def read(z, name):
    try:
        return ET.fromstring(z.read(name))
    except KeyError:
        return None


def para_text(p, view):
    """The paragraph's text: view 'final' (changes accepted), 'original', or 'markup' ({+ins+} [-del-])."""
    out = []

    def walk(el, state):
        for c in el:
            tag = c.tag.replace(W, "")
            if tag in CHANGE:
                walk(c, CHANGE[tag])
            elif tag in ("t", "delText"):
                txt = c.text or ""
                ins, dele = state in ("insert", "move-to"), state in ("delete", "move-from")
                if view == "final" and dele or view == "original" and ins:
                    continue
                out.append(f"{{+{txt}+}}" if view == "markup" and ins else f"[-{txt}-]" if view == "markup" and dele else txt)
            elif tag == "tab":
                out.append("\t")
            elif tag in ("br", "cr"):
                out.append("\n")
            elif tag in ("footnoteReference", "endnoteReference"):
                out.append(f"[^{tag[0]}{c.get(W + 'id')}]")
            elif tag in ("pPr", "rPr", "instrText", "txbxContent"):
                continue
            else:
                walk(c, state)
    walk(p, None)
    return "".join(out)


def paragraphs(root, part):
    """Body paragraphs in order (table cells included, text boxes skipped), with their context."""
    result, idx = [], 0

    def visit(el, ctx):
        nonlocal idx
        for c in el:
            tag = c.tag.replace(W, "")
            if tag == "p":
                idx += 1
                ppr = c.find(W + "pPr")
                style = ppr.find(W + "pStyle").get(W + "val") if ppr is not None and ppr.find(W + "pStyle") is not None else "Normal"
                num = ppr.find(W + "numPr") if ppr is not None else None
                lvl = int(num.find(W + "ilvl").get(W + "val")) if num is not None and num.find(W + "ilvl") is not None else None
                mark = ppr.find(W + "rPr") if ppr is not None else None
                mark_change = next((CHANGE[m.tag.replace(W, "")] for m in (mark if mark is not None else []) if m.tag.replace(W, "") in CHANGE), None)
                pid = c.get(W14 + "paraId")
                result.append({"id": pid or f"{part}#{idx}", "part": part, "style": style, "list": lvl, "where": ctx,
                               "text": para_text(c, "final"), "markup": para_text(c, "markup"), "el": c, "mark": mark_change})
            elif tag == "tbl":
                for r, tr in enumerate(c.findall(W + "tr"), 1):
                    for k, tc in enumerate(tr.findall(W + "tc"), 1):
                        visit(tc, f"table cell r{r}c{k}")
            elif tag in ("sdt", "sdtContent", "body", "customXml"):
                visit(c, ctx)
    visit(root.find(W + "body") if root.find(W + "body") is not None else root, "body")
    return result


def load(path):
    z = zipfile.ZipFile(path)
    doc = read(z, "word/document.xml")
    paras = paragraphs(doc, "document.xml")
    for name in sorted(n for n in z.namelist() if re.match(r"word/(header|footer)\d*\.xml$", n)):
        paras += [dict(p, where=name[5:-4]) for p in paragraphs(read(z, name), name[5:])]
    for kind in ("footnotes", "endnotes"):
        r = read(z, f"word/{kind}.xml")
        for n in (r if r is not None else []):
            if n.get(W + "type") in (None, "normal"):
                paras += [dict(p, where=f"{kind[:-1]} {n.get(W + 'id')}") for p in paragraphs(n, f"{kind}.xml")]

    # Comments: text, author, date; threads and resolved state from commentsExtended (by paraId).
    comments = {}
    cr = read(z, "word/comments.xml")
    for c in (cr if cr is not None else []):
        ps = c.findall(W + "p")
        comments[c.get(W + "id")] = {"id": c.get(W + "id"), "author": c.get(W + "author"), "date": c.get(W + "date"),
                                     "paraId": ps[-1].get(W14 + "paraId") if ps else None,
                                     "text": "\n".join(para_text(p, "final") for p in ps).strip(), "anchor": [], "quote": ""}
    ext = {}
    er = read(z, "word/commentsExtended.xml")
    for e in (er if er is not None else []):
        ext[e.get(W15 + "paraId")] = e
    by_para = {c["paraId"]: c for c in comments.values()}
    for c in comments.values():
        e = ext.get(c["paraId"])
        parent = e.get(W15 + "paraIdParent") if e is not None else None
        c["replyTo"] = by_para[parent]["id"] if parent in by_para else None
        c["resolved"] = e is not None and e.get(W15 + "done") == "1"
    # Anchors: which paragraphs each comment's range covers, and the quoted text.
    open_ = {}
    for p in paras:
        for el in p["el"].iter():
            tag = el.tag.replace(W, "")
            if tag == "commentRangeStart":
                open_[el.get(W + "id")] = True
            if tag in ("t",) and open_:
                for cid in open_:
                    if cid in comments:
                        comments[cid]["quote"] += el.text or ""
            if tag == "commentRangeEnd":
                open_.pop(el.get(W + "id"), None)
            if tag in ("commentRangeStart", "commentRangeEnd", "commentReference") and el.get(W + "id") in comments:
                a = comments[el.get(W + "id")]["anchor"]
                if p["id"] not in a:
                    a.append(p["id"])
        for cid in open_:
            if cid in comments and p["id"] not in comments[cid]["anchor"]:
                comments[cid]["anchor"].append(p["id"])

    # Tracked changes: kind, author, date, the paragraph, the text it touches.
    changes = []
    for p in paras:
        for el in p["el"].iter():
            tag = el.tag.replace(W, "")
            kind = CHANGE.get(tag) or {"rPrChange": "format", "pPrChange": "paragraph-format"}.get(tag)
            if not kind or el.get(W + "author") is None:
                continue
            if tag in CHANGE and el.find(".//" + W + "t") is None and el.find(".//" + W + "delText") is None:
                kind = f"paragraph-mark-{kind}"  # the paragraph mark itself (whole paragraph or row)
            text = "".join(t.text or "" for t in el.iter() if t.tag in (W + "t", W + "delText"))
            changes.append({"id": el.get(W + "id"), "kind": kind, "author": el.get(W + "author"), "date": el.get(W + "date"),
                            "paragraph": p["id"], "where": p["where"], "text": text})
    # A tracked row insertion: w:trPr/w:ins.
    for tr in doc.iter(W + "tr"):
        trpr = tr.find(W + "trPr")
        for k in ("ins", "del"):
            m = trpr.find(W + k) if trpr is not None else None
            if m is not None:
                first = next(iter(tr.iter(W + "p")), None)
                changes.append({"id": m.get(W + "id"), "kind": f"table-row-{CHANGE[k]}", "author": m.get(W + "author"),
                                "date": m.get(W + "date"), "paragraph": first.get(W14 + "paraId") if first is not None else None,
                                "where": "table", "text": " | ".join(para_text(p, "markup") for p in tr.iter(W + "p"))})
    for p in paras:
        del p["el"]
    return paras, list(comments.values()), changes


def main():
    path, what = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "outline")
    paras, comments, changes = load(path)
    if what == "json":
        print(json.dumps({"paragraphs": paras, "comments": comments, "changes": changes}, indent=1, ensure_ascii=False))
    elif what == "outline":
        for p in paras:
            if not p["markup"].strip() and not p["mark"]:
                continue
            tag = p["style"] if p["style"] != "Normal" else ""
            if p["list"] is not None:
                tag = f"list L{p['list']}"
            where = "" if p["where"] == "body" else f" ({p['where']})"
            notes = [f"c{c['id']}" for c in comments if p["id"] in c["anchor"] and not c["replyTo"]]
            flag = f" [{p['mark']} ¶]" if p["mark"] else ""
            print(f"{p['id']}  {tag:<10.10}{where}{flag} {p['markup'][:110]}" + (f"   ← comments {', '.join(notes)}" if notes else ""))
    elif what == "comments":
        for c in comments:
            if c["replyTo"]:
                continue
            state = "resolved" if c["resolved"] else "open"
            print(f"c{c['id']} [{state}] on {', '.join(c['anchor'])} “{c['quote']}”\n   {c['author']}, {c['date']}: {c['text']}")
            for r in comments:
                if r["replyTo"] == c["id"]:
                    print(f"   ↳ {r['author']}, {r['date']}: {r['text']}")
    elif what == "changes":
        for ch in changes:
            print(f"{ch['kind']:<24} {ch['author']:<15} {(ch['date'] or '')[:10]}  ¶{ch['paragraph']}  {ch['text'][:70]!r}")


main()
