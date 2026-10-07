#!/usr/bin/env python3
"""Draws the GitHub study boards (every mark [P]) as static HTML in the Duo design system.

    python3 docs/design/github-study/canvas/make.py
    bash docs/design/github-study/canvas/render.sh

Reuses the home-evolution study's tokens, CSS and drawing helpers (everything above its
"# ---------- boards" line), as the project & task CX study does, so the studies draw the same app.
The sheet CSS is copied from the CX study's make.py (research/project-task-cx), whose New project
sheet this study adds "From GitHub" to. Names, repos and data are illustrative.
"""
import html, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(HERE, "../../home-evolution-handoff/canvas/make.py")).read()
exec(_src[:_src.index("# ---------- boards ----------")].replace('OUT = os.path.join(HERE, "boards")', ""))
OUT = os.path.join(HERE, "boards")
STUDY = "github-study"

# ---- the CX study's sheet CSS (copied) ----
CSS += f"""
.sheetwrap{{position:relative;flex:1;min-height:0;display:flex;justify-content:center;background:rgba(31,35,40,.32)}}
.sheet{{width:600px;background:{GROUND};border:1px solid {RULE};border-top:none;border-radius:0 0 10px 10px;box-shadow:0 12px 32px rgba(31,35,40,.22);padding:18px 24px 18px;display:flex;flex-direction:column;gap:12px;white-space:normal;align-self:flex-start}}
.sheet h2{{margin:0;font-size:13px;line-height:20px;font-weight:600}}
.fr{{display:grid;grid-template-columns:96px 1fr;column-gap:12px;align-items:center}}
.fr>label{{text-align:right;color:{TEXT}}}
.fr.top{{align-items:start}}.fr.top>label{{padding-top:2px}}
.fld{{height:24px;border:1px solid {RULE};border-radius:6px;background:{PANE};padding:0 8px;display:flex;align-items:center;gap:6px;white-space:nowrap;overflow:hidden}}
.fld.ph{{color:{TEXT2}}}
.fld.focus{{border-color:#0A64D2;box-shadow:0 0 0 3px rgba(10,100,210,.18)}}
.hint{{font-size:12px;line-height:16px;color:{TEXT2}}}
.btns{{display:flex;justify-content:flex-end;gap:8px;margin-top:4px}}
.b{{display:inline-flex;align-items:center;height:24px;padding:0 12px;border:1px solid {EDGE};border-radius:6px;background:{PANE};font-size:13px;white-space:nowrap}}
.b.def{{border:1.5px solid {TEXT};font-weight:600}}
.b.sm{{height:22px;font-size:12px;padding:0 9px}}
.b.dim{{color:{EDGE};border-color:{RULE}}}
.cb{{display:inline-flex;align-items:center;gap:8px}}
.cb i{{width:14px;height:14px;border-radius:4px;background:#0A64D2;display:inline-flex;align-items:center;justify-content:center;flex:none}}
.cb i.off{{background:{PANE};border:1px solid {EDGE}}}
.rb{{display:inline-flex;align-items:center;gap:8px}}
.rb i{{width:14px;height:14px;border-radius:7px;border:1px solid {EDGE};background:{PANE};display:inline-flex;align-items:center;justify-content:center;flex:none}}
.rb i.on{{border:4px solid #0A64D2}}
.pre{{background:{PANE};border:1px solid {RULE};border-radius:6px;padding:8px 10px;font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:11px;line-height:17px;color:{TEXT};white-space:pre-wrap}}
.pre .k{{color:{TEXT2}}}
.found{{display:flex;flex-direction:column;gap:4px;background:{PANE};border:1px solid {RULE};border-radius:6px;padding:8px 10px}}
.found div{{display:flex;gap:8px;align-items:baseline}}
.notice{{display:flex;align-items:center;gap:10px;background:{PANE};border:1px solid {EDGE};border-radius:8px;padding:6px 8px 6px 12px;box-shadow:0 4px 14px rgba(31,35,40,.12);white-space:normal}}
.expl{{background:{GROUND};border-radius:8px;padding:12px 14px;display:flex;flex-direction:column;gap:6px;white-space:normal}}
.expl b{{font-weight:600}}
.menu{{background:rgba(246,246,247,.98);border:1px solid {RULE};border-radius:8px;box-shadow:0 10px 30px rgba(31,35,40,.2);padding:5px 0;font-size:13px;line-height:20px;white-space:nowrap;display:flex;flex-direction:column}}
.menu div{{padding:1px 14px 1px 22px;display:flex;align-items:center;gap:8px}}
.menu .sep{{height:1px;background:{RULE};margin:5px 0;padding:0}}
.menu .hi{{background:#0A64D2;color:#fff;border-radius:5px;margin:0 5px;padding-left:17px}}
.menu .hd{{font-size:11px;font-weight:600;color:{TEXT2};letter-spacing:.3px;padding-left:14px}}
.menu .dim{{color:{EDGE}}}
.pP{{display:inline-block;font:600 10px/14px -apple-system,system-ui,sans-serif;color:{TEXT2};border:1px solid {EDGE};border-radius:7px;padding:0 5px;margin-left:6px;vertical-align:1px}}
"""
# ---- this study ----
CSS += f"""
.repo{{display:flex;align-items:center;gap:6px;min-height:22px;font-size:12px;line-height:16px;color:{TEXT2};white-space:nowrap;min-width:0}}
.repo b{{color:{TEXT};font-weight:600}}
.repo .bad{{color:{TEXT};font-weight:600}}
.badge{{display:inline-flex;align-items:center;height:18px;padding:0 7px;border:1px solid {RULE};border-radius:9px;font-size:11px;line-height:16px;color:{TEXT2};background:{PANE};white-space:nowrap}}
.badge.dk{{border-color:{TEXT};color:{TEXT};font-weight:600}}
.pop{{background:{PANE};border:1px solid {RULE};border-radius:8px;box-shadow:0 10px 30px rgba(31,35,40,.2);padding:10px 12px;display:flex;flex-direction:column;gap:6px;white-space:normal;font-size:12px;line-height:17px}}
.lrow{{display:flex;align-items:center;gap:8px;height:28px;padding:0 8px;border-radius:5px;font-size:13px;white-space:nowrap}}
.lrow.hi{{background:{SELECTED}}}
.lrow .r{{margin-left:auto;color:{TEXT2};font-size:12px}}
.ask2{{background:{GROUND};border:1px solid {RULE};border-radius:10px;box-shadow:0 12px 32px rgba(31,35,40,.22);padding:18px 22px;display:flex;flex-direction:column;gap:8px;white-space:normal;width:460px}}
.ask2 h3{{margin:0;font-size:13px;line-height:20px;font-weight:600}}
.ask2 p{{margin:0;font-size:12px;line-height:17px}}
.mark{{font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:11px;color:{TEXT2};margin-left:auto}}
.ft{{display:flex;align-items:center;gap:6px;height:22px;font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:12px}}
table.cmp{{border-collapse:collapse;width:100%;font-size:12px;line-height:17px;white-space:normal}}
table.cmp th,table.cmp td{{border-top:1px solid {RULE};padding:7px 10px 7px 0;text-align:left;vertical-align:top}}
table.cmp th{{font-weight:600;color:{TEXT2};width:150px}}
table.cmp thead th{{font:600 11px/16px -apple-system,system-ui,sans-serif;letter-spacing:.66px;text-transform:uppercase;color:{TEXT};border-top:none}}
.cl{{color:{CTEXT}}}
"""

TICK = '<svg width="10" height="8" viewBox="0 0 10 8"><path d="M1 4l2.6 2.6L9 1" fill="none" stroke="#fff" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>'


def br(color=None):
    """branch mark: two nodes joined, a quiet stroke glyph [P]"""
    c = color or TEXT2
    return (f'<svg width="10" height="12" viewBox="0 0 10 12" style="flex:none"><circle cx="2.5" cy="2.2" r="1.5" fill="none" stroke="{c}" stroke-width="1.2"/>'
            f'<circle cx="2.5" cy="9.8" r="1.5" fill="none" stroke="{c}" stroke-width="1.2"/><circle cx="7.5" cy="3.6" r="1.5" fill="none" stroke="{c}" stroke-width="1.2"/>'
            f'<path d="M2.5 3.7v4.6M7.5 5.1c0 2.2-5 1.6-5 3.2" fill="none" stroke="{c}" stroke-width="1.2"/></svg>')


def arrow(up=True, color=None):
    c = color or TEXT2
    d = "M4 9V1.8M1.2 4.5 4 1.6l2.8 2.9" if up else "M4 1v7.2M1.2 5.5 4 8.4l2.8-2.9"
    return f'<svg width="8" height="10" viewBox="0 0 8 10" style="flex:none"><path d="{d}" fill="none" stroke="{c}" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/></svg>'


