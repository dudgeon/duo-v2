#!/usr/bin/env python3
"""Highest record number of each kind (F, C, Q, ENH, DL) on every ref, from the record files.

  maxrec.py <repo> <refs.txt>
Counts a number only where a record is defined (a heading `## F-12`, a table row `| C-3 |`), so a
mention of a future number in prose doesn't count.
"""
import re, subprocess, sys

repo, refs = sys.argv[1], [l.strip() for l in open(sys.argv[2]) if l.strip()]
files = ["docs/plan/findings.md", "docs/plan/concerns-and-questions.md", "docs/plan/enhancements.md", "docs/design/decisions.md"]
defn = re.compile(r"^(?:#+ |\| ?)(F|C|Q|ENH|DL)-(\d+)\b", re.M)
best = {}
for ref in refs:
    for f in files:
        r = subprocess.run(["git", "-C", repo, "show", f"{ref}:{f}"], capture_output=True, text=True)
        if r.returncode:
            continue
        for kind, n in defn.findall(r.stdout):
            n = int(n)
            if n > best.get(kind, (0, ""))[0]:
                best[kind] = (n, ref)
for k in ("F", "C", "Q", "ENH", "DL"):
    print(k, *best.get(k, (0, "-")))
