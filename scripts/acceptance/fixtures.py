#!/usr/bin/env python3
"""Acceptance-test fixtures for Duo (the acceptance-walk skill).

    scripts/acceptance/fixtures.py            build ~/DuoAcceptance (refuses if it exists)
    scripts/acceptance/fixtures.py --reset    move the old one (and its planted sessions) to the Trash, rebuild
    scripts/acceptance/fixtures.py --clean    move everything this script made to the Trash
    scripts/acceptance/fixtures.py --purge    simulate Claude's cleanup of the purge-test session (after Duo has run once)

Builds a workspace of projects and documents in the states the walk needs, plants synthetic
Claude sessions (marked "[fixture]") in ~/.claude/projects for its folders, and records what it
planted so --clean can remove exactly that. Nothing is ever hard-deleted: removals go to the Trash.
"""
import json, os, pathlib, shutil, subprocess, sys, time, uuid, datetime

HOME = pathlib.Path.home()
ROOT = HOME / "DuoAcceptance"
WS = ROOT / "workspace"
ELSE = ROOT / "elsewhere"
PLANTED = ROOT / ".planted.json"
CLAUDE = pathlib.Path(os.environ.get("CLAUDE_CONFIG_DIR", HOME / ".claude")) / "projects"
REPO = pathlib.Path(__file__).resolve().parents[2]


def trash(p):
    p = pathlib.Path(p)
    if p.exists():
        subprocess.run(["/usr/bin/trash", str(p)], check=False)


def encode(path):
    return "".join(c if c.isalnum() else "-" for c in str(path))


def write(p, text, newline="\n", raw=None):
    p = pathlib.Path(p)
    p.parent.mkdir(parents=True, exist_ok=True)
    if raw is not None:
        p.write_bytes(raw)
    else:
        p.write_bytes(text.replace("\n", newline).encode("utf-8"))


def project(folder, goal, health="on-track", next_step=""):
    write(folder / "PROJECT.md", "---\ngoal: \"%s\"\nhealth: %s\nnext: \"%s\"\n---\n\n# %s\n\n%s.\n" % (goal, health, next_step, folder.name, goal))


planted = []


def session(folder, title, turns, days_ago=0, sid=None):
    """Plants a synthetic transcript Claude Code (and Duo) will read as a past session."""
    sid = sid or str(uuid.uuid4())
    folder = pathlib.Path(folder).resolve()
    d = CLAUDE / encode(folder)
    d.mkdir(parents=True, exist_ok=True)
    t = datetime.datetime.utcnow() - datetime.timedelta(days=days_ago)
    stamp = t.strftime("%Y-%m-%dT%H:%M:%S.000Z")
    lines, parent = [], None
    for i, (you, claude) in enumerate(turns):
        u = str(uuid.uuid4())
        lines.append({"type": "user", "cwd": str(folder), "sessionId": sid, "uuid": u, "parentUuid": parent, "timestamp": stamp,
                      "message": {"role": "user", "content": "[fixture] " + you}})
        a = str(uuid.uuid4())
        lines.append({"type": "assistant", "cwd": str(folder), "sessionId": sid, "uuid": a, "parentUuid": u, "timestamp": stamp,
                      "message": {"role": "assistant", "content": [{"type": "text", "text": claude}]}})
        parent = a
    lines.append({"type": "ai-title", "aiTitle": title, "sessionId": sid})
    f = d / (sid + ".jsonl")
    f.write_text("\n".join(json.dumps(l) for l in lines) + "\n")
    mt = time.time() - days_ago * 86400
    os.utime(f, (mt, mt))
    planted.append(str(f))
    return sid


