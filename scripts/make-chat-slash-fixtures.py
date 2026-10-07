#!/usr/bin/env python3
"""Writes the chat-slash targets' recordings: docs/design/chat-slash-handoff/fixture-chat/slash-<board>/.

The boards' content (illustrative, as drawn, DL-143) as Claude Code records it: transcript lines
(slash commands as `system`/`local_command` records with their `<local-command-stdout>`), the TUI's
screen (2.1.292's own, from Spikes/chat-mode/screens/slash-2.1.292/) and meta.json. ChatTargets plays
them as `--state chat-slash-<board>`; scripts/check-chat.sh compares them.

  python3 scripts/make-chat-slash-fixtures.py
"""
import json, pathlib, datetime

root = pathlib.Path(__file__).resolve().parent.parent
out = root / "docs/design/chat-slash-handoff/fixture-chat"
tui = root / "Spikes/chat-mode/screens/slash-2.1.292"
idle = (root / "docs/design/chat-mode-handoff/fixture-chat/composer/screen.txt").read_text()
CWD = "/Users/pm/work/payments/checkout-redesign"
DAY = datetime.datetime(2026, 10, 6, tzinfo=datetime.timezone.utc)


def iso(hm, s=0):
    h, m = map(int, hm.split(":"))
    return (DAY + datetime.timedelta(hours=h, minutes=m, seconds=s)).strftime("%Y-%m-%dT%H:%M:%S.000Z")


class Rec:
    def __init__(self):
        self.t = []

    def say(self, hm, text):
        self.t.append({"type": "assistant", "message": {"model": "claude-opus-5-5", "content": [{"type": "text", "text": text}]}, "timestamp": iso(hm), "cwd": CWD})

    def command(self, hm, name, args="", out=None):
        self.n = getattr(self, "n", 0) + 2   # each command and its output a moment apart, in order
        self.t.append({"type": "system", "subtype": "local_command", "timestamp": iso(hm, self.n), "cwd": CWD,
                       "content": f"<command-name>{name}</command-name>\n            <command-message>{name[1:]}</command-message>\n            <command-args>{args}</command-args>"})
        if out is not None:
            self.t.append({"type": "system", "subtype": "local_command", "timestamp": iso(hm, self.n + 1), "cwd": CWD,
                           "content": f"<local-command-stdout>{out}</local-command-stdout>"})

    def write(self, board, meta, screen=idle):
        d = out / ("slash-" + board)
        d.mkdir(parents=True, exist_ok=True)
        (d / "transcript.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in self.t))
        (d / "meta.json").write_text(json.dumps({"mode": "chat", "tab": "PRD v2 edits", **meta}, indent=1, ensure_ascii=False) + "\n")
        (d / "screen.txt").write_text(screen)


CONTEXT_OPUS = """Context Usage
⛁ ⛁ ⛁ ⛁ ⛀ ⛶ ⛶ ⛶ ⛶ ⛶   Opus 5.5
⛁ ⛁ ⛁ ⛁ ⛁ ⛶ ⛶ ⛶ ⛶ ⛶   claude-opus-5-5
⛁ ⛁ ⛁ ⛁ ⛁ ⛶ ⛶ ⛶ ⛶ ⛶   84k/200k tokens (42%)
⛁ ⛁ ⛁ ⛁ ⛁ ⛶ ⛶ ⛶ ⛶ ⛶
⛁ ⛁ ⛁ ⛁ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶   Estimated usage by category
⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶   ⛁ System prompt: 3.1k tokens (1.6%)
⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶   ⛁ Skills: 1.5k tokens (0.8%)
⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶   ⛁ Messages: 78k tokens (39.0%)
⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶   ⛶ Free space: 116k (58.0%)
⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶

Skills · /skills
└ 13 skills · 1.5k tokens

/context all to expand"""

CONTEXT_HAIKU = (tui / "context-stdout.txt").read_text()

# output: one line, a few lines, /context drawn.
r = Rec()
r.command("11:30", "/rename", "notes", "Session renamed to: notes")
r.command("11:30", "/model", "", "Kept model as `Haiku 4.5`")
r.command("11:31", "/output-style", "", "Output styles\n  default       Claude completes tasks efficiently\n  Explanatory   Claude explains its choices\n  Learning      Claude pauses for you to write code")
r.command("11:32", "/context", "", CONTEXT_OPUS)
r.write("output", {"now": iso("11:33")})

# context: 2.1.292's real record (with its colour codes), in a fresh session.
r = Rec()
r.command("11:32", "/context", "", CONTEXT_HAIKU)
r.write("context", {"now": iso("11:33")})

# model-card: /model's own screen, the card in the composer's place.
r = Rec()
r.say("11:29", "Both drafts are in `docs/prd-v2.md`. The rollout section still needs the beta numbers.")
r.command("11:30", "/model")
r.write("model-card", {"now": iso("11:30", 20)}, (tui / "model.txt").read_text())

# effort-card: /effort's slider.
r = Rec()
r.command("11:30", "/effort")
r.write("effort-card", {"now": iso("11:30", 20)}, (tui / "effort.txt").read_text())

# fallback-named: /permissions in the terminal, the bar naming it.
r = Rec()
r.command("11:30", "/permissions")
r.write("fallback-named", {"now": iso("11:30", 20), "fallback": {"kind": "automatic", "command": "/permissions",
        "message": "/permissions opens in Claude Code’s own screen. Esc closes it and brings chat back."}},
        (tui / "permissions.txt").read_text())

# menu: plugin skills under /de, the TUI's own rows.
rule = "─" * 100
rows = [("❯ ", "/design:design-critique", "Get structured design feedback on usability, hierarchy, and consistency."),
        ("  ", "/design:design-handoff", "Generate developer handoff specs from a design."),
        ("  ", "/design:design-system", "Audit, document, or extend your design system."),
        ("  ", "/deep-research", "[dynamic workflow] Deep research harness — fan-out")]
menu = "\n".join(f"  {c}{n:<28}{d}" for c, n, d in rows)
screen = "\n" * 20 + menu + f"\n{rule}\n❯ /de \n{rule}\n  ⏸ manual mode on\n"
r = Rec()
r.write("menu", {"now": iso("11:30"), "drafts": {"composer": "/de"}, "focusComposer": True}, screen)
print(out)
