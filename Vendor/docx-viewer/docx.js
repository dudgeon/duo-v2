// Duo's page around the renderer (DL-162, docx-viewer-handoff): the document at the pane's width,
// never paginated, and Duo's review layer over it: per-person colours, comment cards, the label
// above a change, the four markup views, one person at a time. Talks to DocxViewer through
// `duoDocx` messages and `window.__duo`. Read only: the bytes come in through `doc.docx`, and
// nothing here can write them (the page has no way to reach the file but that one GET).
import { renderAsync, collectDocxReviewChanges } from './docx-preview.mjs';

const dev = new URLSearchParams(location.search);
const devDoc = location.protocol === 'http:' ? dev.get('doc') : null;
const post = (m) => { try { webkit.messageHandlers.duoDocx.postMessage(m); } catch (_) {} };
const host = document.getElementById('host');
const label = document.getElementById('label');
let doc = null, changes = [], people = [], threads = [], title = '', cfg = defaults();

function defaults() { return { mode: 'all', comments: true, resolved: false, person: null }; }

// The renderer's own review modes: All and Simple keep every mark in the DOM (CSS below draws the
// difference); No Markup is its "final", Original its "original".
const RENDERER_MODE = { all: 'all', simple: 'simple', none: 'final', original: 'original' };
const KINDS = { insert: 'inserted', delete: 'deleted', 'move-from': 'moved', 'move-to': 'moved', format: 'formatted' };
const PROPERTY = { b: 'Bold', i: 'Italic', u: 'Underline', color: 'Font colour', jc: 'Alignment', sz: 'Size', strike: 'Strikethrough' };

const colourIndex = (name) => { let i = people.findIndex((p) => p.name === name); if (i < 0) { people.push({ name, count: 0 }); i = people.length - 1; } return i; };
const colourOf = (name) => `var(--duo-review-author-${(colourIndex(name) % 5) + 1})`;
const day = (iso) => { const d = new Date(iso); return isNaN(d) ? '' : d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }); };
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const isMark = (el) => el.matches?.('[data-docx-change-kind]:not(.docx-comment-anchor), [data-docx-format-change]');

function describeFormat(list) {
  return (list || []).map(({ property: p, after }) => {
    const name = PROPERTY[p] || p, v = String(after ?? '').replace(/^val=/, '');
    return after === undefined ? `Not ${name}` : (v === 'true' || v === '' ? name : `${name}: ${v}`);
  }).join(', ');
}

// ---- the review layer ----------------------------------------------------------------------

