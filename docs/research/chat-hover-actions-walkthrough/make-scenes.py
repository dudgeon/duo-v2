#!/usr/bin/env python3
"""Writes scenes/*.html for the chat hover actions walkthrough. The chat pane (.chat) is drawn after the study's boards
(docs/design/chat-hover-actions-study/project: Row, Rewind, Fork, Copy, Chat, Sheet). Run from this folder: python3 make-scenes.py"""
import os

STROKE = 'fill="none" stroke="#5B636D" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"'
ICON = {
 "copy": f'<svg viewBox="0 0 12 12"><rect x="3.5" y="3.5" width="7" height="7" rx="1.5" {STROKE}/><path d="M8.5 3.5V2A1.5 1.5 0 0 0 7 .5H2A1.5 1.5 0 0 0 .5 2v5A1.5 1.5 0 0 0 2 8.5h1.5" {STROKE}/></svg>',
 "rewind": f'<svg viewBox="0 0 12 12"><path d="M2.2 5.5A4 4 0 1 1 3.4 8.6" {STROKE}/><path d="M1.2 2.6 2.2 5.6 5 4.5" {STROKE}/></svg>',
 "fork": f'<svg viewBox="0 0 12 12"><circle cx="3" cy="2.2" r="1.3" {STROKE}/><circle cx="3" cy="9.8" r="1.3" {STROKE}/><circle cx="9" cy="4" r="1.3" {STROKE}/><path d="M3 3.5v5M9 5.3c0 2-2 2.2-4 2.6L3.6 8.5" {STROKE}/></svg>',
}
def btn(kind, label, id, extra=""):
    return f'<span class="rb{extra}" id="{id}" data-f>{ICON[kind]}{label}</span>'

ASK = "Compare the two refund flows in a table."
REPLY = "Both flows are in docs/refunds/flows.md. Keep self-serve as the default."

def tabs(items):
    return '<div class="tabs" id="tabs">' + "".join(items) + '</div>'

def chat(w=600, h=316, tab_html=None, you=True, claude=True, rows="", comp=True, extra=""):
    t = tabs(tab_html or ['<span class="tab on" id="tab1">Refund flows</span>', '<span class="tab" id="tab3">Teardown research</span>'])
    s = f'<div class="chat" id="chat" style="left:20px;top:26px;width:{w}px;height:{h}px">{t}'
    if you: s += f'<div class="bub" id="you" data-f style="left:{w-440}px;top:42px;width:410px">{ASK}</div>'
    if claude: s += f'<div class="cc" id="cl" data-f style="left:30px;top:128px;width:400px">{REPLY}</div>'
    s += rows
    if comp: s += f'<div class="comp" id="comp" style="left:14px;right:14px;top:{h-62}px">Reply to Claude</div>'
    return s + extra + '</div>'

def rows(rewind=True, fork_you=True, fork_cl=True, more=False, hidden=True):
    d = ' data-in="fade"' if hidden else ""
    ry = (btn("copy", "Copy", "bcy") +
          '<span class="rb more" id="bed" style="display:none" data-f>' + ICON["rewind"] + 'Edit</span>' +
          '<span class="rb more" id="bre" style="display:none" data-f>' + ICON["rewind"] + 'Retry</span>' +
          btn("rewind", "Rewind", "brw") + btn("fork", "Fork", "bfk"))
    rc = btn("copy", "Copy", "bcc") + btn("fork", "Fork", "bfc")
    return (f'<div class="rowb" id="ry"{d} data-f style="right:30px;top:92px">{ry}</div>'
            f'<div class="rowb" id="rc"{d} data-f style="left:30px;top:190px">{rc}</div>')

LAB = '#lbl { left: 20px; top: 352px; width: 600px; text-align: center; }'
scenes = {}

# 1 why
scenes["why"] = f'''<style>#quote {{ left: 20px; top: 350px; width: 600px; }}</style>
{chat(rows=rows())}
<div class="call" id="quote" data-in="up" data-f>“in chat mode I want hover ui for rewind and fork … copy … as raw markdown”</div>'''

