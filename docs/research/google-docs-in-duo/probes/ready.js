const t0 = performance.now(); let n = 0;
while (typeof window._docs_annotate_getAnnotatedText !== 'function' && n < 200) { await new Promise(r => setTimeout(r, 25)); n++; }
const a = await window._docs_annotate_getAnnotatedText('x');
return {navToHookMs: Math.round(performance.now()), waitedMs: Math.round(performance.now() - t0), len: a.getText().length};
