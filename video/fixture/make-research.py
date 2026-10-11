#!/usr/bin/env python3
"""Writes the demo world's research fixtures (sample data only, all invented; see SCENARIO.md and world.json):
docs/eval/results.csv, score.py, spine-eval-2026-09-28.md, research/feedback/denise-p3.txt,
chat-s2/{meta.json,transcript.jsonl} and sessions/auto-add-decision.jsonl. Run with plain python3."""
import csv, json, pathlib, random, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
W = json.loads((HERE / "world.json").read_text())
N = W["numbers"]
EV = N["eval"]
PROJ = "/Users/sam/work/little-shared-library/shelf-scan"
DOCS = HERE / "docs"
PRD = (DOCS / "docs" / "prd-v2.md").read_text()

# ---------------------------------------------------------------- 1. results.csv
TITLES = W["books"]["classics"] + W["books"]["invented"]
MISREADS = {
    "Middlemarch": ["Midd1emarch", "Middlemarsh", "Mlddlemarch"],
    "Moby-Dick": ["Mobv-Dick", "Moby-Dlck", "Mohy-Dick"],
    "Little Women": ["Llttle Women", "Little Wornen", "Littie Women"],
    "The Secret Garden": ["The Secret Garclen", "The Secret Gardon", "Tne Secret Garden"],
    "Persuasion": ["Pervasion", "Persuaslon", "Persnasion"],
    "Bleak House": ["Bleak Hause", "Bleah House", "Bleak Horse"],
    "Jane Eyre": ["Jane Eyrc", "Jane Eyne", "Jame Eyre"],
    "Great Expectations": ["Great Expectatlons", "Great Expedations", "Great Exneclations"],
    "The Wind in the Willows": ["The Wind in the Willow", "The Wind in the Wiliows", "The Wlnd in the Willows"],
    "Treasure Island": ["Treasure Isiand", "Treasure Istand", "Treasur Island"],
    "Emma": ["Erma", "Ernma", "Emrna"],
    "Silas Marner": ["Silas Mamer", "Sllas Marner", "Silas Marnen"],
    "The Lantern Keeper": ["The Lantern Keepet", "The Lantern Kecper", "The Lantem Keeper"],
    "Salt Roads": ["Sait Roads", "Salt Roacls", "Sal Roads"],
    "A Field Guide to Small Birds": ["A Field Guide to Small Bircls", "A Field Guide to Smal Birds", "A Fleld Guide to Small Birds"],
    "Winter at Halloway": ["Winter at Hallowav", "Wlnter at Halloway", "Winter at Hailoway"],
    "The Quiet Orchard": ["The Quiet Orchand", "The Qulet Orchard", "The Quiet Orcharcl"],
    "Ninety Bridges": ["Ninety Brides", "Ninety Bridoes", "Ninety Brldges"],
}
GLARE_SHELVES = ["elm-park-03", "elm-park-11", "elm-park-19", "northgate-05", "northgate-14",
                 "northgate-22", "riverside-02", "riverside-09", "riverside-17"]
LINDEN = "northgate-14"


def make_results():
    rng = random.Random(20260928)
    shelves = [f"{h}-{n:02d}" for h in ("elm-park", "northgate", "riverside") for n in range(1, 33)]
    assert len(shelves) == EV["shelves"]
    size = {}
    for i, s in enumerate(GLARE_SHELVES):
        size[s] = 16 if i < 5 else 15
    others = [s for s in shelves if s not in GLARE_SHELVES]
    for i, s in enumerate(others):
        size[s] = 13 if i < 56 else 12
    assert sum(size.values()) == EV["photos"] and sum(size[s] for s in GLARE_SHELVES) == EV["glareSubset"]["photos"]
    slots = [(s, k) for s in shelves for k in range(size[s])]
    cause_of = {}
    glare_slots = [x for x in slots if x[0] in GLARE_SHELVES]
    for x in rng.sample(glare_slots, EV["causes"][1]["wrong"]):
        cause_of[x] = "glare"
    rest = [c["cause"] for c in EV["causes"] if c["cause"] != "glare" for _ in range(c["wrong"])]
    rng.shuffle(rest)
    for x, c in zip(rng.sample([x for x in slots if x[0] not in GLARE_SHELVES], len(rest)), rest):
        cause_of[x] = c
    rows, nbox = [], {"elm-park": "ep", "northgate": "ng", "riverside": "rs"}
    forced_p = forced_n = False
    for i, (s, k) in enumerate(slots, 1):
        hood, num = s.rsplit("-", 1)
        box = "linden-st" if s == LINDEN else f"{nbox[hood]}-{(int(num) + 1) // 2:02d}"
        truth = rng.choice(TITLES)
        cause = cause_of.get((s, k), "")
        if cause == "glare" and s == LINDEN and not forced_p:
            truth, forced_p = "Persuasion", True
            read = "Pervasion"
        elif cause == "thin" and not forced_n:
            truth, forced_n = "Ninety Bridges", True
            read = "Ninety Brides"
        elif cause:
            read = rng.choice(MISREADS[truth])
        else:
            read = truth
        conf = round(rng.uniform(0.35, 0.86), 2) if cause else round(min(0.99, rng.triangular(0.78, 0.99, 0.97)), 2)
        rows.append([f"lsl-{i:04d}", s, box, truth, read, 0 if cause else 1, cause, f"{conf:.2f}"])
    return rows


