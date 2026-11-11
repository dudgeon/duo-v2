// The cards of a review margin, host-agnostic (DL-237; target markdown-review-handoff `margin-crowded`, `margin-thread`,
// `margin-narrow`, `close-*`, `margin-claude`): thread cards level with their anchors, the active card with its reply
// field and Close and Keep / Delete, closed threads folded into "n closed · Show", under 420 a gutter of count markers
// and a popover, @claude's delivery lines and session pill, and the composer. Two hosts draw them: the Markdown editor
// (margin.js: anchors are text in a CodeMirror document, edits are transactions) and the PDF viewer (side-margin.js:
// anchors are highlights PDFKit draws, edits are Swift's writes to the file). The look is one thing because the code is.
//
// A host extends `Cards` and provides: relayout(), schedule(), anchorY(thread), composerY(), finish(bottom), reviewerName(),
// people(), emit(action), colourOf(name), reply(id, text) -> bool, act(op, id) for close/reopen/delete, post(text),
// cancelCompose(), pillOrigin(button) -> {x, y}, and may override setActive/setHover/escaped.
import { attachAtMenu, atTheme } from "./atmenu.js";

export const MARGIN_W = 180, MARGIN_RIGHT = 20, GAP_TEXT = 12, CARD_GAP = 10, ACTIVE_W = 192, NARROW = 420, GUTTER = 24, POPOVER_W = 280;

export const day = (iso) => { if (!iso) return ""; const d = new Date(iso + "T12:00:00"); return isNaN(d) ? iso : d.getDate() + " " + d.toLocaleString("en", { month: "short" }); };
export const person = (a) => a ? a.charAt(0).toUpperCase() + a.slice(1) : "Someone";
export const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; };

export class Cards {
  constructor(layer) {
    this.layer = layer;
    this.delivery = { map: {}, def: null }; this.active = null; this.hover = null; this.composer = null; this.cards = new Map(); this.sig = ""; this.width = 0;
  }

  // m: { W, narrow, show, shown: [thread], closedCount, showClosed }; a thread: { id, closed, comments: [{ author, date, text, closing }] }
  build(m) {
    this.layer.textContent = "";
    this.cards = new Map();
    const n = (a) => this.colourOf(a);
    for (const t of m.shown) {
      const open = this.active === t.id;
      const c = this.card(t, m, open, n);
      this.cards.set(t.id, c);
      if (!m.narrow || open) this.layer.appendChild(c.dom);
      if (m.narrow) this.layer.appendChild(this.marker(t, open));
    }
    if (this.composer) this.layer.appendChild(this.composerCard(m));
    const closed = m.closedCount;
    this.foot = null;
    if (closed && !m.narrow) {
      const f = el("div", "duo-mg-foot");
      f.append(document.createTextNode(`${closed} closed · `));
      const link = el("span", "duo-mg-link", m.showClosed ? "Hide" : "Show");
      link.addEventListener("mousedown", (e) => { e.preventDefault(); e.stopPropagation(); this.emit({ op: "showClosed", value: !m.showClosed }); });
      f.append(link);
      this.foot = f;
      this.layer.appendChild(f);
    }
  }

  nameLine(c, n, extra) {
    const line = el("div", "duo-mg-line");
    const who = el("span", `duo-mg-who duo-rv-a${c.author === "claude" ? 3 : n(c.author)}`, person(c.author));
    line.append(who, el("span", "duo-mg-date", ` · ${day(c.date)}${extra || ""}`));
    return line;
  }
  body(text) {
    const d = el("div", "duo-mg-text");
    for (const p of text.split(/((?:^|(?<=\s))@[\w][\w-]*)/)) {
      if (/^@claude$/i.test(p)) d.append(el("span", "duo-mg-claude", p));
      else if (/^@[\w][\w-]*$/.test(p)) d.append(el("span", "duo-mg-mention", p));   // a person's tag: text, drawn as a mention, routes nothing
      else if (p) d.append(document.createTextNode(p));
    }
    return d;
  }

