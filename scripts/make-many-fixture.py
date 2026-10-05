#!/usr/bin/env python3
"""Writes the fixture for S4-1's target (DL-104): slice 2's Home and 64 folders outside it.

    scripts/make-many-fixture.py      → docs/design/many-projects-handoff/fixture.json

The same data as docs/design/explorations/home-many-projects.html draws. The `map-many` state loads it.
"""
import json, pathlib

repo = pathlib.Path(__file__).resolve().parent.parent
base = json.loads((repo / "docs/design/build-handoff/fixture.json").read_text())


def wait(m):
    return f"{m}m" if m < 60 else f"{round(m / 60)}h" if m < 1440 else f"{round(m / 1440)}d"


projects, sessions = [], []


def session(name, project, state="idle", w=None, **extra):
    s = {"name": name, "project": project, "state": state}
    if w is not None:
        s["wait"] = w
    s.update(extra)
    sessions.append(s)


# Home and its sessions: 8 named, then older ones to make 42.
projects.append({"name": "claude-home", "path": "~/claude-home", "isHome": True, "goal": "Triage, inbox and the weekly status"})
session("Morning triage", "claude-home", "needsYou", "1m", question="5 new asks: route 3 to projects?", reason="question")
session("Weekly status draft", "claude-home", "working", "working")
for n, w in [("Inbox sweep", "2h"), ("Legal call prep", "5h"), ("Q4 pricing numbers?", "1d"), ("Vendor shortlist", "2d"),
             ("Reading: buyer interviews", "3d"), ("“Summarise the six buyer…”", "4d")]:
    session(n, "claude-home", "idle", w)
for i in range(34):
    session(f"Session {i + 1}", "claude-home", "idle", f"{5 + i}d")

# Home's projects (slice 2's map).
for p, ss in [
    ({"name": "pricing-page", "topic": "", "path": "~/claude-home/pricing-page", "goal": "Launch the new tiers by Oct 20", "health": "On track", "next": "Copy freeze Oct 12"},
     [("Tier names", "needsYou", "2m", {"question": "Rename “Pro” to “Team” everywhere, including the billing emails?", "reason": "question"})]),
    ({"name": "q4-planning", "topic": "", "path": "~/claude-home/q4-planning", "goal": "Q4 plan signed off by staff", "health": "At risk", "next": "Draft due Oct 9"},
     [("Roadmap narrative", "working", "6m", {})]),
    ({"name": "checkout", "topic": "payments", "path": "~/claude-home/payments/checkout", "goal": "Cut guest-checkout abandonment 15% by Q1", "health": "On track", "next": "Exec review Oct 14"},
     [("PRD v2 edits", "needsYou", "4m", {"question": "Move saved cards into scope, or keep it out and log an open question?", "reason": "plan to approve"}),
      ("Teardown research", "working", "6m", {})]),
    ({"name": "refunds", "topic": "payments", "path": "~/claude-home/payments/refunds", "goal": "Ship refunds API spec to eng by Oct 10", "health": "At risk", "next": "Spec review Oct 8"},
     [("Edge cases", "idle", "5h", {})]),
    ({"name": "onboarding", "topic": "growth", "path": "~/claude-home/growth/onboarding", "goal": "Lift day-7 activation to 40%", "health": "On track", "next": "Copy freeze Oct 6"},
     [("Funnel SQL", "readyForReview", None, {"summary": "wrote funnel.sql, 3 files"})]),
]:
    projects.append(p)
    for n, st, w, extra in ss:
        session(n, p["name"], st, w, **extra)

