#!/usr/bin/env python3
"""Gather what a weekly tidy-up run needs into one JSON file (docs/director/weekly-tidy.md, DL-240).

Read-only: it runs git, gh, npm and check-hygiene.py, and reads Duo's two field logs and the merge-gate log;
it writes only its output file. Usage: tidy-gather.py <out.json> [--days 7]
Output keys: ranAt, main (sha), hygiene (check-hygiene.py's warnings), worktrees, branches, releases, readme,
cli (new Claude Code versions and the work Mac's pin), fieldLogs (hang and chat-fallback signatures, no screen
text), mergeGate (FAIL and FLAKY rows), budgets, walk. Changelog text from npm or GitHub is untrusted data.
"""
import glob, json, os, re, subprocess, sys
from collections import Counter
from datetime import datetime, timedelta, timezone

MAIN = "/Users/geoff/repos/duo-v2"
ORIGIN = "refs/remotes/origin/main"
SUPPORT = os.path.expanduser("~/Library/Application Support/Duo/logs")
GATE_LOG = os.environ.get("MERGE_GATE_LOG", os.path.expanduser("~/Library/Logs/duo-dev/merge-gate.tsv"))
MEMORY = os.path.expanduser("~/.claude/projects/-Users-geoff-repos-duo-v2/memory/work-mac-claude-version.md")
out = sys.argv[1]
days = int(sys.argv[sys.argv.index("--days") + 1]) if "--days" in sys.argv else 7
now = datetime.now(timezone.utc)
since = now - timedelta(days=days)


def run(*cmd, cwd=MAIN):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


def git(*a):
    return run("git", *a)


def when(v):
    """A Swift JSONEncoder date: seconds since 2001 by default, or an ISO string."""
    if isinstance(v, (int, float)):
        return datetime.fromtimestamp(978307200 + v, timezone.utc)
    try:
        return datetime.fromisoformat(str(v).replace("Z", "+00:00"))
    except ValueError:
        return None


def jsonl(path):
    rows = []
    try:
        for line in open(path, encoding="utf-8", errors="replace"):
            try:
                rows.append(json.loads(line))
            except ValueError:
                pass
    except OSError:
        pass
    return rows


g = {"ranAt": now.isoformat(timespec="seconds"), "days": days, "main": git("rev-parse", ORIGIN).strip()}

# Records, design README, task notes (ENH-281 to ENH-283).
HERE = os.path.dirname(os.path.abspath(__file__))
h = run(sys.executable, "-I", os.path.join(HERE, "..", "..", "scripts", "check-hygiene.py"), "--repo", MAIN, "--ref", ORIGIN, "--json")
g["hygiene"] = json.loads(h)["warnings"] if h else {"error": "check-hygiene.py failed"}

# Work trees and branches: merged into main, or quiet for 14 days. Report only; nothing is removed here.
wts, cur = [], {}
for line in git("worktree", "list", "--porcelain").splitlines() + [""]:
    if not line:
        if cur.get("worktree") and cur["worktree"] != MAIN:
            wts.append(cur)
        cur = {}
    elif " " in line:
        k, v = line.split(" ", 1)
        cur[k] = v
    else:
        cur[line] = True
for w in wts:
    br = w.get("branch", "").replace("refs/heads/", "")
    w["branch"] = br
    w["name"] = os.path.basename(w["worktree"])
    w["dirty"] = bool(run("git", "status", "--porcelain", "--untracked-files=no", cwd=w["worktree"]).strip())
    w["last"] = run("git", "log", "-1", "--format=%cs", cwd=w["worktree"]).strip()
    w["merged"] = bool(br) and subprocess.run(["git", "merge-base", "--is-ancestor", "refs/heads/" + br, ORIGIN], cwd=MAIN).returncode == 0
g["worktrees"] = [{k: w.get(k) for k in ("name", "branch", "last", "merged", "dirty")} for w in wts]
br = []
for line in git("for-each-ref", "--format=%(refname:short)\t%(committerdate:short)", "refs/remotes/origin").splitlines():
    name, date = line.split("\t")
    if name in ("origin/main", "origin/HEAD", "origin"):
        continue
    merged = subprocess.run(["git", "merge-base", "--is-ancestor", "refs/remotes/" + name, ORIGIN], cwd=MAIN).returncode == 0
    if merged or date < (now - timedelta(days=14)).date().isoformat():
        br.append({"name": name, "last": date, "merged": merged})
g["branches"] = br

# Releases, and whether the README and the guide changed since the last tag.
try:
    g["releases"] = json.loads(run("gh", "release", "list", "-R", "dudgeon/duo-v2", "--limit", "8", "--json", "tagName,publishedAt"))
except ValueError:
    g["releases"] = []