  card(t, m, open, n) {
    const dom = el("div", "duo-mg-card" + (open ? " duo-mg-open" : "") + (t.closed ? " duo-mg-closed" : "") + (m.narrow && open ? " duo-mg-pop" : ""));
    dom.dataset.thread = t.id;
    const root = t.comments.find((c) => !c.closing) || t.comments[0];
    const replies = t.comments.filter((c) => !c.closing).slice(1);
    const closing = t.comments[t.comments.length - 1]?.closing ? t.comments[t.comments.length - 1] : null;
    if (t.closed && !open) {
      // Shown but closed: one line in text2 (close-shown).
      dom.textContent = "";
      dom.classList.add("duo-mg-fold");
      dom.append(document.createTextNode(`› Closed · ${person(root.author)}: ${root.text}`));
    } else {
      if (t.closed && closing) dom.append(el("div", "duo-mg-closedby", closing.author ? `Closed by ${person(closing.author)} · ${day(closing.date)}` : "Closed"));
      dom.append(this.nameLine(root, n), this.body(root.text));
      this.deliveryLines(dom, t);
      if (!open) {
        const text = dom.querySelector(".duo-mg-text"); text.classList.add("duo-mg-clamp");
        if (replies.length) dom.append(el("div", "duo-mg-replies", `${replies.length} ${replies.length === 1 ? "reply" : "replies"}`));
      } else {
        const shown = replies.length > 3 ? replies.slice(-2) : replies;
        if (replies.length > 3) { const more = el("div", "duo-mg-more", `${replies.length - 2} more replies`); dom.append(more); }
        for (const r of shown) { const rd = el("div", "duo-mg-reply"); rd.append(this.nameLine(r, n), this.body(r.text)); dom.append(rd); }
        const field = el("textarea", "duo-mg-field"); field.rows = 1; field.placeholder = t.closed ? "Reply to reopen…" : "Reply…";
        attachAtMenu(field, dom, () => { field.style.height = "auto"; field.style.height = field.scrollHeight + "px"; this.relayout(); }, () => this.people());
        field.addEventListener("keydown", (e) => this.fieldKey(e, t, field));
        field.addEventListener("input", () => { field.style.height = "auto"; field.style.height = field.scrollHeight + "px"; this.relayout(); });
        dom.append(field);
        const verbs = el("div", "duo-mg-verbs");
        for (const [label, op] of t.closed ? [["Reopen", "reopen"], ["Delete", "delete"]] : [["Close and Keep", "close"], ["Delete", "delete"]]) {
          const b = el("button", "duo-rv-btn", label); b.type = "button"; b.dataset.op = op;
          verbs.append(b);
        }
        dom.append(verbs);
        this.field = field;
      }
    }
    dom.addEventListener("mouseenter", () => this.setHover(t.id));
    dom.addEventListener("mouseleave", () => this.setHover(null));
    return { dom, t };
  }
  // @claude (DL-236 9A, 10A; margin-claude): where it goes, and how far it got. Never auto-sent from the file (C-112).
  deliveryLines(dom, t) {
    if (!t.comments.some((c) => /@claude\b/i.test(c.text))) return;
    if (t.comments.some((c) => c.author === "claude")) { dom.append(this.pill(this.delivery.map[t.id], t)); return; }   // answered: the status goes, the pill stays
    const d = this.delivery.map[t.id];
    const line = (txt, glyph) => { const l = el("div", "duo-mg-status"); if (glyph) l.append(glyph); l.append(document.createTextNode(txt)); return l; };
    const glyph = (cls) => { const g = el("span", "duo-mg-glyph " + cls); return g; };
    const btn = (label, op) => { const b = el("button", "duo-rv-btn", label); b.type = "button"; b.dataset.op = op; return b; };
    if (!d) {
      dom.append(line("Not sent"));
      const row = el("div", "duo-mg-verbs"); row.append(btn("Send", "send")); dom.append(row);
      dom.append(this.pill(null, t));
      return;
    }
    if (d.state === "queued") dom.append(line("Queued: waits for its turn", glyph("duo-mg-dash")));
    else if (d.state === "sent") dom.append(line(`Sent · ${d.at}`));
    else if (d.state === "replying") dom.append(line("Claude is replying", glyph("duo-mg-ring")));
    else if (d.state === "not-delivered") {
      dom.append(line(`Not delivered: ${d.why || d.name + " ended"}`));
      const row = el("div", "duo-mg-verbs"); row.append(btn("Retry", "retry"), btn("Send To…", "pillbtn")); dom.append(row);
    }
    dom.append(this.pill(d, t));
  }
  // `>_ name · at prompt ⌄`: height 20, radius 9; a click picks the session (Send To).
  pill(d, t) {
    const src = d || this.delivery.def || { name: "New Session", status: "" };
    const p = el("button", "duo-mg-pill"); p.type = "button"; p.dataset.op = "pill"; p.dataset.id = t ? t.id : "";
    p.append(el("span", "duo-mg-pill-mono", ">_"), el("span", "duo-mg-pill-name", src.name || "New Session"));
    if (src.status) p.append(el("span", "duo-mg-pill-status", ` · ${src.status}`));
    p.append(el("span", "duo-mg-pill-chev", "⌄"));
    return p;
  }
  marker(t, open) {
    const mk = el("div", "duo-mg-marker" + (open ? " duo-mg-marker-open" : ""), String(t.comments.filter((c) => !c.closing).length));
    mk.dataset.thread = t.id; mk.dataset.marker = "1";
    return mk;
  }
  composerCard(m) {
    const dom = el("div", "duo-mg-card duo-mg-open duo-mg-composer");
    dom.append(el("div", "duo-mg-line", person(this.reviewerName())));
    const field = el("textarea", "duo-mg-field"); field.rows = 2; field.placeholder = "Comment…";
    const to = el("div", "duo-mg-to"); to.style.display = "none"; to.append(el("div", "duo-mg-to-label", "To"), this.pill(null, null));
    field.addEventListener("input", () => { to.style.display = /@claude\b/i.test(field.value) ? "block" : "none"; this.relayout(); });
    const verbs = el("div", "duo-mg-verbs");
    const post = el("button", "duo-rv-btn", "Post"); post.type = "button"; post.dataset.op = "post";
    const cancel = el("button", "duo-rv-btn", "Cancel"); cancel.type = "button"; cancel.dataset.op = "cancel";
    verbs.append(post, cancel);
    attachAtMenu(field, dom, () => field.dispatchEvent(new Event("input")), () => this.people());
    field.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) { e.preventDefault(); this.post(field.value); }
      if (e.key === "Escape") { e.preventDefault(); this.cancelCompose(); }
    });
    dom.append(field, to, verbs);
    dom.dataset.composer = "1";
    this.composerField = field; this.composerDom = dom;
    // A comment asked for from a preview (R12) leaves the keyboard where it is: a click in the field takes it.
    if (!(this.composer && this.composer.quiet)) setTimeout(() => field.focus(), 0);
    return dom;
  }

  fieldKey(e, t, field) {
    if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
      e.preventDefault();
      if (this.reply(t.id, field.value)) this.sig = "";
    } else if (e.key === "Escape") { e.preventDefault(); this.setActive(null); this.escaped(); }
  }
  escaped() {}

  // ---------- positions ----------

  place(m) {
    const W = m.W;
    const items = m.shown.map((t) => ({ t, card: this.cards.get(t.id), y: this.anchorY(t) })).filter((x) => x.card);
    items.sort((a, b) => a.y - b.y);
    const left = W - MARGIN_W - MARGIN_RIGHT, activeLeft = left - 12;
    let bottom = 0;
    if (m.narrow) {
      // Markers stack 4 apart where they meet; the open thread is a popover under its anchor's line.
      let last = -1e9;
      for (const it of items) {
        const mk = this.layer.querySelector(`.duo-mg-marker[data-thread="${it.t.id}"]`);
        const y = Math.max(it.y + 2, last + 16 + 4);
        if (mk) { mk.style.top = y + "px"; mk.style.left = (W - GUTTER + 2) + "px"; }
        last = y; bottom = Math.max(bottom, y + 16);
        if (this.active === it.t.id) {
          const d = it.card.dom;
          d.style.width = POPOVER_W + "px";
          d.style.left = Math.max(8, Math.min(20, W - POPOVER_W - 8)) + "px";
          d.style.top = (it.y + 24) + "px";
          bottom = Math.max(bottom, it.y + 24 + d.offsetHeight);
        }
      }
    } else {
      // Widths first: a card's height depends on the width its text wraps at (F-400).
      items.forEach((it) => { const a = this.active === it.t.id; it.card.dom.style.width = (a ? ACTIVE_W : MARGIN_W) + "px"; });
      const heights = items.map((it) => it.card.dom.offsetHeight || 60);
      const activeIx = items.findIndex((it) => this.active === it.t.id);
      const tops = items.map(() => 0);
      if (activeIx < 0) {
        let prev = -1e9;
        items.forEach((it, i) => { tops[i] = Math.max(it.y, prev + CARD_GAP); prev = tops[i] + heights[i]; });
      } else {
        tops[activeIx] = items[activeIx].y;
        // Above: slide up to make room (each at its anchor or as high as the one below allows).
        let limit = tops[activeIx] - CARD_GAP;
        for (let i = activeIx - 1; i >= 0; i--) { tops[i] = Math.min(items[i].y, limit - heights[i]); limit = tops[i] - CARD_GAP; }
        // Below: pushed down.
        let prev = tops[activeIx] + heights[activeIx];
        for (let i = activeIx + 1; i < items.length; i++) { tops[i] = Math.max(items[i].y, prev + CARD_GAP); prev = tops[i] + heights[i]; }
      }
      // The first card can't go above the top of the document.
      const shift = Math.min(0, ...tops) < 0 ? -Math.min(...tops) : 0;
      items.forEach((it, i) => {
        const d = it.card.dom, isActive = i === activeIx;
        d.style.left = (isActive ? activeLeft : left) + "px";
        d.style.width = (isActive ? ACTIVE_W : MARGIN_W) + "px";
        d.style.top = (tops[i] + shift) + "px";
        // The live height, not the one measured before the cards moved: the foot follows a card that grew.
        bottom = Math.max(bottom, tops[i] + shift + (d.offsetHeight || heights[i]));
      });
    }
    if (this.composerDom) {
      const y = this.composerY();
      const d = this.composerDom;
      if (m.narrow) { d.style.left = "20px"; d.style.width = POPOVER_W + "px"; d.style.top = (y + 24) + "px"; }
      else { d.style.left = (left - 12) + "px"; d.style.width = ACTIVE_W + "px"; d.style.top = y + "px"; }
      bottom = Math.max(bottom, y + d.offsetHeight + 24);
    }
    if (this.foot) { this.foot.style.left = left + "px"; this.foot.style.width = MARGIN_W + "px"; this.foot.style.top = (bottom + 12) + "px"; bottom += 12 + 16; }
    this.finish(bottom);
  }

  // ---------- interaction ----------

  setActive(id) { this.active = id; this.sig = ""; this.schedule(); }
  setHover(id) {
    if (this.hover === id) return;
    this.hover = id;
    this.layer.querySelectorAll(".duo-mg-hot").forEach((e) => e.classList.remove("duo-mg-hot"));
    if (id) this.layer.querySelectorAll(`.duo-mg-card[data-thread="${id}"]`).forEach((e) => e.classList.add("duo-mg-hot"));
  }
  onMouse(e) {
    const btn = e.target.closest("button[data-op]"), card = e.target.closest(".duo-mg-card"), marker = e.target.closest(".duo-mg-marker");
    if (e.target.closest("textarea")) return;
    if (btn) {
      e.preventDefault();
      const id = card && card.dataset.thread;
      switch (btn.dataset.op) {
        case "close": this.act("close", id); this.active = null; break;
        case "reopen": this.act("reopen", id); break;
        case "delete": this.act("delete", id); this.active = null; break;
        case "post": this.post(this.composerField.value); break;
        case "send": case "retry": this.emit({ op: btn.dataset.op, id }); break;
        case "pill": case "pillbtn": {
          const o = this.pillOrigin(btn);
          this.emit({ op: "pill", id: id || btn.dataset.id, x: o.x, y: o.y });
          break;
        }
        case "cancel": this.cancelCompose(); break;
      }
      this.sig = ""; this.schedule();
      return;
    }
    if (e.target.closest(".duo-mg-more")) { e.preventDefault(); return; }
    const id = (marker || card)?.dataset.thread;
    if (id) { e.preventDefault(); this.setActive(this.active === id && marker ? null : id); if (this.field) setTimeout(() => this.field && this.field.focus(), 0); }
  }
}

