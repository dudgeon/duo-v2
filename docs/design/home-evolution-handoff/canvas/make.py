#!/usr/bin/env python3
"""Draws the home-evolution study boards (every mark [P]) as static HTML in the Duo design system.

    python3 docs/design/home-evolution-handoff/canvas/make.py
    bash docs/design/home-evolution-handoff/canvas/render.sh

Colours are the light and console tokens of docs/design/build-handoff/tokens.json, by value, as the
exported screens are. Names and data are illustrative.
"""
import html, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "boards")

# tokens (build-handoff/tokens.json)
GROUND, PANE, SELECTED, RULE, EDGE = "#F3F4F6", "#FFFFFF", "#E9ECEF", "#C9CDD3", "#8B939C"
TEXT, TEXT2, NEEDS, TINT, YOU = "#1F2328", "#5B636D", "#C2410C", "#E8F0FA", "#DCE6F7"
CONSOLE, CRULE, CTEXT, CTEXT2 = "#15171B", "#2B2F36", "#E6E8EB", "#9AA1AB"

CSS = f"""
body{{margin:0}}
.w{{box-sizing:border-box;display:flex;flex-direction:column;background:{PANE};color:{TEXT};font:13px/20px -apple-system,BlinkMacSystemFont,'SF Pro Text',system-ui,sans-serif;white-space:nowrap;overflow:hidden}}
.w *{{box-sizing:border-box}}
.mono{{font-family:ui-monospace,'SF Mono',SFMono-Regular,Menlo,monospace;font-size:12px;line-height:19px}}
.tb{{display:flex;align-items:center;gap:8px;height:38px;flex:none;padding:0 12px 0 20px;border-bottom:1px solid {RULE};background:{GROUND}}}
.tl{{display:flex;gap:8px;margin-right:4px}}.tl i{{width:12px;height:12px;border-radius:50%;display:block}}
.cnt{{display:flex;gap:16px;margin-left:8px;align-items:center}}.cnt span{{display:flex;gap:6px;align-items:center}}
.srch{{margin-left:auto;width:300px;height:24px;border:1px solid {RULE};border-radius:6px;background:{PANE};display:flex;align-items:center;gap:6px;padding:0 8px;color:{TEXT2}}}
.tgl{{display:flex;padding:4px 6px}}
.sl{{font:600 11px/16px -apple-system,system-ui,sans-serif;letter-spacing:.66px;text-transform:uppercase;color:{TEXT2};display:flex;align-items:center;gap:6px;height:16px}}
.t2{{color:{TEXT2}}}
.ell{{overflow:hidden;text-overflow:ellipsis;min-width:0}}
.filter{{display:inline-flex;align-items:center;gap:6px;height:22px;padding:0 8px;border:1px solid {RULE};border-radius:6px;color:{TEXT2};font-size:12px;background:{PANE}}}
.popup{{display:inline-flex;align-items:center;gap:6px;height:22px;padding:0 6px 0 8px;border:1px solid {RULE};border-radius:6px;font-size:12px;line-height:16px;background:{PANE}}}
.segc{{display:inline-flex;height:22px;border:1px solid {EDGE};border-radius:6px;overflow:hidden;background:{PANE};font-size:12px;line-height:16px}}
.segc span{{display:flex;align-items:center;padding:0 10px;color:{TEXT2}}}
.segc span+span{{border-left:1px solid {RULE}}}
.segc .on{{background:{SELECTED};color:{TEXT};font-weight:600}}
.chip{{display:inline-flex;align-items:center;gap:5px;height:22px;padding:0 9px;border:1px solid {RULE};border-radius:11px;font-size:12px;line-height:16px;color:{TEXT2};background:{PANE}}}
.chip.on{{border-color:{TEXT};color:{TEXT};font-weight:600}}
.row{{white-space:nowrap;display:flex;align-items:center;gap:8px;height:26px;padding:0 8px;margin:0 8px;border-radius:6px;min-width:0}}
.row.tint{{background:{TINT}}}
.row.sel{{background:{SELECTED}}}
.row .ti{{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis}}
.row .pj{{color:{TEXT2};overflow:hidden;text-overflow:ellipsis;flex:none}}
.row .tk{{display:flex;align-items:center;gap:5px;color:{TEXT2};overflow:hidden;flex:none}}
.row .tm{{color:{TEXT2};flex:none;text-align:right}}
.row2{{white-space:nowrap;display:flex;flex-direction:column;justify-content:center;gap:0;height:44px;padding:0 8px;margin:0 8px;border-radius:6px;min-width:0}}
.row2.tint{{background:{TINT}}}
.row2.sel{{background:{SELECTED}}}
.row2 .l1,.row2 .l2{{display:flex;align-items:center;gap:8px;min-width:0}}
.row2 .l2{{padding-left:17px;font-size:12px;line-height:16px;color:{TEXT2}}}
.sec{{padding:10px 16px 4px;font:600 11px/16px -apple-system,system-ui,sans-serif;letter-spacing:.66px;color:{TEXT2}}}
.sec.ny{{color:{NEEDS}}}
.fold{{display:flex;align-items:center;gap:8px;height:26px;padding:0 16px;color:{TEXT2}}}
.card{{border:1px solid {RULE};border-radius:6px;padding:10px 12px 12px;display:flex;flex-direction:column;gap:2px;white-space:normal}}
.card .top{{display:flex;align-items:center;gap:6px;white-space:nowrap}}
.q{{border:1.5px solid {NEEDS};border-radius:6px;padding:6px 10px;margin:6px 0}}
.btn{{align-self:flex-start;display:inline-flex;align-items:center;height:26px;padding:0 10px;border:1px solid {EDGE};border-radius:6px;background:{PANE};font-size:12px;line-height:16px;color:{TEXT}}}
.act{{flex:none;padding:16px;display:flex;flex-direction:column;gap:10px;overflow:hidden;border-left:1px solid {RULE}}}
.mapcol{{flex:1;min-width:0;display:flex;flex-direction:column}}
.mh{{display:flex;align-items:center;gap:10px;height:22px;flex:none}}
.tile{{display:flex;flex-direction:column;gap:2px;padding:10px 12px 12px;border:1px solid {RULE};border-radius:6px;min-width:0}}
.tile.star{{border-color:{TEXT}}}
.nm{{font-weight:600;overflow:hidden;text-overflow:ellipsis}}
.srow{{height:24px;display:flex;align-items:center;gap:6px;min-width:0;border-radius:4px}}
.srow .n{{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis}}
.foot{{height:34px;flex:none;border-top:1px solid {RULE};display:flex;align-items:center;gap:8px;padding:0 16px;color:{TEXT2}}}
/* chat (chat-mode-handoff, chat-polish-handoff) */
.chat{{display:flex;flex-direction:column;background:{GROUND};min-width:0;min-height:0}}
.strip{{white-space:nowrap;display:flex;align-items:stretch;gap:16px;height:28px;flex:none;padding:0 10px 0 16px;background:{GROUND};border-bottom:1px solid {RULE};font-size:12px;line-height:16px}}
.strip .tab{{display:flex;align-items:center;gap:6px;color:{TEXT2}}}
.strip .tab.on{{color:{TEXT};font-weight:600;box-shadow:inset 0 -2px 0 {TEXT}}}
.pill{{display:flex;border:1px solid {EDGE};border-radius:6px;overflow:hidden;background:{PANE}}}
.pill span{{width:22px;height:16px;display:flex;align-items:center;justify-content:center;color:{TEXT2}}}
.pill .on{{background:{SELECTED};color:{TEXT}}}
.feed{{flex:1;min-height:0;display:flex;flex-direction:column;justify-content:flex-end;gap:12px;overflow:hidden;font-size:14px;line-height:22px;white-space:normal}}
.who{{font-size:12px;line-height:16px;color:{TEXT2}}}
.ccard{{background:{PANE};border-radius:14px 14px 14px 3px;padding:12px 16px 14px;display:flex;flex-direction:column;gap:8px}}
.you{{background:{YOU};border-radius:14px 14px 3px 14px;padding:8px 14px}}
.trail{{display:flex;flex-direction:column;border-left:1.5px dotted {EDGE};margin-left:6px}}
.step{{display:flex;align-items:center;gap:10px;min-height:24px;margin-left:-5px;font-size:12px;line-height:16px;color:{TEXT2}}}
.step b{{font-weight:600;color:{TEXT}}}
.dot{{width:7px;height:7px;border-radius:4px;border:1.5px solid {EDGE};background:{PANE};flex:none;margin-left:3px}}
.composer{{flex:none;background:{PANE};border:1px solid {EDGE};border-radius:12px;padding:7px 12px;color:{TEXT2};font-size:14px;line-height:22px}}
.ask{{background:{PANE};border:1.5px solid {NEEDS};border-radius:14px;padding:12px 14px;display:flex;flex-direction:column;gap:8px;white-space:normal}}
.lbl{{font-size:11px;line-height:16px;font-weight:600;letter-spacing:.06em}}
.opt{{display:flex;align-items:flex-start;gap:8px;font-size:13px;line-height:20px;border:1px solid {EDGE};border-radius:8px;padding:5px 8px}}
.key{{flex:none;width:18px;height:18px;margin-top:1px;border:1px solid {RULE};border-radius:4px;display:flex;align-items:center;justify-content:center;font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:11px;line-height:16px;color:{TEXT2};background:{GROUND}}}
/* board furniture: not the app */
.bd{{box-sizing:border-box;background:{GROUND};color:{TEXT};font:13px/20px -apple-system,BlinkMacSystemFont,'SF Pro Text',system-ui,sans-serif;overflow:hidden;padding:24px 28px;display:flex;flex-direction:column;gap:14px}}
.bd *{{box-sizing:border-box}}
.bt{{font:600 17px/24px -apple-system,system-ui,sans-serif}}
.bsub{{color:{TEXT2};font-size:13px;line-height:20px;white-space:normal;max-width:1100px}}
.note{{color:{TEXT2};font-size:12px;line-height:18px;white-space:normal}}
.note b{{color:{TEXT};font-weight:600}}
.frame{{background:{PANE};border:1px solid {RULE};border-radius:8px;overflow:hidden;display:flex;flex-direction:column}}
.cap{{font:600 11px/16px -apple-system,system-ui,sans-serif;letter-spacing:.66px;text-transform:uppercase;color:{TEXT2}}}
.rec{{display:inline-block;font:600 11px/16px -apple-system,system-ui,sans-serif;letter-spacing:.4px;color:{TEXT};border:1px solid {TEXT};border-radius:9px;padding:0 7px;margin-left:6px;vertical-align:1px}}
.p{{color:{TEXT2};font-weight:500}}
.txt{{background:{PANE};border:1px solid {RULE};border-radius:8px;padding:16px 18px;white-space:normal;font-size:13px;line-height:20px}}
.txt h3{{margin:0 0 6px;font-size:13px;line-height:20px;font-weight:600}}
.txt ul,.txt ol{{margin:4px 0 8px;padding-left:18px}}
.txt li{{margin:2px 0}}
.txt p{{margin:4px 0 8px}}
.txt code{{font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:12px}}
"""

