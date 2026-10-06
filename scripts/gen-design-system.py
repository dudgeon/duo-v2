#!/usr/bin/env python3
"""Generate the machine-readable half of Duo's design system, docs/design/system/, from the one
source of tokens (docs/design/build-handoff/tokens.json):

  tokens.json          in the list shape Claude Design's Design System type reads (DTCG maps
                       are unreadable there), every token named as in Swift, each with a usage note
  assets/Icons/*.svg   the icon paths from tokens.json, strokes set to their token's hex
  assets/Glyphs/*.svg  the five session-state glyphs, likewise

The README, sections and component docs beside them are written by hand; this script never
touches them. Run after changing tokens.json (after scripts/gen-tokens.py):

  python3 scripts/gen-design-system.py           write
  python3 scripts/gen-design-system.py --check   exit 1 if anything here is out of date
"""
import json
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
src = root / "docs/design/build-handoff/tokens.json"
out = root / "docs/design/system"
t = json.loads(src.read_text())
light, console = t["color"]["light"], t["color"]["console"]


def px(v):
    return f"{v:g}px"


def cap(s):
    return s[0].upper() + s[1:]


def rgba(spec):
    v = spec["value"]
    if "alpha" not in spec:
        return v.lower()
    r, g, b = (int(v[i:i + 2], 16) for i in (1, 3, 5))
    return f"rgba({r}, {g}, {b}, {spec['alpha']})"


# ---------- colour ----------
colors = []
for name, spec in light.items():
    if not name.startswith("$"):
        colors.append({"name": name, "value": {"light": rgba(spec)}, "usage": spec.get("use", "")})
for name, spec in console.items():
    if not name.startswith("$"):
        colors.append({"name": name, "value": {"light": rgba(spec)},
                       "usage": spec.get("use", "") + " Console chrome: the same in every appearance."})
tp = t["terminal"]
for k, spec in tp["ansi"].items():
    colors.append({"name": "terminal" + cap(k), "value": {"light": spec["value"].lower()},
                   "usage": f"Terminal ANSI {spec['index']} ({k}) on `console`, {spec['contrastOnConsole']}:1 (DB-2). Only inside terminals."})
for k, spec in tp["ansiIncreaseContrast"].items():
    colors.append({"name": "terminalHC" + cap(k), "value": {"light": spec["value"].lower()},
                   "usage": f"Terminal ANSI {spec['index']} ({k}) when macOS Increase Contrast is on (DB-2)."})
colors.append({"name": "terminalCursor", "value": {"light": tp["cursor"]["value"].lower()}, "usage": "The terminal's block cursor (DB-2)."})
colors.append({"name": "terminalTextUnderCursor", "value": {"light": tp["cursor"]["textUnderCursor"].lower()}, "usage": "Text under the terminal's cursor."})
colors.append({"name": "terminalSelection", "value": {"light": tp["selection"]["value"].lower()}, "usage": "Selected text in a terminal."})

# ---------- type ----------
weights = {"regular": 400, "medium": 500, "semibold": 600, "bold": 700}
default_use = {
    "body": "Default text: rows, cards, documents' UI.",
    "bodyEmphasis": "Names that lead a row or card: project and group names, the selected item.",
    "chip": "The needs-you chip in the toolbar.",
    "pill": "Count pills (`group · 3`, `task · 2`) and small tags.",
    "monoActiveTab": "The selected console tab's title.",
}
groups = {"ui": [], "mono": []}
for name, s in t["font"]["style"].items():
    style = {"name": name, "fontSize": px(s["size"]), "lineHeight": px(s["lineHeight"]), "fontWeight": weights[s["weight"]],
             "usage": s.get("use") or default_use.get(name, "")}
    if s.get("tracking"):
        style["letterSpacing"] = px(s["tracking"])
    if s.get("textCase") == "uppercase":
        style["usage"] = (style["usage"] + " Set in capitals." if style["usage"] else "Section labels: capitals, +0.06 em.")
        style["sample"] = "NEEDS YOU · 2"
    groups[s["family"]].append(style)
typ = {
    "fonts": [],
    "families": {"ui": t["font"]["family"]["ui"]["css"], "mono": t["font"]["family"]["mono"]["css"]},
    "groups": [{"name": "Interface", "family": "ui", "styles": groups["ui"]},
               {"name": "Console and paths", "family": "mono", "styles": groups["mono"]}],
}

