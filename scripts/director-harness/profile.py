#!/usr/bin/env python3
"""Profile helper for check-director.sh.

  profile.py setup <profile.json> <config-dir>   write settings.json and .claude.json
  profile.py get <profile.json> <dotted.key>     print one value
  profile.py env <profile.json>                  print KEY=VALUE lines from profile.env
"""
import json, os, sys

cmd, path = sys.argv[1], sys.argv[2]
p = json.load(open(path))
if cmd == "setup":
    d = sys.argv[3]
    os.makedirs(d, exist_ok=True)
    if p.get("settings"):
        json.dump(p["settings"], open(os.path.join(d, "settings.json"), "w"))
    claude = {"hasCompletedOnboarding": True}
    if "monitor" in p.get("flags", {}):
        claude["cachedGrowthBookFeatures"] = {"tengu_amber_sentinel": bool(p["flags"]["monitor"])}
    json.dump(claude, open(os.path.join(d, ".claude.json"), "w"))
elif cmd == "get":
    v = p
    for k in sys.argv[3].split("."):
        v = v[k]
    print(v if isinstance(v, str) else json.dumps(v))
elif cmd == "env":
    for k, v in p.get("env", {}).items():
        print("%s=%s" % (k, v))
