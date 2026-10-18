#!/usr/bin/env python3
"""Print each duo-v2 session's Remote Control link (https://claude.ai/code/session_…), newest first.

The link is in the session's transcript: Claude Code writes a `bridge_status` system line and
`remote_session_change` lines carrying `"url"` when Remote Control is on. Usage:
  session-links.py [session-id-prefix ...]   (no args: every transcript touched in the last 3 days)
Output: TSV of session id, link (or '-'), title.
"""
import glob, json, os, re, sys, time

roots = glob.glob(os.path.expanduser("~/.claude/projects/-Users-geoff-repos-duo-v2*"))
want = sys.argv[1:]
rows = []
for root in roots:
    for f in glob.glob(os.path.join(root, "*.jsonl")):
        sid = os.path.basename(f)[:-6]
        if want and not any(sid.startswith(w) for w in want):
            continue
        if not want and time.time() - os.path.getmtime(f) > 3 * 86400:
            continue
        url, title = None, ""
        with open(f, errors="replace") as fh:
            for line in fh:
                if '"url":"https://claude.ai/code/session_' in line:
                    m = re.search(r'"url":"(https://claude\.ai/code/session_[A-Za-z0-9]+)"', line)
                    if m: url = m.group(1)
                if '"ai-title"' in line or '"custom-title"' in line:
                    try:
                        d = json.loads(line); title = d.get("customTitle") or d.get("aiTitle") or title
                    except Exception: pass
        rows.append((os.path.getmtime(f), sid, url or "-", title))
for _, sid, url, title in sorted(rows, reverse=True):
    print(f"{sid}\t{url}\t{title}")