# ---------- spacing ----------
sp = t["space"]
spacing = [
    {"name": "panePadding", "value": px(sp["panePadding"]), "usage": "Inset of every pane's content from its edges."},
    {"name": "selectionInset", "value": px(sp["selectionInset"]), "usage": "Selected rows' rounded fill is inset this far from the pane edges."},
    {"name": "threadRuleX", "value": px(sp["threadRuleX"]), "usage": "Where the vertical rule under an open group or thread sits."},
    {"name": "chatColumnInset", "value": px(sp["chatColumnInset"]), "usage": "Chat transcript side padding (chat-mode-handoff)."},
    {"name": "chatCardTrailing", "value": px(sp["chatCardTrailing"]), "usage": "Space kept to the right of Claude's reply card (chat-mode-handoff)."},
    {"name": "chatBubbleMax", "value": px(sp["chatBubbleMax"]), "usage": "Your chat bubble's maximum width (chat-mode-handoff)."},
]
for k in ["cardPadding", "pointerCardPadding", "questionBoxPadding", "buttonPadding", "popoverPadding", "documentPadding"]:
    for side, v in sp[k].items():
        spacing.append({"name": k + cap(side), "value": px(v), "usage": f"{k.replace('Padding', ' padding')}, {side}."})
gap_use = {
    "tileRows": "Between a tile's text lines.", "glyphToLabel": "State glyph to its label.", "buttonToButton": "Between buttons in a row.",
    "rowItems": "Between items in a row (glyph, name, pill, wait).", "cardToCard": "Between cards in the action column.",
    "cardContent": "Between a card's header, question and buttons.", "tileToTile": "Between tiles in a map column.",
    "mapColumns": "Between map columns (and wrapped rows).", "toolbarOverview": "Between items on the All projects toolbar.",
    "toolbarProject": "Between breadcrumb items in a project.", "paneTabs": "Between right-pane tabs.",
    "aboveDocumentHeading": "Extra space above a document's H2 and smaller headings, on top of the 10 between blocks (S3-5, C-22).",
}
for k, v in sp["gap"].items():
    spacing.append({"name": "gap" + cap(k), "value": px(v), "usage": gap_use.get(k, k)})

# ---------- radius, border, shadow ----------
radius_use = {"control": "Buttons and fields.", "card": "Tiles and cards.", "selection": "Selected row fill.", "field": "Text fields.",
              "pill": "Count pills (fully rounded at 18 high).", "popover": "Popovers, the search modal, menus Duo draws.",
              "placeholderBar": "Placeholder bars in the design targets only."}
radius_use.update({"reviewCard": "A permission, plan or question card docked at the bottom of chat, with a 1.5 needsYou border (chat-mode-handoff).",
                   "composer": "The chat composer field (chat-mode-handoff).",
                   "chatInlineCode": "Inline code's fill in chat Markdown (chat-mode-handoff `text`).",
                   "chatStepBody": "A tool step's diff, output or agent box (chat-mode-handoff `tools`).",
                   "chatCodeBlock": "A code block in chat Markdown (chat-mode-handoff `text`).",
                   "chatCheckbox": "A question card's checkbox (chat-mode-handoff `question-multi`).",
                   "chatPreviewCode": "An option's preview inside a question card (chat-mode-handoff `question-previews`)."})
# A per-corner radius (chat-mode-handoff) reads as CSS: top-left, top-right, bottom-right, bottom-left.
corners = lambda v: " ".join(px(v[c]) for c in ["topLeft", "topRight", "bottomRight", "bottomLeft"])
radius = [{"name": "radius" + cap(k), "value": corners(v) if isinstance(v, dict) else px(v),
           "usage": v.get("use", k) if isinstance(v, dict) else radius_use.get(k, k)} for k, v in t["radius"].items()]
border_use = {"hairline": "Pane dividers, card and field borders (`rule`).", "emphasis": "Group rule, focus outlines inside lists.",
              "filesDivider": "The divider above FILES in a project's left pane.", "tileFocusOutline": "Keyboard focus around a map tile."}
border = [{"name": "border" + cap(k), "value": px(v), "usage": border_use.get(k, k)} for k, v in t["border"].items()
          if not k.startswith("$") and isinstance(v, (int, float))]
border.append({"name": "borderDash", "value": " ".join(px(x) for x in t["border"]["dash"]),
               "usage": "Dash pattern (on, off) for dashed borders: the New project tile, drop targets."})
sh = t["shadow"]["popover"]
shadow = [{"name": "shadowPopover", "value": f"{px(sh['x'])} {px(sh['y'])} {px(sh['blur'])} {sh['color'].replace(',', ', ')}",
           "usage": "Popovers Duo draws: search, the action menu, the idle list, drag cards. System popovers keep the system's."}]