def lock():
    return f'<svg width="10" height="11" viewBox="0 0 10 11" style="flex:none"><rect x="1.5" y="4.8" width="7" height="5.4" rx="1.2" fill="none" stroke="{TEXT2}" stroke-width="1.2"/><path d="M3.2 4.8V3.3a1.8 1.8 0 0 1 3.6 0v1.5" fill="none" stroke="{TEXT2}" stroke-width="1.2"/></svg>'


def warn(color=None):
    c = color or TEXT
    return f'<svg width="12" height="11" viewBox="0 0 12 11" style="flex:none"><path d="M6 1 11 10H1z" fill="none" stroke="{c}" stroke-width="1.2" stroke-linejoin="round"/><path d="M6 4.3v2.6" stroke="{c}" stroke-width="1.3" stroke-linecap="round"/><circle cx="6" cy="8.3" r=".7" fill="{c}"/></svg>'


def fr(label, body, top=False):
    return f'<div class="fr{" top" if top else ""}"><label>{label}</label><div>{body}</div></div>'


def seg(opts, on):
    return '<span class="segc" style="height:24px">' + "".join(f'<span class="{"on" if i == on else ""}">{o}</span>' for i, o in enumerate(opts)) + '</span>'


def tb_quiet(crumb="All projects"):
    return f'''<div class="tb">
<span class="tl"><i style="background:#FF5F57"></i><i style="background:#FEBC2E"></i><i style="background:#28C840"></i></span>
<span class="tgl">{g("sidebar")}</span><span style="font-weight:600">{crumb}</span>
<span class="srch">{g("search")}Search all projects<span style="margin-left:auto">⇧⌘A</span></span>
<span class="tgl" style="margin-left:4px">{g("right")}</span></div>'''


def sheet_over(w, h, sheet, crumb="All projects"):
    return f'<div class="w" style="width:{w}px;height:{h}px">{tb_quiet(crumb)}<div class="sheetwrap">{sheet}</div></div>'


def ask_over(w, h, ask, crumb="All projects › website › pricing-copy"):
    return f'<div class="w" style="width:{w}px;height:{h}px">{tb_quiet(crumb)}<div class="sheetwrap" style="align-items:flex-start">{ask}</div></div>'


SHEET_HEAD = f'''<h2>New project</h2>
<div class="hint" style="font-size:13px;line-height:19px">A project is one piece of work with an end, in its own folder. Its <span class="mono">_PROJECT.md</span> holds the goal, how it’s going and the next step, and Claude is told them. <span style="text-decoration:underline">Learn more</span></div>'''
START3 = ["A new folder", "A folder I have", "From GitHub"]

# ---------- board furniture ----------
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
STUDY BOARD [P], not approved. Drawn for the GitHub study (2026-10-07) with the Duo design system.
{e(note)}
It is a picture written in HTML: match what it draws, do not port its markup. Names, repos and data are illustrative.
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


def txt(inner, w=None, flex=False):
    st = f"width:{w}px;flex:none" if w else ("flex:1;min-width:0" if flex else "")
    return f'<div class="txt" style="{st}">{inner}</div>'


# ---------- the project window ----------
REPO = "acme/website"
BRANCH = "geoff/pricing-copy"


def repo_line(state="changed", button=True):
    """Option A: the repo line under the project's status line [P]."""
    s = {
        "clean": (f'<b>{BRANCH}</b>', "up to date with GitHub", None),
        "changed": (f'<b>{BRANCH}</b>', "3 files changed", "Push…"),
        "ahead": (f'<b>{BRANCH}</b>', f'{arrow(True)}2 to push', "Push…"),
        "new": (f'<b>{BRANCH}</b>', "not on GitHub yet", "Push…"),
        "pr": (f'<b>{BRANCH}</b>', '<span style="text-decoration:underline">PR #482</span> open · up to date', None),
        "pr-ahead": (f'<b>{BRANCH}</b>', f'<span style="text-decoration:underline">PR #482</span> · {arrow(True)}1 to push', "Push"),
        "behind": (f'<b>{BRANCH}</b>', f'{arrow(False)}4 new on GitHub', "Get Latest"),
        "conflict": (f'<b>{BRANCH}</b>', '<span class="bad">1 file in conflict</span>', "Resolve…"),
        "offline": (f'<b>{BRANCH}</b>', "can’t reach GitHub · checked 2 h ago", None),
        "readonly": (f'<b>{BRANCH}</b>', f'{lock()}read only · 2 to push to your fork', "Push…"),
        "protected": ('<b>main</b>', f'{lock()}protected · 1 to push', "Move to a Branch…"),
        "signedout": (f'<b>{BRANCH}</b>', "signed out of GitHub", "Sign In…"),
    }[state]
    btn = f'<span class="b sm" style="margin-left:auto;height:20px;font-size:11px;padding:0 8px">{s[2]}</span>' if (button and s[2]) else ""
    return (f'<div style="display:flex;flex-direction:column;gap:0"><div class="repo">{br()}<span class="ell">{s[0]}</span></div>'
            f'<div class="repo" style="padding-left:16px"><span style="display:inline-flex;align-items:center;gap:4px" class="ell">{s[1]}</span>{btn}</div></div>')


def srow(st, t, tm, tint=False):
    b = ' style="font-weight:600"' if st == "needs" else ""
    return (f'<div class="row{" tint" if tint else ""}">{g({"prompt": "idle"}.get(st, st))}'
            f'<span class="ti"{b}>{e(t)}</span><span class="tm t2">{e(tm)}</span></div>')


def file_rows(marks=True):
    m = (lambda x: f'<span class="mark">{x}</span>') if marks else (lambda x: "")
    return (f'<div class="ft">_PROJECT.md<span class="mark" style="font-family:inherit">kept out of git</span></div>'
            f'<div class="ft">{g("chevd")}content/</div>'
            f'<div class="ft" style="padding-left:18px">pricing.md{m("changed")}</div>'
            f'<div class="ft" style="padding-left:18px">faq.md{m("changed")}</div>'
            f'<div class="ft" style="padding-left:18px">plans.json{m("new")}</div>'
            f'<div class="ft">{g("chev")}src/</div><div class="ft">README.md</div>')


def left_pane(status="A", state="changed", w=300, notice=""):
    head = f'<div style="padding:14px 16px 8px"><div style="font-weight:600;font-size:14px">pricing-copy</div><div class="t2">On track · Ship by Oct 18</div>'
    if status == "A":
        head += f'<div style="margin-top:6px">{repo_line(state)}</div>'
    head += '</div>'
    rows = [sec("Needs you", 1, True), srow("needs", "Tighten the FAQ", "4m"), sec("Today"), srow("working", "Pricing headline options", "working", tint=True), srow("idle", "Plan table copy", "2h")]
    btn = f'<div style="display:flex;gap:8px;padding:10px 16px"><span class="btn">+ New session</span></div>'
    if status == "B":
        fh = (f'<div style="display:flex;align-items:center;gap:6px"><span class="sl">Files</span><span style="flex:1"></span>'
              f'<span class="repo" style="gap:4px">{br()}<b>{BRANCH}</b></span></div>'
              f'<div class="repo" style="gap:6px">3 changed · {arrow(True)}2 to push<span class="b sm" style="margin-left:auto;height:20px;font-size:11px;padding:0 8px">Push…</span></div>')
    else:
        fh = '<div class="sl">Files</div>'
    files = (f'<div style="margin-top:auto;border-top:2px solid {EDGE};padding:10px 16px 8px;display:flex;flex-direction:column;gap:2px">{fh}<div class="mono t2" style="font-size:11px">~/claude-home/website/pricing-copy</div>'
             f'<div style="margin-top:4px">{file_rows(marks=True)}</div></div>')
    return f'<div style="width:{w}px;flex:none;border-right:1px solid {RULE};display:flex;flex-direction:column;min-height:0;overflow:hidden;background:{PANE};position:relative">{head}{"".join(rows)}{btn}{notice}{files}</div>'


def ptoolbar(chip=False):
    c = ""
    if chip:
        c = (f'<span class="popup" style="margin-left:10px;gap:5px">{br()}{BRANCH}<span class="t2">· 3 changed</span>'
             f'<span style="display:inline-flex;align-items:center;gap:2px" class="t2">{arrow(True)}2</span>{g("chevd")}</span>')
    return f'''<div class="tb">
<span class="tl"><i style="background:#FF5F57"></i><i style="background:#FEBC2E"></i><i style="background:#28C840"></i></span>
<span class="tgl">{g("sidebar")}</span>
<span style="text-decoration:underline;color:{TEXT2}">All projects</span>{g("chev")}<span class="t2">website</span>{g("chev")}<span style="font-weight:600">pricing-copy</span>{c}
<span class="srch">{g("search")}Search all projects<span style="margin-left:auto">⇧⌘A</span></span>
<span class="tgl" style="margin-left:4px">{g("right")}</span>
</div>'''


