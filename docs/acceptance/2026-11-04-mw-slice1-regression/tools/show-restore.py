#!/usr/bin/env python3
"""show-restore.py <raw dir>: summarise restore.sh outputs (what each launch showed after the upgrade)."""
import json, os, sys
base = sys.argv[1]
for d in ("restore-22-22", "restore-22-new", "restore-23-new"):
    print("##", d)
    p = os.path.join(base, d)
    for st in ("first", "second", "third"):
        for k in ("status", "tabs", "split", "window"):
            f = os.path.join(p, f"{st}-{k}.out")
            if not os.path.exists(f):
                continue
            t = open(f, errors="replace").read()
            if k == "status":
                try:
                    j = json.loads(t)
                    t = json.dumps({x: j.get(x) for x in ("view", "project", "documents", "rightTab", "pane")}) + f" window={j.get('window')} session={(j.get('session') or {}).get('project')}"
                except Exception:
                    pass
            print(f"  {st}-{k}: {t.strip()[:230]!r}")
    for f in ("restore-files.txt",):
        q = os.path.join(p, f)
        if os.path.exists(q):
            print("  files:", open(q).read().split())
