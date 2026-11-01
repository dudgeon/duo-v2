// Duo's page around the renderer (ENH-12, DL-125): the slides top to bottom, the slide on screen,
// and the shape picker. Talks to DeckViewer through `duoDeck` messages and `window.__duo`, the
// same calls the HTML picker answers (PageHost), with selectors of the form "<slide>/<shape id>".
import { PptxViewer, RECOMMENDED_ZIP_LIMITS } from './pptx-renderer.js';

const post = (m) => { try { webkit.messageHandlers.duoDeck.postMessage(m); } catch (_) {} };
let host = document.getElementById('host');
let spare = document.getElementById('spare');   // a redraw is made here, out of sight, then swapped in
const outline = document.getElementById('outline');
const tag = document.getElementById('tag');
let viewer = null, title = '', current = 0, picking = false, hovered = null, frozen = null, hidden = false;
// What Duo draws around the slides (P3b): cards under a slide, comment pins on a slot or slide, each slide's
// template beside its number, and tick boxes while slides are being picked (Make Templates, DL-291).
let overlay = { cards: [], pins: [], templates: [], shapes: {} };
let slidePicking = false, slidePicks = new Set();

const items = () => [...host.querySelectorAll('[data-slide-index]')];
const count = () => viewer ? viewer.slideCount : 0;

// A number above each slide, and the renderer's wrapper marked for the stylesheet.
function decorate(item) {
  if (!item || item.querySelector(':scope > .deck-number')) return;
  const n = document.createElement('div');
  n.className = 'deck-number';
  n.textContent = numberLabel(+item.dataset.slideIndex + 1);
  item.prepend(n);
  item.querySelector(':scope > div:not(.deck-number)')?.classList.add('deck-slide');
  if (+item.dataset.slideIndex === current - 1) n.classList.add('current');
}

const numberLabel = (k) => overlay.templates[k - 1] ? `${k} · ${overlay.templates[k - 1]}` : String(k);

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

// Motion (DL-130): durations from Duo's tokens (`--duo-motion-*-ms`, zero with Reduce Motion),
// and none when the system asks for reduced motion.
function motionMs(name) {
  if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) return 0;
  return parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--duo-motion-' + name + '-ms')) || 0;
}

// The outline: dashed under the pointer while picking, solid once picked, with the name above.
// It glides from shape to shape (`motion.outline`), and appears where it lands.
function place(el) {
  if (!el || hidden) { outline.style.display = 'none'; tag.style.display = 'none'; return; }
  const r = el.getBoundingClientRect();
  const pad = el === frozen ? 0 : 3;
  const ms = outline.style.display === 'block' ? motionMs('outline') : 0;
  const glide = ms > 0 ? ['left', 'top', 'width', 'height'].map((p) => `${p} ${ms}ms ease-out`).join(', ') : 'none';
  outline.style.transition = glide;
  tag.style.transition = ms > 0 ? `left ${ms}ms ease-out, top ${ms}ms ease-out` : 'none';
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
  if (slidePicking) {
    const item = e.target.closest?.('[data-slide-index]');
    if (!item) return;
    e.preventDefault(); e.stopPropagation();
    const k = +item.dataset.slideIndex + 1;
    if (slidePicks.has(k)) slidePicks.delete(k); else slidePicks.add(k);
    markPicks(); post({ kind: 'slidePicks', slides: [...slidePicks].sort((a, b) => a - b) });
    return;
  }
  if (!picking) return;
  e.preventDefault(); e.stopPropagation();
  if (frozen) return;
  const el = e.target.closest?.('[data-duo-shape-id]');
  if (!el) return;
  frozen = el; place(el);
  post({ kind: 'picked', element: describe(el) });
}, true);
document.addEventListener('keydown', (e) => {
  if (slidePicking && e.key === 'Escape') { e.preventDefault(); setSlidePicking(false); post({ kind: 'slidePickEnded' }); return; }
  if (picking && e.key === 'Escape') { e.preventDefault(); stop(); post({ kind: 'pickEnded' }); return; }
  if (picking) return;
  if (e.key === 'PageDown' || e.key === 'ArrowRight') { e.preventDefault(); go(current + 1); }
  if (e.key === 'PageUp' || e.key === 'ArrowLeft') { e.preventDefault(); go(current - 1); }
}, true);

