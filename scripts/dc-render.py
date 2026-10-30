#!/usr/bin/env python3
"""Render a Design canvas board (.dc.html) to static HTML for a handoff's screens/.

    scripts/dc-render.py <canvas-dir> <Board.dc.html> <out.html> --comment "<header>" [--surface <s>]

Handles the subset Duo's boards use: {{holes}}, <sc-for>, <sc-if>, <dc-import> (sibling boards), and the
board's renderVals() (run with node, props as JSON). The output is a picture written in HTML, as the other
handoffs' screens are: match what it draws, don't port its markup.
"""
import argparse, html, json, re, subprocess, sys
from html.parser import HTMLParser
from pathlib import Path

VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}


class Node:
    def __init__(self, tag, attrs=None, parent=None):
        self.tag, self.attrs, self.parent, self.kids = tag, attrs or [], parent, []


class Parser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.root = Node("#root")
        self.cur = self.root

    def handle_starttag(self, tag, attrs):
        n = Node(tag, attrs, self.cur)
        self.cur.kids.append(n)
        if tag not in VOID:
            self.cur = n

    def handle_startendtag(self, tag, attrs):
        self.cur.kids.append(Node(tag, attrs, self.cur))

    def handle_endtag(self, tag):
        n = self.cur
        while n is not self.root and n.tag != tag:
            n = n.parent
        if n is not self.root:
            self.cur = n.parent

    def handle_data(self, d):
        self.cur.kids.append(d)

    def handle_entityref(self, name):
        self.cur.kids.append(f"&{name};")

    def handle_charref(self, name):
        self.cur.kids.append(f"&#{name};")


def parse(text):
    p = Parser()
    p.feed(text)
    return p.root


class Board:
    def __init__(self, path: Path):
        src = path.read_text()
        self.title = re.search(r"<title>(.*?)</title>", src, re.S).group(1)
        self.xdc = re.search(r"<x-dc>(.*)</x-dc>", src, re.S).group(1)
        self.style = "\n".join(re.findall(r"<helmet>\s*<style>(.*?)</style>\s*</helmet>", src, re.S))
        self.xdc = re.sub(r"<helmet>.*?</helmet>", "", self.xdc, flags=re.S)
        m = re.search(r"<script type=\"text/x-dc\" data-dc-script[^>]*?data-props='(.*?)'>(.*?)</script>", src, re.S)
        self.props_spec = json.loads(html.unescape(m.group(1)))
        self.js = m.group(2)
        self.tree = parse(self.xdc)


NODE_JS = r"""
class DCLogic { constructor(p) { this.props = p; this.state = {}; } setState() {} forceUpdate() {} }
%s
const v = new Component(%s).renderVals();
process.stdout.write(JSON.stringify(v));
"""
_cache = {}


def render_vals(board, props):
    key = (id(board), json.dumps(props, sort_keys=True))
    if key not in _cache:
        out = subprocess.run(["node", "-e", NODE_JS % (board.js, json.dumps(props))], capture_output=True, text=True, check=True).stdout
        _cache[key] = json.loads(out)
    return _cache[key]


def lookup(scope, path):
    path = path.strip()
    if path in ("true", "false"):
        return path == "true"
    if re.fullmatch(r"-?\d+(\.\d+)?", path):
        return float(path) if "." in path else int(path)
    cur = scope
    for part in path.split("."):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return None
    return cur


def text_of(v):
    if v is None or v is False:
        return ""
    if v is True:
        return "true"
    return str(v)


def interp(s, scope):
    return re.sub(r"\{\{(.*?)\}\}", lambda m: text_of(lookup(scope, m.group(1))), s)


def whole(s, scope):
    m = re.fullmatch(r"\s*\{\{(.*?)\}\}\s*", s or "")
    return lookup(scope, m.group(1)) if m else s


def camel(k):
    return re.sub(r"-([a-z])", lambda m: m.group(1).upper(), k)


class Renderer:
    def __init__(self, folder: Path):
        self.folder, self.boards, self.styles = folder, {}, []

    def board(self, name):
        if name not in self.boards:
            self.boards[name] = Board(self.folder / f"{name}.dc.html")
            self.styles.append(self.boards[name].style)
        return self.boards[name]

    def run(self, board, props):
        scope = render_vals(board, props)
        return "".join(self.node(k, scope) for k in board.tree.kids)

    def node(self, n, scope):
        if isinstance(n, str):
            return interp(n, scope)
        if n.tag == "sc-for":
            a = dict(n.attrs)
            items = whole(a.get("list"), scope) or []
            name = a.get("as", "item")
            return "".join("".join(self.node(k, {**scope, name: it, "$index": i}) for k in n.kids) for i, it in enumerate(items))
        if n.tag == "sc-if":
            v = whole(dict(n.attrs).get("value"), scope)
            return "".join(self.node(k, scope) for k in n.kids) if v else ""
        if n.tag == "dc-import":
            a = dict(n.attrs)
            props = {camel(k): whole(v, scope) for k, v in a.items() if k not in ("name",) and not k.startswith("hint-")}
            return self.run(self.board(a["name"]), props)
        attrs = ""
        for k, v in n.attrs:
            if v is None:
                attrs += f" {k}"
            else:
                attrs += f' {k}="{html.escape(interp(v, scope), quote=True)}"'
        if n.tag in VOID:
            return f"<{n.tag}{attrs}>"
        return f"<{n.tag}{attrs}>" + "".join(self.node(k, scope) for k in n.kids) + f"</{n.tag}>"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder")
    ap.add_argument("board")
    ap.add_argument("out")
    ap.add_argument("--comment", default="")
    ap.add_argument("--surface", default="")
    a = ap.parse_args()
    r = Renderer(Path(a.folder))
    b = r.board(a.board.removesuffix(".dc.html"))
    prev = b.props_spec.get("$preview", {})
    body = r.run(b, {})
    styles = "\n".join(dict.fromkeys(r.styles))
    out = f"""<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="design-size" content="{prev.get('width')}x{prev.get('height')}">
<meta name="design-kind" content="board">
<meta name="design-surface" content="{a.surface}">
<!--
{a.comment}
-->
<title>Duo · {b.title}</title>
<style>
{styles}
</style>
</head>
<body>
{body}
</body>
</html>
"""
    Path(a.out).write_text(out)


if __name__ == "__main__":
    main()
