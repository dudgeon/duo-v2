#!/usr/bin/env python3
"""Writes the recordings for your Markdown in chat (DL-188): docs/design/chat-markdown-handoff/fixture-chat/md-<board>/.

Your messages with Markdown in them, as Claude Code records them (same format as
scripts/make-chat-fixtures.py): transcript lines, Duo's hook events and meta.json. ChatTargets
plays them as `--state chat-md-<board>`; scripts/check-chat.sh captures them.

  python3 scripts/make-chat-markdown-fixtures.py
"""
import json, pathlib, datetime

root = pathlib.Path(__file__).resolve().parent.parent
out = root / "docs/design/chat-markdown-handoff/fixture-chat"
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
        self.t, self.e = [], []

    def you(self, hm, text, blocks=False):
        content = [{"type": "text", "text": text}] if blocks else text
        self.t.append({"type": "user", "message": {"role": "user", "content": content}, "timestamp": iso(hm), "origin": {"kind": "human"}, "cwd": CWD})

    def say(self, hm, text):
        self.t.append({"type": "assistant", "message": {"model": "claude-opus-5-5", "content": [{"type": "text", "text": text}]}, "timestamp": iso(hm), "cwd": CWD})

    def hook(self, hm, s, **e):
        self.e.append({"at": epoch(hm, s), "e": {"session_id": "fixture", "cwd": CWD, **e}})

    def write(self, board, meta):
        d = out / board
        d.mkdir(parents=True, exist_ok=True)
        (d / "transcript.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in self.t))
        (d / "events.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in self.e))
        (d / "meta.json").write_text(json.dumps(meta, indent=1, ensure_ascii=False) + "\n")


BLOCKS = """## Saved cards, next pass

Rework the **non-goals** in `docs/prd-v2.md`:
- drop #3, it ~~repeats~~ restates #1
- keep wallets out
  - but log an open question
1. Read the interviews first
2. Then the [Stripe guide](https://stripe.com/docs/refunds)

> P2: “I’m not typing a card number on my phone again.”

```
refund.threshold = 500
```"""

TABLE = """Put these in a table:

| Flow | Confirms |
|---|---|
| Self-serve | Buyer |
| Assisted | Support |

- [ ] check the numbers
- [x] name the owner"""

LONG = "\n".join(["Checklist for the rollout section:"] + [f"- step {i}: **owner** and `date`" for i in range(1, 7)]
                 + ["", "```", "flag = guest_saved_cards", "rollout = 10%", "```", "", "> Ask support before 50%.", "Thanks!"])

# history: your messages as the transcript replays them (opening a session that has history).
r = Rec()
r.you("10:02", BLOCKS)
r.say("10:02", "Done.")
r.you("10:05", TABLE, blocks=True)
r.say("10:05", "Done.")
r.write("md-history", {"mode": "chat", "tab": "PRD v2 edits"})

# live: the same messages as the prompt hook brings them, with no transcript yet.
r = Rec()
r.hook("10:02", 0, hook_event_name="UserPromptSubmit", prompt=BLOCKS, source="user")
r.hook("10:02", 1, hook_event_name="Stop", last_assistant_message="Done.")
r.hook("10:05", 0, hook_event_name="UserPromptSubmit", prompt=TABLE, source="user")
r.write("md-live", {"mode": "chat", "tab": "PRD v2 edits"})

# long: over 12 lines, cut at 8 with Show all (inside the list, before the fence).
r = Rec()
r.you("10:10", LONG)
r.say("10:10", "On it.")
r.write("md-long", {"mode": "chat", "tab": "PRD v2 edits"})
# composer: section B of composer.html, typed in the composer (focused, caret at the end), and C's wrapped bullet.
COMPOSER = """## Saved cards, next pass
Rework the **non-goals** in `docs/prd-v2.md`:
- drop #3, it restates #1
- keep wallets out
  - but log an open question
1. Read the interviews first
2. Then the [Stripe guide](https://stripe.com/docs/refunds)
> P2: “I’m not typing a card number on my phone again.”
```
refund.threshold = 500
```"""
WRAP = """Before Friday:
- check whether the guest flow keeps the card form on one page, as the interviews asked, and say which screens change
- name an owner"""
FENCE = "\n".join(COMPOSER.split("\n")[-4:])   # the quote and the fence, which the eight-line field scrolls past in md-composer
for board, draft in (("md-composer", COMPOSER), ("md-composer-wrap", WRAP), ("md-composer-fence", FENCE)):
    r = Rec()
    r.you("10:50", "Tighten the non-goals.")
    r.say("10:50", "Done: non-goal #3 is gone.")
    r.write(board, {"mode": "chat", "tab": "PRD v2 edits", "drafts": {"composer": draft}, "focusComposer": True})
print("wrote md boards")
