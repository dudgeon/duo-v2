#!/usr/bin/env python3
"""Draws the project & task CX study boards (every mark [P]) as static HTML in the Duo design system.

    python3 docs/design/project-task-cx/canvas/make.py
    bash docs/design/project-task-cx/canvas/render.sh

Reuses the home-evolution study's tokens, CSS and drawing helpers (everything above its
"# ---------- boards" line), so the two studies draw the same app. Names and data are illustrative.
"""
import html, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "boards")
_src = open(os.path.join(HERE, "../../home-evolution-handoff/canvas/make.py")).read()
exec(_src[:_src.index("# ---------- boards ----------")].replace('OUT = os.path.join(HERE, "boards")', ""))
OUT = os.path.join(HERE, "boards")

CSS += f"""
.sheetwrap{{position:relative;flex:1;min-height:0;display:flex;justify-content:center;background:rgba(31,35,40,.32)}}
.sheet{{width:600px;background:{GROUND};border:1px solid {RULE};border-top:none;border-radius:0 0 10px 10px;box-shadow:0 12px 32px rgba(31,35,40,.22);padding:18px 24px 18px;display:flex;flex-direction:column;gap:12px;white-space:normal;align-self:flex-start}}
.sheet h2{{margin:0;font-size:13px;line-height:20px;font-weight:600}}
.fr{{display:grid;grid-template-columns:96px 1fr;column-gap:12px;align-items:center}}
.fr>label{{text-align:right;color:{TEXT}}}
.fld{{height:24px;border:1px solid {RULE};border-radius:6px;background:{PANE};padding:0 8px;display:flex;align-items:center;gap:6px;white-space:nowrap;overflow:hidden}}
.fld.ph{{color:{TEXT2}}}
.hint{{font-size:12px;line-height:16px;color:{TEXT2}}}
.btns{{display:flex;justify-content:flex-end;gap:8px;margin-top:4px}}
.b{{display:inline-flex;align-items:center;height:24px;padding:0 12px;border:1px solid {EDGE};border-radius:6px;background:{PANE};font-size:13px;white-space:nowrap}}
.b.def{{border:1.5px solid {TEXT};font-weight:600}}
.cb{{display:inline-flex;align-items:center;gap:8px}}
.cb i{{width:14px;height:14px;border-radius:4px;background:#0A64D2;display:inline-flex;align-items:center;justify-content:center}}
.cb i.off{{background:{PANE};border:1px solid {EDGE}}}
.rb{{display:inline-flex;align-items:center;gap:8px}}
.rb i{{width:14px;height:14px;border-radius:7px;border:1px solid {EDGE};background:{PANE};display:inline-flex;align-items:center;justify-content:center}}
.rb i.on{{border:4px solid #0A64D2}}
.pre{{background:{PANE};border:1px solid {RULE};border-radius:6px;padding:8px 10px;font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:11px;line-height:17px;color:{TEXT};white-space:pre}}
.pre .k{{color:{TEXT2}}}
.found{{display:flex;flex-direction:column;gap:4px;background:{PANE};border:1px solid {RULE};border-radius:6px;padding:8px 10px}}
.found div{{display:flex;gap:8px;align-items:baseline}}
.pP{{display:inline-block;font:600 10px/14px -apple-system,system-ui,sans-serif;color:{TEXT2};border:1px solid {EDGE};border-radius:7px;padding:0 5px;margin-left:6px;vertical-align:1px}}
.notice{{display:flex;align-items:center;gap:10px;background:{PANE};border:1px solid {EDGE};border-radius:8px;padding:6px 8px 6px 12px;box-shadow:0 4px 14px rgba(31,35,40,.12);white-space:normal}}
.expl{{background:{GROUND};border-radius:8px;padding:12px 14px;display:flex;flex-direction:column;gap:6px;white-space:normal}}
.expl b{{font-weight:600}}
.menu{{background:rgba(246,246,247,.98);border:1px solid {RULE};border-radius:8px;box-shadow:0 10px 30px rgba(31,35,40,.2);padding:5px 0;font-size:13px;line-height:20px;white-space:nowrap;display:flex;flex-direction:column}}
.menu div{{padding:1px 14px 1px 22px;display:flex;align-items:center;gap:8px}}
.menu .sep{{height:1px;background:{RULE};margin:5px 0;padding:0}}
.menu .hi{{background:#0A64D2;color:#fff;border-radius:5px;margin:0 5px;padding-left:17px}}
.menu .new{{font-weight:600}}
.menu .dim{{color:{EDGE}}}
.ck{{display:flex;align-items:center;gap:10px;min-height:26px}}
.ck .bx{{width:16px;height:16px;border-radius:8px;border:1.3px solid {EDGE};flex:none;display:flex;align-items:center;justify-content:center}}
.ck .bx.done{{background:{TEXT};border-color:{TEXT}}}
.drop{{background:{SELECTED};outline:1.5px dashed {TEXT};outline-offset:-1.5px}}
table.j{{border-collapse:collapse;width:100%;font-size:12px;line-height:17px;white-space:normal}}
table.j td,table.j th{{border:1px solid {RULE};padding:6px 8px;vertical-align:top;text-align:left;background:{PANE}}}
table.j th{{background:{GROUND};font-weight:600}}
.pain{{color:{NEEDS};font-weight:600}}
"""

TICK = '<svg width="10" height="8" viewBox="0 0 10 8"><path d="M1 4l2.6 2.6L9 1" fill="none" stroke="#fff" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>'
CHECK = f'<svg width="11" height="9" viewBox="0 0 10 8" style="flex:none"><path d="M1 4l2.6 2.6L9 1" fill="none" stroke="{TEXT}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>'
P = '<span class="pP">P</span>'
BOARDS = []


def board(name, w, h, title, note, body):
    BOARDS.append(dict(name=name, w=w, h=h, title=title, kind="board"))
    doc = f'''<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="design-size" content="{w}x{h}">
<meta name="design-kind" content="board">
<meta name="design-surface" content="project-task-cx">
<!--
{e(title)}
STUDY BOARD [P], not approved. Drawn for the project & task CX study (2026-10-07) with the Duo design system.
{e(note)}
It is a picture written in HTML: match what it draws, do not port its markup. Names and data are illustrative.
-->
<title>Duo · {e(title)}</title>
<style>{CSS}</style>
</head>
<body>
{body}
</body>
</html>
'''
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + ".html"), "w") as f:
        f.write(doc)


def bd(w, h, title, sub, inner, gap=14):
    return f'<div class="bd" style="width:{w}px;height:{h}px;gap:{gap}px"><div class="bt">{title}</div><div class="bsub">{sub}</div>{inner}</div>'


