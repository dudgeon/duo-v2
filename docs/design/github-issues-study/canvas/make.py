#!/usr/bin/env python3
"""Draws the GitHub issues study boards (every mark [P]) as static HTML in the Duo design system.

    python3 docs/design/github-issues-study/canvas/make.py
    bash docs/design/github-issues-study/canvas/render.sh

Reuses the task board's drawn components (task-board-study/canvas/make.py: lanes, cards, session rows,
the project window, the note pane) and the GitHub study's sheet, notice and branch mark
(github-study/canvas/make.py), by executing their component sections. Colours are tokens by value.
Names, repos and data are illustrative.
"""
import html, json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "boards")
STUDY = "github-issues"
DESIGN = os.path.normpath(os.path.join(HERE, "../.."))


def load(path, marker):
    src = open(path).read()
    ns = {"__file__": path, "__name__": "component"}
    exec(src[:src.index(marker)], ns)
    return ns


TB = load(f"{DESIGN}/task-board-study/canvas/make.py", "# ---------- 0 · the study")
GH = load(f"{DESIGN}/github-study/canvas/make.py", "# ======================================================================\n# 00 · the study")
for k in ("GROUND", "PANE", "SELECTED", "RULE", "EDGE", "TEXT", "TEXT2", "NEEDS", "TINT", "CONSOLE", "CRULE", "CTEXT", "CTEXT2",
          "g", "e", "box", "plus", "person", "cal", "card", "lane", "sess_rows", "ptoolbar", "left_pane", "console", "note_pane",
          "pwindow", "board_header", "bd", "frame", "T", "LANES", "GLYPH_FOR", "sec", "fold", "srow"):
    globals()[k] = TB[k]
br, nt, fr = GH["br"], GH["nt"], GH["fr"]
TICK = GH["TICK"]

# the GitHub study's sheet/notice/menu CSS, evaluated with the same tokens
_gsrc = open(f"{DESIGN}/github-study/canvas/make.py").read()
_blocks = re.findall(r'CSS \+= f"""(.*?)"""', _gsrc, re.S)
GH_CSS = "".join(eval('f"""' + b + '"""', dict(TB)) for b in _blocks)

CSS = TB["CSS"] + TB["EXTRA_CSS"] + GH_CSS + f"""
.isc{{background:{PANE};border:1px solid {RULE};border-radius:6px;padding:8px 10px 9px;display:flex;flex-direction:column;gap:3px;white-space:normal;min-width:0}}
.isc.sel{{border-color:{TEXT}}}
.isc .tt{{display:flex;align-items:flex-start;gap:7px;font-weight:600;line-height:18px}}
.isc .tt svg{{margin-top:4px}}
.isc .mt{{display:flex;flex-wrap:wrap;align-items:center;gap:4px 10px;font-size:12px;line-height:16px;color:{TEXT2};padding-left:17px}}
.num{{font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:11.5px;color:{TEXT2};font-weight:400}}
.ichip{{display:inline-flex;align-items:center;gap:4px;white-space:normal}}
.ilist .r{{display:flex;align-items:center;gap:8px;height:44px;padding:0 12px;margin:0 8px;border-radius:6px}}
.ilist .r.sel{{background:{SELECTED}}}
pre.fm{{margin:0;white-space:pre;font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:11.5px;line-height:17px}}
.hl{{background:{TINT}}}
"""


# ---------- new marks [P] ----------
def imark(closed=False, color=None):
    """The issue mark [P]: a circle with a dot (open) or a tick (closed)."""
    c = color or TEXT2
    inner = (f'<path d="M3.1 5.1 4.4 6.4 6.9 3.7" fill="none" stroke="{c}" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/>' if closed
             else f'<circle cx="5" cy="5" r="1.3" fill="{c}"/>')
    return f'<svg width="10" height="10" viewBox="0 0 10 10" style="flex:none"><circle cx="5" cy="5" r="4.2" fill="none" stroke="{c}" stroke-width="1.2"/>{inner}</svg>'


def pP():
    return '<span class="pP">P</span>'


# ---------- data (illustrative) ----------
REPO = "acme/checkout"
ISSUES = [
    dict(n=482, t="Apple Pay button misaligned on iPad", lab="bug", up="2h", by="priya-s"),
    dict(n=477, t="Add an order notes field", lab="enhancement", up="1d", by="sam-o"),
    dict(n=469, t="Saved cards: warn before a card expires", lab="enhancement · p2", up="3d", by="priya-s"),
    dict(n=455, t="Promo code field accepts spaces", lab="bug · good first issue", up="6d", by="dana-k"),
]


def issue_card(i, sel=False, cls="", lift=False, ghost=False):
    k = "isc" + (" sel" if sel else "") + (f" {cls}" if cls else "")
    st = ""
    if lift:
        st = ' style="box-shadow:0 12px 32px rgba(31,35,40,0.22);transform:rotate(-1.5deg)"'
    if ghost:
        return f'<div class="tc ghost" style="opacity:.55"><div class="tt">{imark()}<span>{e(i["t"])}</span></div></div>'
    meta = f'<span>{e(i["lab"])}</span><span>updated {e(i["up"])}</span>' if i.get("lab") else f'<span>updated {e(i["up"])}</span>'
    return (f'<div class="{k}"{st}><div class="tt">{imark(i.get("closed"))}<span style="flex:1;min-width:0">{e(i["t"])} <span class="num">#{i["n"]}</span></span></div>'
            f'<div class="mt">{meta}</div></div>')


def chip(c):
    iss = c.get("issue")
    if not iss:
        return ""
    if iss.get("gone"):
        return f'<span class="ichip" style="color:{TEXT};font-weight:600">{imark(True, TEXT)}#{iss["n"]} closed on GitHub</span>'
    if iss.get("closed"):
        return f'<span class="ichip">{imark(True)}#{iss["n"]} closed</span>'
    return f'<span class="ichip">{imark()}#{iss["n"]}</span>'


def tcard(c, **kw):
    """The task board's card, with the issue chip first on line 2."""
    h = card(c, **kw)
    ch = chip(c)
    if not ch:
        return h
    if '<div class="mt">' in h:
        return h.replace('<div class="mt">', f'<div class="mt">{ch}', 1)
    i = h.index("</div>", h.index('class="tt"')) + 6
    return h[:i] + f'<div class="mt">{ch}</div>' + h[i:]


# task board data with links
TT = {k: [dict(c) for c in v] for k, v in T.items()}
TT["in-progress"].insert(0, dict(t="Guest checkout times out on slow 3G", o="Geoff", due="Oct 16", issue=dict(n=451),
                                ss=[("working", "Timeout repro on 3G", "working")]))
