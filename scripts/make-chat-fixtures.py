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

# ---- Review cards: screens in Claude Code 2.1.291's layout, from the spike's real ones ----
W = 100
HEAD = (spike / "60-edit-perm.txt").read_text().split("\n")[:4]
RULE = "─" * W


def wrap(prefix, text, indent):
    """Word-wraps a dialog line at the terminal's width, as the TUI does."""
    out, line = [], prefix
    for word in text.split(" "):
        if len(line) + len(word) + (0 if line.endswith(" ") or line == prefix else 1) > W - 1 and line.strip():
            out.append(line)
            line = " " * indent + word
        else:
            line = line + ("" if line == prefix or line.endswith(" ") else " ") + word
    out.append(line)
    return out


def screen(body):
    lines = HEAD + [""] + body
    return "\n".join(lines + [""] * max(0, 34 - len(lines))) + "\n"


def write_screen(board, text):
    (out / board / "screen.txt").write_text(text)


def options(opts, cursor=0, indent=1):
    rows = []
    for i, o in enumerate(opts):
        mark = "❯ " if i == cursor else "  "
        rows += wrap(" " * indent + mark + f"{i + 1}. ", o, indent + 5)
    return rows


PRD = CWD + "/docs/prd-v2.md"
PRD_TEXT = "\n".join(["# PRD v2: guest checkout"] + [""] * 29 + ["## Non-goals", "Saved cards for guests, for now.", "Accounts or sign-in at checkout."]) + "\n"
EDIT_OPTS = ["Yes", "Yes, and switch to accept edits (auto-approve file edits and common file commands) for this session (shift+tab)", "No"]

# permission-edit
r = Rec()
r.you("10:12", "Add the interview finding to the non-goals.")
r.tool("10:12", "toolu_p1", "Read", {"file_path": PRD}, {"type": "text", "file": {"content": PRD_TEXT, "numLines": 88, "totalLines": 88}})
edit = {"file_path": PRD, "old_string": "Saved cards for guests, for now.", "new_string": "Storing cards for guests in this release.\n(Interviews disagree: see Open questions.)"}
r.tool("10:12", "toolu_p2", "Edit", edit)
r.hook("10:12", 5, hook_event_name="PermissionRequest", tool_name="Edit", tool_input=edit)
r.write("permission-edit", {"mode": "chat", "tab": "PRD v2 edits", "files": {PRD: PRD_TEXT}}, None)
write_screen("permission-edit", screen(["❯ Add the interview finding to the non-goals.", "", "⏺ Update(docs/prd-v2.md)", "", RULE, " Edit file", " docs/prd-v2.md", "╌" * W,
                                        " 31  ## Non-goals", " 32 -Saved cards for guests, for now.", " 32 +Storing cards for guests in this release.", " 33 +(Interviews disagree: see Open questions.)", "╌" * W,
                                        " Do you want to make this edit to prd-v2.md?"] + options(EDIT_OPTS) + ["", " Esc to cancel · Tab to amend"]))

# permission-bash
r = Rec()
r.you("10:12", "Add the interview finding to the non-goals.")
r.tool("10:12", "toolu_b1", "Read", {"file_path": PRD}, {"type": "text", "file": {"content": PRD_TEXT, "numLines": 88, "totalLines": 88}})
r.tool("10:12", "toolu_b2", "Edit", edit, {"structuredPatch": [{"oldStart": 32, "newStart": 32, "lines": ["-Saved cards for guests, for now.", "+Storing cards for guests in this release.", "+(Interviews disagree: see Open questions.)"]}]})
r.say("10:13", "Edit made. Now I’ll check whether anything else in research mentions saved cards.")
bash = {"command": "rg -n -i \"saved card\" research/", "description": "Search the research notes for saved-card mentions"}
r.tool("10:13", "toolu_b3", "Bash", bash)
r.hook("10:13", 5, hook_event_name="PermissionRequest", tool_name="Bash", tool_input=bash)
r.write("permission-bash", {"mode": "chat", "tab": "PRD v2 edits", "toggled": ["toolu_b2"],
                            "answers": [{"at": iso("10:12", 30), "text": "You chose **1** · **Yes** for the edit to prd-v2.md"}]}, None)
write_screen("permission-bash", screen(["⏺ Bash(rg -n -i \"saved card\" research/)", "", RULE, " Bash command", "╌" * W, " rg -n -i \"saved card\" research/", " Search the research notes for saved-card mentions", "╌" * W,
                                        " Do you want to proceed?"] + options(["Yes", "Yes, and always allow access to /Users/geoff/work/payments/checkout-redesign/research from this project", "No"]) + ["", " Esc to cancel · Tab to amend"]))

# plan
PLAN_PATH = "/Users/pm/.claude/plans/saved-cards-for-guests.md"
PLAN = "## Saved cards for guests\n\n1. Move “Storing cards for guests” from **Non-goals** to **Requirements** in `docs/prd-v2.md`.\n2. Add a requirement: a guest can save a card *without* creating an account.\n3. Log the account question under **Open questions**, with P2 and P5 as evidence.\n4. Update the success metric: abandonment at the card form, target −15%.\n5. Add survey-q3’s 31% to **What we heard**.\n"
r = Rec()
r.t.append({"type": "user", "message": {"role": "user", "content": "Plan how we’d bring saved cards into scope. Don’t change anything yet."}, "timestamp": iso("10:30"), "origin": {"kind": "human"}, "permissionMode": "plan"})
r.tool("10:31", "toolu_l1", "Read", {"file_path": PRD}, {"type": "text", "file": {"content": "", "numLines": 88}})
r.say("10:31", "Here’s the plan.")
r.tool("10:31", "toolu_l2", "ExitPlanMode", {})
r.hook("10:31", 5, hook_event_name="PermissionRequest", tool_name="ExitPlanMode", tool_input={"plan": PLAN, "planFilePath": PLAN_PATH})
r.write("plan", {"mode": "chat", "tab": "PRD v2 edits", "drafts": {"plan": "Keep the survey number out of the PRD"}}, None)
plan_screen = (spike / "73-plan.txt").read_text()
write_screen("plan", plan_screen)

