#!/usr/bin/env python3
"""Draws the knowledge-base (LLM wiki / second brain) study boards, every mark [P], as static HTML
in the Duo design system.

    python3 docs/design/second-brain-study/canvas/make.py
    bash docs/design/second-brain-study/canvas/render.sh

Reuses the project & task CX study's helpers (everything above its "00 study" board), which in
turn reuse the home-evolution study's tokens, CSS and glyphs, so the three studies draw the same
app. Names and data are illustrative. The study is docs/research/second-brains.md.
"""
import html, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(HERE, "../../project-task-cx/canvas/make.py")).read()
_src = _src[:_src.index("# ---------------------------------------------------------------- 00 study")]
_src = _src.replace('HERE = os.path.dirname(os.path.abspath(__file__))', f'HERE = {os.path.join(HERE, "../../project-task-cx/canvas")!r}')
MINE = HERE
exec(_src)
HERE = MINE
OUT = os.path.join(HERE, "boards")
BOARDS = []

CSS += f"""
.rp{{flex:1;min-width:0;background:{PANE};display:flex;flex-direction:column;white-space:normal}}
.rtabs{{height:36px;flex:none;border-bottom:1px solid {RULE};display:flex;align-items:stretch;padding:0 16px;gap:18px;white-space:nowrap}}
.rtabs span{{display:flex;align-items:center;color:{TEXT2}}}
.rtabs .on{{color:{TEXT};font-weight:600;box-shadow:inset 0 -2px 0 {TEXT}}}
.doc{{padding:16px 22px;display:flex;flex-direction:column;gap:6px;font-size:14px;line-height:22px}}
.doc h1{{margin:0 0 4px;font-size:20px;line-height:28px;font-weight:600}}
.doc h2{{margin:8px 0 0;font-size:15px;line-height:22px;font-weight:600}}
.doc p{{margin:0}}
.lk{{text-decoration:underline;text-decoration-color:{EDGE};text-underline-offset:3px}}
.unres{{color:{TEXT2};text-decoration:underline dashed;text-decoration-color:{EDGE};text-underline-offset:3px}}
.br{{color:{EDGE};font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:12px}}
.tip{{background:{PANE};border:1px solid {RULE};border-radius:6px;box-shadow:0 6px 18px rgba(31,35,40,.16);padding:6px 10px;font-size:12px;line-height:16px;white-space:nowrap}}
.left{{width:300px;flex:none;border-right:1px solid {RULE};display:flex;flex-direction:column;background:{PANE};white-space:nowrap}}
.irow{{display:flex;align-items:center;gap:8px;height:26px;padding:0 8px;margin:0 8px;border-radius:6px}}
.irow .ti{{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis}}
.sb{{display:inline-flex;align-items:center;height:20px;padding:0 8px;border:1px solid {EDGE};border-radius:5px;background:{PANE};font-size:11px;line-height:16px;font-weight:600;letter-spacing:0;text-transform:none;color:{TEXT}}}
.desk{{background:linear-gradient(160deg,#B9C3CE,#8E9AA8);position:relative;overflow:hidden}}
.panel{{position:absolute;background:rgba(250,250,251,.97);border:1px solid {RULE};border-radius:12px;box-shadow:0 18px 50px rgba(31,35,40,.32);display:flex;flex-direction:column;white-space:normal}}
.ta{{background:{PANE};border:1px solid {RULE};border-radius:8px;padding:8px 10px;font-size:14px;line-height:22px;min-height:96px}}
.caret{{display:inline-block;width:1.5px;height:17px;background:{TEXT};vertical-align:-3px}}
.kbd{{font-size:12px;line-height:16px;color:{TEXT2}}}
.kbd b{{font-weight:600;color:{TEXT}}}
.lane{{font:600 11px/16px -apple-system,system-ui,sans-serif;letter-spacing:.5px;color:{TEXT2};text-transform:uppercase}}
table.bp{{border-collapse:collapse;width:100%;font-size:12px;line-height:17px;white-space:normal;table-layout:fixed}}
table.bp td,table.bp th{{border:1px solid {RULE};padding:7px 8px;vertical-align:top;text-align:left;background:{PANE}}}
table.bp th{{background:{GROUND};font-weight:600}}
table.bp td.v1{{box-shadow:inset 3px 0 0 {TEXT}}}
.tag{{display:inline-block;font:600 10px/14px -apple-system,system-ui,sans-serif;border:1px solid {EDGE};border-radius:7px;padding:0 5px;color:{TEXT2};vertical-align:1px}}
.tag.v1{{border-color:{TEXT};color:{TEXT}}}
"""

BOOK = f'<svg width="12" height="11" viewBox="0 0 12 11" style="flex:none"><path d="M6 2.2C4.8 1.3 3.2 1 1 1v8c2.2 0 3.8.3 5 1.2 1.2-.9 2.8-1.2 5-1.2V1c-2.2 0-3.8.3-5 1.2zM6 2.2v8" fill="none" stroke="{TEXT2}" stroke-width="1.1" stroke-linejoin="round"/></svg>'
TRAY = f'<svg width="12" height="11" viewBox="0 0 12 11" style="flex:none"><path d="M1 6.5 2.6 1.6h6.8L11 6.5V9.4H1z M1 6.5h3l.7 1.3h2.6L8 6.5h3" fill="none" stroke="{TEXT2}" stroke-width="1.1" stroke-linejoin="round"/></svg>'
NOTE = f'<svg width="10" height="12" viewBox="0 0 10 12" style="flex:none"><path d="M1.5 1h4.6L8.5 3.4V11h-7z M6 1v2.6h2.5" fill="none" stroke="{TEXT2}" stroke-width="1.1" stroke-linejoin="round"/></svg>'


def board(name, w, h, title, note, body):
    BOARDS.append(dict(name=name, w=w, h=h, title=title, kind="board"))
    doc = f'''<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="design-size" content="{w}x{h}">
<meta name="design-kind" content="board">
<meta name="design-surface" content="second-brain-study">
<!--
{e(title)}
STUDY BOARD [P], not approved. Drawn for the knowledge-base study (2026-10-07) with the Duo design system.
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


def rpane(tabs, sel, body, plus=True):
    t = "".join(f'<span class="{"on" if i == sel else ""}">{x}</span>' for i, x in enumerate(tabs))
    return f'<div class="rp"><div class="rtabs">{t}{"<span>+</span>" if plus else ""}</div>{body}</div>'


INBOX = [("Pricing sync: annual discount test starts Nov 3", "2h"), ("Competitor raised Pro tier to $24", "5h"),
         ("Clip: Patrick Campbell on value metrics", "1d"), ("Idea: usage-based add-on for API calls", "1d"),
         ("Call notes, Ana (finance)", "2d"), ("Clip: Stripe pricing page teardown", "3d")]


def kb_left(inbox_open=True, sel_session=None, processing=False):
    head = f'''<div style="padding:12px 16px 6px"><div style="font-weight:600">pricing-wiki</div>
