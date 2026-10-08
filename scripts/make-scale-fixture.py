#!/usr/bin/env python3
"""Writes a work-Mac-scale fixture for Duo's scale check (F-208): a Home with many projects, many
Claude sessions in a scratch Claude config folder, a few long transcripts, and optionally a
restore file that reopens sessions as tabs in chat.

    scripts/make-scale-fixture.py <root> [--projects 40] [--sessions 600] [--long 4]
                                  [--tabs 20] [--home-view list|board|none] [--claude <stub>]

<root>/ws is the workspace (HOME.md, then <topic>/<project>/PROJECT.md), <root>/cfg the Claude
config folder (CLAUDE_CONFIG_DIR) and <root>/sup Duo's support folder (DUO_SUPPORT_DIR; keep
<root> short, the control socket's path must stay under 104 characters). Every word is
generated; no real transcript text.
"""
import argparse, datetime, json, os, pathlib, random, re, subprocess, sys, uuid

ap = argparse.ArgumentParser()
ap.add_argument("root")
ap.add_argument("--projects", type=int, default=40)
ap.add_argument("--sessions", type=int, default=600)
ap.add_argument("--long", type=int, default=4, help="sessions with long transcripts (make-long-chat.py)")
ap.add_argument("--tabs", type=int, default=0, help="sessions reopened as tabs by the restore file")
ap.add_argument("--chat", action="store_true", help="chat mode is the default for every session")
ap.add_argument("--home-view", default="none", choices=["list", "board", "none"])
ap.add_argument("--claude", help="a stub claude for restored tabs (state.json's claudePath)")
ap.add_argument("--mock-key", help="approve this dummy API key and trust every folder in the config (for the mock API)")
ap.add_argument("--on-home", action="store_true", help="the restore file shows Home's own project with its newest session as the tab, and that session as Home's tab")
ap.add_argument("--nested", type=int, default=0, help="Home's newest session ends with your message and Claude's reply holding Markdown lists nested this deep")
ap.add_argument("--modes-chat", action="store_true", help="chat.json modes: chat for every restored session id")
ap.add_argument("--seed", type=int, default=7)
a = ap.parse_args()

r = random.Random(a.seed)
root = pathlib.Path(os.path.realpath(a.root))
ws, cfg, sup = root / "ws", root / "cfg", root / "sup" / "Duo"
for d in (ws, cfg / "projects", sup):
    d.mkdir(parents=True, exist_ok=True)
repo = pathlib.Path(__file__).resolve().parent.parent
WORDS = ("checkout wallet ledger refund rollout pricing vendor interview draft review fixture onboarding "
         "dashboard migration billing report budget roadmap launch audit cleanup").split()

(ws / "HOME.md").write_text("---\ngoal: \"Triage and the weekly status\"\n---\n\n# Home\n")
folders = [ws]
topics = ["payments", "growth", "platform", "research", "ops"]
for i in range(a.projects):
    f = ws / topics[i % len(topics)] / f"{r.choice(WORDS)}-{i + 1}"
    f.mkdir(parents=True, exist_ok=True)
    (f / "PROJECT.md").write_text(f"---\ngoal: \"{' '.join(r.choice(WORDS) for _ in range(5))}\"\n---\n\n# {f.name}\n")
    folders.append(f)


def enc(p):
    return re.sub(r"[^A-Za-z0-9]", "-", str(p))


