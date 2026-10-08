# Boards 11 to 14: the slice as Geoff decided it (DL-152). Run by make.py, after boards 0 to 10.

def setrow(title, sub, btns):
    b = "".join(f'<span class="b" style="height:22px;font-size:12px">{x}</span>' for x in btns)
    return (f'<div style="display:flex;align-items:center;gap:12px;padding:10px 16px"><div style="display:flex;flex-direction:column;flex:1;min-width:0;white-space:normal">'
            f'<span>{title}</span><span style="font-size:12px;line-height:16px;color:{TEXT2}">{sub}</span></div>{b}</div>')


HR = f'<div style="height:1px;margin:0 16px;background:{RULE}"></div>'
MONO = "style=\"font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:11px\""
CARD = f"display:flex;flex-direction:column;background:{PANE};border:1px solid {RULE};border-radius:6px"

# ---------------------------------------------------------------- 11 settings
settings = (f'<div style="width:620px;display:flex;flex-direction:column;gap:14px;padding:22px 26px;background:{GROUND};white-space:normal">'
            f'<div style="{CARD}"><div class="lane" style="padding:12px 16px 4px">TEMPLATES</div>'
            + setrow("New projects", "Duo’s base template", ["Edit…"]) + HR
            + setrow("New tasks", "Yours, in Home’s templates folder", ["Edit…"]) + HR
            + setrow("New notes in an inbox", "Duo’s base template", ["Edit…"]) + '</div>'
            f'<div style="{CARD}"><div class="lane" style="padding:12px 16px 4px;display:flex;gap:8px;align-items:center">KNOWLEDGE BASES <span class="tag">ALPHA</span></div>'
            f'<div style="padding:0 16px 8px;font-size:12px;line-height:16px;color:{TEXT2}">A project you keep notes in for good, like an Obsidian vault or an LLM wiki. Duo writes nothing in it.</div>'
            + setrow('<b style="font-weight:600">pricing-wiki</b> <span class="t2">· default</span>',
                     f'Inbox <span {MONO}>inbox/</span> · Index <span {MONO}>index.md</span> · Log <span {MONO}>log.md</span> · Schema <span {MONO}>AGENTS.md</span> · tab shown',
                     ["Edit…", "Remove"]) + HR
            + setrow('<b style="font-weight:600">★ home</b>', f'Inbox <span {MONO}>Inbox/</span> · no index or log · no tab', ["Edit…", "Remove"])
            + f'<div style="padding:6px 16px 12px;display:flex;gap:8px;align-items:center"><span class="b" style="height:22px;font-size:12px">Add a Knowledge Base…</span>'
              f'<span style="font-size:12px;line-height:16px;color:{TEXT2}">⇧⌘N makes a note in the inbox of the one you’re in, else the default’s.</span></div></div></div>')
found11 = ('<div class="found"><div><b style="font-weight:600">Obsidian vault</b><span class="t2">.obsidian/ · 412 notes</span></div>'
           '<div><b style="font-weight:600">LLM wiki</b><span class="t2">index.md · log.md · AGENTS.md</span></div></div>')
edit = ('<div class="sheet" style="width:540px"><h2>Knowledge base</h2>'
        + fr("Project", f'<span class="popup" style="height:24px;font-size:13px">pricing-wiki{g("chevd")}</span>')
        + fr("Found", found11)
        + fr("Inbox", f'<span class="popup" style="height:24px;font-size:13px">{g("folder")} inbox/{g("chevd")}</span><span class="hint" style="margin-left:8px">12 notes</span>')
        + fr("", '<span class="cb"><i>' + TICK + '</i>Show a Knowledge base tab in the project</span>')
        + fr("", '<span class="cb"><i>' + TICK + '</i>Default for ⇧⌘N outside a knowledge base</span>')
        + fr("Claude", '<div class="hint" style="font-size:13px;line-height:19px">Sessions here are told where the inbox, index, log and schema are. Your own skills do the rest.</div>')
        + '<div class="btns"><span class="b">Cancel</span><span class="b def">Save</span></div></div>')