export const cardStyles = {
  ".duo-mg": { position: "absolute", top: "0", left: "0", width: "100%", pointerEvents: "none", zIndex: "2" },
  ".duo-mg > *": { pointerEvents: "auto" },
  ".duo-mg-card": { position: "absolute", boxSizing: "border-box", backgroundColor: "var(--duo-pane)", border: "1px solid var(--duo-rule)", borderRadius: "6px", padding: "8px 10px", font: "12px/16px var(--duo-font-ui)", color: "var(--duo-text)", cursor: "default", overflow: "hidden" },
  ".duo-mg-card.duo-mg-hot": { borderColor: "var(--duo-control-edge)" },
  ".duo-mg-open": { border: "1.5px solid var(--duo-text)", padding: "7.5px 9.5px", overflow: "visible" },
  ".duo-mg-pop": { borderRadius: "10px", boxShadow: "var(--duo-shadow-popover)", padding: "10px 12px", zIndex: "3" },
  ".duo-mg-who": { fontWeight: "600" },
  ".duo-mg-date": { color: "var(--duo-text2)" },
  ".duo-mg-mention": { fontWeight: "600" },
  ".duo-mg-claude": { fontWeight: "600", color: "var(--duo-review-3)" },
  ".duo-mg-clamp": { display: "-webkit-box", WebkitLineClamp: "2", WebkitBoxOrient: "vertical", overflow: "hidden" },
  ".duo-mg-replies": { color: "var(--duo-text2)" },
  ".duo-mg-more": { color: "var(--duo-text2)", textDecoration: "underline" },
  ".duo-mg-reply": { marginLeft: "12px", marginTop: "6px" },
  ".duo-mg-field": { display: "block", width: "100%", boxSizing: "border-box", marginTop: "8px", resize: "none", font: "12px/16px var(--duo-font-ui)", color: "var(--duo-text)", backgroundColor: "var(--duo-pane)", border: "1px solid var(--duo-rule)", borderRadius: "6px", padding: "4px 8px", outline: "none" },
  ".duo-mg-field:focus": { borderColor: "var(--duo-control-edge)" },
  ".duo-mg-verbs": { display: "flex", gap: "6px", marginTop: "8px", flexWrap: "wrap" },
  ".duo-mg-verbs .duo-rv-btn": { padding: "4px 8px" },
  ".duo-mg-fold": { color: "var(--duo-text2)", whiteSpace: "nowrap", textOverflow: "ellipsis" },
  ".duo-mg-closed.duo-mg-open": { color: "var(--duo-text2)" },
  ".duo-mg-closedby": { color: "var(--duo-text2)", font: "11px/16px var(--duo-font-ui)" },
  ".duo-mg-foot": { position: "absolute", font: "12px/16px var(--duo-font-ui)", color: "var(--duo-text2)" },
  ".duo-mg-link": { textDecoration: "underline", color: "var(--duo-text)", cursor: "default" },
  ".duo-mg-marker": { position: "absolute", width: "20px", height: "16px", boxSizing: "border-box", border: "1px solid var(--duo-rule)", borderRadius: "4px", backgroundColor: "var(--duo-pane)", color: "var(--duo-text2)", font: "10px/14px var(--duo-font-ui)", textAlign: "center", cursor: "default" },
  ".duo-mg-marker-open": { backgroundColor: "var(--duo-selected)", border: "1.5px solid var(--duo-text)" },
  ".duo-mg-status": { color: "var(--duo-text2)", font: "11px/16px var(--duo-font-ui)", marginTop: "4px", display: "flex", alignItems: "center", gap: "6px" },
  ".duo-mg-glyph": { display: "inline-block", flex: "none", width: "10px", height: "10px", boxSizing: "border-box" },
  ".duo-mg-dash": { height: "1.6px", backgroundColor: "var(--duo-text2)", borderRadius: "1px", alignSelf: "center" },
  ".duo-mg-ring": { border: "1.5px solid var(--duo-text)", borderRadius: "50%" },
  ".duo-mg-pill": { display: "inline-flex", alignItems: "center", maxWidth: "100%", boxSizing: "border-box", height: "20px", marginTop: "6px", padding: "0 6px", border: "1px solid var(--duo-control-edge)", borderRadius: "9px", backgroundColor: "var(--duo-pane)", color: "var(--duo-text)", font: "11px/16px var(--duo-font-ui)", cursor: "default", gap: "4px" },
  ".duo-mg-pill-mono": { fontFamily: "var(--duo-font-mono)", fontSize: "10px", color: "var(--duo-text2)", flex: "none" },
  ".duo-mg-pill-name": { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", minWidth: "0" },
  ".duo-mg-pill-status": { color: "var(--duo-text2)", whiteSpace: "nowrap", flex: "none" },
  ".duo-mg-pill-chev": { flex: "none" },
  ".duo-mg-to-label": { color: "var(--duo-text2)", font: "11px/16px var(--duo-font-ui)", marginTop: "6px" },
  ...atTheme,
};
// The names' colours and the button, which the editor's review theme (critic.js) also owns: the PDF page has no editor theme, so they are here too.
export const reviewColourStyles = {
  ...Object.fromEntries([1, 2, 3, 4, 5].map((n) => [`.duo-rv-a${n}`, { color: `var(--duo-review-${n})` }])),
  ".duo-rv-btn": { font: "12px/16px var(--duo-font-ui)", padding: "4px 10px", border: "1px solid var(--duo-control-edge)", borderRadius: "6px", backgroundColor: "var(--duo-pane)", color: "var(--duo-text)", cursor: "default" },
};
/** The style objects as plain CSS text (for a page that is not an editor). */
export function toCss(styles) {
  const kebab = (k) => k.replace(/[A-Z]/g, (c) => "-" + c.toLowerCase());
  return Object.entries(styles).map(([sel, rules]) => `${sel} { ${Object.entries(rules).map(([k, v]) => `${kebab(k)}: ${v};`).join(" ")} }`).join("\n");
}
