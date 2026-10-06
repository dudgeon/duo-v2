"""The agent's side of a deck (ENH-12 spike): slide N's shapes and text straight from the OOXML,
with nothing but the standard library. What `duo2 slide shapes <file> [n]` would print.

    python3 -I pptx_outline.py <deck.pptx> [slide]

Ids are p:cNvPr ids, the same ones the patched renderer stamps on the DOM, so a picked element and
this outline name the same shape. Boxes are in slide pixels (96 per inch), as the renderer's.
"""
import json
import posixpath
import re
import sys
import zipfile
from xml.etree import ElementTree as ET

NS = {"p": "http://schemas.openxmlformats.org/presentationml/2006/main",
      "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
      "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
      "rel": "http://schemas.openxmlformats.org/package/2006/relationships",
      "c": "http://schemas.openxmlformats.org/drawingml/2006/chart"}
EMU_PX = 914400 / 96


def rels(z, part):
    path = posixpath.join(posixpath.dirname(part), "_rels", posixpath.basename(part) + ".rels")
    if path not in z.namelist(): return {}
    return {r.get("Id"): posixpath.normpath(posixpath.join(posixpath.dirname(part), r.get("Target")))
            for r in ET.fromstring(z.read(path)).findall("rel:Relationship", NS)}


def slide_parts(z):
    pres = ET.fromstring(z.read("ppt/presentation.xml"))
    rel = rels(z, "ppt/presentation.xml")
    return [rel[s.get(f"{{{NS['r']}}}id")] for s in pres.findall("p:sldIdLst/p:sldId", NS)]


def text_of(el):
    return "\n".join("".join(t.text or "" for t in p.iter(f"{{{NS['a']}}}t")) for p in el.iter(f"{{{NS['a']}}}p")).strip()


def box(el):
    # The shape's own transform only: `.//a:ext` would also match an extension list's a:ext.
    xfrm = next((c.find("a:xfrm", NS) for c in el if c.tag.endswith("}spPr") or c.tag.endswith("}grpSpPr")), None)
    xfrm = xfrm if xfrm is not None else el.find("p:xfrm", NS)
    if xfrm is None: return None
    off, ext = xfrm.find("a:off", NS), xfrm.find("a:ext", NS)
    if off is None or ext is None: return None
    return {k: round(int(v) / EMU_PX) for k, v in [("x", off.get("x")), ("y", off.get("y")), ("w", ext.get("cx")), ("h", ext.get("cy"))]}


def shapes(z, part, tree, groups=()):
    out = []
    kinds = {"sp": "shape", "pic": "picture", "graphicFrame": "frame", "grpSp": "group", "cxnSp": "connector"}
    for el in tree:
        kind = kinds.get(el.tag.split("}")[1])
        if not kind: continue
        nv = el.find(".//p:cNvPr", NS)
        item = {"id": int(nv.get("id")), "name": nv.get("name"), "type": kind, "inGroups": list(groups)}
        if kind == "frame":
            if el.find(".//a:tbl", NS) is not None:
                item["type"] = "table"
                item["text"] = "\n".join("\t".join(text_of(tc) for tc in tr.findall("a:tc", NS)) for tr in el.iter(f"{{{NS['a']}}}tr"))
            elif (ch := el.find(".//c:chart", NS)) is not None:
                item["type"] = "chart"
                target = rels(z, part).get(ch.get(f"{{{NS['r']}}}id"))
                if target:
                    cx = ET.fromstring(z.read(target))
                    item["chart"] = re.sub(r"Chart$", "", cx.find(".//c:plotArea", NS)[1].tag.split("}")[1])
                    item["series"] = [{"name": s.findtext("c:tx//c:v", "", NS),
                                       "values": [float(v.text) for v in s.iterfind("c:val//c:v", NS)]} for s in cx.iter(f"{{{NS['c']}}}ser")]
        elif kind != "group":
            if t := text_of(el): item["text"] = t
        if b := box(el): item["box"] = b
        out.append(item)
        if kind == "group":
            out += shapes(z, part, el, groups + (item["name"],))
    return out


def outline(path, only=None):
    with zipfile.ZipFile(path) as z:
        result = []
        for n, part in enumerate(slide_parts(z), start=1):
            if only and n != only: continue
            root = ET.fromstring(z.read(part))
            notes = next((t for t in rels(z, part).values() if "notesSlide" in t), None)
            result.append({"slide": n, "shapes": shapes(z, part, root.find("p:cSld/p:spTree", NS)),
                           "notes": text_of(ET.fromstring(z.read(notes)).find("p:cSld", NS)) if notes else ""})
        return result


if __name__ == "__main__":
    print(json.dumps(outline(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else None), indent=1, ensure_ascii=False))