# Folders outside Home: name, sessions, minutes since last active, CLAUDE.md, live state and session.
OUT = [
    ("~/repos", [("duo-v2", 38, 3, True, "working", "Slice 3 build"), ("pm-harness", 2, 2880, True), ("duo-legacy", 61, 4320, True),
                 ("obsidian-sync", 7, 1440 * 6), ("dotfiles", 4, 1440 * 9), ("blog", 3, 1440 * 12), ("claude-skills", 12, 1440 * 2),
                 ("mcp-notion", 5, 1440 * 15), ("fin-models", 3, 1440 * 20), ("interview-kit", 2, 1440 * 24), ("slackbot", 9, 1440 * 30),
                 ("scratch", 14, 1440 * 3), ("website-2024", 6, 1440 * 45), ("data-pipes", 4, 1440 * 50), ("prd-templates", 3, 1440 * 5),
                 ("analytics-sql", 8, 1440 * 8), ("roadmap-viz", 2, 1440 * 60), ("okr-tracker", 3, 1440 * 70), ("ai-evals", 5, 1440 * 11),
                 ("research-bot", 1, 1440 * 90), ("figma-export", 2, 1440 * 100), ("launch-checklist", 1, 1440 * 110), ("pricing-sim", 4, 1440 * 4),
                 ("survey-tools", 2, 1440 * 120)]),
    ("~/Desktop", [("interviews", 1, 1440 * 7), ("offsite-plan", 3, 1440), ("board-deck", 5, 1440 * 3, False, "needsYou", "Slide 7 numbers"),
                   ("q3-review", 2, 1440 * 25), ("competitor-teardown", 6, 1440 * 10), ("screenshots", 1, 1440 * 40), ("tmp-notes", 2, 1440 * 33),
                   ("hiring", 4, 1440 * 16)]),
    ("~/Documents", [("taxes-2025", 3, 1440 * 2), ("house", 2, 1440 * 13), ("resume", 4, 1440 * 28), ("reading-notes", 9, 1440 * 6),
                     ("letters", 1, 1440 * 80), ("journal", 11, 1440), ("recipes", 1, 1440 * 95), ("travel-japan", 2, 1440 * 140), ("kids-school", 2, 1440 * 21)]),
    ("~/Downloads", [("invoice-parse", 2, 1440 * 5), ("csv-cleanup", 3, 1440 * 9), ("pdf-merge", 1, 1440 * 30), ("statements", 2, 1440 * 14),
                     ("transcript-dump", 1, 1440 * 60), ("logo-files", 1, 1440 * 75), ("export-0912", 1, 1440 * 23)]),
    ("~/code/work", [("payments-api", 6, 1440, True, "working", "Webhook retries"), ("ledger", 4, 1440 * 4, True), ("checkout-web", 8, 1440 * 2, True),
                     ("risk-rules", 3, 1440 * 17), ("ops-scripts", 2, 1440 * 26), ("design-tokens", 2, 1440 * 31), ("mobile-app", 5, 1440 * 12),
                     ("admin-console", 3, 1440 * 38), ("feature-flags", 1, 1440 * 65), ("docs-site", 2, 1440 * 44)]),
    ("~", [("geoff", 4, 600)]),
    ("/private/tmp", [("tmp.x8Yq2", 1, 1440 * 2), ("claude-test", 2, 1440 * 19), ("sandbox-1", 1, 1440 * 48), ("sandbox-2", 1, 1440 * 48), ("tmp.Ka01", 1, 1440 * 130)]),
]
topics = ["", "payments", "growth"]
for parent, folders in OUT:
    topics.append(parent)
    for f in folders:
        name, count, minutes = f[0], f[1], f[2]
        claude_md = len(f) > 3 and f[3]
        live = f[4] if len(f) > 4 else None
        path = "~" if parent == "~" else f"{parent}/{name}"
        p = {"name": name, "topic": parent, "path": path, "goal": "", "kind": "folder"}
        if claude_md:
            p["hasClaudeMD"] = True
        projects.append(p)
        for i in range(count):
            if i == 0 and live:
                extra = {"question": "Run python3 chart.py?", "reason": "permission"} if live == "needsYou" else {}
                session(f[5], name, live, "9m" if live == "needsYou" else "3m", **extra)
            else:
                session(f"{name} {i + 1}", name, "idle", wait(minutes + i * 1440))

live = [s for s in sessions if s["state"] in ("needsYou", "readyForReview", "working")]
fixture = {
    "$note": "S4-1 (DL-104): the map with many projects. Made by scripts/make-many-fixture.py; don't edit by hand.",
    "now": "2026-10-05T09:40:00",
    "user": "Geoff",
    "topics": topics,
    "projects": projects,
    "sessions": sessions,
    "otherIdleSessions": 0,
    "groups": [],
    "counts": {"needsYou": sum(s["state"] == "needsYou" for s in live), "readyForReview": sum(s["state"] == "readyForReview" for s in live),
               "working": sum(s["state"] == "working" for s in live), "idle": 63},
    "homeInbox": base["homeInbox"],
    "focusDocument": base["focusDocument"],
    "projectFiles": {},
    "tasks": [
        {"project": "checkout", "path": "tasks/exec-review-prep.md", "title": "Exec review prep", "status": "in progress", "sessionIds": []},
        {"project": "checkout", "path": "tasks/legal-review.md", "title": "Legal review of saved cards", "status": "waiting", "sessionIds": []},
        {"project": "pricing-page", "path": "tasks/tier-table.md", "title": "Tier comparison table", "status": None, "sessionIds": []},
    ],
}
out = repo / "docs/design/many-projects-handoff/fixture.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(fixture, indent=1, ensure_ascii=False) + "\n")
print(out.relative_to(repo), len(projects), "projects,", len(sessions), "sessions")