# ---------- glyphs ----------
def g(kind, color=None):
    if kind == "needs":
        return f'<svg width="9" height="9" viewBox="0 0 10 10" style="flex:none"><circle cx="5" cy="5" r="5" fill="{color or NEEDS}"/></svg>'
    if kind == "review":
        return f'<svg width="9" height="9" viewBox="0 0 10 10" style="flex:none"><path d="M5 0 10 5 5 10 0 5z" fill="{color or TEXT}"/></svg>'
    if kind == "working":
        return f'<svg width="9" height="9" viewBox="0 0 10 10" style="flex:none"><circle cx="5" cy="5" r="4.2" fill="none" stroke="{color or TEXT}" stroke-width="1.5"/></svg>'
    if kind in ("idle", "prompt"):
        return f'<svg width="9" height="9" viewBox="0 0 10 10" style="flex:none"><path d="M1 5h8" fill="none" stroke="{color or TEXT2}" stroke-width="1.6" stroke-linecap="round"/></svg>'
    if kind == "task":
        return f'<svg width="10" height="10" viewBox="0 0 10 10" style="flex:none"><rect x="1" y="1" width="8" height="8" rx="2" fill="none" stroke="{color or TEXT2}" stroke-width="1.3"/></svg>'
    if kind == "chev":
        return f'<svg width="8" height="10" viewBox="0 0 8 10" style="flex:none"><path d="M2 1.5 6 5 2 8.5" fill="none" stroke="{color or TEXT2}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>'
    if kind == "chevd":
        return f'<svg width="10" height="8" viewBox="0 0 10 8" style="flex:none"><path d="M1.5 2 5 6 8.5 2" fill="none" stroke="{color or TEXT2}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>'
    if kind == "search":
        return f'<svg width="11" height="11" viewBox="0 0 12 12" style="flex:none"><circle cx="5" cy="5" r="3.6" fill="none" stroke="{TEXT2}" stroke-width="1.3"/><path d="M7.8 7.8 11 11" stroke="{TEXT2}" stroke-width="1.3" stroke-linecap="round"/></svg>'
    if kind == "updown":
        return f'<svg width="7" height="10" viewBox="0 0 7 10"><path d="M1 3.5 3.5 1 6 3.5M1 6.5 3.5 9 6 6.5" fill="none" stroke="{TEXT2}" stroke-width="1.2"/></svg>'
    if kind == "folder":
        return f'<svg width="12" height="10" viewBox="0 0 12 10" style="flex:none"><path d="M1 2.2c0-.7.5-1.2 1.2-1.2h2.3l1.2 1.3h4.1c.7 0 1.2.5 1.2 1.2v4.3c0 .7-.5 1.2-1.2 1.2H2.2C1.5 9 1 8.5 1 7.8z" fill="none" stroke="{TEXT2}" stroke-width="1.1"/></svg>'
    if kind == "jump":
        return f'<svg width="10" height="10" viewBox="0 0 10 10" style="flex:none"><path d="M3.5 1.5h5v5M8.5 1.5 1.5 8.5" fill="none" stroke="{color or TEXT2}" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>'
    if kind == "term":
        return '<svg width="13" height="10" viewBox="0 0 13 10"><path d="M1.5 2 5 5 1.5 8" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><path d="M6.5 8.5h5" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>'
    if kind == "bubble":
        return '<svg width="13" height="11" viewBox="0 0 13 11"><path d="M2.5 1h8A1.5 1.5 0 0 1 12 2.5v4A1.5 1.5 0 0 1 10.5 8H6L3.5 10V8h-1A1.5 1.5 0 0 1 1 6.5v-4A1.5 1.5 0 0 1 2.5 1Z" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/></svg>'
    if kind == "sidebar":
        return f'<svg width="18" height="14" viewBox="0 0 18 14"><rect x="1" y="1" width="16" height="12" rx="2.5" fill="none" stroke="{TEXT2}" stroke-width="1.3"/><path d="M6.5 1v12" stroke="{TEXT2}" stroke-width="1.3"/></svg>'
    if kind == "right":
        return f'<svg width="18" height="14" viewBox="0 0 18 14"><rect x="1" y="1" width="16" height="12" rx="2.5" fill="none" stroke="{TEXT2}" stroke-width="1.3"/><path d="M11.5 1v12" stroke="{TEXT2}" stroke-width="1.3"/></svg>'
    if kind == "board":
        return f'<svg width="12" height="10" viewBox="0 0 12 10" style="flex:none"><rect x="1" y="1" width="4" height="8" rx="1" fill="none" stroke="currentColor" stroke-width="1.2"/><rect x="7" y="1" width="4" height="5" rx="1" fill="none" stroke="currentColor" stroke-width="1.2"/></svg>'
    if kind == "list":
        return f'<svg width="12" height="10" viewBox="0 0 12 10" style="flex:none"><path d="M1 2h10M1 5h10M1 8h10" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/></svg>'
    raise KeyError(kind)

GLYPH_FOR = {"needs": "needs", "review": "review", "working": "working", "prompt": "idle", "idle": "idle"}

