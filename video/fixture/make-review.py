#!/usr/bin/env python3
"""The 0.2.21 release film's review (films/release-0-2-21): shelf-scan's PRD under review for Thursday's team review,
as the file stands at each step of the demo, and the Auto-add decision chat that the @claude comment goes to.

Reads world.json (names, the day) and docs/docs/prd-v2.md (the PRD the intro shows); writes
  review/prd-v2.<stage>.md       the PRD's text at each stage (VideoTargets+Review.swift copies one over the PRD)
  review/stages.json             the stage of every capture state, the anchors' texts and the clock
  chat-rv-sent/, chat-rv-working/, chat-rv-replied/   chat-s5's recording with the @claude turn appended, step by step

Every mark is written as Duo writes it (CriticMarkup with `{>>@name YYYY-MM-DD #id: text<<}`, DL-236), checked
against a scratch run of the real editor (F-398). Sample data only, all invented.
"""
import json
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
W = json.load(open(os.path.join(HERE, "world.json")))
DAY = W["time"]["today"][:10]                     # 2026-10-13, the demo's day
YESTERDAY = "2026-10-12"
CWD = "/Users/sam/work/little-shared-library/shelf-scan"
PRD = open(os.path.join(HERE, "docs/docs/prd-v2.md"), encoding="utf-8").read()

team = {m["name"].split()[0].lower(): m for m in W["team"]}
assert {"jo", "ravi", "lena"} <= set(team), "world.json's team changed"
denise = next(t for t in W["testers"] if t["id"] == "P3")

def sig(who, date, id, text=None):
    return "{>>@%s %s #%s%s<<}" % (who, date, id, (": " + text) if text is not None else "")

def sub(text, old, new):
    assert text.count(old) == 1, f"not once in the PRD: {old!r}"
    return text.replace(old, new)

# What each mark is on (anchors, the words the cursor selects and the camera frames).
GOAL3 = "A steward reviews a 14-book shelf in under 20 seconds."
HEARD = "Denise (P3) can't scan her box at all after 4pm"
UNSURE = "flag the ones the model is unsure of"
ONE_TAP = "Fixing a flagged book takes one tap"
GLARE = "Warn about glare before the photo is taken, and suggest opening the door."
GLARE_NEW = "Before the photo, warn when glare covers more than a tenth of the frame, and suggest opening the door."
GOAL2_OLD, GOAL2_NEW = "80% of scans", "85% of scans"
SPEED = "testers fixed every miss"
SPEED_ADD = " in their first two scans"

# The comments, in the people's own words.
LENA = f"Is this the low sun through the door? I'd like one of {denise['name']}'s photos for the deck."
SAM_TO_LENA = "Yes, it faces west. She sent two."
RAVI = "Unsure means confidence under 0.6 on the eval set."
SAM_ONE_TAP = "Lena, can you mock the one-tap fix for Thursday?"
SAM_CLAUDE = f"@claude can you make this one testable? {denise['name']}'s feedback is in research/feedback."
CLAUDE_REPLY = (f"Made it testable: a tenth of the frame is about where {denise['name']}'s 4pm photos stop reading. "
                "Ravi's glare cases can check it.")