SETWIN = (f'<div class="w" style="width:700px;height:520px"><div class="tb" style="justify-content:center;position:relative"><span class="tl" style="position:absolute;left:20px"><i style="background:#FF5F57"></i><i style="background:#FEBC2E"></i><i style="background:#28C840"></i></span><span style="font-weight:600">Settings</span></div>'
          f'<div class="sheetwrap">{edit}</div></div>')
board("11-settings", 1440, 760, "11 · Settings › Knowledge bases (alpha)", "Geoff: an alpha power-user feature, set up in Settings; discoverability later.", bd(1440, 760,
    "11 · Set up in Settings: Knowledge bases, alpha (DL-152)",
    "Geoff: “this is like an alpha power user feature”, so it lives in <b>Settings</b> for now, with no menus or prompts elsewhere; ways to discover it come later. A <b>KNOWLEDGE BASES · ALPHA</b> section after Templates lists each with its inbox, index, log and schema. <b>Add a Knowledge Base…</b> and <b>Edit…</b> open the sheet (right): the project (any project, or Home), what Duo found, the inbox (detected: <code>inbox/</code>, <code>Inbox/</code>, <code>+/</code>, <code>00 Inbox/</code>, <code>Clippings/</code>; else <code>inbox/</code>, made with the first note), whether the project shows a <b>Knowledge base tab</b>, and which is the default for ⇧⌘N. Templates gains <b>New notes in an inbox</b> (<code>templates/new-note.md</code>). Duo keeps all of it in its own state (Q-130 A); nothing is written in the folder. <code>duo2 kb add|edit|remove|list</code>.",
    f'<div style="display:flex;gap:24px;align-items:flex-start">{frame(settings, 620, None, "Settings")}{frame(SETWIN, 700, 520, "Add or Edit a knowledge base")}</div>'))

# ---------------------------------------------------------------- 12 new note
newnote = ('<div class="doc" style="gap:4px">'
           f'<div style="font-family:ui-monospace,\'SF Mono\',Menlo,monospace;font-size:12px;line-height:19px;color:{TEXT2};background:{GROUND};border-radius:6px;padding:6px 10px;margin-bottom:8px">type: note<br>created: 2026-10-07</div>'
           '<h1 style="display:flex;align-items:center"><span class="caret" style="height:24px"></span><span class="t2" style="font-weight:400;margin-left:2px">Title</span></h1>'
           '<p class="t2" style="font-size:13px">Write; it’s saved as you go. Esc or ⌘W on an empty note discards it.</p></div>')
menuF = ('<div class="menu" style="width:300px"><div>New Claude Session<span style="margin-left:auto" class="t2">⌘T</span></div>'
         '<div>New Markdown File<span style="margin-left:auto" class="t2">⌘N</span></div><div class="hi new">New Note in Inbox<span style="margin-left:auto">⇧⌘N</span></div>'
         '<div>New Folder<span style="margin-left:auto" class="t2">⌥⇧⌘N</span></div><div>New from Template ▸</div><div class="sep"></div>'
         '<div>New Window<span style="margin-left:auto" class="t2">⌥⌘N</span></div></div>')


def left_kb(sel=True):
    hi = f"background:{SELECTED};border-radius:4px;" if sel else ""
    return (f'<div class="left"><div style="padding:12px 16px 6px"><div style="font-weight:600">pricing-wiki</div><div class="t2">Pricing knowledge base</div></div>'
            f'{sec("This week")}<div class="row">{g("idle")}<span class="ti">Ask: annual discounts</span><span class="tm">1d</span></div>'
            f'<div class="row">{g("idle")}<span class="ti">Ingest: Q3 win/loss</span><span class="tm">3d</span></div><div style="flex:1"></div>'
            f'<div style="border-top:1px solid {RULE};padding:8px 16px 10px"><div class="sl">FILES</div><div class="mono t2" style="margin-top:4px">inbox/</div>'
            f'<div class="mono" style="padding-left:14px;{hi}">2026-10-07-1432.md</div><div class="mono t2" style="padding-left:14px">2026-10-07-0910.md</div>'
            f'<div class="mono t2">raw/ · wiki/ · index.md · log.md</div></div></div>')


