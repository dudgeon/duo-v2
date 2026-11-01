// Duo Decks in the editor (DL-295, DL-296, DL-303): the slide chip, the template picker (⌃⌘N and a click on a
// chip) and the anchor mark. Everything here is inert unless the document's frontmatter says `type: deck`.
// Swift owns the logic that touches the deck (DuoDeck's insert and change): this page draws, filters and reports a
// pick; Swift answers with the whole new text (`duo.deckApply`), applied as one undo step.
import { StateField, StateEffect, RangeSetBuilder, Prec } from "@codemirror/state";
import { EditorView, ViewPlugin, Decoration, WidgetType, keymap, layer, RectangleMarker } from "@codemirror/view";

const MARK = /^\s*<!--\s*slide:\s*([^\s>]+)\s*-->\s*$/;

function post(kind, body) {
  try { window.webkit?.messageHandlers?.duo?.postMessage({ kind, ...body }); } catch (_) {}
}

// `type: deck` in the first frontmatter block.
export function isDeckDoc(state) {
  const d = state.doc;
  if (d.lines < 2 || d.line(1).text.trim() !== "---") return false;
  for (let i = 2; i <= Math.min(d.lines, 40); i++) {
    const t = d.line(i).text.trim();
    if (t === "---") return false;
    if (/^type:\s*deck\s*$/.test(t)) return true;
  }
  return false;
}

// The slide markers: [{ n, name, from, to, line }] and the frontmatter's end.
export function slideMarks(state) {
  const out = [], d = state.doc;
  for (let i = 1; i <= d.lines; i++) {
    const l = d.line(i), m = MARK.exec(l.text);
    if (m) out.push({ n: out.length + 1, name: m[1], from: l.from, to: l.to, line: i });
  }
  return out;
}

// What a chip reads (pure: DuoChecks runs it): "Slide 3 · kpi ⌄".
export function chipLabel(n, name) { return { n: `Slide ${n}`, rest: name ? ` · ${name}` : "", arrow: "⌄" }; }

// The text a pick of `t` inserts: the marker, an empty title, a bare heading per other slot (Swift's Deck.skeleton).
export function skeletonLines(t) {
  const out = [`<!-- slide: ${t.name} -->`];
  const slots = t.slots || [];
  if (slots.some((s) => s.name === "title")) out.push("# ");
  for (const s of slots) if (s.name !== "title") out.push("", `## ${s.name}`);
  return out;
}

// ----- state -----

const setTemplates = StateEffect.define();
const setAnchor = StateEffect.define();
const openPicker = StateEffect.define();   // { mode: "insert"|"change", slide, at } or null
const setQuery = StateEffect.define();     // { query, sel }

const templatesField = StateField.define({
  create: () => ({ pack: "", templates: [] }),
  update(v, tr) { for (const e of tr.effects) if (e.is(setTemplates)) return e.value; return v; },
});

const anchorField = StateField.define({
  create: () => null,
  update(v, tr) { for (const e of tr.effects) if (e.is(setAnchor)) return e.value; return v; },
});

// The picker: mode "insert" has a pending chip after slide `slide` (at: doc position of the widget); "change" is
// the chip of slide `slide`.
const pickerField = StateField.define({
  create: () => null,
  update(v, tr) {
    for (const e of tr.effects) {
      if (e.is(openPicker)) return e.value ? { ...e.value, query: "", sel: 0 } : null;
      if (e.is(setQuery) && v) return { ...v, ...e.value };
    }
    if (v && tr.docChanged) return null;   // any edit closes it
    return v;
  },
});

// ----- the chip -----

class ChipWidget extends WidgetType {
  constructor(n, name, pending, query) { super(); this.n = n; this.name = name; this.pending = pending; this.query = query || ""; }
  eq(o) { return o.n === this.n && o.name === this.name && o.pending === this.pending && o.query === this.query; }
  toDOM(view) {
    const el = document.createElement("div");
    el.className = "duo-deck-chip" + (this.pending ? " duo-deck-chip-pending" : "");
    const l = chipLabel(this.n, this.name);
    const a = document.createElement("span"); a.className = "duo-deck-chip-n"; a.textContent = l.n;
    el.append(a);
    if (this.pending) {
      const q = document.createElement("span"); q.className = "duo-deck-chip-rest"; q.textContent = " · ";
      const t = document.createElement("span"); t.className = "duo-deck-chip-query"; t.textContent = this.query;
      const c = document.createElement("span"); c.className = "duo-deck-chip-caret";
      el.append(q, t, c);
    } else {
      const r = document.createElement("span"); r.className = "duo-deck-chip-rest"; r.textContent = l.rest + " " + l.arrow;
      el.append(r);
      el.addEventListener("mousedown", (e) => {
        e.preventDefault();
        view.dispatch({ effects: openPicker.of({ mode: "change", slide: this.n }) });
      });
    }
    return el;
  }
  ignoreEvent() { return true; }
}

