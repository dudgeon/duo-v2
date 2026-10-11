#!/usr/bin/env python3
"""Rebuild fixture.json for the demo world (SCENARIO.md, world.json). Stdlib only.
Same keys and types as Sources/DuoKit/Model/Fixture.swift decodes."""
import json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
world = json.load(open(os.path.join(HERE, "world.json")))
ROOT = world["root"]

# --- projects ---
projects = []
for p in world["projects"]:
    projects.append({
        "name": p["name"], "topic": p["topic"], "path": f"{ROOT}/{p['name']}",
        **({"isHome": True} if p.get("isHome") else {}),
        "goal": p["goal"], "health": p["health"], "next": p["next"],
    })

# --- sessions ---
sessions, archived = [], []
for s in world["sessions"]:
    o = {"name": s["name"], "project": s["project"], "state": s["state"]}
    if s.get("wait"): o["wait"] = s["wait"]
    if s["name"] == "Auto-add decision": o["forkOf"] = "Synthesis from interviews"
    if s.get("question"): o["question"] = s["question"]
    if s.get("options"): o["options"] = s["options"]
    if s.get("summary"): o["summary"] = s["summary"]
    if s.get("document"): o["document"] = s["document"]
    if s["state"] == "archived":
        o["state"] = "idle"
        archived.append(o)
    else:
        sessions.append(o)

counts = {k: sum(1 for s in sessions if s["state"] == k) for k in ["needsYou", "readyForReview", "working", "idle"]}
other_idle = 0

groups = [{
    "name": "Scan v2", "project": "shelf-scan",
    "sessions": ["Synthesis from interviews", "Auto-add decision", "Tighten PRD goals"],
    "threads": [["Synthesis from interviews", "Auto-add decision"], ["Tighten PRD goals"]],
}]

home_inbox = [
    {"title": "Ravi: new eval run on glare set", "source": "Slack · Ravi · 8:12", "status": "suggested → shelf-scan"},
    {"title": "Jo: can you send the deck by Wed noon?", "source": "Slack · Jo · 8:40", "status": "suggested → shelf-scan"},
    {"title": "Tester email: the scan keeps adding the wrong book", "source": "Email · 8:05", "status": "routed → beta-feedback, session started"},
    {"title": "Map tile invoice, October", "source": "Email · 7:52", "status": "routed → neighborhood-map, resumed Map pins: stale boxes"},
    {"title": "1 duplicate, ignored"},
]

# PRD headings, exactly
prd = open(os.path.join(HERE, "docs/docs/prd-v2.md")).read().split("\n")
sections = [l[3:].strip() for l in prd if l.startswith("## ")]

focus = {"project": "shelf-scan", "path": "docs/prd-v2.md", "sections": sections,
         "addedByClaude": ["What we heard"], "markdownFile": "docs/docs/prd-v2.md"}

project_files = {"shelf-scan": [
    "PROJECT.md", "docs/prd-v2.md", "docs/team-review-oct15.pptx", "docs/beta-interview-synthesis.docx",
    "prototype/scan-review.html", "eval/spine-eval-2026-09-28.md", "eval/results.csv", "eval/score.py"]}

AUTO = "where did we land on auto-add"
SNIP_Q1 = "…Auto-add: keep it for stewards whose scans are 95%+ accurate, or remove it until the model reaches 95%? Three testers (P3, P6, P8) stopped scanning after a wrong book…"