def console(text=None):
    t = text or (f'Update content/pricing.md<br><span style="color:{CTEXT2}">Tightened the headline to “Pay for what you ship”</span><br><br>'
                 f'Update content/faq.md<br><span style="color:{CTEXT2}">Rewrote 3 answers about annual billing</span>')
    return (f'<div style="flex:1;min-width:0;background:{CONSOLE};display:flex;flex-direction:column;border-right:1px solid {RULE}">'
            f'<div class="ctab mono" style="display:flex;gap:22px;height:36px;align-items:center;padding:0 20px;border-bottom:1px solid {CRULE};color:{CTEXT2}"><span style="color:{CTEXT};display:flex;gap:6px;align-items:center">{g("needs")}Tighten the FAQ</span><span style="display:flex;gap:6px;align-items:center">{g("working", CTEXT2)}Pricing headline options</span><span>+</span></div>'
            f'<div class="mono cl" style="padding:16px 20px;flex:1;white-space:normal">{t}</div>'
            f'<div style="margin:0 20px 16px;border:1px solid {CRULE};border-radius:6px;height:30px;color:{CTEXT2};padding:5px 10px" class="mono">&gt; ▌</div></div>')


def project_tab(card=""):
    return (f'<div style="width:420px;flex:none;display:flex;flex-direction:column;min-height:0;background:{PANE};white-space:normal">'
            f'<div style="height:36px;border-bottom:1px solid {RULE};display:flex;align-items:center;padding:0 16px;gap:16px;flex:none"><span style="font-weight:600">Project</span><span class="t2">pricing.md</span><span class="t2">+</span></div>'
            f'{card}<div style="padding:14px 18px"><div style="font-size:20px;font-weight:600;line-height:28px">Pricing copy</div>'
            f'<div style="margin-top:6px">New pricing page copy for the October launch: headline, plan table, FAQ.</div></div></div>')


def pwindow(w, h, body, tb=None):
    return f'<div class="w" style="width:{w}px;height:{h}px;border:1px solid {RULE};border-radius:10px">{tb or ptoolbar()}<div style="display:flex;flex:1;min-height:0">{body}</div></div>'


def nt(msg, btns, w=560):
    return f'<div class="notice" style="width:{w}px"><span style="flex:1">{msg}</span>' + "".join(f'<span class="b" style="height:22px;font-size:12px">{b}</span>' for b in btns) + '</div>'


# ======================================================================
# 00 · the study
board("00-study", 1440, 980, "0 · GitHub in Duo: the study", "The ask, what changes from the legacy call, the principles, legacy and the landscape in short.", bd(1440, 980,
    "0 · GitHub in Duo: bring a repo in, see where it stands, share it back",
    "Geoff, 2026-10-07: “claude <i>can</i> perform cli tasks to operate github, but we should incorporate github primitives in many places; eg we should make it easy to add a project from remote (gh), as a new or existing branch, and make it easy to push and/or open a pr (anticipating that many users will not be admin).” Every mark on these boards is a proposal [P]. The research is in <code>docs/research/github-primitives.md</code>.",
    f'''<div style="display:flex;gap:14px;align-items:flex-start">
{txt(f"""<h3>What changes from the legacy call</h3>
<p><code>legacy-requirements.md</code> dropped “Git for PMs: worktrees UI, clone, pull, propose-changes PR, repo chips” from v1 as code-shaped. <b>This study brings back four of the five, reshaped</b>: getting a repo (as a new project), its state on the project, Push / Open PR (with the fork path), and Get Latest. The worktrees UI stays out. Kept from the call: the vanished-folder recovery and fail-closed probes.</p>
<h3>Principles [P]</h3><ul>
<li><b>Duo does the mechanics, Claude does the words.</b> Duo runs the network and permission steps the same way every time and explains their failures; Claude writes commit messages and PR descriptions and resolves conflicts, from an instruction Duo drafts.</li>
<li><b>Never a token.</b> Duo uses the user’s own <code>gh auth</code> or git’s credential helper (the macOS keychain). It never asks for, stores or reads a token.</li>
<li><b>Works without <code>gh</code>.</b> Paste a link, push with git, and open the pull request on GitHub’s own page. <code>gh</code> adds the repo picker, the fork path and PRs opened from Duo.</li>
<li><b>Assume no admin, maybe no write.</b> A project from GitHub starts on its own branch, so a protected main never blocks it; no write access means a fork, said plainly before it happens.</li>
<li><b>Not a git client.</b> No staging area, history graph, rebase or branch manager. One branch per project, set when it’s made.</li>
<li>Every action has a <code>duo2 repo</code> verb (DL-71). Nothing here shows a system alert.</li></ul>""", flex=True)}
{txt(f"""<h3>The boards</h3><ol start="0">
<li>This page.</li>
<li><b>New project, From GitHub</b>: inside the CX study’s sheet; the repo field and its picker.</li>
<li><b>The branch</b>: a new branch or one that’s there; A in the sheet, B one combined field.</li>
<li><b>Where it lands, and getting it</b>: a copy per project inside Home; progress, done.</li>
<li><b>The repo’s state on a project</b>: A under the status line, B in Files, C a toolbar chip.</li>
<li><b>Every state</b> of the line.</li>
<li><b>Push / Open PR</b> with write access.</li>
<li><b>No write access</b>: the fork, said before it happens.</li>
<li><b>No <code>gh</code></b>: push with git, open the PR on GitHub’s page.</li>
<li><b>Get Latest</b> and a conflict.</li>
<li><b>When it fails</b>: every failure with its words.</li>
<li><b>Duo and Claude</b>: who does what; the instructions Duo drafts.</li>
<li><b><code>duo2 repo</code></b>: the verbs.</li>
<li><b>Recommendation</b> and the v1 slice.</li></ol>
<h3>Shared with the CX study</h3><p class="note">The New project sheet, its Start from segment and its Name, Goal, In and Will write rows are the project &amp; task CX study’s (R3, R4). This study adds “From GitHub” and owns what shows when it’s picked.</p>""", w=520)}
</div>
<div style="display:flex;gap:14px;align-items:flex-start">
{txt("""<h3>Legacy Duo, in short (docs/research/github-primitives.md §1)</h3><ul>
<li><b>Repo chips</b> (branch, ahead/behind, modified): Geoff called v1 “very bad” for hiding when clean; took five rounds. Kept as an idea, redrawn.</li>
<li><b>Clone</b> from File, the tree and ⌘O; <code>gh repo clone</code> with a <code>git clone</code> fallback; raw stderr on failure.</li>
<li><b>Pull</b>: fetch, fast-forward or merge, abort on conflict; a red “Discard my changes and pull”. Shipped with no live walk.</li>
<li><b>Propose changes</b>: commit, push, auto-fork when not WRITE, <code>gh pr create</code>. Worked end to end; failures were raw stderr; forked even when the probe failed.</li>
<li><b>Worktrees UI</b>: Geoff’s favourite, but its sessions broke when a worktree was removed.</li></ul>""", flex=True)}
{txt("""<h3>What others do (§2)</h3><ul>
<li><b>GitHub Desktop</b>: one button that becomes Publish, Push, Pull or Fetch; asks before forking (“contribute to the parent” or “for my own purposes”).</li>
<li><b>VS Code</b>: Sync Changes; offers to fork when a push is refused.</li>
<li><b><code>gh pr create</code></b> offers to fork when you can’t push; <code>gh repo fork</code> renames your <code>origin</code> to <code>upstream</code> unless told not to.</li>
<li><b>Claude Code</b> already commits and runs <code>gh pr create</code> when asked; it doesn’t know your permissions until a push fails.</li>
<li><b>GitHub’s web editor</b> forks for you when you edit a repo you can’t write to: “Propose changes”.</li></ul>""", flex=True)}
</div>'''))

# ---------- 01 · new project from GitHub ----------
def sheet_github(repo_field, found, branch_rows, name="Pricing copy", goal="New pricing page copy, approved by marketing", lands="~/claude-home/website/pricing-copy", btn="Create Project", extra=""):
    return f'''<div class="sheet" style="width:640px">{SHEET_HEAD}
{fr("Start from", seg(START3, 2))}
{fr("Repository", repo_field)}
{found}
{branch_rows}
{fr("Name", f'<div class="fld">{name}</div>')}
{fr("Goal", f'<div class="fld">{goal}</div>')}
{fr("In", f'<span class="popup" style="height:24px;font-size:13px">{g("folder")} website{g("chevd")}</span> <span class="mono t2" style="margin-left:8px;font-size:11px">{lands}</span>')}
{fr("", '<div style="display:flex;flex-direction:column;gap:6px"><span class="cb"><i>' + TICK + '</i>Start a Claude session in it</span><span class="cb"><i>' + TICK + '</i>Keep <span class="mono">_PROJECT.md</span> out of git (listed in <span class="mono">.git/info/exclude</span>)</span></div>')}
{extra}
<div class="btns"><span class="b">Cancel</span><span class="b def">{btn}</span></div></div>'''