def frame(content, w=None, h=None, cap=None, note=None):
    st = (f"width:{w}px;" if w else "") + (f"height:{h}px;" if h else "")
    c = f'<div class="cap">{cap}</div>' if cap else ""
    n = f'<div class="note" style="width:{w}px">{note}</div>' if note else ""
    return f'<div style="display:flex;flex-direction:column;gap:8px;flex:none">{c}<div class="frame" style="{st}">{content}</div>{n}</div>'


def tb_quiet(crumb="All projects"):
    return f'''<div class="tb">
<span class="tl"><i style="background:#FF5F57"></i><i style="background:#FEBC2E"></i><i style="background:#28C840"></i></span>
<span class="tgl">{g("sidebar")}</span><span style="font-weight:600">{crumb}</span>
<span class="srch">{g("search")}Search all projects<span style="margin-left:auto">⇧⌘A</span></span>
<span class="tgl" style="margin-left:4px">{g("right")}</span></div>'''


def sheet_over(w, h, sheet, crumb="All projects"):
    return f'<div class="w" style="width:{w}px;height:{h}px">{tb_quiet(crumb)}<div class="sheetwrap">{sheet}</div></div>'


def fr(label, body):
    return f'<div class="fr"><label>{label}</label><div>{body}</div></div>'


def seg(opts, on):
    return '<span class="segc" style="height:24px">' + "".join(f'<span class="{"on" if i == on else ""}">{o}</span>' for i, o in enumerate(opts)) + '</span>'


PREVIEW_NEW = ('<span class="k">---</span>\n<span class="k">type:</span> project\n<span class="k">title:</span> Q4 plan\n<span class="k">aliases:</span>\n  - Q4 plan\n'
               '<span class="k">status:</span> active\n<span class="k">goal:</span> Q4 plan signed off by staff\n<span class="k">health:</span>\n<span class="k">next:</span>\n'
               '<span class="k">created:</span> 2026-10-07\n<span class="k">---</span>\n\n# Q4 plan\n\n## Goal …   ## Done when …   ## Notes …')

# ---------------------------------------------------------------- 00 study
board("00-study", 1200, 860, "0 · Projects and tasks: the study", "What Geoff asked, what the walk found, the principles.", bd(1200, 860,
    "0 · Making projects and putting work in tasks: the study",
    "Geoff, 2026-10-07: “the cx of creating projects (from scratch or from legacy project), and assigning tasks needs a thorough study with recommendations — the service design is not intuitive and has no explainer content or affordances.” Standing rule: keep everything Obsidian- and OKF-compatible. The walk ran build c463b79 on the acceptance fixtures in an isolated Duo (captures in <code>journey/</code>); the doc is <code>docs/research/project-task-cx.md</code>. Every mark on these boards is a proposal [P].",
    f'''<div style="display:flex;gap:16px;align-items:flex-start">
<div class="txt" style="flex:1"><h3>What the walk found, worst first</h3><ol>
<li><b>Nothing says what the words mean.</b> Project, task, Home, topic, session, group and thread appear with no definition in the app, and Help has no link to the guide (only the duo2 reference).</li>
<li><b>“New project” only makes a blank folder.</b> You can’t start from a folder you already have unless Duo lists it, so an Obsidian vault or legacy Duo notes folder with no Claude history can’t become a project at all (UI or duo2: “no folder”).</li>
<li><b>Linking a session to a task is hidden.</b> It’s right-click only (Add to Task ▸). There’s no drag, no picker, and nothing on a new task says how. <b>A session can’t leave a task</b> except by editing YAML, so moving work between tasks can’t be done.</li>
<li><b>The first view has no way in.</b> List, now the first view (DL-142), has no + New project; the Board has one at the very bottom.</li>
<li><b>You can’t see what Duo writes, and what it writes isn’t the agreed format.</b> PROJECT.md gets only goal / health / next, with health made up as on-track; a task note gets <code>sessions: []</code> (F-188).</li>
<li><b>No feedback after a change.</b> Make a Project, Move into Home and Add to Task change files and folders silently; Undo exists but nothing mentions it.</li>
<li><b>The brief is raw YAML</b> with no hint of what goal, health and next are for, or which values health takes.</li></ol></div>
<div class="txt" style="width:470px;flex:none"><h3>Principles [P]</h3><ol>
<li><b>Say it where it happens.</b> One plain sentence at the first point of use, linked to the guide page. No tours.</li>
<li><b>Start from what people have.</b> A folder you already use is as good a start as a new one.</li>
<li><b>Show the file before writing it,</b> and what Duo will never touch.</li>
<li><b>Never rewrite what isn’t Duo’s.</b> Obsidian and OKF notes, <code>.obsidian/</code> and <code>_index.md</code> stay byte-identical; Duo adds its own file beside them.</li>
<li><b>One relationship, three routes:</b> drag, a menu, a typed picker, all one duo2 verb.</li>
<li><b>Say what changed, with Undo,</b> and what Claude will now be told.</li>
<li><b>Fewer nouns first.</b> Lead with project and session; task when work spans sessions; group, topic and thread only where they appear.</li>
<li><b>Teach by doing.</b> A checklist that ticks when you do the real thing, not a slideshow.</li></ol></div>
</div>'''))

# ---------------------------------------------------------------- 01 journeys
J = [
    ("New project, from scratch", ["Board: scroll past every column and Outside Home to + New project; List shows none", "Sheet: Name, Goal, In, Start a session", "Folder + PROJECT.md made; a session starts"],
     "No word on what a project is or what file is written. Health is set to on-track for you. Nothing on List."),
    ("Project from a folder Duo lists", ["Find the folder under its parent heading or Outside Home", "Right-click › Make a Project, or open it: the notice offers Make a Project / Not Now", "PROJECT.md written, opened"],
     "Rows outside Home show no affordance. The notice is good copy (DL-110), but on the List view folders don’t appear at all."),
    ("Project from an Obsidian vault or legacy Duo notes", ["Folder has no Claude sessions, so Duo doesn’t list it", "File › Open File… opens a note, not the folder", "duo2 project make <path>: “no folder”"],
     "Dead end. No way in from the app or duo2. Nothing detects .obsidian/ or an OKF _index.md."),
    ("Move a project into Home", ["Right-click › Move into Home…", "Sheet: Into (Home or a topic), paths, warning", "Folder moves; sessions follow on resume"],
     "Good sheet. Afterwards nothing says it’s done or offers Undo. In the walk the moved folder’s session vanished from the lists (F-189)."),
    ("Make a task", ["+ New task under the session list", "tasks/untitled-task.md opens with the title selected", "Properties: type, title, status, sessions: []"],
     "Nothing says what a task is for or how to give it sessions. + New task also shows in a folder that isn’t a project."),
    ("Put a session in a task", ["Right-click the session › Add to Task ▸ › pick", "Or on a task: + (New Session in Task, DL-112)", "The task row gains it; Claude is told (DL-116)"],
     "Menu-only. No drag, no search, no feedback. Can’t take a session out, so it can’t move to another task."),
]
rows_j = "".join(f'<tr><th style="width:190px">{e(t)}</th>' + "".join(f'<td>{e(s)}</td>' for s in steps) + f'<td class="pain" style="width:280px">{e(p)}</td></tr>' for t, steps, p in J)
board("01-journeys", 1440, 760, "1 · Today’s journeys", "The walk, step by step, with where people get stuck.", bd(1440, 760,
    "1 · Today’s journeys, as walked on build c463b79",
    "Each row is a job as people meet it today; the last column is where they get stuck. Captures 01–09 in <code>docs/design/project-task-cx/journey/</code>.",
    f'<table class="j"><tr><th>Job</th><th>Step 1</th><th>Step 2</th><th>Step 3</th><th>Where it breaks</th></tr>{rows_j}</table>'))

