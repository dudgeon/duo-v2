import json, sys
P = json.load(open(sys.argv[1])); OUT = sys.argv[2]
C = {c['id']: c for c in P['colours']}
HUE_ORDER = ['coral','ochre','green','teal','blue','purple']           # 4a′ hue order
LIGHT = HUE_ORDER; DEEP = ['deep-' + h for h in HUE_ORDER]
T = {
 'light':   dict(ground='#F3F4F6', pane='#FFFFFF', text='#1F2328', text2='#5B636D', rule='#C9CDD3', edge='#8B939C', sel='#E9ECEF', needs='#C2410C', console='#15171B', ctext='#E6E8EB', ctext2='#9AA1AB', field='#FFFFFF', shadow='0 12px 32px rgba(31,35,40,0.22)', menu='#FFFFFF'),
 'dark':    dict(ground='#131518', pane='#181A1E', text='#E6E8EB', text2='#9AA1AB', rule='#2B2F36', edge='#6E7681', sel='#262A30', needs='#F97316', console='#0C0D10', ctext='#E6E8EB', ctext2='#9AA1AB', field='#181A1E', shadow='0 12px 32px rgba(0,0,0,0.5)', menu='#1F2227'),
 'classic': dict(ground='#F0E9D6', pane='#FBF8EE', text='#1A1410', text2='#7B6F58', rule='#D4C8A6', edge='#B8AB8E', sel='#F2D9B8', needs='#B91C1C', console='#1A1410', ctext='#F0E9D6', ctext2='#8A7E66', field='#FBF8EE', shadow='0 12px 32px rgba(31,35,40,0.22)', menu='#FFFFFF'),
}
FONT = "-apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif"
LBL = 'font-size: 11px; line-height: 16px; font-weight: 600; letter-spacing: 0.06em; color: #5B636D'
REC = '<span style="padding: 0 7px; border: 1px solid #8B939C; border-radius: 9px; font-size: 11px; line-height: 16px; background: #FFFFFF">recommended</span>'
STANDIN = '<span style="padding: 0 7px; border: 1px dashed #8B939C; border-radius: 9px; font-size: 11px; line-height: 16px; color: #5B636D">as built (stand-in)</span>'
def g(cid, mode, role='ground'):
    return C[cid][mode][role]
def name(cid): return C[cid]['name']
def lights(on): return ''.join(f'<span style="width: 10px; height: 10px; border-radius: 50%; background: {c}"></span>' for c in (['#FF5F57','#FEBC2E','#28C840'] if on else ['#C9CDD3']*3))
def swatch_btn(fill, crumb, edge, ring=None, size=10):
    rb = f'border: 1px solid {ring}; background: rgba(255,255,255,0.0);' if ring else 'border: 1px solid transparent;'
    return (f'<span style="display: inline-flex; flex: none; align-items: center; gap: 3px; padding: 2px 4px; border-radius: 5px; {rb}">'
            f'<span style="width: {size}px; height: {size}px; border-radius: 50%; border: 1px solid {edge}; background: {fill}"></span>'
            f'<svg width="7" height="5" viewBox="0 0 10 6" aria-hidden="true"><path d="M1 1l4 4 4-4" fill="none" stroke="{crumb}" stroke-width="1.6" stroke-linecap="round"></path></svg></span>')
def chip(t, coloured):
    bg = t['pane'] if coloured else 'transparent'
    return (f'<span style="display: inline-flex; align-items: center; gap: 5px; padding: 0 7px; border: 1.5px solid {t["needs"]}; border-radius: 6px; background: {bg}; color: {t["needs"]}; font-size: 11px; line-height: 18px; font-weight: 600">'
            f'<svg width="7" height="7" viewBox="0 0 10 10" aria-hidden="true"><circle cx="5" cy="5" r="5" fill="{t["needs"]}"></circle></svg>1 needs you</span>')
