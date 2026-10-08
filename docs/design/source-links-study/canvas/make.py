#!/usr/bin/env python3
"""Draws the source-links study boards (every mark [P]) as static HTML in the Duo design system.

    python3 docs/design/source-links-study/canvas/make.py
    bash docs/design/source-links-study/canvas/render.sh

Reuses the GitHub study's helpers (everything above its "# =====" line), which reuse the
home-evolution study's tokens, CSS and glyphs, so the studies draw the same app. The deck viewer's
bar is copied from the approved pptx board (pptx-handoff/screens/pptx-viewer.html, DL-125).
Research: docs/research/source-links.md. Names, links and data are illustrative.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(HERE, "../../github-study/canvas/make.py")).read()
_src = _src[:_src.index("# ======")].replace('HERE = os.path.dirname(os.path.abspath(__file__))', "")
_cwd_here = HERE
exec(_src.replace('os.path.join(HERE, "../../home-evolution-handoff/canvas/make.py")',
                  f'os.path.join({_cwd_here!r}, "../../home-evolution-handoff/canvas/make.py")'))
HERE = _cwd_here
OUT = os.path.join(HERE, "boards")
STUDY = "source-links-study"
BOARDS.clear()


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
STUDY BOARD [P], not approved. Drawn for the source-links study (2026-10-08) with the Duo design system.
{e(note)}
It is a picture written in HTML: match what it draws, do not port its markup. Names, links and data are illustrative.
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


# ---- this study ----
CSS += f"""
.vbar{{display:flex;align-items:center;gap:6px;height:44px;flex:none;padding:0 20px;border-bottom:1px solid {RULE};white-space:nowrap}}
.vb{{font:inherit;font-size:12px;line-height:16px;padding:4px 10px;border:1px solid {EDGE};border-radius:6px;background:{PANE};color:{TEXT};display:inline-flex;align-items:center;gap:5px}}
.srcl{{display:flex;align-items:center;gap:6px;height:28px;flex:none;padding:0 20px;border-bottom:1px solid {RULE};background:{GROUND};font-size:12px;line-height:16px;color:{TEXT2};white-space:nowrap}}
.srcl a,.lnk{{color:{TEXT};text-decoration:underline;text-decoration-color:{EDGE};text-underline-offset:2px}}
.slide{{position:relative;background:{PANE};border:1px solid {RULE};flex:none}}
.slide .h{{position:absolute;left:8%;top:9%;font-weight:600}}
.chg{{outline:2px solid {TEXT};outline-offset:2px}}
.tag{{display:inline-flex;align-items:center;height:16px;padding:0 6px;border-radius:8px;font-size:10px;line-height:14px;font-weight:600;letter-spacing:.3px;border:1px solid {EDGE};color:{TEXT2};background:{PANE}}}
.tag.dk{{border-color:{TEXT};color:{TEXT}}}
.del{{text-decoration:line-through;color:{TEXT2}}}
.ins{{text-decoration:underline;text-decoration-thickness:2px;text-underline-offset:3px}}
.lane{{display:grid;grid-template-columns:150px repeat(7,minmax(0,1fr));gap:8px;align-items:stretch}}
.lane>div{{background:{PANE};border:1px solid {RULE};border-radius:6px;padding:8px 10px;font-size:12px;line-height:17px;white-space:normal}}
.lane>div.lh{{background:transparent;border:none;font:600 11px/16px -apple-system,system-ui,sans-serif;letter-spacing:.66px;text-transform:uppercase;color:{TEXT2};padding:8px 0}}
.lane>div.ch{{background:transparent;border:none;font-weight:600;padding:0 2px}}
.lane>div.no{{background:transparent;border:1px dashed {RULE};color:{TEXT2}}}
.fm{{font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:11px;line-height:17px;white-space:pre;color:{TEXT}}}
.obs{{background:#1E1E1E;color:#DADADA;border-radius:8px;overflow:hidden;display:flex;font-size:12px;line-height:18px}}
"""

DOC_ID = "1EAYk18WDjIG-zp_0vLm3CsfQh_i8eXc67Jo2O9C6Vuc"
EDIT = f"docs.google.com/presentation/d/{DOC_ID[:10]}…/edit"
DECK = "Q3 plan.pptx"


def link_g(color=None):
    c = color or TEXT2
    return (f'<svg width="12" height="12" viewBox="0 0 12 12" style="flex:none"><path d="M5 7 7 5M4.2 5.3 2.9 6.6a2 2 0 0 0 2.8 2.8l1.3-1.3M7.8 6.7l1.3-1.3a2 2 0 0 0-2.8-2.8L5 3.9" '
            f'fill="none" stroke="{c}" stroke-width="1.3" stroke-linecap="round"/></svg>')


def ext_g(color=None):
    return g("jump", color)


def refresh_g(color=None):
    c = color or TEXT
    return (f'<svg width="11" height="11" viewBox="0 0 12 12" style="flex:none"><path d="M10 6a4 4 0 1 1-1.2-2.85M10 1.8v2.6H7.4" fill="none" stroke="{c}" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/></svg>')


def vbar(extra_right="", source_btn=False):
    sb = f'<span class="vb">{link_g(TEXT)}Google Slides{g("chevd")}</span>' if source_btn else ""
    return (f'<div class="vbar"><span class="vb" style="padding:4px 7px">‹</span><span class="vb" style="padding:4px 7px">›</span>'
            f'<span style="margin-left:4px">Slide 2 of 5</span><span style="flex:1"></span>{sb}{extra_right}<span class="vb">Select Shape</span><span class="vb">Open With ⌄</span></div>')


def src_line(state="snap", w=None):
    if state == "snap":
        body = (f'{link_g()}<span>Snapshot of <a class="lnk">Q3 plan</a> in Google Slides · 30 Sep</span><span style="flex:1"></span>'
                f'<span class="vb" style="padding:2px 8px;font-size:11px">{refresh_g()}Get Latest</span>')
    elif state == "waiting":
        body = (f'{link_g()}<span>Waiting for the download from your browser…</span><span style="flex:1"></span>'
                f'<span class="vb" style="padding:2px 8px;font-size:11px">Cancel</span>')
    elif state == "newer":
        body = (f'{link_g(TEXT)}<span style="color:{TEXT}"><b style="font-weight:600">A newer Q3 plan</b> arrived · today 15:24 · 2 slides changed</span><span style="flex:1"></span>'
                f'<span class="vb" style="padding:2px 8px;font-size:11px">Compare</span>')
    elif state == "offer":
        body = (f'{link_g()}<span>From <a class="lnk">Q3 plan</a> in Google Slides</span><span style="flex:1"></span>'
                f'<span class="vb" style="padding:2px 8px;font-size:11px">Add Source</span><span class="t2" style="text-decoration:underline">Other…</span>')
    elif state == "none":
        body = f'{link_g()}<span>No source</span><span style="flex:1"></span><span class="vb" style="padding:2px 8px;font-size:11px">Add Source…</span>'
    elif state == "newer-nosrc":
        body = (f'{link_g(TEXT)}<span style="color:{TEXT}"><b style="font-weight:600">A newer download</b> · Q3 plan (1).pptx · today 15:24</span><span style="flex:1"></span>'
                f'<span class="vb" style="padding:2px 8px;font-size:11px">Compare</span>')
    return f'<div class="srcl">{body}</div>'


def slide(w, title, body="", chg=False, extra=""):
    h = int(w * 9 / 16)
    return (f'<div class="slide{" chg" if chg else ""}" style="width:{w}px;height:{h}px">'
            f'<div class="h" style="font-size:{max(9, w // 22)}px;line-height:1.25">{title}</div>{body}{extra}</div>')


def bars(w, hs, color="#6E93C9"):
    h = int(w * 9 / 16)
    bw = max(4, w // 16)
    return (f'<div style="position:absolute;left:12%;bottom:12%;width:70%;height:{int(h * .55)}px;border-left:1px solid {EDGE};border-bottom:1px solid {EDGE};display:flex;align-items:flex-end;gap:{bw // 2 + 2}px;padding:0 6px">'
            + "".join(f'<div style="width:{bw}px;height:{x}%;background:{color}"></div>' for x in hs) + '</div>')


def bullets(w, lines):
    fs = max(7, w // 34)
    return (f'<div style="position:absolute;left:8%;top:30%;right:8%;font-size:{fs}px;line-height:1.5;white-space:normal">'
            + "".join(f'<div>• {l}</div>' for l in lines) + '</div>')


def deck_pane(w=460, h=800, line="snap", source_btn=False, notice="", picked=False):
    tabs = (f'<div style="display:flex;align-items:center;gap:18px;height:36px;flex:none;padding:0 20px;border-bottom:1px solid {RULE};white-space:nowrap">'
            f'<span class="t2">Project</span><span style="font-weight:600">{DECK}</span><span class="t2">+</span></div>')
    sw = w - 40
    sl = (f'<div style="flex:1;min-height:0;display:flex;flex-direction:column;gap:6px;padding:10px 20px 0;background:{GROUND};overflow:hidden;position:relative">'
          f'<span style="font-size:11px;line-height:16px;font-weight:600">2</span>'
          + slide(sw, "Revenue by quarter", bars(sw, [40, 55, 72, 64]))
          + f'<span style="font-size:11px;line-height:16px;color:{TEXT2};margin-top:10px">3</span>'
          + slide(sw, "What we ship in Q3", bullets(sw, ["Billing v2 to every plan", "Usage alerts", "SSO for teams"]))
          + (f'<div style="position:absolute;left:20px;right:20px;bottom:16px">{notice}</div>' if notice else "")
          + '</div>')
    ln = src_line(line) if line else ""
    return (f'<div style="width:{w}px;height:{h}px;flex:none;display:flex;flex-direction:column;background:{PANE};border:1px solid {RULE};overflow:hidden;font-size:13px;line-height:20px;white-space:nowrap">'
            f'{tabs}{vbar(source_btn=source_btn)}{ln}{sl}</div>')


def pnotice(msg, btns, w=None, close=True):
    st = f"width:{w}px" if w else ""
    x = f'<span class="t2" style="padding:0 4px">✕</span>' if close else ""
    return (f'<div class="notice" style="{st}"><span style="flex:1;font-size:12px;line-height:17px">{msg}</span>'
            + "".join(f'<span class="b" style="height:22px;font-size:12px">{b}</span>' for b in btns) + f'{x}</div>')


def popover(w=360):
    snaps = "".join(f'<div style="display:flex;gap:8px"><span style="width:96px">{d}</span><span class="t2">{t}</span></div>' for d, t in
                    [("30 Sep, 09:12", "this copy"), ("12 Sep, 16:40", "replaced · in git"), ("2 Sep, 11:05", "replaced · in the Trash")])
    return f'''<div class="pop" style="width:{w}px;gap:8px">
<div style="display:flex;align-items:center;gap:8px"><span style="font-weight:600;font-size:13px">Q3 plan</span><span class="badge">Google Slides</span></div>
<div class="mono t2" style="font-size:11px;line-height:16px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{EDIT}</div>
<div style="display:flex;gap:6px;flex-wrap:wrap"><span class="b sm def">{ext_g(TEXT)}&nbsp;Open in Google Slides</span><span class="b sm">Copy Link</span><span class="b sm">{refresh_g()}&nbsp;Get Latest</span></div>
<div style="border-top:1px solid {RULE};padding-top:8px;display:flex;flex-direction:column;gap:2px"><div class="sl" style="font-size:10px">Snapshots</div>{snaps}</div>
<div style="border-top:1px solid {RULE};padding-top:6px;display:flex;gap:14px" class="t2"><span style="text-decoration:underline">Change Source…</span><span style="text-decoration:underline">Remove Source</span><span style="margin-left:auto">Slide 2 in Slides {ext_g()}</span></div>
</div>'''


def files_block(sel=None, mark=True, show_sidecar=False, extra_rows=""):
    def ft(name, pad=0, m="", s=False):
        bg = f"background:{SELECTED};border-radius:4px;" if s else ""
        return f'<div class="ft" style="padding-left:{pad}px;{bg}">{name}{m}</div>'
    lm = f'<span style="margin-left:6px;display:inline-flex">{link_g()}</span>' if mark else ""
    rows = (ft("_PROJECT.md") + ft(f'{g("chevd")}inputs/')
            + ft(DECK, 18, lm, sel == DECK)
            + (ft(DECK + ".md", 18, '<span class="mark" style="font-family:inherit">source</span>') if show_sidecar else "")
            + ft("Launch brief.docx", 18, lm, sel == "brief")
            + (ft("Launch brief.docx.md", 18, '<span class="mark" style="font-family:inherit">source</span>') if show_sidecar else "")
            + ft("survey.csv", 18) + extra_rows + ft(f'{g("chev")}drafts/') + ft("plan.md"))
    return (f'<div style="border-top:2px solid {EDGE};padding:10px 16px 8px;display:flex;flex-direction:column;gap:2px"><div class="sl">Files</div>'
            f'<div class="mono t2" style="font-size:11px">~/claude-home/q3-planning</div><div style="margin-top:4px">{rows}</div></div>')


def lpane(w=300, files="", notice="", status="On track · Board review Oct 20"):
    head = f'<div style="padding:14px 16px 8px"><div style="font-weight:600;font-size:14px">q3-planning</div><div class="t2">{status}</div></div>'
    rows = [sec("Today"), srow("working", "Draft the board memo", "working", tint=True), srow("idle", "Summarise the survey", "2h")]
    btn = '<div style="display:flex;gap:8px;padding:10px 16px"><span class="btn">+ New session</span></div>'
    f = files or files_block()
    n = f'<div style="padding:0 12px 10px">{notice}</div>' if notice else ""
    return f'<div style="width:{w}px;flex:none;border-right:1px solid {RULE};display:flex;flex-direction:column;min-height:0;overflow:hidden;background:{PANE};position:relative">{head}{"".join(rows)}{btn}<div style="flex:1"></div>{n}{f}</div>'


def qtoolbar():
    return f'''<div class="tb">
<span class="tl"><i style="background:#FF5F57"></i><i style="background:#FEBC2E"></i><i style="background:#28C840"></i></span>
<span class="tgl">{g("sidebar")}</span>
<span style="text-decoration:underline;color:{TEXT2}">All projects</span>{g("chev")}<span style="font-weight:600">q3-planning</span>
<span class="srch">{g("search")}Search all projects<span style="margin-left:auto">⇧⌘A</span></span>
<span class="tgl" style="margin-left:4px">{g("right")}</span>
</div>'''


def qconsole(text=None, w=None):
    t = text or (f'I read inputs/Q3 plan.pptx (5 slides).<br><span style="color:{CTEXT2}">It’s a snapshot of the Google Slides deck “Q3 plan”, downloaded 30 Sep.</span>')
    st = f"width:{w}px;flex:none" if w else "flex:1;min-width:0"
    return (f'<div style="{st};background:{CONSOLE};display:flex;flex-direction:column;border-right:1px solid {RULE}">'
            f'<div class="mono" style="display:flex;gap:22px;height:36px;align-items:center;padding:0 20px;border-bottom:1px solid {CRULE};color:{CTEXT2}"><span style="color:{CTEXT};display:flex;gap:6px;align-items:center">{g("working", CTEXT)}Draft the board memo</span><span>+</span></div>'
            f'<div class="mono cl" style="padding:16px 20px;flex:1;white-space:normal">{t}</div>'
            f'<div style="margin:0 20px 16px;border:1px solid {CRULE};border-radius:6px;height:30px;color:{CTEXT2};padding:5px 10px" class="mono">&gt; ▌</div></div>')


def qwindow(w, h, body):
    return f'<div class="w" style="width:{w}px;height:{h}px;border:1px solid {RULE};border-radius:10px">{qtoolbar()}<div style="display:flex;flex:1;min-height:0">{body}</div></div>'


def menu(items, w=230):
    out = []
    for it in items:
        if it == "-":
            out.append('<div class="sep"></div>')
        elif it.startswith("#"):
            out.append(f'<div class="hd">{it[1:]}</div>')
        elif it.startswith("*"):
            out.append(f'<div class="hi">{it[1:]}</div>')
        elif it.startswith("~"):
            out.append(f'<div class="dim">{it[1:]}</div>')
        else:
            out.append(f'<div>{it}</div>')
    return f'<div class="menu" style="width:{w}px">{"".join(out)}</div>'


# ======================================================================
# 00 · the study
board("00-study", 1440, 900, "0 · Source links: the study", "The ask, what the research found, the principles.", bd(1440, 900,
    "0 · Where did this file come from? Source links for downloaded Google files (decided: DL-163)",
    "Geoff, 2026-10-08: at work it’s Google Docs and Slides, which neither Duo nor Claude can reach, so he downloads a .pptx or .docx. He wants Duo to know the canonical link, open it in the browser, replace a snapshot with a newer download, perhaps watch Downloads and offer a side-by-side compare. Every mark on these boards is a proposal [P]. The research is in docs/research/source-links.md.",
    f'''<div style="display:flex;gap:14px;align-items:flex-start">
<div class="txt" style="flex:1"><h3>What the research found</h3><ul>
<li><b>Google’s download carries nothing.</b> The .docx and .pptx have no properties at all: no title, no id, no link [V].</li>
<li><b>The browser records it.</b> Chrome writes the download’s address on the file (macOS’s “Where from”). It ends in the document’s id, so Duo can rebuild <span class="mono" style="font-size:12px">docs.google.com/presentation/d/&lt;id&gt;/edit</span> [V].</li>
<li><b>That record is fragile.</b> It survives Finder copies and moves, and Duo’s own; it is lost through git, zip and an app’s Save [V]. So Duo reads it once, when the file arrives.</li>
<li><b>Spotlight finds every download of the same document</b> by that id, wherever the browser put it, without Duo looking in Downloads [V]. Whether that asks macOS’s privacy question is untested (Q-155).</li>
<li><b>A deck knows its slides.</b> Google names shapes after each slide’s id, which is the id in Slides’ own link. Duo can open slide 4 in Google Slides and match slides between two downloads [V].</li>
<li><b>Two downloads of the same thing differ byte for byte</b> (timestamps, image order) [V], so “has it changed?” compares contents.</li>
<li><b>Writing the link into the file</b> works by the spec, and Word shows it, but it changes the file, and Google drops it on the way back [V for export].</li></ul></div>
<div class="txt" style="width:540px;flex:none"><h3>The boards</h3><ol start="0">
<li>This page. 1 · The journey, moment by moment.</li>
<li>2 · The thin bar: Add Source, the link, a newer download.</li>
<li>3 · Seeing the source in the viewer’s bar: A, a line; B, a button.</li>
<li>4 · The source popover; Add Source… by hand.</li>
<li>5 · In Files and the right-click menu.</li>
<li>6 · Newer downloads, with or without a source; Get Latest. 13 · How a download is matched.</li>
<li>7 · Compare a deck, side by side. 8 · Compare a document.</li>
<li>9 · Replace, Undo, and history.</li>
<li>10 · Where the link is kept: one _sources.md per folder.</li>
<li>11 · What Claude sees; <span class="mono" style="font-size:12px">duo2 file source</span>.</li>
<li>12 · The recommendation and a first slice.</li></ol>
<h3>Principles</h3><ul>
<li>Never change the downloaded file (DL-162’s view-only rule).</li><li>Newer downloads, compare and replace work for any file, with or without a source (Geoff).</li>
<li>Never look in Downloads on Duo’s own; never a system alert.</li>
<li>Store only the clean link, never the raw download address (it holds tokens).</li>
<li>Plain Markdown that Obsidian and OKF read (Geoff, 2026-10-07).</li></ul></div></div>'''))

# 01 · journey
cols = ["Arrives", "Link kept", "Seen", "Opened", "Newer exists", "Compared", "Replaced"]
lanes = [
    ("Geoff", ["Downloads the deck in Chrome; drags it into the project", "Opens it; clicks Add Source in the thin bar", "Sees the link in the bar in a later session", "Clicks the link", "Downloads it again (or clicks Get Latest)", "Looks at what changed", "Replaces; can Undo"]),
    ("Duo, on screen", ["The thin bar: From Q3 plan in Google Slides · Add Source", "A link mark on the file in Files", "The bar: Snapshot of Q3 plan · 30 Sep", "Opens the /edit link in the default browser", "The bar: A newer download · today 15:24 · Compare (source or not)", "Two columns of slides, changes marked; Changed only", "Notice: Replaced · old copy in the Trash · Undo"]),
    ("Duo, behind", ["Reads “Where from”; rebuilds the /edit link from the id, to offer", "Adds a line to the folder’s _sources.md (creates it if needed)", "Reads _sources.md", "—", "A live Spotlight query: downloads with the same name or Google id, newer than the copy", "Matches slides by Google’s slide ids; text by paragraphs", "Moves the new file to the old name; updates the line’s date"]),
    ("macOS, browser", ["Chrome writes “Where from” and quarantine", "—", "—", "The browser, already signed in to Google", "Chrome downloads to ~/Downloads; Spotlight indexes it", "Reading the download may ask for Downloads access, once (Q-155)", "The old copy goes to the Trash"]),
    ("Claude", ["—", "Can read _sources.md", "Told: “a snapshot of …, downloaded 30 Sep”", "Can’t open it; can say where it came from", "Can run duo2 file latest", "Can read both copies", "Told the file was replaced"]),
]
lane_html = '<div class="lane"><div class="lh"></div>' + "".join(f'<div class="ch">{i + 1} · {c}</div>' for i, c in enumerate(cols)) + "</div>"
for ln, cells in lanes:
    lane_html += f'<div class="lane"><div class="lh">{ln}</div>' + "".join(f'<div class="{"no" if c == "—" else ""}">{c}</div>' for c in cells) + "</div>"
board("01-journey", 1680, 900, "1 · The journey", "A service blueprint: what Geoff does, what Duo shows and does, what macOS and Claude do.", bd(1680, 900,
    "1 · The journey, moment by moment",
    "From the download to the replaced snapshot. Lanes are who acts; columns are the moments. The boards that follow draw each moment.",
    f'<div style="display:flex;flex-direction:column;gap:8px">{lane_html}</div>'
    f'<div class="note" style="max-width:1300px"><b>Other ways in:</b> a file Claude fetched, a file from git or a zip, a file from a colleague: no “Where from”, so the bar offers Add Source… with an empty field (board 4). Newer downloads are still found by name (board 13). <b>Other kinds:</b> the same note works for any file from any web page (a PDF, a CSV from a dashboard). Only Google files get Get Latest, compare and the slide links.</div>'))

# 02 · the thin bar
st_a = deck_pane(420, 330, line="offer")
st_b = deck_pane(420, 330, line="none")
st_c = deck_pane(420, 330, line="snap")
st_d = deck_pane(420, 330, line="newer-nosrc")
board("02-thin-bar", 2100, 820, "2 · The thin bar", "Under the viewer’s bar, on every .pptx and .docx: Add Source, the link, a newer download.", bd(2100, 820,
    "2 · The thin bar under the viewer’s bar (DL-163)",
    "Every .pptx and .docx shows it. Nothing is written until the user adds a source: then a line goes into the folder’s _sources.md (created if needed), and in a later session the bar carries the link.",
    f'''<div style="display:flex;gap:40px;align-items:flex-start">
{frame(st_a, cap="1 · The browser knows the link", note="From the download’s “Where from”, cleaned to its /edit form. <b>Add Source</b> writes the line in one click; <b>Other…</b> opens Add Source… (board 4) to type a different link.", w=420)}
{frame(st_b, cap="2 · No link known", note="A file from git, a zip, Claude or a colleague. Add Source… opens the field empty.", w=420)}
{frame(st_c, cap="3 · Source added", note="The title opens the link in the default browser; a click elsewhere on the line opens the popover (board 4). Get Latest only for Google links.", w=420)}
{frame(st_d, cap="4 · A newer download, no source needed", note="Found by name in what the browser downloaded (board 13). With a source, the line names it instead: “A newer Q3 plan arrived”. Compare opens board 7.", w=420)}
</div>'''))

# 03 · the bar
pane_a = deck_pane(460, 520, line="snap")
pane_b = (f'<div style="position:relative">{deck_pane(460, 520, line=None, source_btn=True)}'
          f'<div style="position:absolute;left:66px;top:122px">{popover(360)}</div></div>')
board("03-bar", 1300, 760, "3 · Seeing the source", "A: a line under the deck’s bar. B: a Google Slides button in the bar that opens the popover.", bd(1300, 760,
    "3 · Seeing the source, in the viewer (DL-125’s bar; the docx bar, DL-162, the same)",
    "The deck’s bar stays as approved. The source is either its own quiet line under the bar (A) or one more button in it (B). The link opens in the default browser.",
    f'''<div style="display:flex;gap:60px;align-items:flex-start">
{frame(pane_a, cap="A · A line under the bar" + '<span class="rec">recommended</span>', note="Always says what it is: <b>Snapshot of Q3 plan in Google Slides · 30 Sep</b>. The title opens the link in the default browser; ⌥-click copies it; a click elsewhere on the line opens the popover (board 4). Get Latest sits at its end. Without a source, no line at all.", w=460)}
{frame(pane_b, cap="B · A button in the bar, opening the popover", note="Takes no height, but the bar is already full at 460 px (Select Shape, Open With), and the date is hidden until clicked.", w=460)}
<div class="txt" style="width:240px"><h3>The words</h3><ul>
<li>“Snapshot of” says this is a copy that can go stale.</li>
<li>The document’s title, from the download’s name, not the file’s (which the user may rename).</li>
<li>The date is when it was downloaded, not modified.</li>
<li>“Google Slides”, “Google Docs”, “Google Sheets”; for any other link, its site’s name.</li></ul></div>
</div>'''))

# 04 · popover + set source
set_sheet = f'''<div class="sheet" style="width:520px">
<h2>Add a source for “Launch brief.docx”</h2>
<div class="hint" style="font-size:12px">Where this file came from. It’s kept in this folder’s <span class="mono">_sources.md</span>; the file itself isn’t changed.</div>
{fr("Link", '<div class="fld focus mono" style="font-size:12px">https://docs.google.com/document/d/1hK…Qe4/edit?tab=t.0</div>')}
{fr("", f'<div class="found" style="font-size:12px"><div>{link_g(TEXT)}<b style="font-weight:600">Google Docs</b><span class="t2">document 1hK…Qe4</span></div><div class="t2">Get Latest will download it as Word (.docx).</div></div>')}
<div class="btns"><span class="b">Cancel</span><span class="b def">Add Source</span></div></div>'''
set_win = f'<div class="w" style="width:640px;height:330px">{tb_quiet("All projects › q3-planning")}<div class="sheetwrap">{set_sheet}</div></div>'
board("04-popover", 1300, 740, "4 · The source popover; Add Source…", "Everything about the link in one place; adding one by hand.", bd(1300, 740,
    "4 · The source popover, and Add Source… for a file with none",
    "The popover opens from the bar’s line (A) or button (B), and from Files’ right-click menu. Add Source… takes any link; Google links are recognised and cleaned to their /edit form.",
    f'''<div style="display:flex;gap:60px;align-items:flex-start">
{frame(f'<div style="padding:16px;background:{GROUND}">{popover(380)}</div>', cap="The popover", note="<b>Open in Google Slides</b> is the default. <b>Slide 2 in Slides</b> opens the slide on screen (from Google’s slide id). <b>Snapshots</b> lists the dates this file was replaced, kept in its line. Change Source… and Remove Source edit only the file’s line in _sources.md.", w=412)}
{frame(set_win, cap="Add Source…", note="Pasting a link fills the found box. A link that isn’t Google’s is kept as it is (“example.com”); Get Latest is then hidden. An export or googleusercontent link is turned into its /edit form; tokens never kept.", w=640)}
</div>'''))

# 05 · files + menu
mn = menu(["Open", "Open With", "Reveal in Finder", "-", "#Source", f"*Open Q3 plan in Google Slides", "Get Latest", "Copy Source Link", "Change Source…", "Remove Source", "-", "Compare with Newer Download", "Replace with File…", "-", "Send to Claude", "Rename…", "Move to…", "Move to Trash"], 270)
SRC_ROW = '<div class="ft" style="padding-left:18px">_sources.md</div>'
fl_a = f'<div style="width:300px;background:{PANE};position:relative">{files_block(sel=DECK, extra_rows=SRC_ROW)}</div>'
board("05-files", 1300, 760, "5 · In Files, and the right-click menu", "A link mark on files with a source; _sources.md as an ordinary file; Source and compare items in the menu.", bd(1300, 760,
    "5 · In Files, and the right-click menu",
    "A file with a line in its folder’s _sources.md shows the link mark. _sources.md itself is an ordinary Markdown file: it opens in the editor like any other.",
    f'''<div style="display:flex;gap:40px;align-items:flex-start">
{frame(fl_a, cap="Files", note="The link mark comes from _sources.md. A renamed file keeps its mark when Duo did the rename (it rewrites the line); after a Finder rename, the line is matched again by name and Google id when Duo next reads the folder.", w=300)}
{frame(f'<div style="padding:14px;background:{GROUND}">{mn}</div>', cap="Right-click on the deck", note="The Source group appears only on a file with a source; on one without, a single Add Source… item. Compare with Newer Download and Replace with File… are there for every .pptx and .docx.", w=298)}
</div>'''))

# 06 · newer downloads
p1 = deck_pane(420, 380, line="newer-nosrc")
p2 = deck_pane(420, 380, line="waiting")
p3 = deck_pane(420, 380, line="snap", notice=pnotice("No changes since 30 Sep. Your copy is current.", ["OK"], close=False))
p4 = deck_pane(420, 380, line="snap", notice=pnotice("No download seen in 5 minutes.", ["Choose File…"]))
board("06-newer", 2100, 920, "6 · Newer downloads, with or without a source", "Duo notices a newer download of any .pptx or .docx in a project; Get Latest adds the browser trip for Google links.", bd(2100, 920,
    "6 · Newer downloads, with or without a source (Q-155)",
    "Duo keeps a live Spotlight query for downloaded files that match a project’s .pptx and .docx (board 13). It never lists ~/Downloads: Spotlight answers. A source only adds Get Latest, which opens the export link in the default browser so the user needn’t find File › Download.",
    f'''<div style="display:flex;gap:40px;align-items:flex-start">
{frame(p1, cap="1 · Found, no source needed", note="You downloaded “Q3 plan” again; Chrome saved it as Q3 plan (1).pptx. The bar says so the next time the deck is on screen, and Files marks the deck. Compare opens board 7.", w=420)}
{frame(p2, cap="2 · Get Latest (Google links only)", note="Opens …/export/pptx (or ?format=docx) in the default browser, signed in to Google. The bar waits up to 5 minutes, then shows 1 or 4.", w=420)}
{frame(p3, cap="3 · Nothing changed", note="Contents compared, not bytes (two downloads always differ). Said once; the download is left where it was.", w=420)}
{frame(p4, cap="4 · Nothing seen", note="Spotlight off, or the browser saved somewhere unindexed. Choose File… opens an Open panel at Downloads, filtered to .pptx; picking a file is the user’s own choice.", w=420)}
</div>
<div class="note" style="max-width:1600px"><b>On by default</b> [P]: the query reads only Spotlight’s index, so Duo opens a downloaded file only when the user clicks Compare. If that click is when macOS asks for Downloads access (Q-155), it’s asked at the user’s own action, never on Duo’s. Settings can turn it off.</div>'''))

# 07 · compare deck
def cmp_row(n, ta, tb, state, ba="", bb_="", w=250):
    tg = {"same": '<span class="tag">same</span>', "changed": '<span class="tag dk">changed</span>', "new": '<span class="tag dk">new</span>', "removed": '<span class="tag dk">removed</span>'}[state]
    left = slide(w, ta, ba) if ta else f'<div style="width:{w}px;height:{int(w * 9 / 16)}px;border:1px dashed {RULE};flex:none"></div>'
    right = slide(w, tb, bb_, chg=(state in ("changed", "new"))) if tb else f'<div style="width:{w}px;height:{int(w * 9 / 16)}px;border:1px dashed {RULE};flex:none"></div>'
    return (f'<div style="display:flex;flex-direction:column;gap:4px"><div style="display:flex;align-items:center;gap:6px;font-size:11px;line-height:16px"><b style="font-weight:600">{n}</b>{tg}</div>'
            f'<div style="display:flex;gap:16px">{left}{right}</div></div>')


W = 250
cmp_body = (cmp_row("2", "Revenue by quarter", "Revenue by quarter", "changed", bars(W, [40, 55, 72, 64]), bars(W, [40, 55, 72, 81]))
            + cmp_row("3", "What we ship in Q3", "What we ship in Q3", "changed", bullets(W, ["Billing v2 to every plan", "Usage alerts", "SSO for teams"]), bullets(W, ["Billing v2 to every plan", "Usage alerts", "<b>Audit log</b>"]))
            + cmp_row("4", None, "Risks", "new", "", bullets(W, ["Hiring for SSO", "Billing migration"])))
cmp_pane = (f'<div style="width:600px;height:760px;display:flex;flex-direction:column;background:{PANE};border:1px solid {RULE};overflow:hidden;font-size:13px;line-height:20px;white-space:nowrap">'
            f'<div style="display:flex;align-items:center;gap:18px;height:36px;flex:none;padding:0 20px;border-bottom:1px solid {RULE}"><span class="t2">Project</span><span class="t2">{DECK}</span><span style="font-weight:600">Compare · Q3 plan</span><span class="t2">+</span></div>'
            f'<div class="vbar"><span class="vb" style="padding:4px 7px">‹</span><span class="vb" style="padding:4px 7px">›</span><span style="margin-left:4px">Change 1 of 3</span><span style="flex:1"></span>'
            f'<span class="cb" style="font-size:12px"><i>✓</i>Changed only</span><span class="vb">Keep Mine</span><span class="vb" style="border:1.5px solid {TEXT};font-weight:600">Replace</span></div>'
            f'<div style="display:flex;gap:16px;padding:8px 20px 6px;font-size:11px;line-height:16px;color:{TEXT2};border-bottom:1px solid {RULE}"><span style="width:{W}px"><b style="color:{TEXT};font-weight:600">Your copy</b> · 30 Sep, 09:12</span><span style="width:{W}px"><b style="color:{TEXT};font-weight:600">The download</b> · today, 15:24</span></div>'
            f'<div style="flex:1;min-height:0;display:flex;flex-direction:column;gap:14px;padding:12px 20px;background:{GROUND};overflow:hidden">{cmp_body}</div></div>')
alt = (f'<div style="width:420px;height:420px;display:flex;flex-direction:column;background:{PANE};border:1px solid {RULE};overflow:hidden;white-space:nowrap">'
       f'<div class="vbar"><span class="segc"><span>Mine</span><span class="on">Download</span></span><span style="margin-left:6px">Slide 3 · changed</span><span style="flex:1"></span><span class="vb">Replace</span></div>'
       f'<div style="flex:1;padding:16px 20px;background:{GROUND}">{slide(380, "What we ship in Q3", bullets(380, ["Billing v2 to every plan", "Usage alerts", "<b>Audit log</b>"]), chg=True)}'
       f'<div class="note" style="margin-top:10px">Hold Space to flick to your copy.</div></div></div>')
board("07-compare-deck", 1500, 1020, "7 · Compare a deck", "A: two columns, slides matched by Google’s slide ids, changes marked. B: one slide at a time, flicking.", bd(1500, 1020,
    "7 · Compare a deck, side by side",
    "A right-pane tab beside the deck (it can be widened, DL-129). Slides are paired by Google’s slide id, so a moved slide is still paired; then by position. Each pair: same, changed, new or removed.",
    f'''<div style="display:flex;gap:60px;align-items:flex-start">
{frame(cmp_pane, cap="A · Two columns" + '<span class="rec">recommended</span>', note="Both columns use the deck renderer (DL-121). <b>Changed only</b> hides pairs that are the same. A changed slide gets a dark outline on the download’s side; the words that changed aren’t marked inside the slide (the renderer draws the slide whole). ‹ › step through changes.", w=600)}
{frame(alt, cap="B · One slide, flicking", note="Like Keynote’s and Photos’ compare: the same place on screen, Mine | Download. Better for spotting a moved chart; worse for seeing everything at once.", w=420)}
</div>'''))

# 08 · compare document
red = f'''<div style="padding:18px 24px;white-space:normal;font-size:13px;line-height:21px;display:flex;flex-direction:column;gap:12px;background:{PANE};flex:1">
<div style="font-size:18px;font-weight:600;line-height:26px">Launch brief</div>
<div>The launch moves to <span class="del">October 14</span> <span class="ins">October 21</span>, after the billing migration.</div>
<div style="color:{TEXT2}">Owners: Product (Maya), Marketing (Jon), Support (Ines).</div>
<div><span class="ins">We will pause the annual discount during the first week, so support can keep up.</span></div>
<div style="color:{TEXT2}">Success means 400 teams on the new plans by the end of Q3.</div>
<div><span class="del">Press: an embargoed briefing on the 13th.</span></div></div>'''
doc_pane = (f'<div style="width:520px;height:600px;display:flex;flex-direction:column;background:{PANE};border:1px solid {RULE};overflow:hidden;white-space:nowrap">'
            f'<div style="display:flex;align-items:center;gap:18px;height:36px;flex:none;padding:0 20px;border-bottom:1px solid {RULE}"><span class="t2">Launch brief.docx</span><span style="font-weight:600">Compare · Launch brief</span><span class="t2">+</span></div>'
            f'<div class="vbar"><span class="segc"><span>Mine</span><span class="on">Changes</span><span>Download</span></span><span style="margin-left:6px">3 changes</span><span style="flex:1"></span><span class="vb">Keep Mine</span><span class="vb" style="border:1.5px solid {TEXT};font-weight:600">Replace</span></div>'
            f'<div style="height:24px;flex:none;display:flex;align-items:center;padding:0 20px;font-size:11px;color:{TEXT2};border-bottom:1px solid {RULE};background:{GROUND}"><span>Your copy · 30 Sep → the download · today, 15:24</span></div>{red}</div>')
board("08-compare-doc", 1300, 800, "8 · Compare a document", "Changes as a redline in the docx viewer’s look; Mine | Changes | Download.", bd(1300, 800,
    "8 · Compare a document",
    "Paragraphs are matched on their text (from Duo’s docx reader); words that changed are struck and underlined, in ink, not colour. Mine | Changes | Download switches. It shares the docx viewer’s look (DL-162), which another session is designing now: this board follows whatever that bar becomes.",
    f'''<div style="display:flex;gap:60px;align-items:flex-start">
{frame(doc_pane, cap="One column, a redline" + '<span class="rec">recommended</span>', note="Side-by-side pages are the fallback for a document whose text barely changed but whose layout did (a table, a picture): then the Download side is drawn with the viewer, and the change count says “layout only”.", w=520)}
<div class="txt" style="width:420px"><h3>What counts as a change</h3><ul>
<li>Text, in order, paragraph by paragraph; a moved paragraph shows as removed and added.</li>
<li>Pictures, as a set: one added or removed is listed at the foot (“1 picture added”).</li>
<li>Comments and tracked changes in the download are shown by the viewer, not by the compare.</li>
<li>Formatting alone (bold, a style) isn’t a change here.</li></ul>
<h3>Why not Word’s Compare?</h3><p>Duo can’t run Word, and the user may not have it. Open With › Word on both files still works for a full compare.</p></div>
</div>'''))

# 09 · replace + history
p_r = deck_pane(420, 400, line="snap", notice=pnotice(f'Replaced {DECK} with today’s download. The 30 Sep copy is in the Trash.', ["Undo"]))
hist_a = f'<div class="txt" style="width:300px"><h3>A · Trash only</h3><p>The old copy goes to the Trash; the note lists the dates. In a git project, the old copy is also in history.</p><p class="note">Nothing new in the folder.</p></div>'
hist_b = f'<div class="txt" style="width:300px"><h3>B · Dated copies</h3><p>The old copy stays as <span class="mono" style="font-size:12px">Q3 plan (30 Sep).pptx</span> in a <span class="mono" style="font-size:12px">snapshots/</span> folder beside it.</p><p class="note">Every version at hand; the folder grows.</p></div>'
hist_c = f'<div class="txt" style="width:300px"><h3>C · Ask each time</h3><p>Replace… asks: Trash the old copy, or keep it dated.</p><p class="note">One more question each time.</p></div>'
board("09-replace", 1500, 760, "9 · Replace, Undo, history", "Replace keeps the name; the old copy goes to the Trash with Undo; Q-156 on history.", bd(1500, 760,
    "9 · Replace, with Undo, and what’s kept (Q-156)",
    "The download takes the old file’s name and place, so links, a task’s references: and Claude’s memory of the path still work. The download in ~/Downloads is left alone.",
    f'''<div style="display:flex;gap:40px;align-items:flex-start">
{frame(p_r, cap="After Replace", note="Undo puts the old copy back and the download back where it was. The line’s date becomes today.", w=420)}
<div style="display:flex;flex-direction:column;gap:12px"><div class="cap">What’s kept</div><div style="display:flex;gap:16px">{hist_a.replace("A · Trash only", "A · Trash only" + '<span class="rec">recommended</span>')}{hist_b}{hist_c}</div>
<div class="note" style="width:940px">If the file is open in another app (PowerPoint), Duo says so and doesn’t replace it. If someone edited the project’s copy since it was downloaded (it no longer matches its download), Replace warns: “Your copy has changes that aren’t in Google Slides.”</div></div>
</div>'''))

# 10 · where the link is kept
sources_md = """---
type: sources
---

# Sources

- [Q3 plan.pptx](./Q3%20plan.pptx): [Q3 plan](https://docs.google.com/presentation/d/1EAY…/edit) · Google Slides · downloaded 2026-09-30
- [Launch brief.docx](./Launch%20brief.docx): [Launch brief](https://docs.google.com/document/d/1hK…/edit) · Google Docs · downloaded 2026-10-02
- [vendor-terms.pdf](./vendor-terms.pdf): [Vendor terms](https://example.com/terms) · example.com · added 2026-10-05"""
obs = (f'<div class="obs" style="width:620px;height:300px"><div style="width:180px;background:#262626;padding:10px 8px;display:flex;flex-direction:column;gap:2px;color:#BBB">'
       f'<div>▾ inputs</div><div style="padding-left:14px;background:#3A3A3A;border-radius:4px;color:#EEE">_sources</div><div style="padding-left:14px">Launch brief.docx</div><div style="padding-left:14px">Q3 plan.pptx</div><div style="padding-left:14px">survey.csv</div><div style="padding-left:14px">vendor-terms.pdf</div></div>'
       f'<div style="flex:1;padding:12px 16px;white-space:normal"><div style="font-size:16px;font-weight:600;color:#EEE;margin-bottom:6px">Sources</div>'
       f'<div style="display:grid;grid-template-columns:60px 1fr;gap:3px 8px;font-size:12px;margin-bottom:8px"><span style="color:#999">type</span><span>sources</span></div>'
       f'<div style="display:flex;flex-direction:column;gap:6px">'
       f'<div>• <span style="color:#8AB4F8;text-decoration:underline">Q3 plan.pptx</span>: <span style="color:#8AB4F8;text-decoration:underline">Q3 plan</span> · Google Slides · downloaded 2026-09-30</div>'
       f'<div>• <span style="color:#8AB4F8;text-decoration:underline">Launch brief.docx</span>: <span style="color:#8AB4F8;text-decoration:underline">Launch brief</span> · Google Docs · downloaded 2026-10-02</div>'
       f'<div>• <span style="color:#8AB4F8;text-decoration:underline">vendor-terms.pdf</span>: <span style="color:#8AB4F8;text-decoration:underline">Vendor terms</span> · example.com · added 2026-10-05</div></div></div></div>')
rules = """<ul>
<li><b>One file per folder</b>, beside the files it describes: <span class="mono">_sources.md</span>. The first Add Source in a folder creates it; later ones add a line.</li>
<li><b>One line per file</b>: a Markdown link to the file, a link to its source, the kind (Google Slides, Google Docs, or the site’s name), and the date. A Markdown list, so two sessions adding lines rarely conflict in git.</li>
<li><b>Duo owns only its lines</b>: it rewrites a file’s line on Change Source, Remove Source, Rename, Move and Replace, and leaves anything else in the file (a heading, notes the user wrote) alone.</li>
<li><b>Never the raw download address</b>, only the clean link.</li>
<li><b>Obsidian and OKF</b>: <span class="mono">type: sources</span> for OKF; Markdown links, which both read; no new syntax.</li>
<li><b>Never inside the .pptx or .docx</b>; writing the link into the file’s own properties stays a possible later action (ENH-56).</li></ul>"""
board("10-where-kept", 1500, 820, "10 · Where the link is kept: _sources.md", "Decided (DL-163): one _sources.md per folder, one line per file, created on the first Add Source.", bd(1500, 820,
    "10 · Where the link is kept: one _sources.md per folder (DL-163)",
    "Geoff, 2026-10-08: “if they add source, a source file is created in same folder (or appended to if one exists); thin bar carries a link so the user can click on it in a future session”.",
    f'''<div style="display:flex;gap:30px;align-items:flex-start">
<div style="display:flex;flex-direction:column;gap:10px;width:680px"><div class="cap">inputs/_sources.md</div>
<div class="txt"><div class="fm" style="white-space:pre-wrap">{e(sources_md)}</div></div>
<div class="cap">The same file in Obsidian</div>{obs}</div>
<div class="txt" style="width:700px"><h3>The rules</h3>{rules}</div>
</div>'''))

# 11 · Claude and duo2
claude_txt = (f'<span style="color:{CTEXT2}">&gt;</span> where did the Q3 deck come from? is it current?<br><br>'
              f'inputs/Q3 plan.pptx is a snapshot of the Google Slides deck “Q3 plan”<br>'
              f'(docs.google.com/presentation/d/1EAYk18WDj…/edit), downloaded 30 Sep.<br>'
              f'I can’t open Google Slides myself. If you want the latest, I can ask Duo<br>to fetch it: <span style="color:{CTEXT}">duo2 file latest "inputs/Q3 plan.pptx"</span>, then you download it in your browser.')
verbs = [("duo2 file source &lt;path&gt;", "The link, title, kind and date, from _sources.md (JSON with --json)", "the bar’s line, the popover"),
         ("duo2 file source &lt;path&gt; --set &lt;url&gt; | --clear", "Add or remove the file’s line in _sources.md", "Add Source, Remove Source"),
         ("duo2 file source &lt;path&gt; --open [--slide n]", "Open it in the default browser", "the title link, Slide n in Slides"),
         ("duo2 file latest &lt;path&gt;", "Open the export link and watch for the download", "Get Latest"),
         ("duo2 file newer [&lt;path&gt;]", "Newer downloads of a file (or of every .pptx and .docx in the project), source or not", "the bar’s “A newer download”"),
         ("duo2 file compare &lt;path&gt; [&lt;newer&gt;]", "Open the compare (newest matching download by default)", "Compare"),
         ("duo2 file replace &lt;path&gt; &lt;newer&gt; [--keep-old]", "Replace; old copy to the Trash (or dated)", "Replace, Undo"),
         ("duo2 file snapshots &lt;path&gt;", "The dates it was replaced", "the popover’s Snapshots")]
vt = "".join(f'<tr><td class="mono" style="font-size:11px;white-space:nowrap">{a}</td><td>{b}</td><td class="t2">{c}</td></tr>' for a, b, c in verbs)
sent = f'''<div class="pre" style="width:560px">{e("inputs/Q3 plan.pptx, slide 2, “Revenue by quarter”, shape “Chart 3” (id 27)")}
<span class="k">Source: Google Slides “Q3 plan”, docs.google.com/presentation/d/1EAYk18WDj…/edit (snapshot, downloaded 30 Sep)
This slide in Slides: …/edit#slide=id.ge63a4b4_1_9</span>
duo2 slide shapes "inputs/Q3 plan.pptx" 2</div>'''
board("11-claude", 1700, 820, "11 · What Claude sees, and duo2", "The source in Claude’s context; the duo2 verbs for every new action (DL-71).", bd(1700, 820,
    "11 · What Claude sees, and the duo2 verbs (DL-71)",
    "Claude can’t reach Google, but it can say where a file came from, and ask Duo for a newer copy. Duo’s teaching text (cli-teaching.md) gains one line about duo2 file source.",
    f'''<div style="display:flex;gap:40px;align-items:flex-start">
<div style="display:flex;flex-direction:column;gap:14px">
{frame(qconsole(claude_txt, w=640) , cap="Asked in a session", note="Claude reads the folder’s _sources.md (or runs duo2 file source), and says it can’t open the link itself.", w=640)}
<div class="cap">A picked shape, as pasted into Claude’s prompt (DL-125 D, one line added)</div>{sent}
</div>
<div style="display:flex;flex-direction:column;gap:8px;width:900px"><div class="cap">New verbs</div>
<table class="cmp"><thead><tr><th style="width:330px">Verb</th><th>Does</th><th style="width:220px">In the app</th></tr></thead><tbody>{vt}</tbody></table>
<div class="note">Send to Claude, the docx reader and duo2 doc read add a <b>Source:</b> line for a file that has one. <span class="mono">duo2 files</span> marks files with a source.</div></div>
</div>'''))

# 12 · decided
board("12-recommendation", 1440, 860, "12 · What’s decided, and a first slice", "Geoff’s choices (DL-163) and the slices.", bd(1440, 860,
    "12 · What’s decided (DL-163), and a first slice",
    "One rule underneath: the downloaded file is never changed, and Duo never looks in Downloads on its own.",
    f'''<div style="display:flex;gap:14px;align-items:flex-start">
<div class="txt" style="flex:1"><h3>Decided (Geoff, 2026-10-08)</h3><ul>
<li><b>A thin bar under the viewer’s bar</b> on every .pptx and .docx (2, 3 A). It offers Add Source, prefilled in one click when the browser’s “Where from” knows the link; nothing is written until then.</li>
<li><b>One _sources.md per folder</b> (10): created by the first Add Source, a line added by each after; <span class="mono">type: sources</span>, one Markdown list line per file.</li>
<li><b>The bar carries the link</b> in later sessions: the title opens it in the default browser; the popover for the rest (4).</li>
<li><b>Newer downloads, compare and replace work with or without a source</b> (6, 13). Get Latest is the extra for Google links.</li>
<li><b>Replace</b> keeps the name; the old copy goes to the Trash with Undo (9 A).</li>
<li><b>Claude</b> reads _sources.md and is told the source wherever Duo hands it the file (11).</li></ul></div>
<div class="txt" style="width:560px;flex:none"><h3>Slice 1</h3><ol>
<li>The thin bar on the deck viewer (and the docx viewer when DL-162 lands): Add Source with the “Where from” prefill, Add Source…, the link, the popover.</li>
<li>_sources.md: create, add, change, remove; rename and move keep lines.</li>
<li>Open in Google Slides / Docs, Slide n in Slides, Copy Link; the link mark in Files.</li>
<li>Claude: the Source line in Send to Claude and slide pick; duo2 file source.</li></ol>
<h3>Slice 2</h3><ol start="5">
<li>Newer downloads by Spotlight (13), the bar’s notice, duo2 file newer; Get Latest; Choose File….</li>
<li>Compare (deck, then document), Replace with Undo.</li></ol>
<h3>Later</h3><ul><li>Write Link into File (ENH-56); Sheets with an xlsx viewer (ENH-55).</li></ul>
<h3>Before slice 2</h3><ul><li>Q-155: does opening a download from Spotlight ask for Downloads access, tested with Geoff’s OK or a test bundle id.</li></ul></div></div>'''))

# 13 · matching
mt = [("The name", "The project file’s name without its extension, matched to a download’s name with the browser’s copy marks stripped: “Q3 plan (1).pptx”, “Q3 plan-2.pptx”, “Q3 plan (2026-10-08).pptx” all match “Q3 plan”. Same extension. Case ignored.", "always"),
      ("A download", "Spotlight’s “Where from” is set (it came through a browser, Mail or AirDrop), so files the user saved by hand elsewhere aren’t candidates.", "always"),
      ("Newer", "Downloaded (quarantine time, else created) after the project copy’s date: its _sources.md date, else when the file arrived in the project.", "always"),
      ("The Google id", "When either side knows one (the source line, or the download’s “Where from”), the ids must agree; a different id is a different document even with the same name.", "when known"),
      ("Not already seen", "A download the user compared and kept theirs over isn’t offered again.", "always")]
mt_rows = "".join(f'<tr><th>{a}</th><td>{b}</td><td class="t2" style="width:110px">{c}</td></tr>' for a, b, c in mt)
board("13-matching", 1300, 700, "13 · How a download is matched", "Name, a real download, newer, the Google id when known: no source needed.", bd(1300, 700,
    "13 · How Duo knows a download is a newer copy (no source needed)",
    "Geoff, 2026-10-08: “download monitoring and updating should be agnostic of whether the source url exists”. Google names a download after the document’s title, so the name is the common key; the id, when either side has one, settles it.",
    f'''<div style="display:flex;gap:30px;align-items:flex-start">
<div class="txt" style="flex:1"><table class="cmp"><thead><tr><th>Rule</th><th>What</th><th>Applies</th></tr></thead><tbody>{mt_rows}</tbody></table></div>
<div class="txt" style="width:420px"><h3>Verified (F-241)</h3><ul>
<li>A Spotlight query on the name finds “Baby album (1).pptx” for “Baby album.pptx”, and the “Where from” filter keeps only downloads [V].</li>
<li>Spotlight can find by Google id inside “Where from” [V].</li>
<li>Chrome leaves Spotlight’s “Downloaded date” empty; the quarantine stamp has the time [V].</li></ul>
<h3>When the name changed</h3><p>If the document was renamed in Google, its next download has a new name: only the id finds it, so a file with a Google source is also matched by id alone.</p></div>
</div>'''))

with open(os.path.join(OUT, "manifest.json"), "w") as f:
    import json
    json.dump(BOARDS, f, indent=1)
print(len(BOARDS), "boards")