# ---------------------------------------------------------------- 02 words
W = [("Session", "One conversation with Claude. Duo finds every one on this Mac and keeps it.", "Session lists, the toolbar counts"),
     ("Project", "One piece of work with an end, in its own folder. Its brief (_PROJECT.md, or a note you choose) holds the goal and the next step; Claude is told them.", "New project sheet, the Project tab, a folder’s notice"),
     ("Task", "Optional. Most sessions are for a task or a goal; a task keeps them together so you can come back to the work by what it’s for. It can have many sessions; a session doesn’t need one.", "The Tasks fold, a new task note, Add to Task"),
     ("Home", "The one folder you choose for the projects you’re working on, with its own Claude session to tell what’s new. Not your Mac’s home folder.", "Home’s pane (S2-3, as built)"),
     ("Topic", "A folder in Home that holds projects: an area you own, like payments. It never finishes.", "A map column’s heading, tooltip"),
     ("Group", "A few sessions bundled by hand, Duo-only. Make it a task to give it a note.", "A group row’s tooltip"),
     ("Thread", "A session and the forks made from it, folded into one row.", "A thread row’s tooltip"),
     ("Folder", "A place Claude has worked that isn’t a project yet. Keep working there, make it a project, or move its sessions.", "A folder’s notice (DL-110)")]
board("02-words", 1200, 720, "2 · The words, in one sentence each", "Proposed definitions and where each appears.", bd(1200, 720,
    "2 · The words, one sentence each [P]",
    "Each line appears once, where the thing first appears, with “Learn more” opening its guide page. Help gains <b>Duo Guide</b> (opens the guide) above duo2 Reference. The same sentences lead the guide pages, so app and guide never disagree.",
    '<table class="j"><tr><th style="width:110px">Word</th><th>What Duo says</th><th style="width:330px">Where it says it</th></tr>' +
    "".join(f'<tr><th>{e(a)}</th><td>{e(b)}</td><td>{e(c)}</td></tr>' for a, b, c in W) + '</table>'))

# ---------------------------------------------------------------- 03 new project A (new folder)
SHEET_HEAD = f'''<h2>New project</h2>
<div class="hint" style="font-size:13px;line-height:19px">A project is one piece of work with an end, in its own folder. Its brief, <span class="mono">_PROJECT.md</span>, holds the goal and the next step, and Claude is told them. <span style="text-decoration:underline">Learn more</span></div>'''
sheetA = f'''<div class="sheet">{SHEET_HEAD}
{fr("Start from", seg(["A new folder", "A folder I have", "From GitHub"], 0))}
{fr("Name", '<div class="fld">Q4 plan</div>')}
{fr("Goal", '<div class="fld">Q4 plan signed off by staff</div><div class="hint" style="margin-top:4px">One line: what done looks like. It shows on the tile and Claude reads it.</div>')}
{fr("In", f'<span class="popup" style="height:24px;font-size:13px">{g("folder")} Home (top level){g("chevd")}</span> <span class="mono t2" style="margin-left:8px">~/claude-home/q4-plan</span>')}
{fr("", '<span class="cb"><i>' + TICK + '</i>Start a Claude session in it</span>')}
{fr("Will write", f'<div class="hint mono" style="margin-bottom:4px">q4-plan/_PROJECT.md</div><div class="pre">{PREVIEW_NEW}</div><div class="hint" style="margin-top:4px">From your template (Home’s templates/new-project.md, else Duo’s). Plain Markdown: Obsidian reads it as is.</div>')}
<div class="btns"><span class="b">Cancel</span><span class="b def">Create Project</span></div></div>'''
board("03-new-a-fresh", 1200, 900, "3 · New project, A: one sheet, start fresh", "Option A: the New project sheet gains Start from, an explainer and a preview.", bd(1200, 900,
    "3 · New project, option A: one sheet with “Start from” <span class=\"rec\">recommended</span>",
    "The built sheet (S2-6) keeps its fields. Added [P]: the one-line explainer with Learn more; <b>Start from: A new folder | A folder I have | From GitHub</b> (the last drawn by the GitHub study); a hint under Goal; the folder name as a slug (<code>q4-plan</code>, title kept in <code>title:</code>); a <b>Will write</b> preview of <code>_PROJECT.md</code> (Geoff: the _ prefix sorts it first, as OKF’s <code>_index.md</code>), drawn from the templates session’s template. Health and next start empty and the sheet doesn’t ask for them.",
    frame(sheet_over(1140, 700, sheetA), 1140, 700)))