<div class="t2" style="display:flex;align-items:center;gap:6px">{BOOK}Knowledge base · 12 in inbox</div></div>'''
    if inbox_open:
        rows = "".join(f'<div class="irow">{NOTE}<span class="ti">{e(t)}</span><span class="t2">{tm}</span></div>' for t, tm in INBOX)
        btn = '<span class="sb" style="margin-left:auto">Process with Claude</span>' if not processing else f'<span style="margin-left:auto;display:flex;align-items:center;gap:5px;text-transform:none;letter-spacing:0;font-weight:400">{g("working")}Claude is processing</span>'
        inbox = f'''<div class="sec" style="display:flex;align-items:center;gap:6px;padding-right:16px">{g("chevd")}INBOX · 12 <span class="t2" style="font-weight:400;letter-spacing:0">+</span>{btn}</div>{rows}<div class="fold" style="height:22px;font-size:12px">6 more · oldest 9 days</div>'''
    else:
        inbox = f'<div class="fold">{g("chev")}INBOX · 12</div>'
    sess = [("idle", "Ask: what do we know about annual discounts?", "1d"), ("idle", "Ingest: Q3 win/loss interviews", "3d")]
    if sel_session:
        sess = [sel_session] + sess
    srows = "".join(f'<div class="row{" sel" if i == 0 and sel_session else ""}">{g(GLYPH_FOR[st])}<span class="ti">{e(t)}</span><span class="tm">{tm}</span></div>' for i, (st, t, tm) in enumerate(sess))
    return f'''<div class="left">{head}{inbox}{sec("This week")}{srows}{fold("Earlier · 14")}<div style="flex:1"></div>
<div style="border-top:1px solid {RULE};padding:8px 16px 10px"><div class="sl">FILES</div><div class="mono t2" style="margin-top:4px">AGENTS.md · index.md · log.md</div><div class="mono t2">inbox/ · raw/ · wiki/ · templates/</div></div></div>'''


def console(w, title="No session open in pricing-wiki", sub="Start Claude here. It’s told where the schema, index, log and inbox are."):
    return f'<div style="width:{w}px;flex:none;background:{CONSOLE};color:{CTEXT};padding:20px;white-space:normal"><div style="font-weight:600">{title}</div><div style="color:{CTEXT2};margin:4px 0 12px">{sub}</div><span class="b" style="background:transparent;color:{CTEXT};border-color:{CTEXT2}">Start Claude here</span></div>'


INDEX_DOC = '''<div class="doc"><h1>Pricing wiki: index</h1>
<p class="t2" style="font-size:13px">Every page, one line each. Claude updates this on every ingest.</p>
<h2>Concepts</h2>
<p>• <span class="lk">Value metric</span>: the unit a price scales with; ours is seats today</p>
<p>• <span class="lk">Annual discount</span>: 16% now; test of 20% starts Nov 3</p>
<p>• <span class="lk">Usage-based pricing</span>: where it fits our API add-on</p>
<h2>Competitors</h2>
<p>• <span class="lk">Acme</span>: Pro tier $24 since Oct 2 (was $20)</p>
<p>• <span class="lk">Globex</span>: per-seat, no annual discount</p>
<h2>Sources</h2>
<p>• <span class="lk">Q3 win/loss interviews</span> (raw/2026-09-30-win-loss.pdf), 14 pages touched</p></div>'''

LOG_DOC = '''<div class="doc"><h1>Log</h1>
<h2>2026-10-07</h2>
<p>• <b>Update</b>: <span class="lk">Acme</span>, Pro tier now $24 (from inbox, 1 note)</p>
<p>• <b>Creation</b>: <span class="lk">Usage-based pricing</span></p>
<h2>2026-10-04</h2>
<p>• <b>Ingest</b>: <span class="lk">Q3 win/loss interviews</span>, 14 pages updated</p>
<p>• <b>Lint</b>: 2 orphans linked, 1 contradiction flagged on <span class="lk">Annual discount</span></p>
<h2>2026-09-28</h2>
<p>• <b>Update</b>: <span class="lk">Value metric</span>, seats vs. API calls</p></div>'''

# ---------------------------------------------------------------- 00 study
board("00-study", 1280, 900, "0 · Knowledge bases in Duo: the study", "The question, who it's for, what the research found, the principles.", bd(1280, 900,
    "0 · LLM wikis and second brains in Duo: the study",
    "Geoff, 2026-10-07: “many users will have a project (or more) that contain LLM wiki and or OKF second brains … think about what features we could add (not just a pile of features but thoughtful service design) to better support these uses without getting in others’ way.” Standing rule: maximise compatibility with Obsidian and OKF. The doc is <code>docs/research/second-brains.md</code>; the sources are in <code>docs/research/second-brain-sources/</code>. Every mark on these boards is a proposal [P].",
    f'''<div style="display:flex;gap:14px;align-items:flex-start">