def write_results():
    rows = make_results()
    assert len(rows) == 1240 and sum(r[5] for r in rows) == EV["correct"]
    for c in EV["causes"]:
        assert sum(1 for r in rows if r[6] == c["cause"]) == c["wrong"]
    with open(DOCS / "eval" / "results.csv", "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["photo_id", "shelf_id", "box", "truth", "read", "correct", "cause", "confidence"])
        w.writerows(rows)


# ---------------------------------------------------------------- 2. score.py
SCORE_PY = '''#!/usr/bin/env python3
"""Score eval/results.csv: accuracy, and the miss table by cause.

    python3 eval/score.py                 # all 1,240 photos
    python3 eval/score.py --cause glare   # only shelves that had at least one glare miss
"""
import argparse
import collections
import csv
import pathlib

ORDER = ["tilted", "glare", "thin", "stacked", "other"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", default=str(pathlib.Path(__file__).with_name("results.csv")))
    ap.add_argument("--cause", help="restrict to shelves with at least one miss of this cause")
    a = ap.parse_args()
    rows = list(csv.DictReader(open(a.csv, newline="")))
    if a.cause:
        # TODO(ravi): glass-door shelves should be a column, not inferred from the misses
        keep = {r["shelf_id"] for r in rows if r["cause"] == a.cause}
        rows = [r for r in rows if r["shelf_id"] in keep]
        print(f"subset: shelves with {a.cause} misses")
    shelves = {r["shelf_id"] for r in rows}
    right = sum(1 for r in rows if r["correct"] == "1")
    wrong = [r for r in rows if r["correct"] == "0"]
    print(f"{len(rows):,} photos, {len(shelves)} shelves")
    print(f"accuracy: {100 * right / len(rows):.1f}% ({right:,} / {len(rows):,})")
    print()
    print(f"misses: {len(wrong)}")
    by = collections.Counter(r["cause"] or "unlabelled" for r in wrong)
    print(f"{'cause':<10}{'count':>6}{'share':>8}")
    for c in sorted(by, key=lambda c: (ORDER.index(c) if c in ORDER else 99)):
        print(f"{c:<10}{by[c]:>6}{100 * by[c] / len(wrong):>7.0f}%")
    # TODO(ravi): per-neighbourhood breakdown; Elm Park looks better than Riverside


if __name__ == "__main__":
    main()
'''

# ---------------------------------------------------------------- 3. eval notes
EVAL_MD = """# Spine eval, 2026-09-28

Ravi Menon. Model: spine-reader v1 (the one in the beta since Aug 24). Scrappy notes, not a report.

## Method

- 1,240 spine photos from 96 shelves (32 each in Elm Park, Northgate, Riverside). Photos came from the beta uploads, 12 to 16 per shelf.
- Labelled by hand: Tomás and I typed the title for each photo, blind to what the model said. Anything we couldn't read ourselves got dropped, so the set is slightly kind to the model.
- A read counts as correct only if the string matches the truth title exactly (case-insensitive). "Midd1emarch" is a miss even though a human would shrug. That is deliberate: the catalog match downstream is strict too.
- Each miss got one cause label from looking at the photo. One cause per photo, so shares add up. Borderline calls (tilted *and* thin) went to whichever looked worse.
- Scored with `eval/score.py` on `eval/results.csv`.

## Results

| | |
| --- | --- |
| Photos | 1,240 |
| Read correctly | 1,004 (81.0%) |
| Wrong | 236 |

Where the 236 misses come from:

| Cause | Misses | Share |
| --- | --- | --- |
| Tilted or leaning spines | 80 | 34% |
| Glare (glass or plastic doors) | 64 | 27% |
| Thin spines (under 1 cm) | 50 | 21% |
| Stacked or sideways books | 28 | 12% |
| Other (non-Latin titles, worn print) | 14 | 6% |

Confidence is not much help: wrong reads are spread from 0.35 to 0.86, and a few sit above 0.8. At the v1 auto-add setting that is how a wrong book gets in.

## Confusion examples

- *Persuasion* read as **Pervasion** (glare, Linden Street box). The catalog then matched "Pervasion" to *Pervasive Games: A Handbook*. This is the one Denise hit.
- *Ninety Bridges* read as **Ninety Brides** (thin spine). Two letters lost at the edge of the crop.
- *Middlemarch* read as **Midd1emarch** (worn print, the "l" looks like a 1).
- *Moby-Dick* read as **Mobv-Dick** (tilted).
- *Emma* read as **Erma** (short title, glare).

## Caveats

- The glare set is only 140 photos from 9 shelves, all glass or plastic doors. Needs more. Anything we say about glare is soft until we have more doors.
- Only 9 of 96 shelves have doors at all, but stewards of door boxes are the loudest in the interviews, so the beta mix may differ from this one.
- Labels are two people. No second pass for disagreement yet.
- The set is photos people chose to upload. Probably cleaner than what the camera sees in the field.

## Rerun

Reran on Oct 1 after fixing the crop-scale bug (it was off on a handful of shelves). Same 1,004 of 1,240, same table. Nothing to update.

## TODO

- [ ] Add 300+ photos from glass-door boxes, a few different times of day (glare moves).
- [ ] Add a `glass_door` column to `results.csv`, so `score.py --cause glare` stops guessing from the misses.
- [ ] Second labeller on the 236 misses.
- [ ] Per-neighbourhood numbers. Eyeballing says Riverside is worse.
- [ ] Try the polarising-filter trick Lena suggested for the door boxes. Probably a no for a phone app.

@Sam: the auto-add threshold is 95%. The v1 model is at 81%, so on these numbers auto-add shouldn't be on for anyone yet. If the review step gets users' fixed shelves to 97%, that is a different conversation. Your call for the PRD.
"""

# ---------------------------------------------------------------- 7. Denise's email
DENISE = """Hi Sam,

Thanks for asking, here's everything in one go because I've been meaning to write it down.

I look after the Linden Street box, the one with the glass door (Gerald says it's the fanciest in the beta, I say it just has a good lock). I usually scan around 4pm when I do my rounds, and that's exactly when the sun comes round the corner and hits the glass. The app just gives up. It takes the photo, then half the spines come out as nonsense and I can't tell until later.

Last week it added "Pervasive Games: A Handbook" to my shelf. The book was Persuasion! I know because I put it there myself. I didn't notice until Mrs. Abernathy from number 14 walked all the way over for it, in the drizzle, and she was very nice about it but I felt dreadful.

Honestly I stopped scanning for a few days after that. It isn't that I mind the app being wrong sometimes, glass is glass. It's that it put the wrong book in without asking me.

If the app asked me first, "is this Persuasion?", I would happily check each book. I'd rather tap ten times than have Mrs. Abernathy come over for nothing. I think a lot of stewards would say the same.

Also, small thing, it would be lovely if it warned me about the glare before I took the photo. I'd just open the door.

I attached a screenshot of the wrong match so you can see it.

Thanks for listening, and good luck with the next version!

Denise (Linden St box)
"""

# ---------------------------------------------------------------- transcripts
class Log:
    def __init__(self, cwd, sid=None, day="2026-10-13", ids=True):
        self.cwd, self.sid, self.day, self.ids = cwd, sid, day, ids
        self.lines, self.parent, self.n = [], None, 0

    def _add(self, d, t):
        d["timestamp"] = f"{self.day}T{t}.000Z" if len(t) == 8 else t
        if self.ids:
            self.n += 1
            u = f"{self.sid[:24]}{self.n:012x}"
            d = {"type": d["type"], "uuid": u, "parentUuid": self.parent, "sessionId": self.sid, "cwd": self.cwd, **{k: v for k, v in d.items() if k != "type"}}
            self.parent = u
        else:
            d["cwd"] = self.cwd
        self.lines.append(d)

    def user(self, text, t):
        self._add({"type": "user", "message": {"role": "user", "content": text}, "origin": {"kind": "human"}}, t)

    def text(self, text, t):
        self._add({"type": "assistant", "message": {"role": "assistant", "model": "claude-opus-5-5", "content": [{"type": "text", "text": text}]}}, t)

    def use(self, tid, name, inp, t):
        self._add({"type": "assistant", "message": {"role": "assistant", "model": "claude-opus-5-5", "content": [{"type": "tool_use", "id": tid, "name": name, "input": inp}]}}, t)

    def result(self, tid, content, tur, t):
        self._add({"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": tid, "content": content, "is_error": False}]}, "toolUseResult": tur}, t)

    def dump(self, path, title=None):
        lines = list(self.lines)
        if title:
            lines.append({"type": "ai-title", "aiTitle": title, "sessionId": self.sid})
        pathlib.Path(path).write_text("\n".join(json.dumps(l, ensure_ascii=False) for l in lines) + "\n")