search = {
    "coverage": "Indexing: neighborhood-map 118 of 164 files · sessions before Aug 12 not yet indexed",
    "firstRun": "Building the index for the first time. Newest first: 2 of 5 projects done · sessions before Sep 20 not yet indexed.",
    "recent": [
        {"query": AUTO, "when": "today"},
        {"query": "books that weren't there", "when": "yesterday"},
        {"query": "ERR_SCAN_GLARE", "when": "3d"},
    ],
    "sendTarget": {"allProjects": "Morning triage", "insideProject": "Auto-add decision"},
    "queries": [
        {
            "query": AUTO, "mode": "meaning and words", "currentProject": "shelf-scan",
            "screens": ["search-overview", "search-project", "search-project-narrowed", "search-typing",
                        "search-first-run", "search-actions-file", "search-actions-session", "search-multi"],
            "results": [
                {"project": "shelf-scan", "kind": "file", "title": "docs/prd-v2.md", "where": "L28–30",
                 "matchedBy": ["meaning", "words"], "date": "today", "snippet": SNIP_Q1,
                 "matchedWords": ["Auto-add"], "alsoIn": ["research/prd-v1-goals.md"],
                 "passages": [
                     {"where": "L28–30", "heading": "Open questions", "snippet": "…Q1. Auto-add: keep it for stewards whose scans are 95%+ accurate, or remove it until the model reaches 95%?…"},
                     {"where": "L13–16", "heading": "What we heard", "snippet": "…Three of eight testers (P3, P6, P8) stopped scanning after a wrong book was added for them…"},
                     {"where": "L18–22", "heading": "Requirements", "snippet": "…Nothing is added to the catalog until the steward taps “Add”…"},
                 ]},
                {"project": "shelf-scan", "kind": "session", "title": "Auto-add decision", "where": "turn 6",
                 "matchedBy": ["meaning"], "date": "4m",
                 "snippet": "You: Put auto-add behind the review step, or keep it and log an open question? Claude: Three testers say a wrong auto-added book is why they stopped scanning…"},
                {"project": "shelf-scan", "kind": "session", "title": "Synthesis from interviews", "where": "turn 11",
                 "matchedBy": ["meaning"], "date": "1h",
                 "snippet": "…P3, P6 and P8 each say the same thing: after two wrong books, they stopped scanning…"},
                {"project": "shelf-scan", "kind": "file", "title": "eval/spine-eval-2026-09-28.md", "where": "L44–58",
                 "matchedBy": ["words"], "date": "2w",
                 "snippet": "…auto-add stays risky until accuracy clears 95%; v1 model is at 81%…",
                 "matchedWords": ["auto-add"]},
                {"project": None, "unfiled": True, "kind": "session", "title": "quick q: TestFlight build size",
                 "where": "turn 2", "matchedBy": ["meaning"], "date": "3d",
                 "snippet": "…does the scan model ship inside the app or download after install…"},
            ],
        },
        {
            "query": "books that weren't there", "mode": "meaning and words",
            "screens": ["search-none (with Kind: Memory and Date: Past week set, which hide all three)"],
            "results": [
                {"project": "shelf-scan", "kind": "file", "title": "research/feedback/denise-p3.txt", "where": "L4–12",
                 "snippet": "a neighbour walked over for Persuasion and it wasn't in the box"},
                {"project": "shelf-scan", "kind": "session", "title": "Synthesis from interviews", "where": "turn 3"},
                {"project": "beta-feedback", "kind": "file", "title": "digests/2026-10-05.md", "where": "L9–20"},
            ],
        },
        {
            "query": "ERR_SCAN_GLARE", "mode": "exact", "screens": ["search-exact"],
            "results": [
                {"project": "shelf-scan", "kind": "file", "title": "eval/score.py", "where": "L52",
                 "matchedBy": ["exact"], "date": "5d"},
                {"project": "shelf-scan", "kind": "session", "title": "Spine eval: glare cases", "where": "turn 9",
                 "matchedBy": ["exact"], "date": "9m"},
                {"project": "beta-feedback", "kind": "file", "title": "crashes/triage.md", "where": "L31",
                 "matchedBy": ["exact"], "date": "2w"},
            ],
        },
    ],
    "similar": {
        "source": {"project": "shelf-scan", "kind": "file", "title": "docs/prd-v2.md", "where": "L28–30"},
        "returnsTo": AUTO,
        "results": "results 2 to 5 of that query, in the same order",
        "screens": ["search-similar"],
    },
    "jump": {
        "query": "auto", "screens": ["search-jump"],
        "results": [
            {"kind": "group", "title": "Scan v2", "project": "shelf-scan", "sessions": 3, "state": "needsYou", "wait": "4m"},
            {"kind": "session", "title": "Auto-add decision", "project": "shelf-scan", "state": "needsYou", "wait": "4m"},
        ],
        "always": ["New project “auto”", "Search contents for “auto”"],
    },
    "archivedExample": {
        "project": "shelf-scan", "kind": "session", "title": "Scan v1 launch notes", "where": "turn 4",
        "matchedBy": ["words"], "date": "7w", "archived": True,
        "snippet": "…auto-add came up once at launch and was kept so a first scan feels instant…",
    },
    "$additions": [
        "search.queries[0].results[0].passages (count 3, and the L13–16 and L18–22 passages)",
        "dates on the ERR_SCAN_GLARE results",
        "search.recent",
        "search.firstRun",
        "search.archivedExample (used only on the sheet)",
        "matchedWords (which words the snippets show in semibold)",
    ],
}

def idle(name, project, age, **kw):
    return {"name": name, "project": project, "age": age, **kw}

