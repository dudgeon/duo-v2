// What Duo would add on top of @file-viewer/docx (docx viewer spike): the renderer keeps every
// revision and comment anchor in the DOM with author, date and id, and leaves the review UI to
// the host. This layer draws Word's "All Markup": per-author colours, deletions struck through,
// moves in double lines, format changes and comments in a margin beside the page, comment ranges
// highlighted, replies threaded under their parent and resolved comments greyed.
const PALETTE = ['#b4235a', '#1d6fb8', '#2f8a3b', '#8a4fc2', '#c2410c', '#0f766e'];

export function reviewLayer(host, doc, changes, { margin = true } = {}) {
  const authors = new Map();
  const colour = a => { if (!authors.has(a)) authors.set(a, PALETTE[authors.size % PALETTE.length]); return authors.get(a); };
  // 1. Per-author colour on every revision element, in order of appearance (the renderer hashes the
  //    author's name into a short palette, so two of our three authors came out the same teal).
  for (const el of host.querySelectorAll('[data-docx-change-author]')) {
    const c = colour(el.dataset.docxChangeAuthor);
    el.style.setProperty('--duo-author', c); el.style.setProperty('--docx-review-color', c);
  }
  // A change bar on each paragraph that holds a revision (Word draws it in the left margin).
  for (const el of host.querySelectorAll('ins[data-docx-change-kind], del[data-docx-change-kind], [data-docx-format-change]'))
    el.closest('p')?.classList.add('duo-changed');

  // 2. Comment ranges: the renderer leaves <!--start of comment #N--> and an anchor span at the end.
  const starts = new Map();
  const walker = document.createTreeWalker(host, NodeFilter.SHOW_COMMENT);
  for (let n; (n = walker.nextNode());) { const m = /^start of comment #(\S+)$/.exec(n.data); if (m) starts.set(m[1], n); }
  for (const end of host.querySelectorAll('.docx-comment-anchor[data-docx-change-kind="comment"]')) {
    const id = end.dataset.docxChangeId, start = starts.get(id);
    if (!start) continue;
    const range = document.createRange(); range.setStartAfter(start); range.setEndBefore(end);
    const texts = []; const tw = document.createTreeWalker(range.commonAncestorContainer, NodeFilter.SHOW_TEXT);
    for (let t; (t = tw.nextNode());) if (range.intersectsNode(t) && t.data.trim()) texts.push(t);
    for (const t of texts) { const mk = document.createElement('mark'); mk.className = 'duo-comment'; mk.dataset.commentId = id; t.replaceWith(mk); mk.append(t); }
  }

  // 3. Comments as threads: commentsExtended links a reply's paraId to its parent's, and says done.
  const ext = new Map((doc.commentsExtendedPart?.comments ?? []).map(e => [e.paraId, e]));
  const lastPara = c => { const ps = (c.children ?? []).filter(x => x.displayAddress); return ps.length ? ps[ps.length - 1].displayAddress.replace(/^p:/, '') : null; };
  const comments = (doc.commentsPart?.comments ?? []).map(c => {
    const pid = lastPara(c), e = pid && ext.get(pid);
    return { id: String(c.id), author: c.author, date: c.date, paraId: pid, parentParaId: e?.paraIdParent ?? null, done: !!e?.done,
             text: (changes.find(x => x.kind === 'comment' && String(x.id) === String(c.id))?.text) ?? '' };
  });
  const byPara = new Map(comments.map(c => [c.paraId, c]));
  for (const c of comments) c.parent = c.parentParaId ? byPara.get(c.parentParaId)?.id ?? null : null;
  for (const c of comments) { colour(c.author); if (c.done) host.querySelectorAll(`mark.duo-comment[data-comment-id="${c.id}"]`).forEach(m => m.classList.add('duo-done')); }

  if (!margin) return { comments, authors };
  // 4. The margin: a card per thread (and per format change / move-from), beside its anchor.
  const describe = f => f.map(({ property: p, before, after }) => {
    const names = { b: 'Bold', i: 'Italic', u: 'Underline', color: 'Font colour', jc: 'Alignment', sz: 'Size', strike: 'Strikethrough' };
    const v = (after ?? '').replace(/^val=/, '');
    return after === undefined ? `Not ${names[p] ?? p}` : (v === 'true' ? names[p] ?? p : `${names[p] ?? p}: ${v}`);
  }).join(', ');
  const cards = [];
  for (const c of comments.filter(c => !c.parent)) {
    const anchor = host.querySelector(`.docx-comment-anchor[data-docx-change-id="${c.id}"]`) ?? host.querySelector(`mark[data-comment-id="${c.id}"]`);
    const replies = comments.filter(r => r.parent === c.id);
    cards.push({ anchor, kind: 'comment', id: c.id, html: [c, ...replies].map((x, i) => `
      <div class="duo-c ${i ? 'duo-reply' : ''}"><b style="color:${colour(x.author)}">${x.author}</b> <span class="duo-date">${new Date(x.date).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })}</span>
      ${i === 0 && c.done ? '<span class="duo-tag">Resolved</span>' : ''}<div>${x.text}</div></div>`).join(''), done: c.done });
  }
  for (const ch of changes.filter(x => x.kind === 'format' || x.kind === 'move-from')) {
    const anchor = host.querySelector(`[data-docx-change-id="${ch.id}"]`);
    const what = ch.kind === 'format' ? `Formatted: ${describe(ch.formatChanges ?? [])}` : 'Moved (from here)';
    cards.push({ anchor, kind: ch.kind, id: ch.id, html: `<div class="duo-c"><b style="color:${colour(ch.author)}">${ch.author}</b> <span class="duo-date">${new Date(ch.date).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })}</span><div>${what}</div></div>` });
  }
  const hostBox = host.getBoundingClientRect();
  const placed = cards.filter(c => c.anchor).map(c => {
    const page = c.anchor.closest('section.docx'), pb = page.getBoundingClientRect(), ab = c.anchor.getBoundingClientRect();
    return { ...c, x: pb.right - hostBox.left + 12, y: ab.top - hostBox.top - 4, ay: ab.top - hostBox.top + ab.height / 2 - 4 };
  }).sort((a, b) => a.y - b.y);
  let bottom = 0;
  for (const c of placed) {
    const el = document.createElement('div');
    el.className = `duo-card duo-${c.kind}${c.done ? ' duo-done' : ''}`; el.dataset.for = c.id; el.innerHTML = c.html;
    el.style.left = `${c.x}px`; el.style.top = `${Math.max(c.y, bottom)}px`;
    host.append(el);
    bottom = Math.max(c.y, bottom) + el.offsetHeight + 6;
  }
  return { comments, authors };
}
