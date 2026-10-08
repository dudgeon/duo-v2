#!/usr/bin/env python3
# A stand-in Claude Code TUI for scripts/check-scale.sh (F-208): reports 2.1.219 (the version work
# pins), then alternates between its idle prompt and a browser sign-in screen, as the work Mac's
# CLI did on every resume, redrawing on every resize as Ink does. No network, no login.
#   AUTH_UNKNOWN / AUTH_IDLE: seconds on each screen (0.8 / 0.4); AUTH_UNKNOWN=0: the prompt only.
#   AUTH_MODE=spin: busy at 10 Hz under a sign-in wait instead.
import os, sys, time, signal, shutil, random
if len(sys.argv) > 1 and sys.argv[1] in ("--version", "-v"):
    print("2.1.219 (Claude Code)"); sys.exit(0)
UNKNOWN, IDLE = float(os.environ.get("AUTH_UNKNOWN", "0.8")), float(os.environ.get("AUTH_IDLE", "0.4"))
url = "https://claude.ai/oauth/authorize?code=true&client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e&response_type=code&redirect_uri=https%3A%2F%2Fconsole.anthropic.com%2Foauth%2Fcode%2Fcallback&scope=org%3Acreate_api_key+user%3Aprofile+user%3Ainference&state=" + "x" * 40
def draw(auth):
    cols, rows = shutil.get_terminal_size((100, 30))
    out = ["\x1b[2J\x1b[H"]
    if auth:
        out += [" Browser didn't open? Use the url below to sign in (c to copy)", "", " " + url, "", " Paste code here if prompted > "]
    else:
        out += ["╭─── Claude Code v2.1.219 ───╮", "", "⏺ ok", "", "─" * cols, "❯ ", "─" * cols, "  ⏸ manual mode on · ? for shortcuts"]
    sys.stdout.write("\r\n".join(out)); sys.stdout.flush()
state = [False]
if os.environ.get("AUTH_MODE") == "spin":
    # Busy at 10 Hz, as a sign-in or OAuth wait animates: the spinner and its seconds change every frame.
    glyphs = "✻✽✶✳✢·"
    def busy(i):
        cols, _ = shutil.get_terminal_size((100, 30))
        out = ["\x1b[2J\x1b[H", "⏺ Waiting for authentication in your browser…", "  " + url, "",
               f"{glyphs[i % len(glyphs)]} Authenticating… ({i // 10}s · esc to interrupt)", "", "─" * cols, "❯ ", "─" * cols, "  ⏸ manual mode on · ? for shortcuts"]
        sys.stdout.write("\r\n".join(out)); sys.stdout.flush()
    i = 0
    signal.signal(signal.SIGWINCH, lambda *_: busy(i))
    while True:
        busy(i); i += 1; time.sleep(0.1)
signal.signal(signal.SIGWINCH, lambda *_: draw(state[0]))
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
time.sleep(random.random())
if UNKNOWN == 0:
    draw(False)
    while True: time.sleep(3600)
while True:
    state[0] = not state[0]; draw(state[0])
    time.sleep(UNKNOWN if state[0] else IDLE)