now = datetime.datetime.now(datetime.timezone.utc)
ids = []
for n in range(a.sessions):
    folder = folders[n % len(folders)]
    sid = str(uuid.UUID(int=r.getrandbits(128), version=4))
    ids.append((sid, folder))
    d = cfg / "projects" / enc(folder)
    d.mkdir(parents=True, exist_ok=True)
    t = d / f"{sid}.jsonl"
    if n < a.long:
        subprocess.run([sys.executable, str(repo / "scripts/make-long-chat.py"), str(t), "--seed", str(n + 1)],
                       check=True, stdout=subprocess.DEVNULL)
        body = t.read_text().replace("/Users/pm/work/payments/checkout-redesign", str(folder))
        t.write_text(body)
    else:
        lines = []
        at = now - datetime.timedelta(minutes=n * 37 + r.randint(0, 30))
        for k in range(r.randint(1, 4)):
            ts = (at + datetime.timedelta(minutes=k)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
            prompt = " ".join(r.choice(WORDS) for _ in range(r.randint(4, 14))).capitalize()
            lines.append({"type": "user", "message": {"role": "user", "content": prompt}, "timestamp": ts,
                          "cwd": str(folder), "sessionId": sid})
            lines.append({"type": "assistant", "message": {"model": "claude-opus-5-5", "role": "assistant",
                          "content": [{"type": "text", "text": " ".join(r.choice(WORDS) for _ in range(30)) + "."}]},
                          "timestamp": ts, "cwd": str(folder), "sessionId": sid})
        t.write_text("".join(json.dumps(l) + "\n" for l in lines))
        mt = at.timestamp()
        os.utime(t, (mt, mt))

if a.mock_key:
    trust = {"hasTrustDialogAccepted": True, "hasCompletedProjectOnboarding": True}
    (cfg / ".claude.json").write_text(json.dumps({
        "hasCompletedOnboarding": True, "lastOnboardingVersion": "2.1.219", "theme": "dark", "numStartups": 5,
        "customApiKeyResponses": {"approved": [a.mock_key[-20:]], "rejected": []},
        "projects": {str(f): trust for f in folders}}))
if a.nested:
    # Lists nested D deep, as pasted outlines and Claude's own plans often are (F-208).
    def outline(d, k=0):
        pad = "  " * k
        out = [f"{pad}- {' '.join(r.choice(WORDS) for _ in range(6))}", f"{pad}- {' '.join(r.choice(WORDS) for _ in range(4))}"]
        if k + 1 < d:
            out[1:1] = outline(d, k + 1)
        return out
    text = "Plan:\n\n" + "\n".join(outline(a.nested))
    sid, folder = next((sid, f) for sid, f in ids if f == ws)
    t = cfg / "projects" / enc(folder) / f"{sid}.jsonl"
    ts = now.strftime("%Y-%m-%dT%H:%M:%S.000Z")
    with t.open("a") as f:
        f.write(json.dumps({"type": "user", "message": {"role": "user", "content": text}, "timestamp": ts, "cwd": str(folder), "sessionId": sid}) + "\n")
        f.write(json.dumps({"type": "assistant", "message": {"model": "claude-opus-5-5", "role": "assistant", "content": [{"type": "text", "text": text}]},
                            "timestamp": ts, "cwd": str(folder), "sessionId": sid}) + "\n")
state = {"home": str(ws), "root": str(ws)}
if a.home_view != "none":
    state["homeView"] = a.home_view
if a.claude:
    state["claudePath"] = a.claude
(sup / "state.json").write_text(json.dumps(state))
if a.chat:
    (sup / "chat.json").write_text(json.dumps({"modes": {}, "last": "chat"}))
if a.tabs:
    # Restore (LR-58): one file per Home, named by an FNV-1a hash of Home's path, as Duo does.
    h = 1469598103934665603
    for ch in str(ws):
        h = ((h ^ ord(ch)) * 1099511628211) & 0xFFFFFFFFFFFFFFFF
    key, digits = "", "0123456789abcdefghijklmnopqrstuvwxyz"
    while h:
        h, m = divmod(h, 36)
        key = digits[m] + key
    by = {}
    for sid, folder in ids[:a.tabs]:
        if folder != ws:
            by.setdefault(str(folder), []).append(sid)
    first = next(iter(by), None)
    restore = {"version": 1, "root": str(ws), "project": first, "leftCollapsedAllProjects": False, "leftCollapsedProject": False,
               "projects": [{"folder": f, "sessions": s, "documents": []} for f, s in by.items()]}
    if a.on_home:
        home_sid = next(sid for sid, folder in ids if folder == ws)
        restore["project"] = str(ws)
        restore["homeTab"] = home_sid
        restore["projects"].append({"folder": str(ws), "sessions": [home_sid], "consoleTab": home_sid, "documents": []})
    (sup / f"restore-{key or '0'}.json").write_text(json.dumps(restore))
    if a.modes_chat:
        modes = {sid: "chat" for ss in by.values() for sid in ss}
        modes.update({sid: "chat" for sid, folder in ids if folder == ws})
        (sup / "chat.json").write_text(json.dumps({"modes": modes, "last": "chat"}))
print(f"{root}: {a.projects} projects, {a.sessions} sessions ({a.long} long), {a.tabs} tabs, home view {a.home_view}")