surfaces = {
    "$note": "Sample data the surfaces screens add to the fixture's world. Not a schema. Grows with each slice.",
    "$additions": [
        "Named idle sessions (live idle plus archived)",
        "idleMany: a larger set for the long list",
        "consoleStates and shells: what the DB-3 and DB-4 screens show",
    ],
    "idleSessions": {
        "$surface": "DB-1", "count": 8,
        "buckets": [
            {"label": "This week", "sessions": [
                idle("Map pins: stale boxes", "neighborhood-map", "2d"),
                idle("quick q: TestFlight build size", "shelf-scan", "3d", group="Scan v2"),
            ]},
            {"label": "Last week", "sessions": [
                idle("Old v1 notes cleanup", "shelf-scan", "6d"),
            ]},
            {"label": "Earlier", "sessions": [
                idle("Map tile costs", "neighborhood-map", "3w", archived=True),
                idle("Interview guide", "shelf-scan", "4w", archived=True),
                idle("Scan v1 launch notes", "shelf-scan", "7w", archived=True),
            ]},
        ],
    },
    "idleMany": {
        "$surface": "DB-1", "count": 312,
        "firstBuckets": [{"label": "This week", "count": 9}, {"label": "Last week", "count": 14}],
        "laterBuckets": "by month: September, August, …",
        "awkwardRows": [
            {"name": "Synthesis of the eight beta interviews about wrong books, auto-add and glass-door glare, second pass",
             "project": "shelf-scan", "age": "1d", "why": "a title too long for its row"},
            {"name": "Steward handbook rewrite", "project": "steward-onboarding", "openIn": "Terminal",
             "why": "live outside Duo, so not resumable (LR-8)"},
            {"name": "scratch notes on TestFlight groups", "project": None, "unfiled": True, "age": "3d",
             "why": "from a folder that is not a project"},
        ],
        "otherRows": [
            "Crash log patterns · beta-feedback · 4d",
            "Box freshness thresholds · neighborhood-map · 9d",
            "Friday triage · home · 9d",
        ],
    },
    "consoleStates": {
        "$surface": "DB-3",
        "none": {"project": "steward-onboarding", "lastSession": "Steward welcome email",
                 "files": ["PROJECT.md", "welcome-email.md"],
                 "path": f"{ROOT}/steward-onboarding", "needYouElsewhere": 3},
        "ended": {"project": "shelf-scan", "session": "Spine eval: glare cases", "at": "09:12", "crashVariant": "exit 1"},
        "elsewhere": {"session": "Auto-add decision", "app": "Terminal", "since": "8:55"},
        "folderMissing": {"path": f"{ROOT}/neighborhood-map", "nearest": ROOT},
        "homeNone": {
            "counts": {"needsYou": 2, "readyForReview": 3, "working": 4, "idle": 6},
            "why": "Morning triage is closed, so it counts as idle and the Home pointer card is gone",
        },
    },
    "shells": {
        "$surface": "DB-4", "project": "shelf-scan",
        "tabs": [
            {"kind": "session", "name": "Auto-add decision", "state": "needsYou"},
            {"kind": "session", "name": "Spine eval: glare cases", "state": "working"},
            {"kind": "shell", "name": "zsh", "selected": True},
            {"kind": "shell", "name": "python3 eval/score.py", "running": True},
        ],
        "transcript": ["git status", "ls"],
        "untrackedFile": "docs/glare-notes.md",
        "promoted": {"before": "claude", "after": "New session"},
        "failed": {"name": "python3 eval/score.py", "exit": 1},
        "narrow": {"window": "1280x800",
                   "visible": ["Auto-add decision", "Spine eval: glare cases", "zsh"], "hidden": 2},
    },
}

fixture = {
    "$note": "Sample data for the intro video's demo world (Little Shared Library; SCENARIO.md, world.json). Built by make-fixture.py; do not edit by hand. Same keys as the design fixture.",
    "videoS2": {
        "folder": "docs",
        "project": "shelf-scan",
        "cwd": "/Users/sam/work/little-shared-library/shelf-scan",
        "terminals": [
            {"name": "Tighten PRD goals", "state": "working", "wait": "now", "screen": "terms/tighten-prd.ans"},
            {"name": "Prototype scan review", "state": "idle", "wait": "12m", "screen": "terms/prototype-scan-review.ans"},
            {"name": "Synthesis from interviews", "state": "idle", "wait": "1h", "screen": "terms/synthesis.ans"},
        ],
        "chat": "chat-s2",
        "tabs": ["docs/prd-v2.md", "prototype/scan-review.html", "docs/team-review-oct15.pptx", "docs/beta-interview-synthesis.docx"],
        "files": ["PROJECT.md", "docs/prd-v2.md", "docs/team-review-oct15.pptx", "docs/beta-interview-synthesis.docx", "prototype/scan-review.html"],
    },
    "now": world["time"]["today"],
    "user": world["user"]["name"],
    "topics": world["topics"],
    "projects": projects,
    "sessions": sessions,
    "otherIdleSessions": other_idle,
    "groups": groups,
    "counts": counts,
    "homeInbox": home_inbox,
    "focusDocument": focus,
    "projectFiles": project_files,
    "archivedSessions": archived,   # optional in the decoder: kept out of lists and counts
    "search": search,
    "surfaces": surfaces,
}

with open(os.path.join(HERE, "fixture.json"), "w") as f:
    json.dump(fixture, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("counts", counts, "sessions", len(sessions), "archived", len(archived))
