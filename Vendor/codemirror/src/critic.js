// Review in Markdown (DL-236, DL-237): CriticMarkup marks with a signature, read and drawn in the
// editor, and Suggest Edits. The grammar is the one `Review` in Sources/DuoControl/ReviewMarkup.swift
// reads (keep them the same; DuoChecks compares them on a shared document):
//
//   {++added++}  {--cut--}  {~~old~>new~~}  {==anchor==}  {>>@name 2026-10-28 #id: note<<}
//   suggestion = an insertion, deletion or substitution, then the comments right after it
//   thread     = a highlight, then its comments (or comments alone)
//   a closing line is {>>@name date #c1.2 closed<<}
//
// The scan runs over the whole document, not per paragraph, so a mark that spans paragraphs reads
// as one (Q-244). Marks inside fenced or inline code are text. The text stays the truth (LR-30):
// drawing hides the marks' syntax with decorations and never rewrites the document.
import { StateField, StateEffect, EditorState, EditorSelection } from "@codemirror/state";
import { EditorView, Decoration, hoverTooltip } from "@codemirror/view";

const OPENERS = [["{++", "++}", "ins"], ["{--", "--}", "del"], ["{~~", "~~}", "sub"], ["{==", "==}", "hl"], ["{>>", "<<}", "cm"]];

// Where marks aren't read: fenced code blocks and inline code.
function codeRanges(text) {
  const out = [];
  let pos = 0, fence = null;
  while (pos < text.length) {
    let end = text.indexOf("\n", pos);
    end = end < 0 ? text.length : end + 1;
    const line = text.slice(pos, end), t = line.trim();
    if (t.startsWith("```") || t.startsWith("~~~")) {
      if (fence != null) { out.push([fence, end]); fence = null; } else fence = pos;
    } else if (fence == null && t.includes("`")) {
      let i = pos;
      while (i < end) {
        if (text.charCodeAt(i) === 96) {
          const j = text.indexOf("`", i + 1);
          if (j >= 0 && j < end) { out.push([i, j + 1]); i = j + 1; continue; }
        }
        i++;
      }
    }
    pos = end;
  }
  if (fence != null) out.push([fence, text.length]);
  return out;
}

function rawMarks(text, within) {
  const code = codeRanges(text), out = [];
  const end = within ? within[1] : text.length;
  let i = within ? within[0] : 0;
  outer: while (i + 3 <= end) {
    if (text.charCodeAt(i) === 123 && !code.some(([a, b]) => i >= a && i < b)) {
      const head = text.slice(i, i + 3);
      for (const [open, close, kind] of OPENERS) {
        if (head !== open) continue;
        const c = text.indexOf(close, i + 3);
        if (c >= 0 && c + 3 <= end) { out.push({ kind, from: i, to: c + 3, inner: [i + 3, c] }); i = c + 3; continue outer; }
      }
    }
    i++;
  }
  return out;
}