def toolbar(mode, cid, project=None, pos='after', w=620, ring=False, key=True, show_chip=True, search=True):
    """A full-size Duo toolbar. cid None = no colour. pos: after | left | none."""
    t = T[mode]; coloured = cid is not None and mode != 'classic'
    bg = g(cid, mode) if coloured else t['ground']
    crumb = t['text'] if coloured else t['text2']
    fill = g(cid, mode, 'swatch') if coloured else t['pane']
    sw = swatch_btn(fill, crumb, t['edge'], t['text'] if ring else None)
    parts = [f'<span style="display: inline-flex; gap: 6px; margin-right: 6px">{lights(key)}</span>']
    if pos == 'left' and mode != 'classic': parts.append(sw)
    if project:
        parts.append(f'<span style="color: {crumb}">All projects</span><svg width="7" height="10" viewBox="0 0 8 10" aria-hidden="true" style="flex: none"><path d="M2 1.5 6 5 2 8.5" fill="none" stroke="{crumb}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"></path></svg><span style="font-weight: 600">{project}</span>')
    else:
        parts.append('<span style="font-weight: 600">All projects</span>')
    if pos == 'after' and mode != 'classic': parts.append(sw)
    if show_chip: parts.append('<span style="margin-left: 6px">' + chip(t, coloured) + '</span>')
    if search:
        parts.append(f'<span style="display: inline-flex; align-items: center; width: {150 if w > 500 else 118}px; flex: none; height: 22px; box-sizing: border-box; margin-left: auto; padding: 0 8px; border: 1px solid {t["rule"]}; border-radius: 5px; background: {t["field"]}; color: {t["text2"]}; font-size: 11px">{"Search all projects" if w > 500 else "Search"}<span style="margin-left: auto">⇧⌘A</span></span>')
    return (f'<div style="display: flex; align-items: center; gap: 6px; width: {w}px; height: 38px; box-sizing: border-box; padding: 0 12px; border: 1px solid {t["edge"]}; border-radius: 8px 8px 0 0; '
            f'background: {bg}; color: {t["text"]}; font-size: 13px; white-space: nowrap">' + ''.join(parts) + '</div>')
def under(mode, cid, w=620, h=16):
    t = T[mode]; coloured = cid is not None and mode != 'classic'
    return f'<div style="width: {w}px; height: {h}px; box-sizing: border-box; border: 1px solid {t["edge"]}; border-top: 0; border-radius: 0 0 8px 8px; background: {g(cid, mode, "pane") if coloured else t["pane"]}"></div>'
def window_strip(mode, cid, **kw):
    w = kw.get('w', 620)
    return f'<div style="display: flex; flex-direction: column">{toolbar(mode, cid, **kw)}{under(mode, cid, w)}</div>'
def board(fname, title, label, heading, intro, body, h):
    s = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{title}</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<style>
