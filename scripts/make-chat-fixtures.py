#!/usr/bin/env python3
"""Writes the chat-mode targets' recordings: docs/design/chat-mode-handoff/fixture-chat/<board>/.

Each board's content (names and data are the boards' own, illustrative) as Claude Code would record
it: transcript lines (`transcript.jsonl`), Duo's hook events (`events.jsonl`, {"at", "e"}), the
TUI's screen (`screen.txt`, Claude Code 2.1.291's layout) and `meta.json`. ChatTargets plays them
through the same readers a live session uses.

  python3 scripts/make-chat-fixtures.py
"""
import json, pathlib, datetime

root = pathlib.Path(__file__).resolve().parent.parent
out = root / "docs/design/chat-mode-handoff/fixture-chat"
spike = root / "Spikes/chat-mode/screens"
CWD = "/Users/pm/work/payments/checkout-redesign"
DAY = datetime.datetime(2026, 10, 6, tzinfo=datetime.timezone.utc)


def ts(hm, s=0):
    h, m = map(int, hm.split(":"))
    return (DAY + datetime.timedelta(hours=h, minutes=m, seconds=s))


def iso(hm, s=0):
    return ts(hm, s).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def epoch(hm, s=0):
    return ts(hm, s).timestamp()


class Rec:
    def __init__(self):
        self.t, self.e = [], []

    def you(self, hm, text):
        self.t.append({"type": "user", "message": {"role": "user", "content": text}, "timestamp": iso(hm), "origin": {"kind": "human"}, "cwd": CWD})

    def say(self, hm, text, s=0):
        self.t.append({"type": "assistant", "message": {"content": [{"type": "text", "text": text}]}, "timestamp": iso(hm, s), "cwd": CWD})

    def think(self, hm, ms):
        self.t.append({"type": "assistant", "message": {"content": [{"type": "thinking", "thinking": ""}]}, "thinkingDurationMs": ms, "timestamp": iso(hm)})

    def tool(self, hm, id, name, inp, result=None, content="", error=False, denial=None):
        self.t.append({"type": "assistant", "message": {"content": [{"type": "tool_use", "id": id, "name": name, "input": inp}]}, "timestamp": iso(hm)})
        if result is None and not error and denial is None:
            return
        r = {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": id, "content": content, "is_error": error}]},
             "timestamp": iso(hm), "toolUseResult": result if result is not None else content}
        if denial:
            r["toolDenialKind"] = denial
        self.t.append(r)

    def hook(self, hm, s, **e):
        self.e.append({"at": epoch(hm, s), "e": {"session_id": "fixture", "cwd": CWD, **e}})

    def stream(self, hm, s, mid, lines, final=False):
        for i, l in enumerate(lines):
            self.hook(hm, s + i, hook_event_name="MessageDisplay", message_id=mid, index=i, final=final and i == len(lines) - 1, delta=l)

    def write(self, board, meta, screen):
        d = out / board
        d.mkdir(parents=True, exist_ok=True)
        (d / "transcript.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in self.t))
        (d / "events.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in self.e))
        (d / "meta.json").write_text(json.dumps(meta, indent=1, ensure_ascii=False) + "\n")
        if screen:
            (d / "screen.txt").write_text((spike / screen).read_text())


IDLE = "tour-2.1.291/01-markdown.txt"
BUSY = "48-streaming.txt"

# window: the project window in chat mode.
r = Rec()
r.you("9:41", "Tighten the **non-goals** in `docs/prd-v2.md`, then check what the interviews say about saved cards.")
r.tool("9:42", "toolu_w1", "Read", {"file_path": CWD + "/research/interviews.md"}, {"type": "text", "file": {"filePath": CWD + "/research/interviews.md", "content": "# Interviews", "numLines": 214, "totalLines": 214}})
r.tool("9:42", "toolu_w2", "Edit", {"file_path": CWD + "/docs/prd-v2.md", "old_string": "3. Saved cards.\n- Wallets.", "new_string": "2. Storing cards for guests in this release.\n- (Interviews disagree.)\n- Wallets.\n- Later."},
       {"filePath": CWD + "/docs/prd-v2.md", "structuredPatch": [{"oldStart": 31, "oldLines": 2, "newStart": 31, "newLines": 4, "lines": ["-3. Saved cards.", "-- Wallets.", "+2. Storing cards for guests in this release.", "+- (Interviews disagree.)", "+- Wallets.", "+- Later."]}]})
r.say("9:42", "## Non-goals, tightened\n\nI cut non-goal #3 (it repeated #1). Two of six interviewees named saved cards as the reason they abandon guest checkout:\n\n- **P2**, ops lead: “I’m not typing a card number on my phone again.”\n- **P5**, frequent buyer: “If it remembered me, I’d finish.”\n\nMove saved cards into scope, or keep it out and log an open question?", 30)
r.hook("9:42", 40, hook_event_name="Stop", last_assistant_message="…")
r.write("window", {"mode": "chat", "tab": "PRD v2 edits", "toggled": ["toolu_w2"]}, IDLE)

# text: Markdown, thinking, streaming with the Writing line.
r = Rec()
r.you("9:52", "Compare the **two refund flows** in a table, with a short recommendation.")
r.think("9:52", 6000)
lines = ["## Refund flows compared\n", "\n", "Both flows are in `docs/refunds/flows.md:42`. The main difference is **who confirms** the refund.\n", "\n",
         "| Flow | Confirms | Median time |\n", "|---|---|---|\n", "| Self-serve | Buyer | 2 min |\n", "| Assisted | Support agent | 3.4 h |\n", "\n",
         "1. Keep self-serve as the default.\n", "2. Route orders over $500 to assisted.\n", "\n",
         "```\n", "refund.threshold = 500   // USD\n", "refund.route     = \"assisted\"\n", "```\n", "\n",
         "See the [Stripe refunds guide](https://stripe.com/docs/refunds) for the limits on partial refu"]
r.hook("9:52", 0, hook_event_name="UserPromptSubmit", prompt="Compare the **two refund flows** in a table, with a short recommendation.", source="user")
r.stream("9:52", 2, "m-text", lines)
r.write("text", {"mode": "chat", "tab": "PRD v2 edits", "now": iso("9:52", 14), "states": {"PRD v2 edits": "working"}}, BUSY)

# tools: every kind of step.
r = Rec()
r.tool("10:04", "toolu_t1", "Read", {"file_path": CWD + "/research/interviews.md"}, {"type": "text", "file": {"content": "# Interviews\n\nP1 …", "numLines": 214, "totalLines": 214}})
r.tool("10:04", "toolu_t2", "Grep", {"pattern": "saved card", "path": "research"}, {"mode": "content", "numFiles": 2, "numLines": 6, "content": "research/interviews.md:12: saved card"})
r.tool("10:04", "toolu_t3", "WebFetch", {"url": "https://stripe.com/docs/refunds", "prompt": "limits"}, {"bytes": 12288, "code": 200, "result": "Refunds …"})
r.tool("10:04", "toolu_t4", "Edit", {"file_path": CWD + "/docs/prd-v2.md", "old_string": "- Saved cards for guests, for now.", "new_string": "+ Storing cards for guests in this release.\n+ (Interviews disagree: see Open questions.)"},
       {"structuredPatch": [{"oldStart": 31, "oldLines": 2, "newStart": 31, "newLines": 3, "lines": [" ## Non-goals", "-Saved cards for guests, for now.", "+Storing cards for guests in this release.", "+(Interviews disagree: see Open questions.)"]}]})
out_lines = ["docs/prd-v2.md: 0 problems", "docs/refunds/flows.md: 0 problems"] + [f"docs/page-{i}.md: 0 problems" for i in range(38)]
r.tool("10:04", "toolu_t5", "Bash", {"command": "npm run lint:docs"}, {"stdout": "\n".join(out_lines), "stderr": "", "interrupted": False})
r.tool("10:04", "toolu_t6", "Bash", {"command": "rg -n \"saved card\" research/old/"}, None, content="Exit code 2\nrg: research/old/: No such file or directory (os error 2)", error=True)
r.tool("10:04", "toolu_t7", "Task", {"description": "Survey cross-check", "prompt": "…", "run_in_background": True}, {"isAsync": True, "status": "async_launched", "agentId": "a1"})
r.hook("10:04", 30, hook_event_name="SubagentStart", agent_id="a7", agent_type="general-purpose")
r.hook("10:05", 0, hook_event_name="SubagentStop", agent_id="a7", agent_type="general-purpose", last_assistant_message="31% of survey respondents mention saved cards; it’s the second most common reason after delivery cost.")
r.t.append({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "toolu_t7", "content": "done"}]}, "timestamp": iso("10:06"),
            "toolUseResult": {"isAsync": True, "totalDurationMs": 134000, "totalToolUseCount": 18, "status": "completed"}})