FOUND_OK = fr("", f'<div class="found"><div><b style="font-weight:600">acme/website</b><span class="t2">private · you can push · main is protected</span></div><div class="hint">Signed in to GitHub as geoffd (GitHub CLI).</div></div>')
BRANCH_A = (fr("Branch", f'<div style="display:flex;flex-direction:column;gap:6px"><span class="rb"><i class="on"></i>A new branch for this work</span>'
               f'<div style="display:flex;gap:8px;align-items:center;padding-left:22px"><div class="fld mono" style="flex:1;font-size:12px">{BRANCH}</div><span class="t2">from</span><span class="popup" style="height:24px">main{g("chevd")}</span></div>'
               f'<span class="rb"><i></i>A branch that’s already there</span></div>', top=True))
REPO_FIELD = f'<div style="display:flex;gap:8px"><div class="fld" style="flex:1">{lock()}acme/website</div><span class="b">Choose…</span></div><div class="hint" style="margin-top:4px">Paste a link from GitHub, or choose one of your repos.</div>'

picker = f'''<div class="pop" style="width:420px;padding:6px">
<div class="fld focus" style="margin:2px 2px 6px">{g("search")}<span>web</span></div>
<div class="menu" style="box-shadow:none;border:none;background:transparent;padding:0">
<div class="hd">YOURS AND YOUR ORGANIZATIONS’</div></div>
<div class="lrow hi">{lock()}<b style="font-weight:600">acme/website</b><span class="r">pushed 2 h ago</span></div>
<div class="lrow">{lock()}acme/web-docs<span class="r">yesterday</span></div>
<div class="lrow">geoffd/website-notes<span class="r">Sep 12</span></div>
<div class="menu" style="box-shadow:none;border:none;background:transparent;padding:0"><div class="hd" style="margin-top:4px">ON GITHUB</div></div>
<div class="lrow">vercel/next.js<span class="r">public · read only</span></div>
<div class="hint" style="padding:6px 8px 2px">From the GitHub CLI, signed in as geoffd. Any repo’s link works too.</div></div>'''

sheet1 = sheet_github(REPO_FIELD, FOUND_OK, BRANCH_A)
board("01-new-from-github", 2120, 1000, "1 · New project, From GitHub", "The CX study’s New project sheet with a third Start from: the repo field, what Duo found, the branch.", bd(2120, 1000,
    "1 · New project, From GitHub: a third “Start from” in the CX study’s sheet",
    "The sheet is the CX study’s option A (its board 3). <b>From GitHub</b> swaps Folder for <b>Repository</b>: paste a link (any form: <code>https://github.com/acme/website</code>, <code>…/tree/branch</code>, <code>git@github.com:…</code>, <code>acme/website</code> with <code>gh</code>) or Choose… from the GitHub CLI’s list. Once Duo can see the repo it says what it found in one quiet box, including your access, before anything is copied. [P]",
    f'''<div style="display:flex;gap:28px;align-items:flex-start">{frame(sheet_over(1240, 800, sheet1), 1240, 800, "The sheet, a repo chosen", "Name comes from the repo until typed over; In defaults to a topic named after the repo (made if missing). Create Project copies the repo, makes the branch, writes _PROJECT.md and opens the project.")}
<div style="display:flex;flex-direction:column;gap:14px;width:800px">{frame(f'<div style="padding:16px;background:{GROUND}">{picker}</div>', 460, None, "Choose… (with gh signed in)", "<code>gh repo list</code> for you and your organizations, newest push first; typing searches GitHub (<code>gh search repos</code>). A lock marks private repos.")}
{txt("""<h3>What the Found box can say [P]</h3><ul>
<li><b>acme/website</b> · private · you can push · main is protected</li>
<li><b>acme/website</b> · you can read it, not push · <i>Duo will push your work to your own copy (a fork) when you share it.</i></li>
<li><b>octo/docs</b> · public · Duo can’t tell what you can push until you share (no GitHub CLI)</li>
<li><b>acme/website</b> is already on this Mac in <span class="mono">website/launch-plan</span>. <i>This project gets its own copy.</i></li></ul>
<p class="note">Access is read with <code>gh repo view --json viewerPermission</code>; protection from <code>repos/:o/:r/branches/main</code> (<code>protected</code>, readable by anyone who can read the repo) plus its rulesets (<code>…/rules/branches/main</code>). The <code>…/protection</code> endpoint answers 404 to non-admins: that never means “unprotected”. Without <code>gh</code>, <code>git ls-remote</code> says only whether the repo is reachable.</p>""")}</div></div>'''))

# ---------- 02 · the branch ----------
existing = f'''<div class="pop" style="width:440px;padding:6px">
<div class="fld focus" style="margin:2px 2px 6px">{g("search")}<span class="t2">Filter branches</span></div>
<div class="lrow hi">{br(TEXT)}<b style="font-weight:600">priya/pricing-v2</b><span class="badge dk" style="margin-left:6px">PR #471</span><span class="r">Priya · 1 d</span></div>
<div class="lrow">{br()}geoffd/faq-cleanup<span class="badge" style="margin-left:6px">yours</span><span class="r">3 d</span></div>
<div class="lrow">{br()}launch/oct<span class="r">Sam · 5 d</span></div>
<div class="lrow">{br()}main<span class="badge" style="margin-left:6px">default · protected</span><span class="r">2 h</span></div>
<div class="hint" style="padding:6px 8px 2px">Branches on GitHub, newest first. A PR badge means a pull request is open from it.</div></div>'''
sheetA_exist = sheet_github(REPO_FIELD, FOUND_OK,
    fr("Branch", f'<div style="display:flex;flex-direction:column;gap:6px"><span class="rb"><i></i>A new branch for this work</span><span class="rb"><i class="on"></i>A branch that’s already there</span>'
       f'<div style="display:flex;gap:8px;align-items:center;padding-left:22px"><span class="popup" style="height:24px;flex:1">{br()}priya/pricing-v2<span class="badge dk">PR #471</span><span style="margin-left:auto"></span>{g("chevd")}</span></div>'
       f'<div class="hint" style="padding-left:22px">Someone else’s branch: your pushes join their pull request. Duo says so again before you push.</div></div>', top=True),
    name="Pricing v2 review")
comboB = f'''<div style="display:flex;flex-direction:column;gap:8px;width:440px">
<div class="fr" style="grid-template-columns:60px 1fr"><label>Branch</label><div class="fld focus mono" style="font-size:12px">pricing-copy▌</div></div>
<div class="pop" style="padding:6px;margin-left:72px">
<div class="lrow hi">{g("folder") and ""}<span style="font-weight:600">Make a new branch</span><span class="mono" style="font-size:12px">geoff/pricing-copy</span><span class="r">from main</span></div>
<div class="menu" style="box-shadow:none;border:none;background:transparent;padding:0"><div class="hd" style="margin-top:4px">ON GITHUB</div></div>
<div class="lrow">{br()}priya/pricing-v2<span class="badge dk" style="margin-left:6px">PR #471</span></div>
<div class="lrow">{br()}pricing-copy-old<span class="r">Sam · 40 d</span></div></div></div>'''
board("02-branch", 2000, 1000, "2 · The branch: new, or one that’s there", "A: two choices in the sheet (recommended). B: one combined field, GitHub Desktop’s style.", bd(2000, 1000,
    "2 · The branch: a new branch for this work, or one that’s already there",
    "A new branch is the default, named <code>&lt;your GitHub login&gt;/&lt;project slug&gt;</code> (or <code>&lt;slug&gt;</code> without <code>gh</code>), made from the repo’s default branch. It exists only on this Mac until the first push, so making a project never changes GitHub. Picking an existing branch is for joining someone’s work: reviewing a colleague’s PR or picking up your own branch on another Mac. [P]",
    f'''<div style="display:flex;gap:28px;align-items:flex-start">
<div style="display:flex;flex-direction:column;gap:14px">{frame(sheet_over(1240, 780, sheetA_exist), 1240, 780, "A · two choices in the sheet, an existing branch picked <span class=rec>recommended</span>", "The popup lists the branches on GitHub (<code>git ls-remote --heads</code>; with <code>gh</code>, each open PR’s number and author). The default branch is listed last and marked: working on it directly is allowed only when it isn’t protected and you can push.")}</div>
<div style="display:flex;flex-direction:column;gap:18px;width:660px">{frame(f'<div style="padding:16px;background:{GROUND}">{existing}</div>', 480, None, "A · the existing-branch popup")}
{frame(f'<div style="padding:16px;background:{GROUND}">{comboB}</div>', 480, None, "B · one field: type a new name, or pick", "One field fewer, but “new or existing” is a choice people should see; a typo makes a new branch silently. Not recommended.")}
{txt("""<h3>Rules [P]</h3><ul><li>A new branch’s name is checked as typed (<code>git check-ref-format</code>), and must not start with “-”. Taken on GitHub: “That name is taken on GitHub. Pick it under ‘A branch that’s already there’, or change the name.”</li>
<li>No branch picker after the project is made: one project, one branch. Another branch of the same repo is another project (board 3).</li></ul>""")}</div></div>'''))

