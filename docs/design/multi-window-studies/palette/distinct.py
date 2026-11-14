#!/usr/bin/env python3
"""Q-441 round 2: pick window colours for distance, not harmony (Geoff, 2026-11-02).
Farthest-point search in OKLab over every in-gamut colour in the allowed hue arc,
then swap-improvement, maximising the smallest distance between any two toolbars
(and from None's grey, and from needs-you)."""
import math, itertools, json, sys, random
import window_palette as w
def lab(L, C, h): return (L, C*math.cos(math.radians(h)), C*math.sin(math.radians(h)))
def maxc(L, h, cap):
    c = 0
    while c < cap and w.hexc(L, c+0.004, h)[1]: c += 0.004
    return c
HUES = [h for h in range(95, 350, 5)]          # no red/orange/amber: needs-you is h38-48
def candidates(Ls, cap, frac=0.92):
    out = []
    for L in Ls:
        for h in HUES:
            c = maxc(L, h, cap)*frac
            if c >= 0.03: out.append((L, round(c, 4), h))
    return out
def pick(cands, n, avoid):
    P = [lab(*c) for c in cands]; A = [lab(*a) for a in avoid]
    def score(idx):
        pts = [P[i] for i in idx]
        m = min(math.dist(a, b) for a, b in itertools.combinations(pts, 2))
        return min([m] + [math.dist(p, a)*1.0 for p in pts for a in A])
    best = None
    for seed in range(len(cands)):
        idx = [seed]
        while len(idx) < n:
            idx.append(max((i for i in range(len(P)) if i not in idx),
                           key=lambda i: min([math.dist(P[i], P[j]) for j in idx] + [math.dist(P[i], a) for a in A])))
        s = score(idx)
        if not best or s > best[0]: best = (s, idx)
    s, idx = best
    improved = True
    while improved:
        improved = False
        for k in range(n):
            for i in range(len(P)):
                if i in idx: continue
                t = idx[:]; t[k] = i; st = score(t)
                if st > s + 1e-6: s, idx, improved = st, t, True
    return s, [cands[i] for i in idx]
if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "pale":     # A: toolbar keeps text2 at 4.5:1 -> L >= 0.90
        Ls, cap = [0.90, 0.92, 0.94], 0.16
    else:                  # B: deep toolbar, toolbar text in `text`
        Ls, cap = [0.72, 0.76, 0.80, 0.84, 0.88], 0.17
    grey = (0.95, 0, 0) if mode == "pale" else (0.80, 0, 0)
    needs = w.hex_to_oklch("#C2410C")
    s, sel = pick(candidates(Ls, cap), 12, [grey, needs])
    sel.sort(key=lambda c: c[2])
    print(mode, "min dE %.3f" % s)
    for L, C, h in sel:
        print("  L %.2f C %.3f h %3d %s" % (L, C, h, w.hexc(L, C, h)[0]))