# ---------- data (illustrative) ----------
# state, title, project, task, time, open, reason, thread
S = [
    dict(id="morning", st="needs", t="Morning triage", p="★ home", task=None, tm="1h", open=True, why="question", q="5 new asks this morning. Route 3 to projects?"),
    dict(id="copy", st="needs", t="Copy review pass 2", p="onboarding-v3", task="Launch copy", tm="12m", open=True, why="permission", q="Approve these 6 string changes?"),
    dict(id="prd", st="needs", t="PRD v2 edits", p="checkout-redesign", task="Exec review prep", tm="4m", open=False, why="question", q="Move saved cards into scope, or keep it out and log an open question?"),
    dict(id="readout", st="review", t="Results readout", p="pricing-experiment-q4", task="Q4 readout", tm="25m", open=False),
    dict(id="funnel", st="review", t="Funnel SQL", p="onboarding-v3", task=None, tm="40m", open=False),
    dict(id="teardown", st="working", t="Teardown research", p="checkout-redesign", task="Exec review prep", tm="working", open=True),
    dict(id="edge", st="working", t="Edge-case matrix", p="refunds-api-spec", task=None, tm="working", open=True),
    dict(id="rules", st="working", t="Rule audit", p="fraud-rules-review", task="Simplify rules", tm="working", open=True),
    dict(id="weekly", st="prompt", t="Weekly status draft", p="★ home", task=None, tm="at prompt", open=True),
    dict(id="footer", st="prompt", t="Fix footer links", p="~/repos/site", task=None, tm="at prompt", open=True),
    dict(id="buyer", st="idle", t="Buyer synthesis", p="buyer-interviews", task="Synthesis memo", tm="2h", open=False, when="today"),
    dict(id="q4", st="idle", t="Q4 plan outline", p="q4-planning", task="Draft plan", tm="3h", open=False, when="today"),
    dict(id="vendor", st="idle", t="Vendor shortlist", p="vendor-review", task=None, tm="5h", open=False, when="today"),
    dict(id="audit", st="idle", t="Checkout copy audit", p="checkout-redesign", task=None, tm="2d", open=False, when="week"),
    dict(id="deprec", st="idle", t="Deprecation email", p="api-deprecations", task="Sunset comms", tm="3d", open=False, when="week"),
    dict(id="summ", st="idle", t="“Summarise the six buyer interviews”", p="buyer-interviews", task=None, tm="4d", open=False, when="week"),
]
BY = {s["id"]: s for s in S}
NEEDS_IDS = ["morning", "copy", "prd"]
OPEN_IDS = ["teardown", "edge", "rules", "weekly", "footer"]
REVIEW_IDS = ["readout", "funnel"]
TODAY_IDS = ["readout", "funnel", "buyer", "q4", "vendor"]
WEEK_IDS = ["audit", "deprec", "summ"]


def e(s):
    return html.escape(s, quote=False)


def row(s, cols="full", sel=False, w_proj=150, w_task=150, w_tm=64, hover=None):
    """A one-line session row. cols: full (glyph, title, project, task, time) | proj (no task column) | bare."""
    cls = "row" + (" sel" if sel else (" tint" if s.get("open") and s["st"] != "needs" else ""))
    bold = ' style="font-weight:600"' if s["st"] == "needs" else ""
    parts = [g(GLYPH_FOR[s["st"]]), f'<span class="ti"{bold}>{e(s["t"])}</span>']
    if cols in ("full", "proj"):
        parts.append(f'<span class="pj" style="width:{w_proj}px">{e(s["p"])}</span>')
    if cols == "full":
        tk = f'{g("task")}<span class="ell">{e(s["task"])}</span>' if s.get("task") else ""
        parts.append(f'<span class="tk" style="width:{w_task}px">{tk}</span>')
    if hover:
        parts.append(hover)
    else:
        parts.append(f'<span class="tm" style="width:{w_tm}px">{e(s["tm"])}</span>')
    return f'<div class="{cls}">{"".join(parts)}</div>'


def row2(s, sel=False, reason=False):
    """A two-line row for narrow lists: title and time, then project › task (or the reason)."""
    cls = "row2" + (" sel" if sel else (" tint" if s.get("open") and s["st"] != "needs" else ""))
    bold = ' style="font-weight:600"' if s["st"] == "needs" else ""
    l2 = e(s["p"])
    if s.get("task"):
        l2 += f' <span style="color:{EDGE}">›</span> {g("task")} {e(s["task"])}'
    if reason and s.get("why"):
        l2 += f' · {e(s["why"])}'
    return (f'<div class="{cls}"><div class="l1">{g(GLYPH_FOR[s["st"]])}<span class="ti ell" style="flex:1"{bold}>{e(s["t"])}</span>'
            f'<span class="t2" style="flex:none">{e(s["tm"])}</span></div><div class="l2"><span class="ell" style="display:flex;align-items:center;gap:4px">{l2}</span></div></div>')


def sec(label, n=None, ny=False):
    t = label.upper() + (f" · {n}" if n is not None else "")
    return f'<div class="sec{" ny" if ny else ""}">{t}</div>'


def fold(label):
    return f'<div class="fold">{g("chev")}{e(label)}</div>'


def recency_list(two=False, needs="section", cols="full", wp=150, wt=150, sel=None, pointer=False, merged=False, merged_w=None):
    """The list grouped as DL-91 groups a project's sessions, across every project.
    needs: section | none | pointer | merged"""
    r = row2 if two else (lambda s, sel=False: row(s, cols, sel, wp, wt))
    out = []
    if needs == "section":
        out.append(sec("Needs you", 3, True))
        out += [r(BY[i], sel=(i == sel)) for i in NEEDS_IDS]
    elif needs == "pointer":
        out.append(f'<div class="row" style="margin-top:8px;border:1px solid {NEEDS};color:{NEEDS};font-weight:600;height:28px">{g("needs")}<span class="ti">3 need you</span><span style="font-weight:400" class="t2">in the column</span>{g("chev", NEEDS)}</div>')
    elif needs == "merged":
        out.append(sec("Needs you", 3, True))
        for i in NEEDS_IDS:
            s = BY[i]
            out.append(f'<div style="margin:0 8px 6px;border:1px solid {RULE};border-radius:6px;padding:4px 0 8px">' + row(s, cols, False, wp, wt).replace('class="row"', 'class="row" style="margin:0"') +
                       f'<div style="margin:2px 16px 0 33px;white-space:normal;display:flex;gap:10px;align-items:flex-start"><div class="q" style="margin:0;flex:1">{e(s["q"])}</div><span class="btn">Open</span></div></div>')
    out.append(sec("Open", 5))
    out += [r(BY[i], sel=(i == sel)) for i in OPEN_IDS]
    out.append(sec("Today"))
    today = TODAY_IDS
    out += [r(BY[i], sel=(i == sel)) for i in today]
    out.append(sec("This week"))
    out += [r(BY[i], sel=(i == sel)) for i in WEEK_IDS]
    out.append(fold("Earlier · 9"))
    out.append(fold("Archived · 4"))
    return "".join(out)


def list_header(width_field=220, group="Recent", chips=False, extra=""):
    h = f'<div style="display:flex;align-items:center;gap:8px;height:38px;flex:none;padding:0 16px;border-bottom:1px solid {RULE}">'
    h += f'<span class="filter" style="width:{width_field}px">{g("search")}Filter sessions</span>'
    h += '<span style="flex:1"></span>'
    if group:
        h += f'<span class="popup">{e(group)}{g("updown")}</span>'
    h += extra + '</div>'
    if chips:
        h += (f'<div style="display:flex;gap:6px;padding:8px 16px 2px;flex:none"><span class="chip on">All</span><span class="chip">{g("needs")}Needs you 3</span>'
              f'<span class="chip">Open 5</span><span class="chip">Tasks</span><span class="chip">Project{g("chevd")}</span></div>')
    return h


# ---------- window chrome ----------
def toolbar(view_toggle=None, crumb="All projects"):
    vt = ""
    if view_toggle:
        a, b = view_toggle
        vt = (f'<span class="segc" style="margin-left:12px"><span class="{"on" if a else ""}" style="gap:5px">{g("board")}Board</span>'
              f'<span class="{"on" if b else ""}" style="gap:5px">{g("list")}Sessions</span></span>')
    return f'''<div class="tb">
<span class="tl"><i style="background:#FF5F57"></i><i style="background:#FEBC2E"></i><i style="background:#28C840"></i></span>
<span class="tgl">{g("sidebar")}</span>
<span style="font-weight:600">{crumb}</span>{vt}
<span class="cnt"><span style="font-weight:600;color:{NEEDS}">{g("needs")}3 need you</span><span>{g("review")}2 to review</span><span>{g("working")}3 working</span><span class="t2">{g("idle")}14 idle</span></span>
<span class="srch">{g("search")}Search all projects<span style="margin-left:auto">⇧⌘A</span></span>
<span class="tgl" style="margin-left:4px">{g("right")}</span>
</div>'''


def window(w, h, body, tb=None):
    return f'<div class="w" style="width:{w}px;height:{h}px">{tb or toolbar()}<div style="display:flex;flex:1;min-height:0">{body}</div></div>'


