#!/usr/bin/env python3
"""Writes a long Claude Code session's transcript for chat mode's performance runs (F-157).

Its shape follows long real agent sessions (a 150 MB transcript: ~95 prompts, ~3,500 tool calls,
70% Bash, thinking before most calls, short text blocks with the odd long one), but every word is
generated: no real transcript text, since the repo is public.

  python3 scripts/make-long-chat.py <out.jsonl> [--turns 95] [--tools 37] [--seed 1]

--tools is the mean number of tool calls per turn; --heavy makes command outputs as large as
the largest real sessions' (the transcript grows to about 150 MB).
"""
import argparse, datetime, json, random

CWD = "/Users/pm/work/payments/checkout-redesign"
WORDS = ("the checkout flow card wallet sheet token payment retry ledger rollout pane draft review fixture state "
         "session option button field label total refund merchant order quote cache index page step queue build "
         "report check stage branch commit layout spacing column header footer value result error budget").split()
FILES = ["Sources/Checkout/WalletSheet.swift", "Sources/Checkout/CardForm.swift", "Sources/Ledger/Refunds.swift",
         "docs/prd-v2.md", "docs/flows.md", "scripts/rollout.sh", "Tests/CheckoutChecks/main.swift",
         "Sources/Checkout/Retry.swift", "research/interviews.md", "Package.swift"]


def words(r, n):
    return " ".join(r.choice(WORDS) for _ in range(n))


def sentence(r):
    s = words(r, r.randint(6, 18))
    if r.random() < .3:
        s += f" in `{r.choice(FILES)}`"
    if r.random() < .2:
        s += " **" + words(r, 2) + "**"
    return s[0].upper() + s[1:] + "."


def code_line(r):
    return r.choice(["let {a} = {b}.{c}({d})", "if {a}.isEmpty {{ return {b} }}", "for {a} in {b} {{ {c}.append({a}) }}",
                     "func {a}(_ {b}: String) -> {c} {{", "    {a}[{b}] = {c}", "}}", "// {a} {b} {c}"]).format(
        a=r.choice(WORDS), b=r.choice(WORDS), c=r.choice(WORDS).capitalize(), d=r.choice(WORDS))


