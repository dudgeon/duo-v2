const t0 = performance.now();
const a = await window._docs_annotate_getAnnotatedText('duo-probe');
const t1 = performance.now();
const text = a.getText();
const t2 = performance.now();
const anns = a.getAnnotations();
const t3 = performance.now();
let annSummary;
try { annSummary = {type: typeof anns, isArray: Array.isArray(anns), len: anns && anns.length,
  sample: JSON.stringify(anns, (k, v) => typeof v === 'function' ? 'fn' : v).slice(0, 1500)}; } catch (e) { annSummary = 'err ' + e; }
const i = text.indexOf('Session History');
a.setSelection(i, i + 'Session History'.length);
const t4 = performance.now();
await new Promise(r => setTimeout(r, 400));
const sel = a.getSelection();
const a2 = await window._docs_annotate_getAnnotatedText('duo-probe');
return {getMs: t1 - t0, textMs: t2 - t1, annMs: t3 - t2, setMs: t4 - t3, len: text.length, idx: i,
  tail: text.slice(-200), annSummary, selAfterSet: JSON.stringify(sel), selFresh: JSON.stringify(a2.getSelection()),
  selectedText: sel && sel[0] ? text.slice(sel[0].start, sel[0].end) : null, nativeSel: String(window.getSelection())};