# 2 claude
scenes["claude"] = '''<style>
#term { left: 20px; top: 16px; width: 320px; height: 190px; }
#m2 { display: none; } [data-state~="s2"] #m1 { display: none; } [data-state~="s2"] #m2 { display: block; }
#chain { left: 20px; top: 222px; display: flex; gap: 6px; }
[data-state~="rew"] #c3, [data-state~="rew"] #c4 { opacity: .45; border-style: dashed; }
#k1 { left: 355px; top: 16px; width: 265px; } #k2 { left: 355px; top: 100px; width: 265px; }
#k3 { left: 355px; top: 184px; width: 265px; } #k4 { left: 20px; top: 280px; width: 320px; }
#stamp { left: 355px; top: 290px; font-size: 14px; white-space: normal; width: 250px; }
</style>
<div class="term" id="term" data-in="fade" data-f>
<div id="m1"><div class="dm">Restore to the point before…</div>
<div id="p1">  hello</div><div id="p2" data-f class="hl">  write A      a.txt +1</div><div id="p3">  write B      b.txt +1</div><div id="p4">  bash C       No code changes</div><div class="dm">  (current)</div></div>
<div id="m2"><div class="dm">Restore to before this message:</div>
<div id="o1">  1 Restore code and conversation</div><div id="o2" data-f class="hl">  2 Restore conversation</div><div id="o3">  3 Restore code</div><div id="o4">  4 Summarize from here</div><div id="o5">  5 Summarize up to here</div></div>
</div>
<div id="chain" data-in="fade"><span class="step" id="c1">hello</span><span class="step" id="c2">write A</span><span class="step" id="c3">write B</span><span class="step" id="c4">bash C</span></div>
<div class="call" id="k1" data-in="up" data-f>Conversation: the prompt comes back to the box. Removed turns stay in the file, a dead branch.</div>
<div class="call" id="k2" data-in="up" data-f>Code: only what Write and Edit changed. Never Bash. 2.1.316 warns later changes by anyone are lost.</div>
<div class="call" id="k3" data-in="up" data-f>Same on 2.1.284 (the work Mac) and 2.1.316, apart from the wording.</div>
<div class="call" id="k4" data-in="up" data-f>Fork copies it all. A fork at one turn is print mode only: fork whole, then rewind the copy.</div>
<div class="stamp" id="stamp" data-in="scale" data-f>Tried on a mock API, no real Claude</div>'''

# 3 duo
scenes["duo"] = '''<style>
#chat { width: 380px !important; height: 290px !important; }
#n1 { left: 415px; top: 28px; width: 205px; } #n2 { left: 415px; top: 120px; width: 205px; } #n3 { left: 415px; top: 212px; width: 205px; }
#n4 { left: 20px; top: 336px; width: 600px; }
</style>
<div class="chat" id="chat" style="left:20px;top:26px">
<div class="tabs"><span class="tab on">Refund flows</span></div>
<div class="bub" id="you" data-f style="left:90px;top:44px;width:270px">Compare the two refund flows.</div>
<div class="cc" id="cl" data-f style="left:20px;top:100px;width:290px">Both flows are in flows.md.</div>
<span class="tagid" id="t1" data-in="scale" style="left:16px;top:48px">you-12</span>
<span class="tagid" id="t2" data-in="scale" style="left:318px;top:104px;white-space:nowrap">turn-13</span>
<div class="bub dead" id="dyou" data-in="up" data-f style="left:90px;top:158px;width:270px">Make it shorter. (rewound in Claude)</div>
<div class="cc dead" id="dcl" data-in="up" data-f style="left:20px;top:206px;width:290px">Self-serve by default.</div>
<div class="comp" style="left:14px;right:14px;top:248px">Reply to Claude</div>
</div>
<div class="call" id="n1" data-in="up" data-f>No hover row, no menu. Only the code block’s Copy.</div>
<div class="call" id="n2" data-in="up" data-f>Counters like you-12, not Claude’s transcript ids.</div>
<div class="call" id="n3" data-in="up" data-f>Follows file order: rewound turns stay on screen.</div>
<div class="call" id="n4" data-in="up" data-f>First job of any build: show only the live chain of turns.</div>'''

