#!/usr/bin/env python3
"""Builds an acceptance walk page from a sprint's features.json.

    python3 scripts/acceptance/build-page.py docs/acceptance/<sprint>

Writes <sprint>/walk.html from .claude/skills/acceptance-walk/walk-template.html.
Every feature needs `commit` (see the skill); this refuses to build without it.
Publish it with the Artifact tool (capabilities {"db": {}, "comments": {}}); see the acceptance-walk skill.
"""
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
TEMPLATE = ROOT / ".claude/skills/acceptance-walk/walk-template.html"


# A card or decision that points at a design thing (a board, canvas, handoff, screen, mock-up, film...)
# has to link it, in `[label](https://...)` in its text or in `links` (Geoff, 2026-10-30: "this
# acceptance walk artifact NEEDS to always contain links to artifacts that are referenced").
REFERENCE = re.compile(
    r"\b(boards?|canvas(?:es)?|handoffs?|mock-?ups?|films?|videos?|"
    r"(?:the |approved |design |designed )screens?|(?:walk|review|decision|design) page|this page)\b", re.I)
# Words that look like references but name a Duo feature or UI.
NOT_REFERENCE = re.compile(r"task boards?|Obsidian boards?|boards? \| list|list \| board|boards?'s lanes?|"
                           r"(?-i:Boards?(?:'s|,|`| and| or| \||\)))|`Board`|home page|design system|design-system", re.I)
LINK = re.compile(r"\]\(https?://[^)\s]+\)")


def texts(x):
    if isinstance(x, str):
        return [x]
    if isinstance(x, list):
        return [t for i in x for t in texts(i)]
    if isinstance(x, dict):
        return [t for k, v in x.items() if k not in ("mockup", "id", "recommended", "links") for t in texts(v)]
    return []


def unlinked_references(item, keys):
    """The reference words in an item's text when it has no link at all (else [])."""
    if item.get("links"):
        return []
    body = " ".join(t for k in keys for t in texts(item.get(k, ""))) + " " + item.get("title", "")
    if LINK.search(body):
        return []
    body = NOT_REFERENCE.sub(" ", body)
    return sorted({m.group(0).lower() for m in REFERENCE.finditer(body)})


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
    # Where each feature can be walked (Geoff, 2026-10-09): on his work Mac with a stock install and
    # his own folders ("as-is"), after a minute of by-hand setup ("small"), or only with the fixtures,
    # scripts or the home Mac ("home"). The page puts as-is cards first on a phone.
    RATINGS = ("as-is", "small", "home")
    for f in data["features"]:
        if "workMac" not in f:
            sys.exit(f"{f['id']}: no `workMac` (one of {', '.join(RATINGS)}; see the acceptance-walk skill)")
        if f["workMac"] not in RATINGS:
            sys.exit(f"{f['id']}: `workMac` is {f['workMac']!r}, expected one of {', '.join(RATINGS)}")
        if "workMacWhy" in f and not isinstance(f["workMacWhy"], str):
            sys.exit(f"{f['id']}: `workMacWhy` must be a string")
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
    for q in data.get("decisions", []):
        for l in q.get("links", []):
            if not (l.get("label") and str(l.get("url", "")).startswith("http")):
                sys.exit(f"decision {q['id']}: each `links` entry needs a `label` and an http(s) `url`")
    for f in data["features"]:
        for l in f.get("links", []):
            if not (l.get("label") and str(l.get("url", "")).startswith("http")):
                sys.exit(f"{f['id']}: each `links` entry needs a `label` and an http(s) `url`")
    bad = [(f["id"], w) for f in data["features"] for w in [unlinked_references(f, ("what", "steps", "expect"))] if w]
    bad += [("decision " + q["id"], w) for q in data.get("decisions", []) for w in [unlinked_references(q, ("context", "options"))] if w]
    if bad:
        sys.exit("These mention a board, canvas, handoff, screen, design, mock-up, page, film or video without a link "
                 "(add `links: [{label, url}]` or a [label](https://...) in the text):\n" +
                 "\n".join(f"  {i}: {', '.join(w)}" for i, w in bad))
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
    print(f"{out}  ({len(ids)} features, {len(setups)} with setup, {sum(1 for f in data['features'] if f.get('claude'))} tried by Claude; work Mac: {', '.join(str(sum(1 for f in data['features'] if f['workMac'] == r)) + ' ' + r for r in RATINGS)})")


if __name__ == "__main__":
    main()