# ---------- panes ----------
def home_header(dark=False, extra=""):
    if dark:
        return f'<div style="height:36px;flex:none;display:flex;align-items:center;gap:10px;padding:0 16px;border-bottom:1px solid {CRULE};background:{CONSOLE};color:{CTEXT}"><span style="font-weight:600">★ home</span><span class="mono" style="color:{CTEXT2}">~/work/home</span></div>'
    return f'<div style="height:36px;flex:none;display:flex;align-items:center;gap:10px;padding:0 12px 0 16px;border-bottom:1px solid {RULE};background:{GROUND}"><span style="font-weight:600">★ home</span><span class="mono t2 ell">~/work/home</span>{extra}</div>'


def pill(chat=True):
    return f'<span style="display:flex;align-items:center;margin-left:auto"><span class="pill"><span class="{"" if chat else "on"}">{g("term")}</span><span class="{"on" if chat else ""}">{g("bubble")}</span></span></span>'


def chat_strip(tabs, sel=0, right=""):
    t = "".join(f'<span class="tab{" on" if i == sel else ""}">{x}</span>' for i, x in enumerate(tabs))
    return f'<div class="strip">{t}<span class="tab">+</span>{right or pill(True)}</div>'


def home_feed(narrow=True, ask=False, compact=False):
    mr = 24 if narrow else 36
    pad = "14px 14px 12px" if narrow else "18px 24px 12px"
    parts = []
    if not compact:
        parts.append(f'''<div style="align-self:flex-end;display:flex;flex-direction:column;align-items:flex-end;gap:4px;max-width:86%"><div class="who">You · 8:02</div><div class="you">What came in overnight?</div></div>''')
    parts.append(f'''<div style="margin-right:{mr}px;display:flex;flex-direction:column;gap:4px"><div class="who">Claude · 8:03</div><div class="ccard">
<div class="trail"><div class="step"><span class="dot"></span><span><b>Read</b> 6 files, <b>ran</b> 2 shell commands</span><span style="margin-left:auto">›</span></div></div>
<div>Five new asks. Three belong to projects: the refunds edge cases, the onboarding copy and the pricing readout. Two are yours.</div></div></div>''')
    if not ask:
        parts.append(f'''<div style="margin-right:{mr}px;display:flex;flex-direction:column;gap:4px"><div class="ccard"><div>Route the three to their projects as tasks?</div></div></div>''')
    feed = f'<div class="feed" style="padding:{pad}">{"".join(parts)}</div>'
    if ask:
        bottom = f'''<div style="flex:none;padding:0 12px 12px"><div class="ask"><div style="display:flex;gap:6px"><span class="lbl" style="color:{NEEDS}">NEEDS YOU</span><span class="lbl t2">· QUESTION</span></div>
<div style="font-weight:600;font-size:13px;line-height:20px">Route 3 asks to projects?</div>
<div class="opt"><span class="key">1</span><span>Yes, as tasks</span></div><div class="opt"><span class="key">2</span><span>Show me first</span></div><div class="opt"><span class="key">3</span><span>Type something else</span></div></div></div>'''
    else:
        bottom = f'<div style="flex:none;padding:0 12px 12px"><div class="composer">Reply to Claude</div></div>'
    return feed + bottom


def home_chat_pane(w, tabs=("Morning triage", "Weekly status"), ask=False, header=True, border=True):
    b = f"border-right:1px solid {RULE};" if border else "height:100%;"
    return (f'<div class="chat" style="width:{w}px;flex:none;{b}">' + (home_header() if header else "") +
            chat_strip([f'{g("needs")}{e(tabs[0])}', f'{g("idle")}{e(tabs[1])}'] if len(tabs) > 1 else [e(tabs[0])]) + home_feed(ask=ask) + '</div>')


def action_column(w, needs=True, compact=False, review=True, tasks=True, hide_needs=False):
    out = []
    if needs and not hide_needs:
        out.append(f'<div class="sl" style="color:{NEEDS}">NEEDS YOU · 3</div>')
        out.append(f'<div class="card" style="border-style:dashed"><div class="top">{g("needs")}<span style="font-weight:600">Morning triage</span><span class="t2">home</span><span class="t2" style="margin-left:auto">1h</span></div><span class="t2">← Waiting in the Home pane</span></div>')
        out.append(f'<div class="card"><div class="top">{g("needs")}<span style="font-weight:600">Copy review pass 2</span><span class="t2" style="margin-left:auto">12m</span></div><span class="t2">onboarding-v3 · permission</span><div class="q">Approve these 6 string changes?</div><span class="btn">Open project</span></div>')
        if not compact:
            out.append(f'<div class="card"><div class="top">{g("needs")}<span style="font-weight:600">PRD v2 edits</span><span class="t2" style="margin-left:auto">4m</span></div><span class="t2">checkout-redesign · question</span><span style="margin:6px 0">Move saved cards into scope, or keep it out and log an open question?</span><span class="btn">Open project</span></div>')
        else:
            out.append(f'<div class="card"><div class="top">{g("needs")}<span style="font-weight:600">PRD v2 edits</span><span class="t2" style="margin-left:auto">4m</span></div><span class="t2">checkout-redesign · question</span></div>')
    if review:
        out.append(f'<div class="sl" style="margin-top:6px">READY FOR REVIEW · 2</div>')
        out.append(f'<div class="card"><div class="top">{g("review")}<span style="font-weight:600">Results readout</span></div><span class="t2">pricing-experiment-q4</span></div>')
        out.append(f'<div class="card"><div class="top">{g("review")}<span style="font-weight:600">Funnel SQL</span></div><span class="t2">onboarding-v3</span></div>')
    if tasks:
        out.append(f'<div class="sl" style="margin-top:6px">OPEN TASKS · 6</div>')
        for t, p, stt in (("Exec review prep", "checkout-redesign", "in progress"), ("Draft plan", "q4-planning", "open"), ("Legal review of saved cards", "checkout-redesign", "waiting")):
            out.append(f'<div style="display:flex;align-items:center;gap:8px;height:24px">{g("task")}<span class="ell" style="flex:1">{t}</span><span class="t2">{stt}</span></div>')
    return f'<div class="act" style="width:{w}px">{"".join(out)}</div>'


def tile(name, goal, status, sessions, star=False):
    rows = ""
    if sessions:
        for st, t, tm in sessions:
            tint = f' style="background:{TINT};margin:0 -6px;padding:0 6px"' if tm in ("working", "at prompt") else ""
            fw = ' style="font-weight:600"' if st == "needs" else ""
            rows += f'<div class="srow"{tint}>{g(GLYPH_FOR[st])}<span class="n"{fw}>{e(t)}</span><span class="t2">{e(tm)}</span></div>'
    else:
        rows = '<div class="srow t2">Nothing running</div>'
    return f'<div class="tile{" star" if star else ""}"><span class="nm">{e(name)}</span><span style="white-space:normal">{e(goal)}</span><span class="t2">{e(status)}</span><div style="margin-top:6px;display:flex;flex-direction:column">{rows}</div></div>'


TILES_A = [
    ("", [("★ home", "Triage, dispatch, status, personal ops", "Home · 2 sessions", [("needs", "Morning triage", "1h"), ("prompt", "Weekly status draft", "at prompt")], True),
          ("vendor-review", "Pick a fraud-scoring vendor", "On track", [], False)]),
    ("growth /", [("onboarding-v3", "Lift day-7 activation to 40%", "On track · Copy freeze Oct 6", [("needs", "Copy review pass 2", "12m"), ("review", "Funnel SQL", "")], False),
                  ("pricing-experiment-q4", "Decide Q4 pricing test", "On track · Readout Oct 20", [("review", "Results readout", "")], False)]),
]
TILES_B = [
    ("payments /", [("checkout-redesign", "Cut guest-checkout abandonment 15% by Q1", "On track · Exec review Oct 14", [("needs", "PRD v2 edits", "4m"), ("working", "Teardown research", "working")], False),
                    ("refunds-api-spec", "Ship refunds API spec to eng by Oct 10", "At risk · Spec review Oct 8", [("working", "Edge-case matrix", "working")], False),
                    ("fraud-rules-review", "Audit and simplify fraud rules", "On track", [("working", "Rule audit", "working")], False)]),
    ("research /", [("buyer-interviews", "Six buyer interviews, synthesised", "On track", [], False)]),
]
TILES_C = [("platform /", [("api-deprecations", "Comms plan for v1 API sunset", "Off track", [], False)]),
           ("ops /", [("q4-planning", "Q4 plan signed off by staff", "At risk · Draft due Oct 9", [], False)])]