# ---------------------------------------------------------------- 04 new project A (folder I have, Obsidian/OKF)
sheetA2 = f'''<div class="sheet">{SHEET_HEAD}
{fr("Start from", seg(["A new folder", "A folder I have", "From GitHub"], 1))}
{fr("Folder", '<div style="display:flex;gap:8px"><div class="fld mono" style="flex:1;font-size:12px">~/Notes/pricing-vault</div><span class="b">Choose…</span></div>')}
{fr("Found", f'<div class="found"><div><b style="font-weight:600">Obsidian vault</b><span class="t2">.obsidian/ · 214 notes</span></div><div><b style="font-weight:600">Legacy Duo notes</b><span class="t2">_index.md, okf_version 0.1</span></div><div><b style="font-weight:600">3 Claude sessions</b><span class="t2">last 2 days ago</span></div></div><div class="hint" style="margin-top:4px">Duo won’t move, rename or rewrite your notes, and never touches <span class="mono">.obsidian/</span>.</div>')}
{fr("Name", '<div class="fld">Pricing</div><div class="hint" style="margin-top:4px">From _index.md’s title.</div>')}
{fr("Goal", '<div class="fld ph">What done looks like, in one line</div>')}
{fr("Brief", '<div style="display:flex;flex-direction:column;gap:4px"><span class="rb"><i class="on"></i>Use <span class="mono">_index.md</span> as the project’s brief</span><div class="hint" style="margin-left:22px">Adds one line to its properties, <span class="mono">project_brief: true</span>. Nothing else in it changes.</div><span class="rb"><i></i>Write a new <span class="mono">_PROJECT.md</span> beside it</span></div>')}
{fr("", '<span class="cb"><i class="off"></i>Also move it into Home</span>')}
<div class="btns"><span class="b">Cancel</span><span class="b def">Make a Project</span></div></div>'''
board("04-new-a-existing", 1200, 900, "4 · New project, A: a folder I have", "Option A with an existing folder: detection and promises.", bd(1200, 900,
    "4 · Option A, “A folder I have”: an Obsidian vault or legacy Duo notes",
    "Any folder, listed by Duo or not (File › Make a Project from Folder… opens this too). Duo looks and says what it found: <code>.obsidian/</code>, an OKF <code>_index.md</code> with <code>okf_version</code>, a git repo, CLAUDE.md, Claude sessions. When the folder has a note that could be the brief (an OKF <code>_index.md</code>, a folder note, a README with properties), Duo <b>asks whether it should be the brief</b> (Geoff). Yes adds <code>project_brief: true</code> to that note, a second way Duo finds a project besides <code>_PROJECT.md</code>, and the name comes from its <code>title</code>. No writes a new <code>_PROJECT.md</code>. A folder that already has <code>_PROJECT.md</code> or <code>PROJECT.md</code> is adopted as is. “From GitHub” belongs to the GitHub study. <code>duo2 project make &lt;path&gt;</code> takes any folder.",
    frame(sheet_over(1140, 700, sheetA2), 1140, 700)))

# ---------------------------------------------------------------- 05 option B chooser
def choice(title, body, sel=False):
    bdr = f"1.5px solid {TEXT}" if sel else f"1px solid {RULE}"
    return f'<div style="flex:1;background:{PANE};border:{bdr};border-radius:8px;padding:14px;display:flex;flex-direction:column;gap:6px;white-space:normal;min-height:150px"><div style="font-weight:600">{title}</div><div class="hint" style="font-size:12px;line-height:17px">{body}</div></div>'
sheetB = f'''<div class="sheet" style="width:720px">{SHEET_HEAD}
<div style="display:flex;gap:10px">{choice("Start fresh", "A new folder in Home with a brief. For work that hasn’t started.", True)}{choice("Use a folder I have", "Any folder: a repo, an Obsidian vault, legacy Duo notes. Duo adds a brief and changes nothing else.")}{choice("A folder with sessions", "One of the 4 folders where you’ve used Claude but that isn’t a project yet.")}</div>
<div class="btns"><span class="b">Cancel</span><span class="b def">Continue</span></div></div>'''
board("05-new-b-chooser", 1200, 640, "5 · New project, B: choose first", "Option B: a chooser step before the form.", bd(1200, 640,
    "5 · Option B: choose how to start, then the form",
    "Three cards, then A’s form for the one chosen. Clearer for a first-timer, one more step for everyone after. The third card lists Duo’s no-project folders, which A reaches from the folder itself.",
    frame(sheet_over(1140, 420, sheetB), 1140, 420)))

# ---------------------------------------------------------------- 06 option C menu
menuC = f'''<div class="menu" style="width:280px"><div>New Claude Session<span style="margin-left:auto" class="t2">⌘T</span></div><div>New Shell<span style="margin-left:auto" class="t2">⇧⌘T</span></div><div>New Browser Tab<span style="margin-left:auto" class="t2">⌥⌘T</span></div><div>New Markdown File<span style="margin-left:auto" class="t2">⌘N</span></div><div>New Folder<span style="margin-left:auto" class="t2">⇧⌘N</span></div><div>New Task</div><div>New Project…</div><div class="hi new">Make a Project from Folder…</div><div class="sep"></div><div>Open File…<span style="margin-left:auto" class="t2">⌘O</span></div><div class="dim">Open Location…<span style="margin-left:auto">⌘L</span></div></div>'''
board("06-new-c-menu", 1200, 560, "6 · New project, C: a second command", "Option C: keep the sheet; add a folder command.", bd(1200, 560,
    "6 · Option C: keep the sheet as built; add File › Make a Project from Folder…",
    "Cheapest. The macOS folder picker, then a short confirm sheet (board 4’s Found and Brief rows). Two commands to learn, and the New project sheet still says nothing about folders people already have.",
    f'<div style="display:flex;gap:28px;align-items:flex-start">{frame(menuC, 300, None, "File menu")}<div class="txt" style="flex:1"><h3>Trade-offs</h3><ul><li>A: one place to start any project; the sheet grows a segment and a preview. Medium effort.</li><li>B: the friendliest first time, slowest every time after. Medium.</li><li>C: small, but people who don’t open the File menu never learn they can start from a folder. Small.</li></ul></div></div>'))

# ---------------------------------------------------------------- 07 empty states at All projects
def list_with_banner():
    banner = f'''<div class="expl" style="margin:12px 16px 4px"><div><b>Your sessions, newest first.</b> Gather them into projects: a project is a folder for one piece of work, with a brief Claude reads. <span style="text-decoration:underline">Learn more</span></div>
<div style="display:flex;gap:8px"><span class="b def">+ New project</span><span class="b">Use a folder I have…</span><span class="b" style="border-color:transparent;background:transparent;color:{TEXT2}">Not Now</span></div></div>'''
    hdr = f'<div style="display:flex;align-items:center;gap:8px;height:38px;flex:none;padding:0 16px;border-bottom:1px solid {RULE}">{view_toggle_hdr(False)}<span class="filter" style="width:200px">{g("search")}Filter sessions</span><span style="flex:1"></span><span class="t2" style="font-size:12px">Group</span><span class="popup">Recent{g("updown")}</span><span class="b">+ New project</span></div>'
    rows_ = "".join(row(dict(st="idle", t=t, p=p, task=None, tm=tm), "proj") for t, p, tm in [("Plan the side-project landing page", "~/Desktop", "2d"), ("Quick question about refund SLAs", "~/Downloads", "5d"), ("Draft a post about pricing", "~", "6d"), ("Fix footer links", "~/repos/site", "6d")])
    return f'<div style="flex:1;min-width:0;display:flex;flex-direction:column;background:{PANE}">{hdr}{banner}{sec("This week")}{rows_}</div>'