// The decorations: a chip over each marker line (a block replace, so the line is atomic and the file unchanged), and
// the pending chip.
function chipDecos(state) {
  if (!isDeckDoc(state)) return Decoration.none;
  const b = new RangeSetBuilder();
  const picker = state.field(pickerField);
  const marks = slideMarks(state);
  const items = [];
  for (const m of marks) items.push({ from: m.from, to: m.to, deco: Decoration.replace({ widget: new ChipWidget(m.n, m.name, false), block: true }) });
  if (picker?.mode === "insert") {
    items.push({ from: picker.at, to: picker.at, deco: Decoration.widget({ widget: new ChipWidget(picker.slide + 1, "", true, picker.query), block: true, side: 1 }) });
  }
  items.sort((a, b2) => a.from - b2.from || (a.deco.startSide - b2.deco.startSide));
  for (const it of items) b.add(it.from, it.to, it.deco);
  return b.finish();
}

const chipField = StateField.define({
  create: (state) => chipDecos(state),
  update(v, tr) {
    if (tr.docChanged || tr.effects.some((e) => e.is(openPicker) || e.is(setQuery)) || tr.startState.field(pickerField) !== tr.state.field(pickerField)) return chipDecos(tr.state);
    return v;
  },
  provide: (f) => [EditorView.decorations.from(f), EditorView.atomicRanges.of((view) => view.state.field(f))],
});

// ----- the anchor mark -----

const anchorLayer = layer({
  above: false,
  class: "duo-deck-anchor-layer",
  update: (u) => u.docChanged || u.viewportChanged || u.geometryChanged || u.transactions.some((t) => t.effects.some((e) => e.is(setAnchor))),
  markers(view) {
    const a = view.state.field(anchorField);
    if (!a || !isDeckDoc(view.state)) return [];
    const d = view.state.doc;
    const first = Math.max(1, Math.min(a.first, d.lines)), last = Math.max(first, Math.min(a.last, d.lines));
    const top = view.lineBlockAt(d.line(first).from), bottom = view.lineBlockAt(d.line(last).to);
    const base = view.scrollDOM.getBoundingClientRect();
    const content = view.contentDOM.getBoundingClientRect();
    const padLeft = parseFloat(getComputedStyle(view.contentDOM).paddingLeft) || 0;
    // 8 in from the text's left edge; layer coordinates are relative to the scroller's content.
    const left = content.left - base.left + view.scrollDOM.scrollLeft + padLeft - 8 - 2;
    return [new RectangleMarker("duo-deck-anchor", left, top.top + view.documentPadding.top, 2, bottom.bottom - top.top)];
  },
});

// ----- the picker -----

let current = null;   // { el, view }

function filtered(state) {
  const p = state.field(pickerField);
  const q = (p?.query || "").toLowerCase();
  const ts = state.field(templatesField).templates;
  return ts.filter((t) => !q || t.name.toLowerCase().includes(q) || (t.purpose || "").toLowerCase().includes(q));
}

function thumbFor(t) {
  const box = document.createElement("div");
  box.className = "duo-deck-thumb";
  if (t.thumb) {
    const img = document.createElement("img"); img.src = t.thumb; img.alt = ""; box.append(img);
    return box;
  }
  // A stand-in drawn from the slots until Duo can draw the pack's own pictures: a rule per slot, sized by kind.
  const slots = (t.slots || []).filter((s) => s.name !== "title");
  const title = document.createElement("i"); title.className = "duo-deck-thumb-title"; box.append(title);
  for (const s of slots.slice(0, 4)) {
    const k = document.createElement("i");
    k.className = "duo-deck-thumb-" + (s.kind === "image" ? "image" : s.kind === "table" || s.kind === "chart" ? "table" : "text");
    box.append(k);
  }
  return box;
}

function closePicker() { if (current) { current.el.remove(); current = null; } }

