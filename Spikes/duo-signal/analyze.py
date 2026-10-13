#!/usr/bin/env python3
"""The duo-signal spike's numbers (ENH-70): from live.sh runs' stderr (signal-trace lines), how long
after the screen first shows a dialog chat's card is up, and when busy and idle reach chat against
the screen's own reading. Usage: analyze.py <run dir>... (each holds stderr.txt)"""
import re, sys, statistics as st

def events(path):
    out = []
    for l in open(path, errors="replace"):
        m = re.match(r"signal-trace (\d+) (\S+) (.*)", l.strip())
        if m:
            out.append((int(m.group(1)), m.group(2), m.group(3)))
    return out

card, busy_lead, idle_lead, req_lead = [], [], [], []
for run in sys.argv[1:]:
    ev = events(run + "/stderr.txt")
    # Card: from the screen's dialog to chat's card=true.
    for i, (t, what, d) in enumerate(ev):
        if what == "screen" and d in ("permission", "question"):
            up = next((t2 for t2, w2, d2 in ev[i:] if w2 == "chat" and d2.endswith("card=true")), None)
            if up is not None and up - t < 3000:
                card.append((run.rsplit("/", 1)[-1], d, up - t))
            hook = [t2 for t2, w2, d2 in ev[i - 3:i + 12] if w2 == "pending"]
            sig = [t2 for t2, w2, d2 in ev[i - 3:i + 12] if w2 == "request"]
            if len(hook) >= 1 and sig:
                req_lead.append(max(hook) - min(sig))
    # Busy and idle: signal vs the screen reader, each transition.
    for i, (t, what, d) in enumerate(ev):
        if what == "signal" and "question=-" in d:
            b = "busy=true" in d
            prev = [(t2, d2) for t2, w2, d2 in ev[max(0, i - 6):i + 6] if w2 == "screen" and d2 == ("busy" if b else "idle")]
            if prev:
                (busy_lead if b else idle_lead).append(min(prev, key=lambda x: abs(x[0] - t))[0] - t)

def show(name, xs):
    if xs:
        print(f"{name}: n={len(xs)} median={st.median(xs):.0f} ms min={min(xs)} max={max(xs)}  {xs}")
    else:
        print(f"{name}: none")

for r, k, ms in card:
    print(f"card {r} {k}: {ms} ms after the dialog drew")
show("card after dialog", [c[2] for c in card])
show("hook request after signal request (signal's lead)", req_lead)
show("screen busy minus signal busy (+ = signal first)", busy_lead)
show("screen idle minus signal idle (+ = signal first)", idle_lead)
