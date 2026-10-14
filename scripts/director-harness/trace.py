#!/usr/bin/env python3
"""Prints an eval run's trace.jsonl readably: each tool call, its result (cut), and the assistant's text."""
import json, sys

for line in open(sys.argv[1]):
    try:
        e = json.loads(line)
    except Exception:
        continue
    m = e.get("message") or {}
    if not isinstance(m, dict): continue
    for b in m.get("content", []) if isinstance(m.get("content"), list) else []:
        if b.get("type") == "text" and e.get("type") == "assistant":
            print("SAY:", b["text"][:1200])
        elif b.get("type") == "tool_use":
            print("CALL", b["name"], json.dumps(b["input"])[:700])
        elif b.get("type") == "tool_result":
            c = b.get("content")
            c = c if isinstance(c, str) else json.dumps(c)
            print("  ->", c[:500].replace("\n", " | "))