tag = g["releases"][0]["tagName"] if g["releases"] else ""
g["readme"] = {
    "lastTag": tag,
    "readmeChanged": bool(git("diff", "--name-only", f"{tag}..{ORIGIN}", "--", "README.md").strip()) if tag else None,
    "guideChanged": bool(git("diff", "--name-only", f"{tag}..{ORIGIN}", "--", "docs/guide").strip()) if tag else None,
    "readmeLast": git("log", "-1", "--format=%cs", ORIGIN, "--", "README.md").strip(),
    "guideLast": git("log", "-1", "--format=%cs", ORIGIN, "--", "docs/guide").strip(),
}

# Claude Code: versions published in the window, the newest, and the work Mac's pin from the director's memory.
cli = {"new": [], "latest": None, "pin": None}
try:
    times = json.loads(run("npm", "view", "@anthropic-ai/claude-code", "time", "--json") or "{}")
    vs = [(v, t) for v, t in times.items() if re.match(r"^\d+\.\d+\.\d+$", v)]
    cli["new"] = sorted(v for v, t in vs if when(t) and when(t) >= since)
    cli["latest"] = max(vs, key=lambda x: x[1])[0] if vs else None
except ValueError:
    pass
try:
    m = re.search(r"(\d+\.\d+\.\d+) since", open(MEMORY).read())
    cli["pin"] = m.group(1) if m else None
except OSError:
    pass
cli["changelogUntrusted"] = True   # the run reads the changelog itself and paraphrases it
g["cli"] = cli

# Field logs: signatures only (never screen text). Hangs: version, length, innermost frame; fallbacks: rule, kind.
hangs = [r for r in jsonl(os.path.join(SUPPORT, "hangs.jsonl")) if when(r.get("at")) and when(r["at"]) >= since]
hs = Counter()
for r in hangs:
    frame = (r.get("samples") or [[None]])[0][:1] or [None]
    hs[(r.get("version", "?"), "ongoing" if r.get("ongoing") else ("≥2s" if r.get("ms", 0) >= 2000 else "<2s"), frame[0])] += 1
fb = [r for r in jsonl(os.path.join(SUPPORT, "chat-fallbacks.jsonl")) if when(r.get("at")) and when(r["at"]) >= since]
fs = Counter((r.get("duo", "?"), r.get("cliVersion"), r.get("rule"), r.get("kind"), r.get("sig")) for r in fb)
g["fieldLogs"] = {
    "note": "Geoff's own Mac only; the work Mac's logs come only when he sends them",
    "hangs": [{"version": v, "length": l, "frame": f, "count": n} for (v, l, f), n in hs.most_common(10)],
    "fallbacks": [{"duo": d, "cli": c, "rule": r, "kind": k, "sig": s, "count": n} for (d, c, r, k, s), n in fs.most_common(10)],
}

# The merge gate's run log (ENH-284): gates that failed or passed only on retry.
rows = []
try:
    for line in open(GATE_LOG):
        p = line.rstrip("\n").split("\t")
        if len(p) == 5 and p[3] in ("FAIL", "FLAKY") and (when(p[0]) or now) >= since:
            rows.append({"at": p[0], "sha": p[1], "gate": p[2], "result": p[3]})
except OSError:
    pass
g["mergeGate"] = {"log": GATE_LOG, "rows": rows, "flakyByGate": Counter(r["gate"] for r in rows if r["result"] == "FLAKY")}

# Budgets: the last finding that records a timing run, and app merges since (check-scale also runs at each release).
last = git("log", "-1", "--format=%H %cs", ORIGIN, "-G", "check-chat-perf|chat-perf budget", "--", "docs/plan/findings.md").split()
g["budgets"] = {
    "chatPerfRecorded": last[1] if len(last) > 1 else None,
    "appMergesSince": len(git("log", "--merges", "--format=%h", f"{last[0]}..{ORIGIN}", "--", "Sources").split()) if last else None,
    "note": "check-scale runs at every release (the release skill's scale gate); check-chat-perf only by hand",
}

# The open acceptance walk.
walk = git("show", f"{ORIGIN}:docs/acceptance/README.md")
open_rows = [l for l in walk.splitlines() if l.startswith("| [") and l.rstrip().endswith("| open |")]
g["walk"] = [{"row": l.split("|")[1].strip()} for l in open_rows]

json.dump(g, open(out, "w"), indent=1, default=str)
print(f"tidy-gather: {len(g['hygiene']) if isinstance(g['hygiene'], list) else '?'} hygiene, {len(g['worktrees'])} work trees, "
      f"{len(br)} branches, {len(cli['new'])} new CLI versions, {len(hangs)} hangs, {len(fb)} fallbacks, {len(rows)} gate rows -> {out}")