TT["waiting"][0]["issue"] = dict(n=440, gone=True)
TT["review"][0]["issue"] = dict(n=436)


def issues_lane(sel=None, w=None, filt="Mine", extra="", cards=None, drop=False):
    cards = ISSUES if cards is None else cards
    body = "".join(issue_card(i, sel=(i["n"] == sel)) for i in cards) + extra
    hdr = (f'<span class="popup" style="height:18px;font-size:11px;letter-spacing:0;text-transform:none;font-weight:400;color:{TEXT2};margin-left:auto;padding:0 4px 0 6px">{e(filt)}{g("updown")}</span>')
    st = f' style="flex:none;width:{w}px"' if w else ""
    return (f'<div class="lane"{st}><div class="lh">{imark()}<span>Issues · {len(cards)}</span>{hdr}</div>'
            f'<div class="lb" style="background:{GROUND};border:1px dashed {RULE}">{body}</div></div>')


def task_lanes(keys, sel=None, data=None, drop_into=None, slot=None, lift_t=None):
    data = data or TT
    out = []
    for k, label in LANES:
        if k not in keys:
            continue
        cs = data[k]
        parts = [tcard(c, sel=(c["t"] == sel), sess="rows" if c.get("ss") and k != "done" else "lead") for c in cs if c["t"] != lift_t]
        if drop_into == k and slot:
            parts.insert(0, slot)
        h = lane(k, label, "".join(parts), len(cs))
        if drop_into == k:
            h = h.replace('class="lb"', f'class="lb" style="background:{SELECTED};outline:1px dashed {EDGE};outline-offset:-1px"')
        out.append(h)
    return "".join(out)


def done_strip(n=2):
    return (f'<div style="width:34px;flex:none;margin:32px 0 0;background:{GROUND};border-radius:6px;display:flex;flex-direction:column;align-items:center;gap:8px;padding-top:8px">'
            f'{g("chev")}<span class="sl" style="writing-mode:vertical-rl;height:auto">Done · {n}</span></div>')


def wa_board(sel_issue=482, sel_task=None, header_left=None, lanes_html=None):
    hdr = board_header(n=13)
    if header_left:
        hdr = hdr.replace('<span class="sl">Tasks · 13</span>', header_left)
    lanes_html = lanes_html or (issues_lane(sel=sel_issue) + task_lanes(["open", "in-progress", "waiting", "review"], sel=sel_task) + done_strip())
    return (f'<div style="flex:1;min-width:0;display:flex;flex-direction:column;min-height:0;border-right:1px solid {RULE}">{hdr}'
            f'<div style="display:flex;gap:10px;flex:1;min-height:0;padding:10px 16px 16px;overflow:hidden">{lanes_html}</div></div>')


def issue_pane(w=460, i=ISSUES[0]):
    tabs = f'<span>Project</span><span class="on" style="display:flex;gap:5px;align-items:center">{imark()}#{i["n"]}</span><span>+</span>'
    props = [("state", f'{imark()}open · opened by {i["by"]} 2d ago'), ("labels", e(i["lab"])), ("assignees", "geoffd"), ("milestone", "October launch"), ("comments", "3")]
    pl = "".join(f'<div class="pl"><span class="k">{k}</span><span style="display:flex;align-items:center;gap:6px">{v}</span></div>' for k, v in props)
    comments = "".join(f'<div style="display:flex;flex-direction:column;gap:2px;padding:8px 0;border-top:1px solid {SELECTED}"><span class="t2" style="font-size:12px">{a} · {t}</span><span>{x}</span></div>'
                       for a, t, x in [("sam-o", "1d", "Repro on iPad Air in landscape only; portrait is fine."), ("priya-s", "2h", "Design says the button should align with the card field’s left edge.")])
    body = (f'<div style="padding:16px 24px;white-space:normal;display:flex;flex-direction:column;gap:0;flex:1;min-height:0;overflow:hidden">'
            f'<div class="mono t2" style="font-size:11.5px">{REPO} #{i["n"]}</div>'
            f'<div style="font-weight:600;font-size:18px;line-height:24px;margin:2px 0 10px">{e(i["t"])}</div>'
            f'<div class="pb"><div class="sl" style="margin-bottom:2px">From GitHub</div>{pl}</div>'
            f'<div>On iPad the Apple Pay button sits 12 px right of the card field and overlaps the total at narrow widths.</div>'
            f'<div style="margin-top:8px">Steps: open checkout on iPad in landscape, add one item, look at the payment row.</div>'
            f'<div class="sl" style="margin-top:16px">Last comments · 2 of 3</div>{comments}'
            f'<div style="display:flex;gap:8px;margin-top:12px"><span class="b def">Make Task</span><span class="b">Open on GitHub</span><span class="b">Ask Claude About It…</span></div>'
            f'<div class="t2" style="font-size:12px;margin-top:auto">Read-only · from GitHub at 10:32 · ⌘R refreshes</div></div>')
    return f'<div style="width:{w}px;flex:none;display:flex;flex-direction:column;min-height:0"><div class="ltab">{tabs}</div>{body}</div>'


def task_note_pane(w=460, issue_state="open", linking=False):
    tabs = '<span>Project</span><span class="on">Guest checkout times out…</span><span>+</span>'
    if issue_state == "open":
        irow = (f'{imark()}<span style="text-decoration:underline;text-decoration-color:{EDGE}">#451 Checkout spinner never ends on slow networks</span>'
                f'<span class="t2" style="font-size:12px">open · bug, p1</span>{g("jump")}')
    else:
        irow = (f'{imark(True, TEXT)}<span style="text-decoration:underline;text-decoration-color:{EDGE}">#451</span><span style="font-weight:600">closed on GitHub</span>'
                f'<span class="b sm" style="margin-left:4px">Mark Done</span>')
    props = [("status", f'in-progress {g("chevd")}'), ("due", "2026-10-16"), ("issue", irow)]
    pl = "".join(f'<div class="pl"><span class="k">{k}</span><span style="display:flex;align-items:center;gap:6px;min-width:0">{v}</span></div>' for k, v in props)
    pl += f'<div class="pl"><span class="k">sessions</span><span style="display:flex;align-items:center;gap:6px">{g("working")}<span>Timeout repro on 3G</span><span class="t2">working</span></span></div>'
    extra = ""
    if linking:
        extra = linking
    body = (f'<div style="padding:18px 24px;white-space:normal"><div class="pb"><div class="sl" style="margin-bottom:2px">Properties</div>{pl}</div>{extra}'
            f'<div style="font-weight:600;font-size:18px;line-height:24px;margin:6px 0 10px">Guest checkout times out on slow 3G</div>'
            f'<div>Find why the spinner never ends on slow networks and fix it before the October launch.</div>'
            f'<div style="font-weight:600;margin-top:14px">Done when</div><div style="display:flex;gap:8px;align-items:center;margin-top:4px">{box()}Checkout completes on throttled 3G in under 20 s</div>'
            f'<div style="font-weight:600;margin-top:14px">Notes</div><div class="t2" style="font-size:12px">From GitHub, 2026-10-09:</div>'
            f'<div style="border-left:2px solid {RULE};padding-left:10px;color:{TEXT2}">On a throttled connection the payment step spins forever; no error is shown…</div></div>')
    return f'<div style="width:{w}px;flex:none;display:flex;flex-direction:column;min-height:0"><div class="ltab">{tabs}</div>{body}</div>'


