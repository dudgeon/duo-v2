#!/usr/bin/env python3
"""Creates a demo workspace mirroring the handoff fixture's projects (Phase E).

    scripts/make-demo-workspace.py [root]      default: .build/ws

Each project gets a PROJECT.md (HOME.md for Home) with the fixture's goal/health/next as
Obsidian-compatible frontmatter, and a couple of docs. Sessions aren't faked: run Duo with
`--workspace <root>` and start real ones. Existing folders are left alone.
"""
import json, pathlib, sys

repo = pathlib.Path(__file__).resolve().parent.parent
root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else repo / ".build/ws").resolve()
fixture = json.loads((repo / "docs/design/build-handoff/fixture.json").read_text())

for p in fixture["projects"]:
    folder = root / (p["name"] if p.get("isHome") else f'{p["topic"].lower()}/{p["name"]}')
    marker = folder / ("HOME.md" if p.get("isHome") else "PROJECT.md")
    if marker.exists():
        continue
    folder.mkdir(parents=True, exist_ok=True)
    lines = ["---", f'goal: "{p["goal"]}"']
    if p.get("health"):
        lines.append(f'health: {p["health"].lower().replace(" ", "-")}')
    if p.get("next"):
        lines.append(f'next: "{p["next"]}"')
    lines += ["---", "", f'# {p["name"]}', "", p["goal"] + ".", ""]
    marker.write_text("\n".join(lines))
    for f in fixture.get("projectFiles", {}).get(p["name"], [])[:6]:
        doc = folder / f
        if f.endswith("/") or doc.exists():
            continue
        doc.parent.mkdir(parents=True, exist_ok=True)
        doc.write_text(f"# {doc.stem}\n")
print(root)