def map_pane(cols=2, header=None, footer=True, border=True):
    groups = [TILES_A, TILES_B, TILES_C]
    if cols == 3:
        columns = [TILES_A, TILES_B, TILES_C]
    elif cols == 2:
        columns = [TILES_A + TILES_C[:1], TILES_B + TILES_C[1:]]
    else:
        columns = [TILES_A + TILES_B]
    hcols = ""
    for col in columns:
        c = ""
        for label, tiles in col:
            lab = f'<div class="sl">{g("folder") if label else ""}{e(label) if label else "&nbsp;"}</div>'
            c += f'<div style="display:flex;flex-direction:column;gap:10px;margin-bottom:10px">{lab}{"".join(tile(*t) for t in tiles)}</div>'
        hcols += f'<div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:10px">{c}</div>'
    hdr = header or f'<div class="mh"><span class="filter" style="width:200px">{g("search")}Filter folders</span><span style="flex:1"></span><span class="t2" style="font-size:12px">Sort</span><span class="popup">Recent{g("updown")}</span></div>'
    f = f'<div class="foot">{g("idle")}14 idle, resumable{g("chev")}</div>' if footer else ""
    return f'<div class="mapcol"><div style="flex:1;min-height:0;overflow:hidden;padding:16px;display:flex;flex-direction:column;gap:14px">{hdr}<div style="display:flex;gap:14px;align-items:flex-start">{hcols}</div></div>{f}</div>'


def view_toggle_hdr(board=True, rest=""):
    return (f'<span class="segc"><span class="{"on" if board else ""}" style="gap:5px">{g("board")}Board</span>'
            f'<span class="{"" if board else "on"}" style="gap:5px">{g("list")}List</span></span>{rest}')


def list_pane(w=None, two=False, needs="section", cols="full", wp=150, wt=150, header=None, sel=None, border_right=False, flex=False, chips=False):
    style = f"width:{w}px;flex:none;" if w else "flex:1;min-width:0;"
    br = f"border-right:1px solid {RULE};" if border_right else ""
    hdr = header if header is not None else list_header(width_field=(160 if two else 220), chips=chips)
    return (f'<div style="{style}{br}display:flex;flex-direction:column;min-height:0;background:{PANE}">{hdr}'
            f'<div style="flex:1;min-height:0;overflow:hidden;padding-bottom:8px">{recency_list(two=two, needs=needs, cols=cols, wp=wp, wt=wt, sel=sel)}</div></div>')


# ---------- boards ----------
BOARDS = []


def board(name, w, h, title, kind, note, body, approved=False):
    BOARDS.append(dict(name=name, w=w, h=h, title=title, kind=kind))
    doc = f'''<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="design-size" content="{w}x{h}">
<meta name="design-kind" content="{kind}">
<meta name="design-surface" content="home-evolution">
<!--
{e(title)}
STUDY BOARD [P], not approved. Drawn for the home-evolution study (2026-10-07) with the Duo design system.
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


# 0 · the study
board("00-study", 1200, 820, "0 · Home's evolution: the study", "board", "The map of the study and the prior art.", bd(1200, 820,
    "0 · Home’s evolution: what this study asks",
    "Geoff, 2026-10-07: many people will want every active and recent session in one list, with its project and task, like the Claude app’s left bar. Needs you stays. Home’s agent opens in chat, not the terminal. Every mark on these boards is a proposal [P].",
    f'''<div style="display:flex;gap:14px;align-items:flex-start">
