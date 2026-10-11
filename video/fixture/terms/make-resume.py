#!/usr/bin/env python3
"""S8: renders Claude Code's own screens for Sam's home folder, as the installed CLI draws them: the banner of
`claude` started in ~, and the `claude --resume` picker (top, then one screen down). It fills a scratch config
with world.json's homeSessions (cwd ~), runs the CLI in a pty with HOME and CLAUDE_CONFIG_DIR scratch (nothing of
the real ~/.claude is read or written, and no turn is sent), and reads the screen with pyte.
Run: uv run -q --with pyte video/fixture/terms/make-resume.py   Writes terms/s8-*.txt."""
import fcntl, json, os, pathlib, pty, re, select, shutil, struct, sys, tempfile, termios, time, uuid
import pyte

HERE = pathlib.Path(__file__).resolve().parent
W = json.loads((HERE.parent / "world.json").read_text())
HS = W["homeSessions"]
COLS, ROWS = 100, 32
CLI = os.path.expanduser("~/.local/bin/claude")


def filler(i, k):
    """A reply of a plausible size (real sessions carry tool output too), so the picker's sizes read like real ones."""
    return ("Here is what I found. " * (60 + (i * 37 + k * 11) % 140)).strip()


def fill(cfg, home):
    real = os.path.realpath(home)
    proj = pathlib.Path(cfg) / "projects" / re.sub(r"[^A-Za-z0-9]", "-", real)
    proj.mkdir(parents=True)
    now = time.time()
    for i, s in enumerate(HS["sessions"]):
        sid = str(uuid.UUID(int=0x5a3000000000400080000000000000 + i))
        end = now - s["age"] * 60
        start = end - s["msgs"] * 45
        lines, parent = [], None
        for k in range(s["msgs"]):
            t = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(start + k * 45))
            u = str(uuid.UUID(int=(i << 32) + k + 1))
            user = k % 2 == 0
            msg = ({"role": "user", "content": s["prompt"] if k == 0 else "Thanks, go on."} if user else
                   {"role": "assistant", "model": "claude-opus-5-5", "content": [{"type": "text", "text": filler(i, k)}]})
            lines.append({"type": "user" if user else "assistant", "uuid": u, "parentUuid": parent, "sessionId": sid, "cwd": real,
                          "version": "2.1.296", "isSidechain": False, "userType": "external", "message": msg, "timestamp": t})
            parent = u
        lines.append({"type": "ai-title", "aiTitle": s["title"], "sessionId": sid})
        f = proj / f"{sid}.jsonl"
        f.write_text("\n".join(json.dumps(l) for l in lines) + "\n")
        os.utime(f, (end, end))


def run(home, cfg, args, keys):
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(home)
        env = {k: v for k, v in os.environ.items() if not k.startswith(("CLAUDE", "ANTHROPIC", "DUO_"))}
        env.update(HOME=home, CLAUDE_CONFIG_DIR=cfg, TERM="xterm-256color", COLUMNS=str(COLS), LINES=str(ROWS))
        os.execve(CLI, ["claude", *args], env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
    scr = pyte.Screen(COLS, ROWS); st = pyte.ByteStream(scr)
    def pump(t):
        end = time.time() + t
        while time.time() < end:
            if select.select([fd], [], [], 0.1)[0]:
                try: st.feed(os.read(fd, 65536))
                except OSError: return
    pump(7)
    shots = []
    for k in keys:
        if k == "SHOT": shots.append("\n".join(l.rstrip() for l in scr.display).rstrip("\n") + "\n"); continue
        os.write(fd, {"DOWN": b"\x1b[B", "ESC": b"\x1b"}.get(k, k.encode())); pump(0.4)
    os.kill(pid, 15); pump(1)
    try: os.waitpid(pid, 0)
    except ChildProcessError: pass
    return shots


def main():
    with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR")) as t:
        home, cfg = os.path.join(t, "sam"), os.path.join(t, "cfg")
        os.makedirs(home); os.makedirs(cfg)
        real = os.path.realpath(home)
        (pathlib.Path(cfg) / ".claude.json").write_text(json.dumps({"hasCompletedOnboarding": True, "theme": "dark",
            "projects": {real: {"hasTrustDialogAccepted": True}}}))
        fill(cfg, home)
        banner, = run(home, cfg, ["--model", "claude-opus-5-5"], ["SHOT"])
        n = int(os.environ.get("S8_DOWN", "12"))
        top, down = run(home, cfg, ["--resume"], ["SHOT"] + ["DOWN"] * n + ["SHOT"])
    # The scratch run isn't signed in and its HOME isn't the account's: Sam's banner names his plan (as S2's
    # screens do) and his home as ~. The one-time auto-mode notice is gone: Sam has used Claude Code before.
    b = banner.splitlines()
    b[1] = re.sub(r"·.*$", "· Claude Max", b[1])
    b[2] = re.sub(r"(\s{3})[/~]\S*$", r"\1~", b[2])
    b = [l for l in b if not l.startswith("▎")]
    while len(b) > 4 and b[3] == "" and b[4] == "": del b[4]
    b = [re.sub(r"\s+Not logged in · Run /login\s*$", "", l) for l in b]
    banner = "\n".join(b) + "\n"
    for name, text in [("s8-banner.txt", banner), ("s8-resume-top.txt", top), ("s8-resume-scrolled.txt", down)]:
        (HERE / name).write_text(text)
        print("wrote", name)


if __name__ == "__main__":
    main()
