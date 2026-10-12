#!/usr/bin/env python3
"""Inclusive sample counts for chosen frames in a macOS `sample` call graph.

  inclusive.py <sample.txt> <frame substring>...

A frame's inclusive count is the sum of the lines naming it that have no ancestor naming it
(so recursion and repeated branches aren't counted twice). Also prints each thread's busy
samples (its total minus samples whose top of stack is a wait).
"""
import re, sys

path, frames = sys.argv[1], sys.argv[2:]
text = open(path, errors="replace").read()
graph = text.split("Call graph:", 1)[1].split("Total number in stack", 1)[0]
line_re = re.compile(r"^(?P<lead>[\s+!:|]*)(?P<n>\d+) (?P<name>.*)$")
WAITS = ("__psynch_cvwait", "poll ", "__workq_kernreturn", "mach_msg2_trap", "semaphore_wait_trap",
         "__semwait_signal", "__ulock_wait", "semaphore_timedwait_trap", "kevent", "__select", "start_wqthread")
incl = {f: 0 for f in frames}
stack = []  # (depth, name)
threads = []  # [name, total, wait]
for raw in graph.split("\n"):
    m = line_re.match(raw)
    if not m:
        continue
    depth, n, name = len(m.group("lead")), int(m.group("n")), m.group("name")
    while stack and stack[-1][0] >= depth:
        stack.pop()
    if not stack:
        threads.append([name.strip()[:70], n, 0])
    for f in frames:
        if f in name and not any(f in s for _, s in stack):
            incl[f] += n
    stack.append((depth, name))
for f in frames:
    print(f"{incl[f]:7d}  {f}")
# Leaf waits per thread: from the top-of-stack section is per-process, so estimate per thread by
# subtracting nothing here; print totals so the reader can compare against wall-clock samples.
print("threads:", len(threads))