def ptb(toggle="board", third=None):
    h = ptoolbar(toggle=toggle)
    if third:
        h = h.replace(f'{g("board")}Tasks</span></span>',
                      f'{g("board")}Tasks</span><span class="{"on" if third == "on" else ""}" style="gap:5px">{imark(color=TEXT if third == "on" else None)}Issues</span></span>')
        if third == "on":
            h = h.replace('<span class="on" style="gap:5px">' + g("board") + 'Tasks', '<span class="" style="gap:5px">' + g("board") + 'Tasks')
    return h


WW, WH = 1440, 900

# ---------- furniture ----------
BOARDS = []


def board(name, w, h, title, note, body):
    BOARDS.append(dict(name=name, w=w, h=h, title=title, kind="board"))
    doc = f'''<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="design-size" content="{w}x{h}">
<meta name="design-kind" content="board">
<meta name="design-surface" content="{STUDY}">
<!--
{e(title)}
STUDY BOARD [P], not approved. Drawn for the GitHub issues study (2026-10-09) with the Duo design system,
reusing the task board's components (DL-148) and the GitHub study's sheet (DL-149).
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


def txt(inner, w=None, flex=False):
    st = (f"width:{w}px;flex:none;" if w else "") + ("flex:1;min-width:0;" if flex else "")
    return f'<div class="txt" style="{st}">{inner}</div>'


def table(head, rows, first_w=150):
    th = "".join(f"<th>{h}</th>" for h in head)
    trs = "".join("<tr>" + "".join((f"<th style='width:{first_w}px'>{c}</th>" if j == 0 else f"<td>{c}</td>") for j, c in enumerate(r)) + "</tr>" for r in rows)
    return f'<table class="cmp"><thead><tr>{th}</tr></thead><tbody>{trs}</tbody></table>'


# ======================================================================
# 00 · the study and the facts
clone_rows = [
    ["Branches, tags", "<b>yes</b>", "<code>refs/heads</code>, <code>refs/tags</code>"],
    ["A pull request’s commits", "fetchable, not by default", "<code>refs/pull/&lt;n&gt;/head</code>: cli/cli shows 266 heads, 205 tags, 5,398 pull refs, and nothing else [probe]"],
    ["Issues, comments, reviews", "<b>no</b>", "GitHub’s database: REST, GraphQL, <code>gh</code>, GitHub’s MCP server"],
    ["Labels, milestones", "<b>no</b>", "made on GitHub by anyone with write access; no file declares them"],
    ["Projects (v2)", "<b>no</b>", "owned by a user or an org, not a repo; can span repos"],
    ["Issue templates and forms", "<b>yes</b>", "<code>.github/ISSUE_TEMPLATE/*.md|*.yml</code>; a form can add labels and a Project; <code>config.yml</code> sets the chooser"],
    ["PR templates, workflows", "<b>yes</b>", "<code>.github/</code>, on the default branch"],
]
board("00-study", 1440, 1000, "0 · GitHub issues in Duo: the study", "The ask, the sync facts, and who does what.", bd(1440, 1000,
    "0 · GitHub issues and Projects in Duo",
    "Geoff, 2026-10-09: “Many projects are repos; some of these repos track issues and/or implement GitHub projects. I don’t know if these are already synced/syncable via clone/push/pull — but I want to understand what options exist for duo to help visualize, edit, and otherwise manipulate issues by human and agent… reuse/share ui elements and UX mental models with the kanban features.” Every mark on these boards is a proposal [P]. Research: <code>docs/research/github-issues.md</code>.",
    f'''<div style="display:flex;gap:16px;align-items:flex-start">
{txt("<h3>Does clone, pull or push move issues? No.</h3>" + table(["Thing", "In a clone", "Where it lives"], clone_rows, 170) + "<p class='note' style='margin-top:8px'>So an issue’s state reaches Duo only through GitHub’s API, with the user’s own <code>gh</code> sign-in. Projects need an extra scope (<code>read:project</code>, or <code>project</code> to write) that Geoff’s <code>gh</code> doesn’t have today. Signed out, <code>gh</code> refuses even a public repo’s issues; offline it fails in 0.04 s.</p>", 820)}
<div style="display:flex;flex-direction:column;gap:14px;flex:1">
{txt("""<h3>Who does what (the DL-149 split, again)</h3><ul>
<li><b>Claude can already do all of it</b>: <code>gh issue create / edit / close / comment</code>, <code>gh project item-edit</code>, in any repo session.</li>
<li><b>Duo shows and links</b>: which issues are yours, which task tracks which issue, the issue’s state on the card, told to Claude.</li>
<li><b>Duo makes the common moves one click</b>: make a task from an issue; close it with the task; “Closes #n” in the PR it opens.</li>
<li><b>Claude does judgement and words</b>: triage, labels, duplicates, comments, from instructions Duo drafts.</li>
<li><b>Not a second GitHub</b>: no label editor, comment threads, assignee picker or milestone manager.</li></ul>""")}
{txt("""<h3>What others do</h3><ul>
<li><b>Link by ID, derive status from events</b>: Linear (“closes #n” in a PR), Jira (keys in branches), VS Code (Start Working on Issue).</li>
<li><b>Mirror into notes</b>: Obsidian plugins pull one-way and overwrite the note except a “persist block”.</li>
<li><b>Issues in git</b>: git-bug, a different tracker with bridges; teams on GitHub won’t move.</li>
<li><b>Issue as launch point</b>: Copilot’s agent starts from an assigned issue. Duo’s New Session in Task does it with Claude Code.</li></ul>""")}</div></div>'''))

# ======================================================================
# 02 · the model
model_rows = [
    ["On disk", "nothing", "<code>issue:</code> on notes that track one", "a note per issue, kept in sync", "nothing"],
    ["Status truth", "GitHub", "task <code>status</code> local; issue state GitHub’s", "two copies", "the Project’s Status"],
    ["Sync", "read only", "none; Duo <b>offers</b> close and done", "two-way, conflict rules", "Duo writes Status on drag"],
    ["Conflicts", "none", "none: no shared field", "many: both edited; closed vs done; labels", "last write wins"],
    ["Repo noise", "none", "one line per linked note", "files churn on every poll", "none"],
    ["Obsidian", "n/a", "a URL property, clickable", "notes overwritten by sync", "n/a"],
    ["Offline", "cached list", "cached state; the link always works", "full but stale", "cached, read-only"],
    ["No gh / signed out", "nothing", "link works; “Sign in to see #123”", "can’t sync", "nothing"],
    ["Cost", "M", "<b>S</b> (link) to M (lane)", "L, ongoing", "L + a scope step"],
    ["Verdict", "a part of B (the lane)", '<span class="verdict">recommended</span>', '<span class="verdict no">rejected</span>', '<span class="verdict no">later, as a source</span>'],
]
board("02-model", 1500, 980, "2 · How issues relate to task notes", "Four models; link, don't mirror.", bd(1500, 980,
    "2 · The model: how a GitHub issue relates to a task note",
    "The task board’s rule holds: <b>one truth per fact.</b> A task’s status lives in its note (DL-13); an issue’s state lives on GitHub. B links them and keeps each fact in one place. [P]",
    f'''{txt(table(["", "A · live list, read-only", "B · linked task", "C · mirror into notes", "D · a Project as the board"], model_rows, 140))}
