// Shared by the proof pages (ENH-12 spike): a side panel that shows what Duo would get, the
// current slide and the picked shape, and posts the same to a WKWebView handler when there is one.
export function setup(rendererName) {
  const q = new URLSearchParams(location.search);
  const deck = q.get('deck') || 'shapes';
  document.body.insertAdjacentHTML('beforeend', `
    <aside id="duo-panel">
      <b>${rendererName}</b>
      <div>deck: <select id="deck">${['basics', 'data', 'shapes'].map(d => `<option ${d === deck ? 'selected' : ''}>${d}</option>`).join('')}</select></div>
      <div>current slide: <b id="cur">–</b> / <span id="count">–</span></div>
      <div>rendered in <span id="ms">–</span> ms</div>
      <div class="lbl">picked (what <code>duo2 slide element</code> would give):</div>
      <pre id="picked">click a shape</pre>
    </aside>`);
  document.getElementById('deck').onchange = e => { q.set('deck', e.target.value); location.search = q; };
  const post = (msg) => { window.__duo_last = msg; window.webkit?.messageHandlers?.duo?.postMessage(msg); };
  return {
    deck, url: `decks/${deck}.pptx`,
    rendered(ms, count) { document.getElementById('ms').textContent = Math.round(ms); document.getElementById('count').textContent = count; },
    slide(n) { if (document.getElementById('cur').textContent != n) { document.getElementById('cur').textContent = n; post({ event: 'slide', slide: n }); } },
    picked(info, el) {
      document.querySelectorAll('.duo-picked').forEach(x => x.classList.remove('duo-picked'));
      el?.classList.add('duo-picked');
      document.getElementById('picked').textContent = JSON.stringify(info, null, 2);
      post({ event: 'picked', ...info });
    },
    // The slide most of the viewport shows: an IntersectionObserver over the slide elements.
    trackSlides(slides, numberOf) {
      const seen = new Map();
      const io = new IntersectionObserver(es => {
        for (const e of es) seen.set(e.target, e.intersectionRatio);
        let best = null, r = -1;
        for (const [el, ratio] of seen) if (ratio > r) { r = ratio; best = el; }
        if (best) this.slide(numberOf(best));
      }, { threshold: [0, .25, .5, .75, 1] });
      slides.forEach(s => io.observe(s));
    },
  };
}