# ---------- 03 · where it lands, cloning ----------
progress = f'''<div class="sheet" style="width:640px"><h2>Getting acme/website</h2>
<div style="height:6px;border-radius:3px;background:{SELECTED};overflow:hidden"><div style="width:42%;height:6px;background:{TEXT}"></div></div>
<div class="hint">Copying from GitHub: 51 of 120 MB. Then the branch geoff/pricing-copy and _PROJECT.md.</div>
<div class="btns"><span class="b">Cancel</span></div></div>'''
notice_done = nt('Copied <b style="font-weight:600">acme/website</b> into <span class="mono">website/pricing-copy</span>, on a new branch, <span class="mono">geoff/pricing-copy</span>. Nothing changes on GitHub until you push. <span class="mono">_PROJECT.md</span> is listed in <span class="mono">.git/info/exclude</span>, so it stays out of git.', ["Show in Finder"], 600)
landing = f'''<table class="cmp"><thead><tr><th></th><th>Clone per project <span class="rec">recommended</span></th><th>One clone, a worktree per project</th><th>A shared hidden clone + worktrees</th></tr></thead><tbody>
<tr><th>On disk</th><td><span class="mono">Home/website/pricing-copy/</span> is a whole repo; a second project from it is a second copy.</td><td>The first project is the clone; later ones are <code>git worktree add</code> folders beside it.</td><td><span class="mono">Home/.duo/repos/acme-website.git</span> (bare); every project is a worktree.</td></tr>
<tr><th>For</th><td>Every project stands alone: move, delete or archive it and nothing else breaks. What every other tool expects.</td><td>Fast and small; branches visible to each other.</td><td>No project is “the main one”.</td></tr>
<tr><th>Against</th><td>Disk and time for big repos (a shallow first fetch is an option, ENH-38).</td><td>Delete or move the first project and the others break (legacy’s ENH-232).</td><td>A hidden folder people can’t see owns their work; a moved folder needs <code>git worktree repair</code>.</td></tr>
<tr><th>Effort</th><td>S</td><td>M</td><td>M–L</td></tr></tbody></table>'''
board("03-landing", 2000, 1000, "3 · Where it lands, and getting it", "A clone per project inside Home; progress in the sheet; the notice when done.", bd(2000, 1000,
    "3 · Where it lands, and getting it",
    "The copy is a normal folder in Home, in the topic chosen under In, named after the project. Duo adds <code>_PROJECT.md</code> (the CX study’s name for a new project’s note, DL-147). A checkbox in the sheet, on by default, lists it and <code>.duo/</code> in the repo’s own <code>.git/info/exclude</code>, which stays on this Mac: Duo’s files never reach a commit or PR, and the repo’s <code>.gitignore</code> is untouched. Asked in the sheet and named in the notice, never silent (DL-50). Unticked, <code>_PROJECT.md</code> is an ordinary new file the user may commit. [P]",
    f'''<div style="display:flex;gap:28px;align-items:flex-start">
<div style="display:flex;flex-direction:column;gap:18px">{frame(sheet_over(1080, 300, progress), 1080, 300, "Getting it: progress in the same sheet", "git’s own progress (<code>--progress</code>) as a bar and sizes. Cancel stops it and removes the half-made folder.")}
{frame(f'<div style="padding:18px;background:{GROUND}">{notice_done}</div>', 1080, None, "Done: the project opens, with the notice (the CX study’s notice pattern)", "The first session is told the repo, the branch and your access in its brief (board 11).")}</div>
{txt(f"<h3>Where it lands: three ways</h3>{landing}<p class=note>Claude Code’s own worktrees (<code>claude --worktree</code>, <code>.claude/worktrees/</code>) are untouched: they live inside a project and Duo shows their sessions as today.</p>", w=820)}</div>'''))

# ---------- 04 · repo status options ----------
popC = f'''<div class="pop" style="width:330px;position:absolute;left:300px;top:44px;z-index:3">
<div style="display:flex;align-items:center;gap:6px">{br(TEXT)}<b style="font-weight:600">{BRANCH}</b></div>
<div class="t2">acme/website · from main · you can push</div>
<div>3 files changed · {arrow(True)}2 to push · main is 4 ahead</div>
<div style="display:flex;gap:6px;margin-top:4px"><span class="b sm def">Push…</span><span class="b sm">Get Latest</span><span class="b sm">Open on GitHub</span></div></div>'''
wA = pwindow(1180, 640, left_pane("A") + console() + project_tab())
wB = pwindow(1180, 640, left_pane("B") + console() + project_tab())
wC = f'<div style="position:relative">{pwindow(1180, 640, left_pane("none") + console() + project_tab(), ptoolbar(chip=True))}{popC}</div>'
board("04-status", 2600, 1640, "4 · The repo’s state on a project: A, B, C", "Where the branch, changes and push state show.", bd(2600, 1640,
    "4 · The repo’s state on a project: where it shows",
    "Only for a project whose folder is in a git repo with a GitHub remote; nothing shows otherwise. The words are the same in all three; only the place differs. The file tree marks changed and new files in every option. [P]",
    f'''<div style="display:flex;gap:40px;flex-wrap:wrap">
{frame(wA, 1180, 640, "A · a line under the project’s status line <span class=rec>recommended</span>", "Where the project already says how it’s going. One button, the next useful action (Push…, Get Latest, Resolve…), or none. Click the line for the details popover (as C’s).")}
{frame(wB, 1180, 640, "B · in the Files block", "Next to the files it describes, but at the bottom of a pane that is often short, and gone when Files is folded.")}
{frame(wC, 1180, 640, "C · a chip in the toolbar, details in a popover", "Always visible, even at All projects’ altitude for the open project. Crowds the toolbar (the needs-you chip and search), and the toolbar so far shows place, not state.")}
{txt("""<h3>Why A [P]</h3><ul><li>The project header is where the project says how it’s going (health, next); “3 files changed, 2 to push” is part of that.</li><li>It stays put while sessions scroll, at every window width (300 left pane).</li><li>The file marks (“changed”, “new”) are the existing “edited by Claude” label’s place, in <code>text2</code>.</li></ul>
<h3>How it stays current</h3><ul><li>Local state (branch, changed, to push) from <code>git status --porcelain=v2 --branch</code> on file events, as the tree refreshes.</li><li>GitHub’s side (new commits, PR) from a quiet <code>git fetch</code> every 5 minutes while the project is open, and on Get Latest. Fetch never prompts (<code>GIT_TERMINAL_PROMPT=0</code>); if it can’t, the line says “can’t reach GitHub” and when it last could.</li><li>The PR number from <code>gh pr view --json number,state</code>, when <code>gh</code> is signed in.</li></ul>""", w=1180)}</div>'''))

# ---------- 05 · every state ----------
states = [
    ("clean", "Up to date", "Nothing changed here, nothing new on GitHub. No button."),
    ("changed", "Files changed", "Saved files that aren’t in a commit yet. Push… commits them first (board 6)."),
    ("ahead", "Commits to push", "Committed here (often by Claude), not on GitHub yet."),
    ("new", "A new branch", "Made with the project; GitHub hasn’t seen it."),
    ("pr", "A pull request is open", "The PR’s number links to GitHub. Pushes update it."),
    ("pr-ahead", "PR open, more to push", "Push sends straight away: the PR exists, there’s nothing to ask."),
    ("behind", "New commits on GitHub", "Someone pushed to this branch. Get Latest brings them here (board 9)."),
    ("conflict", "A conflict", "Get Latest stopped part way. In <code>text</code> semibold, not <code>needsYou</code> (that stays for sessions)."),
    ("readonly", "Read only: your fork", "You can’t push to acme/website; pushes go to your fork (board 7)."),
    ("protected", "On a protected main", "Commits on main that GitHub won’t take. Move to a Branch… (board 10)."),
    ("signedout", "Signed out", "A push or fetch needed a sign-in and had none. Sign In… (board 10)."),
    ("offline", "Can’t reach GitHub", "Quiet: <code>text2</code>, no button, the last time it could."),
]
cells = "".join(f'<div style="display:flex;flex-direction:column;gap:6px;width:400px"><div class="cap">{c}</div><div style="background:{PANE};border:1px solid {RULE};border-radius:6px;padding:8px 12px;width:300px">{repo_line(k)}</div><div class="note">{n}</div></div>' for k, c, n in states)
board("05-states", 1440, 940, "5 · Every state of the repo line", "Twelve states, their words and their one button.", bd(1440, 940,
    "5 · Every state of the repo line (option A, 300 wide)",
    "Two lines: the branch, then one fact and at most one button. When several facts hold, the line shows the most pressing (conflict › signed out › protected › behind › to push › changed › PR › clean) and the popover lists them all. Words are git’s own where people meet them on GitHub (branch, push, pull request, fork); “commit” stays out of the line. [P]",
    f'<div style="display:flex;flex-wrap:wrap;gap:22px 30px">{cells}</div>'))