function start() { picking = true; frozen = null; hovered = null; document.body.classList.add('picking'); place(null); }
function stop() { picking = false; frozen = null; hovered = null; document.body.classList.remove('picking'); place(null); }
function go(n, instant) {
  if (!viewer) return false;
  n = Math.max(1, Math.min(count(), n));
  const it = items()[n - 1];
  if (!it) return false;
  const to = Math.max(0, it.getBoundingClientRect().top + scrollY - 16), from = scrollY;
  const ms = instant ? 0 : motionMs('slide');
  // A smooth scroll to the slide (`motion.slide`, ease-in-out): CSS's smooth scroll has no duration.
  cancelAnimationFrame(glideFrame);
  if (ms <= 0 || Math.abs(to - from) < 1) { scrollTo(0, to); track(); return true; }
  const t0 = performance.now();
  const step = (now) => {
    const t = Math.min(1, (now - t0) / ms), e = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
    scrollTo(0, from + (to - from) * e);
    if (t < 1) glideFrame = requestAnimationFrame(step); else { clearTimeout(glideSafety); track(); }
  };
  glideFrame = requestAnimationFrame(step);
  // A page that isn't on screen gets no animation frames (F-102): land on the slide anyway.
  clearTimeout(glideSafety);
  glideSafety = setTimeout(() => { cancelAnimationFrame(glideFrame); scrollTo(0, to); track(); }, ms + 150);
  return true;
}
let glideFrame = 0, glideSafety = 0;

// ---- Duo's marks round the slides -----------------------------------------------------------------
const SPEECH = '<svg width="11" height="11" viewBox="0 0 11 11" fill="none" stroke="currentColor" stroke-width="1" stroke-linejoin="round"><path d="M1.5 1.5h8v5.5H5.5L3 9.2V7H1.5z"/></svg>';
const el_ = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; };

