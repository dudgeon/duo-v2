#!/usr/bin/env python3
"""Draws the task board study boards (every mark [P]) as static HTML in the Duo design system.

    python3 docs/design/task-board-study/canvas/make.py
    bash docs/design/task-board-study/canvas/render.sh

Colours are the light and console tokens of docs/design/build-handoff/tokens.json, by value, as the
exported screens are. The shared CSS and glyphs are copied from home-evolution-handoff/canvas/make.py.
Names and data are illustrative.
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
.chip{{white-space:nowrap;display:inline-flex;align-items:center;gap:5px;height:22px;padding:0 9px;border:1px solid {RULE};border-radius:11px;font-size:12px;line-height:16px;color:{TEXT2};background:{PANE}}}
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

# ---------- the task board study ----------
OUT = os.path.join(HERE, "boards")
STUDY = "task-board"


def e(s):
    return html.escape(s, quote=False)


def sec(label, n=None, ny=False):
    t = label.upper() + (f" · {n}" if n is not None else "")
    return f'<div class="sec{" ny" if ny else ""}">{t}</div>'


def fold(label):
    return f'<div class="fold">{g("chev")}{e(label)}</div>'


def box(checked=False, color=None):
    c = color or TEXT2
    tick = f'<path d="M2.8 5.2 4.4 6.8 7.4 3.4" fill="none" stroke="{c}" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/>' if checked else ""
    return f'<svg width="10" height="10" viewBox="0 0 10 10" style="flex:none"><rect x="1" y="1" width="8" height="8" rx="2" fill="none" stroke="{c}" stroke-width="1.3"/>{tick}</svg>'


def plus(color=None):
    return f'<svg width="10" height="10" viewBox="0 0 10 10" style="flex:none"><path d="M5 1.5v7M1.5 5h7" stroke="{color or TEXT2}" stroke-width="1.4" stroke-linecap="round"/></svg>'


def person():
    return f'<svg width="10" height="10" viewBox="0 0 10 10" style="flex:none"><circle cx="5" cy="3.4" r="2" fill="none" stroke="{TEXT2}" stroke-width="1.2"/><path d="M1.5 9c.4-1.9 1.8-2.9 3.5-2.9S8.1 7.1 8.5 9" fill="none" stroke="{TEXT2}" stroke-width="1.2" stroke-linecap="round"/></svg>'


def cal(color=None):
    c = color or TEXT2
    return f'<svg width="10" height="10" viewBox="0 0 10 10" style="flex:none"><rect x="1" y="1.8" width="8" height="7.2" rx="1.5" fill="none" stroke="{c}" stroke-width="1.2"/><path d="M1 4h8M3.3.8v2M6.7.8v2" stroke="{c}" stroke-width="1.2"/></svg>'


def grip():
    d = "".join(f'<circle cx="{x}" cy="{y}" r=".9" fill="{EDGE}"/>' for x in (2, 5) for y in (2, 5, 8))
    return f'<svg width="7" height="10" viewBox="0 0 7 10" style="flex:none">{d}</svg>'


EXTRA_CSS = f"""
.lane{{display:flex;flex-direction:column;gap:6px;min-width:0;flex:1}}
.lh{{display:flex;align-items:center;gap:6px;height:22px;padding:0 4px;font:600 11px/16px -apple-system,system-ui,sans-serif;letter-spacing:.66px;color:{TEXT2};text-transform:uppercase;white-space:nowrap}}
.lb{{display:flex;flex-direction:column;gap:6px;background:{GROUND};border-radius:6px;padding:6px;flex:1;min-height:0}}
.tc{{background:{PANE};border:1px solid {RULE};border-radius:6px;padding:8px 10px 9px;display:flex;flex-direction:column;gap:3px;white-space:normal;min-width:0}}
.tc .tt{{display:flex;align-items:flex-start;gap:7px;font-weight:600;line-height:18px}}
.tc .tt svg{{margin-top:4px}}
.tc .mt{{display:flex;flex-wrap:wrap;align-items:center;gap:4px 10px;font-size:12px;line-height:16px;color:{TEXT2};padding-left:17px}}
.tc .mt span{{display:inline-flex;align-items:center;gap:4px;white-space:nowrap}}
.tc .ss{{display:flex;align-items:center;gap:6px;font-size:12px;line-height:16px;color:{TEXT2};padding-left:17px;white-space:nowrap;min-width:0}}
.tc.sel{{border-color:{TEXT}}}
.tc.ghost{{border:1px dashed {EDGE};background:transparent;color:{TEXT2}}}
.tc.lift{{box-shadow:0 12px 32px rgba(31,35,40,0.22);transform:rotate(-1.5deg)}}
.tc.done .tt{{color:{TEXT2};font-weight:400}}
.drop{{border:1px dashed {EDGE};border-radius:6px;height:40px;display:flex;align-items:center;justify-content:center;font-size:12px;color:{TEXT2}}}
.ltab{{display:flex;align-items:center;gap:22px;height:36px;flex:none;padding:0 20px;border-bottom:1px solid {RULE};font-size:13px;color:{TEXT2}}}
.ltab .on{{color:{TEXT};font-weight:600}}
.pb{{background:{GROUND};border-radius:6px;padding:8px 12px;margin:0 0 12px;display:flex;flex-direction:column}}
.pb .pl{{display:flex;align-items:center;gap:10px;min-height:22px;font-size:12px;line-height:16px}}
.pb .pl .k{{width:84px;color:{TEXT2};flex:none}}
.ctab{{display:flex;align-items:center;gap:22px;height:36px;flex:none;padding:0 20px;background:{CONSOLE};border-bottom:1px solid {CRULE};color:{CTEXT2}}}
.ctab .on{{color:{CTEXT}}}
.cl{{color:{CTEXT}}}
.diffl{{font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:12px;line-height:19px;white-space:pre}}
.diffl .del{{background:#FDECEA;color:#B42318;display:block;padding:0 8px}}
.diffl .add{{background:#E6F4EA;color:#2F7D32;display:block;padding:0 8px}}
.diffl .ctx{{color:{TEXT2};display:block;padding:0 8px}}
.opt3{{display:flex;flex-direction:column;gap:10px;flex:1;min-width:0}}
.verdict{{font:600 11px/16px -apple-system,system-ui,sans-serif;letter-spacing:.4px;border:1px solid {TEXT};border-radius:9px;padding:0 7px;align-self:flex-start}}
.verdict.no{{border-color:{EDGE};color:{TEXT2}}}
table.cmp{{border-collapse:collapse;width:100%;font-size:12px;line-height:17px;white-space:normal}}
table.cmp th,table.cmp td{{border-top:1px solid {RULE};padding:7px 10px 7px 0;text-align:left;vertical-align:top}}
table.cmp th{{font-weight:600;color:{TEXT2};width:150px}}
table.cmp thead th{{font:600 11px/16px -apple-system,system-ui,sans-serif;letter-spacing:.66px;text-transform:uppercase;color:{TEXT};border-top:none}}
"""

# ---------- data (illustrative) ----------
# lane, title, owner, due, due_note, waiting, sessions [(state,title,time)], needs
T = {
    "open": [
        dict(t="Pricing page copy", o="Geoff", due="Oct 18"),
        dict(t="Refund flow edge cases", o="Sam Ortiz", ss=[("idle", "Edge-case matrix", "2d")]),
        dict(t="Pull the top three quotes", o="Geoff"),
    ],
    "in-progress": [
        dict(t="PRD v2", o="Geoff", due="Oct 10", ss=[("needs", "PRD v2 edits", "4m"), ("working", "", ""), ("idle", "", "")], needs=True),
        dict(t="Exec review prep", o="Geoff", due="Oct 14", ss=[("working", "Teardown research", "working"), ("idle", "", "")]),
        dict(t="Competitor teardown", o="Geoff", ss=[("prompt", "Shopify teardown", "at prompt")]),
    ],
    "waiting": [
        dict(t="Analytics events spec", o="Geoff", due="Oct 3", over=True, w="Data team"),
        dict(t="Legal review of saved cards", o="Geoff", due="Oct 9", w="Priya Shah", ss=[("idle", "Retention wording", "1d")]),
    ],
    "review": [
        dict(t="Checkout copy audit", o="Geoff", due="Oct 12", ss=[("review", "Copy audit pass", "25m")]),
    ],
    "done": [
        dict(t="Interview synthesis", o="Geoff", done="Oct 5", ss=[("idle", "", "")]),
        dict(t="Funnel baseline", o="Sam Ortiz", done="Oct 2"),
    ],
}
LANES = [("open", "Open"), ("in-progress", "In progress"), ("waiting", "Waiting"), ("review", "Review"), ("done", "Done")]


def card(c, sel=False, cls="", compact=False, hover=False):
    k = "tc" + (" sel" if sel else "") + (f" {cls}" if cls else "")
    done = "done" in c
    title = f'<div class="tt">{box(done)}<span style="flex:1;min-width:0">{e(c["t"])}</span>'
    if hover:
        title += f'<span style="width:18px;height:18px;border-radius:4px;display:flex;align-items:center;justify-content:center;flex:none;margin-top:0">{plus()}</span>'
    title += '</div>'
    meta = []
    if c.get("w"):
        meta.append(f'<span>waiting on {e(c["w"])}</span>')
    if c.get("o") and c.get("o") != "Geoff":
        meta.append(f'<span>{person()}{e(c["o"])}</span>')
    if c.get("due"):
        if c.get("over"):
            meta.append(f'<span style="color:{TEXT};font-weight:600">{cal(TEXT)}{e(c["due"])} · overdue</span>')
        else:
            meta.append(f'<span>{cal()}{e(c["due"])}</span>')
    if c.get("done"):
        meta.append(f'<span>done {e(c["done"])}</span>')
    ss0 = c.get("ss") or []
    if len(ss0) > 1 and not c.get("done") and not compact:
        meta.append(f'<span>{len(ss0)} sessions</span>')
    out = title
    if meta:
        out += f'<div class="mt">{"".join(meta)}</div>'
    ss = c.get("ss") or []
    if ss and not compact:
        lead = ss[0]
        glyphs = "".join(g(GLYPH_FOR[s[0]]) for s in ss)
        if lead[1] and not done:
            col = f'color:{NEEDS};font-weight:600;' if lead[0] == "needs" else f"color:{TEXT};"
            tm = f'<span style="margin-left:auto;color:{TEXT2};font-weight:400">{e(lead[2])}</span>' if lead[2] else ""
            more = ""
            out += f'<div class="ss" style="{col}">{g(GLYPH_FOR[lead[0]])}<span class="ell">{e(lead[1])}</span>{more}{tm}</div>'
        else:
            n = len(ss)
            out += f'<div class="ss">{glyphs}<span>{n} session{"s" if n > 1 else ""}</span></div>'
    return f'<div class="{k}">{out}</div>'


def lane(key, label, cards_html, n=None, extra="", hdr_extra=""):
    cnt = f" · {n}" if n is not None else ""
    return (f'<div class="lane"><div class="lh"><span>{e(label)}{cnt}</span>{hdr_extra}</div>'
            f'<div class="lb">{cards_html}{extra}</div></div>')


def lanes(w, keys=None, sel=None, done_folds=True, lane_w=None, ghost=None, lift=None, drop_into=None, hover=None, dense=False):
    keys = keys or [k for k, _ in LANES]
    out = []
    for k, label in LANES:
        if k not in keys:
            continue
        cs = T[k]
        body = ""
        for c in cs:
            if lift and c["t"] == lift:
                body += card(c, cls="ghost") .replace('class="tc ghost"', 'class="tc ghost" style="opacity:.55"')
                continue
            body += card(c, sel=(c["t"] == sel), hover=(c["t"] == hover), compact=dense)
            if drop_into == k and c["t"] == T[k][0]["t"] and ghost:
                pass
        if drop_into == k and ghost:
            slot = '<div class="tc ghost" style="height:58px;justify-content:center;font-size:12px">lands here: due Oct 18, after Oct 14</div>'
            parts = [card(c, sel=(c["t"] == sel), compact=dense) for c in cs]
            parts.insert(int(ghost), slot)
            body = "".join(parts)
        extra = ""
        if k == "done" and done_folds:
            extra = f'<div class="fold" style="padding:0 4px;height:24px;font-size:12px">{g("chev")}Earlier · 4</div><div class="fold" style="padding:0 4px;height:24px;font-size:12px">{g("chev")}Dropped · 1</div>'
        style = f' style="flex:none;width:{lane_w}px"' if lane_w else ""
        n = len(cs) + (4 if k == "done" and done_folds else 0) if k != "done" else len(cs)
        h = lane(k, label, body, len(cs), extra)
        if drop_into == k:
            h = h.replace('class="lb"', f'class="lb" style="background:{SELECTED};outline:1px dashed {EDGE};outline-offset:-1px"')
        out.append(h.replace('class="lane"', f'class="lane"{style}', 1))
    return f'<div style="display:flex;gap:10px;flex:1;min-height:0;padding:10px 16px 16px;overflow:hidden">{"".join(out)}</div>'


def board_header(extra="", n=11, filter_w=180):
    return (f'<div style="display:flex;align-items:center;gap:8px;height:38px;flex:none;padding:0 16px;border-bottom:1px solid {RULE}">'
            f'<span class="sl">Tasks · {n}</span>'
            f'<span class="filter" style="width:{filter_w}px;margin-left:8px">{g("search")}Filter tasks</span>'
            f'<span class="popup">Anyone{g("updown")}</span>'
            f'<span style="flex:1"></span>{extra}<span class="btn" style="align-self:center;height:22px">+ New task</span></div>')


# ---------- the project window ----------
def ptoolbar(crumb="checkout-redesign", toggle=None):
    vt = ""
    if toggle:
        vt = (f'<span class="segc" style="margin-left:10px"><span class="{"on" if toggle == "sessions" else ""}" style="gap:5px">{g("term")}Sessions</span>'
              f'<span class="{"on" if toggle == "board" else ""}" style="gap:5px">{g("board")}Tasks</span></span>')
    return f'''<div class="tb">
<span class="tl"><i style="background:#FF5F57"></i><i style="background:#FEBC2E"></i><i style="background:#28C840"></i></span>
<span class="tgl">{g("sidebar")}</span>
<span style="text-decoration:underline;color:{TEXT2}">All projects</span>{g("chev")}<span class="t2">Payments</span>{g("chev")}<span style="font-weight:600">{crumb}</span>{vt}
<span style="margin-left:8px;display:inline-flex;align-items:center;gap:6px;height:22px;padding:0 8px;border:1.5px solid {NEEDS};border-radius:6px;color:{NEEDS};font-weight:600;font-size:12px">{g("needs")}2 need you</span>
<span class="srch">{g("search")}Search all projects<span style="margin-left:auto">⇧⌘A</span></span>
<span class="tgl" style="margin-left:4px">{g("right")}</span>
</div>'''


def srow(st, t, tm, ind=0, bold=False, tint=False, pill=None):
    b = ' style="font-weight:600"' if bold or st == "needs" else ""
    pl = f'<span class="chip" style="height:18px;padding:0 7px;font-size:11px">{pill}</span>' if pill else ""
    return (f'<div class="row{" tint" if tint else ""}" style="padding-left:{8 + ind}px">{g(GLYPH_FOR.get(st, st)) if st != "task" else box()}'
            f'<span class="ti"{b}>{e(t)}</span>{pl}<span class="tm t2">{e(tm)}</span></div>')


def left_pane(tasks_mode="fold", w=300, board_btn=False):
    out = [f'<div style="padding:14px 16px 6px"><div style="font-weight:600;font-size:14px">checkout-redesign</div><div class="t2">On track · Exec review Oct 14</div></div>']
    out.append(sec("Needs you", 1, True))
    out.append(srow("needs", "PRD v2 edits", "4m"))
    out.append(sec("Open", 2))
    out.append(srow("working", "Teardown research", "working", tint=True))
    out.append(srow("prompt", "Shopify teardown", "at prompt", tint=True))
    out.append(sec("Today"))
    out.append(srow("review", "Copy audit pass", "25m"))
    out.append(srow("idle", "Retention wording", "1d"))
    out.append(fold("Earlier · 6"))
    if tasks_mode == "fold":
        bb = f'<span style="margin-left:auto;display:flex;align-items:center;gap:4px;color:{TEXT2};font-size:12px">{g("board")}Board</span>' if board_btn else ""
        out.append(f'<div class="fold">{g("chevd")}Tasks · 3{bb}</div>')
        out.append(srow("task", "Pricing page copy", "", ind=18))
        out.append(srow("task", "Pull the top three quotes", "", ind=18))
        out.append(srow("task", "Analytics events spec", "waiting", ind=18))
    elif tasks_mode == "stacked":
        out.append(stacked_tasks())
    out.append(fold("Archived · 1"))
    out.append(f'<div style="display:flex;gap:8px;padding:10px 16px"><span class="btn">+ New session</span><span class="btn">+ New task</span></div>')
    files = (f'<div style="margin-top:auto;border-top:2px solid {EDGE};padding:10px 16px 8px"><div class="sl">Files</div><div class="mono t2" style="font-size:11px">~/work/payments/checkout-redesign</div>'
             f'<div class="mono" style="margin-top:6px">PROJECT.md</div><div class="mono" style="display:flex;gap:6px;align-items:center">{g("chev")}docs/</div><div class="mono" style="display:flex;gap:6px;align-items:center">{g("chev")}tasks/</div></div>')
    return f'<div style="width:{w}px;flex:none;border-right:1px solid {RULE};display:flex;flex-direction:column;min-height:0;overflow:hidden">{"".join(out)}{files}</div>'


def stacked_tasks(drag=False):
    """C: the Tasks fold grouped by status (a vertical board)."""
    out = [f'<div class="fold">{g("chevd")}Tasks · 11<span style="margin-left:auto;font-size:12px" class="t2">by status</span></div>']
    for k, label in LANES[:4]:
        out.append(f'<div class="sec" style="padding:6px 16px 2px 34px">{label.upper()} · {len(T[k])}</div>')
        for c in T[k]:
            st = c.get("ss", [("task",)])[0][0] if c.get("ss") and c["ss"][0][0] == "needs" else "task"
            right = "4m" if st == "needs" else (c.get("due") or "")
            out.append(srow("task" if st != "needs" else "task", c["t"], right, ind=18, bold=(st == "needs")))
    out.append(f'<div class="fold" style="padding-left:34px">{g("chev")}Done · 2</div>')
    return "".join(out)


def console(w=None, flex=True):
    st = "flex:1;min-width:0" if flex else f"width:{w}px;flex:none"
    return (f'<div style="{st};background:{CONSOLE};display:flex;flex-direction:column;border-right:1px solid {RULE}">'
            f'<div class="ctab mono"><span class="on" style="display:flex;gap:6px;align-items:center">{g("needs")}PRD v2 edits</span><span style="display:flex;gap:6px;align-items:center">{g("working", CTEXT2)}Teardown research</span><span>+</span></div>'
            f'<div class="mono cl" style="padding:16px 20px;flex:1;white-space:normal">Read docs/prd-v2.md<br>Update docs/prd-v2.md<br><span style="color:{CTEXT2}">Added “What we heard” after Goals</span>'
            f'<div style="margin-top:300px">Two interviewees said saved cards are the main reason they abandon guest checkout. Move saved cards into scope, or keep it out and log an open question?</div>'
            f'<div style="margin-top:8px">❯ 1. Move saved cards into scope<br><span style="color:{CTEXT2}">&nbsp;&nbsp;2. Keep it out and log an open question</span></div></div>'
            f'<div style="margin:0 20px 16px;border:1px solid {CRULE};border-radius:6px;height:30px;color:{CTEXT2};padding:5px 10px" class="mono">&gt; ▌</div></div>')


def note_pane(w=460, tabs=("Project", "PRD v2"), on=1, task="PRD v2"):
    t = "".join(f'<span class="{"on" if i == on else ""}">{e(x)}</span>' for i, x in enumerate(tabs)) + '<span>+</span>'
    props = [("status", f'in-progress {g("chevd")}'), ("owner", "Geoff"), ("due", "2026-10-10"), ("sessions", "")]
    pl = "".join(f'<div class="pl"><span class="k">{k}</span><span style="display:flex;align-items:center;gap:6px">{v}</span></div>' for k, v in props)
    pl += "".join(f'<div class="pl"><span class="k"></span><span style="display:flex;align-items:center;gap:6px">{g(st)}<span style="{"font-weight:600;color:" + NEEDS if st == "needs" else ""}">{e(n)}</span><span class="t2">{tm}</span></span></div>'
                  for st, n, tm in [("needs", "PRD v2 edits", "4m"), ("working", "Teardown research", "working"), ("idle", "Scope notes", "3d")])
    body = (f'<div style="padding:18px 24px;white-space:normal"><div class="pb"><div class="sl" style="margin-bottom:2px">Properties</div>{pl}</div>'
            f'<div style="font-weight:600;font-size:18px;line-height:24px;margin:6px 0 10px">{e(task)}</div>'
            f'<div>Rewrite the checkout PRD around the abandonment data.</div>'
            f'<div style="font-weight:600;margin-top:14px">Done when</div><div style="display:flex;gap:8px;align-items:center;margin-top:4px">{box()}Problem and metrics reflect the Q3 funnel</div>'
            f'<div style="display:flex;gap:8px;align-items:center">{box()}Priya has cleared the retention language</div></div>')
    return f'<div style="width:{w}px;flex:none;display:flex;flex-direction:column;min-height:0"><div class="ltab">{t}</div>{body}</div>'


def pwindow(w, h, body, tb=None):
    return f'<div class="w" style="width:{w}px;height:{h}px;border:1px solid {RULE};border-radius:10px">{tb or ptoolbar()}<div style="display:flex;flex:1;min-height:0">{body}</div></div>'


def board_area(flex=True, w=None, sel=None, header_extra="", lane_w=None, keys=None, **kw):
    st = "flex:1;min-width:0" if flex else f"width:{w}px;flex:none"
    return (f'<div style="{st};display:flex;flex-direction:column;min-height:0;border-right:1px solid {RULE}">'
            f'{board_header(header_extra)}{lanes(0, keys=keys, sel=sel, lane_w=lane_w, **kw)}</div>')


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
STUDY BOARD [P], not approved. Drawn for the task board study (2026-10-07) with the Duo design system.
{e(note)}
It is a picture written in HTML: match what it draws, do not port its markup. Names and data are illustrative.
-->
<title>Duo · {e(title)}</title>
<style>{CSS}{EXTRA_CSS}</style>
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

# ---------- 0 · the study ----------
board("00-study", 1200, 860, "0 · Task board: the study", "The question, the rule, and what Obsidian does.", bd(1200, 860,
    "0 · A visual way to track a project’s tasks",
    "Geoff, 2026-10-07: “projects would benefit from a visual way of tracking tasks besides the left column — do some research into the obsidian kanban feature.” His rule for everything we build: maximize backwards compatibility with Obsidian and OKF. Every mark on these boards is a proposal [P].",
    f'''<div style="display:flex;gap:14px;align-items:flex-start">
<div class="txt" style="flex:1"><h3>The boards</h3><ol start="0">
<li>This page.</li>
<li><b>Where the data lives</b>: four ways to keep a board, judged on compatibility first.</li>
<li><b>Where the board lives</b> (2 to 5): A, a tab in the right pane; B, Sessions | Tasks in the middle; C, the board over the left and middle with the note beside it; then B and C at 1280×800.</li>
<li><b>A card</b> (6): title, owner, due, waiting on, sessions, needs you; hover and selected.</li>
<li><b>Drag</b> (7): between lanes, onto Done, a session onto a card; what gets written; card order.</li>
<li><b>Empty and narrow</b> (8).</li>
<li><b>The same board in Obsidian</b> (9): the files, before and after a drag, and the <code>tasks.base</code> Duo writes when asked.</li>
<li><b>Recommendation</b> (10).</li></ol>
<h3>What stays as decided</h3><ul>
<li>One file per task, <code>tasks/&lt;slug&gt;.md</code>, <code>status</code> one of open, in-progress, waiting, review, done, dropped (DL-6, the format doc §4.2).</li>
<li>Duo edits only the lines it owns, surgically (§4.1, DL-93); never writes <code>.obsidian/</code>; never writes a <code>.base</code> unless asked (DL-20).</li>
<li>The task menu (DL-115), New Session in Task (DL-112), the five session states and their glyphs.</li>
<li>Side panes keep their width; the middle flexes (DL-129).</li></ul></div>
<div class="txt" style="width:540px;flex:none"><h3>What Obsidian does today (verified 2026-10-07)</h3><ul>
<li><b>Bases Kanban is public</b> since Obsidian 1.14.4 (2026-10-05). A <code>.base</code> view <code>type: kanban</code> groups notes by one property; dragging a card writes that property in the note. <code>groupOrder</code> fixes the columns. <span class="p">This is exactly Duo’s shape: one note per task, lanes = <code>status</code>.</span></li>
<li><b>Bases stores no manual card order</b>: cards follow the view’s sort.</li>
<li><b>The Kanban plugin</b> (2.7M installs) keeps a whole board in one note: lanes are <code>##</code> headings, cards are <code>- [ ]</code> lines. It rewrites the whole file on every change and can’t read one-note-per-task. Its last release was May 2024; its author is looking for maintainers.</li>
<li><b>TaskNotes</b> (2M installs) is a kanban over task notes too. Its manual order is a <code>tasknotes_manual_order</code> key written into each note.</li>
<li>Tasks has columns over checklist lines, not notes; Dataview has no board; Projects is archived.</li></ul>
<p class="note">Sources and [V]/[U] marks: docs/research/task-board.md §1.</p></div></div>'''))

# ---------- 1 · where the data lives ----------
cmp_rows = [
    ("What’s on disk", "Nothing new. The board is computed from <code>tasks/*.md</code>: lane = <code>status</code>.",
     "A board note, e.g. <code>tasks/board.md</code> with <code>kanban-plugin: board</code>, a <code>##</code> lane per status and a <code>- [ ] [Title](task.md)</code> card per task.",
     "<code>tasks.base</code> beside <code>PROJECT.md</code>: a <code>kanban</code> view grouped by <code>status</code>. Written only when asked (DL-20).",
     "(a) for Duo, plus (c) on request, both reading the same <code>status</code> key."),
    ("Drag in Duo writes", "The task’s <code>status:</code> line (and <code>completed:</code>, as Set Status does). Nothing else.",
     "The board note (the whole file, re-serialised as the plugin does) <b>and</b> the task’s <code>status</code>: two copies of one fact.",
     "Same as (a): Duo never edits the <code>.base</code> on a drag.", "The <code>status</code> line only."),
    ("What Obsidian shows", "Each task as a note, with <code>status</code> in Properties. No board unless the user makes a base.",
     "The board, if the Kanban plugin is installed; a list of links if not.",
     "The same board as Duo’s, in core Obsidian 1.14.4+, no plugin. Older Obsidian shows an error view for <code>kanban</code> [U].",
     "Notes everywhere; the board wherever <code>tasks.base</code> was added."),
    ("Edited in Obsidian", "Any change to <code>status</code> (Properties, a Bases drag, TaskNotes) moves the card in Duo on the next file event.",
     "A drag in the Kanban plugin moves the card line but leaves the task’s <code>status</code> stale; Duo must reconcile two truths. Prose between lanes is lost on the plugin’s next save.",
     "A Bases drag writes <code>status</code>: Duo follows. Edits to the base (columns, sort) are the user’s; Duo never rewrites it.",
     "One truth, so nothing drifts."),
    ("Card order", "Computed: needs you, then due date, then oldest. Nothing stored.",
     "Position in the board note (the plugin’s only order). Duo would have to keep it in step.",
     "Bases sorts by the view’s <code>sort</code> (Duo writes due, then created). No manual order exists in core.",
     "Same rule both sides, except needs you, which Obsidian can’t know."),
    ("OKF / legacy", "Unchanged: same files legacy Duo wrote.", "A new file type OKF never had.", "Legacy wrote <code>.base</code> files too (ENH-266d); same filter rules.", "Unchanged."),
    ("Effort", "Medium: a view, drag, the status write we have.", "High: a parser/serialiser for the plugin’s format, two-way sync.", "Small: extend DL-20’s action with one view.", "Medium + small."),
]
th = "".join(f"<th>{h}</th>" for h in ["", "a · Computed from task notes", "b · A Kanban-plugin note", "c · A Bases <code>.base</code> file", "Recommended: a + c"])
trs = "".join(f"<tr><th>{r[0]}</th>" + "".join(f"<td>{c}</td>" for c in r[1:]) + "</tr>" for r in cmp_rows)
board("01-data", 1500, 900, "1 · Where the board’s data lives", "Four ways, compatibility first.", bd(1500, 900,
    "1 · Where the board’s data lives",
    "Compatibility decides it: whatever Duo shows must round-trip through Obsidian with no loss. The fourth column is the recommendation [P]. Option (d), TaskNotes’ own board, needs only its settings (identify tasks by <code>type: task</code>, add three statuses): Duo needs to do nothing for it.",
    f'''<div class="txt" style="padding:12px 18px 6px"><table class="cmp"><thead><tr>{th}</tr></thead><tbody>{trs}</tbody></table></div>
<div style="display:flex;gap:14px"><div class="txt" style="flex:1"><h3>Why not (b)</h3><p>The Kanban plugin keeps lanes in a note of its own. A task’s lane would live in two places (the board note and the task’s <code>status</code>), and the plugin rewrites the whole note on every change, so Duo couldn’t edit it surgically. It also can’t read one-note-per-task boards, which is Duo’s format (DL-6). It stays readable: a card that links a task note is just a link.</p></div>
<div class="txt" style="flex:1"><h3>Statuses Duo doesn’t know</h3><p>Someone types <code>status: blocked</code> in Obsidian. Duo shows a <b>blocked</b> lane at the end, in <code>text2</code>, and never rewrites the value. In Obsidian, a base whose <code>groupOrder</code> lists Duo’s five hides it (Bases shows only listed groups), so the <code>tasks.base</code> Duo writes leaves <code>groupOrder</code> to the user after the first write [P, Q-121].</p></div></div>'''))

# ---------- 6 · a card ----------
def cardf(c, w=230, **kw):
    return f'<div style="width:{w}px">{card(c, **kw)}</div>'


samples = [
    ("Needs you", T["in-progress"][0], "A linked session needs you: its line leads, glyph and name in <code>needsYou</code>, semibold, with its wait. “3 sessions” on line 2 counts them all."),
    ("Working", T["in-progress"][1], "The most urgent session leads (needs you › review › working › at prompt › idle), as a task row does (DL-93)."),
    ("Waiting on someone", T["waiting"][1], "<code>waiting_on</code> first, then due. Owner shows only when it isn’t you."),
    ("Overdue", T["waiting"][0], "Past due and not done: the date in <code>text</code> semibold with “overdue”. Not <code>needsYou</code>: that colour stays for sessions waiting on you."),
    ("Someone else’s", T["open"][1], "Owner with the person mark. Idle sessions collapse to their glyphs and a count."),
    ("Plain", T["open"][2], "A task with no sessions, due or owner: just its title."),
    ("Done", T["done"][0], "Ticked box, title in <code>text2</code> regular, “done Oct 5” from <code>completed</code>."),
]
cells = "".join(f'<div style="display:flex;flex-direction:column;gap:6px;width:250px"><div class="cap">{cap}</div>{cardf(c)}<div class="note">{n}</div></div>' for cap, c, n in samples)
board("06-cards", 1200, 940, "6 · A card", "Anatomy, variants, hover, selected.", bd(1200, 940,
    "6 · A card: what it shows",
    "A card is a task note. Everything on it is read from the note’s frontmatter and its linked sessions’ live state; nothing is stored for the card. [P]",
    f'''<div style="display:flex;flex-wrap:wrap;gap:22px 24px">{cells}
<div style="display:flex;flex-direction:column;gap:6px;width:250px"><div class="cap">Hover</div>{cardf(T["open"][0], hover=True)}<div class="note">The + is New Session in Task (DL-112), as on a task row. Right-click is the task menu (DL-115).</div></div>
<div style="display:flex;flex-direction:column;gap:6px;width:250px"><div class="cap">Selected</div>{cardf(T["in-progress"][1], sel=True)}<div class="note">A <code>text</code> border while its note is open in the right pane (as a selected tile).</div></div></div>
<div class="txt"><h3>Anatomy [P]</h3><ul>
<li><b>Card</b>: <code>pane</code> on the lane’s <code>ground</code>, 1 <code>rule</code> border, radius 6 (<code>radiusCard</code>), padding 8 10 9; lanes 6 apart. Width follows the lane (180 to 240).</li>
<li><b>Line 1</b>: the task box (<code>TaskBox</code>, as a TaskLine) and the <code>title</code>, semibold 13/18, wrapping to 3 lines then truncating.</li>
<li><b>Line 2</b>, 12/16 <code>text2</code>, indented to the title: <code>waiting on …</code>, owner (when not you), due (calendar mark), <code>done …</code>. Missing fields leave no gap.</li>
<li><b>Line 3</b>: sessions, from the note’s <code>sessions:</code> list (DL-93). The most urgent one leads with its name and wait (line 2 says how many when there are several); idle-only shows glyphs and a count.</li>
<li>Not shown: tags, milestone, <code>done_when</code>, <code>depends_on</code> (ENH-36 lets a user pick extra properties, as Bases does).</li></ul></div>'''))

# ---------- 7 · drag ----------
lifted = card(T["open"][0], cls="lift")
drag_win = pwindow(1200, 600, f'<div style="flex:1;display:flex;flex-direction:column;position:relative">{board_header()}{lanes(0, lift="Pricing page copy", drop_into="in-progress", ghost=2)}'
                   f'<div style="position:absolute;left:330px;top:300px;width:210px">{lifted}</div></div>', ptoolbar(toggle="board"))
diff = (f'<div class="diffl"><span class="ctx">---</span><span class="ctx">type: task</span><span class="ctx">title: Pricing page copy</span>'
        f'<span class="del">-status: open</span><span class="add">+status: in-progress</span><span class="ctx">owner: Geoff</span><span class="ctx">due: 2026-10-18</span><span class="ctx">created: 2026-10-06</span><span class="ctx">---</span></div>')
diff2 = (f'<div class="diffl"><span class="del">-status: review</span><span class="add">+status: done</span><span class="ctx">&nbsp;owner: Geoff</span><span class="ctx">&nbsp;due: 2026-10-12</span><span class="ctx">&nbsp;created: 2026-10-01</span><span class="add">+completed: 2026-10-07</span></div>')
target_card = card(T['open'][0]).replace('class="tc"', f'class="tc" style="outline:1.5px solid {TEXT};outline-offset:1px"')
sess_drop = (f'<div style="display:flex;gap:16px;align-items:flex-start"><div style="width:220px;display:flex;flex-direction:column;gap:6px">'
             f'<div class="row sel" style="margin:0;box-shadow:0 12px 32px rgba(31,35,40,0.22)">{g("idle")}<span class="ti">Pricing research</span><span class="tm t2">2h</span></div>'
             f'<div class="note">A session dragged from the list (B) or a session tab</div></div>'
             f'<div style="width:220px">{target_card}<div class="note" style="margin-top:6px">Drop on a card: <code>duo2 task add</code>, the same as Add to Task (CX study owns this flow)</div></div></div>')
board("07-drag", 1500, 1060, "7 · Drag", "Between lanes, onto Done, a session onto a card; what is written.", bd(1500, 1060,
    "7 · Drag: what moves and what gets written",
    "A drag between lanes is Set Status (<code>duo2 task status</code>). It rewrites one line of one note, through the editor’s buffer if the note is open (DL-13), and ⌘Z undoes it. [P]",
    f'''<div style="display:flex;gap:20px;align-items:flex-start">{frame(drag_win, 1200, 600, "Mid-drag: Pricing page copy to In progress", "The card lifts (popover shadow, a 1.5° tilt); its place stays as a dashed ghost; the target lane takes <code>selected</code> with a dashed edge; a dashed slot shows where it will land. The slot is the card’s computed place in that lane, not where the pointer is.")}
<div style="display:flex;flex-direction:column;gap:14px;flex:1">
<div class="txt"><h3>Written: one line</h3>{diff}</div>
<div class="txt"><h3>Onto Done</h3>{diff2}<p class="note">As Mark Complete: the card holds ticked for 5 s (DL-130), then settles into Done. Dropped has no lane: drop on the <b>Dropped</b> fold under Done, or use Set Status.</p></div></div></div>
<div style="display:flex;gap:14px">
<div class="txt" style="flex:1"><h3>Card order: computed, not stored [P, Q-120]</h3><p>Inside a lane: <b>needs you first</b>, then <b>due date</b> (soonest, overdue on top), then <b>oldest created</b>. Dragging within a lane does nothing. Obsidian’s Bases can’t store a manual order either, and TaskNotes’ way (a rank key in every note) would put a Duo or TaskNotes key into each task and churn files on every reorder.</p></div>
<div class="txt" style="flex:1"><h3>A session onto a card</h3>{sess_drop}</div>
<div class="txt" style="flex:1"><h3>Keys and menus</h3><ul><li>Right-click: the task menu (DL-115), Set Status ▸ included.</li><li>Arrow keys move the selection; ⌥⌘← / ⌥⌘→ move a card one lane [P].</li><li>Return opens the note; Space shows a peek [P].</li><li>VoiceOver: “Pricing page copy, Open, due October 18. Move to ▸” as an action.</li></ul></div></div>'''))

# ---------- 8 · empty and narrow ----------
empty_win = pwindow(980, 560, f'''<div style="flex:1;display:flex;flex-direction:column">{board_header().replace("Tasks · 11", "Tasks · 0")}
<div style="flex:1;display:flex;align-items:center;justify-content:center"><div style="width:420px;text-align:center;white-space:normal;display:flex;flex-direction:column;gap:10px;align-items:center">
<div style="font-weight:600;font-size:14px">No tasks yet</div><div class="t2">[Explainer copy from the project &amp; task CX study]</div>
<div style="display:flex;gap:8px"><span class="btn">+ New task</span><span class="btn">Make a Task from a session…</span></div></div></div></div>''', ptoolbar(toggle="board"))
empty_lane = lane("review", "Review", '<div class="drop">Nothing to review</div>', 0)
board("08-empty-narrow", 1500, 960, "8 · Empty and narrow", "No tasks, an empty lane, and widths.", bd(1500, 960,
    "8 · Empty states and narrow widths",
    "The minimum window is 1280×800 (DL-129), but the board’s share of it shrinks when the right pane opens. Lanes keep at least 150; below that the board gives way in steps. [P]",
    f'''<div style="display:flex;gap:20px;align-items:flex-start">{frame(empty_win, 980, 560, "A project with no tasks", "Centred in the board: a title, the CX study’s explainer (its copy, not drawn here), + New task and Make a Task from a session…. The lanes don’t show until there is a task.")}
<div style="display:flex;flex-direction:column;gap:8px;width:220px"><div class="cap">An empty lane</div><div style="height:180px;display:flex">{empty_lane}</div><div class="note">The lane stays, so it is a drop target: a dashed box (<code>controlEdge</code>, the dash token) saying what isn’t there. All five lanes always show (Bases’ “Hide empty columns” is off for the same reason).</div></div>
<div class="txt" style="flex:1"><h3>Widths, in steps [P]</h3><ol>
<li><b>900 and up</b>: five lanes, flexing from 240 down to about 170.</li>
<li><b>Under 900</b>: Done folds into a 34-wide strip at the right (board 5, C at 1280 with the note open). A click opens it as a lane over the others.</li>
<li><b>Under 640</b> (B with a note open at 1280): lanes keep 200 and scroll sideways; the lane you drag toward scrolls into view.</li>
<li><b>Left pane only</b> (both side panes hidden doesn’t apply to C, which uses the left pane): the Tasks fold in the session list is the narrow board: grouped by status, rows drag between groups (ENH-35).</li></ol>
<h3>Done and Dropped</h3><p>Done shows tasks completed in the last 7 days; older ones sit in an <b>Earlier · n</b> fold, then <b>Dropped · n</b>. Archived tasks (DL-115) never show on the board.</p></div></div>'''))

# ---------- 9 · Obsidian ----------
task_md = '''---
type: task
title: Pricing page copy
status: in-progress
owner: Geoff
due: 2026-10-18
sessions:
  - "[Pricing research](duo2://session/9b1d…)"
created: 2026-10-06
tags:
  - copy
---

Rewrite the pricing page for saved cards.'''
base = '''filters:
  and:
    - type == "task"
    - 'file.folder == if(this.file.folder == "/", "tasks", this.file.folder + "/tasks")'
views:
  - type: kanban
    name: Board
    groupBy:
      property: status
      direction: ASC
    groupOrder:
      - open
      - in-progress
      - waiting
      - review
      - done
    order:
      - title
      - owner
      - waiting_on
      - due
    sort:
      - property: due
        direction: ASC
      - property: created
        direction: ASC
  - type: table
    name: By status
    groupBy:
      property: status
      direction: ASC
    order: [title, owner, waiting_on, due]'''
kp = '''---
kanban-plugin: board
---

## Open

- [ ] [Pricing page copy](pricing-page-copy.md)

## In progress

- [ ] [PRD v2](prd-v2.md)

%% kanban:settings
```
{"kanban-plugin":"board"}
```
%%'''
board("09-obsidian", 1500, 960, "9 · The same board in Obsidian", "The files: a task note, tasks.base, and why not a Kanban-plugin note.", bd(1500, 960,
    "9 · The same board in Obsidian",
    "Nothing to draw of Obsidian itself: the point is the files. Duo’s board and Obsidian’s Bases Kanban both read and write the same <code>status</code> line, so either app can move a card and the other follows. [P]",
    f'''<div style="display:flex;gap:14px;align-items:flex-start">
<div class="txt" style="width:400px;flex:none"><h3><code>tasks/pricing-page-copy.md</code></h3><pre class="mono" style="margin:0;white-space:pre;font-size:11.5px;line-height:17px">{e(task_md)}</pre><p class="note">The board needs no new key. Moving a card in either app changes only <code>status</code> (Duo also writes <code>completed</code> on done, as today).</p></div>
<div class="txt" style="width:520px;flex:none"><h3><code>tasks.base</code>, written only by “Add Obsidian Board” (DL-20)</h3><pre class="mono" style="margin:0;white-space:pre;font-size:11.5px;line-height:17px">{e(base)}</pre><p class="note">The format doc’s base (§4.7) with its Board view filled in: <code>groupOrder</code> pins Duo’s five lanes (dropped stays out, as in Duo), the sort is Duo’s minus needs-you. Needs Obsidian 1.14.4 (public 2026-10-05). Duo never rewrites it once written.</p></div>
<div class="txt" style="flex:1"><h3>Not written: a Kanban-plugin note</h3><pre class="mono" style="margin:0;white-space:pre;font-size:11.5px;line-height:17px">{e(kp)}</pre><p class="note">For contrast: the plugin keeps lanes as headings in one note. Duo would have to keep it in step with every task’s <code>status</code>. If a user has one, Duo opens it as a note and its links work; that’s all (ENH-36 could import one, once).</p></div></div>
<div class="txt"><h3>Round trip, checked against the rules (format doc §4.8)</h3><ul>
<li>No <code>.obsidian/</code> writes; no keys added to task notes; no rewriting of the base after it’s written; nothing removed from a note Duo doesn’t own.</li>
<li>A drag in Obsidian is a file change: Duo’s watcher moves the card, the same as for Set Status from <code>duo2</code>.</li>
<li>A status Obsidian adds that Duo doesn’t know gets its own lane in Duo; in Obsidian it is hidden while <code>groupOrder</code> lists only Duo’s five (C-52).</li>
<li>Bases may replace a list value on drag (unverified for lists); <code>status</code> is a scalar, so it doesn’t matter here.</li></ul></div>'''))

# ---------- 10 · recommendation ----------
board("10-recommendation", 1200, 820, "10 · Recommendation", "a + c data, C placement, computed order.", bd(1200, 820,
    "10 · Recommendation and a first slice",
    "<b>Data: (a) + (c).</b> The board is computed from the task notes, a drag writes only <code>status</code>, and “Add Obsidian Board” writes a <code>tasks.base</code> with the same Kanban view. <b>Placement: C</b>, the board over the left and middle with the note beside it, switched by <b>Sessions | Tasks</b>. <b>Order: computed.</b> [P]",
    f'''<div style="display:flex;gap:16px;align-items:flex-start">
<div class="txt" style="flex:1"><h3>Why</h3><ul>
<li><b>One truth.</b> <code>status</code> in each note is the lane, in Duo, in Bases, in TaskNotes. Nothing to sync, nothing to drift, no new key.</li>
<li><b>Obsidian caught up this week.</b> Bases Kanban (1.14.4, public 2026-10-05) is the same model, so “the same board in Obsidian” is one generated file, not a plugin dependency.</li>
<li><b>C fits planning</b>: the board and the task’s note side by side at 1440 and 1280, no reflow.</li>
<li><b>Computed order</b> matches what Bases can do and keeps files quiet.</li></ul>
<h3>Not recommended</h3><p>(b) a Kanban-plugin note: two truths, whole-file rewrites, an unmaintained plugin. A: two lanes in 460. B is the second choice if the session list must stay visible.</p></div>
<div class="txt" style="width:520px;flex:none"><h3>First slice [P]</h3><ol>
<li><b>Sessions | Tasks</b> in the toolbar of a project; the board as C; Board link on the Tasks fold. <code>duo2 task board [show|hide|toggle]</code>.</li>
<li>Five lanes, cards as board 6, unknown statuses as extra lanes, Done’s Earlier and Dropped folds.</li>
<li>Drag between lanes = <code>duo2 task status</code>; drop a session = <code>duo2 task add</code>; ⌘Z.</li>
<li>Empty and narrow as board 8.</li>
<li>“Add Obsidian Board” writes board 9’s <code>tasks.base</code> (DL-20’s action, extended).</li></ol>
<h3>Later</h3><ul><li>ENH-35: a board across all projects, and the Tasks fold grouped by status as the narrow board.</li><li>ENH-36: choose card properties; import a Kanban-plugin note once.</li></ul>
<h3>Open (Q-119 to Q-121)</h3><ul><li>Q-119 where it lives (A, B, C).</li><li>Q-120 card order (computed, or manual with a key).</li><li>Q-121 the base’s <code>groupOrder</code>.</li></ul></div></div>'''))

# ---------- 2 to 5 · where the board lives ----------
WW, WH = 1440, 900


def where_a():
    tabs = '<span>Project</span><span class="on" style="display:flex;gap:5px;align-items:center">' + g("board") + 'Board</span><span>PRD v2</span><span>+</span>'
    right = (f'<div style="width:460px;flex:none;display:flex;flex-direction:column;min-height:0"><div class="ltab">{tabs}</div>'
             f'{board_header(n=11, filter_w=110).replace("+ New task", "+ Task")}'
             f'<div style="display:flex;flex:1;min-height:0;overflow:hidden">{lanes(0, lane_w=200)}</div>'
             f'<div style="height:12px;margin:0 16px 8px;position:relative"><div style="position:absolute;left:0;top:4px;width:180px;height:5px;border-radius:3px;background:{EDGE};opacity:.5"></div></div></div>')
    return pwindow(WW, WH, left_pane(board_btn=True) + console() + right)


def where_b(note=False):
    if note:
        body = left_pane() + board_area(lane_w=200, sel="PRD v2") + note_pane()
    else:
        body = left_pane() + board_area()
    return pwindow(WW, WH, body, ptoolbar(toggle="board"))


def where_c(w=WW, h=WH, sel="PRD v2", note=True, narrow_done=False):
    if narrow_done:
        strip = (f'<div style="width:34px;flex:none;margin:42px 16px 16px -6px;background:{GROUND};border-radius:6px;display:flex;flex-direction:column;align-items:center;gap:8px;padding-top:8px">'
                 f'{g("chev")}<span class="sl" style="writing-mode:vertical-rl;height:auto">Done · 2</span></div>')
        body = (f'<div style="flex:1;min-width:0;display:flex;flex-direction:column;min-height:0;border-right:1px solid {RULE}">{board_header()}'
                f'<div style="display:flex;flex:1;min-height:0">{lanes(0, keys=["open", "in-progress", "waiting", "review"], sel=sel)}{strip}</div></div>')
    else:
        body = board_area(sel=sel if note else None)
    if note:
        body += note_pane(460)
    return pwindow(w, h, body, ptoolbar(toggle="board"))


def where_board(name, title, sub, win, notes):
    board(name, 1520, 1260, title, sub, bd(1520, 1260, title, sub,
          f'<div style="display:flex;flex-direction:column;gap:12px">{win}<div style="display:flex;gap:14px">{"".join(f"<div class=txt style=flex:1>{n}</div>" for n in notes)}</div></div>'))


where_board("02-where-a", "2 · A: a Board tab in the right pane",
            "The board is a tab in the right pane, after Project (as DL-60’s Project tab is), opened from a Board link on the Tasks fold or <code>duo2 task board</code>. Sessions and the console stay where they are. [P]",
            where_a(),
            ["<h3>For</h3><ul><li>Nothing else moves: the console stays in the middle, Claude keeps talking while you look.</li><li>A tab is a pattern Duo already has (Project, documents).</li></ul>",
             "<h3>Against</h3><ul><li>The right pane is 460 (DL-129): two lanes fit, the other three scroll sideways. The board is the one view that needs width.</li><li>Opening a card’s note replaces the board in the same pane, so you can’t see both.</li></ul>",
             "<h3>Verdict [P]</h3><p>Not recommended as the board’s home. It is the right place for a <b>one-lane glance</b> later (a task’s note already shows its sessions).</p>"])

where_board("03-where-b", "3 · B: Sessions | Tasks in the middle",
            "A <b>Sessions | Tasks</b> switch in the toolbar after the project’s name, like All projects’ Board | List (DL-142). Tasks shows the board across the middle and right panes; the session list stays on the left. Clicking a card brings the right pane back with its note, and the board narrows to the middle and scrolls sideways. [P]",
            where_b(),
            ["<h3>For</h3><ul><li>The most width a board can have without losing the session list: 1140 at 1440, five lanes of about 210.</li><li>The switch matches All projects’ Board | List.</li></ul>",
             "<h3>Against</h3><ul><li>The console disappears while the board shows (sessions keep running; their state is on the cards and in the list).</li><li>Opening a note reflows the board from five lanes to three (board 3b).</li></ul>",
             "<h3>Behaviour [P]</h3><p>⌘1 Sessions, ⌘2 Tasks [P, see Q-100]. The choice is per project and remembered. A click on a session in the list switches back to Sessions with it selected.</p>"])

where_board("03b-where-b-note", "3b · B with a card’s note open",
            "B after a click on <b>PRD v2</b>: the note opens in the right pane (460), the board keeps the middle (680) and scrolls sideways; three lanes show. [P]",
            where_b(note=True),
            ["<h3>Reflow</h3><p>The board keeps its lane width (200) and scrolls, rather than squeezing five lanes into 680. Esc or the note’s tab close gives the width back.</p>",
             "<h3>Selected card</h3><p>A <code>text</code> border, as a selected tile (model.md). The note is the task’s own file: edits go through the editor as today.</p>",
             "<h3>Compare</h3><p>C (board 4) keeps the note pane open all the time and gives the board the left pane’s width instead, so nothing reflows.</p>"])

where_board("04-where-c", "4 · C: the board takes the left and middle",
            "The same <b>Sessions | Tasks</b> switch, and a <b>Board</b> link on the Tasks fold. Tasks shows the board in place of the session list <i>and</i> the console (980 at 1440); the right pane stays, so a card’s note opens beside the board and nothing reflows. [P]",
            where_c(),
            ["<h3>For</h3><ul><li>Board and note side by side, the way you plan: pick a card, read or edit its note, drag the next.</li><li>Five lanes of about 180 at 1440, about 150 at 1280 (board 5).</li><li>The right pane behaves as it does everywhere (documents, Project tab).</li></ul>",
             "<h3>Against</h3><ul><li>The session list and console hide while the board shows. Needs you is still in the toolbar’s chip, and on each card (the orange line).</li><li>A new layout for the left pane, which so far has only been the session list.</li></ul>",
             "<h3>Verdict [P]</h3><p><b>Recommended.</b> It is the one layout where the board and a task’s note are both fully visible, at both window sizes. B is the close second if Geoff wants the session list always visible.</p>"])


def pair_1280():
    b = pwindow(1280, 800, left_pane() + board_area(), ptoolbar(toggle="board"))
    c = where_c(1280, 800, narrow_done=True)
    return b, c


b1280, c1280 = pair_1280()
board("05-where-1280", 2720, 1060, "5 · B and C at 1280×800 (the smallest window)",
      "B and C at the minimum window size.", bd(2720, 1060, "5 · B and C at 1280×800, the smallest window (DL-129)",
      "Side panes keep their width; the board flexes. C with the note open has 820: below 900 the Done lane folds into a 34-wide strip (click to open it), so four lanes keep about 190. [P]",
      f'<div style="display:flex;gap:40px">{frame(b1280, 1280, 800, "B · 980 for five lanes", "Five lanes of about 180. With a note open it is 520: two lanes and a sideways scroll.")}{frame(c1280, 1280, 800, "C · note open, Done folded", "Four lanes of about 190 and Done as a strip. With the right pane hidden (⌥⌘0) all five lanes come back at full width.")}</div>'))

with open(os.path.join(OUT, "manifest.json"), "w") as f:
    json.dump(BOARDS, f, indent=1)
print(f"{len(BOARDS)} boards in {OUT}")