# ---------- 06 · push / open PR ----------
def share_sheet(head, banner, files_rows, msg, pr_block, btn, w=660):
    return f'''<div class="sheet" style="width:{w}px"><h2>{head}</h2>
{banner}
{fr("Changes", f'<div class="found" style="gap:2px">{files_rows}</div>', top=True)}
{fr("Message", msg, top=True)}
{pr_block}
<div class="btns"><span class="b" style="margin-right:auto">Ask Claude to Write These</span><span class="b">Cancel</span><span class="b def">{btn}</span></div></div>'''


FILES = (f'<div><span class="cb"><i>{TICK}</i><span class="mono" style="font-size:12px">content/pricing.md</span></span><span class="t2" style="margin-left:auto">+18 −9</span></div>'
         f'<div><span class="cb"><i>{TICK}</i><span class="mono" style="font-size:12px">content/faq.md</span></span><span class="t2" style="margin-left:auto">+31 −22</span></div>'
         f'<div><span class="cb"><i>{TICK}</i><span class="mono" style="font-size:12px">content/plans.json</span></span><span class="t2" style="margin-left:auto">new</span></div>'
         f'<div class="hint" style="margin-top:2px">Plus 2 commits already made here. _PROJECT.md stays out.</div>')
MSG = f'<div class="fld">Pricing page: new headline, plan table and FAQ</div>'
PR = (fr("Pull request", f'<div style="display:flex;flex-direction:column;gap:6px"><span class="cb"><i>{TICK}</i>Open a pull request into <b style="font-weight:600">acme/website</b> <span class="popup" style="height:22px">main{g("chevd")}</span></span>'
      f'<div class="fld" style="height:auto;min-height:64px;align-items:flex-start;padding:5px 8px;white-space:normal;font-size:12px;line-height:17px">Rewrites the pricing page for the October launch: a shorter headline, the plan table moved to plans.json, and three FAQ answers about annual billing.</div>'
      f'<span class="cb"><i class="off"></i>As a draft</span></div>', top=True))
s6 = share_sheet("Push to GitHub", f'<div class="hint" style="font-size:13px;line-height:19px">To <b style="color:{TEXT}">acme/website</b>, branch <span class="mono">{BRANCH}</span> (new on GitHub).</div>', FILES, MSG, PR, "Push and Open PR")
done6 = nt('Pushed <span class="mono">geoff/pricing-copy</span> and opened <b style="font-weight:600">PR #482</b> into acme/website main. The session “Tighten the FAQ” is told.', ["Open PR"], 620)
board("06-push-pr", 2000, 1020, "6 · Push / Open PR, with write access", "One sheet: what goes, the message, the pull request.", bd(2000, 1020,
    "6 · Push… and Open PR, when you can push",
    "Push… on the repo line (or Project › Push to GitHub…, ⇧⌘P [P]) opens one sheet. Duo commits the ticked files with the message, pushes the branch, and opens the pull request: with <code>gh pr create</code>, or GitHub’s own page without <code>gh</code> (board 8). The message and description start from the project’s goal and the sessions’ titles; <b>Ask Claude to Write These</b> hands the project’s session a drafted instruction and Claude fills them in with <code>duo2 repo draft</code> (board 11). [P]",
    f'''<div style="display:flex;gap:28px;align-items:flex-start">
{frame(sheet_over(1240, 760, s6, "All projects › website › pricing-copy"), 1240, 760, "The sheet: three changed files, two commits, a new branch", "With a PR already open the sheet has no Pull request row and the button is Push; with nothing to commit, Changes lists the commits only.")}
<div style="display:flex;flex-direction:column;gap:18px;width:640px">{frame(f'<div style="padding:18px;background:{GROUND}">{done6}</div>', 640, None, "Done")}
{txt("""<h3>What Duo runs [P]</h3><ol><li><code>git add -- &lt;ticked files&gt;</code>, <code>git commit -m …</code> (skipped when nothing is ticked).</li><li><code>git push -u origin geoff/pricing-copy</code>, never <code>--force</code>.</li><li><code>gh pr create --repo acme/website --base main --head geoff/pricing-copy --title … --body …</code> (non-interactive, <code>GH_PROMPT_DISABLED=1</code>), or the compare page (board 8).</li></ol>
<p class="note">The commit is made under the user’s own git name and email; with none set, the sheet asks for them once (Duo writes <code>user.name</code>/<code>user.email</code> to the repo’s config only if told to, ENH-39). Nothing is ever pushed without this sheet, from the UI or <code>duo2</code> (which needs <code>--yes</code>, as legacy’s did).</p>""")}</div></div>'''))

# ---------- 07 · no write: fork ----------
banner7 = (f'<div class="expl" style="background:{PANE};border:1px solid {RULE}"><div style="display:flex;gap:8px;align-items:flex-start">{lock()}<div><b>You can read acme/website but not push to it.</b> Duo will push your branch to your own copy of it on GitHub, <b>geoffd/website</b> (a fork), and open the pull request into acme/website from there. '
           f'The owners see the pull request; your fork is public if acme/website is.</div></div></div>')
PR7 = PR.replace("Open a pull request into", "Open a pull request into")
s7 = share_sheet("Push to GitHub", banner7, FILES, MSG, PR7, "Fork, Push and Open PR")
optA7 = f'<div class="hint" style="font-size:13px;line-height:19px">A · said in the sheet, before anything happens <span class="rec">recommended</span></div>'
ask7 = f'''<div class="ask2"><h3>Make your own copy of acme/website?</h3><p>You can’t push to acme/website. Duo can make a copy you own, geoffd/website, push there and open the pull request into acme/website.</p><p class="t2">Forking makes a repo on your GitHub account. You can delete it after the pull request is merged.</p>
<div class="btns"><span class="b">Cancel</span><span class="b def">Fork and Push</span></div></div>'''
board("07-fork", 2000, 1040, "7 · Push / Open PR without write access: the fork", "Said before it happens, in the same sheet.", bd(2000, 1040,
    "7 · No write access: push to your fork, open the PR into theirs",
    "Duo knows before the sheet opens (<code>viewerPermission</code> READ or TRIAGE), so it says it in the sheet rather than failing a push and asking after, as VS Code and <code>gh</code> do. Unlike legacy, Duo forks only when the access probe <i>says</i> read-only; when it can’t tell, it tries the push and asks (B) only if GitHub refuses with 403. Forking needs the GitHub CLI; without it, board 10’s explainer. [P]",
    f'''<div style="display:flex;gap:28px;align-items:flex-start">
{frame(sheet_over(1240, 800, s7, "All projects › website › pricing-copy"), 1240, 800, "A · the sheet says so first <span class=rec>recommended</span>", "One button, named for what it does: Fork, Push and Open PR. A fork that already exists is reused; its name is shown.")}
<div style="display:flex;flex-direction:column;gap:18px;width:640px">{frame(f'<div style="padding:18px;background:{GROUND}">{ask7}</div>', 500, None, "B · a question after a refused push", "Used when the access probe couldn’t answer (no gh, or GitHub didn’t say). Same words.")}
{txt("""<h3>What Duo runs [P]</h3><ol><li><code>gh repo fork acme/website --clone=false --remote --remote-name fork</code>. Duo names the remote <code>fork</code> so <code>origin</code> keeps meaning acme/website (by default <code>gh</code> renames origin to upstream, which would confuse Claude and every later status).</li>
<li><code>git push -u fork geoff/pricing-copy</code>.</li><li><code>gh pr create --repo acme/website --head geoffd:geoff/pricing-copy …</code>.</li></ol>
<p class="note">From then on the repo line reads “read only · n to push to your fork”, and Get Latest still pulls from acme/website. The project’s brief tells Claude: push to <code>fork</code>, never to <code>origin</code>.</p>""")}</div></div>'''))

