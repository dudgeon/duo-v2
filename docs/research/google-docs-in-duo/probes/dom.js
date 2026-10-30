const q = s => document.querySelectorAll(s).length;
const svgRects = [...document.querySelectorAll('.kix-canvas-tile-content svg rect[aria-label], svg rect[aria-label]')];
const iframes = [...document.querySelectorAll('iframe')].map(f => ({cls: f.className, title: f.title, src: (f.src||'').slice(0,80)}));
let tet = null;
try { const f = document.querySelector('.docs-texteventtarget-iframe'); const b = f && f.contentDocument && f.contentDocument.body; tet = b ? {editable: b.isContentEditable, html: b.innerHTML.slice(0,200), active: f.contentDocument.activeElement && f.contentDocument.activeElement.tagName} : 'no access'; } catch (e) { tet = 'err ' + e; }
let ann = null;
try { ann = typeof window._docs_annotate_getAnnotatedText; } catch (e) { ann = 'err ' + e; }
const bodyText = document.body.innerText;
return {
  title: document.title, ready: document.readyState, vis: document.visibilityState,
  canvases: q('canvas'), kixCanvasTiles: q('.kix-canvas-tile-content'), kixPages: q('.kix-page-paginated, .kix-page'),
  kixLineviews: q('.kix-lineview'), kixParagraphs: q('.kix-paragraphrenderer'),
  svgRectsWithLabel: svgRects.length, svgRectSample: svgRects.slice(0,5).map(r => r.getAttribute('aria-label')),
  ariaLive: [...document.querySelectorAll('[aria-live]')].map(e => ({live: e.getAttribute('aria-live'), text: e.innerText.slice(0,80)})).slice(0,8),
  roleDocument: q('[role=document]'), roleTextbox: q('[role=textbox]'),
  iframes, tet, annotateFn: ann,
  kixAppPresent: typeof window.KX_kixApp,
  bodyTextLen: bodyText.length, bodyTextHead: bodyText.slice(0, 600),
  selectionNative: String(window.getSelection()),
  modelChunkType: typeof window.DOCS_modelChunk,
};
