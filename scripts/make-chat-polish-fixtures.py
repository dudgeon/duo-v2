#!/usr/bin/env python3
"""Writes the chat-polish targets' recordings: docs/design/chat-polish-handoff/fixture-chat/polish-<board>/.

The boards' content (illustrative, as drawn) as Claude Code would record it, in the same format as
scripts/make-chat-fixtures.py: transcript lines, Duo's hook events, the TUI's screen and meta.json.
ChatTargets plays them as `--state chat-polish-<board>`; scripts/check-chat.sh compares them.

  python3 scripts/make-chat-polish-fixtures.py
"""
import json, pathlib, datetime

root = pathlib.Path(__file__).resolve().parent.parent
out = root / "docs/design/chat-polish-handoff/fixture-chat"
screens = root / "docs/design/chat-mode-handoff/fixture-chat"
CWD = "/Users/pm/work/payments/checkout-redesign"
DAY = datetime.datetime(2026, 10, 6, tzinfo=datetime.timezone.utc)


def ts(hm, s=0):
    h, m = map(int, hm.split(":"))
    return DAY + datetime.timedelta(hours=h, minutes=m, seconds=s)


def iso(hm, s=0):
    return ts(hm, s).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def epoch(hm, s=0):
    return ts(hm, s).timestamp()


