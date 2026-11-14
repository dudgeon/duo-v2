#!/usr/bin/env python3
"""Writes scenes/*.html for the Home agent panel walkthrough. The All projects window (.ap) is shared; each scene
adds its own callouts and states. Run from this folder: python3 make-scenes.py"""
import os

def win(left=20, top=24, w=600, h=270, extra_tb=""):
    return f'''<div class="win ap c-none" id="ap" data-f style="left:{left}px;top:{top}px;width:{w}px;height:{h}px">
  <div class="tb" id="ap-tb"><span id="sbb" data-f>▯</span> All projects <span style="color:#c2410c">● 3 need you</span>{extra_tb}</div>
  <div class="bd">
    <div class="hc" id="hc" data-f>
      <span class="hh">★ home</span>
      <span class="bub">What came in overnight?</span>
      <span class="ans">Five new asks. Two are yours.</span>
      <span class="qb" id="hq">Route the three to their projects?</span>
      <div id="startcard" class="card" style="display:none"><b>Home's agent</b><br>Nothing runs until you start it.<br><span class="chip" style="height:22px;font-size:12px;margin-top:4px">Start Home's Agent</span></div>
    </div>
    <div class="mid" id="mid" data-f>
      <span class="nr" id="newrow" data-f>New session in ★ home ⌄</span>
      <div class="lr" id="ghost"><span>▭</span><span>Session 8:05 PM</span><span>★ home · at prompt</span></div>
      <div class="lr"><span>○</span><span>Teardown research</span><span>working</span></div>
      <div class="lr"><span>○</span><span>Edge-case matrix</span><span>working</span></div>
      <div class="lr"><span>◆</span><span>Results readout</span><span>25m</span></div>
      <div class="lr"><span>–</span><span>Weekly status draft</span><span>★ home</span></div>
    </div>
    <div class="rp" id="rp" data-f>
      <span class="lab2">Needs you · 3</span>
      <div class="card home" id="homecard">● Morning triage<br>← Waiting in the Home pane</div>
      <div class="card" id="homefull" style="display:none">● Morning triage · ★ home<div class="q">Route the three to their projects?</div></div>
      <div class="card">● Copy review pass 2<div class="q">Approve 6 changes?</div></div>
    </div>
  </div>
</div>'''

BASE = '''
#ghost { display: none; }
[data-state~="closed"] #hc, [data-state~="c"] #hc { width: 0; padding: 0; border: none; opacity: 0; }
[data-state~="ghost"] #ghost { display: flex; }
[data-state~="c"] #homecard, [data-state~="home"] #homecard { display: none; }
[data-state~="c"] #homefull, [data-state~="home"] #homefull { display: block !important; }
[data-state~="c"] #sbb, [data-state~="nosbb"] #sbb { visibility: hidden; }
[data-state~="b"] #hc > span:not(.hh) { display: none; }
[data-state~="b"] #startcard { display: block !important; }
[data-state~="d"] #hc { width: 42%; }
#ap-tb span#sbb { display: inline-block; }
'''

scenes = {}

scenes["why"] = f'''<style>{BASE}
#q1 {{ left: 20px; top: 306px; width: 290px; }} #q2 {{ left: 330px; top: 306px; width: 290px; }}
</style>
{win()}
<div class="call" id="q1" data-in="up" data-f>Nov 3 · “not sure most users will use it … strange workarounds” (ENH-322)</div>
<div class="call" id="q2" data-in="up" data-f>Today · “gate it in system prefs or require a more proactive user intervention”</div>'''

scenes["costs"] = f'''<style>{BASE}
#c1 {{ left: 20px; top: 306px; width: 190px; }} #c2 {{ left: 225px; top: 306px; width: 190px; }} #c3 {{ left: 430px; top: 306px; width: 190px; }}
</style>
{win()}
<div class="call" id="c1" data-in="up" data-f><b>Narrow.</b> 38–43 columns: 2–4 of 17 questions fall back</div>
<div class="call" id="c2" data-in="up" data-f><b>Two places.</b> One terminal, two slots: Oliver's black terminal</div>
<div class="call" id="c3" data-in="up" data-f><b>Unseen.</b> Closed, yet Home's Claude starts at launch</div>'''

def card(i, k, t, rec=False):
    return f'<div class="opt5{" rec" if rec else ""}" id="o{k}" data-in="up" data-f style="left:{20 + i * 122}px;top:110px"><b>{k}</b><span>{t}</span></div>'