function renderPicker(view) {
  const p = view.state.field(pickerField);
  if (!p) { closePicker(); return; }
  const list = filtered(view.state);
  const all = view.state.field(templatesField).templates;
  if (p.sel >= list.length) p.sel = Math.max(0, list.length - 1);
  if (!current) {
    const el = document.createElement("div");
    el.className = "duo-deck-picker";
    document.body.append(el);
    current = { el, view };
  }
  const el = current.el;
  el.textContent = "";
  const ul = document.createElement("ul");
  list.forEach((t, i) => {
    const li = document.createElement("li");
    if (i === p.sel) li.setAttribute("aria-selected", "true");
    li.append(thumbFor(t));
    const txt = document.createElement("div"); txt.className = "duo-deck-row-text";
    const nm = document.createElement("div"); nm.className = "duo-deck-row-name"; nm.textContent = t.name;
    const pu = document.createElement("div"); pu.className = "duo-deck-row-purpose"; pu.textContent = t.purpose || "";
    txt.append(nm, pu); li.append(txt);
    li.addEventListener("mousedown", (e) => { e.preventDefault(); choose(view, t); });
    li.addEventListener("mousemove", () => { if (p.sel !== i) { view.dispatch({ effects: setQuery.of({ sel: i }) }); } });
    ul.append(li);
  });
  if (!list.length) { const e = document.createElement("div"); e.className = "duo-deck-empty"; e.textContent = all.length ? "No template matches" : "No templates found"; el.append(e); }
  else el.append(ul);
  const foot = document.createElement("div"); foot.className = "duo-deck-foot";
  foot.textContent = `↩ ${p.mode === "insert" ? "insert" : "change"} · esc cancel · type to filter ${all.length} template${all.length === 1 ? "" : "s"}`;
  el.append(foot);
  // Under the chip (or the pending chip), left edge at the text column.
  const chips = view.dom.querySelectorAll(".duo-deck-chip");
  let anchorEl = null;
  if (p.mode === "insert") anchorEl = view.dom.querySelector(".duo-deck-chip-pending");
  else for (const c of chips) if (c.firstChild?.textContent === `Slide ${p.slide}`) anchorEl = c;
  const r = anchorEl?.getBoundingClientRect() || view.dom.getBoundingClientRect();
  const w = Math.min(340, window.innerWidth - 24);
  el.style.width = w + "px";
  el.style.left = Math.max(12, Math.min(r.left, window.innerWidth - w - 12)) + "px";
  const h = el.offsetHeight;
  const below = r.bottom + 4;
  el.style.top = (below + h > window.innerHeight - 8 ? Math.max(8, r.top - h - 4) : below) + "px";
  el.querySelector("[aria-selected]")?.scrollIntoView({ block: "nearest" });
}

function choose(view, t) {
  const p = view.state.field(pickerField);
  if (!p) return;
  view.dispatch({ effects: openPicker.of(null) });
  post("deckPick", { op: p.mode, slide: p.slide, template: t.name, text: view.state.doc.toString() });
}

function cancel(view) {
  view.dispatch({ effects: openPicker.of(null) });
}

// Where a new chip goes: after slide n's last content line (before the next marker, past its trailing blanks and rule).
function insertionPoint(state, n) {
  const marks = slideMarks(state), d = state.doc;
  if (n >= marks.length) return d.length;
  let ln = marks[n].line - 1;
  while (ln > marks[n - 1].line && (d.line(ln).text.trim() === "" || d.line(ln).text.trim() === "---")) ln--;
  return d.line(ln).to + 1 > d.length ? d.length : d.line(ln).to + 1;
}

function slideAtCaret(state) {
  const marks = slideMarks(state);
  const line = state.doc.lineAt(state.selection.main.head).number;
  let n = 0;
  for (const m of marks) if (m.line <= line) n = m.n;
  return n;   // 0: above the first slide
}

function newSlide(view) {
  if (!view || !isDeckDoc(view.state)) return false;
  const n = slideAtCaret(view.state);
  const marks = slideMarks(view.state);
  // Under a deck with no slides, or the caret before the first: after slide 0 would be first; use the last slide for the former.
  const slide = marks.length ? Math.max(n, 0) : 0;
  const at = slide === 0 ? (marks.length ? Math.max(0, view.state.doc.line(marks[0].line).from) : view.state.doc.length) : insertionPoint(view.state, slide);
  view.dispatch({ effects: openPicker.of({ mode: "insert", slide, at }), scrollIntoView: false });
  return true;
}