def file_result(path, content, n):
    return {"type": "text", "file": {"filePath": path, "content": content, "numLines": n, "startLine": 1, "totalLines": n}}


# ---------------------------------------------------------------- 5. chat-s2 (synthesis)
INTERVIEWS = [("p1", "Aisha", 23), ("p2", "Gerald", 23), ("p3", "Denise", 24), ("p4", "Marco", 23),
              ("p5", "Priya", 23), ("p6", "Hal", 23), ("p7", "June", 23), ("p8", "Owen", 23)]
QUOTE_P3 = "The glass door throws the afternoon sun straight back at the camera. Then my own box has a book on it that isn\u2019t there."
QUOTE_P8 = "Two wrong books and I stopped. I don\u2019t have time to audit it."
SYNTH_THEMES = [
    ("A wrong book costs trust fast", "P3, P6, P8", "all three stopped scanning after a wrong book was added for them"),
    ("Glare from glass doors makes scanning unreliable", "P3, P2", "Denise's glass door in the afternoon sun"),
    ("Testers want to check the list before it is saved", "P1, P4, P7", "they would tap through it rather than find out later"),
    ("Fixing a miss must take one tap", "P4, P5, P7", "nobody wants to retype a title"),
]


def synth_final():
    lines = ["## Interview synthesis", "",
             "Three of the eight testers (P3, P6, P8) stopped scanning after a wrong book was added for them. Four themes come up again and again:", ""]
    for t, who, why in SYNTH_THEMES:
        lines.append(f"- **{t}** ({who}): {why}.")
    lines += ["", "Two quotes carry it:", "",
              f"- **P3 Denise**: “{QUOTE_P3}”",
              f"- **P8 Owen**: “{QUOTE_P8}”", "",
              "I wrote it up in `docs/beta-interview-synthesis.docx` (Summary, What we heard, Themes, Recommendations). The recommendation: show what the scan found and let the steward review it before anything is added, make fixing a missed book one tap, and warn about glare before the photo is taken."]
    return "\n".join(lines)


