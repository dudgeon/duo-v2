// Duo's page around the renderer (ENH-12, DL-125): the slides top to bottom, the slide on screen,
// and the shape picker. Talks to DeckViewer through `duoDeck` messages and `window.__duo`, the
// same calls the HTML picker answers (PageHost), with selectors of the form "<slide>/<shape id>".
import { PptxViewer, RECOMMENDED_ZIP_LIMITS } from './pptx-renderer.js';

const post = (m) => { try { webkit.messageHandlers.duoDeck.postMessage(m); } catch (_) {} };
const host = document.getElementById('host');
const outline = document.getElementById('outline');
const tag = document.getElementById('tag');
let viewer = null, title = '', current = 0, picking = false, hovered = null, frozen = null, hidden = false;

const items = () => [...host.querySelectorAll('[data-slide-index]')];
const count = () => viewer ? viewer.slideCount : 0;

// A number above each slide, and the renderer's wrapper marked for the stylesheet.
function decorate(item) {
  if (!item || item.querySelector(':scope > .deck-number')) return;
  const n = document.createElement('div');
  n.className = 'deck-number';
  n.textContent = String(+item.dataset.slideIndex + 1);
  item.prepend(n);
  item.querySelector(':scope > div:not(.deck-number)')?.classList.add('deck-slide');
  if (+item.dataset.slideIndex === current - 1) n.classList.add('current');
}

// The slide on screen is the one filling most of the pane.
function track() {
  let best = 0, most = -1;
  const h = window.innerHeight;
  for (const it of items()) {
    const r = it.getBoundingClientRect();
    const seen = Math.min(r.bottom, h) - Math.max(r.top, 0);
    if (seen > most) { most = seen; best = +it.dataset.slideIndex + 1; }
  }
  if (best && best !== current) {
    current = best;
    for (const it of items()) it.querySelector(':scope > .deck-number')?.classList.toggle('current', +it.dataset.slideIndex === current - 1);
    post({ kind: 'slide', slide: current, count: count() });
  }
}
let trackTimer = null;
window.addEventListener('scroll', () => { clearTimeout(trackTimer); trackTimer = setTimeout(track, 50); }, { passive: true });
window.addEventListener('resize', () => { clearTimeout(trackTimer); trackTimer = setTimeout(() => { track(); place(frozen || hovered); }, 100); });

function shapeAt(slide, id) {
  return host.querySelector(`[data-slide-index="${slide - 1}"] [data-duo-shape-id="${CSS.escape(String(id))}"]`);
}

// What a shape is, for Duo: its slide, OOXML id, name, type, groups, text, box in slide pixels
// (96 per inch, as the outline gives), and where it is in the view (for its screenshot). Shaped
// so SendFormat.Element decodes it too; `shape` carries the deck's own fields.
function describe(el) {
  const item = el.closest('[data-slide-index]');
  const slide = +item.dataset.slideIndex + 1;
  const wrap = item.querySelector(':scope > .deck-slide') || item;
  const groups = [];
  for (let p = el.parentElement?.closest('[data-duo-shape-id]'); p; p = p.parentElement?.closest('[data-duo-shape-id]')) groups.unshift(p.dataset.duoShapeName);
  const r = el.getBoundingClientRect(), s = wrap.getBoundingClientRect();
  const k = viewer.slideWidth / s.width;
  const box = [Math.round((r.left - s.left) * k), Math.round((r.top - s.top) * k), Math.round(r.width * k), Math.round(r.height * k)];
  const text = (el.innerText || el.textContent || '').trim();
  const shape = { slide, count: count(), id: +el.dataset.duoShapeId, name: el.dataset.duoShapeName, type: el.dataset.duoShapeType,
                  groups, text, box, slideWidth: Math.round(viewer.slideWidth), slideHeight: Math.round(viewer.slideHeight) };
  return {
    tag: 'shape', label: shape.name, selector: `${slide}/${shape.id}`, trail: groups, text,
    attributes: { slide: String(slide), id: String(shape.id), type: shape.type }, styles: {},
    rect: box, html: '', url: location.href, title,
    viewRect: [r.left, r.top, r.width, r.height], shape,
  };
}

