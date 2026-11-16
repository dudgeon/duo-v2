// Renders the study's boards (docs/design/btw-in-chat-study/project/*.dc.html) to static screens/*.html.
// A tiny stand-in for the Design canvas runtime: {{path}}, <sc-if>, <sc-for>, <dc-import>.
// Run from the repo root: node docs/design/btw-in-chat-handoff/export.mjs
import fs from 'node:fs';
const src = 'docs/design/btw-in-chat-study/project', out = 'docs/design/btw-in-chat-handoff/screens';
class DCLogic { constructor(p) { this.props = p; } }
const load = (n) => {
  const s = fs.readFileSync(`${src}/${n}.dc.html`, 'utf8');
  const tpl = (s.match(/<\/helmet>\n([\s\S]*?)\n<\/x-dc>/) || s.match(/<x-dc>\n([\s\S]*?)\n<\/x-dc>/))[1];
  const style = (s.match(/<style>([\s\S]*?)<\/style>/) || [, ''])[1];
  const code = s.match(/<script type="text\/x-dc"[^>]*>([\s\S]*?)<\/script>/)[1];
  const Cls = new Function('DCLogic', code + '\nreturn Component;')(DCLogic);
  return { tpl, style, Cls };
};
const cache = {};
const comp = (n) => (cache[n] = cache[n] || load(n));
const get = (scope, path) => path.split('.').reduce((o, k) => (o == null ? o : o[k]), scope);
const ev = (expr, scope) => { expr = expr.trim(); if (expr === 'true') return true; if (expr === 'false') return false; return get(scope, expr); };
const esc = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const attr = (tag, name) => (tag.match(new RegExp(`${name}="([^"]*)"`)) || [])[1];
const styles = new Set();
function render(tpl, scope) {
  let i = 0;
  const re = /<(\/?)(sc-for|sc-if)\b([^>]*)>|<dc-import\b([^>]*)><\/dc-import>/g;
  function parse() {
    const nodes = [];
    while (i < tpl.length) {
      re.lastIndex = i; const m = re.exec(tpl);
      if (!m) { nodes.push({ t: 'text', v: tpl.slice(i) }); i = tpl.length; break; }
      if (m.index > i) nodes.push({ t: 'text', v: tpl.slice(i, m.index) });
      i = m.index + m[0].length;
      if (m[1] === '/') return nodes;
      if (m[2]) nodes.push({ t: m[2], attrs: m[3], kids: parse() });
      else nodes.push({ t: 'imp', attrs: m[4] });
    }
    return nodes;
  }
  const tree = parse();
  const run = (nodes, sc) => nodes.map((n) => {
    if (n.t === 'text') return n.v.replace(/\{\{([^}]*)\}\}/g, (_, e) => esc(ev(e, sc)));
    if (n.t === 'sc-if') { const v = attr(n.attrs, 'value').match(/\{\{([^}]*)\}\}/)[1]; return ev(v, sc) ? run(n.kids, sc) : ''; }
    if (n.t === 'sc-for') {
      const l = ev(attr(n.attrs, 'list').match(/\{\{([^}]*)\}\}/)[1], sc) || [];
      const as = attr(n.attrs, 'as');
      return l.map((x) => run(n.kids, Object.assign({}, sc, { [as]: x }))).join('');
    }
    if (n.t === 'imp') {
      const name = attr(n.attrs, 'name'); const props = {};
      for (const [, k, v] of n.attrs.matchAll(/\s([\w-]+)="([^"]*)"/g)) {
        if (k === 'name' || k === 'hint-size') continue;
        const mm = v.match(/^\{\{([^}]*)\}\}$/); props[k] = mm ? ev(mm[1], sc) : v;
      }
      const c = comp(name); styles.add(c.style);
      return render(c.tpl, new c.Cls(props).renderVals());
    }
    return '';
  }).join('');
  return run(tree, scope);
}
const meta = JSON.parse(fs.readFileSync('docs/design/btw-in-chat-handoff/meta.json', 'utf8'));
for (const [file, m] of Object.entries(meta)) {
  styles.clear();
  const c = comp(file); const body = render(c.tpl, new c.Cls({}).renderVals());
  const [w, h] = m.size;
  fs.writeFileSync(`${out}/${m.name}.html`, `<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="design-size" content="${w}x${h}">
<meta name="design-kind" content="${m.kind}">
<meta name="design-surface" content="DL-344">
<!--
${m.note}
Geoff, 2026-11-16 (DL-344). Exported from the Design canvas https://claude.ai/artifact/L2NaLSyuma4dDhExA9SH4G (board ${file}.dc.html), rendered to static markup.
It is a picture written in HTML: match what it draws, do not port its markup. Names and data are illustrative.
-->
<title>Duo · /btw in chat · ${m.title}</title>
<style>${[c.style, ...styles].join('\n')}</style>
</head>
<body>
${body}
</body></html>
`);
  console.log('wrote', m.name);
}
