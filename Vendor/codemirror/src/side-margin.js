// The side margin: the comment column beside a viewer that is not the editor (the PDF viewer now; Word and PowerPoint next).
// Geoff, 2026-11-10: PDF comments look and work exactly like Markdown review comments.
// It is margin.js's margin: the same `Cards` (cards.js: cards, active card with reply field and Close and Keep / Delete,
// "n closed · Show", the narrow gutter and popover, @claude's delivery lines and pill, the composer) and the same `@` menu
// (atmenu.js), in a small page of its own beside the PDFView. What differs is the host: the anchors are where PDFKit draws
// each highlight (Swift sends their y in the document's coordinates and the scroll offset), and what a card's buttons do
// goes to Swift (messages of the kind the host names; the PDF viewer's are `pdfMargin`), which writes the PDF through `PdfComments` and sends `@claude` comments when they
// are posted. The page keeps its own state (the active card, the composer) while Swift re-sends the threads after each write.
import { Cards, cardStyles, reviewColourStyles, toCss, el, NARROW, MARGIN_W, MARGIN_RIGHT, GAP_TEXT, GUTTER, POPOVER_W } from "./cards.js";
import { atPeople } from "./atmenu.js";

// The message kind is the host's to name: Swift sets window.duoMarginKind before the page loads (the PDF viewer: "pdfMargin").
const KIND = window.duoMarginKind || "sideMargin";
const send = (a) => { try { window.webkit.messageHandlers.duo.postMessage({ kind: KIND, ...a }); } catch (e) { /* no host: a browser page for checks */ } };

class SideMargin extends Cards {
  constructor(root) {
    const layer = el("div", "duo-mg");
    super(layer);
    this.root = root; root.append(layer);
    layer.style.left = "auto"; layer.style.right = "0";
    layer.addEventListener("mousedown", (e) => this.onMouse(e));
    this.state = { paneWidth: 1000, threads: [], showClosed: false, reviewer: "you" };
    this.scroll = 0; this.reported = ""; this.last = null;
  }

  // ----- what Swift sends -----
  setState(s) { this.state = { ...this.state, ...s }; if (this.active && !this.state.threads.some((t) => t.id === this.active)) this.active = null; this.sig = ""; this.schedule(); }
  setScroll(y) { this.scroll = y; this.applyScroll(); }
  setDelivery(map, def) { this.delivery = { map: map || {}, def: def || null }; this.sig = ""; this.schedule(); }
  compose(y, quiet) { this.composer = { y, quiet: !!quiet }; this.active = null; this.sig = ""; this.schedule(); return true; }
  moveComposer(y) { if (this.composer) { this.composer.y = y; this.schedule(); } }
  closeComposer() { this.composer = null; this.composerDom = null; this.sig = ""; this.schedule(); }
  activate(id) { this.active = id; this.sig = ""; this.schedule(); }

  // ----- layout -----
  schedule() {
    if (this.pending) return;
    this.pending = true;
    const run = () => { if (!this.pending) return; this.pending = false; this.render(); };
    setTimeout(run, 0);
    requestAnimationFrame(run);
  }
  relayout() { if (this.last) this.place(this.last); }
  mode() {
    const s = this.state;
    const shown = s.threads.filter((t) => !t.closed || s.showClosed);
    const show = s.threads.length > 0 || !!this.composer;
    const narrow = s.paneWidth < NARROW;
    // Narrow: a gutter of markers; the open thread (or the composer) is a popover that widens the page over the PDF.
    const pop = narrow && (!!this.composer || shown.some((t) => t.id === this.active));
    const W = !show ? 0 : narrow ? (pop ? GUTTER + POPOVER_W + 20 : GUTTER) : MARGIN_W + MARGIN_RIGHT + GAP_TEXT;
    return { W, narrow, show, shown, showClosed: s.showClosed, closedCount: s.threads.filter((t) => t.closed).length, reserve: !show ? 0 : narrow ? GUTTER : W };
  }
  render() {
    const m = this.mode(), s = this.state;
    this.last = m;
    this.layer.style.width = m.W + "px";
    this.layer.style.display = m.show ? "block" : "none";
    const sig = JSON.stringify([m.W, m.show, s.showClosed, m.shown.map((t) => [t.id, t.closed, t.comments.map((c) => [c.author, c.date, c.text, c.closing])]), this.active, this.composer && 1, this.hover, this.delivery]);
    if (!m.show) { this.layer.textContent = ""; this.sig = ""; } else { if (sig !== this.sig) { this.sig = sig; this.build(m); } this.place(m); }
    const r = JSON.stringify([m.W, m.reserve]);
    if (r !== this.reported) { this.reported = r; send({ op: "width", w: m.W, reserve: m.reserve }); }
  }
  anchorY(t) { return t.y; }
  composerY() { return this.composer ? this.composer.y : 0; }
  finish(bottom) { this.layer.style.height = Math.max(bottom, 0) + "px"; this.applyScroll(); }
  applyScroll() { this.layer.style.transform = `translateY(${-this.scroll}px)`; }