def markdown(r, long=False):
    """A reply: mostly a short paragraph; sometimes headings, lists, code and a table."""
    if not long:
        return " ".join(sentence(r) for _ in range(r.randint(1, 3)))
    out = [f"## {words(r, 3).capitalize()}", " ".join(sentence(r) for _ in range(r.randint(2, 5)))]
    out += [f"- {sentence(r)}" for _ in range(r.randint(3, 8))]
    out += ["```swift"] + [code_line(r) for _ in range(r.randint(6, 30))] + ["```"]
    cols = r.randint(3, 5)
    out += ["| " + " | ".join(words(r, 1).capitalize() for _ in range(cols)) + " |", "|" + "---|" * cols]
    out += ["| " + " | ".join(words(r, r.randint(1, 4)) for _ in range(cols)) + " |" for _ in range(r.randint(3, 12))]
    out += [f"{i + 1}. {sentence(r)}" for i in range(r.randint(2, 6))]
    out += [" ".join(sentence(r) for _ in range(r.randint(1, 4)))]
    return "\n".join(out[:2]) + "\n\n" + "\n".join(out[2:])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--turns", type=int, default=95)
    ap.add_argument("--tools", type=int, default=37)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--heavy", action="store_true", help="outputs the size of the largest real sessions' (p90 ~17 KB, a ~150 MB transcript)")
    a = ap.parse_args()
    r = random.Random(a.seed)
    t = datetime.datetime(2026, 10, 1, 9, 0, tzinfo=datetime.timezone.utc)
    lines, n = [], 0

    def stamp():
        nonlocal t
        t += datetime.timedelta(seconds=r.randint(1, 20))
        return t.strftime("%Y-%m-%dT%H:%M:%S.000Z")

    def asst(content):
        lines.append({"type": "assistant", "message": {"model": "claude-opus-5-5", "role": "assistant", "content": content}, "timestamp": stamp(), "cwd": CWD})

    for turn in range(a.turns):
        lines.append({"type": "user", "message": {"role": "user", "content": " ".join(sentence(r) for _ in range(r.randint(1, 4)))},
                      "timestamp": stamp(), "origin": {"kind": "human"}, "cwd": CWD})
        k = max(1, int(r.expovariate(1 / a.tools)))
        for c in range(k):
            if r.random() < .8:
                asst([{"type": "thinking", "thinking": ""}])
                lines[-1]["thinkingDurationMs"] = r.randint(800, 12000)
            if r.random() < .3:
                asst([{"type": "text", "text": markdown(r, long=r.random() < .08)}])
            n += 1
            tid = f"toolu_{a.seed}_{n:06d}"
            kind = r.choices(["Bash", "Read", "Edit", "Write", "Grep", "Agent", "mcp__x__update"], [70, 9, 8, 4, 4, 1, 4])[0]
            f = f"{CWD}/{r.choice(FILES)}"
            if kind == "Bash":
                inp = {"command": f"{r.choice(['swift build', 'scripts/check.sh', 'git log --oneline', 'grep -rn', 'python3 scripts/run.py'])} {r.choice(WORDS)}"}
                nl = int(min(4000, r.lognormvariate(4.4, 1.6))) if a.heavy else int(min(600, r.lognormvariate(2.5, 1.4)))
                out = "\n".join(words(r, r.randint(3, 14)) for _ in range(nl))
                res, content = {"stdout": out, "stderr": "", "interrupted": False}, out
            elif kind == "Read":
                inp = {"file_path": f}
                nl = r.randint(20, 900)
                body = "\n".join(f"{i + 1}\t{code_line(r)}" for i in range(min(nl, 60)))
                res, content = {"type": "text", "file": {"filePath": f, "content": body, "numLines": nl, "totalLines": nl}}, body
            elif kind == "Edit":
                old = "\n".join(code_line(r) for _ in range(r.randint(1, 12)))
                new = "\n".join(code_line(r) for _ in range(r.randint(1, 20)))
                inp = {"file_path": f, "old_string": old, "new_string": new}
                start = r.randint(1, 400)
                hunk = [" " + code_line(r)] * 3 + ["-" + x for x in old.split("\n")] + ["+" + x for x in new.split("\n")] + [" " + code_line(r)] * 3
                res, content = {"filePath": f, "structuredPatch": [{"oldStart": start, "newStart": start, "lines": hunk}]}, "ok"
            elif kind == "Write":
                body = "\n".join(code_line(r) for _ in range(int(min(800, r.lognormvariate(4.5, .8)))))
                inp = {"file_path": f, "content": body}
                res, content = {"type": "create", "filePath": f, "content": body, "structuredPatch": []}, "ok"
            elif kind == "Grep":
                inp = {"pattern": r.choice(WORDS)}
                fs = [f"{CWD}/{x}" for x in r.sample(FILES, 3)]
                res, content = {"mode": "files_with_matches", "numFiles": 3, "filenames": fs}, "\n".join(fs)
            elif kind == "Agent":
                inp = {"description": words(r, 3), "prompt": words(r, 30), "subagent_type": "general-purpose"}
                msg = markdown(r)
                res, content = {"status": "completed", "content": [{"type": "text", "text": msg}], "totalDurationMs": 40000, "totalToolUseCount": 12}, msg
            else:
                inp = {"doc": words(r, 2), "payload": words(r, 40)}
                res, content = words(r, 20), words(r, 20)
            asst([{"type": "tool_use", "id": tid, "name": kind, "input": inp}])
            lines.append({"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": tid, "content": content, "is_error": False}]},
                          "timestamp": stamp(), "toolUseResult": res, "cwd": CWD})
        asst([{"type": "text", "text": markdown(r, long=r.random() < .5)}])
    with open(a.out, "w") as fh:
        for l in lines:
            fh.write(json.dumps(l) + "\n")
    print(f"{a.out}: {a.turns} turns, {n} tool calls, {len(lines)} lines")


if __name__ == "__main__":
    main()
