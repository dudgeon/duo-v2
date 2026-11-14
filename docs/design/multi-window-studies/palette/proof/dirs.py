import math, itertools, json, sys
sys.path.insert(0,'.')
import window_palette as w
from distinct import maxc, lab
def build(hues, names, Ll, Ld, capl=0.14, capd=0.12):
    out=[]
    for h,n in zip(hues,names):
        for k in (0,1):
            cl=min((0.10 if k==0 else capl),maxc(Ll[k],h,0.3)*0.92); cd=min(capd,maxc(Ld[k],h,0.3)*0.92)
            out.append({'name': n if k==0 else 'Deep '+n.lower(), 'h':h,
              'l':w.hexc(Ll[k],cl,h)[0],'d':w.hexc(Ld[k],cd,h)[0],
              'pl':w.hexc(0.965,0.018,h)[0],'pd':w.hexc(0.235,0.022,h)[0]})
    return out
def stats(cols,key):
    pts=[lab(*w.hex_to_oklch(c[key])) for c in cols]
    ds=sorted(math.dist(a,b)*100 for a,b in itertools.combinations(pts,2))
    return round(ds[0],1), round(sum(d>=15 for d in ds)/len(ds)*100)
P=json.load(open('palette.json'))
cur=[{'name':c['name'],'h':c['hue'],'l':c['light']['ground'],'d':c['dark']['ground'],'pl':c['light']['pane'],'pd':c['dark']['pane']} for c in P['colours']]
o2=build([95,130,195,245,300,350],['Yellow','Green','Teal','Blue','Violet','Pink'],(0.88,0.72),(0.50,0.36))
o3=build([20,75,135,185,250,315],['Coral','Ochre','Green','Teal','Blue','Purple'],(0.86,0.72),(0.50,0.36))
res={}
for k,c in (('cur',cur),('o2',o2),('o3',o3)):
    res[k]={'cols':c,'light':stats(c,'l'),'dark':stats(c,'d')}
    print(k,res[k]['light'],res[k]['dark'],[x['l'] for x in c])
json.dump(res,open(sys.argv[1],'w'))
