#!/usr/bin/env python3
"""Duo Decks compiler prototype: check a deck against its template definition, and export it.

    deck.py check  <deck.md> [--templates <dir>]...
    deck.py export <deck.md> <out.pptx> [--templates <dir>]...
    deck.py templates <deck.md> [--templates <dir>]...

A stand-in for the Swift `duo2 deck check|export|templates` verbs the plan proposes. Its job is to
show that the convention parses deterministically, that errors can name a line and a fix, and that
export only fills the template's own placeholders by idx (no geometry of its own). Needs python-pptx
and pyyaml; the real thing would not.
"""
import re, sys, copy, pathlib
import yaml
from pptx import Presentation
from pptx.util import Pt

MARK = re.compile(r'^<!--\s*slide:\s*([a-z0-9-]+)\s*-->\s*$')
SLOT = re.compile(r'^##\s+([a-z0-9-]+)\s*$')
IMG = re.compile(r'^!\[([^\]]*)\]\(([^)\s]+)\)\s*$')


# ---------- the definition ----------

def load_pack(name, dirs):
    for d in dirs:
        md = pathlib.Path(d) / name / f'{name}.md'
        if md.exists():
            break
    else:
        sys.exit(f'no template pack "{name}" in {", ".join(map(str, dirs))}')
    text = md.read_text()
    front = yaml.safe_load(text.split('---\n')[1])
    templates = {}
    for m in re.finditer(r'^## ([a-z0-9-]+)\n\n(.*?)\n\n```yaml\n(.*?)```', text, re.S | re.M):
        spec = yaml.safe_load(m.group(3))
        spec['purpose'] = m.group(2).strip()
        templates[m.group(1)] = spec
    return md, front, templates


# ---------- the deck ----------

def parse(path):
    lines = pathlib.Path(path).read_text().split('\n')
    if lines[0] != '---':
        return None, [], [(1, 'a deck starts with frontmatter holding type: deck')]
    end = lines.index('---', 1)
    front = yaml.safe_load('\n'.join(lines[1:end]))
    slides, errors, cur, slot = [], [], None, None
    for n, line in enumerate(lines[end + 1:], start=end + 2):
        if m := MARK.match(line):
            cur = {'template': m.group(1), 'line': n, 'slots': {}, 'notes': []}
            slides.append(cur)
            slot = None
            continue
        if cur is None:
            if line.strip() and line.strip() != '---':
                errors.append((n, 'text before the first slide marker; start each slide with <!-- slide: name -->'))
            continue
        if line.strip() == '---':
            continue
        if line.startswith('# ') and 'title' not in cur['slots']:
            cur['slots']['title'] = {'line': n, 'lines': [line[2:].strip()]}
            slot = None
            continue
        if m := SLOT.match(line):
            slot = m.group(1)
            cur['slots'][slot] = {'line': n, 'lines': []}
            continue
        if line.startswith('> [!note]'):
            slot = '_notes'
            continue
        if slot == '_notes' and line.startswith('>'):
            cur['notes'].append(line[1:].strip())
            continue
        if not line.strip():
            if slot == '_notes':
                slot = None
            continue
        key = slot or ('_image' if IMG.match(line) else '_default')
        cur['slots'].setdefault(key, {'line': n, 'lines': []})['lines'].append(line)
    return front, slides, errors


def check(deck, dirs):
    front, slides, errors = parse(deck)
    if front is None:
        return None, None, slides, errors
    if front.get('type') != 'deck':
        errors.append((2, 'frontmatter needs type: deck'))
    md, pack, templates = load_pack(front.get('template', ''), dirs)
    for i, s in enumerate(slides, 1):
        t = templates.get(s['template'])
        where = f'slide {i} ({s["template"]})'
        if not t:
            errors.append((s['line'], f'{where}: no template "{s["template"]}" in {md.name}; use one of {", ".join(templates)}'))
            continue
        slots = t['slots']
        if '_default' in s['slots']:
            default = next((k for k, v in slots.items() if v.get('default')), None)
            if not default:
                errors.append((s['slots']['_default']['line'], f'{where}: text with no slot heading, and {s["template"]} has no default slot'))
            elif default in s['slots']:
                errors.append((s['slots']['_default']['line'], f'{where}: text with no slot heading, but "## {default}" is also given'))
            else:
                s['slots'][default] = s['slots'].pop('_default')
        if '_image' in s['slots']:
            pics = [k for k, v in slots.items() if v['kind'] == 'image']
            if len(pics) == 1 and pics[0] not in s['slots']:
                s['slots'][pics[0]] = s['slots'].pop('_image')
            else:
                errors.append((s['slots'].pop('_image')['line'], f'{where}: an image with no slot heading; {s["template"]} has no single image slot to put it in'))
        for name, got in s['slots'].items():
            spec = slots.get(name)
            if not spec:
                errors.append((got['line'], f'{where}: no slot "{name}"; {s["template"]} has {", ".join(slots)}'))
                continue
            errors += [(got['line'], f'{where}, {name}: {e}') for e in check_slot(spec, got['lines'], deck)]
    return front, templates, slides, errors


