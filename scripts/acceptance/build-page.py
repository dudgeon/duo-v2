#!/usr/bin/env python3
"""Builds an acceptance walk page from a sprint's features.json.

    python3 scripts/acceptance/build-page.py docs/acceptance/<sprint>

Writes <sprint>/walk.html from .claude/skills/acceptance-walk/walk-template.html.
Every feature needs `commit` (see the skill); this refuses to build without it.
Publish it with the Artifact tool (capabilities {"db": {}, "comments": {}}); see the acceptance-walk skill.
"""
import json
import pathlib
import subprocess
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
    # Every feature is tied to the commit that built it, so a rejected one can be reverted
    # (Geoff, 2026-10-05). `commit`: a full sha in HEAD's history; `alsoCommits`: later commits
    # that changed it; or `commit: null` with `noCommit` saying why there's nothing to revert.
    git = lambda *a: subprocess.run(["git", "-C", str(ROOT), *a], capture_output=True, text=True)
    for f in data["features"]:
        if "commit" not in f:
            sys.exit(f"{f['id']}: no `commit` (the commit that built it; see the acceptance-walk skill)")
        if f["commit"] is None:
            if not f.get("noCommit"):
                sys.exit(f"{f['id']}: `commit` is null without a `noCommit` reason")
            continue
        info = []
        for sha in [f["commit"], *f.get("alsoCommits", [])]:
            if not isinstance(sha, str) or len(sha) != 40:
                sys.exit(f"{f['id']}: {sha!r} isn't a full commit sha")
            if git("cat-file", "-e", sha + "^{commit}").returncode != 0:
                sys.exit(f"{f['id']}: commit {sha} doesn't exist here")
            if git("merge-base", "--is-ancestor", sha, "HEAD").returncode != 0:
                sys.exit(f"{f['id']}: commit {sha} isn't in HEAD's history")
            info.append({"sha": sha, "subject": git("log", "-1", "--format=%s", sha).stdout.strip()})
        f["commitInfo"] = info
    data["repo"] = git("remote", "get-url", "origin").stdout.strip().removesuffix(".git")
    data["builtAt"] = git("rev-parse", "HEAD").stdout.strip()
    for q in data.get("decisions", []):
        missing = {"id", "title", "context", "options"} - q.keys()
        if missing:
            sys.exit(f"decision {q.get('id', '?')}: missing {sorted(missing)}")
    # Embedded in a <script> block: keep "</" from closing it.
    payload = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
    html = TEMPLATE.read_text().replace("__TITLE__", data["title"]).replace("__DATA__", payload)
    # What "Set up test" runs (DL-81): Duo reads this local file, never steps from a link.
    setups = {f["id"]: f["setup"] for f in data["features"] if f.get("setup")}
    walk_file = pathlib.Path.home() / "DuoAcceptance" / "walk-setups.json"
    walk_file.parent.mkdir(parents=True, exist_ok=True)
    walk_file.write_text(json.dumps({"workspace": str(pathlib.Path.home() / "DuoAcceptance" / "workspace"),
                                     "repo": str(ROOT), "walk": sprint.name, "setups": setups}, indent=1))
    out = sprint / "walk.html"
    out.write_text(html)
    print(f"{out}  ({len(ids)} features, {len(setups)} with setup, {sum(1 for f in data['features'] if f.get('claude'))} tried by Claude)")


if __name__ == "__main__":
    main()