scenes["options"] = '''<style>
#ot { left: 20px; top: 40px; } #rec { left: 20px; top: 270px; width: 600px; }
</style>
<div class="h" id="ot" data-in="up">Five ways out</div>
''' + "\n".join([card(0, "A", "A Settings switch"), card(1, "B", "Start it only when asked"),
                 card(2, "C", "Home's page only", False), card(3, "D", "Keep it, make it fit"), card(4, "E", "A Sessions view, later")]) + '''
<div class="call" id="rec" data-in="up" data-f>Recommended: C. The deliberate action already exists: New session in ★ home.</div>'''

scenes["q498"] = f'''<style>{BASE}
#set {{ left: 330px; top: 196px; width: 280px; z-index: 5; }}
[data-state~="a"] #set {{ opacity: 1; }} #set {{ opacity: 0; transition: opacity .5s; }}
#lab {{ left: 20px; top: 314px; width: 600px; text-align: center; }}
</style>
{win()}
<div class="call" id="set">Settings › Home<br>☐ Show Home's agent at All projects</div>
<div class="mlabel" id="lab" data-in="up">Sketches: canvas boards C1, A, B and D2</div>'''

scenes["q499"] = '''<style>
#cap { left: 20px; top: 24px; width: 600px; height: 280px; }
#proc { left: 40px; top: 236px; z-index: 5; }
#start { left: 380px; top: 236px; z-index: 5; }
#lab { left: 20px; top: 318px; width: 600px; text-align: center; }
</style>
<div class="win c-none" id="cap" data-f><div class="tb">A fresh Duo, Home's column closed (F-648)</div><div class="bd"><img class="cap" src="{{f648}}" alt="All projects on a fresh isolated Duo, with a session nobody started"></div></div>
<div class="stamp" id="proc" data-in="scale" data-f>claude --session-id … in ★ home, at launch</div>
<div class="call" id="start" data-in="scale" data-f>Home's page: Start Claude in Home</div>
<div class="mlabel" id="lab" data-in="up">Checked with a stub claude: no real Claude, no tokens</div>'''

scenes["q500"] = '''<style>
#note { left: 30px; top: 70px; width: 270px; }
#line { left: 340px; top: 70px; width: 270px; }
#sub { left: 30px; top: 260px; width: 580px; }
</style>
<div class="call" id="note" data-in="left" data-f><b>Release note</b><br>Home's agent now lives on Home's page: ★ home in the list, or ⇧⌘H.</div>
<div class="call" id="line" data-in="right" data-f><b>A one-time line</b><br>At All projects, for installs whose column was open. New, so it needs drawing.</div>
<div class="s" id="sub" data-in="up">DL-315 already closed the column for everyone who hadn't touched it.</div>'''

scenes["q501"] = f'''<style>{BASE}
#lab {{ left: 20px; top: 314px; width: 600px; text-align: center; }}
</style>
{win()}
<div class="mlabel" id="lab" data-in="up">⌃⌘S and duo2 view sidebar at All projects</div>'''

scenes["q488"] = '''<style>
#t { left: 30px; top: 30px; }
#b38 { left: 30px; top: 100px; width: 190px; } #b43 { left: 30px; top: 150px; width: 215px; } #b60 { left: 30px; top: 200px; width: 300px; }
.n { position: absolute; font-size: 18px; font-weight: 600; }
#n38 { left: 360px; top: 104px; color: #c2410c; } #n43 { left: 360px; top: 154px; color: #c2410c; } #n60 { left: 360px; top: 204px; }
#f641 { left: 30px; top: 270px; width: 580px; }
</style>
<div class="h" id="t" data-in="up">Questions that fall back, of 17</div>
<div class="bar" id="b38" data-in="grow" data-f>38 columns</div>
<div class="bar" id="b43" data-in="grow" data-f>43 columns</div>
<div class="bar" id="b60" data-in="grow" data-f>60 columns</div>
<div class="n" id="n38" data-in="fade">4</div><div class="n" id="n43" data-in="fade">2</div><div class="n" id="n60" data-in="fade">0</div>
<div class="call" id="f641" data-in="up" data-f>Held at 43, shown at 38: every switch redraws (F-641)</div>'''

scenes["wrap"] = '''<style>
#done { left: 40px; top: 30px; } #list { left: 40px; top: 84px; width: 560px; }
</style>
<div class="h" id="done" data-in="up">That's all five</div>
<div id="list" data-dw="answers" data-in="up" data-f></div>'''

os.makedirs("scenes", exist_ok=True)
for k, v in scenes.items():
    open(f"scenes/{k}.html", "w").write(v + "\n")
print(len(scenes), "scenes")
