#!/usr/bin/env python3
"""mkvis.py <root>: a tiny workspace whose project names exist nowhere else (F-583: an isolated Duo can still
resolve real folders by name). <root>/ws (Home + zqv-alpha, zqv-beta, zqv-gamma), <root>/cfg (Claude config with
two planted sessions per project, no real text)."""
import json, os, pathlib, sys, uuid, datetime

root = pathlib.Path(sys.argv[1]).resolve()
ws, cfg = root / "ws", root / "cfg"

def write(p, s):
    p.parent.mkdir(parents=True, exist_ok=True); p.write_text(s)

def enc(path):
    return "".join(c if c.isalnum() else "-" for c in str(path))

write(ws / "zqvhome" / "_HOME.md", "---\ngoal: \"Visible-run home\"\n---\n# zqvhome\n")
names = ["zqv-alpha", "zqv-beta", "zqv-gamma"]
for i, n in enumerate(names):
    d = ws / "zqvtopic" / n
    write(d / "_PROJECT.md", f"---\ngoal: \"Visible run {n}\"\nhealth: on-track\n---\n# {n}\n")
    write(d / "notes.md", f"# Notes for {n}\n\nAlpha line.\n\nbeta line.\n")
    write(d / "other.md", f"# Other {n}\n\nGamma line.\n")
    for k in range(2):
        sid = str(uuid.uuid4())
        t = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=k + 1, hours=i)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
        rows = [
            {"type": "user", "sessionId": sid, "cwd": str(d), "timestamp": t, "uuid": str(uuid.uuid4()),
             "message": {"role": "user", "content": f"zqv test prompt {k} in {n}"}},
            {"type": "assistant", "sessionId": sid, "cwd": str(d), "timestamp": t, "uuid": str(uuid.uuid4()),
             "message": {"role": "assistant", "model": "claude-haiku-5-5", "content": [{"type": "text", "text": f"zqv reply {k}"}]}},
        ]
        write(cfg / "projects" / enc(d) / f"{sid}.jsonl", "".join(json.dumps(r) + "\n" for r in rows))
print(ws)