body{{margin:0}}
</style>
</helmet>
<div style="width: 1720px; height: {h}px; box-sizing: border-box; padding: 40px 48px; display: flex; flex-direction: column; gap: 24px; background: #F3F4F6; color: #1F2328; font-family: {FONT}; font-size: 13px; line-height: 20px">
<div style="display: flex; flex-direction: column; gap: 4px">
<span style="{LBL}">{label}</span>
<span style="font-size: 22px; line-height: 28px; font-weight: 600">{heading}</span>
<span style="color: #5B636D; white-space: normal; max-width: 1480px">{intro}</span>
</div>
{body}
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":1720,"height":{h}}}}}'>
class Component extends DCLogic {{
  renderVals() {{
    return {{}};
  }}
}}
</script>
</body>
</html>
'''
    open(OUT + '/' + fname, 'w').write(s)
def option(head, badge, visual, caption):
    return (f'<div style="display: flex; flex-direction: column; gap: 12px; min-width: 0">'
            f'<span style="display: flex; gap: 8px; align-items: center"><span style="font-weight: 600">{head}</span>{badge}</span>'
            f'{visual}<span style="color: #5B636D; white-space: normal">{caption}</span></div>')
def grid(n, items, gap=40):
    return f'<div style="display: grid; grid-template-columns: repeat({n}, minmax(0, 1fr)); gap: {gap}px; align-items: start">' + ''.join(items) + '</div>'

# ---------------- 4b′ · Choosing from twelve (Q-444) ----------------
def sw(fill, edge, size=22, ring=None):
    b = f'2px solid {ring}' if ring else f'1px solid {edge}'
    return f'<span style="width: {size}px; height: {size}px; box-sizing: border-box; border-radius: 50%; border: {b}; background: {fill}; flex: none"></span>'
def popover_shell(mode, inner, w):
    t = T[mode]
    return (f'<div style="display: flex; flex-direction: column; gap: 10px; width: {w}px; box-sizing: border-box; padding: 12px; border: 1px solid {t["rule"]}; border-radius: 10px; background: {t["menu"]}; box-shadow: {t["shadow"]}; color: {t["text"]}; font-size: 12px; line-height: 18px">'
            f'<span style="font-weight: 600">Window Colour</span>{inner}'
            f'<span style="display: flex; align-items: center; gap: 7px; padding-top: 8px; border-top: 1px solid {t["rule"]}"><span style="width: 14px; height: 14px; border-radius: 3px; background: #2F6FEB; color: #FFFFFF; font-size: 10px; line-height: 14px; text-align: center">✓</span>Colour new windows automatically</span></div>')
def pop_named(mode, own):
    """Stand-in: None alone, light row over deep row, every name under its swatch."""
    t = T[mode]
    def cell(cid, label):
        fill = t['pane'] if cid is None else g(cid, mode, 'swatch')
        ring = t['text'] if cid == own else None
        return f'<span style="display: flex; flex-direction: column; align-items: center; gap: 3px; width: 58px; font-size: 11px; line-height: 13px; color: {t["text2"]}; text-align: center; white-space: normal">{sw(fill, t["edge"], 22, ring)}{label}</span>'
    rows = (f'<div style="display: flex">{cell(None, "None")}</div>'
            f'<div style="display: flex; gap: 2px">' + ''.join(cell(c, name(c)) for c in LIGHT) + '</div>'
            f'<div style="display: flex; gap: 2px">' + ''.join(cell(c, name(c)) for c in DEEP) + '</div>')
    return popover_shell(mode, rows, 384)
def pop_columns(mode, own):
    """Each hue a column, its name once on top; Light and Deep rows labelled at the left; None on its own row."""
    t = T[mode]
    def dot(cid):
        fill = t['pane'] if cid is None else g(cid, mode, 'swatch')
        return f'<span style="display: flex; justify-content: center; width: 46px">{sw(fill, t["edge"], 22, t["text"] if cid == own else None)}</span>'
    lab = lambda s: f'<span style="width: 40px; color: {t["text2"]}; font-size: 11px">{s}</span>'
    head = f'<div style="display: flex; align-items: center">{lab("")}' + ''.join(f'<span style="width: 46px; text-align: center; color: {t["text2"]}; font-size: 11px">{name(c)}</span>' for c in LIGHT) + '</div>'
    r1 = f'<div style="display: flex; align-items: center">{lab("Light")}' + ''.join(dot(c) for c in LIGHT) + '</div>'
    r2 = f'<div style="display: flex; align-items: center">{lab("Deep")}' + ''.join(dot(c) for c in DEEP) + '</div>'
    none = f'<div style="display: flex; align-items: center; gap: 8px">{sw(t["pane"], t["edge"], 22, t["text"] if own is None else None)}<span>None</span><span style="margin-left: auto; color: {t["text2"]}; font-size: 11px">{name(own) if own else "None"}</span></div>'
    return popover_shell(mode, none + f'<div style="display: flex; flex-direction: column; gap: 6px">{head}{r1}{r2}</div>', 340)
def menu_item(t, label, img=None, tick=False, dim=False, bold=False, arrow=False, hl=False):
    col = t['text2'] if dim else t['text']
    im = f'<span style="width: 12px; height: 12px; box-sizing: border-box; border-radius: 50%; border: 1px solid {t["edge"]}; background: {img}; flex: none; opacity: {0.45 if dim else 1}"></span>' if img else ''
    bg = f'background: {t["sel"]};' if hl else ''
    return (f'<span style="display: flex; align-items: center; gap: 6px; padding: 1px 8px; border-radius: 4px; {bg} color: {col}; {"font-weight: 600;" if bold else ""}">'
            f'<span style="width: 10px; flex: none">{"✓" if tick else ""}</span>{im}{label}{"<span style=&quot;margin-left: auto&quot;>›</span>" if arrow else ""}</span>')
def menu_rule(t): return f'<span style="height: 1px; margin: 3px 6px; background: {t["rule"]}"></span>'
def menu_box(t, items, w=170):
    return f'<div style="display: flex; flex-direction: column; width: {w}px; box-sizing: border-box; padding: 4px; border: 1px solid {t["rule"]}; border-radius: 8px; background: {t["menu"]}; box-shadow: {t["shadow"]}; color: {t["text"]}; font-size: 12px; line-height: 18px">' + ''.join(items) + '</div>'
def colour_menu(mode, own, order):
    t = T[mode]
    items = [menu_item(t, 'None', t['pane'], tick=own is None), menu_rule(t)]
    for k, cid in enumerate(order):
        if k == 6: items.append(menu_rule(t))
        items.append(menu_item(t, name(cid), g(cid, mode, 'swatch'), tick=cid == own))
    return menu_box(t, items, 160)
def window_menu(mode, sub, classic_dim=False, hl=True):
    t = T[mode]
    wm = menu_box(t, [menu_item(t, 'Minimize<span style="margin-left: auto; color: ' + t['text2'] + '">⌘M</span>'), menu_item(t, 'Zoom'), menu_rule(t),
                      menu_item(t, 'Window Colour', arrow=True, hl=hl and not classic_dim, dim=classic_dim), menu_rule(t),
                      menu_item(t, 'refunds', dim=True), menu_item(t, 'checkout', tick=True)], 180)
    bar = f'<div style="display: inline-flex; gap: 14px; padding: 4px 12px; border-radius: 6px; background: {t["menu"] if mode == "dark" else "transparent"}; font-size: 12px; color: {t["text"]}"><span>View</span><span>Project</span><span style="padding: 0 6px; border-radius: 4px; background: {t["sel"]}; font-weight: 600">Window</span></div>'
    return f'<div style="display: flex; flex-direction: column"><div style="padding-left: 40px">{bar}</div><div style="display: flex; align-items: flex-start; gap: 0"><div style="padding-left: 70px">{wm}</div><div style="margin-top: 52px; margin-left: -6px">{sub}</div></div></div>'
own = 'blue'
def stack(mode, cid, pop, project='checkout'):
    return (f'<div style="display: flex; flex-direction: column; gap: 0">{window_strip(mode, cid, project=project, ring=True, w=500, search=False)}'
            f'<div style="margin: -6px 0 0 150px">{pop}</div></div>')
A_vis = (f'<div style="display: flex; flex-direction: column; gap: 18px">{stack("light", own, pop_columns("light", own))}'
         f'{stack("dark", "deep-ochre", pop_columns("dark", "deep-ochre"))}</div>')
B_vis = (f'<div style="display: flex; flex-direction: column; gap: 18px">{stack("light", own, pop_named("light", own))}'
         f'{stack("dark", "deep-ochre", pop_named("dark", "deep-ochre"))}</div>')
M_vis = (f'<div style="display: flex; gap: 20px">{window_menu("light", colour_menu("light", own, LIGHT + DEEP))}</div>'
         f'<span style="{LBL}">ALTERNATIVE: THE MENU IN THE ORDER NEW WINDOWS TAKE THEM</span>'
         f'<div>{window_menu("dark", colour_menu("dark", "deep-ochre", P["order"]))}</div>')
body = grid(3, [
  option('A · Hue columns, named once [P]', REC, A_vis,
         'The twelve line up as on 4a′: one column per hue, its name once on top, the light step over the deep one, and rows labelled Light and Deep. None sits on its own row with the window\'s colour named at the right, so a click target is never guessed from a 22 pt dot. Six names instead of twelve, and each pair reads as the same hue at a glance. The ring in text marks the window\'s own.'),
  option('B · Every swatch named [P]', STANDIN, B_vis,
         'As slice 1 builds it: None alone, then the light row of six over the deep row of six, each name under its swatch in 11 pt text2. Clear, but twelve labels make a wide popover, and the deep names wrap at this width.'),
  option('The Window › Window Colour menu [P]', '', M_vis,
         'For both: None, a rule, the six light, a rule, the six deep, each with a 12 pt swatch image and a tick on the window\'s own, in 4a′\'s hue order so the menu matches the popover (recommended). The alternative lists them in the order new windows take them (Blue, Ochre, Purple …), which matches nothing you can see. Menus and popovers keep their own colours in a coloured window.'),
], 36)
board('ColourChoose.dc.html', 'Choosing from twelve', 'DECISION 4b′ · Q-444 · DL-313 · AFTER 4b',
      'Choosing from twelve: the swatch\'s popover and Window › Window Colour [P]',
      'Board 4b drew five colours (None, Sky, Sage, Lilac, Sand). DL-313 makes twelve plus None: Coral, Ochre, Green, Teal, Blue and Purple, each light and deep. Shown on a Blue window in light and a Deep ochre window in dark; the popover opens under the swatch, the menu from the menu bar.', body, 1080)

# ---------------- 4b″ · The swatch at All projects (Q-445) ----------------
def pair(mode, cid, pos):
    return (f'<div style="display: flex; flex-direction: column; gap: 8px">'
            f'{window_strip(mode, cid, project=None, pos=pos, w=500)}{window_strip(mode, cid, project="checkout", pos=pos, w=500)}</div>')
def opt_vis(pos):
    return (f'<div style="display: flex; flex-direction: column; gap: 14px"><span style="{LBL}">LIGHT · BLUE</span>{pair("light", "blue", pos)}'
            f'<span style="{LBL}">DARK · DEEP TEAL</span>{pair("dark", "deep-teal", pos)}</div>')
body = grid(3, [
  option('A · After the last crumb [P]', REC + STANDIN, opt_vis('after'),
         'The swatch always ends the breadcrumb: after “All projects” at All projects, after the project\'s name inside one. It is the window\'s own control next to the window\'s own name, so it moves with the name but is always in the same relation to it. As slice 1 builds it.'),
  option('B · At the toolbar\'s start [P]', '', opt_vis('left'),
         'Right after the traffic lights, in every window and at every altitude, so it never moves. But it sits apart from the name it describes and crowds the window\'s buttons, and it moves 4b\'s approved place.'),
  option('C · Not at All projects [P]', '', opt_vis('none').replace(pair('light', 'blue', 'none'), f'<div style="display: flex; flex-direction: column; gap: 8px">{window_strip("light", "blue", project=None, pos="none", w=500)}{window_strip("light", "blue", project="checkout", pos="after", w=500)}</div>').replace(pair('dark', 'deep-teal', 'none'), f'<div style="display: flex; flex-direction: column; gap: 8px">{window_strip("dark", "deep-teal", project=None, pos="none", w=500)}{window_strip("dark", "deep-teal", project="checkout", pos="after", w=500)}</div>'),
         'The swatch shows only inside a project; at All projects you change the colour from Window › Window Colour or duo2. Quieter, but the window still has its colour there, and the control you used a moment ago is gone.'),
], 36)
board('ColourAllProjects.dc.html', 'The swatch at All projects', 'DECISION 4b″ · Q-445 · DL-313 · AFTER 4b',
      'The swatch at All projects, where there is no project name [P]',
      'Board 4b puts the swatch after the project\'s name. At All projects the toolbar\'s title is “All projects” and there is no project name to follow. Each option shows the same window at All projects (top) and inside a project (below). On a coloured toolbar the crumb and the chevron draw in text (DL-313).', body, 620)

# ---------------- 4c′ · Window Colour under Classic (Q-446) ----------------
t = T['classic']
line = 'Window colours are off while Classic is on.'
def classic_strip(): return window_strip('classic', 'blue', project='checkout', w=520, search=True)
def tooltip(text): return f'<span style="display: inline-block; padding: 3px 8px; border: 1px solid {t["rule"]}; border-radius: 5px; background: #FFFFFF; box-shadow: 0 4px 12px rgba(31,35,40,0.18); font-size: 11px; line-height: 16px; color: {t["text"]}">{text}</span>'
LT = T['light']
def sub_dimmed():
    items = [f'<span style="display: block; padding: 2px 8px 4px; color: {LT["text2"]}; white-space: normal; font-size: 11px; line-height: 15px">{line} Each window gets its colour back when you choose another appearance.</span>', menu_rule(LT),
             menu_item(LT, 'None', LT['pane'], dim=True), menu_rule(LT)]
    for k, cid in enumerate(LIGHT + DEEP):
        if k == 6: items.append(menu_rule(LT))
        items.append(menu_item(LT, name(cid), g(cid, 'light', 'swatch'), tick=cid == 'blue', dim=True))
    items += [menu_rule(LT), menu_item(LT, 'Appearance Settings…')]
    return menu_box(LT, items, 210)
A_vis = (f'<div style="display: flex; flex-direction: column; gap: 14px">{classic_strip()}<div>{window_menu("light", sub_dimmed(), hl=True)}</div></div>')
B_vis = (f'<div style="display: flex; flex-direction: column; gap: 14px">{classic_strip()}<div style="position: relative; height: 170px">{window_menu("light", "", classic_dim=True, hl=False)}'
         f'<div style="position: absolute; left: 190px; top: 92px">{tooltip(line)}</div></div></div>')
def wm_hidden():
    tt = T['light']
    return menu_box(tt, [menu_item(tt, 'Minimize<span style="margin-left: auto; color: ' + tt['text2'] + '">⌘M</span>'), menu_item(tt, 'Zoom'), menu_rule(tt), menu_item(tt, 'refunds', dim=True), menu_item(tt, 'checkout', tick=True)], 180)
C_vis = (f'<div style="display: flex; flex-direction: column; gap: 14px">{classic_strip()}<div style="display: flex; flex-direction: column"><div style="padding-left: 40px"><div style="display: inline-flex; gap: 14px; padding: 4px 12px; font-size: 12px"><span>View</span><span>Project</span><span style="padding: 0 6px; border-radius: 4px; background: #E9ECEF; font-weight: 600">Window</span></div></div><div style="padding-left: 70px">{wm_hidden()}</div></div></div>')
body = grid(3, [
  option('A · The submenu opens and says why [P]', REC, A_vis,
         'Window Colour stays enabled. Its submenu opens with 4c\'s line at the top, then every colour dimmed, with a tick on the one this window gets back, and Appearance Settings… to leave Classic. The reason is in front of you without hovering, and nothing is forgotten. duo2 window colour still sets a window\'s colour and says it shows once Classic is off.'),
  option('B · Dimmed, the line as a tooltip [P]', STANDIN, B_vis,
         'As slice 1 builds it: the item is dimmed and its tooltip carries the line. Standard, but a dimmed item never opens and a tooltip needs a hover and a wait, so most people see only that the item is greyed.'),
  option('C · Hidden while Classic is on [P]', '', C_vis,
         'Window Colour leaves the menu, as the swatch leaves the toolbar. Tidy, but nothing says why it went, and the menu changes shape when you switch appearance.'),
], 36)
board('ColourClassicMenu.dc.html', 'Window Colour under Classic', 'DECISION 4c′ · Q-446 · DL-312 · AFTER 4c',
      'Window › Window Colour while Classic is on [P]',
      'Board 4c A (DL-312): Classic turns window colours off, the swatch leaves the toolbar, and Window › Window Colour “stays in the menu, dimmed, with the same line”, which 4c doesn\'t draw. The window here is checkout in Classic; it was Blue, and gets Blue back after Classic. The menus are the system\'s, in light.', body, 900)

# ---------------- 10′ · Naming the window Home is in (Q-447) ----------------
def allproj(mode, cid, home_msg, buttons, w=520):
    tt = T[mode]
    pane = g(cid, mode, 'pane') if cid else tt['pane']
    tile = lambda n, s, dot: (f'<div style="display: flex; flex-direction: column; gap: 2px; padding: 8px 10px; border: 1px solid {tt["rule"]}; border-radius: 6px; background: {tt["pane"] if mode=="light" else "#1F2227"}; font-size: 12px; line-height: 16px">'
                              f'<span style="font-weight: 600">{n}</span><span style="color: {tt["needs"] if dot else tt["text2"]}">{s}</span></div>')
    btns = ''.join(f'<span style="padding: 2px 10px; border: 1px solid {tt["ctext2"]}; border-radius: 5px; color: {tt["ctext"]}; font-size: 11px; line-height: 16px">{b}</span>' for b in buttons)
    return (f'<div style="display: flex; flex-direction: column; width: {w}px">{toolbar(mode, cid, project=None, w=w, search=True)}'
            f'<div style="display: flex; height: 240px; box-sizing: border-box; border: 1px solid {tt["edge"]}; border-top: 0; border-radius: 0 0 8px 8px; overflow: hidden; background: {pane}; color: {tt["text"]}">'
            f'<div style="width: 190px; flex: none; display: flex; flex-direction: column; background: {tt["console"]}; color: {tt["ctext"]}">'
            f'<span style="padding: 4px 10px; border-bottom: 1px solid {"#2B2F36" if mode=="light" else "#24272D"}; font-size: 11px; font-weight: 600">Home</span>'
            f'<div style="flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 10px; padding: 0 14px; text-align: center; white-space: normal; font-size: 12px; line-height: 17px">{home_msg}<span style="display: flex; gap: 6px">{btns}</span></div></div>'
            f'<div style="flex: 1; display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px; padding: 10px; align-content: start">'
            f'{tile("checkout", "1 needs you", True)}{tile("refunds", "1 needs you", True)}{tile("vendor-review", "2 working", False)}{tile("pricing", "3 idle", False)}</div></div></div>')
def named(cid, mode):
    tt = T[mode]
    return (f'<span>Home is showing in the <span style="display: inline-flex; align-items: center; gap: 4px; padding: 0 5px; border-radius: 4px; background: {g(cid, mode)}; color: {"#1F2328" if mode=="light" else "#E6E8EB"}; font-weight: 600">{name(cid)}</span> window</span>')
A_vis = (f'<div style="display: flex; flex-direction: column; gap: 14px"><span style="{LBL}">LIGHT · THIS WINDOW OCHRE, HOME IN THE BLUE ONE</span>{allproj("light", "ochre", named("blue", "light"), ["Show Here", "Go There"], 500)}'
         f'<span style="{LBL}">DARK · HOME IN THE DEEP BLUE ONE</span>{allproj("dark", "ochre", named("deep-blue", "dark"), ["Show Here", "Go There"], 500)}</div>')
B_vis = (f'<div style="display: flex; flex-direction: column; gap: 14px"><span style="{LBL}">LIGHT</span>{allproj("light", "ochre", "Home is showing in window 1", ["Show Here"], 500)}'
         f'<span style="{LBL}">DARK</span>{allproj("dark", "ochre", "Home is showing in window 1", ["Show Here"], 500)}</div>')
C_vis = (f'<div style="display: flex; flex-direction: column; gap: 14px"><span style="{LBL}">LIGHT</span>{allproj("light", "ochre", "Home is showing in another window", ["Show Here", "Go There"], 500)}'
         f'<span style="{LBL}">DARK</span>{allproj("dark", "ochre", "Home is showing in another window", ["Show Here", "Go There"], 500)}</div>')
body = grid(3, [
  option('A · By its colour, with Go There [P]', REC, A_vis,
         'Name the window the way you tell it apart: “Home is showing in the Blue window”, the name on a chip of that window\'s toolbar colour. Go There brings that window forward; Show Here moves Home\'s terminal here, as on board 10. A window with no colour (None, or Classic) is named by where it is: “in another window, at refunds”, or “at All projects”.'),
  option('B · By opening order [P]', STANDIN, B_vis,
         'As slice 1 builds it: “window ‹n›”, its place in the order windows were opened. True, but nothing on screen numbers windows any more: titles are project names, and the Window menu lists them by title.'),
  option('C · “Another window”, and Go There [P]', '', C_vis,
         'Don\'t name it; Go There takes you to it. Always right and the shortest line, but you have to go there to find out which window it is.'),
], 36)
board('HomeNamed.dc.html', 'Naming the window Home is in', 'DECISION 10′ · Q-447 · DL-311 · AFTER 10 B',
      'Naming the window Home is in [P]',
      'Board 10 B (DL-311): every window has All projects; Home\'s pane is live in one, and the others draw the dark pane with a line and Show Here. Board 10 said “window 1”, but windows are now titled by project (“Duo” at All projects), so a number names nothing you can see. This window is Ochre and at All projects; Home is live in another.', body, 960)
print('ok')
