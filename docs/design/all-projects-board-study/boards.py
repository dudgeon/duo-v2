# The boards, run by make_boards.py (which defines tile, grid, lab, window, ann, note, board, P …).
IMG1900 = "/_blob/e2f15e1c2a569e7a57aea1b956910de9"
IMG1440 = "/_blob/f932d7d905f13cd0e8b59e0053159a45"

def prow(key, hov=False, pin=False):
    p = P[key]
    name = ("★ " if p["star"] else "") + p["name"]
    kinds = [s[0] for s in p["sessions"]]
    g = glyph("dot") if "dot" in kinds else glyph("dia") if "dia" in kinds else glyph("bub") if kinds else '<span class="g"></span>'
    status = p["health"]
    if kinds and not p.get("last"):
        p = dict(p, last="now")
    plus = ('<button type="button" class="plus" style="color:#1F2328" title="New session in ' + E(p["name"]) + '">+ New session</button>' if hov
            else '<button type="button" class="plus" aria-label="New session in ' + E(p["name"]) + '">+</button>')
    bg = ' style="background:#E9ECEF"' if hov else ""
    last = p.get("last", "")
    return (f'<div class="prow"{bg}>{g}<span class="tn" style="font-weight:{600 if pin else 500}">{E(name)}</span>'
            f'<span class="pp">{E(p["path"])}</span><span class="mut" style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{E(status)}</span>'
            f'<span class="w">{E(last)}</span>{plus}</div>')

# ---- 00 Main -----------------------------------------------------------------------------------
main = f'''
<div style="padding:40px 48px;display:flex;flex-direction:column;gap:18px;height:100%;box-sizing:border-box">
<div class="h1">All projects' Board: organise by what's happening, not by Home</div>
<div class="txt mut" style="max-width:1200px">Geoff, 2026-11-13: the Board wastes space (a tall stack under Home, white space to the right); many users don't keep a Home folder;
the one New session control doesn't say which project it starts in. A study, nothing built. Sample data only (the home-evolution study's names).</div>
<div style="display:grid;grid-template-columns:1fr 1fr;gap:28px">
<div style="display:flex;flex-direction:column;gap:10px">
<div class="h2">Why it looks like that (board 01)</div>
<div class="txt">The Board packs <strong>whole folders</strong> into at most <strong>three columns</strong> (DL-83, DL-129). Home's ★ tile and every project
sitting directly in Home are one unlabelled column, so it is always the tallest; a folder with one project is a short column beside it. A wider window
only makes the three columns wider (526 pt each at 1900): nothing new fits. Folders outside Home sit under the whole grid, below the tallest column.</div>
<div class="h2" style="margin-top:8px">The directions</div>
<div class="txt"><strong>A · Folder bands</strong> (board A). The smallest fix: each folder is a row of tiles across the width, Home is one band like any folder, more tiles across when the window is wider.<br>
<strong>B · By activity, recommended</strong> (boards B1, B2). Pinned, Now, Today as tiles; This week as rows; Earlier and Archived folded. The folder becomes a line on the tile. Group ⌄ keeps Folder (A's bands) and None.<br>
<strong>C · Flat, with pins and a folder filter</strong> (board C). One grid by recency; folders are chips that filter.<br>
<strong>D · A projects table</strong> (board D). The broad rethink: a sortable table instead of tiles.</div>
</div>
<div style="display:flex;flex-direction:column;gap:10px">
<div class="h2">In every direction (board T)</div>
<div class="txt"><strong>+ New session on every tile</strong>: a quiet last row, in the tile's own frame, so there's no doubt which project it starts in.
The tooltip names the project and its folder; ⌘T starts one in the tile that has the keyboard focus. The verb, <code>duo2 session new --project</code>, already exists.</div>
<div class="h2" style="margin-top:8px">Decisions (recommendation first)</div>
<div class="txt" style="font-size:13px;line-height:20px">
<strong>Q-539</strong> How the Board organises projects: <strong>B, by activity</strong> · A folder bands · C flat + filter · D table. Boards B1, A, C, D.<br>
<strong>Q-540</strong> Group ⌄ on the Board: <strong>Activity, Folder, None (A's bands are Folder)</strong> · only the chosen one. B1.<br>
<strong>Q-541</strong> Pinned projects: <strong>yes, a Pinned row first; ★ home pinned when there is a Home</strong> · no pins. B1, C.<br>
<strong>Q-542</strong> The tile's New session control: <strong>a quiet last row, + New session</strong> · a + in the name row · only on hover. T.<br>
<strong>Q-543</strong> ⌘T on the Board: <strong>the focused tile's project, else as today</strong> · always as today. T.<br>
<strong>Q-544</strong> Folders with no project file, Outside Home, Archived: <strong>in the same sections, marked, with Make a Project; no Outside Home rule</strong> · keep today's Outside Home part. B1, T.<br>
<strong>Q-545</strong> How many across: <strong>as many as fit at 220 (four at 1440, six at 1900)</strong> · keep three at most. A, B2.</div>
</div>
</div>
<div class="txt mut" style="margin-top:auto">Canvas {CANVAS} · fits the Projects pane study (Q-527 to Q-531) and Getting started (Q-532 to Q-536): board X.</div>
</div>'''
board("Main.dc.html", "00 All projects board study", 1440, 900, main)