# AskUserQuestion: two questions, multi-select then single.
Q1 = {"header": "Platforms", "question": "Which platforms should saved cards ship on first? Pick every one we can staff before the exec review; the rest move to the next PRD.", "multiSelect": True,
      "options": [{"label": "iOS app", "description": "Native, behind the wallet sheet"}, {"label": "Android app", "description": "Native"}, {"label": "Web checkout", "description": "Browser, guest flow"}]}
Q2 = {"header": "Timing", "question": "When should this land?", "multiSelect": False,
      "options": [{"label": "This release", "description": "Ships with PRD v2"}, {"label": "Next quarter", "description": "After the pricing test"}]}


def ask_rec():
    r = Rec()
    r.you("10:40", "Draft the rollout section. Ask me anything you need first.")
    r.say("10:40", "Two questions before I write it.")
    r.hook("10:40", 5, hook_event_name="PermissionRequest", tool_name="AskUserQuestion", tool_input={"questions": [Q1, Q2]})
    return r


def qrows(q, ticks=None, other="Type something", cursor=0, nxt=None):
    rows = []
    multi = ticks is not None
    for i, o in enumerate(q["options"]):
        box = ("[✔] " if ticks[i] else "[ ] ") if multi else ""
        rows += [("❯ " if i == cursor else "  ") + f"{i + 1}. {box}{o['label']}", " " * (9 if multi else 5) + o["description"]]
    n = len(q["options"]) + 1
    rows.append(("❯ " if cursor == n - 1 else "  ") + f"{n}. " + ("[ ] " if multi else "") + other)
    if nxt:
        rows.append("     " + nxt)
    rows += [RULE, f"  {n + 1}. Chat about this", "Enter to select · Tab/Arrow keys to navigate · Esc to cancel"]
    return rows


r = ask_rec()
r.write("question-multi", {"mode": "chat", "tab": "PRD v2 edits"}, None)
write_screen("question-multi", screen(["❯ Draft the rollout section. Ask me anything you need first.", "", "⏺ Two questions before I write it.", "", RULE, "←  ☐ Platforms  ☐ Timing  ✔ Submit  →"]
                                       + wrap("", Q1["question"], 0) + qrows(Q1, ticks=[True, False, True], nxt="Next")))
r = ask_rec()
r.write("question-other", {"mode": "chat", "tab": "PRD v2 edits"}, None)
write_screen("question-other", screen(["❯ Draft the rollout section. Ask me anything you need first.", "", "⏺ Two questions before I write it.", "", RULE, "←  ☒ Platforms  ☐ Timing  ✔ Submit  →", Q2["question"]]
                                       + qrows(Q2, other="After the beta, if P5’s cohort agrees", cursor=2)))
r = ask_rec()
r.write("question-review", {"mode": "chat", "tab": "PRD v2 edits"}, None)
write_screen("question-review", screen(["❯ Draft the rollout section. Ask me anything you need first.", "", RULE, "←  ☒ Platforms  ☒ Timing  ✔ Submit  →", "Review your answers",
                                        " ● Which platforms should saved cards ship on first?", "   → iOS app, Web checkout", " ● When should this land?", "   → After the beta, if P5’s cohort agrees",
                                        "Ready to submit your answers?", "❯ 1. Submit answers", "  2. Cancel"]))

# previews
P = {"header": "Sign-in", "question": "Which sign-in layout should the guest checkout use?", "multiSelect": False, "options": [
    {"label": "Email first", "description": "Wallets below", "preview": "┌──────────────┐\n│ Email        │\n│ [__________] │\n│ [ Continue ] │\n│ ──── or ──── │\n│ [ Apple Pay ]│\n└──────────────┘"},
    {"label": "Wallets first", "description": "Email below", "preview": "┌──────────────┐\n│ [ Apple Pay ]│\n│ [ Google Pay]│\n│ ──── or ──── │\n│ Email        │\n│ [__________] │\n└──────────────┘"},
    {"label": "Phone code", "description": "No password", "preview": "┌──────────────┐\n│ Phone        │\n│ [__________] │\n│ We'll text a │\n│ code.        │\n│ [ Send code ]│\n└──────────────┘"}]}
r = Rec()
r.you("11:20", "Mock up the guest sign-in step.")
r.say("11:20", "Three layouts. Which one should I build out?")
r.hook("11:20", 5, hook_event_name="PermissionRequest", tool_name="AskUserQuestion", tool_input={"questions": [P]})
r.write("question-previews", {"mode": "chat", "tab": "PRD v2 edits", "drafts": {"notes": "Add a “forgot password” link"}}, None)
box = P["options"][1]["preview"].split("\n")
left = ["  1. Email first", "❯ 2. Wallets first ✔", "  3. Phone code"]
rows = []
for i in range(max(len(left), len(box))):
    l = left[i] if i < len(left) else ""
    rows.append(l.ljust(34) + (box[i] if i < len(box) else ""))
write_screen("question-previews", screen(["❯ Mock up the guest sign-in step.", "", RULE, " ☐ Sign-in ", P["question"]] + rows
                                         + [" " * 34 + "Notes: press n to add notes", RULE, "  Chat about this", "Enter to select · ↑/↓ to navigate · n to add notes · Esc to cancel"]))
print("wrote review boards")
