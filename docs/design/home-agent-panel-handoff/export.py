#!/usr/bin/env python3
"""Strips the .dc.html wrapper from the study's boards C1 and C2 into screens/*.html (run from the repo root)."""
import re
src = "docs/design/home-agent-panel-study/canvas/project"
out = "docs/design/home-agent-panel-handoff/screens"
meta = {
    "c1-allprojects": ("All projects without Home's column", "the middle takes the width the column had; a Home session that needs you is an ordinary card"),
    "c2-homepage": ("Home's page", "a project page as built, with the home name; Home's sessions and console live here only"),
}
for n, (t, d) in meta.items():
    s = open(f"{src}/{n}.dc.html").read()
    style = re.search(r"<style>(.*?)</style>", s, re.S).group(1)
    body = re.search(r"</helmet>\n(.*?)\n</x-dc>", s, re.S).group(1)
    w, h = re.search(r'"width":(\d+),"height":(\d+)', s).groups()
    open(f"{out}/{n}.html", "w").write(f'''<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="design-size" content="{w}x{h}">
<meta name="design-kind" content="target">
<meta name="design-surface" content="home-agent-panel">
<!--
{t} · {w}x{h}
APPROVED. Geoff, 2026-11-11 (DL-336). Exported from the Design canvas https://claude.ai/artifact/PBJttSgB17RzCn8WQQo6sF ({n}.dc.html).
{d}. The yellow notes and the sample data are the board's, not the app's.
-->
<title>Duo · {t}</title>
<style>{style}</style>
</head>
<body>
{body}
</body></html>
''')