# ---- 01 Today ----------------------------------------------------------------------------------
today = f'''
<div style="padding:28px 32px;display:flex;flex-direction:column;gap:12px;height:100%;box-sizing:border-box">
<div class="h2">Today's Board on the sample data (map-many), captured from main: 1900 wide above, 1440 below</div>
<div style="display:flex;gap:24px;align-items:flex-start">
<div style="display:flex;flex-direction:column;gap:12px">
<img src="{IMG1900}" alt="Today's Board at 1900 wide: Home's column is tall, growth's column ends after one tile" style="width:900px;height:503px;border:1px solid #C9CDD3;border-radius:6px">
<img src="{IMG1440}" alt="Today's Board at 1440 wide" style="width:500px;height:299px;border:1px solid #C9CDD3;border-radius:6px">
</div>
<div style="display:flex;flex-direction:column;gap:14px;max-width:420px" class="txt">
<div><strong>1 · Folders are packed whole.</strong> <code>PackedColumns</code> places each folder (a topic) in the shortest column, but never splits one, so a folder's tiles always stack down a single column (DL-129).</div>
<div><strong>2 · Home's column is always the tallest.</strong> Home's ★ tile and every project directly in Home share the first, unlabelled column (DL-83, DL-104). Home's tile is the tallest tile (five sessions and "n more").</div>
<div><strong>3 · Three columns at most.</strong> <code>maxPerRow = 3</code> with <code>mapColumnMin</code> 220: a wider window makes three wider tiles (526 pt each at 1900), with no fourth column.</div>
<div><strong>4 · Everything else waits below.</strong> OUTSIDE HOME, its active tiles and its folder rows start under the tallest column, so the white space beside a short folder is never used.</div>
<div><strong>5 · New session has no project.</strong> The Board has no New session control at all. The List's row reads "New session in ★ home ⌄" (DL-262), and ⌘T at All projects starts in Home, or else in ~/Documents. Neither is a project you can see.</div>
<div><strong>6 · No Home, no first column.</strong> Without a Home folder (Geoff thinks many users have none), every folder is grouped under its parent's path, and the map is all "Outside Home".</div>
</div>
</div>
</div>'''
board("Today.dc.html", "01 Today: why the space goes unused", 1440, 900, today)

