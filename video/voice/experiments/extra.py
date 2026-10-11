import sys; sys.path.insert(0, "experiments")
import expr, numpy as np, tts
m = tts.load("design")
t = expr.PASSAGE.replace("Duo v2", "Duo version two")
expr.save("D2-design-passage-respelled", expr.gen(m, t, 11, instruct=expr.EXPR), expr.PASSAGE, dict(seed=11, spoken_text=t))
# per-line medians for consistency (C-style)
for i, l in enumerate(expr.LINES):
    a = expr.gen(m, l, 11, instruct=expr.EXPR)
    expr.sf.write(expr.OUT / "wav" / f"zz-C-line{i+1}.wav", a, expr.SR)