# ---------- sizes (split so each family stays under the type's 60) ----------
s = t["size"]
layout = [
    {"name": "designWindow", "value": f"{s['designWindow']['width']}px", "usage": f"The window the targets are drawn at: {s['designWindow']['width']} × {s['designWindow']['height']}."},
    {"name": "minimumWindow", "value": f"{s['minimumWindow']['width']}px", "usage": f"Smallest window: {s['minimumWindow']['width']} × {s['minimumWindow']['height']}."},
    {"name": "toolbarHeight", "value": px(s["toolbarHeight"]), "usage": "Toolbar (the system draws 40 on macOS 27; content sits below it)."},
    {"name": "tabStripHeight", "value": px(s["tabStripHeight"]), "usage": "Console and right-pane tab strips."},
    {"name": "homeSessionTabsHeight", "value": px(s["homeSessionTabsHeight"]), "usage": "Home's session tabs under its header."},
    {"name": "overviewFooterHeight", "value": px(s["overviewFooterHeight"]), "usage": "The map's footer (`N idle, resumable ›`)."},
    {"name": "buttonHeight", "value": px(s["buttonHeight"]), "usage": "Buttons."},
    {"name": "newProjectTileHeight", "value": px(s["newProjectTileHeight"]), "usage": "The dashed New project tile."},
    {"name": "glyphSize", "value": px(s["glyph"]), "usage": "State glyphs are drawn 9 pt square."},
    {"name": "searchFieldWidth", "value": px(s["jumpField"]["width"]), "usage": "Toolbar field `Search all projects ⇧⌘A` (DL-80)."},
    {"name": "searchFieldHeight", "value": px(s["jumpField"]["height"]), "usage": "Toolbar search field height."},
    {"name": "peekPopoverWidth", "value": px(s["peekPopoverWidth"]), "usage": "The needs-you peek popover."},
]
for k, v in s["row"].items():
    layout.append({"name": "row" + cap(k), "value": px(v), "usage": {"file": "File tree rows.", "tileSession": "Session rows inside a map tile.",
                                                                    "session": "Session and thread rows in a project's list.", "group": "Group and task rows."}[k]})
for alt, panes in s["pane"].items():
    for k, v in panes.items():
        layout.append({"name": "pane" + cap(alt) + cap(k), "value": px(v), "usage": f"{cap(alt)} view: the {k} pane's width."})
for k, v in s["paneMinimumProposed"].items():
    layout.append({"name": "paneMin" + cap(k), "value": px(v), "usage": f"Proposed minimum width of the {k} pane (DB-25 open)."})

search = []
sm = s["searchModal"]
for k in ["width", "top", "fieldRowHeight", "listColumnWidth", "bodyMinHeight", "footerHeight"]:
    search.append({"name": "searchModal" + cap(k), "value": px(sm[k]), "usage": f"Search modal: {k} (search-handoff)."})
sr = s["searchRow"]
for k, v in sr.items():
    if isinstance(v, dict):
        for kk, vv in v.items():
            search.append({"name": "searchRow" + cap(k) + cap(kk), "value": px(vv), "usage": f"Search result row: {k} {kk}."})
    else:
        search.append({"name": "searchRow" + cap(k), "value": px(v) if k != "snippetMaxLines" else str(v), "usage": f"Search result row: {k}."})
for k, v in s["searchPreview"].items():
    if isinstance(v, dict):
        for kk, vv in v.items():
            search.append({"name": "searchPreview" + cap(k) + cap(kk), "value": px(vv), "usage": f"Search preview: {k} {kk}."})
    else:
        search.append({"name": "searchPreview" + cap(k), "value": px(v), "usage": f"Search preview: {k}."})
am = s["actionMenu"]
for k in ["width", "rowHeight", "padding"]:
    search.append({"name": "actionMenu" + cap(k), "value": px(am[k]), "usage": f"Search's action menu (Tab): {k}."})

surfaces = []
ip = s["idlePopover"]
surfaces += [{"name": "idlePopoverWidth", "value": px(ip["width"]), "usage": "The idle list popover (DB-1)."},
             {"name": "idleRowHeight", "value": px(ip["rowHeight"]), "usage": "Idle list rows."},
             {"name": "idleProjectColumnMax", "value": px(ip["projectColumnMax"]), "usage": "Idle list: widest the project column gets."},
             {"name": "idleAgeColumn", "value": px(ip["ageColumn"]), "usage": "Idle list: the age column."}]
cm = s["consoleMessage"]
surfaces += [{"name": "consoleMessagePadding", "value": px(cm["padding"]), "usage": "A console with nothing running: inset of its message (DB-3)."},
             {"name": "consoleMessageMaxTextWidth", "value": px(cm["maxTextWidth"]), "usage": "The message's widest line."},
             {"name": "consoleMessageGap", "value": px(cm["gap"]), "usage": "Title to body."},
             {"name": "consoleBarHeight", "value": px(s["consoleBar"]["height"]), "usage": "The bar under an ended session or failed shell (DB-3, DB-4)."}]