w07 = window(1140, 560, home_chat_pane(320, tabs=("Session 9:41 AM",)) + list_with_banner(), tb=tb_quiet())
board("07-empty-all-projects", 1200, 760, "7 · All projects before the first project", "List with a one-time explainer and + New project in the header.", bd(1200, 760,
    "7 · All projects, before there’s a project",
    "List is what a new person sees first (DL-142), so it gets the way in: <b>+ New project</b> at the right of the header (Board and List both), and, while no project exists, a one-time explainer over the sessions with the two starts. Not Now hides it; it doesn’t come back once a project exists. The Board keeps its dashed + New project tile (DL-111).",
    frame(w07, 1140, 560)))

# ---------------------------------------------------------------- 08 first project checklist
def project_left(tasks_block, notice=""):
    return f'''<div style="width:300px;flex:none;border-right:1px solid {RULE};display:flex;flex-direction:column;background:{PANE};white-space:nowrap">
<div style="padding:12px 16px 6px"><div style="font-weight:600">q4-plan</div><div class="t2">Q4 plan signed off by staff</div></div>
{tasks_block}<div style="flex:1"></div>{notice}
<div style="border-top:1px solid {RULE};padding:8px 16px 10px"><div class="sl">FILES</div><div class="mono t2" style="margin-top:4px">PROJECT.md</div><div class="mono t2">tasks/</div></div></div>'''
ck = f'''<div class="expl" style="margin:14px 16px 0;background:{GROUND}">
<div style="display:flex;align-items:center"><b>Getting started with q4-plan</b><span class="t2" style="margin-left:8px">all optional</span><span style="margin-left:auto" class="t2">Hide</span></div>
<div class="ck"><span class="bx done">{TICK}</span><span>Write the goal: what done looks like</span></div>
<div class="ck"><span class="bx"></span><span>Start a session here</span><span class="b" style="margin-left:auto;height:22px;font-size:12px">+ New session</span></div>
<div class="ck"><span class="bx"></span><span>Make a task for work that takes more than one session</span><span class="b" style="margin-left:auto;height:22px;font-size:12px">Make a Task…</span></div>
<div class="ck"><span class="bx"></span><span>Put a session in it: drag the session onto the task</span></div>
<div class="hint">Each ticks when you do it, wherever you do it. Skip any. <span style="text-decoration:underline">How projects work</span></div></div>'''
props = f'''<div style="margin:14px 16px 0"><div class="sl">{g("chevd")}PROPERTIES · 5</div>
<div class="pre" style="margin-top:6px;background:{GROUND};border:none"><span class="k">type:</span> project
<span class="k">title:</span> Q4 plan
<span class="k">status:</span> active
<span class="k">goal:</span> Q4 plan signed off by staff
<span class="k">next:</span>   <span style="color:{TEXT2}">the next step, in your words</span></div></div>'''
right08 = f'<div style="flex:1;min-width:0;background:{PANE};display:flex;flex-direction:column;white-space:normal"><div style="height:36px;border-bottom:1px solid {RULE};display:flex;align-items:center;padding:0 16px;gap:16px"><span style="font-weight:600">Project</span><span class="t2">+</span></div>{ck}{props}<div style="padding:14px 18px"><div style="font-size:20px;font-weight:600;line-height:28px">Q4 plan</div></div></div>'
console08 = f'<div style="width:380px;flex:none;background:{CONSOLE};color:{CTEXT};padding:20px;white-space:normal"><div style="font-weight:600">No session open in q4-plan</div><div style="color:{CTEXT2};margin:4px 0 12px">Start Claude here. It’s told the brief when it starts.</div><span class="b" style="background:transparent;color:{CTEXT};border-color:{CTEXT2}">Start Claude here</span></div>'
left08 = project_left(f'<div class="t2" style="padding:6px 16px;white-space:normal">No sessions yet.</div><div style="display:flex;gap:8px;padding:6px 16px"><span class="b">+ New session</span><span class="b">+ New task</span></div>')
w08 = window(1140, 600, left08 + console08 + right08, tb=tb_quiet("All projects › q4-plan"))
board("08-first-project", 1200, 800, "8 · The first project: a checklist that ticks", "A per-project Getting started card in the Project tab, ticking on real actions.", bd(1200, 800,
    "8 · Inside a new project: “Getting started”, every step optional",
    "Geoff: a Getting started card, every step optional, with a guided flow for making a task (board 8b); health will rarely be used, so it isn’t a step. Above the properties on the Project tab until all ticked or Hidden (Duo’s state, never written into the brief). Each line ticks on the real action, wherever it’s done. The console’s empty state says Claude is told the brief.",
    frame(w08, 1140, 600)))

# ---------------------------------------------------------------- 08b guided task
recent = [("Q4 plan outline", "at prompt", True), ("Staff feedback notes", "2h", True), ("Last year’s plan, summarised", "1d", False), ("Vendor shortlist", "3d", False)]
rec_rows = "".join(f'<div style="display:flex;align-items:center;gap:8px;height:24px"><span class="cb"><i class="{"" if on else "off"}">{TICK if on else ""}</i></span>{g("idle")}<span class="ell" style="flex:1">{t}</span><span class="t2">{tm}</span></div>' for t, tm, on in recent)
sheetT = f'''<div class="sheet" style="width:620px"><h2>New task</h2>
<div class="hint" style="font-size:13px;line-height:19px">Most sessions are for a task or a goal. Put them in a task and Duo keeps them together, so you can come back to the work by what it’s for. A task can have many sessions; a session doesn’t need one. <span style="text-decoration:underline">Learn more</span></div>
{fr("Task", '<div class="fld">Draft the plan</div>')}
{fr("Done when", '<div class="fld ph">Optional: one line, e.g. “Staff have signed off”</div>')}
{fr("Sessions", f'<div style="display:flex;flex-direction:column;gap:6px"><span class="rb"><i class="on"></i>Put sessions I already have in it</span><div style="margin-left:22px;background:{PANE};border:1px solid {RULE};border-radius:6px;padding:4px 8px">{rec_rows}</div><span class="rb"><i></i>Start a new session for it</span><span class="rb"><i></i>None yet</span></div>')}
{fr("Will write", '<div class="hint mono">q4-plan/tasks/draft-the-plan.md · status: open · 2 sessions</div>')}
<div class="btns"><span class="b">Cancel</span><span class="b def">Make Task</span></div></div>'''
board("08b-guided-task", 1200, 860, "8b · Making a task, guided", "Geoff: a guided flow for task creation; all fields but the name optional.", bd(1200, 860,
    "8b · Making a task, guided: one sheet that says why, asks the name, and puts sessions in",
    "Geoff asked for a guided flow for making a task. <b>Make a Task…</b> (Getting started, the Tasks fold’s explainer, File › New Task) opens this sheet; + New task on a project that already has tasks keeps today’s inline note (DL-62). The sheet opens with the why, in Geoff’s terms. Only the name is needed. <b>Sessions</b> defaults to the project’s recent sessions, the selected or newest ones ticked, so the commonest case, “these sessions were all for this”, is one click; Start a new session runs New Session in Task (DL-112). Done when goes to <code>done_when</code> (the format doc’s key). The note is written by the templates session’s Templates.make(); <code>duo2 task new &lt;title&gt; [--done-when …] [--session …]… [--start]</code>.",
    frame(sheet_over(1140, 660, sheetT, "All projects › payments › q4-plan"), 1140, 660)))

