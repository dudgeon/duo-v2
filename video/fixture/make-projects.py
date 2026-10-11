#!/usr/bin/env python3
"""Writes the thin projects beside the hero (fixture/docs = shelf-scan): a PROJECT.md and a few believable documents each.
Sample data only; names and numbers come from world.json (see SCENARIO.md). Run: python3 video/fixture/make-projects.py"""
import json, pathlib
here = pathlib.Path(__file__).parent
w = json.load(open(here / "world.json"))
health = {"On track": "on-track", "At risk": "at-risk", "Off track": "off-track"}

def project_md(p, body):
    fm = ['---', f'goal: "{p["goal"]}"']
    if p.get("health"): fm.append(f'health: {health[p["health"]]}')
    if p.get("next"): fm.append(f'next: "{p["next"]}"')
    return "\n".join(fm + ["---", "", f'# {p["name"]}', "", body.strip(), ""])

DOCS = {
"beta-feedback": ("""What TestFlight testers tell us, sorted every week into a digest the team reads on Friday.

- [digests/2026-10-09.md](digests/2026-10-09.md): last week's digest
- [inbox/tester-emails-oct12.md](inbox/tester-emails-oct12.md): this week's emails, sorted""", {
"digests/2026-10-09.md": """# Beta digest: week of Oct 5

212 testers · 3 neighbourhoods · 41 reports this week (up from 29)

## Top themes
1. **Wrong books after a scan** (14 reports). Mostly glass-door boxes and leaning spines. 46 of the 148 testers who have seen a wrong book have stopped scanning.
2. **Map shows books that left days ago** (9). Freshness, see neighborhood-map.
3. **Steward handover** (5). Two boxes changed stewards; the app still notifies the old one.
4. **Crashes on iOS 19.4 when the camera opens** (4). Tomás has a fix in build 0.9.14.

## Quotes
> "It put a cookbook in my box that has never been in my box." (Owen, Riverside Allotments)

> "Love the map. Wish it told me how old the list is." (Priya, Elm Park)

## Asks for the team
- Ravi: the glare cases need more photos; testers on Linden St and Cooper Ln have offered.
- Sam: decide on auto-add before the Oct 15 review.
""",
"inbox/tester-emails-oct12.md": """# Tester emails, Oct 12 (sorted)

23 emails · 5 themes · 2 need a reply from a person

| Theme | Emails | Example |
| --- | --- | --- |
| Wrong book added | 8 | Denise (Linden St): "Persuasion" came out as a games handbook |
| Stale map | 5 | "Walked to Cooper Lane for nothing" |
| Feature ideas | 4 | Hold a book for an hour |
| Steward admin | 3 | Transfer a box to a neighbour |
| Thanks | 3 | "My kids check the map every morning" |

## Needs a person
- Denise (P3): wants to know if her box can be scanned at all with the glass door. Forwarded to Sam.
- Hal (P6): asks to delete 6 wrong books in bulk. Forwarded to Tomás.
""",
}),
"neighborhood-map": ("""The map of nearby boxes, and how fresh each box's catalog is.

- [specs/freshness.md](specs/freshness.md): the freshness badge, in progress
- [notes/map-tile-costs.md](notes/map-tile-costs.md): what the map costs to run""", {
"specs/freshness.md": """# Freshness badge: spec (draft)

Sam · Oct 13 · status: in progress

## Problem
A box's list is only as fresh as its last scan. The map shows every box the same, so neighbours walk to boxes whose books left last week.

## States
| Badge | Last scanned | Pin |
| --- | --- | --- |
| Fresh | under 2 days | solid |
| Getting old | 2–7 days | outlined |
| Stale | over 7 days | faded, "List may be out of date" |

## Open questions
- Does a neighbour's "I took this" count as a scan? (Ask Jo.)
- 61 of 340 boxes are stale today. Do we nudge their stewards?
""",
"notes/map-tile-costs.md": """# Map tile costs

At 212 testers we pay nothing. At 5,000 weekly users we'd cross the free tier around March.
TODO: compare cached vector tiles vs the current provider before the Oct 20 spec review.
""",
}),
"steward-onboarding": ("""Getting new stewards to claim their box and catalog it in their first week.

- [emails/welcome-email.md](emails/welcome-email.md): the welcome email, 3 variants""", {
"emails/welcome-email.md": """# Steward welcome email: 3 variants

**Goal:** half of new stewards catalog their box in week 1 (31% today).

## A · Plain
Subject: Your box is on the map
Thanks for looking after the Cooper Lane box. Scan your shelf once and your neighbours can see what's inside.

## B · Neighbourly
Subject: Your neighbours can see your shelf now
Six people near Cooper Lane opened the map this week. One scan, and they'll know what you've got.

## C · Short
Subject: One photo, done
Open the app, point it at your shelf, check the books, tap Add.
""",
}),
"home": ("""Triage, weekly status and personal ops.

- [status/weekly-2026-10-09.md](status/weekly-2026-10-09.md): last week's status""", {
"status/weekly-2026-10-09.md": """# Weekly status: Oct 9 (Sam)

- **shelf-scan:** PRD v2 started; the eval says 81%; review step prototyped with 4 testers (97%). Team review Thu Oct 15.
- **beta-feedback:** 41 reports; wrong books lead. Digest out Friday.
- **neighborhood-map:** freshness badge at risk; spec due Oct 20.
- **steward-onboarding:** welcome email variants drafted.
""",
}),
}

for p in w["projects"]:
    if p.get("hero"): continue
    body, files = DOCS[p["name"]]
    root = here / "projects" / p["name"]
    root.mkdir(parents=True, exist_ok=True)
    if p.get("isHome"):  # Home is marked by HOME.md (DL-85), not PROJECT.md
        (root / "HOME.md").write_text(project_md(p, body).replace("---\n", "---\ntype: home\n", 1))
    else:
        (root / "PROJECT.md").write_text(project_md(p, body))
    for rel, text in files.items():
        f = root / rel; f.parent.mkdir(parents=True, exist_ok=True); f.write_text(text)
print("wrote", ", ".join(p["name"] for p in w["projects"] if not p.get("hero")))