w13 = window(1140, 560, left_kb() + console(340) + rpane(["Knowledge base", "2026-10-07-1432.md"], 1, newnote), tb=tb_quiet("All projects › pricing-wiki"))
tpl13 = '<span class="k">---</span>\n<span class="k">type:</span> note\n<span class="k">created:</span> "&#123;&#123;date&#125;&#125;"\n<span class="k">---</span>\n\n# '
board("12-new-note", 1640, 900, "12 · ⇧⌘N: a new note in the inbox, in the editor", "Geoff: a new note in the existing right-pane editor, not a modal; ⇧⌘N, New Folder to ⌥⇧⌘N.", bd(1640, 900,
    "12 · ⇧⌘N makes a note in the inbox and opens it in the editor (DL-152)",
    "Geoff: “this should be a new note in the existing right pane markdown editor, not some new modal”, on <b>⇧⌘N</b>, in Duo only for now. <b>New Note in Inbox ⇧⌘N</b> (File menu and the right pane’s +; there only once a knowledge base exists) makes <code>&lt;inbox&gt;/YYYY-MM-DD-HHmm.md</code> (<code>-2</code> on a collision; a time-stamped name, as Obsidian’s Unique note creator makes) from <code>templates/new-note.md</code> through the templates engine, and opens it in the right pane with the cursor on its heading. The inbox is the knowledge base you’re in, else the default one. Typing is saved as you go; Esc or ⌘W on a note still empty deletes it. <b>New Folder moves to ⌥⇧⌘N</b> (legacy Duo’s mapping). The file name never changes after (format doc §4.5); the heading is the title. Duo’s base template is two keys: <code>type: note</code> (OKF’s one required key) and <code>created</code> (a date, as DL-146 and Web Clipper write it). <code>duo2 note new [--kb &lt;p&gt;] [--stdin]</code>.",
    f'<div style="display:flex;gap:24px;align-items:flex-start"><div style="display:flex;flex-direction:column;gap:24px">{frame(menuF, 300, None, "File")}'
    f'{frame("<div class=pre style=border:none>" + tpl13 + "</div>", 300, None, "templates/new-note.md, Duo’s base")}</div>{frame(w13, 1140, 560, "Right after ⇧⌘N")}</div>'))

# ---------------------------------------------------------------- 13 the tab
NL = "font-weight:400;letter-spacing:0;text-transform:none"
inbox_rows = "".join(f'<div class="irow" style="margin:0;padding:0 4px">{NOTE}<span class="ti" style="font-size:13px">{e(t)}</span><span class="t2" style="font-size:12px">{tm}</span></div>' for t, tm in INBOX)
kbtab = (f'<div class="doc" style="gap:14px">'
         f'<div><div class="lane" style="display:flex;gap:8px">INBOX · 12 <span style="{NL}">oldest 9 days</span><span style="margin-left:auto;{NL}">⇧⌘N new note</span></div>'
         f'<div style="margin-top:6px;display:flex;flex-direction:column">{inbox_rows}<span class="t2" style="font-size:12px;padding:2px 4px">6 more</span></div></div>'
         f'<div><div class="lane" style="display:flex">LATEST IN THE LOG<span style="margin-left:auto;{NL}">Open log.md</span></div>'
         '<div style="margin-top:6px;font-size:13px;line-height:22px">Today · <b>Update</b>: Acme, Pro tier now $24<br>Today · <b>Creation</b>: Usage-based pricing<br>Oct 4 · <b>Ingest</b>: Q3 win/loss interviews, 14 pages</div></div>'
         f'<div><div class="lane" style="display:flex">INDEX<span style="margin-left:auto;{NL}">Open index.md</span></div>'
         '<div style="margin-top:6px;font-size:13px">126 pages in 3 sections: Concepts, Competitors, Sources</div></div>'
         '<div class="note">Read only. Claude and your own skills keep these files; Duo shows them.</div></div>')