<div style="display:flex;gap:14px">{txt("<h3>Why B</h3><ul><li>No sync engine, no conflicts.</li><li>What nearly every tool does: link by ID, show live state, bridge through events.</li><li>One quoted URL in the note: Obsidian shows it as a link.</li></ul>", flex=True)}
{txt("<h3>Why not C</h3><ul><li>Every field twice; a repo that churns on each poll; an Obsidian edit and a GitHub edit collide.</li><li>No tool trusts a local note as an issue’s truth.</li><li>Make Task from Issue is a <b>one-off copy</b> (title, quoted body), then the note is yours.</li></ul>", flex=True)}
{txt("<h3>A and D live inside B</h3><ul><li>A becomes the board’s <b>Issues lane</b> (board 4): issues not yet tracked.</li><li>D becomes a <b>board source</b> (board 8), later: same lanes and cards, GitHub’s Status as columns.</li></ul>", flex=True)}</div>'''))

# ======================================================================
# 03 · the link on disk
fm = '''---
type: task
title: Guest checkout times out on slow 3G
status: in-progress
due: 2026-10-16
issue: "https://github.com/acme/checkout/issues/451"
sessions:
  - "[Timeout repro on 3G](duo2://session/5f0c…)"
created: 2026-10-09
---
# Guest checkout times out on slow 3G
…'''
fm_html = e(fm).replace('issue: "https://github.com/acme/checkout/issues/451"', '<span class="hl">issue: "https://github.com/acme/checkout/issues/451"</span>')
picker = (f'<div class="pop" style="margin:-6px 0 12px 96px;width:330px;gap:0;padding:6px 0;font-size:12px;line-height:16px">'
          f'<div class="fld focus" style="margin:0 8px 6px">{g("search")}<span>checkout spin</span></div>'
          + "".join(f'<div class="lrow{" hi" if j == 0 else ""}" style="height:26px;font-size:12px">{imark()}<span class="ell"><b>{a}</b></span><span class="num" style="margin-left:auto">#{n}</span></div>'
                    for j, (a, n) in enumerate([("Checkout spinner never ends on slow networks", 451), ("Spinner overlaps the total on iPad", 448), ("Checkout: retry after a network error", 431)]))
          + f'<div style="height:1px;background:{RULE};margin:5px 0"></div><div class="t2" style="padding:0 12px;height:22px;display:flex;align-items:center">Paste an issue link, or type #number</div></div>')
link_field = f'<div class="pb" style="margin-top:-6px"><div class="pl"><span class="k">issue</span><span class="fld focus" style="width:240px;height:20px">checkout spin|</span></div></div>{picker}'
board("03-link", 1500, 1060, "3 · The link on disk, and in the note", "issue: one quoted URL; shown live in the note's properties; Link Issue… completes from the repo.", bd(1500, 1060,
    "3 · The link: <code>issue:</code>, one URL, in the task’s frontmatter",
    "A task can track <b>one</b> GitHub issue. Duo writes the full URL, quoted, by key, through the editor’s buffer when the note is open (DL-13). It reads <code>owner/repo#123</code>, <code>#123</code> and an <code>issues:</code> list too, and never rewrites them. Other issue or PR links in <code>references:</code> (DL-150) show live state on their rows, with no bridge offers. [P]",
    f'''<div style="display:flex;gap:20px;align-items:flex-start">
{frame(task_note_pane(470), 470, 700, "Linked: the issue row in the note’s properties", "The issue’s mark, number and title (from GitHub, cached), its state and labels in <code>text2</code>, and the open arrow. A click opens the issue in the right pane (board 4); ⌘-click on GitHub. Right-click: Open on GitHub, Copy Link, Change Issue…, Unlink.")}
{frame('<div style="display:flex;flex-direction:column;height:100%"><div class="ltab"><span>Project</span><span class="on">Guest checkout times out…</span><span>+</span></div><div style="padding:18px 24px;white-space:normal"><div class="pb"><div class="sl" style="margin-bottom:2px">Properties</div><div class="pl"><span class="k">status</span><span>in-progress</span></div><div class="pl"><span class="k">due</span><span>2026-10-16</span></div></div>' + link_field + '</div></div>', 470, 700, "Link Issue… (card menu, task menu, or + in properties)", "Completes from the project repo’s open issues: words match titles, <code>#</code> matches numbers. A pasted URL from any repo works. Return writes <code>issue:</code>. Without <code>gh</code>, only a pasted link or <code>#number</code> works, and the row shows the number until Duo can read it.")}
<div style="display:flex;flex-direction:column;gap:14px;flex:1">
{txt(f'<h3>On disk: <code>tasks/guest-checkout-timeout.md</code></h3><pre class="fm">{fm_html}</pre>')}
{txt("""<h3>Why one URL, in its own key</h3><ul>
<li>A URL property is a link in Obsidian and OKF tools. <code>#451</code> alone means nothing outside the repo.</li>
<li>Works for GitHub Enterprise hosts and in a task moved to Home.</li>
<li>One tracked issue keeps “close it too” unambiguous. Mentions go in <code>references:</code>.</li></ul>
<p class="note"><b>Alternatives:</b> only <code>references:</code> (no new key, but which issue is “the” one?); an <code>issues:</code> list (the close offer must ask which).</p>""")}</div></div>'''))

# ======================================================================
# 04 · W-A: the Issues lane
menu = (f'<div class="menu" style="width:250px">'
        f'<div class="hd">Show</div><div class="hi">✓&nbsp;Assigned to me (Mine)</div><div>Mentioning me</div><div>All open</div><div>Label{g("chev")}</div>'
        f'<div class="sep"></div><div>Ask Claude to Triage…</div><div>Refresh</div><div>Open Issues on GitHub</div><div class="sep"></div><div>Hide Issues Lane</div></div>')
signin = (f'<div class="isc" style="gap:8px"><div style="font-weight:600">Sign in to GitHub to see issues here</div>'
          f'<div class="t2" style="font-size:12px;line-height:16px">Duo uses the GitHub CLI’s sign-in and never keeps a token.</div><span class="b sm" style="align-self:flex-start">Sign In in a Shell…</span></div>')
empty = f'<div class="drop" style="height:auto;padding:10px;white-space:normal;text-align:center">No open issues assigned to you in {REPO}</div>'
win4 = pwindow(WW, WH, wa_board() + issue_pane(), ptb())
board("04-lane", 2260, 1180, "4 · W-A: an Issues lane on the board", "The board's first lane: GitHub issues not yet tracked by a task. A click shows the issue; a drag makes a task.", bd(2260, 1180,
    "4 · W-A, recommended: an <b>Issues</b> lane, the board’s first",
    "The project’s board (DL-148, C) gains a first lane, <b>ISSUES · n</b>: open GitHub issues in the project’s repo that no task tracks yet, filtered to <i>assigned to me</i> by default. Its well is dashed: it’s a source, not a status. A click shows the issue read-only in the right pane, where a card’s note goes. <b>Dragging an issue into a lane makes a task</b> linked to it, with that lane’s status (board 7). Shown only for a repo with a GitHub remote and issues on. At 1440 Done folds to its strip to make room. [P]",
    f'''<div style="display:flex;gap:28px;align-items:flex-start">{frame(win4, WW, WH, "1440 × 900: #482 selected", "Order: recently updated first (GitHub’s). Labels are plain <code>text2</code> words: GitHub’s label colours would break Duo’s quiet palette. A drag within the lane does nothing.")}