def write_chat_s2():
    d = HERE / "chat-s2"
    (d / "meta.json").write_text(json.dumps({"mode": "chat", "tab": "Synthesis from interviews"}, indent=1))
    L = Log(PROJ, ids=False, day="2026-10-13")
    L.user("Read the eight interview notes and write the synthesis: themes, two quotes, recommendations.", "08:36:00")
    for i, (p, name, n) in enumerate(INTERVIEWS, 1):
        fp = f"{PROJ}/research/interviews/{p}.md"
        sec = 8 + i * 3
        L.use(f"toolu_s{i}", "Read", {"file_path": fp}, f"08:37:{sec:02d}")
        L.result(f"toolu_s{i}", "", file_result(fp, f"# {p.upper()} {name}", n), f"08:37:{sec:02d}")
    L.use("toolu_s9", "Write", {"file_path": f"{PROJ}/docs/beta-interview-synthesis.docx", "content": "Beta interview synthesis"}, "08:40:10")
    L.result("toolu_s9", "File created successfully at: docs/beta-interview-synthesis.docx", {"type": "create", "filePath": f"{PROJ}/docs/beta-interview-synthesis.docx", "content": "Beta interview synthesis"}, "08:40:11")
    L.text(synth_final(), "08:41:00")
    L.dump(d / "transcript.jsonl")