# ---------------------------------------------------------------- 11b new session in a task
menuN = f'''<div class="menu" style="width:290px"><div>New Claude Session<span style="margin-left:auto" class="t2">⌘T</span></div><div class="hi new">New Session in Task<span style="margin-left:auto">▸</span></div><div>New Shell<span style="margin-left:auto" class="t2">⇧⌘T</span></div><div>New Browser Tab<span style="margin-left:auto" class="t2">⌥⌘T</span></div></div>'''
subN = f'''<div class="menu" style="width:230px;margin-top:26px"><div>Draft the plan<span style="margin-left:auto" class="t2">open</span></div><div>Staff review<span style="margin-left:auto" class="t2">waiting</span></div><div class="sep"></div><div>Make a Task…</div></div>'''
strip = f'<div style="background:{CONSOLE};color:{CTEXT};height:36px;display:flex;align-items:center;gap:14px;padding:0 12px;border-radius:6px 6px 0 0;width:640px"><span>{g("idle", CTEXT2)} Q4 plan outline</span><span style="color:{CTEXT2}">+ ⌄</span></div>'
board("11b-new-session-in-task", 1200, 560, "11b · Starting a session for a task", "The console’s + menu offers New Session in Task.", bd(1200, 560,
    "11b · The moment a session starts is when it’s easiest to say what it’s for",
    "Geoff: “usually, when people open a new session it’s related to a task or goal.” The console’s <b>+ ⌄</b> menu (and File) gains <b>New Session in Task ▸</b> listing the project’s open tasks, then Make a Task…; it runs DL-112’s New Session in Task. ⌘T stays a plain session: tasks stay optional.",
    f'<div style="display:flex;flex-direction:column;gap:6px">{strip}<div style="display:flex;gap:4px;margin-left:120px">{menuN}{subN}</div></div>'))

# ---------------------------------------------------------------- 09 sample project alt
T09F = None
t09 = tile("meet-duo", "Learn Duo by doing: three small tasks", "Sample · archive it when you’re done", [("idle", "Try: ask Claude to summarise this note", "")])
T09F = '<div style="padding:16px;width:340px">' + t09 + "</div>"
board("09-sample-project", 1200, 560, "9 · Alternative: a sample project", "Things-style tutorial project; not recommended for v1.", bd(1200, 560,
    "9 · Alternative to 8: a “Meet Duo” sample project (ENH-33)",
    "Help › Create Sample Project makes <code>meet-duo/</code> in Home: a brief and three task notes (write the goal, start a session in a task, link another session), as Things’ “Meet Things” does. Recreatable, archivable. Not for v1: it writes into the user’s Home, and its sessions spend turns.",
    f'<div style="display:flex;gap:24px;align-items:flex-start">{frame(T09F, 372, None, "On the map")}<div class="txt" style="flex:1"><h3>Tasks in meet-duo/tasks/</h3><ol><li>Write the goal in PROJECT.md (ticks when <code>goal</code> isn’t empty)</li><li>Start a session in this task (+ on its row)</li><li>Drag another session onto this task</li></ol></div></div>'))

# ---------------------------------------------------------------- 10 tasks empty + new task note
tasks_explainer = f'''<div style="padding:10px 16px 4px"><div class="t2" style="display:flex;align-items:center;gap:6px">{g("chevd")}Tasks</div>
<div class="expl" style="margin-top:6px;padding:10px 12px"><div>Most sessions are for a task or a goal. Put them in a task and Duo keeps them together, so you can come back to the work by what it’s for. A task can have many sessions; a session doesn’t need one.</div>
<div style="display:flex;gap:8px"><span class="b">+ New task</span><span class="hint" style="align-self:center">or drag a session here</span></div></div></div>'''
sess = "".join(row(dict(st=st, t=t, p="", task=None, tm=tm), "bare") for st, t, tm in [("prompt", "Q4 plan outline", "at prompt"), ("idle", "Staff feedback notes", "2h"), ("idle", "Last year’s plan, summarised", "1d")])
left10 = f'''<div style="width:300px;flex:none;border-right:1px solid {RULE};display:flex;flex-direction:column;background:{PANE};white-space:nowrap">
<div style="padding:12px 16px 6px"><div style="font-weight:600">q4-plan</div><div class="t2">Q4 plan signed off by staff</div></div>{sec("Today")}{sess}{tasks_explainer}<div style="flex:1"></div></div>'''
note10 = f'''<div style="flex:1;min-width:0;background:{PANE};display:flex;flex-direction:column;white-space:normal"><div style="height:36px;border-bottom:1px solid {RULE};display:flex;align-items:center;padding:0 16px;gap:16px"><span class="t2">Project</span><span style="font-weight:600">draft-the-plan.md</span></div>
<div style="margin:14px 16px 0"><div class="sl">{g("chevd")}PROPERTIES · 4</div>
<div style="margin-top:6px;background:{GROUND};border-radius:6px;padding:8px 10px;display:flex;flex-direction:column;gap:4px" class="mono"><div><span class="t2">type:</span> task</div><div><span class="t2">title:</span> Draft the plan</div><div><span class="t2">status:</span> <span class="popup" style="font-family:inherit">open{g("chevd")}</span></div>
<div style="display:flex;gap:8px;align-items:center"><span class="t2">sessions:</span><span style="font-family:-apple-system,system-ui;color:{TEXT2}">None yet. Drag a session here, or</span><span class="b" style="height:22px;font-size:12px;font-family:-apple-system,system-ui">+ Add</span><span class="b" style="height:22px;font-size:12px;font-family:-apple-system,system-ui">+ New session</span></div></div></div>
<div style="padding:14px 18px"><div style="font-size:20px;font-weight:600;line-height:28px">Draft the plan</div><div class="t2" style="margin-top:6px">Write what done looks like, and notes as the work goes. Claude reads this note when it works on the task.</div></div></div>'''
w10 = window(1140, 560, left10 + note10, tb=tb_quiet("All projects › q4-plan"))
board("10-tasks-empty", 1200, 780, "10 · No tasks yet, and a new task", "The Tasks explainer row and an empty sessions line that says what to do.", bd(1200, 780,
    "10 · Tasks: the empty fold, and a task with no sessions",
    "While a project has no tasks, the session list ends with a <b>Tasks</b> fold holding one explainer and + New task (replacing the bare button; the board view’s empty state uses the same line). A new note’s <code>sessions:</code> line, when empty, reads “None yet. Drag a session here, or + Add / + New session” instead of <code>[]</code>, and Duo omits the key on disk until there’s one (the agreed format). The body’s placeholder says Claude reads the note. A folder that isn’t a project offers no + New task.",
    frame(w10, 1140, 560)))