<div class="txt" style="flex:1"><h3>Who</h3><ul>
<li><b>The Obsidian keeper.</b> A vault of notes they write: PARA or Zettelkasten, daily notes, Templates, Clippings, wikilinks. Wants Claude beside the notes without breaking them.</li>
<li><b>The wiki operator</b> (Karpathy’s pattern). <code>raw/</code> sources, pages Claude writes, <code>index.md</code>, <code>log.md</code>, a schema in AGENTS.md or CLAUDE.md. “You read it; the LLM writes it.” Fears drift.</li>
<li><b>The work brain</b> (Geoff’s case). OKF notes fed from everywhere (Brainstem’s email and assistant inbox), filed by Claude, read in Obsidian. Fears losing a capture, or a silent rewrite.</li>
<li><b>Everyone else</b> uses Duo for code and documents and must never notice any of this.</li></ul>
<h3>What the research found</h3><ol>
<li><b>The value is two loops, not a second Obsidian.</b> Capture is one gesture with no decisions (Apple Quick Note, QuickAdd, Drafts, Tana). Processing is where AI earns its keep: Claude proposes, the person confirms (GTD’s clarify; Forte’s weekly 10–20; Karpathy’s ingest touching 10–15 pages).</li>
<li><b>Legacy Duo proved it.</b> Its inbox and Claude’s processing pass were the differentiator; its rollup engine, Bases renderer and vault tabs duplicated Obsidian and were dropped as “a second product”.</li>
<li><b>Keep a human in each loop.</b> Drift, lost citations and “slop” are the pattern’s known failures; the designs that hold ingest one source at a time, ask before writing and show the diff.</li>
<li><b>index.md and log.md are shared state.</b> Every ingest rewrites both; parallel sessions and sync collide there. OKF’s log is newest first, Karpathy’s oldest first.</li>
<li><b>Duo misreads vaults today</b>: wikilinks are dead text, shortest-path links “aren’t there”, a <code>Tasks/</code> folder becomes Duo tasks, big folders truncate arbitrarily, and a vault can’t be made a project.</li></ol></div>
<div class="txt" style="width:470px;flex:none"><h3>Principles [P]</h3><ol>
<li><b>Opt-in, invisible until then.</b> No chord, fold or context line until a folder is marked a knowledge base.</li>
<li><b>Files are the truth.</b> Marking writes nothing; a capture writes one note; Duo never generates the index or log, relinks or moves by itself.</li>
<li><b>Compatible by construction.</b> Plain Markdown, flat YAML, <code>type:</code> first, quoted links, no Duo-only keys. Read the vault’s conventions before proposing Duo’s.</li>
<li><b>Duo sets up the moment, Claude does the work, the person decides.</b> Buttons draft the instruction and never press Return. CLI login only.</li>
<li><b>A human touchpoint in every loop:</b> one batch, a proposal, then the changes, visible.</li>
<li><b>Don’t rebuild Obsidian.</b> No graph, Bases renderer or rollup engine; Obsidian stays the companion.</li>
<li><b>Instructions live where Claude Code looks:</b> a command or skill in the folder, editable by both.</li></ol>
<h3>Boards</h3><p class="note">1 the service blueprint · 2 ranked candidates · 3 marking a knowledge base · 4 the knowledge base in Duo · 5 capture · 6 process with Claude · 7 index and log · 8 search · 9 reading a vault right · 10 the v1 slice and the questions</p></div>
</div>'''))

# ---------------------------------------------------------------- 01 blueprint
BP = [
    ("0 · Set up", True, "Opens the vault in Duo; marks it a knowledge base", "Detects .obsidian/, OKF index, AGENTS.md, raw/ + wiki/, an inbox-like folder; a sheet says what it found and that it writes nothing", "—", "Nothing written; the mark kept in .duo/ (Q-130)", "Which folder is the inbox; whether to opt in at all"),
    ("1 · Capture", True, "Presses the chord anywhere, types or pastes, Return", "A small panel over any app: the knowledge base, one field; a pasted URL becomes source", "— (no AI: capture must not wait)", "One new note in the inbox from templates/new-note.md: type, title, created, source", "The words"),
    ("2 · See the inbox", True, "Glances at the tile or the project", "A count on the tile; an INBOX fold, newest first, the oldest’s age", "—", "Read only", "—"),
    ("3 · Process", True, "Clicks Process with Claude, reads the drafted instruction, presses Return", "A chat session in the knowledge base with /process-inbox or Duo’s text drafted (Q-133); Ready for review when done", "Reads the schema; proposes per note: merge, new page, task or discard; waits; then edits, moves with links updated, appends to the log", "Pages edited, notes moved out of the inbox, log.md appended", "Every decision"),
    ("4 · Ingest a source", False, "Drops a PDF or clip in raw/, or right-clicks it", "Ingest with Claude on the file’s menu drafts the instruction (ENH-42)", "Summarises, asks what to emphasise, updates 10–15 pages, the index and the log", "wiki/ pages, index.md, log.md", "The source stays as it was"),
    ("5 · Ask", True, "Asks a question", "Search opens narrowed to the knowledge base (Q-134); a chat session in it is told the schema and index", "Answers with links to pages; files a good answer back as a page when asked", "Optional new page", "Whether an answer is worth keeping"),
    ("6 · Look after it", True, "Reads the Index or Log tab; asks for a check now and then", "Index and Log as tabs (Q-132); Check with Claude drafts a lint (ENH-42); schedules are Claude Code’s (ENH-43)", "Contradictions, orphans, missing pages, broken links, stale claims; a dated report", "A report page; fixes after a yes", "What to fix"),
    ("7 · Daily note", False, "Opens today’s note, or captures into it", "Today opens or makes it from Obsidian’s Daily notes settings (ENH-40)", "Summarises the day on request", "Daily/2026-10-07.md from the vault’s template", "The journal"),
    ("8 · Rollups", False, "Wants a view across notes", "Shows what Claude wrote; renders no queries", "Writes a .base (Obsidian shows it) or a Markdown page", ".base, rollups/*.md", "Which views exist"),
]
TAG_V1, TAG_NEXT, V1CELL = '<span class="tag v1">v1</span>', '<span class="tag">next</span>', ' class="v1"'
bprows = "".join(f'<tr><th>{e(j)} {TAG_V1 if v1 else TAG_NEXT}</th>' + "".join(f'<td{V1CELL if (v1 and i == 1) else ""}>{e(c)}</td>' for i, c in enumerate(cells)) + '</tr>' for j, v1, *cells in BP)
board("01-blueprint", 1600, 1000, "1 · The journeys: a service blueprint", "Each journey across the person, Duo, Claude, the files, and what stays the person's.", bd(1600, 1000,
    "1 · The journeys, as a service blueprint",
    "Read across: what the person does, what Duo shows (front stage), what Claude does in a session, what changes on disk (back stage), and what stays the person’s call. <b>v1</b> rows are the slice (board 10); <b>next</b> rows are designed here but come later. Two moments cut across every row: <b>what Claude is told</b> when a session starts in a knowledge base (a few lines: schema, index, log, inbox and its count; never file contents), and <b>two sessions on one knowledge base</b> (C-58): when Process or Ingest starts while another session there is working, the drafted instruction says so.",
    f'<table class="bp"><colgroup><col style="width:150px"><col><col><col><col><col style="width:200px"></colgroup><tr><th>Journey</th><th>Person</th><th>Duo (front stage)</th><th>Claude (in a session)</th><th>Files (back stage)</th><th>Stays the person’s</th></tr>{bprows}</table>'))

# ---------------------------------------------------------------- 02 ranking
RK = [
    ("1", "Read vaults correctly: wikilinks drawn and followed, shortest-path links found by name, ![[image]] drawn; never written", "everyone with a vault", "High", "M", "v1, first"),
    ("2", "Don’t misread folders: tasks/ only for type: task (or no type); the tree sorts before it caps", "everyone", "High", "S", "v1"),
    ("3", "Bring a vault in: DL-147’s “A folder I have”", "everyone with a vault", "High", "M", "v1 dependency"),
    ("4", "Mark a knowledge base (detect, a sheet, writes nothing) and tell Claude where things are", "all three", "High", "S", "v1"),
    ("5", "Inbox: a count on the tile, an INBOX fold", "keeper, work brain", "High", "S", "v1"),
    ("6", "Capture chord and panel, through the templates engine (new-note.md)", "keeper, work brain", "High", "M", "v1"),
    ("7", "Process with Claude: a drafted session from the folder’s command or Duo’s text", "all three", "High", "S", "v1"),
    ("8", "Index and Log as tabs", "wiki, work brain", "Medium", "S", "v1"),
    ("9", "Search opens narrowed to the knowledge base (narrowing exists)", "all three", "Medium", "S", "v1"),
    ("10", "Today’s note from Obsidian’s Daily notes settings; capture into it", "keeper", "Medium", "M", "next · ENH-40"),
    ("11", "Ingest, Check, File this answer; a pages-changed list for a session", "wiki", "Medium", "S each", "next · ENH-42"),
    ("12", "Backlinks and unresolved links under a note", "keeper, wiki", "Medium", "M", "next · ENH-41"),
    ("13", "Scheduled checks through Claude Code’s scheduling", "wiki", "Low–med", "S", "later · ENH-43"),
    ("14", "Search for big and non-English vaults", "big vaults", "Medium", "M–L", "later · ENH-44"),
]
DROP = [("AI at capture (auto-title, auto-file)", "Capture must not wait or ask"), ("Duo generating index.md / log.md", "Shared state; two log orders; Claude or the user’s tools own them"),
        ("A graph, a Bases or Dataview renderer, a rollup engine", "Legacy’s “second product”; Obsidian is the companion"), ("Relinking on open, migrations, writing .obsidian/", "Breaks LR-26 and DL-6: never"),
        ("A separate “Brains” area", "A knowledge base is a project or Home with a mark")]
board("02-ranking", 1280, 860, "2 · Candidates, ranked", "What earns a place, what waits, what's dropped.", bd(1280, 860,
    "2 · Candidates, ranked: what earns its place",
    "Value for the three kinds of people, against effort (S days, M a week or two). Rows 1–3 help everyone and need no opt-in; rows 4–9 are behind the opt-in. Geoff’s example (an inbox folder with its own chord and a notes template) is rows 5 and 6.",
    '<div style="display:flex;gap:14px;align-items:flex-start"><table class="j" style="flex:1"><tr><th style="width:28px">#</th><th>Candidate</th><th style="width:130px">Who</th><th style="width:64px">Value</th><th style="width:56px">Effort</th><th style="width:110px">Verdict</th></tr>' +
    "".join(f'<tr><td>{a}</td><td>{e(b)}</td><td>{e(c)}</td><td>{d}</td><td>{x}</td><td><b>{e(v)}</b></td></tr>' for a, b, c, d, x, v in RK) + '</table>'
    '<div class="txt" style="width:330px;flex:none"><h3>Dropped</h3><ul>' + "".join(f'<li><b>{e(a)}.</b> <span class="t2">{e(b)}</span></li>' for a, b in DROP) + '</ul></div></div>'))

# ---------------------------------------------------------------- 03 marking a knowledge base
menu3 = f'''<div class="menu" style="width:250px"><div>Open in Finder</div><div>Copy Path</div><div class="sep"></div><div>Rename…</div><div>Move into Home…</div><div class="hi new">Use as Knowledge Base…</div><div class="sep"></div><div>Archive Project</div></div>'''
sheet3 = f'''<div class="sheet" style="width:620px"><h2>Use pricing-wiki as a knowledge base</h2>
<div class="hint" style="font-size:13px;line-height:19px">A folder of notes you keep for good. Duo gives it an inbox you can add to from anywhere, a button to have Claude process it, and its index and log beside it. <span style="text-decoration:underline">Learn more</span></div>
{fr("Found", f'<div class="found"><div><b style="font-weight:600">Obsidian vault</b><span class="t2">.obsidian/ · 412 notes</span></div><div><b style="font-weight:600">LLM wiki</b><span class="t2">raw/ 38 sources · wiki/ 126 pages</span></div><div><b style="font-weight:600">Schema</b><span class="t2">AGENTS.md</span></div></div>')}
{fr("Inbox", f'<span class="popup" style="height:24px;font-size:13px">{g("folder")} inbox/{g("chevd")}</span><span class="hint" style="margin-left:8px">12 notes. Captures go here.</span>')}
{fr("New notes", f'<span class="popup" style="height:24px;font-size:13px">templates/new-note.md · Home’s{g("chevd")}</span><span class="hint" style="margin-left:8px">Edit…</span>')}
{fr("Index", '<span class="mono" style="font-size:12px">index.md</span>')}
{fr("Log", '<span class="mono" style="font-size:12px">log.md</span>')}
{fr("Claude", '<div class="hint" style="font-size:13px;line-height:19px">Each session here is told to read <span class="mono">AGENTS.md</span>, where the index, log and inbox are, and how many notes wait.</div>')}
{fr("", '<div class="hint">Duo writes nothing in this folder. Turn it off any time from the same menu.</div>')}
<div class="btns"><span class="b">Cancel</span><span class="b def">Use as Knowledge Base</span></div></div>'''
w3 = sheet_over(900, 580, sheet3, "All projects › pricing-wiki")
sheet3b = f'''<div class="sheet" style="width:560px"><h2>New project</h2>
{fr("Start from", seg(["A new folder", "A folder I have", "From GitHub"], 1))}
{fr("Folder", '<div class="fld mono" style="font-size:12px">~/Notes/pricing-wiki</div>')}
{fr("Found", f'<div class="found"><div><b style="font-weight:600">Obsidian vault</b><span class="t2">.obsidian/ · 412 notes</span></div><div><b style="font-weight:600">LLM wiki</b><span class="t2">index.md, log.md, AGENTS.md</span></div></div>')}
{fr("", '<span class="cb"><i>' + TICK + '</i>Use as a knowledge base</span><div class="hint" style="margin-left:22px;margin-top:2px">An inbox, Process with Claude, its index and log. Inbox: <span class="mono">inbox/</span></div>')}
<div class="btns"><span class="b">Cancel</span><span class="b def">Make a Project</span></div></div>'''
w3b = sheet_over(640, 420, sheet3b)
board("03-mark", 1960, 800, "3 · Marking a knowledge base", "From a project's menu (A), or while adopting a vault (DL-147's sheet).", bd(1960, 800,
    "3 · Marking a knowledge base: an opt-in that writes nothing",
    "<b>Use as Knowledge Base…</b> on a project’s or Home’s menu (tile, title, the project’s ⋯) opens the sheet. Duo shows what it found (<code>.obsidian/</code> or a renamed config folder; an OKF <code>index.md</code>/<code>_index.md</code> with <code>okf_version</code>; <code>AGENTS.md</code> or <code>CLAUDE.md</code>; <code>raw/</code> + <code>wiki/</code>) and proposes the inbox: an existing <code>inbox/</code>, <code>Inbox/</code>, <code>+/</code>, <code>00 Inbox/</code> or <code>Clippings/</code>, else <code>inbox/</code>, made on the first capture. New notes use the templates engine’s lookup (the project’s <code>templates/new-note.md</code>, Home’s, Duo’s). <b>Nothing is written into the folder</b>; the mark is Duo’s own (Q-130). When DL-147’s “A folder I have” finds a vault or a wiki, the same choice is a checkbox there (right). <code>duo2 kb use &lt;project&gt; [--inbox &lt;folder&gt;]</code>, <code>duo2 kb off</code>, <code>duo2 kb show</code>.",
    f'<div style="display:flex;gap:24px;align-items:flex-start">{frame(menu3, 250, None, "The project menu")}{frame(w3, 900, 580, "The sheet")}{frame(w3b, 640, 420, "Or while adopting a vault (DL-147)")}</div>'))

# ---------------------------------------------------------------- 04 the knowledge base in Duo
tileKB = f'''<div class="tile" style="width:300px"><span class="nm">pricing-wiki</span><span style="display:flex;align-items:center;gap:6px">{BOOK}Knowledge base · 12 in inbox</span><span class="t2">Last change 2h ago: Acme, Pro tier now $24</span>
<div style="margin-top:6px;display:flex;flex-direction:column"><div class="srow">{g("idle")}<span class="n">Ask: annual discounts</span><span class="t2">1d</span></div></div></div>'''
tileP = tile("checkout-redesign", "Cut guest-checkout abandonment 15% by Q1", "On track · Exec review Oct 14", [("working", "Teardown research", "working")])
tileP300 = tileP.replace('class="tile"', 'class="tile" style="width:300px"')
w4 = window(1340, 640, kb_left() + console(380) + rpane(["Project", "Index", "Log", "pricing-models.md"], 1, INDEX_DOC), tb=tb_quiet("All projects › pricing-wiki"))
board("04-kb-in-duo", 1440, 1060, "4 · A knowledge base in Duo", "The tile, the INBOX fold, Process with Claude, and Index and Log tabs.", bd(1440, 1060,
    "4 · A knowledge base in Duo: the tile, the inbox, the index",
    "<b>The tile</b> (left) says what kind of folder it is and what waits: the book mark, <b>Knowledge base · 12 in inbox</b>, then the log’s newest entry with its age, where a project shows its goal and health. A project beside it is unchanged. <b>Inside</b>: an <b>INBOX · n</b> fold above the sessions lists the inbox’s notes newest first with their age (6, then “n more · oldest 9 days”); a click opens the note in the right pane; <b>+</b> captures; <b>Process with Claude</b> is in the fold’s header (board 6). <b>Index</b> and <b>Log</b> are tabs beside Project when the files exist (board 7). Everything else is a project as today. No count turns orange: an inbox is not something that needs you.",
    f'<div style="display:flex;gap:24px;align-items:flex-start">{frame(tileKB, 300, None, "Its tile")}{frame(tileP300, 300, None, "A project, unchanged")}</div>' +
    frame(w4, 1340, 640, "Inside, with the Index tab")))

# ---------------------------------------------------------------- 05 capture
note_preview = ('<span class="k">---</span>\n<span class="k">type:</span> note\n<span class="k">title:</span> "Pricing sync: annual discount test starts Nov 3"\n<span class="k">created:</span> 2026-10-07\n'
                '<span class="k">source:</span> "https://notion.so/acme/pricing-sync"\n<span class="k">---</span>\n\n# Pricing sync: annual discount test starts Nov 3\n\nAna says finance signed off on 20%.\nhttps://notion.so/acme/pricing-sync')
panel = f'''<div class="panel" style="left:290px;top:120px;width:560px;padding:14px 16px 12px;gap:10px">
<div style="display:flex;align-items:center;gap:8px;white-space:nowrap"><span style="font-weight:600">Capture to</span><span class="popup" style="height:24px;font-size:13px">{BOOK}&nbsp;pricing-wiki{g("chevd")}</span><span class="t2 mono" style="font-size:12px">› inbox/</span><span style="margin-left:auto" class="kbd">⌃⌥⌘N</span></div>
<div class="ta">Pricing sync: annual discount test starts Nov 3<br>Ana says finance signed off on 20%.<br><span class="t2">https://notion.so/acme/pricing-sync</span><span class="caret"></span></div>
<div style="display:flex;align-items:center;gap:8px;white-space:nowrap"><span class="chip">{g("jump")}source: notion.so/acme/pricing-sync</span><span style="flex:1"></span><span class="kbd"><b>↩</b> Save · <b>⌘↩</b> Save and Open · <b>esc</b></span></div></div>'''
appwin = f'<div style="position:absolute;left:60px;top:50px;width:700px;height:420px;background:#fff;border-radius:10px;box-shadow:0 10px 30px rgba(0,0,0,.25);opacity:.85"><div style="height:30px;background:{GROUND};border-radius:10px 10px 0 0;border-bottom:1px solid {RULE};display:flex;align-items:center;padding:0 12px;gap:6px"><i style="width:11px;height:11px;border-radius:50%;background:#FF5F57;display:block"></i><i style="width:11px;height:11px;border-radius:50%;background:#FEBC2E;display:block"></i><i style="width:11px;height:11px;border-radius:50%;background:#28C840;display:block"></i><span class="t2" style="margin-left:10px;font-size:12px">Another app</span></div></div>'
desk = f'<div class="desk" style="width:1140px;height:540px">{appwin}{panel}<div class="panel" style="left:600px;top:420px;width:400px;padding:8px 12px;flex-direction:row;align-items:center;gap:8px;font-size:12px;line-height:16px;white-space:nowrap">{CHECK}<span>Saved to pricing-wiki/inbox/</span><span class="t2">· Open · Undo</span></div></div>'
sheet5 = f'''<div class="sheet" style="width:400px"><h2>Capture</h2>
<div class="ta" style="min-height:70px">Pricing sync: annual discount test starts Nov 3<span class="caret"></span></div>
<div class="btns"><span class="t2" style="margin-right:auto">To pricing-wiki › inbox/</span><span class="b">Cancel</span><span class="b def">Save</span></div></div>'''
w5b = sheet_over(450, 260, sheet5, "pricing-wiki")
board("05-capture", 1680, 1000, "5 · Capture: one chord, no decisions", "A: a global panel over any app; B: a sheet in Duo only; the file it writes.", bd(1680, 1000,
    "5 · Capture: one chord from anywhere, no decisions <span class=\"rec\">A recommended</span>",
    "<b>A</b> (left): a global chord, <b>⌃⌥⌘N</b> (Q-131), registered only once a knowledge base exists, opens a small panel over whatever app is in front, ready to type (Apple Quick Note, Drafts, QuickAdd). The knowledge base is the last used; the popup switches when there are several. The first line is the title. A pasted URL becomes <code>source</code> (a chip; ⌫ on it removes it). <b>Return</b> saves and closes, ⌘Return saves and opens the note in Duo, Esc discards (asking first when there’s text). A one-line confirmation with Open and Undo shows for 4 s at the screen’s foot. No AI, no network: nothing waits. <b>B</b> (right, below): the same as a sheet inside Duo only. <b>The file</b> (right): Duo’s base note template through <code>Templates.make</code>; keys already in use by OKF (<code>type</code>, <code>title</code>), Web Clipper (<code>created</code>, <code>source</code>) and DL-146 (<code>created</code> a date); <code>source</code> only when there is one; named <code>&lt;date&gt;-&lt;slug&gt;.md</code>, <code>-2</code> on a collision. <code>duo2 capture [--kb] [--title] [--source] [--stdin | text]</code>.",
    f'''<div style="display:flex;gap:24px;align-items:flex-start">{frame(desk, 1140, 540, "A · A global panel over any app")}