def check_slot(spec, lines, deck):
    kind, out = spec['kind'], []
    if kind in ('text', 'number'):
        text = ' '.join(l.strip() for l in lines)
        if any(l.lstrip().startswith(('- ', '* ', '|', '![')) for l in lines):
            out.append(f'is a {kind} slot; write a sentence, not a list, table or image')
        if len(text) > spec.get('max', 10**6):
            out.append(f'is {len(text)} characters; the template allows {spec["max"]}. Shorten it, or split the slide')
    elif kind == 'bullets':
        items = [l for l in lines if re.match(r'^\s*[-*] ', l)]
        if len(items) != len(lines):
            out.append('takes a list: one "- " line per point')
        top = [l for l in items if not l.startswith(' ')]
        if len(top) > spec.get('items', 99):
            out.append(f'has {len(top)} points; the template allows {spec["items"]}. Split the slide; never shrink the text')
        if any(len(l) - len(l.lstrip()) >= 2 * spec.get('levels', 1) for l in items):
            out.append(f'nests deeper than {spec.get("levels", 1)} levels')
        for l in items:
            if len(l.strip()) - 2 > spec.get('max', 10**6):
                out.append(f'a point is {len(l.strip()) - 2} characters; the template allows {spec["max"]}')
    elif kind == 'image':
        m = IMG.match(lines[0]) if len(lines) == 1 else None
        if not m:
            out.append('takes one image: ![alt](path)')
        elif not (pathlib.Path(deck).parent / m.group(2)).exists():
            out.append(f'no file {m.group(2)} next to the deck')
    elif kind == 'table':
        rows = [l for l in lines if l.startswith('|') and not re.match(r'^\|[-| :]+\|$', l)]
        if len(rows) != len(lines) - 1:
            out.append('takes one Markdown table, a header row first')
        if len(rows) > spec.get('rows', 99):
            out.append(f'has {len(rows)} rows; the template allows {spec["rows"]}')
    return out


# ---------- export: fill the layout's placeholders by idx ----------

def runs(par, text):
    for i, part in enumerate(re.split(r'(\*\*[^*]+\*\*)', text)):
        if not part:
            continue
        r = par.add_run()
        r.text = part.strip('*') if part.startswith('**') else part
        if part.startswith('**'):
            r.font.bold = True


def export(deck, out, dirs):
    front, templates, slides, errors = check(deck, dirs)
    if errors:
        report(deck, errors)
        sys.exit(1)
    md, pack, _ = load_pack(front['template'], dirs)
    prs = Presentation(str(md.parent / pack['pptx']))
    layouts = {l.name: l for l in prs.slide_layouts}
    for s in slides:
        t = templates[s['template']]
        layout = layouts[t['layout']]
        slide = prs.slides.add_slide(layout)
        # python-pptx leaves footer and slide-number placeholders off new slides (F-466): clone them
        for ph in layout.placeholders:
            if ph.placeholder_format.type in (15, 13) and ph.placeholder_format.idx not in [p.placeholder_format.idx for p in slide.placeholders]:
                el = copy.deepcopy(ph._element)
                slide.shapes._spTree.append(el)
        phs = {p.placeholder_format.idx: p for p in slide.placeholders}
        for name, got in s['slots'].items():
            spec, ph = t['slots'][name], phs[t['slots'][name]['idx']]
            kind, lines = spec['kind'], got['lines']
            if kind in ('text', 'number'):
                tf = ph.text_frame
                tf.text = ''
                runs(tf.paragraphs[0], ' '.join(l.strip() for l in lines))
            elif kind == 'bullets':
                tf = ph.text_frame
                tf.text = ''
                for j, l in enumerate(lines):
                    p = tf.paragraphs[0] if j == 0 else tf.add_paragraph()
                    p.level = (len(l) - len(l.lstrip())) // 2
                    runs(p, l.strip()[2:])
            elif kind == 'image':
                ph.insert_picture(str(pathlib.Path(deck).parent / IMG.match(lines[0]).group(2)))
            elif kind == 'table':
                rows = [[c.strip() for c in l.strip('|').split('|')] for l in lines if not re.match(r'^\|[-| :]+\|$', l)]
                tbl = ph.insert_table(len(rows), len(rows[0])).table
                for r, row in enumerate(rows):
                    for c, cell in enumerate(row):
                        tbl.cell(r, c).text = cell
        for p in slide.placeholders:
            if p.placeholder_format.type == 15 and front.get('footer'):   # FOOTER
                p.text_frame.text = front['footer']
        if s['notes']:
            slide.notes_slide.notes_text_frame.text = '\n'.join(s['notes'])
    prs.core_properties.title = front.get('title', '')
    prs.save(out)
    print(f'{out}: {len(slides)} slides from {md.name}')


def report(deck, errors):
    for line, msg in sorted(errors):
        print(f'{deck}:{line}: {msg}')
    print(f'{len(errors)} problem{"s" if len(errors) != 1 else ""}' if errors else 'no problems')


def main():
    args, dirs = [], []
    it = iter(sys.argv[1:])
    for a in it:
        if a == '--templates':
            dirs.append(next(it))
        else:
            args.append(a)
    cmd, deck = args[0], args[1]
    dirs = dirs or [pathlib.Path(deck).parent.parent / 'templates' / 'decks']
    if cmd == 'check':
        _, _, _, errors = check(deck, dirs)
        report(deck, errors)
        sys.exit(1 if errors else 0)
    if cmd == 'templates':
        front, _, _ = parse(deck)
        md, pack, templates = load_pack(front['template'], dirs)
        print(f'{front["template"]} ({md})')
        for k, t in templates.items():
            slots = ', '.join(f'{n}: {v["kind"]}' + (f' ≤{v["max"]}' if 'max' in v else '') +
                              (f' ×{v["items"]}' if 'items' in v else '') + (' (default)' if v.get('default') else '')
                              for n, v in t['slots'].items())
            print(f'  {k:<11} {slots}')
            print(f'  {"":<11} {t["purpose"].splitlines()[0]}')
        return
    if cmd == 'export':
        export(deck, args[2], dirs)


if __name__ == '__main__':
    main()
