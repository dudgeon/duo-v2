#!/usr/bin/env python3
"""Writes the GitHub study boards as Design-canvas artboards (<root>/project/*.dc.html) and the canvas index.
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
rows = [["00-study", "13-recommendation"],
        ["01-new-from-github", "02-branch"],
        ["03-landing", "04-status"],
        ["05-states", "06-push-pr", "07-fork"],
        ["08-no-gh", "09-get-latest"],
        ["10-failures", "11-duo-and-claude", "12-duo2"]]
heads = ["The study and the recommendation", "1–2 · New project, From GitHub, and the branch",
         "3–4 · Where it lands; the repo’s state on a project", "5–7 · Every state; Push / Open PR; no write access",
         "8–9 · Without the GitHub CLI; Get Latest and conflicts", "10–12 · Failures, Duo and Claude, duo2 repo"]
boards, order, notes, y = {}, [], {}, 0
for i, r in enumerate(rows):
    y += 260; x = 0; mh = 0
    for n in r:
        w, h, t = size[n]
        boards[f"{n}.dc.html"] = {"x": x, "y": y, "w": w, "h": h, "title": t}
        order.append(f"{n}.dc.html"); x += w + 80; mh = max(mh, h)
    notes[f"h{i}"] = {"x": 0, "y": y - 230, "text": heads[i], "kind": "title1", "maxW": x - 80}
    y += mh + 120
json.dump({"v": 3, "createdOnFiles": {"v": 1, "at": created}, "title": "Duo GitHub study",
           "launch": {"view": "canvas"}, "pages": [], "boards": boards, "order": order, "notes": notes,
           "designSystems": [{"title": "Duo", "namespace": "duo", "artifact": "https://claude.ai/artifact/QMapKeLYS3TVV36QKEc6MH",
                              "version": None, "copiedAt": now}]},
          open(f"{root}/project/canvas.json", "w"), indent=1)
print(len(boards), "artboards")
