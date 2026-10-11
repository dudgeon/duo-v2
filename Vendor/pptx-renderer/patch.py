"""Stamps each rendered shape with its OOXML identity (ENH-12 spike).

@aiden0z/pptx-renderer keeps the shape id (p:cNvPr id) and name in its model but not in the DOM.
Its node dispatcher (one switch on nodeType, also handed to groups for their children) is wrapped
so every element it returns carries data-duo-shape-id, -name and -type.
"""
import re
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()
m = re.search(r'function (\w+)\((\w+), (\w+)\) \{\n  switch \(\2\.nodeType\) \{\n    case "shape":', src)
if not m:
    sys.exit("dispatcher not found: the bundle changed; update the pattern")
name, a, b = m.groups()
wrapper = (f"function {name}({a}, {b}) {{\n"
           f"  const el = {name}__duo({a}, {b});\n"
           f"  if (el && el.dataset) {{ el.dataset.duoShapeId = {a}.id ?? \"\"; el.dataset.duoShapeName = {a}.name ?? \"\"; el.dataset.duoShapeType = {a}.nodeType; }}\n"
           f"  return el;\n}}\n")
src = src[:m.start()] + wrapper + f"function {name}__duo({a}, {b}) {{" + src[m.start() + len(f"function {name}({a}, {b}) {{"):]
open(path, "w", encoding="utf-8").write(src)
print(f"patched {name}() in {path}")

# Second patch: charts draw without animation frames. The renderer starts a chart from requestAnimationFrame
# and ECharts animates its first draw; a page in a window that isn't on screen gets no frames (F-102), so a
# capture showed an empty chart. A timer stands in for the missing frame, and the first draw doesn't animate.
src = open(path, encoding="utf-8").read()
frame = "x = requestAnimationFrame(() => {"
if src.count(frame) != 1 or src.count("i.setOption(t), r == null") != 1:
    sys.exit("chart patch: the bundle changed; update the patterns")
src = src.replace(frame, "x = duoFrame(() => {")
src = src.replace("i.setOption(t), r == null", "i.setOption({ ...t, animation: false }), r == null")
src += ("\nfunction duoFrame(cb) {\n  let done = false;\n  const run = () => { if (!done) { done = true; cb(); } };\n"
        "  const id = requestAnimationFrame(run);\n  setTimeout(() => { cancelAnimationFrame(id); run(); }, 120);\n  return id;\n}\n")
open(path, "w", encoding="utf-8").write(src)
print("patched chart frames")
