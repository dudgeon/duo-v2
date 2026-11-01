#!/usr/bin/env python3
"""A recorded Claude Code screen whose prompt takes what's pasted into it, as Claude's input box shows it.

The 0.2.22 film's terminal (VideoTargets+Voice.swift) runs this in a real shell tab, so voice input's real
delivery (each settled phrase one bracketed paste) lands in the prompt row the way it does in Claude Code.
  prompt-echo.py <screen.ans>
Draws the screen, puts the cursor after the last prompt marker, then echoes printable pasted text there.
"""
import os, sys, tty

screen = open(sys.argv[1], encoding="utf-8").read()
rows = screen.split("\n")
prompt = max(i for i, r in enumerate(rows) if "❯" in r)
os.write(1, ("\x1b[2J\x1b[H" + screen.replace("\n", "\r\n") + f"\x1b[{prompt + 1};3H").encode())
tty.setraw(0)
pending = b""
while True:
    chunk = os.read(0, 1024)
    if not chunk:
        break
    pending = (pending + chunk).replace(b"\x1b[200~", b"").replace(b"\x1b[201~", b"")
    cut = pending.rfind(b"\x1b")
    emit, pending = (pending[:cut], pending[cut:]) if cut >= 0 and len(pending) - cut < 6 else (pending, b"")
    emit = bytes(c for c in emit if c >= 32)
    if emit:
        os.write(1, emit)