# ---- T: the New session control ----------------------------------------------------------------
tipA = '<div class="tip" style="left:{x}px;top:{y}px">New session in checkout-redesign<br><span style="color:#C9CDD3">~/work/home/payments/checkout-redesign</span></div>'
t = f'''
<div style="padding:28px 32px;display:flex;flex-direction:column;gap:14px;height:100%;box-sizing:border-box">
<div class="h2">T · + New session on every tile. Recommended: T1, a quiet last row (Q-542)</div>
<div style="display:flex;gap:14px;align-items:flex-start">
<div style="display:flex;flex-direction:column;gap:6px;width:258px"><span class="lab">T1 · rest</span>{tile("checkout-redesign", width=258)}</div>
<div style="display:flex;flex-direction:column;gap:6px;width:258px;position:relative"><span class="lab">T1 · hover</span>{tile("checkout-redesign", width=258, hov=True)}{tipA.format(x=40, y=226)}</div>
<div style="display:flex;flex-direction:column;gap:6px;width:258px"><span class="lab">T1 · focused tile (arrows)</span>{tile("checkout-redesign", width=258, focus=True, nskey="⌘T")}</div>
<div style="display:flex;flex-direction:column;gap:6px;width:258px"><span class="lab">★ home</span>{tile("home", width=258)}</div>
<div style="display:flex;flex-direction:column;gap:6px;width:258px"><span class="lab">No project file</span>{tile("site", width=258)}<div style="height:6px"></div>{tile("payments-api", width=258)}</div>
</div>
<div style="display:flex;gap:16px;align-items:flex-start;margin-top:56px">
<div style="display:flex;flex-direction:column;gap:6px;width:220px"><span class="lab">T1 · narrowest, 220</span>{tile("onboarding-v3", width=220)}</div>
<div style="display:flex;flex-direction:column;gap:6px;width:258px"><span class="lab">T2 · a + in the name row</span>{tile("checkout-redesign", width=258, ns="corner")}</div>
<div style="display:flex;flex-direction:column;gap:6px;width:258px"><span class="lab">T2 · hover</span>{tile("checkout-redesign", width=258, ns="corner", hov=True)}</div>
<div style="display:flex;flex-direction:column;gap:8px;width:520px" class="txt">
<div><strong>What it does.</strong> It starts a Claude session in the tile's folder, in chat or terminal as Settings says, and opens the project's page on it, as the sidebar's button does inside a project. A folder with no project file starts there too (Claude asks its own trust question), and stays a folder.</div>
<div><strong>Why a row, not a +.</strong> It sits inside the tile's frame and reads as a sentence, so you can tell which project it belongs to, and it lines up with the session rows above it. T2's + is quieter, but it's easy to miss, and a + in a name row usually means "add a project".</div>
<div><strong>Keys and verbs.</strong> The arrow keys already move focus between tiles (§6.3). With a tile focused, ⌘T starts the session there, and the row shows ⌘T. With no tile focused, ⌘T works as it does today (Home, else ~/Documents) (Q-543). <code>duo2 session new --project checkout-redesign</code>, or <code>--folder ~/repos/site</code> for a plain folder: both exist. The tile's menu gains New Session.</div>
</div>
</div>
{ann(816, 760, "T1: a 24 pt last row under a hairline (<code>selected</code>), the + in the glyph column, in text2 at 12. Hover: <code>selected</code> fill, text. The tooltip names the project and its folder.", 300)}
{ann(1130, 760, "Tiles in a project's colour or a window's tint are unchanged; the row takes the tile's ground.", 280)}
</div>'''
board("T-tile-button.dc.html", "T · New session on every tile [P]", 1440, 900, t)

# ---- A: folder bands ---------------------------------------------------------------------------
a_mid = (header(group="Folder", flt="Filter projects") +
  lab("★ home", rule=True) + grid(["home", "q4-planning", "vendor-review", "weekly-metrics", "api-deprecations"], 4, path=False) +
  '<div class="grid" style="grid-template-columns:repeat(2,minmax(0,1fr));gap:12px">'
  '<div style="display:flex;flex-direction:column;gap:8px">' + lab("payments /", icon=True, rule=True) + grid(["checkout-redesign", "refunds-api-spec"], 2, path=False) + '</div>'
  '<div style="display:flex;flex-direction:column;gap:8px">' + lab("growth /", icon=True, rule=True) + grid(["onboarding-v3", "pricing-experiment-q4"], 2, path=False) + '</div></div>' +
  lab("Outside Home", 6, rule=True) + grid(["board-deck", "site", "payments-api", "research-notes"], 4))
a = window(a_mid) + ann(300, 280, "Each folder is a band across the width, its tiles flowing four across at 1440 (Q-545). Home's band is labelled ★ home and its tile is the same size as any other, three rows and \"18 more\".", 300) + ann(660, 280, "Bands with few tiles share a row: payments / and growth / take two columns each. No column ever runs taller than its band.", 300) + ann(1092, 600, "Outside Home stays its own band, as built: tiles for live folders, rows by parent folder below them. Archived folds last.", 300)
board("A-folder-bands.dc.html", "A · Folder bands: the smallest fix [P]", 1440, 900, a)