const SIG = /^@([^\s:]+)(?:\s+(\d{4}-\d{2}-\d{2}))?(?:\s+#([\w.]+))?/;
function parseComment(body, from, to) {
  const s = body.trim(), m = SIG.exec(s);
  if (!m) return { author: null, date: null, id: null, text: s, closing: false, from, to };
  let rest = s.slice(m[0].length).trim(), closing = false;
  if (rest.startsWith(":")) rest = rest.slice(1).trim(); else if (rest === "closed") { closing = true; rest = ""; }
  return { author: m[1], date: m[2] || null, id: m[3] || null, text: rest, closing, from, to };
}

// → { suggestions: [...], threads: [...] }, each with from/to (the whole group) and its pieces.
// A comment over several paragraphs is one highlight per paragraph with the thread after the last (the converter writes
// it so, Q-244): `pieces` has them all. Marks inside a highlight are read again: a deletion in a commented range is a
// suggestion, and the highlight stays its thread's anchor.
export function parseReview(text) {
  const out = { suggestions: [], threads: [] };
  const st = { unsigned: 0 };
  group(text, rawMarks(text), out, st);
  out.suggestions.sort((a, b) => a.from - b.from);
  out.threads.sort((a, b) => a.from - b.from);
  return out;
}
function group(text, raws, out, st) {
  const commentsAfter = (i, end) => {
    const list = [];
    while (i < raws.length && raws[i].kind === "cm" && raws[i].from === end) {
      list.push({ ...parseComment(text.slice(raws[i].inner[0], raws[i].inner[1]), raws[i].from, raws[i].to) });
      end = raws[i].to; i++;
    }
    return { list, i, end };
  };
  const piece = (r) => ({ open: [r.from, r.from + 3], close: [r.to - 3, r.to], inner: r.inner });
  // A highlight's text with the marks inside it read as they are (an insertion's new text, a deletion's old).
  const flat = (inner) => {
    const nested = rawMarks(text, inner);
    let o = "", at = inner[0];
    for (const n of nested) {
      if (n.kind === "cm") { if (n.from >= at) at = Math.max(at, n.to); continue; }
      if (n.from > at) o += text.slice(at, n.from);
      const body = text.slice(n.inner[0], n.inner[1]);
      o += n.kind === "sub" && body.includes("~>") ? body.slice(body.indexOf("~>") + 2) : body;
      at = n.to;
    }
    return o + (at < inner[1] ? text.slice(at, inner[1]) : "");
  };
  for (let i = 0; i < raws.length;) {
    const r = raws[i];
    if (r.kind === "ins" || r.kind === "del" || r.kind === "sub") {
      const inner = text.slice(r.inner[0], r.inner[1]);
      const s = { kind: r.kind, from: r.from, open: [r.from, r.from + 3], close: [r.to - 3, r.to], inner: r.inner, markTo: r.to };
      if (r.kind === "sub") {
        const a = inner.indexOf("~>");
        if (a >= 0) { s.old = [r.inner[0], r.inner[0] + a]; s.arrow = [r.inner[0] + a, r.inner[0] + a + 2]; s.new = [r.inner[0] + a + 2, r.inner[1]]; }
        else { s.old = r.inner; s.new = [r.inner[1], r.inner[1]]; }
      } else if (r.kind === "ins") s.new = r.inner; else s.old = r.inner;
      const c = commentsAfter(i + 1, r.to);
      const first = c.list.find((x) => !x.closing);
      Object.assign(s, { to: c.end, comments: c.list, id: first?.id ?? null, author: first?.author ?? null, date: first?.date ?? null, note: first?.text ?? "" });
      out.suggestions.push(s);
      i = c.i;
    } else if (r.kind === "hl") {
      const pieces = [piece(r)];
      let j = i, c = commentsAfter(j + 1, raws[j].to);
      while (!c.list.length && j + 1 < raws.length && raws[j + 1].kind === "hl" && !text.slice(raws[j].to, raws[j + 1].from).trim()) {
        j++; pieces.push(piece(raws[j])); c = commentsAfter(j + 1, raws[j].to);
      }
      for (const p of pieces) group(text, rawMarks(text, p.inner), out, st);
      const first = c.list.find((x) => !x.closing);
      if (!first?.id) st.unsigned++;
      out.threads.push({ id: first?.id ?? "u" + st.unsigned, from: r.from, to: c.end, open: pieces[0].open, close: pieces[pieces.length - 1].close, anchor: pieces[0].inner, pieces,
                         anchorText: pieces.map((p) => flat(p.inner)).join("\n\n"), comments: c.list, closed: !!c.list.length && c.list[c.list.length - 1].closing });
      i = c.i;
    } else if (r.kind === "cm") {
      const c = commentsAfter(i, r.from);
      const first = c.list.find((x) => !x.closing);
      if (!first?.id) st.unsigned++;
      out.threads.push({ id: first?.id ? first.id.split(".")[0] : "u" + st.unsigned, from: r.from, to: c.end, anchor: null, pieces: [], comments: c.list, closed: !!c.list.length && c.list[c.list.length - 1].closing });
      i = c.i;
    } else i++;
  }
}

// ---------- state ----------

export const setMarkup = StateEffect.define();      // { mode, showClosed }
const markupField = StateField.define({
  create: () => ({ mode: "all", showClosed: false }),
  update(v, tr) { for (const e of tr.effects) if (e.is(setMarkup)) v = { ...v, ...e.value }; return v; },
});
export const setReviewer = StateEffect.define();    // the name that signs a person's typing
const reviewerField = StateField.define({
  create: () => (typeof window !== "undefined" && window.__reviewer) || "me",
  update(v, tr) { for (const e of tr.effects) if (e.is(setReviewer)) v = e.value; return v; },
});

// The `suggest-edits: true` line of the frontmatter (DL-237), and where the frontmatter ends.
function frontmatterEnd(doc) {
  if (doc.lines < 2 || doc.line(1).text.trimEnd() !== "---") return 0;
  for (let n = 2; n <= Math.min(doc.lines, 400); n++) {
    const t = doc.line(n).text.trimEnd();
    if (t === "---" || t === "...") return doc.line(n).to;
  }
  return 0;
}
export function suggestEditsOn(doc) {
  const end = frontmatterEnd(doc);
  if (!end) return false;
  for (let n = 2; n <= doc.lineAt(end).number - 1; n++) if (doc.line(n).text.trim().toLowerCase() === "suggest-edits: true") return true;
  return false;
}

const signatureName = (n) => n.toLowerCase().trim().replace(/\s+/g, "-").replace(/^@/, "");

// People in the order they appear; Claude is always review 3 (Q-266), the others 1, 2, 4, 5, then again.
function colours(parsed) {
  const names = [];
  const note = (a) => { if (a && !names.includes(a)) names.push(a); };
  const all = [...parsed.suggestions.map((s) => [s.from, s.author]), ...parsed.threads.flatMap((t) => t.comments.map((c) => [c.from, c.author]))].sort((a, b) => a[0] - b[0]);
  all.forEach(([, a]) => note(a));
  const order = [1, 2, 4, 5];
  const map = {};
  let k = 0;
  for (const n of names) map[n] = n === "claude" ? 3 : order[k++ % order.length];
  return map;
}

const reviewField = StateField.define({
  create: (state) => build(state),
  update(v, tr) { return tr.docChanged ? build(tr.state, v) : v; },
});
function build(state) {
  const text = state.doc.toString();
  const parsed = text.includes("{") ? parseReview(text) : { suggestions: [], threads: [] };
  const colour = colours(parsed);
  return { parsed, colour, suggest: suggestEditsOn(state.doc) };
}

// What the review bar needs.
export function reviewSummary(state) {
  const v = state.field(reviewField), p = v.parsed;
  const people = {};
  for (const s of p.suggestions) if (s.author) people[s.author] = (people[s.author] || 0) + 1;
  for (const t of p.threads) for (const c of t.comments) if (c.author && !c.closing) people[c.author] = (people[c.author] || 0) + 1;
  return {
    suggestions: p.suggestions.length, threads: p.threads.filter((t) => !t.closed).length, closed: p.threads.filter((t) => t.closed).length,
    mode: state.field(markupField).mode, showClosed: state.field(markupField).showClosed,
    suggestEdits: v.suggest, marks: p.suggestions.length + p.threads.length > 0,
    people: Object.entries(people).map(([name, count]) => ({ name, count, colour: v.colour[name] || 1 })),
  };
}

// ---------- drawing ----------

const hide = Decoration.replace({});
const day = (iso) => { if (!iso) return ""; const d = new Date(iso + "T12:00:00"); return isNaN(d) ? iso : d.getDate() + " " + d.toLocaleString("en", { month: "short" }); };
const personName = (a) => a ? a.charAt(0).toUpperCase() + a.slice(1) : "Someone";
const cls = (kind, n) => `duo-rv duo-rv-${kind} duo-rv-a${n}`;

function decorations(state) {
  const { parsed, colour } = state.field(reviewField), { mode, showClosed } = state.field(markupField);
  const out = [];
  const lines = new Set();
  const range = (a, b, d) => { if (b > a) out.push(d.range(a, b)); };
  const hideAll = (s) => range(s.from, s.to, hide);
  for (const s of parsed.suggestions) {
    const n = colour[s.author] || 1;
    const tail = [s.markTo, s.to];
    if (mode === "all") {
      range(s.open[0], s.open[1], hide); range(s.close[0], s.close[1], hide); range(tail[0], tail[1], hide);
      if (s.old) range(s.old[0], s.old[1], Decoration.mark({ class: cls("del", n), attributes: { "data-rv": s.id || "" } }));
      if (s.arrow) range(s.arrow[0], s.arrow[1], hide);
      if (s.new) range(s.new[0], s.new[1], Decoration.mark({ class: cls("ins", n), attributes: { "data-rv": s.id || "" } }));
    } else {
      // The text as accepted, or as it was.
      const part = mode === "original" ? s.old : s.new;
      if (part) { range(s.from, part[0], hide); range(part[1], s.to, hide); } else hideAll(s);
      if (mode === "simple") lines.add(state.doc.lineAt(s.from).from);
    }
  }
  for (const t of parsed.threads) {
    for (const p of t.pieces) {
      range(p.open[0], p.open[1], hide); range(p.close[0], p.close[1], hide);
      if (mode === "all" && (!t.closed || showClosed)) range(p.inner[0], p.inner[1], Decoration.mark({ class: t.closed ? "duo-rv-closed" : "duo-rv-hl", attributes: { "data-rv": t.id } }));
    }
    hideCommentsOf(t, out);
  }
  for (const from of lines) out.push(Decoration.line({ class: "duo-rv-bar" }).range(from));
  return Decoration.set(out, true);
}
function hideCommentsOf(t, out) { for (const c of t.comments) if (c.to > c.from) out.push(hide.range(c.from, c.to)); }

// Drawn in live preview only: Source mode shows the raw text (DL-167).
const decoField = StateField.define({
  create: (state) => decorations(state),
  update(v, tr) { return tr.docChanged || tr.effects.some((e) => e.is(setMarkup)) ? decorations(tr.state) : v; },
  provide: (f) => [EditorView.decorations.from(f), EditorView.atomicRanges.of((view) => view.state.field(f))],
});

// ---------- the label: Accept, Reject, Reply ----------

let onAction = () => {};
export function onReviewAction(fn) { onAction = fn; }
export function emitReviewAction(a) { onAction(a); }

function labelFor(view, s) {
  const dom = document.createElement("div");
  dom.className = "duo-rv-tip";
  const head = document.createElement("div");
  const who = document.createElement("span");
  who.className = "duo-rv-who duo-rv-a" + (view.state.field(reviewField).colour[s.author] || 1);
  who.textContent = personName(s.author);
  head.append(who, document.createTextNode(` suggested${s.date ? " · " + day(s.date) : ""}`));
  head.className = "duo-rv-tip-head";
  dom.append(head);
  if (s.note) { const n = document.createElement("div"); n.className = "duo-rv-tip-note"; n.textContent = s.note; dom.append(n); }
  const row = document.createElement("div");
  row.className = "duo-rv-tip-row";
  for (const [label, op] of [["Accept", "accept"], ["Reject", "reject"], ["Reply", "reply"]]) {
    const b = document.createElement("button");
    b.type = "button"; b.textContent = label; b.className = "duo-rv-btn";
    b.addEventListener("mousedown", (e) => {
      e.preventDefault();
      if (op === "reply") onAction({ op, id: s.id });
      else resolveSuggestion(view, s.id, op === "accept");
    });
    row.append(b);
  }
  dom.append(row);
  return { dom };
}
const labelHover = hoverTooltip((view, pos) => {
  const { parsed } = view.state.field(reviewField);
  const s = parsed.suggestions.find((x) => pos >= x.from && pos <= x.markTo);
  if (!s || view.state.field(markupField).mode !== "all") return null;
  return { pos: s.from, end: s.markTo, above: true, arrow: false, create: (v) => labelFor(v, s) };
}, { hideOnChange: true, hoverTime: 250 });

// ---------- acting on suggestions ----------

function change(s, accept) {
  const text = (r) => (r ? view_text(r) : "");
  return { from: s.from, to: s.to, insert: accept ? text(s.new) : text(s.old) };
}
let _doc = null;
function view_text(r) { return _doc.sliceString(r[0], r[1]); }
function changesFor(state, pick, accept) {
  _doc = state.doc;
  return state.field(reviewField).parsed.suggestions.filter(pick).map((s) => change(s, accept));
}
export function resolveSuggestion(view, id, accept) {
  const changes = changesFor(view.state, (s) => s.id === id, accept);
  if (!changes.length) return false;
  view.dispatch({ changes, userEvent: "review" });
  return true;
}
export function resolveAll(view, accept, person) {
  const who = person ? signatureName(person) : null;
  const changes = changesFor(view.state, (s) => !who || s.author === who, accept);
  if (!changes.length) return 0;
  view.dispatch({ changes, userEvent: "review" });
  return changes.length;
}

// The marks in document order, for ‹ ›.
export function reviewItems(state) {
  const p = state.field(reviewField).parsed;
  return [...p.suggestions.map((s) => ({ id: s.id, from: s.from, kind: "suggestion" })), ...p.threads.filter((t) => !t.closed).map((t) => ({ id: t.id, from: t.from, kind: "thread" }))].sort((a, b) => a.from - b.from);
}
export function step(view, dir) {
  const items = reviewItems(view.state);
  if (!items.length) return null;
  const head = view.state.selection.main.head;
  let i = dir > 0 ? items.findIndex((x) => x.from > head) : [...items].reverse().findIndex((x) => x.from < head);
  if (dir < 0 && i >= 0) i = items.length - 1 - i;
  if (i < 0) i = dir > 0 ? 0 : items.length - 1;
  const it = items[i];
  view.dispatch({ selection: { anchor: it.from }, effects: EditorView.scrollIntoView(it.from, { y: "center" }) });
  return { ...it, index: i + 1, total: items.length };
}

// ---------- Suggest Edits: everyone's edits become signed marks ----------

const today = () => { const d = new Date(), p = (n) => String(n).padStart(2, "0"); return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`; };
function nextIds(doc) {
  let top = 0;
  const re = /#s(\d+)/g, t = doc.toString();
  for (let m; (m = re.exec(t));) top = Math.max(top, +m[1]);
  return () => "s" + ++top;
}
const sig = (author, id) => `{>>@${signatureName(author)} ${today()} #${id}<<}`;

// A hunk of the old text as a mark: what the person typed, deleted or replaced.
function markFor(old, ins, author, id) {
  if (old && ins) return { text: `{~~${old}~>${ins}~~}${sig(author, id)}`, caret: 3 + old.length + 2 + ins.length };
  if (ins) return { text: `{++${ins}++}${sig(author, id)}`, caret: 3 + ins.length };
  return { text: `{--${old}--}${sig(author, id)}`, caret: 0 };
}
// A change is left plain inside the frontmatter, inside someone else's mark, or inside a code block.
function plainChange(state, from, to) {
  const fm = frontmatterEnd(state.doc);
  if (fm && from <= fm) return true;
  const p = state.field(reviewField).parsed;
  const overlaps = (a, b) => from < b && to > a || (from === to && from > a && from < b);
  if (p.suggestions.some((s) => overlaps(s.from, s.to) && !ownInsertion(state, s, from, to))) return true;
  if (p.threads.some((t) => overlaps(t.from, t.to))) return true;
  const t = state.doc.toString();
  return codeRanges(t).some(([a, b]) => from > a && to < b);
}
function ownInsertion(state, s, from, to) {
  return s.kind === "ins" && s.author === signatureName(state.field(reviewerField)) && from >= s.inner[0] && to <= s.inner[1];
}
function ownInsertionAt(state, from, to) {
  return state.field(reviewField).parsed.suggestions.some((s) => ownInsertion(state, s, from, to));
}
export function suggestHunks(state, hunks, author) {
  const next = nextIds(state.doc);
  return hunks.map((h) => {
    const old = state.sliceDoc(h.from, h.to);
    if (!h.insert && !old) return h;
    if (plainChange(state, h.from, h.to)) return h;
    return { from: h.from, to: h.to, insert: markFor(old, h.insert, author, next()).text, suggested: true };
  });
}
const suggestTyping = EditorState.transactionFilter.of((tr) => {
  if (!tr.docChanged || !tr.startState.field(reviewField).suggest) return tr;
  if (!(tr.isUserEvent("input") || tr.isUserEvent("delete")) || tr.isUserEvent("input.complete")) return tr;
  const hunks = [];
  tr.changes.iterChanges((from, to, _a, _b, ins) => hunks.push({ from, to, insert: ins.toString() }));
  if (hunks.length !== 1) return tr;
  const st = tr.startState, h = hunks[0];
  if (plainChange(st, h.from, h.to) || (h.from === h.to && ownInsertionAt(st, h.from, h.to))) return tr;
  if (h.from !== h.to && ownInsertionAt(st, h.from, h.to)) return tr;
  const author = st.field(reviewerField), id = nextIds(st.doc)();
  const old = st.sliceDoc(h.from, h.to), m = markFor(old, h.insert, author, id);
  return { changes: { from: h.from, to: h.to, insert: m.text }, selection: EditorSelection.cursor(h.from + m.caret), userEvent: tr.isUserEvent("delete") ? "delete.backward" : "input.type", scrollIntoView: true };
});

// ---------- theme ----------

const A = [1, 2, 3, 4, 5];
export const reviewTheme = EditorView.baseTheme({
  ".duo-rv-ins": { textDecoration: "underline", textUnderlineOffset: "3px" },
  ".duo-rv-del": { textDecoration: "line-through" },
  ...Object.fromEntries(A.map((n) => [`.duo-rv-a${n}`, { color: `var(--duo-review-${n})` }])),
  ".duo-rv-hl": { backgroundColor: "var(--duo-comment-highlight)" },
  ".duo-rv-hl:hover": { backgroundColor: "var(--duo-comment-highlight-active)" },
  ".duo-rv-closed": { textDecoration: "underline dotted var(--duo-control-edge)", textDecorationThickness: "1.5px", textUnderlineOffset: "3px" },
  ".duo-rv-bar": { boxShadow: "inset 2px 0 0 var(--duo-text2)" },
  ".duo-rv-tip": { backgroundColor: "var(--duo-pane)", border: "none !important", borderRadius: "10px", boxShadow: "var(--duo-shadow)", padding: "6px 10px 8px", font: "12px/16px -apple-system, sans-serif", color: "var(--duo-text)", maxWidth: "260px" },
  ".duo-rv-tip-head": { color: "var(--duo-text2)" },
  ".duo-rv-who": { fontWeight: "600" },
  ".duo-rv-tip-note": { color: "var(--duo-text)", marginTop: "4px" },
  ".duo-rv-tip-row": { display: "flex", gap: "6px", marginTop: "6px" },
  ".duo-rv-btn": { font: "12px/16px -apple-system, sans-serif", padding: "4px 10px", border: "1px solid var(--duo-control-edge)", borderRadius: "6px", backgroundColor: "var(--duo-pane)", color: "var(--duo-text)", cursor: "default" },
});

// Always on: the parse, the switch and the signing of edits. Drawing is the live preview's (`reviewDrawing`).
export const reviewCore = [reviewField, markupField, reviewerField, suggestTyping, reviewTheme];
export const reviewDrawing = [decoField, labelHover];

export { reviewField, markupField, reviewerField, signatureName, today };

// The next free id of a kind (`c` threads, `s` suggestions) over every id the document uses.
export function nextId(doc, prefix) {
  let top = 0;
  const re = new RegExp("#" + prefix + "(\\d+)", "g"), t = doc.toString();
  for (let m; (m = re.exec(t));) top = Math.max(top, +m[1]);
  return prefix + (top + 1);
}
// The number after the highest `.n` any comment of a thread has.
export function nextReply(comments) {
  return 1 + Math.max(0, ...comments.map((c) => (c.id && c.id.includes(".") ? +c.id.split(".").pop() : 0)));
}
