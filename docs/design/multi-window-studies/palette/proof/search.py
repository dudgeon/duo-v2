import math, itertools, random, sys
sys.path.insert(0,'.')
import window_palette as w
from distinct import maxc, lab
from functools import lru_cache
@lru_cache(None)
def col(L,h,cap): c=min(cap, maxc(L,h,0.3)*0.92); return lab(L,c,h)
def mind(pts): return min(math.dist(a,b) for a,b in itertools.combinations(pts,2))*100
HU=list(range(95,351,5))
def score(hues, Ll, Ld, capl=0.14, capd=0.12):
    a=mind([col(L,h,capl) for h in hues for L in Ll]); b=mind([col(L,h,capd) for h in hues for L in Ld]); return min(a,b),a,b
random.seed(1); best=None
for Ll,Ld in [((0.88,0.72),(0.50,0.36)),((0.90,0.74),(0.52,0.36)),((0.88,0.70),(0.48,0.34))]:
  for _ in range(4000):
    hs=sorted(random.sample(HU,6)); s=score(hs,Ll,Ld)
    if not best or s[0]>best[0][0]: best=(s,hs,Ll,Ld)
  # hill-climb
  s,hs,_,_=best if best[2]==Ll else (score(hs,Ll,Ld),hs,Ll,Ld)
print('6x2', best)
# 12 hues, alternating depth
best2=None
for Lpair,Dpair in [((0.86,0.74),(0.48,0.36)),((0.88,0.72),(0.50,0.36))]:
  for _ in range(3000):
    hs=sorted(random.sample(HU,12))
    pl=[col(Lpair[i%2],h,0.14) for i,h in enumerate(hs)]; pd=[col(Dpair[i%2],h,0.12) for i,h in enumerate(hs)]
    s=min(mind(pl),mind(pd))
    if not best2 or s>best2[0]: best2=(s,mind(pl),mind(pd),hs,Lpair,Dpair)
print('12 alt', best2)
print('--- wider hue range, only needs-you +-17 excluded')
HU=[h for h in range(0,360,5) if not (22<=h<=64)]
random.seed(2); best3=None
for Lpair,Dpair in [((0.86,0.72),(0.50,0.36)),((0.88,0.72),(0.50,0.34))]:
  for _ in range(4000):
    hs=sorted(random.sample(HU,6))
    s=score(hs,Lpair,Dpair)
    if not best3 or s[0]>best3[0][0]: best3=(s,hs,Lpair,Dpair)
print('6x2 wide', best3)
HU=list(range(0,360,5)); best4=None
for _ in range(4000):
    hs=sorted(random.sample(HU,6)); s=score(hs,(0.86,0.72),(0.50,0.36))
    if not best4 or s[0]>best4[0][0]: best4=(s,hs)
print('6x2 any hue', best4)