function applyOverlay() {
  host.querySelectorAll('.deck-card, .deck-pin, .deck-tick').forEach((e) => e.remove());
  for (const item of items()) {
    const k = +item.dataset.slideIndex + 1;
    const num = item.querySelector(':scope > .deck-number');
    if (num) num.textContent = numberLabel(k);
    const wrap = item.querySelector(':scope > .deck-slide') || item;
    item.style.position = 'relative';
    // Cards go under the slide, in the order given.
    overlay.cards.forEach((c, idx) => {
      if (c.slide !== k) return;
      const card = el_('div', 'deck-card ' + c.kind);
      card.dataset.card = String(idx);
      const msg = el_('div', 'deck-card-msg');
      if (c.slot) msg.append(el_('b', null, c.slot), document.createTextNode(' ' + c.message));
      else msg.textContent = c.message;
      const row = el_('div', 'deck-card-buttons');
      for (const b of c.buttons) {
        const btn = el_('button', null, b.label);
        btn.addEventListener('click', (ev) => { ev.stopPropagation(); post({ kind: 'card', index: idx, button: b.id }); });
        row.append(btn);
      }
      card.append(msg, row);
      item.append(card);
    });
    // Pins: at a slot box's top right, or the slide's.
    const ir = item.getBoundingClientRect();
    for (const p of overlay.pins) {
      if (p.slide !== k) continue;
      let el = null;
      const id = p.slot && overlay.shapes[k] ? overlay.shapes[k][p.slot] : null;
      if (id != null) el = shapeAt(k, id);
      const pin = el_('button', 'deck-pin');
      pin.innerHTML = SPEECH;
      pin.append(el_('span', null, String(p.count)));
      pin.title = p.slot ? `Comment on ${p.slot}` : 'Comment on this slide';
      const wr = wrap.getBoundingClientRect();
      if (el) {
        const r = el.getBoundingClientRect();
        pin.style.left = `${Math.round(r.right - ir.left + 4)}px`;
        pin.style.top = `${Math.round(r.top - ir.top - 2)}px`;
      } else {
        pin.style.right = `${Math.round(ir.right - wr.right + 8)}px`;
        pin.style.top = `${Math.round(wr.top - ir.top + 8)}px`;
      }
      pin.addEventListener('mouseenter', () => { if (el && !picking) { hovered = el; place(el); } });
      pin.addEventListener('mouseleave', () => { if (!picking) place(null); });
      pin.addEventListener('click', (ev) => { ev.preventDefault(); ev.stopPropagation(); post({ kind: 'pin', thread: p.thread }); });
      item.append(pin);
      if (el) {   // a box that reaches the slide's edge keeps its pin inside the slide
        const lim = wr.right - ir.left - pin.offsetWidth - 4;
        if (parseFloat(pin.style.left) > lim) pin.style.left = `${Math.round(lim)}px`;
      }
    }
    if (slidePicking) {
      const t = el_('div', 'deck-tick'); t.innerHTML = '<svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M2.5 6.4l2.4 2.4 4.6-5"/></svg>';
      t.style.top = `${Math.round(wrap.getBoundingClientRect().top - ir.top + 10)}px`;
      item.append(t);
    }
  }
  markPicks();
}
function markPicks() {
  for (const item of items()) {
    const k = +item.dataset.slideIndex + 1, on = slidePicking && slidePicks.has(k);
    item.classList.toggle('slide-picked', on);
    item.classList.toggle('slide-picking', slidePicking);
  }
}
// While picking slides they lie in a grid (board 9A): 2 columns under 640 pt of pane, 3 from there. The renderer
// sizes a slide to the host's width times its zoom, so the zoom is the column's share of the width; leaving puts
// it back to 1 and returns to the slide that was on screen.
const GRID_GAP = 16;
const gridCols = () => window.innerWidth < 640 ? 2 : 3;
async function fitGrid(on) {
  if (!viewer) return;
  const w = host.clientWidth || 1;
  const cols = on ? gridCols() : 1;
  host.style.gridTemplateColumns = on ? `repeat(${cols}, minmax(0, 1fr))` : '';
  const z = on ? ((w - (cols - 1) * GRID_GAP) / cols) / w : 1;
  await viewer.setZoom(Math.max(10, z * 100));
  items().forEach(decorate);
  applyOverlay();
}
async function setSlidePicking(on) {
  const keep = current;
  slidePicking = on;
  if (!on) slidePicks = new Set();
  document.body.classList.toggle('slide-picking', on);
  host.classList.toggle('grid', on);
  await fitGrid(on);
  if (keep > 0) go(keep, true);
  track();
}
window.addEventListener('resize', () => { if (slidePicking) fitGrid(true); });


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
      applyOverlay();
      if (slide > 1) go(slide, true); else track();   // opening lands on the slide, no scroll
      post({ kind: 'ready', count: count(), slide: current, width: viewer.slideWidth, height: viewer.slideHeight });
      return { count: count() };
    } catch (err) {
      post({ kind: 'failed', reason: String(err && err.message || err) });
      return { error: String(err && err.message || err) };
    }
  },
  // Draws the deck again (an edit in the split view's source, DL-275): the new drawing is made out of
  // sight and swapped in, so the slides don't blink and the pane keeps its scroll and its slide.
  async refresh(name, slide, v) {
    if (!viewer) return window.__duo.open(name, slide, v);
    title = name;
    stop();
    const y = scrollY, keep = current;
    try {
      const res = await fetch(`deck.pptx?v=${v}`);
      if (!res.ok) throw new Error(`deck.pptx: ${res.status}`);
      const bytes = new Uint8Array(await res.arrayBuffer());
      spare.innerHTML = '';
      const next = await PptxViewer.open(bytes, spare, {
        zipLimits: RECOMMENDED_ZIP_LIMITS, fitMode: 'contain', pdfjs: false,
        onSlideRendered: (_, el) => decorate(el.closest?.('[data-slide-index]') || el),
      });
      const old = viewer, oldHost = host;
      viewer = next; host = spare; spare = oldHost;
      host.classList.remove('staged'); spare.classList.add('staged');
      old.destroy(); spare.innerHTML = '';
      current = Math.min(keep, count()) || 1;
      items().forEach(decorate);
      if (slidePicking) { host.classList.add('grid'); await fitGrid(true); }
      applyOverlay();
      scrollTo(0, y); track();
      post({ kind: 'ready', count: count(), slide: current, width: viewer.slideWidth, height: viewer.slideHeight });
      return { count: count() };
    } catch (err) {
      post({ kind: 'failed', reason: String(err && err.message || err) });
      return { error: String(err && err.message || err) };
    }
  },
  // Duo's marks: { cards, pins, templates, shapes } (see DeckViewer.setOverlay); drawn now, and after each redraw.
  overlay(o) { overlay = Object.assign({ cards: [], pins: [], templates: [], shapes: {} }, o); applyOverlay(); return true; },
  slidePicking: async (on) => { await setSlidePicking(!!on); return true; },
  setSlidePicks: (list) => { slidePicks = new Set(list); markPicks(); return true; },
  overlayState: () => ({ cards: host.querySelectorAll('.deck-card').length, pins: host.querySelectorAll('.deck-pin').length, ticks: host.querySelectorAll('.deck-tick').length }),
  go, current: () => current, count,
  start, stop, unfreeze: () => { frozen = null; place(null); },
  freeze: (sel) => { const [s, id] = String(sel).split('/'); const el = shapeAt(+s, id); if (el) { picking = true; frozen = el; go(+s, true); place(el); post({ kind: 'picked', element: describe(el) }); } return !!el; },
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