# ---------------------------------------------------------------- 11 drag to task
tasks11 = f'''<div style="padding:10px 0 4px"><div class="t2" style="display:flex;align-items:center;gap:6px;padding:0 16px">{g("chevd")}Tasks · 2</div>
<div class="row drop" style="margin-top:4px">{g("task")}<span class="ti" style="font-weight:600">Draft the plan</span><span class="tm">open</span></div>
<div class="row">{g("task")}<span class="ti">Staff review</span><span class="tm">waiting</span></div></div>'''
ghost = f'<div style="position:absolute;left:70px;top:226px;width:220px;background:{PANE};border:1px solid {EDGE};border-radius:6px;box-shadow:0 6px 16px rgba(31,35,40,.18)">{row(dict(st="prompt", t="Q4 plan outline", p="", task=None, tm="at prompt"), "bare").replace("margin:0 8px", "margin:0")}</div><div style="position:absolute;left:96px;top:262px;background:{TEXT};color:#fff;border-radius:5px;padding:2px 8px;font-size:12px">Add to “Draft the plan”</div>'
left11 = f'''<div style="position:relative;width:300px;flex:none;border-right:1px solid {RULE};display:flex;flex-direction:column;background:{PANE};white-space:nowrap">
<div style="padding:12px 16px 6px"><div style="font-weight:600">q4-plan</div><div class="t2">Q4 plan signed off by staff</div></div>{sec("Today")}{sess}{tasks11}<div style="flex:1"></div>{ghost}</div>'''
note_after = f'''<div class="notice" style="margin:0 12px 12px"><span style="flex:1">Added “Q4 plan outline” to <b style="font-weight:600">Draft the plan</b>. Claude is told on its next message.</span><span class="b" style="height:22px;font-size:12px">Undo</span></div>'''
left11b = f'''<div style="width:300px;flex:none;border-right:1px solid {RULE};display:flex;flex-direction:column;background:{PANE};white-space:nowrap">
<div style="padding:12px 16px 6px"><div style="font-weight:600">q4-plan</div><div class="t2">Q4 plan signed off by staff</div></div>{sec("Open", 1)}
<div class="row">{g("chevd")}{g("task")}<span class="ti" style="font-weight:600">Draft the plan</span><span class="tm">open · 1</span></div>
<div class="row" style="padding-left:40px">{g("idle")}<span class="ti">Q4 plan outline</span><span class="tm">at prompt</span></div>
{sec("Today")}{"".join(row(dict(st="idle", t=t, p="", task=None, tm=tm), "bare") for t, tm in [("Staff feedback notes", "2h"), ("Last year’s plan, summarised", "1d")])}<div style="flex:1"></div>{note_after}</div>'''
board("11-assign-drag", 1200, 720, "11 · Put a session in a task: drag", "Drag a session row onto a task row, then a notice with Undo.", bd(1200, 720,
    "11 · Putting a session in a task: drag it onto the task <span class=\"rec\">recommended</span>",
    "The drop look is the file tree’s (DL-132 c: <code>selected</code> fill, the drop dash), with a label saying what will happen. On drop: <code>duo2 task add</code>, the row folds under the task, and a notice at the foot of the list says what changed and that Claude is told (DL-116), with Undo. The same drop works on a task in the board view (task kanban study), on an open task note, and on Open tasks at All projects.",
    f'<div style="display:flex;gap:28px">{frame(left11, 300, 520, "Dragging")}{frame(left11b, 300, 520, "After the drop")}<div class="txt" style="flex:1;align-self:flex-start"><h3>Rules [P]</h3><ul><li>Drag adds; it doesn’t take the session out of another task. To move, hold ⌥ while dropping (the label reads “Move to …”), or use Move to Task ▸ (board 12).</li><li>Dropping on a task in another project asks first, as Move to Project does (DL-66).</li><li>A session already in that task: the label reads “Already in …” and nothing happens.</li><li>Several selected sessions drag together.</li></ul></div></div>'))

