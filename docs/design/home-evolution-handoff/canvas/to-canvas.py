#!/usr/bin/env python3
"""Writes the boards as Design-canvas artboards (<root>/project/*.dc.html) and the canvas index.
    python3 to-canvas.py <root> [createdOnFiles.at]"""
import sys, os, re, json, datetime
here = os.path.dirname(os.path.abspath(__file__)); src = os.path.join(here, "boards")
root = sys.argv[1]; os.makedirs(f"{root}/project", exist_ok=True)
now = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
created = sys.argv[2] if len(sys.argv) > 2 else now
man = json.load(open(f"{src}/manifest.json"))
size = {b["name"]: (b["w"], b["h"], b["title"]) for b in man}
for n, (w, h, t) in size.items():
    s = open(f"{src}/{n}.html").read()
    style = re.search(r"<style>(.*?)</style>", s, re.S).group(1)
    body = re.search(r"<body>\n(.*)\n</body>", s, re.S).group(1)
    assert "{{" not in body + style
    title = re.search(r"<title>Duo · (.*?)</title>", s).group(1)
    open(f"{root}/project/{n}.dc.html", "w").write(f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{title}</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<style>{style}</style>
</helmet>
{body}
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":{w},"height":{h}}}}}'>
class Component extends DCLogic {{
renderVals() {{ return {{}}; }}
}}
</script>
</body>
</html>
''')
rows = [["00-study", "05-where-summary", "11-recommendation"],
        ["01-rows", "02-grouping", "03-filter", "04-click"],
        ["05-where-a-1440", "06-where-b-1440", "06-where-b-board-1440", "07-where-c-1440", "08-where-d-1440"],
        ["05-where-a-1280", "06-where-b-1280", "07-where-c-1280", "08-where-d-1280"],
        ["09-needs-you", "10-home-chat"]]
heads = ["The study and the recommendation", "1–4 · The list", "5–8 · Where it lives, 1440×900",
         "5–8 · Where it lives, 1280×800 (DL-129)", "9–10 · Needs you, and Home in chat"]
boards, order, notes, y = {}, [], {}, 0
for i, r in enumerate(rows):
    y += 260; x = 0; mh = 0
    for n in r:
        w, h, t = size[n]
        boards[f"{n}.dc.html"] = {"x": x, "y": y, "w": w, "h": h, "title": t}
        order.append(f"{n}.dc.html"); x += w + 80; mh = max(mh, h)
    notes[f"h{i}"] = {"x": 0, "y": y - 230, "text": heads[i], "kind": "title1", "maxW": x - 80}
    y += mh + 120
json.dump({"v": 3, "createdOnFiles": {"v": 1, "at": created}, "title": "Duo home evolution study",
           "launch": {"view": "canvas"}, "pages": [], "boards": boards, "order": order, "notes": notes,
           "designSystems": [{"title": "Duo", "namespace": "duo", "artifact": "https://claude.ai/artifact/QMapKeLYS3TVV36QKEc6MH",
                              "version": "1791384905-4ab4", "copiedAt": "2026-10-07T16:15:44Z"}]},
          open(f"{root}/project/canvas.json", "w"), indent=1)
print(len(boards), "artboards")