# ---- B1: by activity ---------------------------------------------------------------------------
b_mid = (header(group="Activity") +
  lab("Pinned", 3) + grid(["home", "checkout-redesign", "onboarding-v3"], 4) +
  lab("Now", 4) + grid(["q4-planning", "pricing-experiment-q4", "board-deck", "site"], 4) +
  lab("Today", 2) + grid(["vendor-review", "weekly-metrics"], 4) +
  lab("This week", 3) + '<div>' + prow("api-deprecations") + prow("payments-api", hov=True) + prow("research-notes") + '</div>' +
  fold("Earlier · 2") + fold("Archived · 3"))
b1 = window(b_mid) + \
  ann(556, 576, "Group ⌄ (Activity, Folder, None) replaces Sort on the Board, like the List's Group (Q-540). Activity is the default.", 240) + \
  ann(810, 576, "<strong>Pinned</strong>: projects you pin (tile menu › Pin to Top, <code>duo2 project pin</code>). ★ home starts pinned when you have a Home, and you can unpin it (Q-541).", 250) + \
  ann(1092, 590, "<strong>Now</strong>: a session needs you, is working, is open, or has something to review. <strong>Today</strong> and <strong>This week</strong> go by the last session's start, as the List's groups do. Tiles move between sections as their sessions change, fading in where they land (<code>motionTileIn</code>).", 336) + \
  ann(1092, 735, "<strong>This week</strong> is rows (name, folder, status, when, +), so the quiet projects don't take a tile each. Earlier and Archived stay folded. A folder with no project file is listed with the others, marked, and has Make a Project (Q-544). There's no Outside Home part.", 336)
board("B1-activity.dc.html", "B1 · By activity, recommended (1440) [P]", 1440, 900, b1)

# ---- B2: wide ----------------------------------------------------------------------------------
b2_mid = (header(group="Activity") +
  lab("Pinned", 3) + grid(["home", "checkout-redesign", "onboarding-v3"], 6) +
  lab("Now", 4) + grid(["q4-planning", "pricing-experiment-q4", "board-deck", "site"], 6) +
  lab("Today", 2) + grid(["vendor-review", "weekly-metrics"], 6) +
  lab("This week", 3) + '<div>' + prow("api-deprecations") + prow("payments-api") + prow("research-notes") + '</div>' +
  fold("Earlier · 2") + fold("Archived · 3"))
b2 = window(b2_mid) + ann(1080, 120, "At 1900 there are six across at 220 or wider (Q-545). Sections still start a new row, so the right end of a short section is empty, but nothing runs down one column and the whole Board fits without scrolling.", 380)
board("B2-activity-wide.dc.html", "B2 · By activity at 1900 [P]", 1900, 1060, b2)

# ---- C: flat with pins and a folder filter -----------------------------------------------------
chips = ('<div style="display:flex;gap:6px;align-items:center;flex-wrap:wrap"><span class="chip on">All folders</span><span class="chip">★ home</span>'
         '<span class="chip">payments</span><span class="chip">growth</span><span class="chip">~/repos</span><span class="chip">~/Desktop</span><span class="chip">~/Documents</span></div>')
c_mid = (header(group="None").replace("Group</span><span class=\"pop\">None ⌃", "Sort</span><span class=\"pop\">Recent ⌃") +
  lab("Pinned", 3) + grid(["home", "checkout-redesign", "onboarding-v3"], 4) +
  lab("All projects", 11) + chips +
  grid(["q4-planning", "pricing-experiment-q4", "board-deck", "site", "vendor-review", "weekly-metrics", "payments-api", "api-deprecations"], 4))
c = window(c_mid) + \
  ann(20, 745, "One grid, newest first (or by name). The folder line on each tile is the only place a folder shows. The chips filter to one folder; ★ home is just one of them.", 300) + \
  ann(380, 745, "Simple, and it fills the width. But needs you and working tiles are mixed in with quiet ones (only the order shows what's live), and with 60 folders the chips need a menu of their own.", 330)
board("C-flat-pinned.dc.html", "C · Flat, pins and a folder filter [P]", 1440, 900, c)

