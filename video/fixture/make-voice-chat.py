#!/usr/bin/env python3
"""The 0.2.22 film's sent dictation: chat-s4's recording (Auto-add decision, where the film's chat stands) with Sam's
dictated words sent as his next message, the words exactly as the recognizer settled them (dictation/recognized.json).
Writes chat-vv-sent/. Sample data only."""
import json, os, shutil
HERE = os.path.dirname(os.path.abspath(__file__))
words = " ".join(json.load(open(os.path.join(HERE, "dictation/recognized.json")))["chat"]["phrases"])
base = [json.loads(l) for l in open(os.path.join(HERE, "chat-s4/transcript.jsonl"), encoding="utf-8")]
last = base[-1]
sent = {"type": "user", "uuid": last["uuid"][:-12] + "%012d" % (int(last["uuid"][-12:]) + 1), "parentUuid": last["uuid"],
        "sessionId": last["sessionId"], "cwd": last["cwd"], "message": {"role": "user", "content": words},
        "origin": {"kind": "human"}, "timestamp": "2026-10-13T09:52:30.000Z"}
out = os.path.join(HERE, "chat-vv-sent")
shutil.rmtree(out, ignore_errors=True); os.makedirs(out)
with open(os.path.join(out, "transcript.jsonl"), "w", encoding="utf-8") as f:
    for e in base + [sent]: f.write(json.dumps(e, ensure_ascii=False) + "\n")
json.dump({"mode": "chat", "tab": "Auto-add decision"}, open(os.path.join(out, "meta.json"), "w"), indent=1)
print("chat-vv-sent:", words)