# ---------- 08 · no gh ----------
banner8 = f'<div class="hint" style="font-size:13px;line-height:19px">To <b style="color:{TEXT}">octo/docs</b>, branch <span class="mono">pricing-copy</span>. Duo pushes with git and your Mac’s keychain; the pull request is written on GitHub’s page.</div>'
PR8 = fr("Pull request", f'<div style="display:flex;flex-direction:column;gap:6px"><span class="cb"><i>{TICK}</i>Then open GitHub’s page for a pull request into <b style="font-weight:600">main</b></span><div class="hint">Your browser opens with the title and description filled in; you press Create pull request there.</div></div>', top=True)
s8 = share_sheet("Push to GitHub", banner8, FILES, MSG, PR8, "Push and Open in Browser").replace('<span class="b" style="margin-right:auto">Ask Claude to Write These</span>', '<span class="b" style="margin-right:auto">Ask Claude to Write These</span>')
browser = f'''<div style="background:{PANE};border:1px solid {RULE};border-radius:8px;width:600px;overflow:hidden;white-space:normal">
<div style="height:30px;background:{GROUND};border-bottom:1px solid {RULE};display:flex;align-items:center;padding:0 10px" class="mono t2">github.com/octo/docs/compare/main...pricing-copy?expand=1&amp;title=…</div>
<div style="padding:14px 16px;display:flex;flex-direction:column;gap:8px"><div style="font-weight:600;font-size:15px">Open a pull request</div>
<div class="fld">Pricing page: new headline, plan table and FAQ</div><div class="fld" style="height:60px;align-items:flex-start;padding-top:4px;white-space:normal;font-size:12px">Rewrites the pricing page for the October launch…</div>
<span class="b def" style="align-self:flex-end">Create pull request</span><div class="hint">GitHub’s own page, drawn here as a stand-in.</div></div></div>'''
board("08-no-gh", 2000, 960, "8 · Push / Open PR without the GitHub CLI", "git pushes; GitHub’s compare page opens with the PR filled in.", bd(2000, 960,
    "8 · Without the GitHub CLI: push with git, open the PR on GitHub’s page",
    "Most of this works with git alone: git signs in through the Mac’s keychain (<code>osxkeychain</code>, set by Apple’s git) or whatever helper the user has. The pull request opens as GitHub’s compare page, <code>https://github.com/&lt;o&gt;/&lt;r&gt;/compare/&lt;base&gt;...&lt;branch&gt;?expand=1&amp;title=…&amp;body=…</code>, which needs no CLI and no token. What needs <code>gh</code>: the repo picker, knowing your access ahead, the fork, PR numbers on the line. [P]",
    f'''<div style="display:flex;gap:28px;align-items:flex-start">
{frame(sheet_over(1240, 700, s8, "All projects › docs › pricing-copy"), 1240, 700, "The sheet without gh")}
<div style="display:flex;flex-direction:column;gap:18px;width:640px">{frame(f'<div style="padding:18px;background:{GROUND}">{browser}</div>', 640, None, "Then, in the browser")}
{txt("""<h3>Signing in without gh [P]</h3><p>When git has no credential for github.com, Duo never lets git ask in a hidden terminal (<code>GIT_TERMINAL_PROMPT=0</code>); the push fails at once and board 10’s <b>Sign in to GitHub</b> explains, offering the GitHub CLI’s browser sign-in. Duo doesn’t offer to paste a token.</p>""")}</div></div>'''))

# ---------- 09 · get latest, conflict ----------
ask9 = f'''<div class="ask2" style="width:520px"><h3>Your changes and GitHub’s both changed content/faq.md</h3><p>Duo stopped bringing in the 4 new commits on main. Nothing is lost: your changes are as they were.</p>
<p>Claude can combine the two versions and tell you what it chose, or you can put things back as they were before Get Latest.</p>
<div class="btns"><span class="b" style="margin-right:auto">Show the File</span><span class="b">Put Back</span><span class="b def">Ask Claude to Combine</span></div></div>'''
menu9 = f'''<div class="menu" style="width:300px"><div>Push to GitHub…<span style="margin-left:auto" class="t2">⇧⌘P</span></div><div class="hi">Get Latest</div><div>Bring In Changes from main</div><div class="sep"></div><div>Open on GitHub</div><div>Open Pull Request #482</div><div class="sep"></div><div>Copy Branch Name</div></div>'''
board("09-get-latest", 2000, 900, "9 · Get Latest, and a conflict", "Bringing GitHub’s changes in; when two edits meet.", bd(2000, 900,
    "9 · Get Latest, and when two changes meet",
    "<b>Get Latest</b> brings in new commits on this project’s own branch (someone else pushed, or you did from another Mac). <b>Bring In Changes from main</b> merges the base branch in, as GitHub’s “Update branch” does. Both merge (never rebase: a merge can be undone in one step and needs no force push), carry uncommitted files along (<code>--autostash</code>), and never discard anything; legacy’s “Discard my changes and pull” is gone. [P]",
    f'''<div style="display:flex;gap:28px;align-items:flex-start">
{frame(f'<div style="padding:18px;background:{GROUND}">{menu9}</div>', 340, None, "The repo line’s menu (right-click, or the popover)")}
{frame(ask_over(1000, 380, ask9), 1000, 380, "A conflict: Duo’s question", "Put Back runs <code>git merge --abort</code>. Ask Claude to Combine sends the project’s session the drafted instruction (board 11); the line reads “1 file in conflict · Resolve…” until it’s done.")}
{txt("""<h3>What Duo runs [P]</h3><ul><li>Get Latest: <code>git fetch</code>, then <code>git merge --ff-only --autostash @{u}</code>, else <code>git merge --no-edit --autostash @{u}</code>.</li><li>Bring In Changes from main: <code>git merge --no-edit --autostash origin/main</code>.</li><li>Every probe fails closed: if Duo can’t read the state it changes nothing (legacy’s lesson).</li></ul>""", w=480)}</div>'''))

# ---------- 10 · failures ----------
def fail(title, body, btns, why):
    b = "".join(f'<span class="b{" def" if i == len(btns) - 1 else ""}">{x}</span>' for i, x in enumerate(btns))
    return (f'<div style="display:flex;flex-direction:column;gap:6px;width:460px"><div class="ask2" style="width:460px;box-shadow:none"><h3>{title}</h3><p>{body}</p><div class="btns">{b}</div></div>'
            f'<div class="note">{why}</div></div>')


fails = [
    fail("Duo needs the GitHub CLI for this", "Listing your repos and making a fork use GitHub’s own command-line tool, <span class=mono>gh</span>. It isn’t on this Mac. You can still paste a repo’s link: Duo copies and pushes with git.", ["Paste a Link", "Install in a Shell…"],
         "<b>No gh</b> (only when a step needs it). Install in a Shell opens a Duo shell tab with <code>brew install gh</code> typed, not run; without Homebrew, the GitHub CLI’s download page."),
    fail("Sign in to GitHub", "Duo never sees your password or keeps a token. The GitHub CLI signs you in through your browser and keeps the sign-in in your Mac’s keychain, where git uses it too.", ["Cancel", "Sign In in a Shell…"],
         "<b>Signed out</b> (gh signed out, or git had no credential). Opens a shell tab running <code>gh auth login --web --git-protocol https</code>, then <code>gh auth setup-git</code>; Duo retries when it ends."),
    fail("Duo can’t see acme/website", "It may be private, the link may be wrong, or your GitHub account (geoffd) hasn’t been given access. Ask the repo’s owner to add you, or sign in with another account.", ["Switch Account…", "Open on GitHub"],
         "<b>No access or not found</b>: GitHub answers the same for both, on purpose. Signed out, the title is “Sign in to see acme/website” and the button is Sign In."),
    fail("acme needs you to authorize single sign-on", "Your organization requires single sign-on for the GitHub CLI. Authorize it on GitHub once, then try again.", ["Cancel", "Open GitHub"],
         "<b>SAML SSO</b>: GitHub’s “Resource protected by organization SAML enforcement”. Common at companies; legacy’s research flagged it."),
    fail("main is protected on acme/website", "Changes to main go in through a pull request. Duo can move your 2 commits to a new branch, geoff/pricing-copy, push that and open the pull request. main here goes back to match GitHub.", ["Cancel", "Move to a Branch and Push"],
         "<b>Protected branch</b> (<code>GH006</code>, or a rule found ahead). Rare: projects from GitHub start on a branch. <code>git switch -c</code>, then main reset to <code>origin/main</code> only after the new branch holds every commit."),
    fail("GitHub has newer work on geoff/pricing-copy", "Someone pushed to this branch (or you did from another Mac). Get it first, then push.", ["Cancel", "Get Latest and Push"],
         "<b>Rejected, not fast-forward</b> (“fetch first”). Never a force push."),
    fail("You can’t push to acme/website", "GitHub says your account, geoffd, can read it but not push to it. If you should be able to, check with the repo’s owner. Or Duo can push to your own copy (a fork) and open the pull request from there.", ["Cancel", "Fork and Push"],
         "<b>403 on push</b> when access wasn’t known ahead (board 7 B). Names the account git used: a stale keychain account is a common cause. Without gh: “…Install the GitHub CLI to make a fork, or ask the owner for write access.”"),
    fail("Duo couldn’t reach GitHub", "Check you’re online and try again. Nothing was changed.", ["OK", "Try Again"],
         "<b>Offline or timed out</b> (every network step has a time limit). For the background fetch, never a question: the line says “can’t reach GitHub”."),
    fail("GitHub refused files that look like secrets", "GitHub’s secret scanning found something like a password or key in content/plans.json and refused the push. Nothing was pushed. Remove it (Claude can help), then push again.", ["Show Details", "Ask Claude to Remove It"],
         "<b>Push protection</b> (<code>GH009</code>). Files Claude wrote can trip it. Never offer to bypass."),
    fail("Tell git who you are", "Commits carry a name and email, and this Mac has none set for git. They show on GitHub next to your changes.", ["Cancel", "Save for This Repo"],
         "<b>No git identity</b>. Name and email fields (prefilled from GitHub when gh is signed in). ENH-39."),
]
board("10-failures", 1600, 1360, "10 · When it fails: the words", "Every failure, in Duo’s question look; what triggers it and what each button does.", bd(1600, 1360,
    "10 · When it fails: one question each, in plain words, never git’s raw output",
    "In Duo’s own question look (DuoQuestion, never a system alert). Each names what happened, what was and wasn’t changed, and one way forward. git’s and gh’s own words are kept behind a Details disclosure for whoever helps, not shown first (legacy showed raw stderr). Duo classifies by exit code and known messages; anything unknown says “GitHub refused the push” with the details. [P]",
    f'<div style="display:flex;flex-wrap:wrap;gap:24px 30px">{"".join(fails)}</div>'))