# ---- D: a projects table -----------------------------------------------------------------------
th = ('<div class="prow" style="height:24px"><span></span><span class="th2">Project ⌃</span><span class="th2">Folder</span><span class="th2">Status</span>'
      '<span class="th2" style="text-align:right">Active</span><span></span></div>')
def drow(key, att="", hov=False):
    r = prow(key, hov=hov, pin=key in ("home", "checkout-redesign", "onboarding-v3"))
    return r.replace('<span class="g"></span>', att or '<span class="g"></span>', 1) if att else r
d_mid = (header(group="None").replace('<span class="on">Board</span><span>List</span>', '<span class="on">Projects</span><span>Sessions</span>').replace("Group</span><span class=\"pop\">None ⌃", "Group</span><span class=\"pop\">None ⌃") +
  th + lab("Pinned", 3) + drow("home") + drow("checkout-redesign") + drow("onboarding-v3") +
  lab("All", 11) + drow("q4-planning") + drow("pricing-experiment-q4", hov=True) + drow("board-deck") + drow("site") + drow("vendor-review") + drow("weekly-metrics") +
  drow("payments-api") + drow("api-deprecations") + drow("research-notes") + drow("refunds-api-spec") + drow("scripts"))
d = window(d_mid) + \
  ann(20, 730, "Board | List becomes Projects | Sessions: a table of projects next to the List of sessions. Headers sort; Group ⌄ is shared with B (Activity, Folder, None).", 300) + \
  ann(370, 730, "The densest view, and it works best with 60 or more folders. But it loses what makes a tile useful: a project's live sessions at a glance. Inside a project you'd still see them, and here only as a glyph. Better as an extra view later (ENH-351) than in place of the Board.", 330) + \
  ann(720, 730, "Each row ends in a quiet + (+ New session on hover, as drawn), with the same verb and tooltip as T1.", 330)
board("D-table.dc.html", "D · A projects table (broad) [P]", 1440, 900, d)

# ---- X: fit with the other studies, keys, not drawn --------------------------------------------
x = f'''
<div style="padding:32px 40px;display:grid;grid-template-columns:1fr 1fr;gap:28px;height:100%;box-sizing:border-box" class="txt">
<div style="display:flex;flex-direction:column;gap:12px">
<div class="h2">X · How each direction fits the other two studies</div>
<div><strong>Projects pane</strong> (https://claude.ai/artifact/MMAaxkzezLUu8LEBGUpbpQ, Q-527 to Q-531). Its A puts a 260 list of projects at All projects' left, "in the map's order". Whatever Q-539 picks sets that order: with B, the pane reads Pinned, Now, Today, then the rest; with A, folders. With the pane, the middle is 840 at 1440, three across at 220. The pane's "+ New session" row and the tile's last row use the same words and verb. Q-531's "+ New session in ‹project›" is for the sidebar; a tile already names its project, so its row reads "+ New session" and the tooltip names the project. If Q-527 picks C, the switcher lists projects by B's sections.</div>
<div><strong>Getting started</strong> (https://claude.ai/artifact/1a6Lfh9dNwco7X5ksruKhJ, Q-532 to Q-536). The card sits above the Board or List in every direction. On a new install, B's Board shows only Today and This week (nothing pinned, no Home), so the card and a few tiles fit with no scrolling. Step 2's Show me points at a tile's + New session row on the Board and at the List's New session row on the List. The Home explainer's anchor (Q-536) moves to ★ home's tile, which is in Pinned under B.</div>
<div><strong>DL-336</strong> stands: no Home column. B makes Home one pinned tile, so a user with no Home folder sees the same Board, just without it.</div>
</div>
<div style="display:flex;flex-direction:column;gap:12px">
<div class="h2">Keys, menus, duo2 (DL-71)</div>
<div style="font-size:13px;line-height:20px">
Tile's + New session, tile menu › New Session · <code>duo2 session new --project &lt;p&gt;</code> or <code>--folder &lt;path&gt;</code> (exists)<br>
⌘T on the Board: the focused tile, else Home, else ~/Documents · the same verb<br>
Group ⌄: Activity, Folder, None; View › Group Projects By · <code>duo2 view group activity|folder|none</code> (new; <code>duo2 view sort</code> stays for C and D)<br>
Pin to Top, Unpin (tile menu, project menu) · <code>duo2 project pin &lt;p&gt; [on|off]</code> (new)<br>
Folder chips (C) · <code>duo2 view filter --folder &lt;path&gt;</code> (new, C only)<br>
Projects | Sessions (D) · <code>duo2 view home projects|list</code> (D only)</div>
<div class="h2">Considered, not drawn</div>
<div style="font-size:13px;line-height:20px"><strong>A timeline</strong> (projects as lanes over days): the List and B's sections already show recency; a timeline needs more width than All projects has. <strong>Tags or people</strong> (group by a <code>tags:</code> or <code>owner:</code> in _PROJECT.md): no project has them today, so it would start empty. It could be a fourth Group option later (ENH-352). <strong>Tasks first</strong> (every open task across projects): the action column's Open tasks covers it, and each project's task board (DL-148) is where tasks are worked.</div>
</div>
</div>'''
board("X-fit.dc.html", "X · Fit with the Projects pane and Getting started; keys; not drawn", 1440, 900, x)

