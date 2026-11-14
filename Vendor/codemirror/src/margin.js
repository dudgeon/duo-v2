// The margin column of a Markdown review (DL-237; target markdown-review-handoff `margin-crowded`, `margin-thread`,
// `margin-narrow`, `close-*`): comment threads as cards beside the text, level with their anchors; the active card
// with its reply field and Close and Keep / Delete; closed threads folded into "n closed · Show"; under 420 a gutter
// of count markers and a popover. The margin is a layer inside the editor's scroller, so it scrolls with the text.
// Everything it does to the document is a plain transaction (userEvent "review"): ⌘Z undoes it, and the file forms
// are the ones `Review` writes in Swift (`{>>@name date #c1.2: text<<}`, `{>>@name date #c1.3 closed<<}`).
import { StateEffect, EditorSelection } from "@codemirror/state";
import { EditorView, ViewPlugin, Decoration } from "@codemirror/view";
import { atPeople } from "./atmenu.js";
import { Cards, cardStyles, el, MARGIN_W, MARGIN_RIGHT, GAP_TEXT, NARROW, GUTTER } from "./cards.js";
import { parseReview } from "./critic.js";
import { reviewField, markupField, reviewerField, signatureName, today, nextId, nextReply, emitReviewAction } from "./critic.js";

const setActive = StateEffect.define();   // a thread id, or null
export const setDeliveryEffect = StateEffect.define();   // { map: { threadId: {state, name, status, at, why} }, def: {name, status} }


// ---------- what the margin does to the document ----------

function dispatchReview(view, spec) { view.dispatch({ ...spec, userEvent: "review", scrollIntoView: false }); }
const reviewer = (view) => view.state.field(reviewerField);

export function addThread(view, body, range) {
  const r = range || view.state.selection.main;
  let { from, to } = r;
  if (from === to) { const w = view.state.wordAt(from); if (!w) return null; from = w.from; to = w.to; }
  const id = nextId(view.state.doc, "c"), anchor = view.state.sliceDoc(from, to);
  const sig = `{>>@${signatureName(reviewer(view))} ${today()} #${id}: ${body.replace(/<<\}/g, "< <}").replace(/\n/g, " ")}<<}`;
  dispatchReview(view, { changes: { from, to, insert: `{==${anchor}==}${sig}` }, selection: EditorSelection.cursor(from) });
  return id;
}
function findThread(view, id) { return view.state.field(reviewField).parsed.threads.find((t) => t.id === id); }

export function replyTo(view, id, body) {
  const t = findThread(view, id);
  if (!t || !body.trim()) return false;
  const changes = [];
  let at = t.to;
  const last = t.comments[t.comments.length - 1];
  if (t.closed && last) { changes.push({ from: last.from, to: last.to }); }   // a reply reopens (DL-237)
  const rid = `${id}.${nextReply(t.comments)}`;
  changes.push({ from: at, insert: `{>>@${signatureName(reviewer(view))} ${today()} #${rid}: ${body.replace(/<<\}/g, "< <}").replace(/\n/g, " ")}<<}` });
  dispatchReview(view, { changes });
  return true;
}
export function closeThread(view, id) {
  const t = findThread(view, id);
  if (!t || t.closed) return false;
  const rid = `${id}.${nextReply(t.comments)}`;
  dispatchReview(view, { changes: { from: t.to, insert: `{>>@${signatureName(reviewer(view))} ${today()} #${rid} closed<<}` } });
  return true;
}
export function reopenThread(view, id) {
  const t = findThread(view, id);
  if (!t || !t.closed) return false;
  const last = t.comments[t.comments.length - 1];
  dispatchReview(view, { changes: { from: last.from, to: last.to } });
  return true;
}
export function deleteThread(view, id) {
  const t = findThread(view, id);
  if (!t) return false;
  // The markers of each highlight and every comment go; what is inside (marks too) stays.
  const cuts = [...t.comments.map((c) => [c.from, c.to]), ...t.pieces.flatMap((p) => [p.open, p.close])].sort((x, y) => x[0] - y[0]);
  dispatchReview(view, { changes: cuts.map(([from, to]) => ({ from, to })) });
  return true;
}

// ---------- the layer ----------