class Rec:
    def __init__(self):
        self.t, self.e, self.n = [], [], 0

    def you(self, hm, text):
        self.t.append({"type": "user", "message": {"role": "user", "content": text}, "timestamp": iso(hm), "origin": {"kind": "human"}, "cwd": CWD})

    def say(self, hm, text):
        self.t.append({"type": "assistant", "message": {"model": "claude-opus-5-5", "content": [{"type": "text", "text": text}]}, "timestamp": iso(hm), "cwd": CWD})

    def think(self, hm, ms):
        self.t.append({"type": "assistant", "message": {"model": "claude-opus-5-5", "content": [{"type": "thinking", "thinking": ""}]}, "thinkingDurationMs": ms, "timestamp": iso(hm)})

    def tool(self, hm, id, name, inp, result=None, content="", error=False):
        self.t.append({"type": "assistant", "message": {"content": [{"type": "tool_use", "id": id, "name": name, "input": inp}]}, "timestamp": iso(hm)})
        if result is None and not error:
            return
        self.t.append({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": id, "content": content, "is_error": error}]},
                       "timestamp": iso(hm), "toolUseResult": result if result is not None else content})

    def bash(self, hm, id, cmd, what=None, out="", **kw):
        inp = {"command": cmd}
        if what:
            inp["description"] = what
        self.tool(hm, id, "Bash", inp, kw.pop("result", {"stdout": out, "stderr": "", "interrupted": False}), **kw)

    def read(self, hm, id, path, lines):
        self.tool(hm, id, "Read", {"file_path": CWD + "/" + path}, {"type": "text", "file": {"filePath": CWD + "/" + path, "content": "…", "numLines": lines, "totalLines": lines}})

    def edit(self, hm, id, path, old, new):
        self.tool(hm, id, "Edit", {"file_path": CWD + "/" + path, "old_string": old, "new_string": new}, {"filePath": CWD + "/" + path})

    def hook(self, hm, s, **e):
        self.e.append({"at": epoch(hm, s), "e": {"session_id": "fixture", "cwd": CWD, **e}})

    def write(self, board, meta, screen="tools"):
        d = out / ("polish-" + board)
        d.mkdir(parents=True, exist_ok=True)
        (d / "transcript.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in self.t))
        (d / "events.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in self.e))
        (d / "meta.json").write_text(json.dumps({"mode": "chat", "tab": "PRD v2 edits", **meta}, indent=1, ensure_ascii=False) + "\n")
        text = screen if "\n" in screen else (screens / screen / "screen.txt").read_text()
        (d / "screen.txt").write_text(text)


LINT = ["docs/prd-v2.md:41: non-goal repeats goal 2", "docs/prd-v2.md:58: link target flows.md#saved-cards not found"] + [f"docs/page-{i}.md: 0 problems" for i in range(38)]


def lint_turn(r, final, rerun):
    r.you("10:12", "Run the docs lint and fix what it finds in the PRD.")
    r.say("10:12", "I’ll run the lint first, then read what it flags.")
    r.bash("10:12", "toolu_c1", "npm run lint:docs", "Run the docs lint", "\n".join(LINT))
    r.bash("10:12", "toolu_c2", "ls docs/", "List the docs folder", "prd-v2.md\nrefunds/")
    r.bash("10:12", "toolu_c3", "rg -n \"flows\\.md#\" docs/ research/ --glob '!*.lock' | sort | head -40", "Find links to flows.md", "docs/prd-v2.md:58: flows.md#saved-cards")
    r.bash("10:12", "toolu_c4", "git log --oneline -5 -- docs/refunds/flows.md", None, "a41c2e9 Move saved-card section to refunds")
    r.read("10:12", "toolu_c5", "research/interviews.md", 214)
    r.read("10:12", "toolu_c6", "docs/prd-v2.md", 88)
    r.read("10:12", "toolu_c7", "docs/refunds/flows.md", 40)
    r.say("10:12", "Two problems, both in the non-goals: an item repeated from the goals, and a link to [flows.md](docs/refunds/flows.md) that points at a section that moved.")
    r.edit("10:13", "toolu_c8", "docs/prd-v2.md", "- Saved cards for guests, for now.", "- Storing cards for guests in this release.\n- (Interviews disagree: see Open questions.)")
    r.edit("10:13", "toolu_c9", "docs/refunds/flows.md", "See [saved cards](#saved-cards).\nOld anchor.", "See [saved cards](#refunds).\nNew anchor.\nRefunds moved.\nSee refunds.")
    if rerun:
        r.bash("10:13", "toolu_c10", "npm run lint:docs", "Run the docs lint again", "0 problems")
    r.say("10:13", final)
    r.hook("10:13", 30, hook_event_name="Stop", last_assistant_message=final)


# collapsed (C1): every run folded.
r = Rec()
lint_turn(r, "The lint is clean now. I cut the repeated non-goal and pointed the link at `flows.md#refunds`.", True)
r.write("collapsed", {})

# expanded (C2): the commands run opened, its first command opened.
r = Rec()
lint_turn(r, "The lint is clean now.", False)
r.write("expanded", {"openRuns": ["run-toolu_c1"], "toggled": ["toolu_c1"]})

# needs-you (C4): a folded run, then the step waiting on you; the review card docked below.
r = Rec()
r.you("10:30", "Check the research for anything else about saved cards.")
r.bash("10:30", "toolu_n1", "ls research/", "List the research folder", "interviews.md\nsurvey.md")
r.read("10:30", "toolu_n2", "research/survey.md", 120)
r.bash("10:30", "toolu_n3", "wc -l research/*.md", "Count the notes", "334 total")
cmd = 'rg -n -i "saved card" ~/work/payments/research/'
r.tool("10:30", "toolu_n4", "Bash", {"command": cmd, "description": "Search the shared research folder for saved-card mentions"})
r.hook("10:30", 5, hook_event_name="PermissionRequest", tool_name="Bash", tool_input={"command": cmd, "description": "Search the shared research folder for saved-card mentions"})
perm = (screens / "permission-bash" / "screen.txt").read_text()
perm = perm.replace('rg -n -i "saved card" research/', cmd).replace("Search the research notes for saved-card mentions", "Search the shared research folder for saved-card mentions")
perm = perm.replace("   2. Yes, and always allow access to /Users/geoff/work/payments/checkout-redesign/research from\n      this project", "   2. Yes, and always allow access to ~/work/payments/research from this project")
r.write("needs-you", {"states": {"PRD v2 edits": "needsYou"}}, perm)

# bar-thin (DL-136): the thin light strip over chat, a turn under it.
r = Rec()
r.you("10:12", "Run the docs lint and fix what it finds in the PRD.")
r.say("10:12", "I’ll run the lint first, then read what it flags.")
r.bash("10:12", "toolu_c1", "npm run lint:docs", "Run the docs lint", "\n".join(LINT))
r.bash("10:12", "toolu_c2", "ls docs/", "List the docs folder", "prd-v2.md")
r.bash("10:12", "toolu_c3", "rg -n flows docs/", "Find links to flows.md", "docs/prd-v2.md:58")
r.bash("10:12", "toolu_c4", "git log --oneline -5 -- docs/refunds/flows.md", None, "a41c2e9")
r.read("10:12", "toolu_c5", "research/interviews.md", 214)
r.read("10:12", "toolu_c6", "docs/prd-v2.md", 88)
r.read("10:12", "toolu_c7", "docs/refunds/flows.md", 40)
r.say("10:12", "Two problems, both in the non-goals: an item repeated from the goals, and a link to [flows.md](docs/refunds/flows.md) that points at a section that moved.")
r.hook("10:12", 30, hook_event_name="Stop", last_assistant_message="Two problems")
r.write("bar-thin", {})

# candidates (K1–K8), each its PROPOSED card.
r = Rec()
r.you("10:20", "Lint the docs and find when the flows section moved.")
r.bash("10:20", "toolu_o1", "cd ~/work/payments/checkout-redesign && npm run lint:docs -- --format=compact", "Run the docs lint", "\n".join(LINT))
r.bash("10:20", "toolu_o2", "git log --oneline -5 -- docs/refunds/flows.md", "Find when the section moved", "a41c2e9 Move saved-card section to refunds")
r.hook("10:20", 30, hook_event_name="Stop", last_assistant_message="")
r.write("output", {"openRuns": ["run-toolu_o1"]})

r = Rec()
r.you("10:22", "Fix both docs.")
r.tool("10:22", "toolu_e1", "Edit", {"file_path": CWD + "/docs/prd-v2.md", "old_string": "- Saved cards for guests, for now.", "new_string": "+ Storing cards for guests in this release."},
       {"structuredPatch": [{"oldStart": 31, "oldLines": 2, "newStart": 31, "newLines": 3, "lines": [" ## Non-goals", "-Saved cards for guests, for now.", "+Storing cards for guests in this release.", "+(Interviews disagree: see Open questions.)"]}]})
r.edit("10:22", "toolu_e2", "docs/refunds/flows.md", "See [saved cards](#saved-cards).\nOld anchor.", "See [saved cards](#refunds).\nNew anchor.\nRefunds moved.\nSee refunds.")
r.hook("10:22", 30, hook_event_name="Stop", last_assistant_message="")
r.write("edits", {"openRuns": ["run-toolu_e1"], "toggled": ["toolu_e1"]})

r = Rec()
r.you("10:24", "Lint the PRD.")
r.think("10:24", 4000)
r.bash("10:24", "toolu_h1", "npm run lint:docs", "Run the docs lint", "\n".join(LINT))
r.think("10:24", 2000)
r.read("10:24", "toolu_h2", "docs/prd-v2.md", 88)
r.think("10:24", 7000)
r.bash("10:24", "toolu_h3", "git log --oneline -5 -- docs/refunds/flows.md", None, "a41c2e9")
r.think("10:24", 3000)
r.say("10:24", "Two problems, both in the non-goals.")
r.hook("10:24", 30, hook_event_name="Stop", last_assistant_message="Two problems")
r.write("thinking", {"openRuns": ["run-toolu_h1"]})

r = Rec()
r.you("10:26", "Cross-check the survey, and start a competitor teardown.")
r.tool("10:26", "toolu_a1", "Task", {"description": "Survey cross-check", "prompt": "…"},
       {"content": [{"type": "text", "text": "31% of survey respondents mention saved cards."}], "totalDurationMs": 134000, "totalToolUseCount": 18, "status": "completed"})
r.tool("10:26", "toolu_a2", "Task", {"description": "Competitor teardown", "prompt": "…", "run_in_background": True}, {"isAsync": True, "status": "async_launched", "agentId": "a2", "totalDurationMs": 62000})
r.say("10:26", "The survey backs the interviews. I’ll fold the teardown in when it finishes.")
r.write("agents", {})

r = Rec()
r.you("10:28", "Work through the lint fixes.")
todos = [("Run the docs lint", "completed"), ("Cut the repeated non-goal", "completed"), ("Fix the flows.md link", "completed"), ("Re-run the lint", "in_progress"), ("Summarise the interview findings", "pending")]
r.tool("10:28", "toolu_d1", "TodoWrite", {"todos": [{"content": c, "status": "pending", "activeForm": c} for c, _ in todos]}, {"oldTodos": []})
r.bash("10:28", "toolu_d2", "npm run lint:docs", "Run the docs lint", "2 problems")
r.tool("10:28", "toolu_d3", "TodoWrite", {"todos": [{"content": c, "status": "completed" if i < 2 else "pending", "activeForm": c} for i, (c, _) in enumerate(todos)]}, {"oldTodos": []})
r.edit("10:28", "toolu_d4", "docs/prd-v2.md", "- Saved cards for guests, for now.", "- Storing cards for guests in this release.\n- (Interviews disagree.)")
r.tool("10:28", "toolu_d5", "TodoWrite", {"todos": [{"content": c, "status": s, "activeForm": c} for c, s in todos]}, {"oldTodos": []})
r.write("todos", {"toggled": ["todos-toolu_d5"]})

r = Rec()
r.you("10:32", "Check Stripe’s refund docs and tell the director.")
r.tool("10:32", "toolu_m1", "ToolSearch", {"query": "select:mcp__claude-in-chrome__tabs_context_mcp,mcp__claude-in-chrome__navigate", "max_results": 2}, {"matches": []})
r.tool("10:32", "toolu_m2", "mcp__claude-in-chrome__tabs_context_mcp", {}, {"tabs": []})
r.tool("10:32", "toolu_m3", "mcp__claude-in-chrome__navigate", {"url": "stripe.com/docs/refunds", "tabId": 1}, {"ok": True})
r.tool("10:32", "toolu_m4", "mcp__claude-in-chrome__computer", {"action": "screenshot", "tabId": 1}, {"ok": True})
r.tool("10:32", "toolu_m5", "mcp__claude-in-chrome__computer", {"action": "left_click", "tabId": 1}, {"ok": True})
r.tool("10:32", "toolu_m6", "mcp__claude-in-chrome__get_page_text", {"tabId": 1}, {"ok": True})
r.tool("10:32", "toolu_m7", "SendMessage", {"to": "DUO DIRECTOR", "message": "Refund limits checked.", "summary": "refunds"}, {"success": True})
r.hook("10:32", 30, hook_event_name="Stop", last_assistant_message="")
r.write("tools", {"openRuns": ["run-toolu_m1"]})

r = Rec()
r.you("10:34", "Lint, then search the research for saved cards.")
r.bash("10:34", "toolu_f1", "npm run lint:docs", "Run the docs lint", "0 problems")
r.bash("10:34", "toolu_f2", "ls docs/", "List the docs folder", "prd-v2.md")
r.bash("10:34", "toolu_f3", 'rg -n "saved card" research/old/', "Search old research", content="Exit code 2\nrg: research/old/: No such file or directory (os error 2)", error=True, result=None)
r.bash("10:34", "toolu_f4", 'rg -n "saved card" research/', "Search research", "research/interviews.md:12: saved card")
r.say("10:34", "The edit is in. One search failed because `research/old/` doesn’t exist; nothing else needed it.")
r.hook("10:34", 30, hook_event_name="Stop", last_assistant_message="The edit is in.")
r.write("failed", {"openRuns": ["run-toolu_f1"]})

r = Rec()
notes = ["Here are the notes from this morning’s review. Fold the decisions into the PRD and list anything still open:",
         "1. Guest checkout keeps the card form on one page.", "2. Saved cards need an account; no guest vault in v1.",
         "3. Apple Pay ships with the redesign, Google Pay after.", "4. Address autocomplete stays behind the flag until the vendor contract is signed.",
         "5. Error copy goes to content design by Friday.", "6. Refund flows are out of scope; see flows.md for what changes there."]
notes += [f"{i}. Follow-up item {i}." for i in range(7, 64)]
r.you("11:02", "\n".join(notes))
r.write("paste", {})
print("wrote", out)