pb = s["propertiesBlock"]
surfaces += [{"name": "propertiesBlockMargin", "value": px(pb["block"]["marginHorizontal"]), "usage": "Properties block (DB-16, designed, not built): side margin."},
             {"name": "propertiesBlockRadius", "value": px(pb["block"]["radius"]), "usage": "Properties block corner radius."},
             {"name": "propertiesLineMinHeight", "value": px(pb["line"]["minHeight"]), "usage": "A property line's minimum height."},
             {"name": "propertiesSuggestionsWidth", "value": px(pb["suggestions"]["widthNames"]), "usage": "Property name suggestions popover."}]

source = {"source": "github", "repo": "dudgeon/duo-v2", "paths": {"tokens": ["docs/design/build-handoff/tokens.json"],
          "swift": ["Sources/DuoKit/Design/Tokens.swift"]}, "generator": "scripts/gen-design-system.py"}
tokens = {
    "name": "Duo", "version": 1, "meta": source,
    "color": {"themes": [{"id": "light", "name": "Light"}], "note": "Light only: the dark appearance isn't approved (DB-29). Console colours are fixed in every appearance.", "tokens": colors},
    "type": typ,
    "spacing": {"tokens": spacing},
    "radius": {"tokens": radius},
    "shadow": {"tokens": shadow},
    "border": {"tokens": border},
    "layout": {"note": "Fixed sizes, in points (shown as px).", "tokens": layout},
    "searchSizes": {"note": "The search modal (search-handoff).", "tokens": search},
    "surfaceSizes": {"note": "Surfaces designed in later handoffs: the idle list, console messages, the properties block.", "tokens": surfaces},
}
names = [x["name"] for fam in ["color", "spacing", "radius", "shadow", "border", "layout", "searchSizes", "surfaceSizes"] for x in tokens[fam]["tokens"]]
dupes = {n for n in names if names.count(n) > 1}
if dupes:
    raise SystemExit(f"duplicate token names: {sorted(dupes)}")
for fam in ["spacing", "radius", "shadow", "border", "layout", "searchSizes", "surfaceSizes"]:
    if len(tokens[fam]["tokens"]) > 60:
        raise SystemExit(f"{fam} has {len(tokens[fam]['tokens'])} tokens; the type reads 60 at most")
missing = [x["name"] for fam in ["color", "spacing", "radius", "shadow", "border", "layout", "searchSizes", "surfaceSizes"] for x in tokens[fam]["tokens"] if not x["usage"]]
if missing:
    raise SystemExit(f"tokens with no usage note: {missing}")

# ---------- SVG assets ----------
hexes = {k: v["value"] for k, v in list(light.items()) + list(console.items()) if not k.startswith("$")}
files = {"tokens.json": json.dumps(tokens, indent=2, ensure_ascii=False) + "\n"}
for k, v in t["icon"].items():
    if k.startswith("$") or "svg" not in v:
        continue
    stroke = v.get("stroke", "text")
    stroke = stroke if stroke in hexes else "text2"
    attrs = f'fill="none" stroke="{hexes[stroke]}" stroke-width="{1.2 if k.startswith("property") else 1.5}" stroke-linecap="round" stroke-linejoin="round"'
    files[f"assets/Icons/{k}.svg"] = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{v.get("viewBox", "0 0 10 10")}" width="24" height="24" {attrs}>{v["svg"].replace(chr(39), chr(34))}</svg>\n'
for k, v in t["glyph"].items():
    if k.startswith("$") or k == "onConsole":
        continue
    color = hexes[v.get("fill") or v.get("stroke")]
    paint = f'fill="{color}"' if "fill" in v else f'fill="none" stroke="{color}"'
    files[f"assets/Glyphs/{k}.svg"] = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10" width="18" height="18" {paint}>{v["svg"].replace(chr(39), chr(34))}</svg>\n'

check = "--check" in sys.argv
stale = []
for rel, text in files.items():
    p = out / rel
    if check:
        if not p.exists() or p.read_text() != text:
            stale.append(rel)
    else:
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
if check:
    if stale:
        print("design system out of date (run python3 scripts/gen-design-system.py): " + ", ".join(stale))
        sys.exit(1)
    print("design system tokens and icons are current")
else:
    print(f"wrote {len(files)} files under {out.relative_to(root)}: {len(colors)} colours, {sum(len(g['styles']) for g in typ['groups'])} type styles, "
          f"{len(spacing)} spacing, {len(radius)} radii, {len(layout) + len(search) + len(surfaces)} sizes")
