from PIL import Image
from collections import deque
R = '/Users/geoff/repos/duo-v2/.claude/worktrees/voice-input'
K = 1.44
T = Image.open(R + '/docs/design/voice-input-handoff/screens/png/composer@2x.png').convert('RGB')
P = R + '/docs/design/voice-input-handoff/proof/'

def flood(img, seed, tol=3):
    c = img.getpixel(seed)
    seen, q = {seed}, deque([seed])
    px = img.load()
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (x + dx, y + dy)
            if n in seen or not (0 <= n[0] < img.width and 0 <= n[1] < img.height): continue
            p = px[n]
            if all(abs(p[i] - c[i]) <= tol for i in range(3)):
                seen.add(n); q.append(n)
    xs = [p[0] for p in seen]; ys = [p[1] for p in seen]
    return c, (min(xs), min(ys), max(xs), max(ys)), len(seen)

def show(label, img, seed):
    c, b, n = flood(img, seed)
    print(f"{label:22} seed fill {c}: {(b[2]-b[0]+1)/2:.1f} x {(b[3]-b[1]+1)/2:.1f} pt, {n} px")
    return b

def d(x, y): return (int(x * K), int(y * K))
tb = show('target hover circle', T, d(1930 - 13, 205 + 12))
bimg = Image.open(P + 'hover-build.png').convert('RGB')
bb = show('build  hover circle', bimg, (1265 - 14, 65 + 14))
print(f"   build circle: right {(bimg.width - bb[2] - 1) / 2:.1f} pt from the crop's right edge")
tl = show('target listening', T, d(952 - 13, 628 + 12))
bl_img = Image.open(P + 'listening-build.png').convert('RGB')
bl = show('build  listening', bl_img, (1265 - 14, 65 + 14))

A = Image.open(R + '/docs/design/voice-input-handoff/screens/png/composer-appearances@2x.png').convert('RGB')
for name, x in (('dark', 1239), ('classic', 1884), ('light', 595)):
    t = show(f'target {name} mic', A, d(x - 12, 273 + 11))
    if name != 'light':
        bi = Image.open(P + f'listening-{name}-build.png').convert('RGB')
        show(f'build  {name} mic', bi, (1265 - 14, 65 + 14))
