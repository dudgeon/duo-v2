"""Inline wf.css into each src/*.html so pages render standalone (file:// or served)."""
import pathlib
root = pathlib.Path(__file__).parent
css = (root / "wf.css").read_text()
for src in sorted((root / "src").glob("*.html")):
    html = src.read_text().replace('<link rel="stylesheet" href="../wf.css">', "<style>\n" + css + "\n</style>")
    (root / src.name).write_text(html)
    print("built", src.name)