w14 = window(1140, 600, left_kb(False) + console(340) + rpane(["Project", "Knowledge base"], 1, kbtab), tb=tb_quiet("All projects › pricing-wiki"))
board("13-kb-tab", 1240, 820, "13 · The Knowledge base tab, when added", "Geoff: one KB tab, only shown if manually added.", bd(1240, 820,
    "13 · The Knowledge base tab, only where it was added (DL-152)",
    "Geoff: “one kb tab, but only shown if manually added”. With <b>Show a Knowledge base tab</b> ticked in Settings, the project’s right pane gets a <b>Knowledge base</b> tab beside Project. It reads, never writes: the <b>inbox</b>, newest first with ages (a click opens the note; ⇧⌘N adds one), the <b>latest entries in the log</b> whichever order the file keeps (OKF newest first, Karpathy oldest first), and the <b>index</b>’s size with a link. No Process button: people run their own skills (Q-133). Without an index or log those parts are left out. Nothing else in the project changes: no tile count, no new fold, search as today (Q-134).",
    frame(w14, 1140, 600, "pricing-wiki with its tab")))

# ---------------------------------------------------------------- 14 the decided slice
board("14-decided", 1280, 900, "14 · The v1 slice, as decided", "DL-152: what's in, what's out, what Claude is told.", bd(1280, 900,
    "14 · The v1 slice, as Geoff decided it (DL-152)",
    "An alpha power-user feature: set up in Settings, invisible to everyone else, writing nothing in the folder but the notes people make. Boards 3 to 8 were the options; boards 11 to 13 are the slice.",
    """<div style="display:flex;gap:14px;align-items:flex-start">
<div class="txt" style="flex:1"><h3>In v1</h3><ol>
<li><b>Read a vault right, for everyone</b> (board 9): wikilinks drawn and followed, shortest-path links, embeds; <code>tasks/</code> by <code>type</code>; the tree sorts before it caps. F-202 to F-204. With DL-147’s adopt flow.</li>
<li><b>Settings › Knowledge bases (alpha)</b> (board 11): any project or Home (Q-129 A); kept in Duo’s own state, nothing in the folder (Q-130 A).</li>
<li><b>⇧⌘N, New Note in Inbox</b> (board 12): a note from <code>templates/new-note.md</code> opened in the right-pane editor; in Duo only; <b>New Folder moves to ⌥⇧⌘N</b> (Q-131).</li>
<li><b>The Knowledge base tab</b>, only where added (board 13; Q-132).</li>
<li><b>What Claude is told</b> in a knowledge base: where the inbox, index, log and schema are, and the inbox’s count; said once and on change.</li></ol>
<div class="pre" style="white-space:pre-wrap;margin-top:6px">This folder is a knowledge base. Its schema is AGENTS.md.
index.md lists the pages; log.md records changes.
The inbox is inbox/ (12 notes, oldest 9 days).</div></div>
<div class="txt" style="width:470px;flex:none"><h3>Not in v1</h3><ul>
<li><b>Process with Claude</b> and any Duo-written instruction (Q-133): “the user will define their own skills for maintaining the wiki and we don’t want to limit their ability to do this.” A button that runs a skill the person names is part of ENH-42.</li>
<li><b>Search narrowed by default</b> (Q-134): as today; ⇧⌘A again narrows.</li>
<li><b>A system-wide capture hotkey</b>: in Duo only for now (ENH-43).</li>
<li><b>Menus, a tile count, an INBOX fold, prompts on adopting a vault</b>: discoverability comes after the alpha (ENH-43).</li>
<li>Today’s note (ENH-40), backlinks (ENH-41), more actions and schedules (ENH-42), search scale (ENH-44).</li></ul>
<h3>duo2 (DL-71)</h3><p class="mono" style="font-size:12px;line-height:18px">duo2 kb add|edit|remove|list<br>duo2 note new [--kb &lt;p&gt;] [--stdin]<br>duo2 kb show [&lt;p&gt;]</p></div></div>"""))