const pickerKeys = Prec.highest(EditorView.domEventHandlers({
  keydown(e, view) {
    const p = view.state.field(pickerField);
    if (!p) return false;
    const list = filtered(view.state);
    const stop = () => { e.preventDefault(); e.stopPropagation(); return true; };
    if (e.key === "Escape") { cancel(view); return stop(); }
    if (e.key === "Enter") { const t = list[p.sel]; if (t) choose(view, t); return stop(); }
    if (e.key === "ArrowDown") { view.dispatch({ effects: setQuery.of({ sel: Math.min(list.length - 1, p.sel + 1) }) }); return stop(); }
    if (e.key === "ArrowUp") { view.dispatch({ effects: setQuery.of({ sel: Math.max(0, p.sel - 1) }) }); return stop(); }
    if (e.key === "Backspace") { view.dispatch({ effects: setQuery.of({ query: p.query.slice(0, -1), sel: 0 }) }); return stop(); }
    if (e.key === "Tab") return stop();
    if (e.key.length === 1 && !e.metaKey && !e.ctrlKey) { view.dispatch({ effects: setQuery.of({ query: p.query + e.key, sel: 0 }) }); return stop(); }
    return false;
  },
  mousedown(e, view) { if (view.state.field(pickerField) && !e.target.closest?.(".duo-deck-chip")) cancel(view); return false; },
  blur(e, view) { if (view.state.field(pickerField)) cancel(view); return false; },
}));

// ----- the plugin: reports the caret, installs the page's verbs, keeps the picker drawn -----

const deckPlugin = ViewPlugin.fromClass(class {
  constructor(view) {
    this.view = view; this.timer = null; this.reportedDeck = null;
    installApi(view);
    this.check();
  }
  check() {
    const deck = isDeckDoc(this.view.state);
    if (deck !== this.reportedDeck) post("deckDoc", { deck });
    this.reportedDeck = deck;
  }
  update(u) {
    if (u.docChanged) this.check();
    if (this.reportedDeck && (u.selectionSet || u.docChanged)) {
      clearTimeout(this.timer);
      this.timer = setTimeout(() => {
        const s = this.view.state;
        post("deckCaret", { line: s.doc.lineAt(s.selection.main.head).number, text: s.doc.toString() });
      }, 120);
    }
    if (u.state.field(pickerField) !== u.startState.field(pickerField) || u.docChanged) renderPicker(u.view);
  }
  destroy() { clearTimeout(this.timer); closePicker(); }
});

let apiView = null;
function installApi(view) {
  apiView = view;
  if (!window.duo || window.duo.__deck) return;
  window.duo.__deck = true;
  Object.assign(window.duo, {
    // Templates the picker lists: { pack, templates: [{ name, purpose, slots: [{ name, kind }], thumb? }] }.
    setDeckTemplates(json) {
      const v = typeof json === "string" ? JSON.parse(json) : json;
      const t = Array.isArray(v) ? { pack: "", templates: v } : v;
      apiView.dispatch({ effects: setTemplates.of({ pack: t.pack || "", templates: t.templates || [] }) });
      return true;
    },
    // The caret's slide: the lines first…last (1-based, from DuoDeck's parser).
    setDeckAnchor(first, last) {
      apiView.dispatch({ effects: setAnchor.of(first > 0 ? { first, last } : null) });
      return true;
    },
    // Scroll first…last into view and put the caret on the slot's first content line, without taking focus.
    revealDeckSlot(first, last) {
      const d = apiView.state.doc;
      if (first < 1 || first > d.lines) return false;
      const lastL = Math.max(first, Math.min(last || first, d.lines));
      let at = first;   // the first line that isn't the marker or blank
      for (let i = first; i <= lastL; i++) { const t = d.line(i).text; if (t.trim() && !MARK.test(t)) { at = i; break; } }
      const pos = d.line(at).from;
      apiView.dispatch({ selection: { anchor: pos }, effects: [EditorView.scrollIntoView(pos, { y: "nearest", yMargin: 24 }), EditorView.scrollIntoView(d.line(lastL).to, { y: "nearest" })] });
      return true;
    },
    // Swift's answer to a pick: the whole new text, applied as the smallest change (one undo step); the caret goes to
    // `line` (1-based), at its end.
    deckApply(text, line) {
      const old = apiView.state.doc.toString();
      if (old !== text) {
        let a = 0; const max = Math.min(old.length, text.length);
        while (a < max && old.charCodeAt(a) === text.charCodeAt(a)) a++;
        let b = 0;
        while (b < max - a && old.charCodeAt(old.length - 1 - b) === text.charCodeAt(text.length - 1 - b)) b++;
        const ln = Math.min(Math.max(1, line || 1), text.split("\n").length);
        const spec = { changes: { from: a, to: old.length - b, insert: text.slice(a, text.length - b) }, userEvent: "input.deck", scrollIntoView: true };
        apiView.dispatch(spec);
        if (line) { const d = apiView.state.doc; const l = d.line(Math.min(ln, d.lines)); apiView.dispatch({ selection: { anchor: l.to }, scrollIntoView: true }); }
      }
      return true;
    },
    deckNewSlide() { return newSlide(apiView); },
    // Harness hooks (captures and checks): type into the picker as a person would, and put the caret in slide n.
    deckType(q) { const p = apiView.state.field(pickerField); if (!p) return false; apiView.dispatch({ effects: setQuery.of({ query: p.query + q, sel: 0 }) }); return true; },
    deckGo(n) { const m = slideMarks(apiView.state)[n - 1]; if (!m) return false; const d = apiView.state.doc; let at = m.line + 1; while (at < d.lines && !d.line(at).text.trim()) at++; apiView.dispatch({ selection: { anchor: d.line(Math.min(at, d.lines)).to } }); return true; },
    deckPickerOpen() { return !!apiView?.state.field(pickerField); },
    deckProbe() { return { deck: isDeckDoc(apiView.state), marks: slideMarks(apiView.state).length, picker: apiView.state.field(pickerField) }; },
  });
}

