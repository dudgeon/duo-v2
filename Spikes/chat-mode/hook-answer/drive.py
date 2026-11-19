import os, pty, sys, time, select, json, glob
# drive.py <claude> <steps.json> <outdir> args... ; steps: {"type":..,"paste":bool} {"key":"enter|esc"} {"sleep":ms} {"wait":"text","timeout":s}
binp, steps, out = sys.argv[1:4]
args = sys.argv[4:]
os.makedirs(out, exist_ok=True)
pid, fd = pty.fork()
if pid == 0:
    os.environ['COLUMNS'] = '94'; os.environ['LINES'] = '40'
    os.execv(binp, [binp] + args)
import fcntl, termios, struct
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 94, 0, 0))
buf = b''
def pump(t):
    global buf
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try: d = os.read(fd, 65536)
            except OSError: return
            buf += d
            if b'\x1b[6n' in d: os.write(fd, b'\x1b[1;1R')
keys = {'enter': b'\r', 'esc': b'\x1b'}
log = open(out + '/steps.log', 'w')
t0 = time.time()
for s in json.load(open(steps)):
    if 'wait' in s:
        ok = False
        for _ in range(int(s.get('timeout', 20) * 10)):
            pump(0.1)
            if s['wait'].encode() in buf[-200000:]: ok = True; break
        log.write(f"{time.time()-t0:.1f} wait {s['wait']} {'ok' if ok else 'TIMEOUT'}\n")
    if 'type' in s:
        os.write(fd, (b'\x1b[200~' + s['type'].encode() + b'\x1b[201~') if s.get('paste') else s['type'].encode()); log.write(f"type {s['type']}\n")
    if 'key' in s: os.write(fd, keys[s['key']]); log.write(f"key {s['key']}\n")
    if 'sleep' in s: pump(s['sleep'] / 1000)
    if 'beacons' in s:
        cfg = os.environ['CLAUDE_CONFIG_DIR']
        log.write(f"beacon dir {s['beacons']}: {os.listdir(cfg + '/sessions') if os.path.isdir(cfg + '/sessions') else 'none'}\n")
        for f in glob.glob(cfg + '/sessions/*'):
            try: log.write(f"beacon {s['beacons']}: {open(f).read()[:400]}\n")
            except Exception as e: log.write(f"beacon err {e}\n")
open(out + '/raw.bin', 'wb').write(buf)
os.kill(pid, 15)