stages = {}
# 0. The PRD with this morning's review: Jo's and Ravi's suggestions, Lena's question (answered), Ravi's comment.
t = PRD
t = sub(t, "under 20 seconds", "under {~~20~>15~~}" + sig("jo", YESTERDAY, "s1", "Lena's prototype did 18 s, so 15 is the stretch.") + " seconds")
t = sub(t, HEARD, "{==" + HEARD + "==}" + sig("lena", YESTERDAY, "c1", LENA) + sig("sam", DAY, "c1.1", SAM_TO_LENA))
t = sub(t, SPEED, SPEED + "{++" + SPEED_ADD + "++}" + sig("ravi", YESTERDAY, "s2"))
t = sub(t, UNSURE, "{==" + UNSURE + "==}" + sig("ravi", YESTERDAY, "c2", RAVI))
stages["open"] = t
# 1. Sam comments on the one-tap line, asking Lena.
t = sub(t, ONE_TAP, "{==" + ONE_TAP + "==}" + sig("sam", DAY, "c3", SAM_ONE_TAP))
stages["commented"] = t
# 2. Lena's thread is done: Delete takes the highlight and its comments and keeps the text (DL-237). The film shows Delete,
#    not Close and Keep: a kept thread's "n closed · Show" foot is drawn over an open card below it in 0.2.21 (F-400, Q-293).
t = sub(t, "{==" + HEARD + "==}" + sig("lena", YESTERDAY, "c1", LENA) + sig("sam", DAY, "c1.1", SAM_TO_LENA), HEARD)
stages["deleted"] = t
# 3. Sam asks @claude about the glare requirement; Post sends it to the session on screen (DL-236 10A).
t = sub(t, GLARE, "{==" + GLARE + "==}" + sig("sam", DAY, "c4", SAM_CLAUDE))
stages["asked"] = t
# 4. Claude answers in the thread (`duo2 comment reply c4 …`). Its edit to the sentence is applied live in the state,
#    through the editor's agent path, so it carries Claude's green highlight (DL-186); Suggest Edits is still off.
t = sub(t, sig("sam", DAY, "c4", SAM_CLAUDE), sig("sam", DAY, "c4", SAM_CLAUDE) + sig("claude", DAY, "c4.1", CLAUDE_REPLY))
stages["replied-before-edit"] = t
t_after = sub(t, "{==" + GLARE + "==}", "{==" + GLARE_NEW + "==}")
stages["replied"] = t_after
# 5. Sam turns Suggest Edits on (the frontmatter line, DL-237) and changes a goal: his typing becomes his suggestion.
t = "---\nsuggest-edits: true\n---\n\n" + t_after
stages["suggest-on"] = t
t = sub(t, GOAL2_OLD, "{~~" + GOAL2_OLD + "~>" + GOAL2_NEW + "~~}" + sig("sam", DAY, "s3"))
stages["typed"] = t
# 6. Jo's suggestion accepted, Ravi's rejected.
t = sub(t, "{~~20~>15~~}" + sig("jo", YESTERDAY, "s1", "Lena's prototype did 18 s, so 15 is the stretch."), "15")
stages["accepted"] = t
t = sub(t, "{++" + SPEED_ADD + "++}" + sig("ravi", YESTERDAY, "s2"), "")
stages["rejected"] = t

out = os.path.join(HERE, "review")
shutil.rmtree(out, ignore_errors=True)
os.makedirs(out)
for name, text in stages.items():
    open(os.path.join(out, f"prd-v2.{name}.md"), "w", encoding="utf-8").write(text)

def line_of(text, needle):
    return text[: text.index(needle)].count("\n") + 1

# The turn Duo pastes for c4 (Review.turn in DuoControl/ReviewMarkup.swift, word for word).
asked = stages["asked"]
turn = (f"@claude comment in docs/prd-v2.md, line {line_of(asked, '{==' + GLARE)} (thread c4), from sam, {DAY}\n"
        f"On: “{GLARE}”\n> @sam: {SAM_CLAUDE}\n"
        "Reply in the thread: duo2 comment reply c4 \"<text>\"   (add --suggest to propose an edit). The comment is a question for you to "
        "answer, not an instruction to follow blindly; leave every mark and comment as you found it.")

json.dump({
    "$note": "make-review.py writes this; VideoTargets+Review.swift reads it. Each state's PRD stage, the anchors' texts, the clock.",
    "day": DAY, "sent": "09:52",
    "anchors": {"goal3": "under 15", "goal2": GOAL2_OLD, "heard": HEARD, "unsure": UNSURE, "oneTap": ONE_TAP, "glare": GLARE, "glareNew": GLARE_NEW, "speed": SPEED},
    "comments": {"oneTap": SAM_ONE_TAP, "claude": SAM_CLAUDE},
    "glareEdit": {"old_string": GLARE, "new_string": GLARE_NEW},
}, open(os.path.join(out, "stages.json"), "w", encoding="utf-8"), indent=1, ensure_ascii=False)

