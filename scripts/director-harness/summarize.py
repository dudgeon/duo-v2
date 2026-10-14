#!/usr/bin/env python3
"""Prints a plugin-eval result.json as one line per case and grader: score, and each failed grader's reason."""
import json, sys

d = json.load(open(sys.argv[1]))
print(f"claude {d.get('claudeVersion')}, ${d.get('costUsd', 0):.3f}, {d.get('durationSeconds')} s")
for c in d.get("cases", []):
    runs = [r for arm in c.get("arms", {}).values() for r in arm]
    agg = c.get("aggregates", {})
    print(f"{c['name']}: score {agg.get('score')}, pass {agg.get('passRate')} ({len(runs)} runs)")
    for r in runs:
        if r.get("error"):
            print(f"   error: {r['error']}")
        for g in r.get("graders", []):
            if not g.get("passed"):
                print(f"   ✘ {g['name']}: {str(g.get('explanation', ''))[:300]}")
    for e in c.get("errors", []) or []:
        print(f"   case error: {e}")
for k in ("errors", "loadErrors", "invalidCases"):
    if d.get(k):
        print(k, json.dumps(d[k])[:1500])