<div style="display:flex;flex-direction:column;gap:24px">{frame('<div style="padding:12px 14px"><div class="hint mono" style="margin-bottom:6px">pricing-wiki/inbox/2026-10-07-pricing-sync-annual-discount-test.md</div><div class="pre" style="white-space:pre-wrap;width:420px">' + note_preview + '</div><div class="hint" style="margin-top:6px">From templates/new-note.md (the project’s, else Home’s, else Duo’s base). Obsidian’s Templates can use the same file.</div></div>', 450, None, "The note it writes")}
{frame(w5b, 450, 260, "B · A sheet inside Duo only")}</div></div>'''))

# ---------------------------------------------------------------- 06 process with Claude
INSTR = ("Process the 12 notes in inbox/. Read AGENTS.md first. For each note, propose one of: merge into an existing page (say which), "
         "a new page, a task, or discard, with the links you’d add. Show me the list and wait for my OK. Then make the changes: keep each "
         "note’s source, move processed notes out of inbox/ with links updated, update index.md, and add one entry to log.md.")


def chat_pane(w, title, composer, feed="", foot=""):
    strip = f'<div class="strip"><span class="tab on">{g("idle")}{e(title)}</span><span class="tab">+</span>{pill(True)}</div>'
    return (f'<div class="chat" style="width:{w}px;flex:none;border-right:1px solid {RULE}">{strip}'
            f'<div class="feed" style="padding:14px 18px 12px;font-size:14px;line-height:22px">{feed}</div>'
            f'<div style="flex:none;padding:0 12px 12px">{composer}{foot}</div></div>')


compA = f'<div class="composer" style="color:{TEXT}">/process-inbox<span class="caret"></span></div>'
compB = f'<div class="composer" style="color:{TEXT};font-size:13px;line-height:20px;white-space:normal">{e(INSTR)}<span class="caret"></span></div>'
footB = f'<div class="hint" style="margin-top:6px;display:flex;gap:6px">Drafted by Duo. Edit it, then press Return. <span style="text-decoration:underline">Save as Command…</span></div>'
footA = f'<div class="hint" style="margin-top:6px">This folder’s own command, <span class="mono">.claude/commands/process-inbox.md</span>. Press Return to run it.</div>'
waitA = f'<div class="who">Duo</div><div class="t2" style="font-size:13px">New session in pricing-wiki for the inbox (12 notes). Another session here is working: wait for it, or go ahead.</div>'
w6a = window(860, 560, kb_left(processing=False, sel_session=("idle", "Process inbox", "now")) + chat_pane(560, "Process inbox", compA, f'<div style="display:flex;flex-direction:column;gap:4px">{waitA}</div>', footA), tb=tb_quiet("All projects › pricing-wiki"))
w6b = window(860, 560, kb_left(processing=False, sel_session=("idle", "Process inbox", "now")) + chat_pane(560, "Process inbox", compB, "", footB), tb=tb_quiet("All projects › pricing-wiki"))
prop = f'''<div style="align-self:flex-end;display:flex;flex-direction:column;align-items:flex-end;gap:4px;max-width:80%"><div class="who">You</div><div class="you">/process-inbox</div></div>
<div style="margin-right:24px;display:flex;flex-direction:column;gap:4px"><div class="who">Claude</div><div class="ccard" style="font-size:13px;line-height:20px">
<div class="trail"><div class="step"><span class="dot"></span><span><b>Read</b> AGENTS.md, index.md and 12 notes</span><span style="margin-left:auto">›</span></div></div>
<div>Here’s what I’d do with the 12 notes:</div>
<table class="j" style="font-size:12px"><tr><th>Note</th><th>Proposal</th></tr><tr><td>Pricing sync: annual discount…</td><td>Merge into <span class="lk">Annual discount</span>; it contradicts the 16% line</td></tr><tr><td>Competitor raised Pro tier…</td><td>Update <span class="lk">Acme</span></td></tr><tr><td>Idea: usage-based add-on</td><td>New page <span class="lk">Usage-based pricing</span></td></tr><tr><td>Call notes, Ana</td><td>Task: confirm the test dates</td></tr><tr><td colspan="2" class="t2">8 more…</td></tr></table></div></div>'''
ask6 = f'''<div class="ask" style="margin:0 12px 12px"><div style="display:flex;gap:6px"><span class="lbl" style="color:{NEEDS}">NEEDS YOU</span><span class="lbl t2">· QUESTION</span></div>
<div style="font-weight:600;font-size:13px;line-height:20px">Go ahead with these 12?</div>
<div class="opt"><span class="key">1</span><span>Yes, all of them</span></div><div class="opt"><span class="key">2</span><span>Yes, but skip the discards</span></div><div class="opt"><span class="key">3</span><span>Type something else</span></div></div>'''
strip6 = f'<div class="strip"><span class="tab on">{g("needs")}Process inbox</span><span class="tab">+</span>{pill(True)}</div>'
w6c = f'<div class="w" style="width:560px;height:560px"><div class="chat" style="height:100%">{strip6}<div class="feed" style="padding:14px 18px 12px">{prop}</div>{ask6}</div></div>'
board("06-process", 1680, 1640, "6 · Process with Claude", "A: the folder's own command; B: Duo's drafted instruction with Save as Command; then Claude proposes and waits.", bd(1680, 1640,
    "6 · Process with Claude: Duo drafts, the person says go, Claude proposes, the person decides <span class=\"rec\">A recommended</span>",
    "<b>Process with Claude</b> (the INBOX fold’s header, the tile’s menu, <code>duo2 inbox process</code>) starts a chat session in the knowledge base, named Process inbox, and drafts the instruction without sending it (DL-112’s rule). <b>A</b>: when the folder has its own command or skill, <code>.claude/commands/process-inbox.md</code> (Claude Code’s folder, invisible to Obsidian), Duo drafts <code>/process-inbox</code>. <b>B</b>: otherwise Duo drafts its own text, editable in place, with <b>Save as Command…</b>, which writes that file so the person and Claude can improve it (Q-133). The fold says “Claude is processing” while it runs. If another session in the knowledge base is working, a line says so first (C-58: index.md and log.md are shared). <b>Then</b> (right): Claude reads the schema and the notes, proposes a disposition per note and waits; the person answers in chat. Nothing moves until they do.",
    f'<div style="display:flex;gap:24px;align-items:flex-start">{frame(w6a, 860, 560, "A · The folder’s own command, drafted")}{frame(w6c, 560, 560, "Then: Claude proposes and waits")}</div>' +
    frame(w6b, 860, 560, "B · No command yet: Duo’s instruction, drafted, with Save as Command…")))

# ---------------------------------------------------------------- 07 index and log
w7a = rpane(["Project", "Index", "Log"], 2, LOG_DOC.replace('<h1>Log</h1>', '<h1>Log</h1><p class="t2" style="font-size:13px">Newest first, as OKF writes it. A log written oldest first (Karpathy’s) opens scrolled to its end.</p>'))
summ = f'''<div class="doc" style="gap:12px"><h1>pricing-wiki</h1>
<div class="card" style="gap:6px"><div class="top"><span style="font-weight:600">Inbox · 12</span><span class="t2">oldest 9 days</span><span class="sb" style="margin-left:auto">Process with Claude</span></div></div>
<div class="card" style="gap:4px"><div class="top"><span style="font-weight:600">Latest in the log</span><span class="t2" style="margin-left:auto">Open log.md</span></div>
<span style="font-size:13px">Today · Update: Acme, Pro tier now $24</span><span style="font-size:13px">Today · Creation: Usage-based pricing</span><span style="font-size:13px">Oct 4 · Ingest: Q3 win/loss interviews</span></div>
<div class="card" style="gap:4px"><div class="top"><span style="font-weight:600">Index</span><span class="t2">126 pages in 3 sections</span><span class="t2" style="margin-left:auto">Open index.md</span></div></div></div>'''
w7b = rpane(["Project", "Knowledge base"], 1, summ)
board("07-index-log", 1280, 820, "7 · Index and log", "A: tabs beside Project; B: one Knowledge base summary tab.", bd(1280, 820,
    "7 · The wiki’s own index and log, one click away <span class=\"rec\">A recommended</span>",
    "Duo never writes these files; it shows them. <b>A</b>: <b>Index</b> and <b>Log</b> tabs beside Project (DL-60), each the file itself in the editor, shown only when the file exists (<code>index.md</code>, <code>_index.md</code>, <code>wiki/index.md</code>; <code>log.md</code>, <code>_log.md</code>). The Log tab opens at the newest entry whichever order the file uses. <b>B</b>: one Knowledge base tab with the inbox, the latest log entries and the index’s size, each linking to the file (Q-132). A is cheaper and is the files; B is a summary Duo has to compute.",
    f'<div style="display:flex;gap:24px;align-items:flex-start">{frame(w7a, 560, 560, "A · Tabs: the Log tab")}{frame(w7b, 560, 560, "B · One Knowledge base tab")}</div>'))

# ---------------------------------------------------------------- 08 search
res = [("wiki/annual-discount.md", "today", "pricing-wiki · file · L12–20", "…the current annual discount is 16%; finance agreed to test 20% from Nov 3…"),
       ("inbox/2026-10-07-pricing-sync-annual-discount-test.md", "2h", "pricing-wiki · file · by meaning", "Ana says finance signed off on 20%."),
       ("Ask: what do we know about annual discounts?", "1d", "pricing-wiki · session · turn 3", "Claude: From the index, three pages mention it…")]
rr = "".join(f'<div style="padding:8px 14px;border-bottom:1px solid {RULE}"><div style="display:flex;gap:8px;align-items:center">{NOTE if "session" not in c else g("idle")}<span style="font-weight:600" class="ell">{e(t)}</span><span class="t2" style="margin-left:auto">{tm}</span></div><div class="t2" style="font-size:12px;line-height:16px;padding-left:18px">{e(c)}</div><div style="font-size:12px;line-height:17px;padding-left:18px">{e(s)}</div></div>' for t, tm, c, s in res)
modal = f'''<div style="width:760px;background:{PANE};border:1px solid {RULE};border-radius:12px;box-shadow:0 18px 50px rgba(31,35,40,.28);overflow:hidden;white-space:nowrap">
<div style="height:52px;display:flex;align-items:center;gap:10px;padding:0 16px;border-bottom:1px solid {RULE}">{g("search")}<span style="font-size:17px;line-height:24px">annual discount</span><span style="margin-left:auto">{seg(["Search ⇧⌘A", "Jump ⌘K"], 0)}</span></div>
<div style="display:flex;align-items:center;gap:8px;padding:8px 14px;border-bottom:1px solid {RULE}"><span class="popup" style="background:{SELECTED};font-weight:600">{BOOK}pricing-wiki{g("chevd")}</span><span class="popup">Any kind{g("chevd")}</span><span class="popup">Any time{g("chevd")}</span><span class="t2" style="margin-left:auto;font-size:12px">⇧⌘A again: all projects</span></div>
{rr}<div style="padding:8px 14px;color:{TEXT2}">{g("chev")} 2 more in other projects</div></div>'''
w8 = f'<div class="w" style="width:1000px;height:520px;background:rgba(31,35,40,.30);align-items:center;padding-top:40px">{modal}</div>'
board("08-search", 1280, 760, "8 · Search, narrowed to the knowledge base", "Opening search inside a knowledge base starts narrowed to it.", bd(1280, 760,
    "8 · Search inside a knowledge base starts narrowed to it <span class=\"rec\">A recommended</span>",
    "Narrowing is built: ⇧⌘A pressed again inside a project narrows to it (DL-79, search handoff <code>search-project-narrowed</code>), with “n more in other projects” to widen. <b>A</b>: inside a knowledge base, ⇧⌘A <b>opens narrowed</b> (the scope popup filled with the book mark), and ⇧⌘A again widens to all projects; everywhere else nothing changes. <b>B</b>: keep today’s behaviour (open across all projects with this project first) (Q-134). Results are the same hybrid search by meaning and words, over the notes and this folder’s sessions. Asking in plain words is a chat session in the knowledge base, told to read the schema and the index first (board 10).",
    frame(w8, 1000, 520, "A · Opened inside pricing-wiki")))

# ---------------------------------------------------------------- 09 reading a vault right
doc9 = f'''<div class="doc"><h1>Annual discount</h1>
<p>We offer 16% off annual plans. Finance agreed to test 20% from Nov 3 (see <span class="lk">Pricing sync</span>).</p>
<p>Related: <span class="lk">Value metric</span> · <span class="lk">Acme</span> · <span class="unres">Discount elasticity</span></p>
<p style="position:relative;margin-top:44px">Source: <span class="br">[[</span><span class="lk">raw/2026-09-30-win-loss</span><span class="br">|</span>Q3 win/loss<span class="br">]]</span> <span class="t2" style="font-size:12px">← the line with the cursor shows the brackets</span></p>
<div style="width:300px;height:120px;border-radius:6px;background:linear-gradient(135deg,#E6E9ED,#CDD3DA);display:flex;align-items:center;justify-content:center;color:{TEXT2};font-size:12px">![[discount-curve.png]] drawn</div></div>'''
tip1 = f'<div class="tip" style="position:absolute;left:56px;top:144px">{NOTE} wiki/value-metric.md · ⌘-click opens</div>'
tip2 = f'<div class="tip" style="position:absolute;left:318px;top:144px">No page yet · <b style="font-weight:600">Make discount-elasticity.md</b></div>'
w9 = f'<div class="w" style="width:860px;height:440px;position:relative">{rpane(["Project", "annual-discount.md"], 1, doc9)}{tip1}{tip2}</div>'
board("09-reading-a-vault", 1280, 760, "9 · Reading a vault right (for everyone)", "Wikilinks drawn and followed, shortest-path links found, embeds drawn; nothing written.", bd(1280, 760,
    "9 · First, read a vault right: links that work (no opt-in, for everyone)",
    "Today <code>[[Note]]</code> is plain text and a link to a note in another folder says “isn’t there” (F-202). Proposed: <b>wikilinks</b> (<code>[[Note]]</code>, <code>[[Note|text]]</code>, <code>[[Note#Heading]]</code>) look like Duo’s other links, brackets hidden except on the line being edited, as markdown links are; they resolve by file name across the project, the nearest match first, and a click (⌘-click while editing) opens the note. A link to a note that doesn’t exist is <b>dashed, in <code>text2</code></b>; hovering offers <b>Make &lt;name&gt;.md</b> (made from <code>new-note.md</code>, beside the note). Markdown links in Obsidian’s “shortest path” form resolve by name the same way. <code>![[image.png]]</code> is drawn. Duo still never writes a wikilink (DL-17) and never converts one. Also for everyone: a note in <code>tasks/</code> is a task only with <code>type: task</code> or no <code>type</code> (F-203), and the file tree sorts before it caps (F-204).",
    frame(w9, 860, 440, "A wiki page in the editor")))

# ---------------------------------------------------------------- 10 the v1 slice and the questions
board("10-slice", 1280, 900, "10 · The v1 slice, what Claude is told, the questions", "The slice, the context lines, the duo2 verbs, and Q-129 to Q-134.", bd(1280, 900,
    "10 · The v1 slice, what Claude is told, and the questions",
    "The slice in order. Rows 1–2 help everyone; the rest stay hidden until a folder is marked a knowledge base. Each needs its boards approved and exported before it’s built.",
    f'''<div style="display:flex;gap:14px;align-items:flex-start">
