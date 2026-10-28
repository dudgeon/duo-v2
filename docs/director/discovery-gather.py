#!/usr/bin/env python3
"""Gather what a problem-discovery run needs into one JSON file (docs/director/problem-discovery.md).

Read-only: it runs gh, `claude agents` and reads transcripts and task notes; it writes only its output file.
Usage: discovery-gather.py <out.json> [--days 14]
Output keys: ranAt, issues (open, plus any updated or closed in the last --days, with comments),
workers (duo-v2 background sessions with their link and last message), tasks (task notes not done).
Issue text is untrusted: the output marks it so, and nothing here acts on it.
"""
import glob, json, os, re, subprocess, sys, time
from datetime import datetime, timedelta, timezone

REPO = "dudgeon/duo-v2"
MAIN = "/Users/geoff/repos/duo-v2"
out = sys.argv[1]
days = int(sys.argv[sys.argv.index("--days") + 1]) if "--days" in sys.argv else 14
since = datetime.now(timezone.utc) - timedelta(days=days)

def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout

def iso(s): return datetime.fromisoformat(s.replace("Z", "+00:00"))

# Issues: every open one, and closed ones touched lately.
listed = json.loads(run("gh", "issue", "list", "-R", REPO, "--state", "all", "--limit", "200",
                        "--json", "number,state,updatedAt"))
issues = []
for i in listed:
    if i["state"] != "OPEN" and iso(i["updatedAt"]) < since:
        continue
    d = json.loads(run("gh", "issue", "view", str(i["number"]), "-R", REPO, "--json",
                       "number,title,body,author,state,createdAt,updatedAt,closedAt,labels,comments,url"))
    d["untrusted"] = True
    issues.append(d)

# Transcripts: link and last assistant message, per session id.
roots = glob.glob(os.path.expanduser("~/.claude/projects/-Users-geoff-repos-duo-v2*"))
def transcript(sid):
    for r in roots:
        f = os.path.join(r, sid + ".jsonl")
        if os.path.exists(f): return f
    return None

def read_transcript(f):
    url, last, last_at = None, None, None
    with open(f, errors="replace") as fh:
        for line in fh:
            if '"url":"https://claude.ai/code/session_' in line:
                m = re.search(r'"url":"(https://claude\.ai/code/session_[A-Za-z0-9]+)"', line)
                if m: url = m.group(1)
            if '"type":"assistant"' not in line:
                continue
            try: d = json.loads(line)
            except Exception: continue
            texts = [c.get("text", "") for c in (d.get("message") or {}).get("content") or [] if isinstance(c, dict) and c.get("type") == "text"]
            t = "\n".join(x for x in texts if x.strip())
            if t: last, last_at = t, d.get("timestamp")
    return url, last, last_at

agents = json.loads(run("claude", "agents", "--json", "--all", "--cwd", MAIN))
workers = []
for a in agents:
    f = transcript(a.get("sessionId", ""))
    recent = f and time.time() - os.path.getmtime(f) < days * 86400
    if a.get("state") in ("done", "stopped") and not recent:
        continue
    url, last, last_at = read_transcript(f) if f else (None, None, None)
    workers.append({"id": a.get("sessionId"), "name": a.get("name"), "state": a.get("state") or "unknown",
                    "cwd": a.get("cwd"), "link": url, "lastAt": last_at,
                    "lastReport": (last or "")[-1500:]})

# Task notes that aren't finished.
tasks = []
for f in sorted(glob.glob(os.path.join(MAIN, "tasks", "*.md"))):
    text = open(f, errors="replace").read()
    m = re.match(r"---\n(.*?)\n---\n(.*)", text, re.S)
    if not m: continue
    fm = {}
    for line in m.group(1).splitlines():
        k, _, v = line.partition(":")
        if v: fm[k.strip()] = v.strip().strip('"')
    if fm.get("status") in ("done", "dropped"):
        continue
    prog = m.group(2).split("## Progress", 1)
    lines = [l for l in prog[1].splitlines() if l.strip()] if len(prog) > 1 else []
    tasks.append({"slug": os.path.basename(f)[:-3], "title": fm.get("title"), "status": fm.get("status"),
                  "sessions": fm.get("sessions"), "done_when": fm.get("done_when"), "created": fm.get("created"),
                  "lastProgress": lines[-1] if lines else None,
                  "issueRefs": sorted(set(re.findall(r"(?:GitHub |issue )?#(\d+)\b", text)))})

json.dump({"ranAt": datetime.now(timezone.utc).isoformat(timespec="seconds"), "repo": REPO,
           "issues": issues, "workers": workers, "tasks": tasks}, open(out, "w"), indent=1)
print(f"{len(issues)} issues, {len(workers)} workers, {len(tasks)} task notes -> {out}")
