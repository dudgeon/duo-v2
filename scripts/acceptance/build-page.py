#!/usr/bin/env python3
"""Builds an acceptance walk page from a sprint's features.json.

    python3 scripts/acceptance/build-page.py docs/acceptance/<sprint>

Writes <sprint>/walk.html from .claude/skills/acceptance-walk/walk-template.html.
Publish it with the Artifact tool (capabilities {"db": {}}); see the acceptance-walk skill.
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
TEMPLATE = ROOT / ".claude/skills/acceptance-walk/walk-template.html"


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sprint = pathlib.Path(sys.argv[1])
    data = json.loads((sprint / "features.json").read_text())
    ids = [f["id"] for f in data["features"]]
    dupes = {i for i in ids if ids.count(i) > 1}
    if dupes:
        sys.exit(f"duplicate feature ids: {sorted(dupes)}")
    for f in data["features"]:
        missing = {"id", "group", "title", "steps", "expect"} - f.keys()
        if missing:
            sys.exit(f"{f.get('id', '?')}: missing {sorted(missing)}")
    # Embedded in a <script> block: keep "</" from closing it.
    payload = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
    html = TEMPLATE.read_text().replace("__TITLE__", data["title"]).replace("__DATA__", payload)
    out = sprint / "walk.html"
    out.write_text(html)
    print(f"{out}  ({len(ids)} features)")


if __name__ == "__main__":
    main()