// A failure in the margin must never break the editor: it is reported to Duo's log and the margin skips that pass.
function guard(what, fn) {
  const dbg = (window.__mg = window.__mg || { calls: 0 }); dbg.calls++; dbg.last = what;
  try { return fn(); } catch (e) { dbg.err = String(e && e.stack || e); emitReviewAction({ op: "error", what, message: String(e && e.stack || e) }); return null; }
}

class Margin extends Cards {
  constructor(view) {
    const layer = el("div", "duo-mg");
    super(layer);
    this.view = view;
    this.layer.addEventListener("mousedown", (e) => this.onMouse(e));
    view.scrollDOM.appendChild(this.layer);
    this.width = 0;
    view.dom.addEventListener("mouseover", (e) => this.anchorHover(e));
    view.contentDOM.addEventListener("mousedown", (e) => this.anchorClick(e), true);
    // F-692: the margin's share of the text column (contentDOM's marginRight) depends on the pane's width, and a pane that
    // changes width alone (a divider drag) raises no CodeMirror update that reaches `update`, so the share stayed what the
    // first layout chose: a note opened wide kept a 184 margin in a narrow pane, and one opened narrow kept 24 when widened.
    if (typeof ResizeObserver === "function") {
      this.resizeWidth = view.dom.clientWidth;
      this.observer = new ResizeObserver(() => {
        const w = view.dom.clientWidth;
        if (w !== this.resizeWidth) { this.resizeWidth = w; this.schedule(); }
      });
      this.observer.observe(view.dom);
    }
    this.schedule();
  }
  destroy() { this.observer?.disconnect(); this.layer.remove(); }
  update(u) {
    for (const t of u.transactions) for (const e of t.effects) { if (e.is(setActive)) { this.active = e.value; this.sig = ""; } if (e.is(setDeliveryEffect)) { this.delivery = e.value; this.sig = ""; } }
    // Moving the caret out of the active thread puts it away (the card is "active" while you're in it).
    if (u.selectionSet && this.active && !u.docChanged) {
      const t = u.state.field(reviewField).parsed.threads.find((x) => x.id === this.active);
      const h = u.state.selection.main.head;
      if (t && t.anchor && (h < t.from || h > t.to) && !this.composer) { this.active = null; this.sig = ""; }
    }
    if (u.docChanged || u.viewportChanged || u.geometryChanged || u.heightChanged || u.transactions.some((t) => t.effects.length)) this.schedule();
  }
  // Runs after the update that asked (never inside it: reading layout there isn't allowed). A timer as well as a frame,
  // because a page in a covered or background window gets no animation frames and the margin must still be laid out.
  schedule() {
    if (this.pending) return;
    this.pending = true;
    const run = () => {
      if (!this.pending) return;
      this.pending = false;
      const m = guard("read", () => this.read());
      if (m) guard("write", () => this.write(m));
    };
    setTimeout(run, 0);
    requestAnimationFrame(run);
  }
  relayout() { this.place(this.mode()); }

  mode() {
    const st = this.view.state, { parsed } = st.field(reviewField), mk = st.field(markupField);
    const W = this.view.dom.clientWidth;
    const shown = parsed.threads.filter((t) => !t.closed || mk.showClosed);
    const any = mk.mode === "all" && (parsed.threads.length > 0 || this.composer);
    return { W, narrow: W < NARROW, show: any, shown, mk, parsed, showClosed: mk.showClosed, closedCount: parsed.threads.filter((t) => t.closed).length };
  }