# ---- the index ---------------------------------------------------------------------------------
boards = [("Main.dc.html", 1440, 900, "00 · The ask, why, four directions, the decisions"),
          ("Today.dc.html", 1440, 900, "01 · Today: why the space goes unused (captures, sample data)"),
          ("T-tile-button.dc.html", 1440, 900, "T · + New session on every tile [P]"),
          ("B1-activity.dc.html", 1440, 900, "B1 · By activity, recommended, 1440 [P]"),
          ("B2-activity-wide.dc.html", 1900, 1060, "B2 · By activity at 1900 [P]"),
          ("A-folder-bands.dc.html", 1440, 900, "A · Folder bands, the smallest fix [P]"),
          ("C-flat-pinned.dc.html", 1440, 900, "C · Flat, pins and a folder filter [P]"),
          ("D-table.dc.html", 1440, 900, "D · A projects table, the broad rethink [P]"),
          ("X-fit.dc.html", 1440, 900, "X · Fit with the other studies; keys and verbs; not drawn")]
rows = [[0, 1, 2], [3, 4], [5, 6, 7], [8]]
layout, y = {}, 0
for r in rows:
    x = 0
    for i in r:
        f, w, h, ttl = boards[i]
        layout[f] = {"x": x, "y": y, "w": w, "h": h, "title": ttl}
        x += w + 80
    y += max(boards[i][2] for i in r) + 343
idx_path = os.path.join(OUT, "canvas.json")
idx = json.load(open(idx_path)) if os.path.exists(idx_path) else {"v": 3, "createdOnFiles": {"v": 1, "at": "2026-11-13T12:10:00Z"}, "pages": [], "notes": {}, "designSystems": []}
idx.update({"title": "Duo All projects board", "launch": {"view": "canvas"}, "boards": layout, "order": [b[0] for b in boards]})
idx["notes"] = {"h0": {"x": 0, "y": -260, "text": "All projects' Board: organising projects (2026-11-13)", "kind": "title1", "maxW": 4480},
                "h1": {"x": 0, "y": layout["B1-activity.dc.html"]["y"] - 240, "text": "B, recommended: by activity", "kind": "title1", "maxW": 3420},
                "h2": {"x": 0, "y": layout["A-folder-bands.dc.html"]["y"] - 240, "text": "The other directions: A folder bands, C flat, D a table", "kind": "title1", "maxW": 4480},
                "h3": {"x": 0, "y": layout["X-fit.dc.html"]["y"] - 240, "text": "Fit, keys, not drawn", "kind": "title1", "maxW": 1440}}
idx.setdefault("designSystems", [])
if not any(d.get("namespace") == "duo" for d in idx["designSystems"]):
    idx["designSystems"].append({"title": "Duo", "namespace": "duo", "artifact": "https://claude.ai/artifact/QMapKeLYS3TVV36QKEc6MH", "version": None, "copiedAt": "2026-11-13T12:10:00Z"})
json.dump(idx, open(idx_path, "w"), indent=1, ensure_ascii=False)
print("wrote", len(boards), "boards to", OUT)