# ---------------------------------------------------------------- 12 menu + picker
menu12 = f'''<div class="menu" style="width:250px"><div>Copy Link</div><div>Resume as a Fork</div><div class="sep"></div><div>Make a Task</div><div class="hi">Add to Task<span style="margin-left:auto">▸</span></div><div class="new">Move to Task<span style="margin-left:auto">▸</span></div><div class="new">Remove from “Draft the plan”</div><div>Move to Project<span style="margin-left:auto">▸</span></div><div class="sep"></div><div>Archive Session</div><div>Delete Session…</div><div>End Session</div></div>'''
sub12 = f'''<div class="menu" style="width:230px;margin-top:62px"><div style="padding-left:6px">{CHECK}Draft the plan</div><div>Staff review</div><div>Exec readout</div><div class="sep"></div><div class="new">Find a Task…<span style="margin-left:auto" class="t2">⌥⌘K</span></div><div>New Task…</div></div>'''
picker = f'''<div style="width:380px;background:{PANE};border:1px solid {RULE};border-radius:10px;box-shadow:0 12px 32px rgba(31,35,40,.22);display:flex;flex-direction:column;white-space:nowrap">
<div style="padding:10px 12px;border-bottom:1px solid {RULE};display:flex;gap:6px;align-items:center">{g("search")}<span>staff</span><span style="margin-left:auto" class="t2">Add “Q4 plan outline” to</span></div>
<div style="padding:6px 0">{sec("q4-plan")}<div class="row sel">{g("task")}<span class="ti">Staff review</span><span class="tm">waiting</span></div><div class="row">{g("task")}<span class="ti">Prep the staff readout</span><span class="tm">open</span></div>
{sec("Other projects")}<div class="row">{g("task")}<span class="ti">Staff offsite agenda</span><span class="pj">ops-offsite</span></div>
<div class="row" style="margin-top:4px"><span class="ti">+ New task “staff”</span></div></div>
<div style="border-top:1px solid {RULE};padding:6px 12px" class="hint">↩ Add · ⌥↩ Move here (leave Draft the plan) · Esc. A session can be in more than one task.</div></div>'''
board("12-assign-menu-picker", 1200, 660, "12 · Put a session in a task: menu and picker", "Move to Task, Remove from Task, and a typed picker.", bd(1200, 660,
    "12 · The session menu gains Move to Task ▸ and Remove from …; a Find a Task… picker later",
    "Add to Task ▸ shows a tick on tasks the session is in. <b>Move to Task ▸</b> adds it there and takes it out of the others; <b>Remove from “…”</b> (one task) or <b>Remove from Task ▸</b> (several) takes it out. <b>Find a Task…</b> opens the picker: search’s modal look, tasks of this project first, other projects after (adding there asks, as on board 11), New task last. New verbs: <code>duo2 task remove &lt;task&gt; &lt;session&gt;</code>, <code>duo2 task add … --move</code>. The ⌥⌘K chord is Q-116.",
    f'<div style="display:flex;gap:6px;align-items:flex-start">{menu12}{sub12}<div style="width:40px"></div>{picker}</div>'))

# ---------------------------------------------------------------- 13 notices
def nt(msg, btns):
    return f'<div class="notice" style="width:560px"><span style="flex:1">{msg}</span>' + "".join(f'<span class="b" style="height:22px;font-size:12px">{b}</span>' for b in btns) + '</div>'
board("13-notices", 1200, 600, "13 · Saying what changed", "One notice pattern after every change to files or folders.", bd(1200, 600,
    "13 · After every change: one notice, what changed, and Undo",
    "A notice rises at the foot of the pane where you acted (motion: <code>rowIn</code>), stays 8 s or until you act, and never takes the keyboard. It says what Duo wrote or moved, what Claude will be told, and offers Undo (the same as Edit › Undo, <code>duo2 undo</code>). Scripts and duo2 get the same words on stdout.",
    '<div style="display:flex;flex-direction:column;gap:12px">' +
    nt('Made <b style="font-weight:600">pricing-vault</b> a project: <span class="mono">_index.md</span> is its brief (added <span class="mono">project_brief: true</span>). Nothing else changed.', ["Open Brief", "Undo"]) +
    nt('Moved <b style="font-weight:600">side-project</b> into Home with its 1 session. It moves in Claude on its next resume.', ["Show in Finder", "Undo"]) +
    nt('Added “Q4 plan outline” to <b style="font-weight:600">Draft the plan</b>. Claude is told on its next message.', ["Undo"]) +
    nt('Moved “Q4 plan outline” from Draft the plan to <b style="font-weight:600">Staff review</b>.', ["Undo"]) +
    nt('Made the task <b style="font-weight:600">Draft the plan</b> from “Q4 plan outline”: tasks/draft-the-plan.md.', ["Undo"]) + '</div>'))

# ---------------------------------------------------------------- 14 recommendation
board("14-recommendation", 1200, 940, "14 · Decisions and the v1 slice", "Geoff's answers and what to build first, with effort.", bd(1200, 940,
    "14 · Geoff’s answers and the v1 slice",
    "Geoff, 2026-10-07, by buttons (DL-147). Small = a day or less; Medium = a few days. Every write follows <code>obsidian-compatible-task-format.md</code>: nothing in <code>.obsidian/</code>, no note rewritten beyond the one key Geoff approved, no Tasks emoji or Dataview inline fields.",
    f'''<div style="display:flex;gap:16px;align-items:flex-start">
<div class="txt" style="flex:1"><h3>v1 slice</h3><ol>
<li><b>Words where they appear</b> (board 2) and Help › Duo Guide. Small.</li>
<li><b><code>_PROJECT.md</code> and <code>_HOME.md</code></b> for new projects and Homes; PROJECT.md and HOME.md still read, never renamed. Small–Medium (discovery, watchers, search, duo2, docs).</li>
<li><b>Write the agreed format</b> (F-188) through the templates session’s Templates.make(). Small.</li>
<li><b>New project, A</b> (boards 3–4): Start from, the preview, “A folder I have” for any folder with detection, and the brief question with <code>project_brief: true</code>. Medium.</li>
<li><b>+ New project on List</b> and the one-time explainer (board 7). Small.</li>
<li><b>Getting started</b>, all optional (board 8), and <b>Make a Task…</b>, guided (board 8b). Medium.</li>
<li><b>Tasks empty states</b> with the why (board 10). Small.</li>
<li><b>Drag a session onto a task</b> (board 11) and <b>New Session in Task ▸</b> on the + menu (board 11b). Medium.</li>
<li><b>Move to Task ▸, Remove from …</b> and <code>duo2 task remove</code> / <code>add --move</code> (board 12): a session can’t leave a task today. Small.</li>
<li><b>Notices with Undo</b> (board 13). Medium.</li></ol></div>
<div class="txt" style="width:450px;flex:none"><h3>Geoff’s answers</h3><ul>
<li>Starting a project: <b>A</b>, one sheet.</li><li>Teaching: <b>Getting started</b>, every step optional, with a guided flow for tasks; health rarely used, so not a step.</li>
<li>Assigning: <b>drag</b>, and say why sessions and tasks connect (optional; many sessions per task; come back by goal or task).</li>
<li>An adopted folder’s note: <b>ask</b> whether it’s the brief; if so mark it <code>project_brief: true</code>, an alternative to the project file.</li>
<li>The project file: <b><code>_PROJECT.md</code></b>; existing PROJECT.md read, never renamed; Home follows (<code>_HOME.md</code>).</li></ul>
<h3>Later</h3><ul><li>Find a Task… picker (board 12).</li><li>ENH-33: a sample project (board 9).</li><li>ENH-34: list an adopted vault’s own task notes.</li></ul>
<h3>Bugs found</h3><ul><li>F-188: files written miss the agreed format.</li><li>F-189: Move into Home lost a session under a symlinked path.</li></ul></div></div>'''))

with open(os.path.join(OUT, "manifest.json"), "w") as f:
    json.dump(BOARDS, f, indent=1)
print(f"{len(BOARDS)} boards in {OUT}")