r.say("10:06", "The edit is in. One search failed because `research/old/` doesn’t exist; nothing else needed it.")
r.hook("10:06", 10, hook_event_name="Stop", last_assistant_message="The edit is in.")
r.write("tools", {"mode": "chat", "tab": "PRD v2 edits"}, IDLE)

# status: compaction, a background agent's line, an interrupt.
r = Rec()
r.t.append({"type": "system", "subtype": "compact_boundary", "timestamp": iso("10:58")})
r.hook("10:59", 0, hook_event_name="SubagentStart", agent_id="a1", agent_type="Survey cross-check")
r.say("10:59", "The survey cross-check is running in the background. I’ll draft the rollout section meanwhile.")
r.hook("10:59", 30, hook_event_name="Stop", last_assistant_message="…")
r.hook("11:01", 0, hook_event_name="SubagentStop", agent_id="a1", agent_type="Survey cross-check", last_assistant_message="31% …")
r.you("11:02", "Actually, hold the rollout section.")
r.hook("11:02", 0, hook_event_name="UserPromptSubmit", prompt="Actually, hold the rollout section.", source="user")
r.stream("11:02", 2, "m-roll", ["## Rollout\n", "\n", "Phase one ships saved cards to the iOS app behind the wallet sh…"])
r.write("status", {"mode": "chat", "tab": "PRD v2 edits", "interruptAfterPlay": True}, "tour-2.1.291/11-interrupted.txt")
print("wrote", out)