  // Build or reuse a card per thread; positions come from the anchors and the cards' own heights.
  read() {
    const m = this.mode();
    const signature = JSON.stringify([m.W, m.show, m.mk, m.shown.map((t) => [t.id, t.closed, t.comments.map((c) => [c.author, c.date, c.text, c.closing])]), this.active, this.composer && this.composer.from, this.hover, this.delivery]);
    return { m, signature };
  }
  colourOf(a) { return this.view.state.field(reviewField).colour[a] || 1; }
  reviewerName() { return reviewer(this.view); }
  emit(a) { emitReviewAction(a); }
  // Who the `@` menu offers besides Claude: the names in this document (comment-at stage 2, DL-251).
  people() { return atPeople(parseReview(this.view.state.doc.toString())); }
  pillOrigin(btn) { const r = btn.getBoundingClientRect(), host = this.view.dom.getBoundingClientRect(); return { x: r.left - host.left, y: r.bottom - host.top + 2 }; }
  anchorY(t) {
    const v = this.view, pos = t.anchor ? t.anchor[0] : t.from;
    const c = v.coordsAtPos(pos);
    const sc = v.scrollDOM, box = sc.getBoundingClientRect();
    if (c) return c.top - box.top + sc.scrollTop;
    return v.lineBlockAt(pos).top + v.documentPadding.top;
  }
  composerY() { const c = this.composer; return c ? this.anchorY({ anchor: [c.from, c.to], from: c.from }) : 0; }
  write({ m, signature }) {
    const v = this.view;
    // The text column gives up the margin's width: its right edge sits 12 left of the cards (the content's own padding is 28).
    v.contentDOM.style.marginRight = m.show ? (m.narrow ? GUTTER : MARGIN_W + MARGIN_RIGHT + GAP_TEXT - 28) + "px" : "";
    this.layer.style.display = m.show ? "block" : "none";
    if (!m.show) { this.layer.textContent = ""; this.sig = ""; v.contentDOM.style.minHeight = ""; return; }
    if (signature !== this.sig) { this.sig = signature; this.build(m); }
    this.place(m);
  }
  finish(bottom) {
    // The margin extends the document when cards run past its end.
    const v = this.view;
    const docBottom = v.contentHeight + v.documentPadding.top;
    v.contentDOM.style.minHeight = bottom + 24 > docBottom ? (bottom + 24 - v.documentPadding.top) + "px" : "";
    this.layer.style.height = Math.max(bottom, 0) + "px";
  }

  // ---------- interaction ----------

  reply(id, text) {
    if (!replyTo(this.view, id, text)) return false;
    if (/@claude\b/i.test(text)) emitReviewAction({ op: "send", id });
    return true;
  }
  act(op, id) { ({ close: closeThread, reopen: reopenThread, delete: deleteThread })[op](this.view, id); }
  escaped() { this.view.focus(); }
  setHover(id) {
    if (this.hover === id) return;
    super.setHover(id);
    this.view.contentDOM.querySelectorAll(".duo-rv-hl-hot").forEach((e) => e.classList.remove("duo-rv-hl-hot"));
    if (id) this.view.contentDOM.querySelectorAll(`[data-rv="${id}"]`).forEach((e) => e.classList.add("duo-rv-hl-hot"));
  }
  anchorHover(e) { const a = e.target.closest && e.target.closest("[data-rv]"); const id = a && this.cards.has(a.dataset.rv) ? a.dataset.rv : null; if (id || this.hover) { if (id !== this.hover && !(this.layer.contains(e.target))) this.setHover(id); } }
  anchorClick(e) {
    const a = e.target.closest && e.target.closest("[data-rv]");
    if (a && this.cards.has(a.dataset.rv)) this.setActive(a.dataset.rv);
  }
  compose(range, quiet) {
    let { from, to } = range || this.view.state.selection.main;
    if (from === to) { const w = this.view.state.wordAt(from); if (!w) return false; from = w.from; to = w.to; }
    this.composer = { from, to, quiet: !!quiet }; this.active = null; this.sig = ""; this.schedule();
    return true;
  }
  post(text) {
    const c = this.composer;
    if (!c || !text.trim()) return;
    this.composer = null; this.composerDom = null;
    const id = addThread(this.view, text.trim(), c);
    if (id) this.active = id;
    if (id && /@claude\b/i.test(text)) emitReviewAction({ op: "send", id });   // Post sends (DL-236 10A)
    this.sig = ""; this.schedule();
  }
  cancelCompose() { this.composer = null; this.composerDom = null; this.sig = ""; this.schedule(); this.view.focus(); }
}

const margin = ViewPlugin.fromClass(Margin);
export const marginExtensions = [margin];
export const setDelivery = (view, map, def) => { view.dispatch({ effects: setDeliveryEffect.of({ map: map || {}, def: def || null }) }); return true; };
export const activate = (view, id) => view.dispatch({ effects: setActive.of(id) });
export const composeComment = (view, range, quiet) => { const p = view.plugin(margin); return p ? p.compose(range, quiet) : false; };
export const activeThread = (view) => { const p = view.plugin(margin); return p ? p.active : null; };

export const marginTheme = EditorView.baseTheme({
  ...cardStyles,
  ".duo-rv-hl-hot": { backgroundColor: "var(--duo-comment-highlight-active) !important" },
});
