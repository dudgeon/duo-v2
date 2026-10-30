const a = await window._docs_annotate_getAnnotatedText('x');
const an = a.getAnnotations();
const out = {};
for (const k of Object.keys(an)) out[k] = {n: an[k].length, first: JSON.stringify(an[k][0]).slice(0, 200)};
return out;