<div class="txt" style="flex:1"><h3>The slice</h3><ol>
<li><b>Links</b> (board 9): wikilinks drawn and followed, shortest-path links, embeds. F-202.</li>
<li><b>Folders</b>: <code>tasks/</code> by <code>type</code>; the tree sorts before it caps. F-203, F-204. With DL-147’s adopt flow.</li>
<li><b>Mark a knowledge base</b> (board 3).</li>
<li><b>The tile and the INBOX fold</b> (board 4).</li>
<li><b>Capture</b> (board 5): the chord, the panel, <code>templates/new-note.md</code> as a third template kind.</li>
<li><b>Process with Claude</b> (board 6).</li>
<li><b>Index and Log tabs</b> (board 7).</li>
<li><b>Search opens narrowed</b> (board 8).</li></ol>
<h3>What a session in a knowledge base is told</h3>
<div class="pre" style="white-space:pre-wrap">This folder is a knowledge base. Read AGENTS.md before changing pages.
index.md lists the pages; log.md records changes, newest first.
The inbox is inbox/ (12 notes, oldest 9 days).</div>
<p class="note">Said once at start and again only when something changes, as DL-116 does for tasks. Paths and counts, never contents.</p>
<h3>duo2 (DL-71)</h3><p class="mono" style="font-size:12px;line-height:18px">duo2 kb use|off|show &lt;project&gt; [--inbox &lt;folder&gt;]<br>duo2 capture [--kb &lt;p&gt;] [--title …] [--source &lt;url&gt;] [--stdin | text]<br>duo2 inbox [&lt;kb&gt;] · duo2 inbox process [&lt;kb&gt;]<br>duo2 kb index|log [&lt;kb&gt;]</p></div>
<div class="txt" style="width:520px;flex:none"><h3>Questions for Geoff</h3><ol>
<li><b>Q-129, what is a knowledge base?</b> A: any project or Home, marked <span class="rec">rec</span>. B: Home only. C: a separate kind with its own place.</li>
<li><b>Q-130, where does the mark live?</b> A: Duo’s <code>.duo/</code>, nothing in the notes <span class="rec">rec</span>. B: a key in the brief, like <code>project_brief</code>. C: a line in CLAUDE.md.</li>
<li><b>Q-131, the chord.</b> A: global ⌃⌥⌘N, only once a knowledge base exists <span class="rec">rec</span>. B: in Duo only. C: global, keys chosen in Settings first.</li>
<li><b>Q-132, index and log.</b> A: tabs <span class="rec">rec</span>. B: one Knowledge base tab. C: nothing special.</li>
<li><b>Q-133, the instruction.</b> A: the folder’s command, else Duo’s with Save as Command… <span class="rec">rec</span>. B: Duo’s only, edited in Settings. C: always a command, written on first use.</li>
<li><b>Q-134, search.</b> A: opens narrowed inside a knowledge base <span class="rec">rec</span>. B: as today.</li></ol>
<h3>Later</h3><p class="note">ENH-40 Today’s note · ENH-41 backlinks · ENH-42 Ingest, Check, File this answer, changed pages · ENH-43 scheduled checks · ENH-44 big and non-English vaults. Concerns: C-57 other tools writing the same folders; C-58 parallel sessions and index/log.</p></div>
</div>'''))

json.dump(BOARDS, open(os.path.join(OUT, "manifest.json"), "w"), indent=1)
print(len(BOARDS), "boards")
