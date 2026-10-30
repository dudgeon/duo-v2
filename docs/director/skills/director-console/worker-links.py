#!/usr/bin/env python3
"""Each background worker's console facts: name, state, the Remote Control link that opens its
session (claude.ai/code/session_…, works on Geoff's phone), and the artifacts it has open
(canvases, pages). Reads ~/.claude/jobs/*/state.json; prints JSON. Optional args: names or id prefixes."""
import json, sys, glob, os
want = set(sys.argv[1:])
out = []
for p in glob.glob(os.path.expanduser("~/.claude/jobs/*/state.json")):
    try:
        d = json.load(open(p))
    except Exception:
        continue
    name, sid = d.get("name") or "", d.get("sessionId") or ""
    if want and name not in want and not any(sid.startswith(w) for w in want):
        continue
    bridge = d.get("bridgeSessionId") or ""
    link = "https://claude.ai/code/session_" + bridge.split("_", 1)[1] if bridge.startswith("cse_") else None
    arts = [{"title": c.get("title"), "url": c.get("href")} for c in d.get("children") or [] if c.get("href")]
    out.append({"name": name, "id": sid[:8], "state": d.get("state"), "updated": d.get("updatedAt"),
                "link": link, "artifacts": arts})
out.sort(key=lambda x: x.get("updated") or "", reverse=True)
print(json.dumps(out, indent=1))
