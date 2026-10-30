#!/usr/bin/env python3
"""Helper for check-fork-primer.sh: plant a parent transcript, serve a stub API, report what the fork saw."""
import http.server, json, os, sys


def plant(b, P, cwd):
    u, a = "bbbbbbbb-0000-4000-8000-000000000001", "bbbbbbbb-0000-4000-8000-000000000002"

    def rec(typ, uuid, parent, text):
        r = {"parentUuid": parent, "isSidechain": False, "userType": "external", "cwd": cwd, "sessionId": P,
             "version": "2.1.311", "type": typ, "uuid": uuid, "timestamp": "2026-10-30T10:00:00Z"}
        r["message"] = {"role": "user", "content": text} if typ == "user" else {
            "id": "msg_1", "type": "message", "role": "assistant", "model": "claude-haiku-5-5",
            "content": [{"type": "text", "text": text}], "stop_reason": "end_turn", "stop_sequence": None,
            "usage": {"input_tokens": 1, "output_tokens": 1}}
        return r
    with open(f"{b}/{P}.jsonl", "w") as f:
        for r in [rec("user", u, None, "hello"), rec("assistant", a, u, "hi")]:
            f.write(json.dumps(r) + "\n")


def sse(ev, d):
    return f"event: {ev}\ndata: {json.dumps(d)}\n\n".encode()


def serve(W):
    class H(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            body = self.rfile.read(int(self.headers.get("content-length", 0)))
            if "/messages" not in self.path:
                self.send_response(404); self.end_headers(); return
            open(W + "/request.jsonl", "ab").write(body + b"\n")
            req = json.loads(body)
            after_tool = "tool_result" in json.dumps(req.get("messages", []))
            self.send_response(200); self.send_header("content-type", "text/event-stream"); self.end_headers()
            msg = {"id": "msg_s", "type": "message", "role": "assistant", "model": req.get("model", "m"), "content": [],
                   "stop_reason": None, "stop_sequence": None, "usage": {"input_tokens": 1, "output_tokens": 1}}
            out = [sse("message_start", {"type": "message_start", "message": msg})]
            if after_tool or not req.get("tools"):
                out += [sse("content_block_start", {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}),
                        sse("content_block_delta", {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "done"}})]
                stop = "end_turn"
            else:
                cmd = 'echo "CLAUDE_CODE_SESSION_ID=$CLAUDE_CODE_SESSION_ID DUO_SESSION_ID=$DUO_SESSION_ID" > ' + W + "/env.txt"
                out += [sse("content_block_start", {"type": "content_block_start", "index": 0, "content_block": {"type": "tool_use", "id": "toolu_1", "name": "Bash", "input": {}}}),
                        sse("content_block_delta", {"type": "content_block_delta", "index": 0, "delta": {"type": "input_json_delta", "partial_json": json.dumps({"command": cmd})}})]
                stop = "tool_use"
            out += [sse("content_block_stop", {"type": "content_block_stop", "index": 0}),
                    sse("message_delta", {"type": "message_delta", "delta": {"stop_reason": stop, "stop_sequence": None}, "usage": {"output_tokens": 1}}),
                    sse("message_stop", {"type": "message_stop"})]
            for o in out:
                self.wfile.write(o)

        def do_GET(self):
            self.send_response(404); self.end_headers()

        def log_message(self, *a):
            pass
    http.server.HTTPServer(("127.0.0.1", 47124), H).serve_forever()


def report(W, P):
    raw = open(W + "/out.txt").read()
    try:
        # Older CLIs print a warning line before the result, so read the last line that is JSON.
        fork = json.loads([l for l in raw.splitlines() if l.startswith("{")][-1]).get("session_id")
    except Exception:
        fork = None
        print("no result JSON:", raw[:300])
    print("parent id:", P)
    print("fork id:  ", fork)
    reqs = [json.loads(l) for l in open(W + "/request.jsonl").read().splitlines() if l.strip()] if os.path.exists(W + "/request.jsonl") else []
    sysp = json.dumps(reqs[0].get("system")) if reqs else ""
    print("requests:", len(reqs))
    print("request carries the primer line:", "CLAUDE_CODE_SESSION_ID:-" + P in sysp)
    print("request carries a socket or token:", any(w in sysp for w in ("DUO_TOKEN", "DUO_SOCKET")))
    env = open(W + "/env.txt").read().strip() if os.path.exists(W + "/env.txt") else "(Bash never ran)"
    print("Bash child saw:", env)
    ok = fork and fork != P and env.startswith("CLAUDE_CODE_SESSION_ID=" + fork)
    print("PASS: the fork's own id reaches Bash" if ok else "NOT PROVEN")


{"plant": lambda a: plant(*a), "serve": lambda a: serve(*a), "report": lambda a: report(*a)}[sys.argv[1]](sys.argv[2:])