# 4 Q-505
scenes["q505"] = f'''<style>
[data-state~="busy"] #brw, [data-state~="busy"] #bfk {{ color: #5b636d; border-color: #c9cdd3; }}
[data-state~="busy"] #brw svg, [data-state~="busy"] #bfk svg {{ opacity: .55; }}
[data-state~="b"] .more {{ display: inline-flex !important; }}
[data-state~="c"] #brw, [data-state~="c"] #bfk, [data-state~="c"] #bfc {{ display: none; }}
#wk {{ left: 30px; top: 226px; }} #tip {{ right: 30px; top: 118px; font-size: 13px; color: #5b636d; }}
{LAB}
</style>
{chat(rows=rows(), extra='<div class="wk" id="wk" data-in="fade">Reading · 6s · Esc to interrupt</div><div class="wk" id="tip" data-in="fade">When Claude finishes</div>')}
<div class="mlabel" id="lbl" data-in="up">Canvas board 1 · The row on hover</div>'''

# 5 Q-506
scenes["q506"] = f'''<style>
#chat {{ opacity: .45; }}
#sheet {{ left: 110px; top: 40px; width: 420px; }}
#sC {{ display: none; }} [data-state~="c"] #sA {{ display: none; }} [data-state~="c"] #sC {{ display: block; }}
[data-state~="b"] #r2, [data-state~="b"] #sm {{ display: none; }}
[data-state~="a2"] #r1 i {{ border-color: #8b939c; background: none; }}
[data-state~="a2"] #r2 i {{ border-color: #1f2328; background: radial-gradient(#1f2328 4px, transparent 5px); }}
{LAB}
</style>
{chat(comp=True)}
<div class="sheet" id="sheet" data-in="scale" data-f>
<h4>Rewind to before this message?</h4>
<div class="sm" style="margin-bottom:4px">“{ASK}”</div>
<div id="sA">
<div class="rd on" id="r1" data-f><i></i><span>Conversation only</span></div>
<div class="rd" id="r2" data-f><i></i><span>Conversation and 2 files<br><span class="sm">a.txt, b.txt go back to how they were</span></span></div>
<div class="sm" id="sm" data-f>Bash changes aren’t undone. Later changes by anyone are lost.</div>
</div>
<div id="sC" class="mono"><div>1 Restore code and conversation</div><div>2 Restore conversation</div><div>3 Restore code</div><div>4 Summarize from here</div><div>5 Summarize up to here</div></div>
<div class="btns"><span class="btn">Cancel</span><span class="btn pri">Rewind</span></div>
</div>
<div class="mlabel" id="lbl" data-in="up">Canvas board 2 · Rewind, the sheet</div>'''

# 6 Q-507
scenes["q507"] = f'''<style>
#s1 {{ left: 20px; }} #s2 {{ left: 140px; }} #s3 {{ left: 260px; }} #s4 {{ left: 380px; }} #s5 {{ left: 500px; }}
.step {{ position: absolute; top: 24px; width: 112px; height: 52px; display: flex; align-items: center; justify-content: center; }}
#term {{ left: 20px; top: 100px; width: 330px; height: 150px; }}
#m2 {{ display: none; }} [data-state~="s2"] #m1 {{ display: none; }} [data-state~="s2"] #m2 {{ display: block; }}
#fb {{ left: 370px; top: 112px; width: 250px; }} #rd {{ left: 370px; top: 190px; width: 250px; }}
#uf {{ left: 370px; top: 112px; width: 250px; }}
[data-state~="b"] #s3, [data-state~="b"] #s4, [data-state~="b"] #s5 {{ opacity: .3; }}
#lbl {{ left: 20px; top: 280px; width: 600px; text-align: center; }}
</style>
<div class="step" id="s1" data-in="down" data-f>Duo’s sheet</div>
<div class="step" id="s2" data-in="down" data-f>Esc Esc</div>
<div class="step" id="s3" data-in="down" data-f>Pick the prompt</div>
<div class="step" id="s4" data-in="down" data-f>Option 2 or 1</div>
<div class="step" id="s5" data-in="down" data-f>Prompt in composer</div>
<div class="term" id="term" data-in="fade" data-f>
<div id="m1"><div class="dm">Restore to the point before…</div><div>  hello</div><div class="hl">  write A      a.txt +1</div><div>  write B      b.txt +1</div><div>  bash C       No code changes</div></div>
<div id="m2"><div class="dm">Restore to before this message:</div><div>  1 Restore code and conversation</div><div class="hl">  2 Restore conversation</div><div>  3 Restore code</div><div>  4 Summarize from here</div></div>
</div>
<div class="call" id="rd" data-in="up" data-f>Duo reads each screen’s words, on both versions, before it presses anything.</div>
<div class="step dash" id="fb" style="position:absolute;top:112px;height:auto;width:250px" data-in="up" data-f>A screen that doesn’t match? The terminal opens. Duo never guesses.</div>
<div class="call" id="uf" data-in="up" data-f>Claude’s menu opens in the terminal on that message. You finish it.</div>
<div class="mlabel" id="lbl" data-in="up">Canvas board 2 · Rewind, the steps</div>'''

