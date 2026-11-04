#!/usr/bin/env python3
"""cmp-sweep.py <dirA> <dirB>: compare two sweep output dirs file by file after normalising ids, times and the
per-run scratch paths. Prints one line per step that differs (rc or text), with a short diff."""
import sys, os, re, difflib

a, b = sys.argv[1:3]
def norm(t):
    t = re.sub(r"/tmp/mwr-[A-Za-z0-9_-]+", "/tmp/MWR", t)
    t = re.sub(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", "<uuid>", t)
    t = re.sub(r"\d{4}-\d\d-\d\dT[\d:.]+Z?", "<ts>", t)
    t = re.sub(r"Session \d+:\d\d [AP]M", "Session <time>", t)
    t = re.sub(r"\b\d+(\.\d+)? ?(s|ms|m|h|d) ago\b", "<ago>", t)
    t = re.sub(r'"(pid|token|socket)"\s*:\s*"?[^",\n]+"?', r'"\1": <x>', t)
    t = re.sub(r"\b\d{9,}(\.\d+)?\b", "<num>", t)
    return t
steps = sorted(set(f.rsplit(".", 1)[0] for f in os.listdir(a) + os.listdir(b) if "." in f and not f.endswith("-support")))
same = diff = 0
for s in steps:
    row = []
    for ext in ("rc", "out", "err"):
        pa, pb = os.path.join(a, f"{s}.{ext}"), os.path.join(b, f"{s}.{ext}")
        ta = norm(open(pa, errors="replace").read()) if os.path.exists(pa) else None
        tb = norm(open(pb, errors="replace").read()) if os.path.exists(pb) else None
        if ta != tb:
            row.append((ext, ta, tb))
    if not row:
        same += 1
        continue
    diff += 1
    print(f"=== {s}")
    for ext, ta, tb in row:
        if ta is None or tb is None:
            print(f"  {ext}: only in {'B' if ta is None else 'A'}")
            continue
        d = list(difflib.unified_diff(ta.splitlines(), tb.splitlines(), "A", "B", lineterm="", n=0))
        for line in d[2:14]:
            print(f"  {ext}: {line[:200]}")
        if len(d) > 14:
            print(f"  {ext}: … {len(d) - 14} more diff lines")
print(f"\nidentical steps: {same}; differing steps: {diff}")