<div style="display:flex;flex-direction:column;gap:18px;width:700px">
<div style="display:flex;gap:18px;align-items:flex-start">{frame(f'<div style="padding:12px;background:{PANE}">{menu}</div>', 274, None, "The lane’s filter menu")}
<div style="display:flex;flex-direction:column;gap:12px;flex:1">{frame(f'<div style="padding:10px;background:{GROUND};width:220px">{signin}</div>', 240, None, "No gh, or signed out")}{frame(f'<div style="padding:10px;background:{GROUND};width:220px">{empty}</div>', 240, None, "Nothing assigned")}</div></div>
{txt("""<h3>The issue in the right pane [P]</h3><ul>
<li>Drawn like a note: the repo and number in mono, the title, a <b>From GitHub</b> properties block (state, labels, assignees, milestone, comments), the body rendered read-only, the last two comments.</li>
<li><b>Make Task</b> (into Open), <b>Open on GitHub</b>, <b>Ask Claude About It…</b> (a drafted instruction, board 9).</li>
<li>“Read-only · from GitHub at 10:32”: the cache’s age. Offline it stays, with “offline” after the time.</li>
<li>The body is GitHub’s text: links open per DL-3, images load only from GitHub’s own hosts [U].</li></ul>""")}
{txt("""<h3>Rules</h3><ul>
<li><b>Polling:</b> while the board shows (dormant off screen, ENH-45), every 5 min with the repo fetch; one query for the lane and one for every linked issue’s state. Cached in <code>.duo/issues.json</code>.</li>
<li>Never asks GitHub for Project fields without the scope (F-267).</li>
<li><b>Hide Issues Lane</b> is per project, kept in <code>.duo/</code>, not the brief.</li>
<li>A session dropped on an issue card makes the task and puts the session in it.</li></ul>""")}</div></div>'''))

# ======================================================================
# 05 · W-B and W-C
def wb_list():
    rows = "".join(f'<div class="r{" sel" if j == 0 else ""}">{imark()}<div style="display:flex;flex-direction:column;min-width:0;flex:1"><span style="font-weight:600" class="ell">{e(i["t"])} <span class="num">#{i["n"]}</span></span><span class="t2" style="font-size:12px;line-height:16px">{e(i["lab"])} · opened by {i["by"]} · updated {i["up"]}</span></div><span class="t2" style="font-size:12px">{"" if j else "no task"}</span></div>'
                   for j, i in enumerate(ISSUES + [dict(n=451, t="Checkout spinner never ends on slow networks", lab="bug · p1", by="dana-k", up="4h")]))
    hdr = (f'<div style="display:flex;align-items:center;gap:8px;height:38px;flex:none;padding:0 16px;border-bottom:1px solid {RULE}"><span class="sl">Issues · 5</span>'
           f'<span class="filter" style="width:180px;margin-left:8px">{g("search")}Filter issues</span><span class="popup">Assigned to me{g("updown")}</span><span style="flex:1"></span><span class="btn" style="align-self:center;height:22px">New Issue…</span></div>')
    return f'<div style="flex:1;min-width:0;display:flex;flex-direction:column;border-right:1px solid {RULE}">{hdr}<div class="ilist" style="padding-top:6px">{rows}</div></div>'


winB = pwindow(WW, WH, wb_list() + issue_pane(), ptb(third="on"))
board("05-where", 2260, 1180, "5 · W-B and W-C: a third segment, or a picker only", "The alternatives to the Issues lane.", bd(2260, 1180,
    "5 · The alternatives: W-B, a third segment; W-C, a picker only",
    "W-B gives issues a view of their own; W-C gives them none and links from the task side only. Both are cheaper to explain than W-A and weaker at pulling work onto the board. [P]",
    f'''<div style="display:flex;gap:28px;align-items:flex-start">{frame(winB, WW, WH, "W-B · Sessions | Tasks | Issues", "A list of the repo’s issues over the left and middle panes, the issue in the right pane, Make Task there. A second place to look, and the board doesn’t show what’s waiting on GitHub.")}