const deckTheme = EditorView.baseTheme({
  ".duo-deck-chip": { display: "block", boxSizing: "border-box", height: "22px", marginTop: "6px", paddingTop: "0", borderTop: "1px solid var(--duo-rule)", font: "11px/20px var(--duo-font-ui)", color: "var(--duo-text2)", cursor: "pointer", userSelect: "none" },
  ".duo-deck-chip-n": { color: "var(--duo-text)", fontWeight: "600" },
  ".duo-deck-chip-pending": { cursor: "default" },
  ".duo-deck-chip-query": { fontFamily: "var(--duo-font-mono)", color: "var(--duo-text)" },
  ".duo-deck-chip-caret": { display: "inline-block", width: "1px", height: "12px", marginLeft: "1px", verticalAlign: "-2px", backgroundColor: "var(--duo-text)" },
  ".duo-deck-anchor": { position: "absolute", backgroundColor: "var(--duo-control-edge)", borderRadius: "1px" },
});

const pickerCSS = `
.duo-deck-picker { position: fixed; z-index: 1000; box-sizing: border-box; background: var(--duo-pane); border: 1px solid var(--duo-rule); border-radius: 10px; box-shadow: var(--duo-shadow-popover); padding: 6px; font: 13px var(--duo-font-ui); color: var(--duo-text); }
.duo-deck-picker ul { list-style: none; margin: 0; padding: 0; max-height: 260px; overflow-y: auto; }
.duo-deck-picker li { display: flex; align-items: center; gap: 8px; padding: 4px 8px; border-radius: 6px; cursor: default; }
.duo-deck-picker li[aria-selected] { background: var(--duo-selected); }
.duo-deck-thumb { position: relative; flex: none; width: 56px; height: 32px; box-sizing: border-box; background: var(--duo-ground); border: 1px solid var(--duo-rule); border-radius: 3px; overflow: hidden; }
.duo-deck-thumb img { width: 100%; height: 100%; object-fit: cover; display: block; }
.duo-deck-thumb i { position: absolute; display: block; background: var(--duo-text2); opacity: .45; border-radius: 1px; }
.duo-deck-thumb-title { left: 5px; top: 5px; width: 22px; height: 3px; opacity: .8 !important; background: var(--duo-text) !important; }
.duo-deck-thumb-text { left: 5px; width: 30px; height: 2px; }
.duo-deck-thumb-image, .duo-deck-thumb-table { left: 5px; width: 44px; height: 11px; }
.duo-deck-thumb i:nth-child(2) { top: 13px; } .duo-deck-thumb i:nth-child(3) { top: 18px; } .duo-deck-thumb i:nth-child(4) { top: 23px; } .duo-deck-thumb i:nth-child(5) { top: 28px; }
.duo-deck-thumb-image:nth-child(2), .duo-deck-thumb-table:nth-child(2) { top: 12px; }
.duo-deck-row-text { min-width: 0; }
.duo-deck-row-name { font: 600 12px/16px var(--duo-font-mono); }
.duo-deck-row-purpose { font: 11px/14px var(--duo-font-ui); color: var(--duo-text2); }
.duo-deck-foot { padding: 6px 8px 2px; font: 11px/14px var(--duo-font-ui); color: var(--duo-text2); }
.duo-deck-empty { padding: 6px 8px; color: var(--duo-text2); }
`;

let cssAdded = false;
function addCSS() {
  if (cssAdded || typeof document === "undefined") return;
  cssAdded = true;
  const s = document.createElement("style"); s.textContent = pickerCSS; document.head.append(s);
}

// What duo-editor.js adds to its extensions: nothing is drawn unless the document is a deck.
export function deckExtensions() {
  addCSS();
  return [templatesField, anchorField, pickerField, chipField, anchorLayer, deckTheme, pickerKeys, deckPlugin];
}
