// Shared by the proof pages (docx viewer spike): a side panel that shows what Duo would get, the
// view mode and the picked paragraph, and posts the same to a WKWebView handler when there is one.
export function setup(rendererName, modes = []) {
  const q = new URLSearchParams(location.search);
  const doc = q.get('doc') || 'review';
  const mode = q.get('mode') || modes[0] || '';
  document.body.insertAdjacentHTML('beforeend', `
    <aside id="duo-panel">
      <b>${rendererName}</b>
      <div>doc: <select id="doc">${['basics', 'review', 'layout'].map(d => `<option ${d === doc ? 'selected' : ''}>${d}</option>`).join('')}</select>
      ${modes.length ? `mode: <select id="mode">${modes.map(m => `<option ${m === mode ? 'selected' : ''}>${m}</option>`).join('')}</select>` : ''}</div>
      <div>rendered in <span id="ms">–</span> ms<span id="pages"></span></div>
      <div class="lbl">picked (what <code>duo2 doc paragraph</code> would give):</div>
      <pre id="picked">click a paragraph</pre>
      <div class="lbl" id="extra-lbl"></div>
      <pre id="extra" hidden></pre>
    </aside>`);
  document.getElementById('doc').onchange = e => { q.set('doc', e.target.value); location.search = q; };
  const m = document.getElementById('mode'); if (m) m.onchange = e => { q.set('mode', e.target.value); location.search = q; };
  const post = (msg) => { window.__duo_last = msg; window.webkit?.messageHandlers?.duo?.postMessage(msg); };
  const h = {
    doc, mode, url: `docs/${doc}.docx`,
    rendered(ms, pages) { document.getElementById('ms').textContent = Math.round(ms); if (pages) document.getElementById('pages').textContent = `, ${pages} pages`; window.__duo_ready = true; },
    extra(label, obj) { document.getElementById('extra-lbl').textContent = label; const x = document.getElementById('extra'); x.hidden = false; x.textContent = typeof obj === 'string' ? obj : JSON.stringify(obj, null, 1); },
    picked(info, el) {
      document.querySelectorAll('.duo-picked').forEach(x => x.classList.remove('duo-picked'));
      el?.classList.add('duo-picked');
      document.getElementById('picked').textContent = JSON.stringify(info, null, 2);
      post({ event: 'picked', ...info });
    },
    // Click → the paragraph element carrying an id attribute (attr), its id parsed by idOf.
    pickParagraphs(host, attr, idOf) {
      host.addEventListener('click', e => {
        const el = e.target.closest(`[${attr}]`);
        if (!el) return;
        const page = el.closest('section');
        h.picked({ ...idOf(el.getAttribute(attr)), page: page ? [...host.querySelectorAll('section')].indexOf(page) + 1 : null,
                   style: [...el.classList].join(' '), text: el.innerText.trim().slice(0, 200),
                   comment: e.target.closest('[data-comment-id]')?.dataset.commentId ?? null }, el);
        e.preventDefault(); e.stopPropagation();
      }, true);
    },
  };
  return h;
}
