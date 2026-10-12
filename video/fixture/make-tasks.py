#!/usr/bin/env python3
"""S10 (Tasks): shelf-scan's task notes in Duo's own format (DL-6, DL-93, DL-146: Templates.baseTask, sessions as
`[title](duo2://session/<id>)` links), from world.json's `tasks`; the new task as File › New Task makes it, after Sam's
lines, and after New Session in Task; and two chat recordings: that session's first exchange, and the Deck for
Thursday session's history. Writes docs/tasks/*.md, s10/*.md, chat-s10-task/, chat-s10-deck/. Plain python3."""
import importlib.util, json, pathlib, re

_spec = importlib.util.spec_from_file_location("make_research", pathlib.Path(__file__).resolve().parent / "make-research.py")
R = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(R)   # its Log and helpers; its main() doesn't run

HERE = pathlib.Path(__file__).resolve().parent
W = json.loads((HERE / "world.json").read_text())
T = W["tasks"]
SID = {s["name"]: s["sessionId"] for s in W["sessions"] + W["tasks"]["sessions"]}   # the S10-only sessions too
PROJ = "/Users/sam/work/little-shared-library/shelf-scan"
DOCS = HERE / "docs"


def slug(title):   # TaskNotes.slug
    s = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
    return s[:60].strip("-") or "task"


def scalar(v):     # plain YAML when it can be, else double-quoted (Templates.render)
    return v if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9 ,.'()/-]*", v) and not re.search(r": | #", v) else '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'


def link(title, sid):   # TaskNotes.link, as a YAML list item
    t = title.replace("[", "\\[").replace("]", "\\]")
    return '"' + f"[{t}](duo2://session/{sid})".replace('"', '\\"') + '"'


def note(title, status="open", owner=None, waiting_on=None, due=None, sessions=(), created=None, completed=None,
         goal=None, done=(), notes=""):
    fm = ["---", "type: task", f"title: {scalar(title)}", f"status: {status}"]
    if owner: fm.append(f"owner: {owner}")
    if waiting_on: fm.append(f"waiting_on: {waiting_on}")
    if due: fm.append(f"due: {due}")
    fm += ["sessions:"] + [f"  - {link(n, i)}" for n, i in sessions] if sessions else ["sessions: []"]
    fm.append(f"created: {created}")
    if completed: fm.append(f"completed: {completed}")
    fm.append("---")
    body = ["", f"# {title}", ""]
    if goal: body += [goal, ""]
    body += ["## Done when", ""] + ([f"- [{'x' if status == 'done' else ' '}] {d}" for d in done] or ["- [ ] "]) + ["", "## Notes", ""]
    if notes: body += [notes, ""]
    return "\n".join(fm + body)


def main():
    tdir = DOCS / "tasks"; tdir.mkdir(exist_ok=True)
    for t in T["notes"]:
        (tdir / f"{slug(t['title'])}.md").write_text(note(t["title"], t["status"], t.get("owner"), t.get("waiting_on"), t.get("due"),
            [(n, SID[n]) for n in t["sessions"]], t["created"], t.get("completed"), t["goal"], t["done"]))
    n = T["new"]; s10 = HERE / "s10"; s10.mkdir(exist_ok=True)
    name = slug(n["title"])
    feedback = f"[Denise's feedback]({'../' + n['feedback']})"
    # File › New Task, named: Templates.baseTask as rendered (an empty Done when box, an empty Notes).
    (s10 / f"{name}.created.md").write_text(note(n["title"], created=n["created"]))
    # Sam's lines: the goal under the heading, two Done when boxes, Denise's feedback under Notes.
    (s10 / f"{name}.details.md").write_text(note(n["title"], created=n["created"], goal="Goal: " + n["goal"][0].lower() + n["goal"][1:], done=n["done"], notes=feedback))
    # New Session in Task: Duo adds the session's link to `sessions:` (TaskNotes.adding); nothing else changes.
    ns = n["session"]
    (s10 / f"{name}.linked.md").write_text(note(n["title"], sessions=[(ns["title"], ns["sessionId"])], created=n["created"],
                                                goal="Goal: " + n["goal"][0].lower() + n["goal"][1:], done=n["done"], notes=feedback))
    write_chats(name, n)
    print("wrote", len(T["notes"]), "notes,", name, "and chat-s10-task, chat-s10-deck")


def write_chats(name, n):
    ns = n["session"]
    # New Session in Task: Duo types `@tasks/<note>.md ` into the new session's prompt (DL-112); Sam adds his words.
    L = R.Log(PROJ, sid=ns["sessionId"], day="2026-10-13")
    L.user(f"@tasks/{name}.md {ns['ask']}", "10:05:12")
    den, prd = f"{PROJ}/{n['feedback']}", f"{PROJ}/docs/prd-v2.md"
    R.read(L, "toolu_g1", den, R.DENISE, "10:05:18")
    R.read(L, "toolu_g2", prd, (HERE / "s7" / "prd-v2.after.md").read_text(), "10:05:19")
    L.text("For the camera view, aimed at the task's goal (no glare misreads at glass-door boxes):\n\n"
           "**Sun on the glass?** Open the door for a clearer photo.\n\n"
           "It's Denise's own fix, and short enough to read before the shutter.", "10:05:31")
    d = HERE / "chat-s10-task"; d.mkdir(exist_ok=True)
    (d / "meta.json").write_text(json.dumps({"mode": "chat", "tab": ns["title"]}, indent=1))
    L.dump(d / "transcript.jsonl", title=ns["title"])
    # Deck for Thursday: the session's history, ready for review (S10 resumes it from the board).
    L = R.Log(PROJ, sid=SID["Deck for Thursday"], day="2026-10-13")
    L.user("Make the deck for Thursday's review from the PRD, Ravi's eval and the interview synthesis. Six slides, our template.", "08:48:10")
    R.read(L, "toolu_d1", prd, R.PRD, "08:48:16")
    R.read(L, "toolu_d2", f"{PROJ}/eval/spine-eval-2026-09-28.md", R.EVAL_MD, "08:48:17")
    cmd = "uv run --with python-pptx python3 scripts/deck.py docs/team-review-oct15.pptx"
    out = "Wrote docs/team-review-oct15.pptx: 6 slides, 1 chart"
    L.use("toolu_d3", "Bash", {"command": cmd, "description": "Build the deck in the team template"}, "08:51:40")
    L.result("toolu_d3", out, {"stdout": out, "stderr": "", "interrupted": False, "isImage": False, "noOutputExpected": False}, "08:51:44")
    L.text("team-review-oct15.pptx is ready: the title, where scans go wrong (the eval chart), what testers said, "
           "the proposal, targets, and the decision for Thursday. Have a look before it goes to Jo.", "08:52:02")
    d = HERE / "chat-s10-deck"; d.mkdir(exist_ok=True)
    (d / "meta.json").write_text(json.dumps({"mode": "chat", "tab": "Deck for Thursday"}, indent=1))
    L.dump(d / "transcript.jsonl", title="Deck for Thursday")


if __name__ == "__main__":
    main()