<div style="display:flex;flex-direction:column;gap:18px;width:700px">
{frame('<div style="display:flex;flex-direction:column;height:100%"><div class="ltab"><span>Project</span><span class="on">Guest checkout times out…</span><span>+</span></div><div style="padding:18px 24px;white-space:normal"><div class="pb"><div class="sl" style="margin-bottom:2px">Properties</div><div class="pl"><span class="k">status</span><span>in-progress</span></div></div>' + link_field + '</div></div>', 470, 470, "W-C · picker only", "No issue surface. Link Issue… in the card and task menus and the note’s properties (as board 3); New Task from Issue… in + New task’s menu. Issues stay invisible until you go looking.")}
{txt(table(["", "W-A · lane", "W-B · segment", "W-C · picker"], [
    ["Mental model", "pull work onto your board", "GitHub’s list beside your board", "tasks can point at issues"],
    ["Reuse", "lanes, cards, drag, strip, filter, right pane", "the switch, right pane; a new list", "property rows"],
    ["Cost", "M", "M–L", "S"],
    ["Risk", "two kinds of card: the mark rule (board 7)", "two places; drift", "invisible"],
    ["Verdict", '<span class="verdict">recommended</span>', '<span class="verdict no">no</span>', '<span class="verdict no">the first slice’s subset</span>']], 110))}</div></div>'''))

# ======================================================================
# 06 · bridges
done_nt = nt('Marked “Guest checkout times out on slow 3G” done.', ["Close #451 too", "Undo"], 520)
gone_card = tcard(TT["waiting"][0])
pr_block = fr("Pull request", f'<div style="display:flex;flex-direction:column;gap:6px"><span class="cb"><i>{TICK}</i>Open a pull request into <b style="font-weight:600">{REPO}</b> <span class="popup" style="height:22px">main{g("chevd")}</span></span>'
              f'<div class="fld" style="height:auto;min-height:84px;align-items:flex-start;padding:5px 8px;white-space:normal;font-size:12px;line-height:17px;flex-direction:column;gap:6px">'
              f'<span>Stops the payment step spinning forever on slow networks: a 20 s timeout with a retry and a plain error.</span><span class="hl" style="font-family:ui-monospace,monospace">Closes #451</span></div>'
              f'<span class="cb"><i>{TICK}</i>Closes #451 · Guest checkout times out on slow 3G</span><span class="cb"><i class="off"></i>Closes #436 · Checkout copy audit <span class="t2">(in Review)</span></span></div>', top=True)
sheet6 = f'<div class="sheet" style="width:640px"><h2>Push to GitHub</h2>{pr_block}<div class="btns"><span class="b" style="margin-right:auto">Ask Claude to Write These</span><span class="b">Cancel</span><span class="b def">Push and Open PR</span></div></div>'
board("06-bridge", 2000, 640, "6 · Bridging a task and its issue: offers, never automatic", "Close too; closed on GitHub; Closes #n in the PR.", bd(2000, 640,
    "6 · Bridges: Duo <b>offers</b>; nothing changes GitHub or a note on its own",
    "The task’s status and the issue’s state stay separate facts. Where one moves, Duo offers the other, in places that already exist: Mark Complete’s notice (DL-130), the card’s line 2, the note’s properties, and the Push sheet (DL-149). [P]",
    f'''<div style="display:flex;gap:24px;align-items:flex-start">
<div style="display:flex;flex-direction:column;gap:18px;width:560px">
{frame(f'<div style="padding:18px;background:{GROUND}">{done_nt}</div>', 560, None, "A tracked task is marked Done", "Mark Complete’s 5-second notice gains <b>Close #451 too</b>: <code>gh issue close 451 -R acme/checkout</code> (completed). Undo while the notice shows reopens it. Dropped offers nothing; Close as not planned is in the issue’s menu.")}
{frame(f'<div style="padding:12px;background:{GROUND};width:250px">{gone_card}</div>', 274, None, "GitHub closed it first", "Line 2: <b>#440 closed on GitHub</b> in <code>text</code> semibold (not <code>needsYou</code>: that stays for sessions, as overdue does). The note’s issue row offers <b>Mark Done</b> (board 3’s second state). Reopened on GitHub: “reopened on GitHub · Reopen Task”.")}</div>
{frame(f'<div style="padding:0 0 18px;background:rgba(31,35,40,.32);display:flex;justify-content:center">{sheet6}</div>', 700, None, "Push: “Closes #n” in the pull request", "The Push sheet’s drafted description ends with one <code>Closes #n</code> per open task in this project that tracks an issue in this repo: a ticked row for in-progress tasks, unticked for the rest. GitHub links the PR and closes the issue on merge: no sync for Duo to do. Without <code>gh</code>, the compare page takes the same body.")}
{txt(table(["When", "Duo offers", "Choosing it"], [
    ["Task marked Done", "Close #n too", "<code>gh issue close</code>; Undo reopens"],
    ["Issue closed on GitHub", "closed on GitHub · Mark Done", "<code>status: done</code>"],
    ["Issue reopened", "reopened · Reopen Task", "<code>status: open</code>"],
    ["Push opens a PR", "Closes #n rows", "GitHub closes on merge"],
    ["Task dropped", "nothing", "—"]], 140), w=560)}</div>'''))

# ======================================================================
# 07 · cards and the drag
var = [
    ("A task", tcard(TT["open"][0]), "The box: yours, on disk. Unchanged from DL-148."),
    ("A task that tracks an issue", tcard(TT["in-progress"][0], sess="rows"), "The issue chip leads line 2: mark and <code>#451</code> in <code>text2</code>. Sessions as S1 rows."),
    ("…closed on GitHub", tcard(TT["waiting"][0]), "<code>text</code> semibold: it wants a decision."),
    ("An issue, not a task", issue_card(ISSUES[0]), "The <b>issue mark</b> in place of the box; the number in mono after the title; labels as words."),
    ("An issue, closed (All filter)", issue_card(dict(ISSUES[3], closed=True)), "The ticked mark. Closed issues show only with a filter that asks for them."),
]
var_html = "".join(f'<div style="display:flex;gap:14px;align-items:flex-start"><div style="width:240px;flex:none">{c}</div><div class="note" style="flex:1"><b>{a}.</b> {n}</div></div>' for a, c, n in var)
slot = '<div class="tc ghost" style="height:52px;justify-content:center;font-size:12px">becomes a task here</div>'
lift = f'<div style="position:absolute;left:600px;top:150px;width:220px">{issue_card(ISSUES[0], lift=True)}</div>'
drag_lanes = (issues_lane(cards=[dict(ISSUES[0], ghost=True)] + ISSUES[1:3], w=200).replace(issue_card(dict(ISSUES[0], ghost=True)), issue_card(ISSUES[0], ghost=True))
              + task_lanes(["open", "in-progress"], drop_into="in-progress", slot=slot))
drag = f'<div style="position:relative;display:flex;gap:10px;padding:12px;background:{PANE};width:820px;height:520px;overflow:hidden">{drag_lanes}{lift}</div>'
new_fm = '''---
type: task
title: Apple Pay button misaligned on iPad
status: in-progress
issue: "https://github.com/acme/checkout/issues/482"
sessions: []
created: 2026-10-09
---
# Apple Pay button misaligned on iPad

## Done when