// The outline: dashed under the pointer while picking, solid once picked, with the name above.
function place(el) {
  if (!el || hidden) { outline.style.display = 'none'; tag.style.display = 'none'; return; }
  const r = el.getBoundingClientRect();
  const pad = el === frozen ? 0 : 3;
  Object.assign(outline.style, { display: 'block', left: `${r.left + scrollX - pad}px`, top: `${r.top + scrollY - pad}px`,
    width: `${r.width + 2 * pad}px`, height: `${r.height + 2 * pad}px` });
  outline.className = el === frozen ? 'frozen' : 'hover';
  tag.textContent = el.dataset.duoShapeName;
  Object.assign(tag.style, { display: 'block', left: `${r.left + scrollX - pad}px`, top: `${r.top + scrollY - pad - 20}px` });
}

document.addEventListener('mousemove', (e) => {
  if (!picking || frozen) return;
  const el = e.target.closest?.('[data-duo-shape-id]');
  if (el !== hovered) { hovered = el; place(el); }
}, true);
document.addEventListener('click', (e) => {
  if (!picking) return;
  e.preventDefault(); e.stopPropagation();
  if (frozen) return;
  const el = e.target.closest?.('[data-duo-shape-id]');
  if (!el) return;
  frozen = el; place(el);
  post({ kind: 'picked', element: describe(el) });
}, true);
document.addEventListener('keydown', (e) => {
  if (picking && e.key === 'Escape') { e.preventDefault(); stop(); post({ kind: 'pickEnded' }); return; }
  if (picking) return;
  if (e.key === 'PageDown' || e.key === 'ArrowRight') { e.preventDefault(); go(current + 1); }
  if (e.key === 'PageUp' || e.key === 'ArrowLeft') { e.preventDefault(); go(current - 1); }
}, true);

function start() { picking = true; frozen = null; hovered = null; document.body.classList.add('picking'); place(null); }
function stop() { picking = false; frozen = null; hovered = null; document.body.classList.remove('picking'); place(null); }
function go(n) {
  if (!viewer) return false;
  n = Math.max(1, Math.min(count(), n));
  items()[n - 1]?.scrollIntoView({ block: 'start' });
  scrollBy(0, -16);
  track();
  return true;
}

window.__duo = {
  // Opens the deck DeckViewer serves at deck.pptx (`v` defeats caching); shows `slide` (from 1).
  async open(name, slide, v) {
    title = name;
    stop();
    viewer?.destroy(); viewer = null; current = 0; host.innerHTML = '';
    try {
      const res = await fetch(`deck.pptx?v=${v}`);
      if (!res.ok) throw new Error(`deck.pptx: ${res.status}`);
      const bytes = new Uint8Array(await res.arrayBuffer());
      viewer = await PptxViewer.open(bytes, host, {
        zipLimits: RECOMMENDED_ZIP_LIMITS, fitMode: 'contain', pdfjs: false,
        onSlideRendered: (_, el) => decorate(el.closest?.('[data-slide-index]') || el),
      });
      items().forEach(decorate);
      if (slide > 1) go(slide); else track();
      post({ kind: 'ready', count: count(), slide: current, width: viewer.slideWidth, height: viewer.slideHeight });
      return { count: count() };
    } catch (err) {
      post({ kind: 'failed', reason: String(err && err.message || err) });
      return { error: String(err && err.message || err) };
    }
  },
  go, current: () => current, count,
  start, stop, unfreeze: () => { frozen = null; place(null); },
  freeze: (sel) => { const [s, id] = String(sel).split('/'); const el = shapeAt(+s, id); if (el) { picking = true; frozen = el; go(+s); place(el); post({ kind: 'picked', element: describe(el) }); } return !!el; },
  describe: (sel) => { const [s, id] = String(sel).split('/'); const el = shapeAt(+s, id); return el ? describe(el) : null; },
  // Every shape the renderer drew, for checks: slide, id, name, type, groups.
  shapes: () => [...host.querySelectorAll('[data-duo-shape-id]')].map((el) => { const d = describe(el).shape; return { slide: d.slide, id: d.id, name: d.name, type: d.type, groups: d.groups }; }),
  hover: (sel) => { const [s, id] = String(sel).split('/'); const el = shapeAt(+s, id); if (el && picking && !frozen) { hovered = el; place(el); } return !!el; },
  hideOutline: () => { hidden = true; place(null); },
  showOutline: () => { hidden = false; place(frozen); },
  selection: () => null,
};
// Anything the page's policy blocks is reported, so a renderer change that needs more shows up.
document.addEventListener('securitypolicyviolation', (e) => post({ kind: 'blocked', what: `${e.violatedDirective} ${e.blockedURI}` }));
post({ kind: 'loaded' });