def build():
    # Workspace: Home, four projects across three topics.
    write(WS / "home" / "HOME.md", "---\ngoal: \"Triage, dispatch, weekly status\"\nnext: \"Weekly status Friday\"\n---\n\n# Home\n")
    write(WS / "home" / "templates" / "decision-record.md", "# Decision: \n\n## Context\n\n## Options\n\n## Decision\n\n## Consequences\n")

    co = WS / "payments" / "checkout"
    project(co, "Cut guest-checkout abandonment 15% by Q1", "on-track", "Exec review Oct 14")
    write(co / "docs" / "prd.md", """---
status: draft
owner: geoff
---
# Checkout PRD

## Problem

Guest checkout loses **15%** of buyers at the card step. See [the research](research.md).

## Goals

- [ ] Cut abandonment to 12.75%
- [x] Interview six buyers
- [ ] Decide on saved cards

## Open questions

Do we keep saved cards out of scope for v2? *Decision due Oct 10.*
""")
    write(co / "docs" / "research.md", "# Research\n\nSix interviews. Two said saved cards were the reason they left.\n")
    write(co / "docs" / "windows-notes.md", "# Notes from the Windows team\n\nThis file uses CRLF line endings.\nSave it and they must stay CRLF.\n", newline="\r\n")
    write(co / "docs" / "mixed-endings.md", None, raw=b"# Mixed endings\r\nThis line ends in CRLF.\nThis one in LF.\r\nDuo must open this read-only.\n")
    write(co / "docs" / "legacy-export.txt", None, raw="Café résumé: exported in Latin-1, not UTF-8.\n".encode("latin-1"))
    write(co / "templates" / "meeting-notes.md", "# Meeting notes\n\n**Date:** \n**Attendees:** \n\n## Decisions\n\n## Actions\n- [ ] \n")
    big = pathlib.Path(HOME / "repos" / "duo" / "tasks.md")
    if big.exists():
        shutil.copy(big, co / "docs" / "long-backlog.md")   # a long file for find and typing speed

    rf = WS / "payments" / "refunds"
    project(rf, "Ship refunds API spec to eng by Oct 10", "at-risk", "Spec review Oct 8")
    write(rf / "spec" / "errors.md", "# Errors\n\n| Code | Meaning |\n|---|---|\n| ERR_REFUND_409 | Refund already in progress |\n| ERR_REFUND_422 | Amount exceeds capture |\n")

    ob = WS / "growth" / "onboarding"
    project(ob, "Lift day-7 activation to 40%", "on-track", "Copy freeze Oct 6")
    write(ob / ".duo" / "sessions.json", json.dumps({"schema": 1, "sessions": [], "groups": []}, indent=2) + "\n")
    subprocess.run(["git", "init", "-q", str(ob)], check=False)     # a git repo: the .gitignore offer

    rd = WS / "research" / "reading"
    project(rd, "Background reading for the platform team")
    poc = HOME / "repos" / "smol-sim-search" / "tests" / "fixtures"
    if poc.exists():
        shutil.copytree(poc, rd / "library", dirs_exist_ok=True)   # the search golden set
    write(rd / "notes" / "duplicate-billing.md", "# Duplicate billing\n\nCustomers were charged twice when the payment retry fired after a timeout.\n")

    # Past sessions in projects (history in place, Older fold, same-name rows, purge test).
    session(co, "Interview synthesis notes", [("Summarise the six buyer interviews.", "Two buyers left over saved cards; four over shipping costs.")], days_ago=3)
    for i in range(9):
        session(rd, "Reading note %d" % (i + 1), [("Note %d on the platform reading." % (i + 1), "Noted.")], days_ago=2 + i)
    session(rf, "Untitled scratch", [("First scratch thought about refunds.", "OK.")], days_ago=1)
    session(rf, "Untitled scratch", [("Second scratch thought, same title.", "OK.")], days_ago=2)
    purge = session(rf, "Refund edge cases (purge test)", [("List refund edge cases: partial, duplicate, expired card.", "1. Partial refunds. 2. Duplicates. 3. Expired cards.")], days_ago=4)

    # Folders with sessions but no PROJECT.md (DL-63), outside the workspace.
    scratch = ELSE / "scratch"
    side = ELSE / "side-project"
    scratch.mkdir(parents=True, exist_ok=True)
    write(side / "CLAUDE.md", "# Side project\n\nA landing page for a weekend idea.\n")
    session(scratch, "Quick question about refund SLAs", [("What's a typical refund SLA?", "Five to ten business days is common.")], days_ago=5)
    session(scratch, "Draft a post about pricing", [("Draft a short post about our pricing change.", "Here's a draft…")], days_ago=6)
    session(side, "Plan the side-project landing page", [("Plan a landing page for the side project.", "Hero, three benefits, sign-up.")], days_ago=2)

    # A legacy Duo install, for `duo2 legacy` (never your real ~/.claude).
    lg = ROOT / "legacy-claude-config"
    write(lg / "settings.json", json.dumps({"model": "opus", "hooks": {"Stop": [
        {"hooks": [{"type": "command", "command": "duo-attention.sh", "_duo": "managed-v3"}]},
        {"hooks": [{"type": "command", "command": "my-own-hook.sh"}]}]}}, indent=2) + "\n")
    write(lg / "CLAUDE.md", "# My instructions\n\nKeep this.\n\n<!-- duo:managed-v3 — installed by Duo. -->\nLegacy Duo instructions.\n<!-- duo:end -->\n\nAnd this.\n")
    write(lg / "skills" / "duo" / "SKILL.md", "legacy skill\n")
    write(lg / "agents" / "duo.md", "legacy subagent\n")

    PLANTED.write_text(json.dumps({"transcripts": planted, "purge_session": purge, "built": datetime.datetime.now().isoformat()}, indent=2))
    print("Built %s\n  workspace: %s\n  planted %d sessions in %s" % (ROOT, WS, len(planted), CLAUDE))


def clean():
    if PLANTED.exists():
        info = json.loads(PLANTED.read_text())
        for f in info.get("transcripts", []):
            trash(f)
            side = pathlib.Path(f).with_suffix("")
            trash(side)
        # Archived copies Duo kept of the fixture sessions.
        arch = HOME / "Library" / "Application Support" / "Duo" / "archive"
        for f in info.get("transcripts", []):
            trash(arch / pathlib.Path(f).name)
    trash(ROOT)
    print("Moved %s and its planted sessions to the Trash." % ROOT)


def purge():
    info = json.loads(PLANTED.read_text())
    sid = info["purge_session"]
    for f in info["transcripts"]:
        if pathlib.Path(f).stem == sid:
            trash(f)
            print("Moved the purge-test transcript to the Trash (as Claude's cleanup would delete it): %s" % f)
            return
    print("purge-test transcript not found")


if __name__ == "__main__":
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg == "--clean":
        clean()
    elif arg == "--purge":
        purge()
    else:
        if ROOT.exists():
            if arg != "--reset":
                sys.exit("%s exists. Use --reset to rebuild it (the old one goes to the Trash)." % ROOT)
            clean()
        build()