<div class="txt" style="flex:1"><h3>The boards</h3><ol>
<li><b>The list</b> (1 to 4): a row and its density; grouping by recency, state or project; filtering; what a click does.</li>
<li><b>Where it lives</b> (5 to 8), each at 1440×900 and at 1280×800 (DL-129): A, in Home’s place; B, a Board | List toggle in the middle; C, a sidebar beside everything; D, a Sessions view like the Claude app (list, then the session itself in chat).</li>
<li><b>Needs you with the list</b> (9): the column owns it; both show it; or merged rows.</li>
<li><b>Home in chat</b> (10): the default, the strip, a question docked, falling back.</li>
<li><b>Recommendation and the v1 slice</b> (11).</li></ol>
<h3>What stays as decided</h3><ul>
<li>The five states and their glyphs, most urgent first (model.md); DL-91’s sections for a session list; DL-133’s words and tint for open sessions.</li>
<li>The action column’s cards (DL-100), the peek (DL-28), the toolbar’s counts.</li>
<li>Chat mode as decided (DL-118 to DL-120, DL-135, DL-136), the Home pill (DL-132 g).</li>
<li>Side panes keep their width and the middle flexes (DL-129).</li></ul></div>
<div class="txt" style="width:520px;flex:none"><h3>Prior art, what we take</h3><ul>
<li><b>Claude app, left bar.</b> One list of conversations by recency, title only, the open one selected; a click opens it beside the list. Claude Code’s desktop adds the repo and a running mark. <span class="p">Take: one list, recency, a click shows the session itself.</span></li>
<li><b>Linear inbox.</b> A list with an unread dot, a detail pane to the right, filters in a header, keys to move and archive. <span class="p">Take: list + detail, filters as a header, not chips everywhere.</span></li>
<li><b>Slack sidebar.</b> Sections the user orders; unread in bold; mentions as a count. <span class="p">Take: bold for what needs you; the count once.</span></li>
<li><b>Arc.</b> Pinned above, today’s below, older ones archive themselves. <span class="p">Take: Home pinned on top; Earlier folds away.</span></li>
<li><b>Superhuman.</b> Split inbox: the important ones in their own tab; done means gone. <span class="p">Take: Needs you as its own place, not a filter you forget.</span></li></ul>
<p class="note">From memory of these products, not re-checked today; prior art only.</p></div></div>'''))

# 1 · rows and density
SAMPLE = ["prd", "copy", "teardown", "weekly", "readout", "buyer", "summ"]
full_rows = "".join(row(BY[i], "full", False, 150, 150) for i in SAMPLE)
two_rows = "".join(row2(BY[i]) for i in SAMPLE)
home_row = (f'<div class="row" style="height:28px">{g("needs")}<span class="ti" style="font-weight:600">★ Home</span><span class="t2">Morning triage · 1h</span></div>')
board("01-rows", 1200, 700, "1 · A session row, two densities", "board", "Compact (one line) for the middle; two lines for a side pane.", bd(1200, 700,
    "1 · A session row: compact and two-line",
    "Every row is one session (a thread folds its forks, DL-24). Left to right: its state glyph, its title (bold while it needs you), its project, its task when it has one, and its wait, or <i>working</i> / <i>at prompt</i> while it’s open in Duo, on the open tint (DL-133). Groups don’t get rows here: a session’s task says enough, and its group shows in the project.",
    f'''<div style="display:flex;gap:24px;align-items:flex-start">
{frame('<div style="padding:6px 0">' + full_rows + '</div>', 620, None, "Compact · 26 high · a list 520 or wider", "Columns: project 150, task 150, time 64; the title takes the rest and gives way first. A session with no task leaves the column empty. Under 520 the task column goes, then the project moves under the title (two-line).")}
{frame('<div style="padding:6px 0">' + two_rows + '</div>', 320, None, "Two-line · 44 high · a side pane under 520", "Line two: project › task, in text2 12. The project name is the folder’s, ★ home for Home. Hover shows the full path and task as a tooltip.")}
<div style="display:flex;flex-direction:column;gap:14px;width:180px;flex:none">
<div class="txt"><h3>States, as built</h3>{g("needs")} needs you<br>{g("review")} ready for review<br>{g("working")} working<br>{g("idle")} idle or at prompt<br><span class="note">Open sessions sit on the tint and read <i>working</i> or <i>at prompt</i>.</span></div>
<div class="txt"><h3>Not shown [P]</h3><span class="note">Health, goal and next step stay on the board: the list is about sessions. The session’s own <code>duo2 session note</code> line could be a third line later (ENH).</span></div></div>
</div>'''))

# 2 · grouping
def state_list():
    out = [sec("Needs you", 3, True)] + [row2(BY[i]) for i in NEEDS_IDS]
    out += [sec("Ready for review", 2)] + [row2(BY[i]) for i in REVIEW_IDS]
    out += [sec("Working", 3)] + [row2(BY[i]) for i in ["teardown", "edge", "rules"]]
    out += [sec("At prompt", 2)] + [row2(BY[i]) for i in ["weekly", "footer"]]
    out += [sec("Idle")] + [row2(BY[i]) for i in ["buyer", "q4"]] + [fold("12 more")]
    return "".join(out)


def project_list():
    by = {}
    for s in S:
        by.setdefault(s["p"], []).append(s)
    out = []
    order = ["★ home", "checkout-redesign", "onboarding-v3", "refunds-api-spec", "pricing-experiment-q4", "fraud-rules-review"]
    for p in order:
        ss = by[p]
        top = min(ss, key=lambda s: ["needs", "review", "working", "prompt", "idle"].index(s["st"]))
        out.append(f'<div class="row" style="height:28px;margin-top:4px">{g("chevd")}<span class="ti" style="font-weight:600">{e(p)}</span><span class="t2">{len(ss)}</span></div>')
        for s in ss[:3]:
            out.append(f'<div style="padding-left:18px">{row(s, "bare")}</div>')
    out.append(fold("buyer-interviews · 2"))
    return "".join(out)


board("02-grouping", 1200, 860, "2 · Grouping: by recency, by state, by project", "board", "The same sessions grouped three ways.", bd(1200, 860,
    "2 · Grouping the list: recency, state, project",
    "The same sixteen sessions, three ways. A <b>Group</b> popup in the list’s header switches between them (View › Group Sessions By, <code>duo2 view list group recent|state|project</code>).",
    f'''<div style="display:flex;gap:20px;align-items:flex-start">
{frame('<div style="padding:4px 0 8px">' + recency_list(two=True) + '</div>', 360, 650, "By recency · as a project’s list (DL-91) <span class=rec>RECOMMENDED</span>", "Needs you, Open, Today, This week, Earlier, Archived: what a project’s session list already does, now across projects. Nothing new to learn; the Claude app reads the same way.")}
{frame('<div style="padding:4px 0 8px">' + state_list() + '</div>', 360, 650, "By state · the five states", "Reads like the old All projects buckets (DL-22). Good for triage; poor for “where was I”: an idle session from an hour ago sinks under week-old idle ones unless sorted by time within.")}
{frame('<div style="padding:4px 0 8px">' + project_list() + '</div>', 360, 650, "By project · folded per project", "Each project is a header with its count and its sessions under it, most urgent first, 3 then more. It is the board again as a list; useful as a filter, less as the main grouping.")}
</div>'''))

# 3 · filter and search
hdrA = list_header(220)
hdrB = list_header(160, chips=True)
filtered = (f'<div style="display:flex;align-items:center;gap:8px;height:38px;padding:0 16px;border-bottom:1px solid {RULE}"><span class="filter" style="width:220px;color:{TEXT}">{g("search")}checkout<span style="margin-left:auto" class="t2">×</span></span><span style="flex:1"></span><span class="popup">Recent{g("updown")}</span></div>'
            + sec("Needs you", 1, True) + row(BY["prd"], "full") + sec("Open", 1) + row(BY["teardown"], "full") + sec("This week") + row(BY["audit"], "full")
            + f'<div class="note" style="padding:8px 16px">Matches titles, projects, folders and tasks. For words inside sessions: <b>Search all projects ⇧⌘A</b>.</div>')
empty = (f'<div style="display:flex;align-items:center;gap:8px;height:38px;padding:0 16px;border-bottom:1px solid {RULE}"><span class="filter" style="width:220px;color:{TEXT}">{g("search")}stripe<span style="margin-left:auto" class="t2">×</span></span><span style="flex:1"></span><span class="popup">Recent{g("updown")}</span></div>'
         + f'<div style="padding:28px 16px;text-align:center;white-space:normal" class="t2">No session’s title, project or task has “stripe”.<br><span style="color:{TEXT};text-decoration:underline;text-decoration-color:{EDGE}">Search inside sessions for “stripe” ⇧⌘A</span></div>')
board("03-filter", 1200, 640, "3 · Filtering and search", "board", "A filter field in the list's header; chips as the alternative.", bd(1200, 640,
    "3 · Filtering and search",
    "The list filters itself; search stays search. Typing narrows by title, project, folder and task, as the map’s Filter folders does (<code>duo2 view filter</code> grows a list form). Words inside a session are search’s job (⇧⌘A), one click away.",
    f'''<div style="display:flex;gap:20px;align-items:flex-start">
{frame(hdrA + '<div style="padding:4px 0">' + "".join(row(BY[i], "full") for i in ["teardown", "edge", "rules"]) + '</div>', 560, None, "A · a field and the Group popup <span class=rec>RECOMMENDED</span>", "As the map’s header (DL-104). ⌘F in the list focuses it; Esc clears. The popup holds Group By and, under a rule, Show Archived.")}
{frame(hdrB + '<div style="padding:4px 0">' + "".join(row2(BY[i]) for i in ["prd", "copy", "teardown"]) + '</div>', 340, None, "B · chips under the field", "All, Needs you, Open, Tasks (sessions with a task), Project ⌄. Faster for one-click views; costs a row, and Needs you is already a section and a column.")}
<div style="display:flex;flex-direction:column;gap:16px">
{frame(filtered, 560, None, "Typed: “checkout”")}
{frame(empty, 560, None, "Nothing matches")}</div></div>'''))

# 4 · click
hover_actions = f'<span style="display:flex;gap:6px;flex:none"><span class="btn" style="height:20px;padding:0 6px;gap:4px">{g("bubble")}Open here</span><span class="btn" style="height:20px;padding:0 6px;gap:4px">{g("jump")}Project</span></span>'
c1 = ('<div style="padding:6px 0">' + row(BY["edge"], "full") + row(BY["buyer"], "proj", hover=hover_actions).replace('class="row', 'class="row sel') + row(BY["q4"], "full") + '</div>')
inplace = (f'<div class="chat" style="height:360px">'
           f'<div class="strip"><span class="tab" style="color:{TEXT}">‹ List</span><span class="tab on">{g("idle")}Buyer synthesis</span><span class="tab">buyer-interviews</span>'
           f'<span style="display:flex;align-items:center;gap:8px;margin-left:auto"><span class="btn" style="height:20px;padding:0 8px;gap:5px">{g("jump")}Open in Project</span><span class="pill"><span>{g("term")}</span><span class="on">{g("bubble")}</span></span></span></div>'
           f'<div class="feed" style="padding:14px 20px 12px"><div style="margin-right:36px;display:flex;flex-direction:column;gap:4px"><div class="who">Claude · 2h</div><div class="ccard"><div>The memo’s draft is in <u>synthesis/memo.md</u>: four themes, each with two quotes. The pricing theme is the weakest; one more interview would settle it.</div></div></div></div>'
           f'<div style="flex:none;padding:0 16px 12px"><div class="composer">Reply to Claude · resumes the session</div></div></div>')
board("04-click", 1200, 700, "4 · What a click does", "board", "Jump to the project, or open the session in place.", bd(1200, 700,
    "4 · What a row does on click",
    "Two ways, both kept: the click picks one, the other is on hover, the right-click menu and a key. The right-click menu is the session menu as everywhere (DL-108). Return opens, ⌘↩ jumps.",
    f'''<div style="display:flex;gap:24px;align-items:flex-start">