  // ----- the host's side of the cards -----
  colourOf(a) {
    // People in the order they appear; Claude is always review 3, the others 1, 2, 4, 5, then again (as critic.js).
    const names = [];
    for (const t of this.state.threads) for (const c of t.comments) if (c.author && !names.includes(c.author)) names.push(c.author);
    const order = [1, 2, 4, 5]; let k = 0, out = 1;
    for (const n of names) { const v = n === "claude" ? 3 : order[k++ % order.length]; if (n === a) out = v; }
    return out;
  }
  reviewerName() { return this.state.reviewer; }
  emit(a) { send(a); }
  people() {
    let at = 0;
    return atPeople({ threads: this.state.threads.map((t) => ({ comments: t.comments.map((c) => ({ author: c.author, date: c.date, from: at++, text: c.text })) })), suggestions: [] });
  }
  pillOrigin(btn) { const r = btn.getBoundingClientRect(); return { x: r.left, y: r.bottom + 2 }; }
  reply(id, text) {
    if (!text.trim()) return false;
    send({ op: "reply", id, text: text.trim() });
    return true;
  }
  act(op, id) { send({ op, id }); }
  post(text) {
    if (!this.composer || !text.trim()) return;
    send({ op: "post", text: text.trim() });
    this.composer = null; this.composerDom = null; this.sig = ""; this.schedule();
  }
  cancelCompose() { this.composer = null; this.composerDom = null; this.sig = ""; this.schedule(); send({ op: "cancel" }); }
  escaped() { send({ op: "escaped" }); }
  setActive(id) { super.setActive(id); send({ op: "active", id }); }
  // Hovering a card lights its anchor in the viewer, as in Markdown (cards.js lets a host override setHover); a host that ignores "hover" loses nothing.
  setHover(id) { super.setHover(id); send({ op: "hover", id }); }
}

// The page paints nothing of its own: the host gives the reserved column its ground, so a narrow pane's popover floats over the document
// instead of hiding it (board S1b; the Word, PowerPoint and PDF viewers all draw this page over their content).
const style = document.createElement("style");
style.textContent = toCss({ ...cardStyles, ...reviewColourStyles })
  + "\nhtml, body { margin: 0; height: 100%; overflow: hidden; background: transparent; }\n#root { position: relative; height: 100vh; overflow: hidden; }\n";
document.head.append(style);
const root = document.getElementById("root");
const margin = new SideMargin(root);
window.duoSideMargin = {
  setState: (s) => margin.setState(s),
  setScroll: (y) => margin.setScroll(y),
  setDelivery: (m, d) => margin.setDelivery(m, d),
  compose: (y, quiet) => margin.compose(y, quiet),
  moveComposer: (y) => margin.moveComposer(y),
  closeComposer: () => margin.closeComposer(),
  activate: (id) => margin.activate(id),
  active: () => margin.active,
  composing: () => !!margin.composer,
  // For checks: the cards as laid out.
  dump: () => Array.from(margin.layer.querySelectorAll(".duo-mg-card,.duo-mg-marker,.duo-mg-foot")).map((e) => ({ id: e.dataset.thread || (e.dataset.composer ? "composer" : ""), text: e.textContent, top: e.offsetTop, left: e.offsetLeft, w: e.offsetWidth, h: e.offsetHeight })),
};
send({ op: "ready" });