# ---------------------------------------------------------------- 6. hero session
SID = "5b1e7c42-9d3a-4f60-8a21-c0de0add0a11"
QUESTION = next(s for s in W["sessions"] if s["name"] == "Auto-add decision")["question"]
OPTIONS = next(s for s in W["sessions"] if s["name"] == "Auto-add decision")["options"]
OPT_DESC = {
    OPTIONS[0]: "Scans show a review step; nothing is added until the steward taps Add (PRD requirements)",
    OPTIONS[1]: "Stay with v1 behaviour for now and list it under Open questions",
    OPTIONS[2]: "Tell me what you would rather do",
}


def run_score():
    return subprocess.run([sys.executable, str(DOCS / "eval" / "score.py")], capture_output=True, text=True, check=True).stdout


def write_hero():
    L = Log(PROJ, sid=SID, day="2026-10-12")
    prd_p, ev_p = f"{PROJ}/docs/prd-v2.md", f"{PROJ}/eval/spine-eval-2026-09-28.md"
    pre_prd_lines, ev_lines = 24, len(EVAL_MD.splitlines())
    # (a) Oct 12
    L.user("Should auto-add survive v2? Read the PRD and Ravi's eval notes and tell me where we stand.", "16:12:05")
    L.use("toolu_h01", "Read", {"file_path": prd_p}, "16:12:20")
    L.result("toolu_h01", "", file_result(prd_p, "# Shelf scan v2: PRD", pre_prd_lines), "16:12:21")
    L.use("toolu_h02", "Read", {"file_path": ev_p}, "16:12:34")
    L.result("toolu_h02", "", file_result(ev_p, "# Spine eval, 2026-09-28", ev_lines), "16:12:35")
    L.text("Short version: on the numbers, auto-add can't survive v2 as it is.\n\n"
           "- **The model**: 81.0% of spines read correctly (1,004 of 1,240 photos, 96 shelves). Ravi's own threshold for auto-add is 95%.\n"
           "- **Where it misses**: tilted spines 34%, glare 27%, thin spines 21%, stacked or sideways books 12%, other 6% of the 236 wrong reads. Confidence doesn't separate right from wrong well, so a threshold on it won't fix this.\n"
           "- **The PRD today**: Requirements say nothing is added until the steward taps \"Add\", but Open question Q1 still asks whether to keep auto-add for stewards whose scans are 95%+ accurate.\n"
           "- **Caveat**: the glare set is only 140 photos from 9 shelves, so treat the glare share as soft.\n\n"
           "I'd leave Q1 open until we have the beta evidence next to the eval. Want me to check the two against each other?", "16:13:40")
    # (b) Today
    L.day = "2026-10-13"
    L.user("Check the eval numbers against the beta feedback, then add a What we heard section to the PRD.", "09:20:12")
    csv_p = f"{PROJ}/eval/results.csv"
    L.text("I'll start with the raw eval rows, then rerun the scoring, then look at what the testers said.", "09:20:30")
    L.use("toolu_h03", "Read", {"file_path": csv_p, "limit": 40}, "09:20:41")
    L.result("toolu_h03", "", file_result(csv_p, "photo_id,shelf_id,box,truth,read,correct,cause,confidence", 1241), "09:20:42")
    out = run_score()
    L.use("toolu_h04", "Bash", {"command": "python3 eval/score.py", "description": "Score the eval results"}, "09:23:02")
    L.result("toolu_h04", out, {"stdout": out, "stderr": "", "interrupted": False, "isImage": False, "noOutputExpected": False}, "09:23:03")
    L.text("The CSV agrees with Ravi's notes: 81.0% right, 236 wrong, and glare is the second biggest cause. Now the interviews.", "09:24:10")
    pat = "stopped"
    ipath = f"{PROJ}/research/interviews"
    hits = [("p3", 22, "- Stopped scanning after the wrong book."), ("p6", 14, "- Stopped after the second scan."),
            ("p6", 18, "> \u201cI added a wrong book and had no idea until a neighbour told me. I stopped scanning after that.\u201d"),
            ("p6", 21, "- Stopped scanning after a wrong book was added for him."), ("p8", 5, "- Who: stopped scanning after two wrong books"),
            ("p8", 13, "- Explained why he stopped."), ("p8", 17, "> \u201cTwo wrong books and I stopped. I don\u2019t have time to audit it.\u201d"),
            ("p8", 21, "- Stopped scanning after two wrong books."), ("p8", 23, "- Typical of the 46 of 148 testers who stopped after a wrong book.")]
    grep_content = "\n".join(f"{ipath}/{f}.md:{n}:{t}" for f, n, t in hits)
    L.use("toolu_h05", "Grep", {"pattern": pat, "path": ipath, "output_mode": "content", "-n": True, "-i": True}, "09:26:15")
    L.result("toolu_h05", grep_content, {"mode": "content", "numFiles": 3, "filenames": [f"{ipath}/p{k}.md" for k in (3, 6, 8)], "content": grep_content, "numLines": len(hits)}, "09:26:16")
    L.text("Three of the eight (P3, P6, P8) stopped after a wrong book. That matches the Oct 5 digest, where 46 of 148 testers who saw a wrong book stopped scanning (31%). Adding the section to the PRD now.", "09:28:30")
    start = PRD.index("3. A steward reviews")
    after_goals = PRD.index("\n\n## Requirements")
    old_s = PRD[start:after_goals] + "\n\n## Requirements"
    wh = PRD[PRD.index("## What we heard"):PRD.index("## Requirements")]
    new_s = PRD[start:after_goals] + "\n\n" + wh + "## Requirements"
    goal3 = PRD[start:after_goals]
    L.use("toolu_h06", "Edit", {"file_path": prd_p, "old_string": old_s, "new_string": new_s}, "09:33:50")
    patch_lines = [" " + goal3, " "] + ["+" + l for l in wh.rstrip("\n").splitlines()] + ["+", " ## Requirements"]
    L.result("toolu_h06", f"The file {prd_p} has been updated successfully.",
             {"filePath": prd_p, "oldString": old_s, "newString": new_s, "originalFile": None, "userModified": False, "replaceAll": False,
              "structuredPatch": [{"oldStart": 11, "oldLines": 3, "newStart": 11, "newLines": 3 + len(wh.rstrip("\n").splitlines()) + 2, "lines": patch_lines}]}, "09:33:51")
    L.text("I added \"What we heard\" between Goals and Requirements. Eval and feedback line up:\n\n"
           "- 81.0% of spines read correctly, and glare alone causes 27% of the wrong reads.\n"
           "- Three of eight testers (P3, P6, P8) stopped scanning after a wrong book was added for them.\n"
           "- With a review step in the prototype, testers fixed every miss: 97% of books right, median 18 s a shelf.\n\n"
           "One thing needs your call before I touch the goals or Open questions.", "09:36:40")
    L.use("toolu_h07", "AskUserQuestion", {"questions": [{
        "header": "Auto-add", "question": QUESTION, "multiSelect": False,
        "options": [{"label": o, "description": OPT_DESC[o]} for o in OPTIONS]}]}, "09:37:05")
    L.dump(HERE / "sessions" / "auto-add-decision.jsonl", title="Auto-add decision")
    # S5: the same session as a chat recording (the chat-s2 format), ending on the pending question.
    d = HERE / "chat-s4"; d.mkdir(exist_ok=True)
    (d / "meta.json").write_text(json.dumps({"mode": "chat", "tab": "Auto-add decision"}, indent=1))
    L.dump(d / "transcript.jsonl")


def main():
    write_results()
    (DOCS / "eval" / "score.py").write_text(SCORE_PY)
    (DOCS / "eval" / "spine-eval-2026-09-28.md").write_text(EVAL_MD)
    (DOCS / "research" / "feedback" / "denise-p3.txt").write_text(DENISE)
    write_chat_s2()
    write_hero()


if __name__ == "__main__":
    main()