<div style="display:flex;flex-direction:column;gap:16px">
{frame(c1, 600, None, "Hover · the row’s two actions", "Open here shows the session beside the list (D, or the middle in B); Project jumps into its project with the session selected, as a tile’s session row does today (ENH-5’s way in).")}
<div class="txt" style="width:600px"><h3>Which is the click? [P]</h3><ul>
<li><b>Jump to the project</b>: what a session on a tile does today. Simple; leaves All projects. Right for B (the list replaces the board in the middle, so there’s nowhere to open it).</li>
<li><b>Open in place</b>: the Claude-app way. The session shows in chat beside the list without leaving All projects; ⌘↩ or <i>Open in Project</i> goes in. Right for D. A session that isn’t running resumes only when you send something.</li></ul>
<p class="note">Verbs: <code>duo2 session open &lt;id&gt; --here</code> (open in place), <code>duo2 open &lt;project&gt; &lt;session&gt;</code> (jump, exists).</p></div></div>
{frame(inplace, 540, None, "Open in place · the session in chat, the list kept", "The strip: ‹ List (narrow windows only), the session, its project as a link, Open in Project, and the Terminal / Chat pill. Its mode is the session’s own (DL-119 (5)).")}
</div>'''))

# 5..8 · where it lives
def where_a(w, h):
    left = 300 if w < 1440 else 340
    act = 340
    seg = (f'<div style="height:36px;flex:none;display:flex;align-items:center;gap:10px;padding:0 12px 0 16px;border-bottom:1px solid {RULE};background:{GROUND}">'
           f'<span class="segc"><span>★ Home</span><span class="on">Sessions</span></span><span style="flex:1"></span><span class="t2" style="font-size:12px">⌃⌘S</span></div>')
    lp = (f'<div style="width:{left}px;flex:none;border-right:1px solid {RULE};display:flex;flex-direction:column;min-height:0">{seg}'
          f'{list_header(150)}<div style="flex:1;min-height:0;overflow:hidden">{recency_list(two=True, needs="pointer")}</div></div>')
    return window(w, h, lp + map_pane(2 if w >= 1440 else 2) + action_column(act, compact=w < 1440))


def where_b(w, h, list_on=True):
    act = 340
    home = 340
    hdr = f'<div class="mh">{view_toggle_hdr(board=not list_on)}<span class="filter" style="width:200px">{g("search")}{"Filter sessions" if list_on else "Filter folders"}</span><span style="flex:1"></span><span class="t2" style="font-size:12px">{"Group" if list_on else "Sort"}</span><span class="popup">Recent{g("updown")}</span></div>'
    if list_on:
        mid_w = w - home - act
        full = mid_w >= 600
        middle = (f'<div class="mapcol"><div style="flex:none;padding:16px 16px 8px">{hdr}</div><div style="flex:1;min-height:0;overflow:hidden">'
                  f'{recency_list(two=False, needs="pointer", cols=("full" if full else "proj"), wp=(150 if mid_w > 700 else 130), wt=(150 if mid_w > 700 else 120))}</div></div>')
    else:
        middle = map_pane(2, header=hdr)
    return window(w, h, home_chat_pane(home) + middle + action_column(act, compact=w < 1440))


def where_c(w, h):
    side = 260
    sp = (f'<div style="width:{side}px;flex:none;border-right:1px solid {RULE};display:flex;flex-direction:column;min-height:0;background:{GROUND}">'
          f'<div style="display:flex;align-items:center;gap:8px;height:38px;flex:none;padding:0 12px;border-bottom:1px solid {RULE}"><span class="filter" style="flex:1">{g("search")}Filter sessions</span></div>'
          f'<div style="flex:1;min-height:0;overflow:hidden">{recency_list(two=True, needs="pointer")}</div></div>')
    if w >= 1440:
        body = sp + home_chat_pane(300) + map_pane(1) + action_column(340, compact=True)
    else:
        # below 1440 Home's pane gives way: Home is the sidebar's first row and opens in the middle
        sp2 = sp.replace(sec("Needs you", 3, True), sec("Needs you", 3, True), 1)
        body = sp2 + map_pane(2) + action_column(340, compact=True)
    return window(w, h, body)


def where_d(w, h):
    lw = 300 if w < 1440 else 320
    act = 340 if w >= 1440 else 300
    homerow = (f'<div class="row sel" style="height:30px;margin-top:8px">{g("needs")}<span class="ti" style="font-weight:600">★ Home</span><span class="t2">Morning triage</span></div>')
    lp = (f'<div style="width:{lw}px;flex:none;border-right:1px solid {RULE};display:flex;flex-direction:column;min-height:0">{list_header(150)}'
          f'<div style="flex:1;min-height:0;overflow:hidden">{homerow}{recency_list(two=True, needs="pointer")}</div></div>')
    middle = (f'<div class="chat" style="flex:1;border-right:1px solid {RULE}">' + home_header() +
              chat_strip([f'{g("needs")}Morning triage', f'{g("idle")}Weekly status']) + home_feed(narrow=False) + '</div>')
    return window(w, h, lp + middle + action_column(act, compact=True, tasks=w >= 1440), tb=toolbar(view_toggle=(False, True)))


for key, fn, title, note in (
    ("05-where-a", where_a, "5 · A · The list in Home’s place", "The left pane switches between Home and Sessions."),
    ("06-where-b", where_b, "6 · B · Board | List in the middle", "The map's header toggles the middle between the board and the list; Home stays left in chat."),
    ("07-where-c", where_c, "7 · C · A sessions sidebar beside everything", "A persistent sidebar left of Home, the board and the column."),
    ("08-where-d", where_d, "8 · D · A Sessions view, like the Claude app", "All projects gets two views; Sessions is list | the selected session in chat | needs you."),
):
    for (w, h) in ((1440, 900), (1280, 800)):
        board(f"{key}-{w}", w, h, f"{title} · {w}×{h}", "target", note, fn(w, h))

# board variant of B with the board showing
board("06-where-b-board-1440", 1440, 900, "6 · B · Board | List in the middle, Board chosen · 1440×900", "target",
      "The same window with Board chosen: today's map, Home in chat.", where_b(1440, 900, list_on=False))

# where-it-lives summary board
def thumb(label, rec=False, desc="", parts=()):
    blocks = "".join(f'<div style="flex:{f};background:{c};border-right:1px solid {RULE};display:flex;align-items:flex-start;justify-content:center;padding-top:8px;font-size:11px;line-height:14px;color:{TEXT2};white-space:normal;text-align:center">{t}</div>' for f, c, t in parts)
    return (f'<div style="display:flex;flex-direction:column;gap:8px;width:260px;flex:none"><div class="cap">{label}{"<span class=rec>RECOMMENDED</span>" if rec else ""}</div>'
            f'<div class="frame" style="height:150px;flex-direction:row">{blocks}</div><div class="note">{desc}</div></div>')


board("05-where-summary", 1200, 560, "5–8 · Where it lives, side by side", "board", "The four placements as diagrams with their trade-offs.", bd(1200, 560,
    "5–8 · Where the list lives",
    "Each is drawn as a window at 1440×900 and 1280×800 on the next boards. Needs you persists in every one (the right column).",
    '<div style="display:flex;gap:20px">' +
    thumb("A · In Home’s place", False, "The left pane switches Home | Sessions. The list is narrow (two-line rows) and Home’s agent hides while you browse. Cheap; but the two compete for one pane, and Home loses its always-on place.",
          [(1, GROUND, "Home | Sessions"), (2, PANE, "board"), (1, PANE, "needs you")]) +
    thumb("B · Board | List in the middle", True, "The middle switches Board | List. Home stays left, in chat; the column stays right. The list gets 600–760 for compact rows with project and task columns. Click jumps into the project. Smallest change; works at 1280.",
          [(1, GROUND, "Home (chat)"), (2, PANE, "board ⇄ list"), (1, PANE, "needs you")]) +
    thumb("C · A sidebar beside it all", False, "A list down the far left, at both altitudes. Four panes don’t fit at 1280: Home’s pane gives way and becomes the list’s first row. Duplicates a project’s own list inside a project.",
          [(0.8, GROUND, "sessions"), (1, GROUND, "Home"), (1.6, PANE, "board"), (1, PANE, "needs you")]) +
    thumb("D · A Sessions view", False, "Board | Sessions in the toolbar. Sessions is list | the session in chat | needs you: the Claude app’s shape. Home is the pinned first row and the default conversation. Most like what Geoff described; the biggest build (any session shown at All projects).",
          [(0.9, PANE, "list, ★ Home first"), (2, GROUND, "selected session (chat)"), (0.9, PANE, "needs you")]) +
    '</div>'))

# 9 · needs you with the list
def ny_pair(mode, cap, note, rec=False):
    if mode == "pointer":
        lst = recency_list(two=False, needs="pointer", cols="proj", wp=130)
        col = action_column(300, compact=True, tasks=False)
    elif mode == "both":
        out = [sec("Open", 6)] + [row(BY[i], "proj", False, 130) for i in ["copy", "teardown", "edge", "rules", "weekly", "footer"]]
        out += [sec("Today")] + [row(BY[i], "proj", False, 130) for i in ["prd", "readout", "funnel", "buyer"]]
        lst = "".join(out)
        col = action_column(300, compact=True, tasks=False)
    else:
        lst = recency_list(two=False, needs="merged", cols="proj", wp=130)
        col = action_column(300, needs=False, tasks=True)
    content = f'<div style="display:flex;height:520px"><div style="flex:1;min-width:0;overflow:hidden;padding-bottom:8px">{lst}</div>{col}</div>'
    return frame(content, 760, None, cap + ("<span class=rec>RECOMMENDED</span>" if rec else ""), note)


board("09-needs-you", 1620, 1240, "9 · Needs you beside the list, without counting twice", "board", "Three ways the list and the column share needs-you sessions.", bd(1620, 1240,
    "9 · Needs you with the list, counted once",
    "The toolbar’s count, the Dock badge and <code>duo2 needs-you</code> count each session once whatever the list does. The question is whether the list repeats what the column holds.",
    f'''<div style="display:flex;gap:20px;align-items:flex-start">