## Notes
From GitHub, 2026-10-09:
> On iPad the Apple Pay button sits 12 px right of…'''
board("07-cards", 2000, 780, "7 · Cards, and dragging an issue onto the board", "A box is a task; the issue mark is GitHub's. A drag from the Issues lane makes a linked task.", bd(2000, 780,
    "7 · At a glance: a <b>box</b> is a task, the <b>issue mark</b> is GitHub’s; a drag turns one into the other",
    "Everything else is the task board’s, unchanged: frame, selection, hover, session rows, the lift, ghost, dashed target and slot, ⌥⌘← / ⌥⌘→, and VoiceOver’s “Move to ▸” (“Make Task in ▸” on an issue). The shapes differ even in the 34-wide strip: a square box, a round mark. [P]",
    f'''<div style="display:flex;gap:24px;align-items:flex-start">
<div style="display:flex;flex-direction:column;gap:14px;width:620px">{txt(f'<h3>The five cards</h3><div style="display:flex;flex-direction:column;gap:12px">{var_html}</div>')}</div>
{frame(drag, 820, 520, "Dragging #482 from Issues into In progress", "The card lifts; In progress takes <code>selected</code> with a dashed edge; the slot says what happens. On drop the issue leaves the lane and a task card appears at its computed place. ⌘Z deletes the new note and the issue comes back.")}
{txt(f'<h3>What the drop writes</h3><pre class="fm">{e(new_fm)}</pre><p class="note">A new note from the project’s task template (DL-146), with <code>title</code>, <code>status</code> and <code>issue</code> set by key, and the issue body quoted once under Notes. Nothing on GitHub changes. <code>duo2 task new "…" --issue acme/checkout#482 --status in-progress</code>.</p>', w=470)}</div>'''))

# ======================================================================
# 08 · a GitHub Project as a board source (later)
PJ = {
    "No Status": [dict(n=430, t="Gift cards at checkout", lab="Sprint 15", up="")],
    "Todo": [dict(n=477, t="Add an order notes field", lab="Sprint 14 · sam-o", up=""), dict(n=469, t="Saved cards: warn before a card expires", lab="Sprint 14", up="")],
    "In Progress": [],
    "In Review": [dict(n=436, t="Checkout copy audit", lab="Sprint 14 · PR #488", up="")],
    "Done": [dict(n=420, t="Remove the coupon banner", lab="Sprint 13", up="", closed=True)],
}


def pj_card(i):
    meta = f'<span>{e(i["lab"])}</span>'
    return (f'<div class="isc"><div class="tt">{imark(i.get("closed"))}<span style="flex:1;min-width:0">{e(i["t"])} <span class="num">#{i["n"]}</span></span></div><div class="mt">{meta}</div></div>')


linked = tcard(dict(t="Guest checkout times out on slow 3G", o="Geoff", issue=dict(n=451), ss=[("needs", "Timeout repro on 3G", "4m")]), sess="rows").replace(
    '<div class="mt">', '<div class="mt"><span>Sprint 14</span>', 1)
pl = []
for k, cs in PJ.items():
    body = "".join(pj_card(i) for i in cs)
    if k == "In Progress":
        body = linked + body
    pl.append(lane(k, k, body, len(cs) + (1 if k == "In Progress" else 0)))
pj_hdr = (f'<span class="popup" style="font-weight:600">{imark()}GitHub: Q4 Checkout (acme #7){g("updown")}</span>')
pj_board = (f'<div style="flex:1;min-width:0;display:flex;flex-direction:column;min-height:0;border-right:1px solid {RULE}">'
            + board_header(n=6).replace('<span class="sl">Tasks · 6</span>', pj_hdr).replace("+ New task", "+ Add Item").replace(f'<span class="popup">Anyone{g("updown")}</span>', f'<span class="popup">Anyone{g("updown")}</span><span class="popup">Iteration: Current{g("updown")}</span>')
            + f'<div style="display:flex;gap:10px;flex:1;min-height:0;padding:10px 16px 16px;overflow:hidden">{"".join(pl)}</div></div>')
win8 = pwindow(WW, WH, pj_board + task_note_pane(), ptb())
src_menu = (f'<div class="menu" style="width:290px"><div class="hd">Board</div><div>✓&nbsp;Tasks</div><div class="sep"></div><div class="hd">GitHub Projects for acme/checkout</div>'
            f'<div class="hi">Q4 Checkout (acme #7)</div><div>Payments roadmap (acme #3)</div></div>')
scope = (f'<div class="isc" style="gap:8px;width:300px"><div style="font-weight:600">Duo needs permission to see your GitHub projects</div>'
         f'<div class="t2" style="font-size:12px;line-height:16px">The GitHub CLI’s sign-in doesn’t include projects yet. Allowing it opens GitHub in your browser once; Duo still keeps no token.</div>'
         f'<span class="b sm" style="align-self:flex-start">Allow in a Shell…</span><span class="mono t2" style="font-size:11px">gh auth refresh -s read:project</span></div>')
board("08-projects", 2260, 1180, "8 · Later: a GitHub Project as a board source", "Same board; the Project's Status options as lanes; a drag writes Status.", bd(2260, 1180,
    "8 · Later (ENH-68): a GitHub Project as the board’s <b>source</b>",
    "The board header’s <code>TASKS · n</code> becomes a source popup when the repo’s owner has Projects linked to it. A Project shows in the same board: its column field’s options (Status by default) are the lanes, in GitHub’s order, with <b>No Status</b> first; items are cards with the issue mark; a drag writes the field with <code>gh project item-edit</code>; ⌘Z writes it back. Sessions attach through the local task that tracks the item’s issue. Columns are edited on GitHub (no + Add Column). [P]",
    f'''<div style="display:flex;gap:28px;align-items:flex-start">{frame(win8, WW, WH, "Q4 Checkout, current iteration", "The linked task’s card (box, chip, S1 rows) sits in GitHub’s In Progress because its issue’s item is there. Order inside a lane is GitHub’s stored position; a drag inside a lane does nothing, as on the task board.")}