# ---------- 11 · Duo and Claude ----------
rows11 = [
    ("Copy a repo, make the branch", "Duo", "Deterministic; needs the sheet’s answers; no turn spent."),
    ("Know your access and the rules", "Duo", "Probed once, then told to Claude in the brief, so Claude never guesses."),
    ("The repo line, fetch", "Duo", "Always on; no Claude involved."),
    ("Commit message, PR title and description", "Claude, if asked", "Words from the work. Ask Claude to Write These sends the drafted instruction; Claude replies with <code>duo2 repo draft</code>."),
    ("Commit, push, fork, open the PR", "Duo", "Publishes under your name: only from the sheet you confirmed."),
    ("A conflict", "Claude, if asked", "Judgement. Duo drafts the instruction; Claude must not push."),
    ("Anything else git", "Claude", "As today: ask in the session. Duo’s line shows the result."),
]
tbl11 = "<table class=cmp><thead><tr><th>Step</th><th>Who</th><th>Why</th></tr></thead><tbody>" + "".join(f"<tr><th style='color:{TEXT}'>{a}</th><td>{b}</td><td>{c}</td></tr>" for a, b, c in rows11) + "</tbody></table>"
brief = '''<span class="k"># Told to Claude when a session starts here (appended to the brief)</span>
This project is a copy of acme/website on branch geoff/pricing-copy, made from main.
You can push to acme/website. main is protected: never commit to it.
_PROJECT.md and .duo/ are Duo's and are excluded from git: don't add them.
To share work, the user presses Push in Duo; don't push or open PRs unless asked.'''
draft = '''<span class="k"># Ask Claude to Write These (shown before sending, as New Session in Task's drafted prompt)</span>
Write a commit message and a pull request title and description for the changes in this
project (git diff origin/main, plus the 3 uncommitted files). Keep the title under 70
characters; the description says what changed and why, for a reviewer who hasn't seen
this work. Don't commit or push. Put them in Duo's Push sheet with:
  duo2 repo draft --message "…" --title "…" --body "…"'''
conflict = '''<span class="k"># Ask Claude to Combine</span>
Bringing main into geoff/pricing-copy stopped with a conflict in content/faq.md.
Combine both versions keeping what each side meant, then `git add` the file and
`git commit --no-edit`. Don't push. Then tell me in two lines what you kept from each side.'''
board("11-duo-and-claude", 1600, 1000, "11 · Duo and Claude: who does what", "The split, what Claude is told, and the instructions Duo drafts.", bd(1600, 1000,
    "11 · Duo does the mechanics; Claude does the words",
    "Claude Code can already do all of this from the terminal, and still can. Duo’s part is to make the safe path one click, the state visible, and the failures plain. Where Claude helps, Duo hands it a ready-made instruction, shown before it’s sent, in the project’s open session (or a new one). [P]",
    f'''<div style="display:flex;gap:14px;align-items:flex-start">{txt(tbl11, w=760)}
<div style="display:flex;flex-direction:column;gap:12px;flex:1">{f'<div class="pre">{brief}</div>'}{f'<div class="pre">{draft}</div>'}{f'<div class="pre">{conflict}</div>'}</div></div>'''))

# ---------- 12 · duo2 ----------
verbs = '''<span class="k"># new project (extends the CX study's `duo2 project new`)</span>
duo2 project new --from-github <link|owner/repo> [--new-branch <name> [--from <base>] | --branch <existing>]
                 [--name <n>] [--goal <g>] [--in <topic>] [--json]
<span class="k"># the repo line</span>
duo2 repo status [<project>] [--json]     branch, base, ahead, behind, changed, pr, access, protected, reachable
duo2 repo check  [<project>|<owner/repo>] gh present, signed in as, access, protection (read only, no network writes)
<span class="k"># sync</span>
duo2 repo latest [<project>]              Get Latest
duo2 repo update [<project>] [--from main] Bring In Changes from main
<span class="k"># share (each needs --yes outside the sheet: it publishes under your name)</span>
duo2 repo push   [<project>] [--message <m>] [--files <f>…] [--fork] --yes
duo2 repo pr     [<project>] [--title <t>] [--body <b>] [--base <b>] [--draft] [--browser] --yes
duo2 repo draft  --message <m> --title <t> --body <b>   fills the open Push sheet (Claude's reply)
duo2 repo move-to-branch <name> [<project>] --yes      board 10, protected main
<span class="k"># help</span>
duo2 repo signin                          opens a shell tab with gh auth login
duo2 repo open   [<project>] [--pr]       the repo or its PR on GitHub'''
board("12-duo2", 1440, 760, "12 · duo2 repo: the verbs", "Every button on these boards has a verb (DL-71).", bd(1440, 760,
    "12 · <code>duo2 repo</code>: every button has a verb (DL-71)",
    "Claude and scripts drive the same steps with the same checks and the same words (stdout is the notice’s text; failures exit non-zero with the question’s title and body). Anything that publishes needs <code>--yes</code>. [P]",
    f'<div class="pre" style="font-size:12px;line-height:19px">{verbs}</div>'))

# ---------- 13 · recommendation ----------
rec = [
    ("R1", "The repo line (A) and file marks, read only: local state + a quiet fetch; the popover", "4, 5", "M"),
    ("R2", "From GitHub in New project: paste a link; the gh picker when signed in; the Found box", "1", "M"),
    ("R3", "The branch: new (default) or existing, A", "2", "S"),
    ("R4", "A clone per project in Home; _PROJECT.md and .duo/ in .git/info/exclude; progress and notice", "3", "S"),
    ("R5", "Push… and Open PR: one sheet; gh pr create, or GitHub’s compare page without gh", "6, 8", "M"),
    ("R6", "No write access: the fork, said in the sheet (needs gh)", "7", "M"),
    ("R7", "Get Latest and Bring In Changes from main; the conflict question", "9", "S–M"),
    ("R8", "The failures, classified, in Duo’s question look, with Details", "10", "M"),
    ("R9", "What Claude is told; the drafted instructions; duo2 repo draft", "11", "S"),
    ("R10", "duo2 repo and project new --from-github", "12", "S (with each step)"),
]
trs = "".join(f"<tr><th style='color:{TEXT};width:60px'>{a}</th><td>{b}</td><td style='width:80px'>{c}</td><td style='width:120px'>{d}</td></tr>" for a, b, c, d in rec)
board("13-recommendation", 1440, 900, "13 · Recommendation and the v1 slice", "What to build first, with effort.", bd(1440, 900,
    "13 · Recommendation and a first slice",
    "Effort: S = a day or less, M = a few days, L = a week or more. Boards are on this canvas. [P]",
    f'''{txt(f"<table class=cmp><thead><tr><th>#</th><th>Recommendation</th><th>Boards</th><th>Effort</th></tr></thead><tbody>{trs}</tbody></table>")}
<div style="display:flex;gap:14px">{txt("""<h3>The first slice [P]</h3><p><b>R1, R2, R3, R4, R5, R8, R9, R10</b>: see where a repo stands; bring one in on a new branch; push and open a PR with or without <code>gh</code>; plain failures. About two weeks. Then <b>R6</b> (fork) and <b>R7</b> (Get Latest).</p><p class=note>Why R6 after: people at a company usually have write access and meet protected branches, which a new branch avoids. The fork serves open source and other teams’ repos.</p>""", flex=True)}
{txt("""<h3>Later (ENH)</h3><ul><li><b>ENH-37</b>: GitHub Enterprise and other hosts (GitLab, Bitbucket): the same line and push; the PR page differs.</li><li><b>ENH-38</b>: the PR on the project: checks, reviews, comments; a shallow first copy for big repos.</li><li><b>ENH-39</b>: git identity from GitHub; first-run setup for git and gh.</li><li>Worktrees per project; Claude Code’s own worktrees shown as branches.</li></ul>""", flex=True)}
{txt("""<h3>Questions for Geoff</h3><ol><li>Where the repo state shows: A, B or C (Q-122).</li><li>Who pushes: Duo’s sheet, Claude writing the words; or Claude does it all (Q-126).</li><li>Fork in the first slice, or after (Q-123).</li><li>A clone per project, or worktrees (Q-124).</li><li>_PROJECT.md in a repo: out of git by a checkbox, on (Q-125).</li></ol>""", flex=True)}</div>'''))

with open(os.path.join(OUT, "manifest.json"), "w") as f:
    json.dump(BOARDS, f, indent=1)
print(f"{len(BOARDS)} boards in {OUT}")