<div style="display:flex;flex-direction:column;gap:18px">
{ny_pair("pointer", "N1 · The column owns them", "The list leaves needs-you sessions out of its sections and starts with one line, <b>3 need you</b>, that selects the first card in the column. With the right pane hidden (⌥⌘0) the line opens into the rows themselves, so nothing is lost. Each session is listed once on screen.", True)}
{ny_pair("both", "N2 · Both show them, in their own way", "The list keeps every session in its time section, marked with the needs-you glyph; the column shows the question. Simple, but the same three sessions sit twice on screen and the eye counts them twice.")}
</div>
<div style="display:flex;flex-direction:column;gap:18px">
{ny_pair("merged", "N3 · Merged into the list", "The list’s Needs you section carries each question under its row, with Open; the column keeps Ready for review and Open tasks. One place, but the list then has to be wide, and Needs you stops being the same column at every altitude (the peek, DL-28, is the column’s twin).")}
<div class="txt" style="width:760px"><h3>Inside a project, unchanged</h3><p>A project’s list keeps its Needs you section (DL-91): there is no column there. The peek (Needs You Elsewhere, DL-28) still lists the other projects’ waits.</p>
<h3>Home’s own wait</h3><p>Home’s session needing you stays the dashed card “← Waiting in the Home pane” (built), and in the list it counts like any other.</p></div>
</div></div>'''))

# 10 · Home in chat
def home_states():
    a = home_chat_pane(340, border=False)
    b = home_chat_pane(340, ask=True, border=False)
    fb = (f'<div class="chat" style="width:340px;height:100%">{home_header()}<div class="strip" style="background:{CONSOLE};border-color:{CRULE}"><span class="tab" style="color:{CTEXT};font-weight:500">{g("needs", "#F97316")}Morning triage</span>'
          f'<span style="display:flex;align-items:center;margin-left:auto"><span class="pill" style="background:{CONSOLE};border-color:#4A4F57"><span style="background:{CRULE};color:{CTEXT}">{g("term")}</span><span style="color:{CTEXT2}">{g("bubble")}</span></span></span></div>'
          f'<div style="display:flex;align-items:center;gap:10px;padding:8px 12px;background:{GROUND};border-bottom:1px solid {RULE};white-space:normal;font-size:12px;line-height:16px"><span style="flex:1">Chat can’t show this screen, so here’s the terminal. Chat comes back when it closes.</span><span class="btn">Back to Chat</span></div>'
          f'<div class="mono" style="flex:1;background:{CONSOLE};color:{CTEXT};padding:12px 14px;white-space:pre"> <b>Select model</b>\n   1. Default (recommended)\n ❯ 2. Opus\n   3. Sonnet\n\n <span style="color:{CTEXT2}">Enter to set · Esc to cancel</span></div></div>')
    return a, b, fb


ha, hb, hf = home_states()
board("10-home-chat", 1500, 900, "10 · Home's agent in chat by default", "board", "Home in chat at 340: talking, a question docked, falling back.", bd(1500, 900,
    "10 · Home’s agent opens in chat",
    "Home’s pane follows the console: in chat its strip is DL-136’s thin light strip, with the Terminal / Chat pill at the right (DL-132 (g)), and its header turns light to match. A terminal tab keeps today’s dark strip.",
    f'''<div style="display:flex;gap:20px;align-items:flex-start">
{frame(ha, 340, 700, "Talking", "Claude’s cards keep 24 free on the right at this width (the Q-57 board); hints are dropped from the composer below 480 (DL-129).")}
{frame(hb, 340, 700, "A question docked", "Review cards dock in the composer’s place (DL-119 (3)), full width; Home’s tab shows the needs-you glyph, and the column’s dashed card points here.")}
{frame(hf, 340, 700, "Fallen back", "Anything chat can’t show goes to the terminal with the bar (DL-119 (6)); the strip turns dark with it.")}
<div class="txt" style="flex:1"><h3>What changes for the Home session [P]</h3><ul>
<li><b>New Home sessions open in chat</b>, including the one Duo starts on launch (DL-54). Elsewhere, a new session still opens in the mode used last (DL-119 (5)).</li>
<li>Each Home session keeps its own mode once switched, as every session does.</li>
<li>The fallback rules don’t change: anything chat can’t show, pasted images (Q-56 e) and plan feedback hand over to the terminal, and chat comes back by itself when it left by itself.</li>
<li>At 280 (Home’s minimum, DL-129) previews in a question stack and the review card’s footer wraps (Q-56 d).</li>
<li><code>duo2 session chat --default</code> gains a Home form: <code>--home chat|terminal|last</code>; Settings › General gets “Home opens in: Chat / Terminal”.</li>
<li>With no Home folder, the pane is unchanged: “Choose a Home folder” (DL-84, DL-100).</li></ul>
<h3>Changed from the Q-57 board</h3><p class="note">Q-57’s board drew the pill on Home’s dark tab row. DL-136 came after it for the console; this proposes the same light strip for Home while chat shows. Flagged to the stand-ins session.</p></div>
</div>'''))

# 11 · recommendation
board("11-recommendation", 1200, 880, "11 · Recommendation and the v1 slice", "board", "B with recency grouping, N1, Home in chat; D later.", bd(1200, 880,
    "11 · Recommendation and the v1 slice",
    "Recommended: <b>B</b> (Board | List in the middle), grouped <b>by recency</b> like a project’s list, Needs you <b>owned by the column</b> (N1), Home <b>in chat</b> by default. Then <b>D</b> as the next step, once the list has been used.",
    f'''<div style="display:flex;gap:16px;align-items:flex-start">
<div class="txt" style="flex:1"><h3>Why B first</h3><ul>
<li>Keeps the three things Geoff named: Home’s agent (left, now in chat), the board (one click away), and Needs you (right, unchanged).</li>
<li>The list gets the middle’s width, so a row carries project and task on one line, and it fits the 1280×800 window without anything giving way.</li>
<li>Everything in it exists: DL-91’s sections, the row, the tint, the filter field, the map header. It’s a new arrangement, not a new language.</li>
<li>A click jumps into the project, as a tile’s session row does, so there’s no new navigation to learn.</li></ul>
<h3>Why D next, not now</h3><ul>
<li>D is the Claude app’s shape, and the most like Geoff’s note. It needs any session shown at All projects (Home’s pane hosting other projects’ sessions), which touches the multi-window study’s question of where Home lives.</li>
<li>B’s list is D’s list: the same rows, grouping and filter. Building B builds most of D.</li></ul>
<h3>Not recommended</h3><p>A (Home and the list fight over one pane) and C (four panes don’t fit at 1280; it duplicates a project’s own list).</p></div>
<div class="txt" style="width:520px;flex:none"><h3>v1 slice [P]</h3><ol>
<li><b>Home opens in chat</b>: new Home sessions in chat; the light strip and header (board 10). <code>duo2 session chat --home</code>.</li>
<li><b>Board | List</b> in the map’s header, remembered; first launch shows List. <code>duo2 view home board|list|toggle</code>; View › Show Board / Show List (⌘1 / ⌘2 [P]).</li>
<li><b>The list</b>, compact rows (board 1), grouped by recency (DL-91 sections across projects), Earlier and Archived folded.</li>
<li><b>Filter sessions</b> field (board 3 A): title, project, folder, task. <code>duo2 view filter</code> applies to whichever is showing.</li>
<li><b>N1</b>: needs-you sessions in the column only; the list’s “3 need you” line; opens into rows when the right pane is hidden.</li>
<li><b>Click jumps</b> into the project with the session selected; right-click is the session menu; Return / ⌘↩ as board 4.</li></ol>
<h3>Later</h3><ul><li>ENH-28: D, a Sessions view with sessions opened in place.</li><li>ENH-29: Group By state and project; chips; the session’s note as a third line.</li></ul>
<h3>Open (Q-100 to Q-104)</h3><ul><li>Q-100 Home’s strip in chat: light (this study) or Q-57’s dark row.</li><li>Q-101 Default view on first launch: List or Board.</li><li>Q-102 Narrow (two-line) rows: when the middle is under 520.</li></ul></div>
</div>'''))

with open(os.path.join(OUT, "manifest.json"), "w") as f:
    json.dump(BOARDS, f, indent=1)
print(f"{len(BOARDS)} boards in {OUT}")