<div style="display:flex;flex-direction:column;gap:18px;width:700px">
<div style="display:flex;gap:18px;align-items:flex-start">{frame(f'<div style="padding:12px;background:{PANE}">{src_menu}</div>', 314, None, "The source popup")}{frame(f'<div style="padding:10px;background:{GROUND}">{scope}</div>', 322, None, "Without the scope")}</div>
{txt(table(["Projects v2", "On Duo’s board"], [
    ["Status, or the view’s column field", "lanes, GitHub’s order"], ["No value", "No Status lane"], ["Iteration", "Iteration ▾ filter; “Sprint 14” on line 2"],
    ["Assignees", "Anyone ▾; owner on line 2"], ["Labels, milestone", "line 2 words"], ["Text, number, date fields", "line 2 (ENH-36 chooses)"],
    ["Item position", "order inside a lane"], ["Draft issue", "a card with no mark or number"], ["Built-in workflows", "run on GitHub; Duo shows the result"]], 220))}
{txt("""<h3>Why later</h3><ul><li>A second data model for the board (GitHub’s fields, positions, workflows).</li><li>A scope every user must grant; fine-grained tokens can’t see user-owned Projects at all.</li><li>Org-only webhooks: polling.</li><li>Linking (B) gives most of the value first, and this board reuses B’s card and chip unchanged.</li></ul>""")}</div></div>'''))

# ======================================================================
# 09 · Duo and Claude
hook = ('Duo: this session is in the task "Guest checkout times out on slow 3G" (tasks/guest-checkout-timeout.md, in progress). '
        'It tracks GitHub issue acme/checkout#451 (open; labels: bug, p1; assigned: geoffd): https://github.com/acme/checkout/issues/451. '
        'Read it with `gh issue view 451 -R acme/checkout --comments`. Change the issue on GitHub only when the user asks. '
        'A pull request for this work should say "Closes #451".')
cons = (f'<div style="background:{CONSOLE};padding:16px 20px;height:100%;white-space:normal" class="mono cl">'
        f'<div style="color:{CTEXT2}">SessionStart hook · additionalContext (DL-116, one line added)</div><div style="margin-top:8px">{e(hook)}</div>'
        f'<div style="color:{CTEXT2};margin-top:18px">UserPromptSubmit, only when something changed:</div><div style="margin-top:6px">Duo: acme/checkout#451 was closed on GitHub.</div></div>')
triage = ("Look at the open issues in acme/checkout that are assigned to me (gh issue list --assignee @me). For each, suggest labels from the repo’s existing ones "
          "(gh label list), say whether it’s a duplicate, and propose a one-line next step. Don’t change anything on GitHub until I say which to apply; then use gh issue edit.")
about = "Read acme/checkout#482 with its comments and tell me in five lines what’s being asked and what’s unclear. Don’t change anything on GitHub."
verbs = """duo2 issue list   [--project p] [--mine|--mentions|--all|--label l|--search q] [--json]
duo2 issue show   <ref> [--refresh] [--json]
duo2 issue open   <ref>
duo2 issue close  <ref> [--not-planned] [--comment c] --yes
duo2 issue reopen <ref> --yes
duo2 issue new    --from-task <task> [--web] [--yes]
duo2 issue lane   [show|hide] [--filter mine|mentions|all|label:l]
duo2 issue triage [--project p]             prints the drafted instruction
duo2 task issue   <task> <ref> | --clear      Link Issue… / Unlink
duo2 task new     [title] --issue <ref> [--status lane]
# later (board 8)
duo2 task board   --source tasks|github:<owner>/<n>
duo2 project-item set <ref> <field> <value> --yes"""
board("09-claude", 1600, 1000, "9 · Duo and Claude: what Claude is told, drafted instructions, duo2", "One line in DL-116's hook; drafted instructions; every button a verb.", bd(1600, 1000,
    "9 · Duo and Claude: one line more for Claude, drafted instructions, and a verb for every button",
    "Claude already runs <code>gh</code>. Duo tells it which issue a task tracks and its state, never the body (Claude reads it with <code>gh</code> when it needs it; the body is untrusted data). Triage and wording are Claude’s, from instructions shown before sending, as DL-149’s Ask Claude to Write These. [P]",
    f'''<div style="display:flex;gap:20px;align-items:flex-start">
{frame(cons, 640, 420, "What Claude is told", "<code>&lt;ref&gt;</code> anywhere is a URL, <code>owner/repo#n</code> or <code>#n</code> (the project’s GitHub remote).")}
<div style="display:flex;flex-direction:column;gap:14px;flex:1">
{txt(f'<h3>Ask Claude to Triage… <span class="t2" style="font-weight:400">(the Issues lane’s menu)</span></h3><div class="pre">{e(triage)}</div><h3 style="margin-top:12px">Ask Claude About It… <span class="t2" style="font-weight:400">(the issue in the right pane)</span></h3><div class="pre">{e(about)}</div><p class="note">Shown before sending, in the project’s open session or a new one. <b>New Session in Task</b> on a task that tracks an issue drafts its first prompt from the issue (DL-112).</p>')}
{txt(f'<h3>duo2 (DL-71)</h3><pre class="fm" style="font-size:11px;line-height:16px">{e(verbs)}</pre><p class="note">Anything that writes to GitHub needs <code>--yes</code> outside a sheet, as <code>duo2 repo push</code> does. Failures exit non-zero with the question’s words (DL-149).</p>')}</div></div>'''))

# ======================================================================
# 10 · recommendation
board("10-recommendation", 1440, 860, "10 · Recommendation and slices", "Link, don't mirror; the Issues lane; a few explicit writes; Projects later.", bd(1440, 860,
    "10 · Recommendation and slices",
    "Each slice stands alone and reuses what’s built: the task board (DL-148), the repo plumbing (DL-149, DL-157), DL-116’s hook. [P]",
    f'''<div style="display:flex;gap:16px">
{txt("""<h3>Slice 1 · Link <span class="t2" style="font-weight:400">S · v1 (recommended)</span></h3><ul>
<li><code>issue:</code> on a task; Link Issue… (board 3); the chip on the card.</li>
<li>Make Task from Issue (menu, <code>duo2 task new --issue</code>).</li>
<li>Poll linked issues’ state; <code>.duo/issues.json</code>.</li>
<li>What Claude is told (board 9).</li>
<li>“Closes #n” in Push’s PR (board 6).</li></ul>""", flex=True)}
{txt("""<h3>Slice 2 · The lane <span class="t2" style="font-weight:400">M · v1.1</span></h3><ul>
<li>The Issues lane, its filter and sign-in card (board 4).</li>
<li>The issue in the right pane.</li>
<li>Bridge offers: Close too, closed on GitHub (board 6).</li>
<li>New Issue from Task (sheet with gh; GitHub’s page without).</li>
<li>Ask Claude to Triage / About It.</li></ul>""", flex=True)}
{txt("""<h3>Later · Projects <span class="t2" style="font-weight:400">L · ENH-68</span></h3><ul>
<li>A Project as a board source (board 8).</li>
<li>The scope step.</li>
<li>Iteration filter, field mapping.</li></ul>
<h3 style="margin-top:12px">Never</h3><ul><li>Mirroring issues into notes (C).</li><li>A label editor, comments, assignee pickers in Duo.</li></ul>""", flex=True)}</div>'''))

with open(os.path.join(OUT, "manifest.json"), "w") as f:
    json.dump(BOARDS, f, indent=1)
print(f"{len(BOARDS)} boards in {OUT}")