function layer() {
  people = []; threads = [];
  // 1. People in the order they first appear in the document, then in the comments part.
  for (const c of changes) if (c.author) colourIndex(c.author);
  for (const c of doc.commentsPart?.comments ?? []) if (c.author) colourIndex(c.author);
  for (const el of host.querySelectorAll('[data-docx-change-author]')) el.style.setProperty('--duo-author', colourOf(el.dataset.docxChangeAuthor));
  const byId = new Map(changes.map((c) => [String(c.id), c]));
  for (const c of changes) if (c.kind !== 'comment' && c.author) people[colourIndex(c.author)].count++;

  // 2. Paragraphs that hold a change; those that vanish with changes accepted, or in Original.
  for (const p of host.querySelectorAll('p')) {
    const marks = [...p.querySelectorAll('ins[data-docx-change-kind], del[data-docx-change-kind], [data-docx-format-change]')];
    if (!marks.length) continue;
    p.classList.add('duo-changed');
    const only = (kinds) => {
      const gone = marks.filter((m) => kinds.includes(m.dataset.docxChangeKind));
      if (!gone.length) return false;
      const clone = p.cloneNode(true);
      for (const m of clone.querySelectorAll(kinds.map((k) => `[data-docx-change-kind="${k}"]`).join(','))) m.remove();
      return !clone.textContent.trim() && !clone.querySelector('img, svg, table');
    };
    if (only(['delete', 'move-from'])) p.classList.add('duo-gone-accepted');
    if (only(['insert', 'move-to'])) p.classList.add('duo-gone-original');
  }

  // 3. Comment ranges: the renderer leaves <!--start of comment #N--> and an anchor span at the end.
  const starts = new Map();
  const walker = document.createTreeWalker(host, NodeFilter.SHOW_COMMENT);
  for (let n; (n = walker.nextNode());) { const m = /^start of comment #(\S+)$/.exec(n.data); if (m) starts.set(m[1], n); }
  const ends = new Map();
  for (const end of host.querySelectorAll('.docx-comment-anchor[data-docx-change-kind="comment"]')) ends.set(end.dataset.docxChangeId, end);
  for (const [id, end] of ends) {
    const start = starts.get(id);
    if (!start) continue;
    const range = document.createRange(); range.setStartAfter(start); range.setEndBefore(end);
    const texts = [];
    const tw = document.createTreeWalker(range.commonAncestorContainer, NodeFilter.SHOW_TEXT);
    for (let t; (t = tw.nextNode());) if (range.intersectsNode(t) && t.data.trim() && !t.parentElement.closest('del[data-docx-change-kind]')) texts.push(t);
    for (const t of texts) { const mk = document.createElement('mark'); mk.className = 'duo-comment'; mk.dataset.commentId = id; t.replaceWith(mk); mk.append(t); }
  }

  // 4. Threads: commentsExtended links a reply's paragraph id to its parent's, and says whether it's resolved.
  const ext = new Map((doc.commentsExtendedPart?.comments ?? []).map((e) => [e.paraId, e]));
  const lastPara = (c) => { const ps = (c.children ?? []).filter((x) => x.displayAddress); return ps.length ? ps[ps.length - 1].displayAddress.replace(/^p:/, '') : null; };
  const comments = (doc.commentsPart?.comments ?? []).map((c) => {
    const pid = lastPara(c), e = pid && ext.get(pid);
    return { id: String(c.id), author: c.author, date: c.date, paraId: pid, parentParaId: e?.paraIdParent ?? null, done: !!e?.done, text: byId.get(String(c.id))?.text ?? '' };
  });
  const byPara = new Map(comments.map((c) => [c.paraId, c]));
  for (const c of comments) { c.parent = c.parentParaId ? byPara.get(c.parentParaId)?.id ?? null : null; if (c.author) people[colourIndex(c.author)].count++; }
  const rootOf = (c) => { let r = c; while (r.parent) r = comments.find((x) => x.id === r.parent) ?? { ...r, parent: null }; return r; };
  for (const c of comments) { c.thread = rootOf(c).id; c.resolved = comments.find((x) => x.id === c.thread)?.done ?? c.done; }
  for (const c of comments) if (c.resolved) host.querySelectorAll(`mark.duo-comment[data-comment-id="${c.id}"]`).forEach((m) => m.classList.add('duo-done'));

  const who = (x) => `<span class="duo-who" style="color:${colourOf(x.author)}">${esc(x.author)}</span> <span class="duo-date">· ${day(x.date)}</span>`;
  for (const root of comments.filter((c) => !c.parent)) {
    const members = [root, ...comments.filter((c) => c.thread === root.id && c !== root)];
    const end = ends.get(root.id) ?? ends.get(members[members.length - 1].id);
    let anchor = end?.closest('p');
    if (!anchor) anchor = host.querySelector(`mark[data-comment-id="${root.id}"]`)?.closest('p');
    const card = document.createElement('div');
    card.className = 'duo-card';
    card.dataset.thread = root.id;
    card.innerHTML = members.map((x, i) => `<div class="${i ? 'duo-reply' : ''}"><div class="duo-head">${who(x)}</div><div>${esc(x.text)}</div></div>`).join('');
    let el = card;
    if (root.done) {
      el = document.createElement('div');
      el.className = 'duo-resolved'; el.dataset.thread = root.id;
      el.innerHTML = `<div class="duo-fold"><svg width="10" height="10" viewBox="0 0 10 10" aria-hidden="true"><path d="M3.5 2 6.5 5 3.5 8" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"></path></svg><span class="duo-line">Resolved · ${esc(root.author)}: ${esc(root.text)}</span></div>`;
      card.classList.add('duo-full');
      el.append(card);
      el.addEventListener('click', (e) => { if (e.target.closest('.duo-fold')) el.classList.add('open'); else if (e.target.closest('.duo-head')) el.classList.remove('open'); });
    }
    if (anchor) {
      const mb = parseFloat(getComputedStyle(anchor).marginBottom) || 0;
      el.style.marginTop = `${Math.max(0, 10 - mb)}px`;
      anchor.after(el);
    }
    threads.push({ id: root.id, authors: [...new Set(members.map((m) => m.author))], el, resolved: !!root.done });
  }
  window.__duo_comments = comments;
  return comments;
}

// ---- views --------------------------------------------------------------------------------

function apply() {
  host.dataset.docxReviewEnabled = 'true';
  host.dataset.docxReviewMode = RENDERER_MODE[cfg.mode] || 'all';
  document.body.classList.toggle('no-comments', !cfg.comments);
  document.body.classList.toggle('show-resolved', !!cfg.resolved);
  // One person: everyone else's changes read as accepted text, and their threads fold away.
  for (const el of host.querySelectorAll('[data-docx-change-author]')) el.classList.toggle('duo-muted', !!cfg.person && el.dataset.docxChangeAuthor !== cfg.person && !el.classList.contains('docx-comment-anchor'));
  for (const t of threads) t.el.classList.toggle('duo-hidden', !!cfg.person && !t.authors.includes(cfg.person));
  for (const m of host.querySelectorAll('mark.duo-comment')) {
    const t = threads.find((x) => x.id === m.dataset.commentId) || threads.find((x) => (window.__duo_comments || []).some((c) => c.id === m.dataset.commentId && c.thread === x.id));
    m.style.background = cfg.person && t && !t.authors.includes(cfg.person) ? 'none' : '';
  }
  originalFormatting(cfg.mode === 'original');
  hideLabel();
}

// The renderer keeps formatting changes applied in Original (F-234); put back what was there: the
// change's old value, or none (plain) where it had none.
function originalFormatting(on) {
  for (const el of host.querySelectorAll('[data-docx-format-change]')) {
    if (!on) { if (el.dataset.duoStyle !== undefined) { el.style.cssText = el.dataset.duoStyle; delete el.dataset.duoStyle; } continue; }
    if (el.dataset.duoStyle !== undefined) continue;
    const ch = byIdChange(el.dataset.docxChangeId);
    if (!ch) continue;
    el.dataset.duoStyle = el.style.cssText;
    const set = (k, v) => el.style.setProperty(k, v, 'important');
    for (const { property: p, before } of ch.formatChanges ?? []) {
      const v = String(before ?? '').replace(/^val=/, '');
      if (p === 'b') set('font-weight', before !== undefined && v !== 'false' ? 'bold' : 'normal');
      if (p === 'i') set('font-style', before !== undefined && v !== 'false' ? 'italic' : 'normal');
      if (p === 'u') set('text-decoration', before !== undefined && v !== 'none' ? 'underline' : 'none');
      if (p === 'strike') set('text-decoration', before !== undefined && v !== 'false' ? 'line-through' : 'none');
      if (p === 'color') set('color', before !== undefined && v ? `#${v}` : 'inherit');
    }
  }
}
const byIdChange = (id) => changes.find((c) => String(c.id) === String(id));

// ---- the label above a change -------------------------------------------------------------

let hovered = null;
function showLabel(el) {
  if (picking) return;
  if (!el || host.dataset.docxReviewMode !== 'all' || el.classList.contains('duo-muted')) return hideLabel();
  const ch = byIdChange(el.dataset.docxChangeId);
  const author = el.dataset.docxChangeAuthor, kind = ch?.kind || el.dataset.docxChangeKind || 'format';
  const what = kind === 'format' ? `formatted: ${describeFormat(ch?.formatChanges) || 'Format'}` : (KINDS[kind] || kind);
  label.innerHTML = `<b style="color:${colourOf(author)}">${esc(author)}</b> ${esc(what)} · ${day(el.dataset.docxChangeDate)}`;
  label.style.display = 'block';
  const r = el.getBoundingClientRect();
  label.style.left = `${Math.max(4, r.left + scrollX - 8)}px`;
  label.style.top = `${r.top + scrollY - label.offsetHeight - 8}px`;
  hovered?.classList.remove('duo-hover'); hovered = el; el.classList.add('duo-hover');
}
function hideLabel() { label.style.display = 'none'; hovered?.classList.remove('duo-hover'); hovered = null; }
document.addEventListener('mouseover', (e) => { const el = e.target.closest?.('[data-docx-change-kind]:not(.docx-comment-anchor), [data-docx-format-change]'); if (el && isMark(el)) showLabel(el); else if (hovered) hideLabel(); });
document.addEventListener('mouseleave', hideLabel);

// ---- the calls from Swift -----------------------------------------------------------------

function summary() {
  return {
    people: people.map((p, i) => ({ name: p.name, colour: (i % 5) + 1, count: p.count })),
    changes: changes.filter((c) => c.kind !== 'comment').length,
    comments: (window.__duo_comments || []).map((c) => ({ id: c.id, author: c.author, date: c.date, text: c.text, resolved: c.resolved, reply: !!c.parent, paragraph: c.paraId })),
  };
}

window.__duo = {
  // Opens the document DocxViewer serves at doc.docx (`v` defeats caching) with the markup settings
  // `c`, keeping the scroll position `y`.
  async open(name, v, c, y) {
    title = name; cfg = { ...defaults(), ...(c || {}) }; opens++; settled = false;
    host.replaceChildren(); doc = null; changes = []; hideLabel();
    try {
      const res = await fetch(`${devDoc || 'doc.docx'}?v=${v}`);
      if (!res.ok) throw new Error(`doc.docx: ${res.status}`);
      const bytes = await res.arrayBuffer();
      doc = await renderAsync(bytes, host, null, {
        breakPages: false, exposeDisplayTargets: true, reviewMode: 'all', renderComments: true, useWorker: false, awaitLayout: false,
        externalLinkPolicy: 'block', externalResourcePolicy: 'block',
      });
      changes = collectDocxReviewChanges(doc);
      layer();
      apply();
      if (y > 0) scrollTo(0, y);
      const s = summary();
      post({ kind: 'ready', ...s });
      // From here on any change of layout is counted: a settled document changes none.
      setTimeout(() => { settled = true; }, 500);
      window.__duo_ready = true;
      return { changes: s.changes };
    } catch (err) {
      post({ kind: 'failed', reason: String(err && err.message || err) });
      window.__duo_last = String(err && err.stack || err) + " :: " + (err && err.name) + " :: " + JSON.stringify(err, Object.getOwnPropertyNames(err || {}));
      window.__duo_ready = true;
      return { error: String(err && err.message || err) };
    }
  },
  // The Markup menu's settings, applied without drawing the document again.
  markup(c) { cfg = { ...cfg, ...(c || {}) }; apply(); return cfg; },
  info: summary,
  scroll: () => scrollY,
  // A change under the pointer, for captures: its id or its text.
  hover(id) {
    const el = host.querySelector(`[data-docx-change-id="${CSS.escape(String(id))}"]:not(.docx-comment-anchor)`)
      || [...host.querySelectorAll('ins, del, [data-docx-format-change]')].find((e) => e.textContent.includes(String(id)));
    if (el) showLabel(el);
    return !!el;
  },
  unhover: hideLabel,
  // The paragraph ids and text the renderer drew, for checks (they compare them with Docx.swift's outline).
  paragraphs: () => [...host.querySelectorAll('[data-office-target]')].map((p) => ({ target: p.dataset.officeTarget, text: p.textContent })),
  // What happened since the page opened: draws asked for, sections drawn, the sheet's size changes and
  // the DOM changes under it since the last draw finished (a layout loop would make these grow).
  stats: () => ({ opens, sections: renders(), height: document.documentElement.scrollHeight, sheetResizes, mutations }),
};

// ---- Select Text (docx-viewer-handoff W5): the deck's picker, for paragraphs and comment cards -----
// Selectors: a paragraph's w14:paraId, or `c:<comment id>` for a comment's card. Messages and calls are
// the HTML picker's (PageHost): start, stop, unfreeze, freeze, describe, hideOutline, showOutline.
const outline = document.getElementById('outline');
const tag = document.getElementById('tag');
let picking = false, hot = null, frozen = null, hidden = false;

const targetOf = (node) => node.closest?.('.duo-resolved, .duo-card, p[data-office-target]');
const paraIdOf = (p) => (p.dataset.officeTarget || '').split('#p:')[1] || '';
function cardParagraph(card) {
  let el = card.closest('.duo-resolved') || card;
  for (let n = el.previousElementSibling; n; n = n.previousElementSibling) if (n.matches('p[data-office-target]')) return n;
  return null;
}
function paragraphFor(sel) {
  const s = String(sel);
  if (s.startsWith('c:')) {
    const t = threads.find((x) => x.id === s.slice(2) || (window.__duo_comments || []).some((c) => c.id === s.slice(2) && c.thread === x.id));
    return t ? { el: t.el.classList.contains('duo-resolved') ? t.el : t.el, comment: s.slice(2) } : null;
  }
  const p = [...host.querySelectorAll('p[data-office-target]')].find((q) => paraIdOf(q) === s);
  return p ? { el: p } : null;
}
function counts(p) {
  const ids = new Set([...p.querySelectorAll('[data-docx-change-id]:not(.docx-comment-anchor)')].map((e) => e.dataset.docxChangeId));
  let comments = 0;
  for (let n = p.nextElementSibling; n && n.matches('.duo-card, .duo-resolved'); n = n.nextElementSibling) comments++;
  return { changes: ids.size, comments };
}
function tagText(el) {
  if (el.matches('.duo-card, .duo-resolved')) return 'Comment';
  const { changes, comments } = counts(el);
  const parts = [];
  if (comments) parts.push(`${comments} comment${comments === 1 ? '' : 's'}`);
  if (changes) parts.push(`${changes} change${changes === 1 ? '' : 's'}`);
  return ['Paragraph', ...parts].join(' · ');
}
function describePick(el, comment) {
  const isCard = el.matches('.duo-card, .duo-resolved');
  const p = isCard ? cardParagraph(el) : el;
  const paraId = p ? paraIdOf(p) : '';
  let heading = '';
  for (const q of host.querySelectorAll('p[data-office-target]')) { if (q === p) break; if (/docx_heading/.test(q.className)) heading = q.textContent.trim(); }
  const thread = isCard ? threads.find((t) => t.el === el || t.el.contains(el)) : null;
  const cid = comment ?? thread?.id ?? '';
  const r = el.getBoundingClientRect();
  const text = (isCard ? el.textContent : [...el.childNodes].map((n) => n.textContent).join('')).trim();
  return {
    tag: isCard ? 'comment' : 'paragraph', label: isCard ? `comment ${cid}` : `paragraph ${paraId}`, selector: isCard ? `c:${cid}` : paraId, trail: heading ? [heading] : [],
    text, attributes: { kind: isCard ? 'comment' : 'paragraph', paraId, ...(isCard ? { comment: String(cid) } : {}) }, styles: {},
    rect: [Math.round(r.left), Math.round(r.top + scrollY), Math.round(r.width), Math.round(r.height)], html: '', url: location.href, title,
    viewRect: [r.left, r.top, r.width, r.height],
  };
}
function motionMs(name) {
  if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) return 0;
  return parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--duo-motion-' + name + '-ms')) || 0;
}
function place(el) {
  if (!el || hidden) { outline.style.display = 'none'; tag.style.display = 'none'; return; }
  const r = el.getBoundingClientRect(), pad = 3;
  const ms = outline.style.display === 'block' ? motionMs('outline') : 0;
  outline.style.transition = ms > 0 ? ['left', 'top', 'width', 'height'].map((q) => `${q} ${ms}ms ease-out`).join(', ') : 'none';
  Object.assign(outline.style, { display: 'block', left: `${r.left + scrollX - pad}px`, top: `${r.top + scrollY - pad}px`, width: `${r.width + 2 * pad}px`, height: `${r.height + 2 * pad}px` });
  outline.className = el === frozen ? 'frozen' : 'hover';
  tag.textContent = tagText(el);
  tag.style.display = 'block';
  tag.style.left = `${r.left + scrollX - pad}px`;
  tag.style.top = `${r.top + scrollY - 24}px`;   // the board: 3 left of the paragraph, 24 above its top (16 high, 8 clear)
}
document.addEventListener('mousemove', (e) => {
  if (!picking || frozen) return;
  const el = targetOf(e.target);
  if (el !== hot) { hot = el; place(el); }
}, true);
document.addEventListener('click', (e) => {
  if (!picking) return;
  e.preventDefault(); e.stopPropagation();
  if (frozen) return;
  const el = targetOf(e.target);
  if (!el) return;
  frozen = el; place(el);
  post({ kind: 'picked', element: describePick(el) });
}, true);
document.addEventListener('keydown', (e) => { if (picking && e.key === 'Escape') { e.preventDefault(); stopPick(); post({ kind: 'pickEnded' }); } }, true);
function startPick() { picking = true; frozen = null; hot = null; document.body.classList.add('picking'); hideLabel(); place(null); }
function stopPick() { picking = false; frozen = null; hot = null; document.body.classList.remove('picking'); place(null); }
Object.assign(window.__duo, {
  start: startPick, stop: stopPick, unfreeze: () => { frozen = null; hot = null; place(null); },
  freeze(sel) { const t = paragraphFor(sel); if (!t) return false; picking = true; document.body.classList.add('picking'); frozen = t.el; t.el.scrollIntoView({ block: 'nearest' }); place(t.el); post({ kind: 'picked', element: describePick(t.el, t.comment) }); return true; },
  describe(sel) { const t = paragraphFor(sel); return t ? describePick(t.el, t.comment) : null; },
  hoverPara(sel) { const t = paragraphFor(sel); if (t && picking && !frozen) { hot = t.el; place(t.el); } return !!t; },
  hideOutline() { hidden = true; place(null); },
  showOutline() { hidden = false; place(frozen); },
  selection: () => null,
});

const renders = () => host.querySelectorAll('section.docx').length;
let opens = 0, sheetResizes = 0, mutations = 0, settled = false;
new ResizeObserver(() => { if (settled) sheetResizes++; }).observe(document.getElementById('sheet'));
new MutationObserver((list) => { if (settled) mutations += list.length; }).observe(host, { childList: true, subtree: true, attributes: false });
document.addEventListener('securitypolicyviolation', (e) => post({ kind: 'blocked', what: `${e.violatedDirective} ${e.blockedURI}` }));
// A dev copy (served over http to a browser, never Duo's own scheme) opens the document named in the address.
if (devDoc) window.__duo.open(devDoc, Date.now(), JSON.parse(dev.get('cfg') || '{}'), 0);
post({ kind: 'loaded' });
