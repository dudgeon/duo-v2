const out = {};
for (const id of ['duo-probe', '']) {
  try { const a = window._docs_annotate_getAnnotatedText(id);
        const o = await Promise.resolve(a);
        out[id||'empty'] = {type: typeof o, keys: o ? Object.getOwnPropertyNames(Object.getPrototypeOf(o)).concat(Object.keys(o)).slice(0,40) : null,
          text: o && o.getText ? String(o.getText()).slice(0, 300) : null,
          sel: o && o.getSelection ? JSON.stringify(o.getSelection()) : null};
  } catch (e) { out[id||'empty'] = 'err ' + e; }
}
out.flags = {annotate: window._docs_annotate_canvas_by_ext, forceHtml: window._docs_force_html_by_ext};
return out;