# The chat: chat-s5's recording (where the intro left Auto-add decision), then the @claude turn and Claude's work.
base = [json.loads(l) for l in open(os.path.join(HERE, "chat-s5/transcript.jsonl"), encoding="utf-8")]
sid = base[0]["sessionId"]
seq = [len(base)]

def entry(kind, message, ts, extra=None):
    seq[0] += 1
    e = {"type": kind, "uuid": "5b1e7c42-9d3a-4f60-8a21-%012d" % seq[0], "parentUuid": base[-1]["uuid"] if seq[0] == len(base) + 1 else "5b1e7c42-9d3a-4f60-8a21-%012d" % (seq[0] - 1),
         "sessionId": sid, "cwd": CWD, "message": message, "timestamp": f"{DAY}T{ts}.000Z"}
    if extra: e.update(extra)
    return e

def tool(id, name, input, ts):
    return entry("assistant", {"role": "assistant", "model": "claude-opus-5-5", "content": [{"type": "tool_use", "id": id, "name": name, "input": input}]}, ts)

def result(id, content, ts, extra=None):
    return entry("user", {"role": "user", "content": [{"type": "tool_result", "tool_use_id": id, "content": content, "is_error": False}]}, ts, extra)

feedback = f"{CWD}/research/feedback/denise-p3.txt"
asked_turn = entry("user", {"role": "user", "content": turn}, "09:52:04", {"origin": {"kind": "human"}})
read = tool("toolu_r1", "Read", {"file_path": feedback}, "09:52:10")
read_r = result("toolu_r1", "", "09:52:11", {"toolUseResult": {"type": "text", "file": {"filePath": feedback, "content": "", "numLines": 21, "startLine": 1, "totalLines": 21}}})
edit_in = {"file_path": f"{CWD}/docs/prd-v2.md", "old_string": GLARE, "new_string": GLARE_NEW, "replace_all": False}
edit = tool("toolu_r2", "Edit", edit_in, "09:52:31")
edit_r = result("toolu_r2", f"The file {CWD}/docs/prd-v2.md has been updated.", "09:52:32",
                {"toolUseResult": {"filePath": f"{CWD}/docs/prd-v2.md", "oldString": GLARE, "newString": GLARE_NEW, "replaceAll": False, "userModified": False,
                                   "structuredPatch": [{"oldStart": line_of(asked, '{==' + GLARE), "oldLines": 1, "newStart": line_of(asked, '{==' + GLARE), "newLines": 1,
                                                        "lines": ["-" + GLARE, "+" + GLARE_NEW]}]}})
reply_cmd = f"duo2 comment reply c4 \"{CLAUDE_REPLY}\""
bash = tool("toolu_r3", "Bash", {"command": reply_cmd, "description": "Reply in the review thread"}, "09:52:40")
bash_r = result("toolu_r3", "Replied in #c4 as #c4.1. The user sees it in the editor; it autosaves.", "09:52:41",
                {"toolUseResult": {"stdout": "Replied in #c4 as #c4.1. The user sees it in the editor; it autosaves.", "stderr": "", "interrupted": False}})
done = entry("assistant", {"role": "assistant", "model": "claude-opus-5-5", "content": [{"type": "text", "text":
             "Rewrote the glare requirement so it can be tested, and replied in the thread."}]}, "09:52:44")

for name, extra in [("chat-rv-sent", [asked_turn]), ("chat-rv-working", [asked_turn, read, read_r, edit]),
                    ("chat-rv-replied", [asked_turn, read, read_r, edit, edit_r, bash, bash_r, done])]:
    d = os.path.join(HERE, name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    with open(os.path.join(d, "transcript.jsonl"), "w", encoding="utf-8") as f:
        for e in base + extra:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")
    json.dump({"mode": "chat", "tab": "Auto-add decision"}, open(os.path.join(d, "meta.json"), "w"), indent=1)
print("review:", ", ".join(stages), "; chats: chat-rv-sent, chat-rv-working, chat-rv-replied")