# 7 Q-508
scenes["q508"] = f'''<style>
#tab2 {{ display: none; }} [data-state~="fk"] #tab2 {{ display: block; }}
[data-state~="t2"] #tab1 {{ background: #23262c; color: #c9cdd3; font-weight: 400; }}
[data-state~="t2"] #tab2 {{ background: #f3f4f6; color: #1f2328; font-weight: 600; }}
#compf {{ display: none; }} [data-state~="fill"] #comp {{ display: none; }} [data-state~="fill"] #compf {{ display: block; }}
[data-state~="c"] #bfk {{ display: none; }}
#how {{ left: 20px; top: 352px; width: 600px; }} #unt {{ left: 330px; top: 215px; width: 280px; z-index: 4; }}
#fnote {{ left: 30px; top: 190px; }}
</style>
{chat(tab_html=['<span class="tab on" id="tab1">Refund flows</span>', '<span class="tab fk" id="tab2">Refund flows</span>', '<span class="tab" id="tab3">Teardown research</span>'], rows=rows(), extra='<div class="comp filled" id="compf" style="left:14px;right:14px;top:268px">' + ASK + '</div><div class="wk" id="fnote" data-in="fade">Forked from before your message</div>')}
<div class="call" id="unt" data-in="up" data-f>Fork, then rewind the copy: untested end to end.</div>
<div class="call" id="how" data-in="up" data-f>Fork the whole session with an id Duo mints, then rewind the copy, conversation only.</div>'''

# 8 Q-509
scenes["q509"] = '''<style>
#src { left: 20px; top: 20px; width: 290px; }
#src .th { color: #8b939c; font-style: italic; }
#src .tl { font: 13px/18px ui-monospace, "SF Mono", Menlo, monospace; color: #5b636d; margin-top: 6px; }
#clip { left: 330px; top: 20px; width: 290px; height: 130px; }
#cl-tool { display: none; } [data-state~="b"] #cl-tool { display: block; }
#alt { left: 330px; top: 170px; }
#img { left: 20px; top: 190px; width: 290px; }
#lbl { left: 20px; top: 352px; width: 600px; text-align: center; }
</style>
<div class="cc" id="src" data-in="up" data-f>
<div class="th" id="seg-think" data-f>Thinking about the two flows…</div>
<div id="seg-text" data-f style="margin-top:6px">Both flows are in docs/refunds/flows.md.<br><br>Keep self-serve as the default.</div>
<div class="tl" id="seg-tool" data-f>Ran npm test</div>
</div>
<div class="clip" id="clip" data-in="up" data-f>Both flows are in docs/refunds/flows.md.

Keep self-serve as the default.<span id="cl-tool">

&gt; Ran npm test</span></div>
<span class="key" id="alt" data-in="scale" data-f>⌥ click</span>
<div class="call" id="img" data-in="up" data-f>Yours copies as typed. A picture becomes [Image #1].</div>
<div class="mlabel" id="lbl" data-in="up">Canvas board 4 · Copy</div>'''

# 9 wrap
scenes["wrap"] = '''<style>
#done { left: 40px; top: 24px; } #list { left: 40px; top: 70px; width: 560px; }
#recs { left: 40px; top: 340px; width: 560px; }
</style>
<div class="h" id="done" data-in="up">That’s all five</div>
<div id="list" data-dw="answers" data-in="up" data-f></div>
<div class="call" id="recs" data-in="up" data-f>Records: Q-505 to Q-509. Later ideas: ENH-342.</div>'''

os.makedirs("scenes", exist_ok=True)
for k, v in scenes.items():
    open(f"scenes/{k}.html", "w").write(v + "\n")
print(len(scenes), "scenes")
