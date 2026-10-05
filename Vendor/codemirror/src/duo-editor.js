// Duo's editor in one WKWebView (stack rec #8–9, spikes S4/S5). Markdown text is the only source
// of truth: the live preview hides syntax with decorations and never rewrites the text, so a
// save writes back exactly what was read plus the user's edits (LR-30).
import { EditorState, ChangeSet, StateField, StateEffect, RangeSetBuilder, Text, Compartment } from "@codemirror/state";
import { EditorView, ViewPlugin, Decoration, WidgetType, keymap } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { syntaxTree } from "@codemirror/language";
import { search, searchKeymap, SearchQuery, setSearchQuery, findNext, findPrevious, openSearchPanel, replaceNext } from "@codemirror/search";

// ---------- live preview ----------

class CheckboxWidget extends WidgetType {
  constructor(checked, from) { super(); this.checked = checked; this.from = from; }
  eq(o) { return o.checked === this.checked && o.from === this.from; }
  toDOM(view) {
    const box = document.createElement("input");
    box.type = "checkbox";
    box.checked = this.checked;
    box.className = "duo-task";
    box.addEventListener("mousedown", (e) => {
      e.preventDefault();
      // Toggle by editing the text: `[ ]` ↔ `[x]`. The text stays the truth.
      view.dispatch({ changes: { from: this.from + 1, to: this.from + 2, insert: this.checked ? " " : "x" } });
    });
    return box;
  }
  ignoreEvent() { return false; }
}

const hide = Decoration.replace({});
const headingMarks = [1, 2, 3, 4, 5, 6].map((l) => Decoration.mark({ class: `duo-h duo-h${l}` }));
const headingMark = (level) => headingMarks[level - 1];
const strong = Decoration.mark({ class: "duo-strong" });
const em = Decoration.mark({ class: "duo-em" });
const code = Decoration.mark({ class: "duo-code" });
const link = Decoration.mark({ class: "duo-link" });

function buildDecorations(view) {
  const { state } = view;
  // Lines with the caret or selection show raw markdown (Obsidian's live preview).
  const active = new Set();
  for (const r of state.selection.ranges) {
    const a = state.doc.lineAt(r.from).number, b = state.doc.lineAt(r.to).number;
    for (let n = a; n <= b; n++) active.add(n);
  }
  const ranges = [];
  // The frontmatter is the properties block's (above); the Markdown parser reads it as text.
  const fm = frontmatterLines(state.doc);
  const fmEnd = fm ? state.doc.line(fm[1]).to : -1;
  const ctx = state.field(contextField);
  for (const { from, to } of view.visibleRanges) {
    syntaxTree(state).iterate({
      from, to,
      enter: (node) => {
        if (node.from <= fmEnd) return node.to > fmEnd;
        const line = state.doc.lineAt(node.from).number;
        const raw = active.has(line);
        const name = node.name;
        const m = /^ATXHeading(\d)$/.exec(name);
        if (m) {
          ranges.push([node.from, node.to, headingMark(m[1])]);
        } else if (name === "HeaderMark" && !raw) {
          // `## ` → hide the hashes and the space after them.
          const end = Math.min(node.to + 1, state.doc.lineAt(node.from).to);
          ranges.push([node.from, end, hide]);
        } else if (name === "StrongEmphasis") {
          ranges.push([node.from, node.to, strong]);
        } else if (name === "Emphasis") {
          ranges.push([node.from, node.to, em]);
        } else if (name === "InlineCode") {
          ranges.push([node.from, node.to, code]);
        } else if (name === "EmphasisMark" || name === "CodeMark") {
          if (!raw && node.to - node.from <= 3 && state.doc.lineAt(node.from).number === state.doc.lineAt(node.to).number) {
            const parent = node.node.parent?.name;
            if (parent !== "FencedCode") ranges.push([node.from, node.to, hide]);
          }
        } else if (name === "Link") {
          ranges.push([node.from, node.to, link]);
          const url = linkAt(state, node.from + 1);
          // A session link shows its session's state glyph before its name (S2-5).
          if (!raw && url && SESSION_URL.test(url)) {
            ranges.push([node.from, node.from, Decoration.widget({ widget: new GlyphWidget(sessionInfo(ctx, url, "").state), side: -1 })]);
          }
          if (!raw) {
            // [text](url) → text: hide `[` and `](url)`.
            const text = state.doc.sliceString(node.from, node.to);
            const close = text.indexOf("](");
            if (text.startsWith("[") && close > 0) {
              ranges.push([node.from, node.from + 1, hide]);
              ranges.push([node.from + close, node.to, hide]);
            }
          }
          return false;
        } else if (name === "TaskMarker" && !raw) {
          const checked = /x/i.test(state.doc.sliceString(node.from, node.to));
          ranges.push([node.from, node.to, Decoration.replace({ widget: new CheckboxWidget(checked, node.from) })]);
        }
      },
    });
  }
  ranges.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  const builder = new RangeSetBuilder();
  let lastFrom = -1;
  for (const [f, t, d] of ranges) {
    if (f < lastFrom) continue;
    builder.add(f, t, d);
    lastFrom = f;
  }
  return builder.finish();
}

// Which lines show raw markdown: rebuild only when that set changes, not on every caret move.
const activeLines = (state) => state.selection.ranges.map((r) => `${state.doc.lineAt(r.from).number}-${state.doc.lineAt(r.to).number}`).join(",");
const livePreview = ViewPlugin.fromClass(class {
  constructor(view) { this.decorations = buildDecorations(view); this.lines = activeLines(view.state); }
  update(u) {
    const lines = u.selectionSet ? activeLines(u.state) : this.lines;
    const ctxChanged = u.startState.field(contextField) !== u.state.field(contextField);
    if (u.docChanged || u.viewportChanged || lines !== this.lines || ctxChanged) this.decorations = buildDecorations(u.view);
    this.lines = lines;
  }
}, { decorations: (v) => v.decorations });

// ---------- the properties block (DB-16 look; S2-5, DL-100) ----------

// The document's own frontmatter lines, decorated in place: the text stays the truth (LR-30).
// Built now: the heading, the ground block with muted names, a task note's status popup and its
// live session lines. Still to build from DB-16: type icons, suggestions, Tab between values,
// the type menu and the date picker (frontmatter-handoff §3–§4).
const STATE_GLYPHS = {
  needsYou: `<circle cx="5" cy="5" r="5" fill="var(--duo-needs-you)"/>`,
  readyForReview: `<path d="M5 0 10 5 5 10 0 5z" fill="var(--duo-text)"/>`,
  working: `<circle cx="5" cy="5" r="4.2" fill="none" stroke="var(--duo-text)" stroke-width="1.5"/>`,
  idle: `<path d="M1 5h8" fill="none" stroke="var(--duo-text2)" stroke-width="1.6" stroke-linecap="round"/>`,
  resolved: `<path d="M1.5 5.4 4 7.8 8.5 2.4" fill="none" stroke="var(--duo-text2)" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>`,
};
function glyphEl(state) {
  const span = document.createElement("span");
  span.className = "duo-glyph";
  span.innerHTML = `<svg width="9" height="9" viewBox="0 0 10 10" aria-hidden="true">${STATE_GLYPHS[state] || STATE_GLYPHS.idle}</svg>`;
  return span;
}
const SESSION_URL = /^duo2:\/\/session\/([0-9a-fA-F-]+)/;

// What Duo knows about the sessions a note links to: id → { state, name, wait }. Pushed from Swift.
const setContext = StateEffect.define();
const contextField = StateField.define({
  create: () => ({ task: false, sessions: {} }),
  update(v, tr) { for (const e of tr.effects) if (e.is(setContext)) v = { ...v, ...e.value }; return v; },
});

// The frontmatter's lines: [open fence line, close fence line], 1-based, or null.
function frontmatterLines(doc) {
  if (doc.lines < 2 || doc.line(1).text.trimEnd() !== "---") return null;
  for (let n = 2; n <= Math.min(doc.lines, 400); n++) {
    const t = doc.line(n).text.trimEnd();
    if (t === "---" || t === "...") return [1, n];
  }
  return null;
}

class HeadingWidget extends WidgetType {
  constructor(count) { super(); this.count = count; }
  eq(o) { return o.count === this.count; }
  toDOM(view) {
    const d = document.createElement("div");
    d.className = "duo-fm-head";
    d.innerHTML = `<span class="duo-fm-label">PROPERTIES · ${this.count}</span><span class="duo-fm-plus" role="button" aria-label="Add a property">+</span>`;
    d.querySelector(".duo-fm-plus").addEventListener("mousedown", (e) => { e.preventDefault(); addProperty(view); });
    return d;
  }
  ignoreEvent() { return true; }
}
class RuleWidget extends WidgetType {
  eq() { return true; }
  toDOM() { const d = document.createElement("div"); d.className = "duo-fm-rule"; return d; }
}
class StatusWidget extends WidgetType {
  constructor(value) { super(); this.value = value; }
  eq(o) { return o.value === this.value; }
  toDOM() {
    const s = document.createElement("span");
    s.className = "duo-fm-popup";
    s.setAttribute("role", "button");
    s.setAttribute("aria-label", `Status: ${this.value}. Change status.`);
    s.innerHTML = `${this.value.replace(/-/g, " ").replace(/[<&]/g, "")}<svg width="10" height="8" viewBox="0 0 10 8" aria-hidden="true"><path d="M1.5 2 5 6 8.5 2" fill="none" stroke="var(--duo-text2)" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
    s.addEventListener("mousedown", (e) => {
      e.preventDefault();
      const r = s.getBoundingClientRect();
      post("propertyMenu", { key: "status", value: this.value, x: r.left, y: r.bottom });
    });
    return s;
  }
  ignoreEvent() { return true; }
}
class AddWidget extends WidgetType {
  constructor(key) { super(); this.key = key; }
  eq(o) { return o.key === this.key; }
  toDOM() {
    const s = document.createElement("span");
    s.className = "duo-fm-add";
    s.textContent = "+ Add";
    s.setAttribute("role", "button");
    s.addEventListener("mousedown", (e) => {
      e.preventDefault();
      const r = s.getBoundingClientRect();
      post("propertyAdd", { key: this.key, x: r.left, y: r.bottom });
    });
    return s;
  }
  ignoreEvent() { return true; }
}
class SessionLineWidget extends WidgetType {
  constructor(url, name, state, wait) { super(); this.url = url; this.name = name; this.state = state; this.wait = wait; }
  eq(o) { return o.url === this.url && o.name === this.name && o.state === this.state && o.wait === this.wait; }
  toDOM() {
    const d = document.createElement("span");
    d.className = "duo-fm-session";
    d.appendChild(glyphEl(this.state));
    const n = document.createElement("span");
    n.className = "duo-fm-session-name";
    n.textContent = this.name;
    d.appendChild(n);
    const w = document.createElement("span");
    w.className = "duo-fm-wait";
    w.textContent = this.wait || "";
    d.appendChild(w);
    // Opens or resumes the session; the note stays open (DL-87).
    n.addEventListener("mousedown", (e) => { e.preventDefault(); post("openLink", { url: this.url }); });
    return d;
  }
  ignoreEvent(e) { return e.type === "mousedown" && e.target.closest?.(".duo-fm-session-name") != null; }
}
class GlyphWidget extends WidgetType {
  constructor(state) { super(); this.state = state; }
  eq(o) { return o.state === this.state; }
  toDOM() { const g = glyphEl(this.state); g.classList.add("duo-link-glyph"); return g; }
}

// A session's place in the list, as Duo shows it: its state and its wait (ready for review reads "ready").
function sessionInfo(ctx, url, fallback) {
  const id = SESSION_URL.exec(url)?.[1]?.toLowerCase();
  const s = id ? (ctx.sessions[id] ?? Object.entries(ctx.sessions).find(([k]) => k.startsWith(id) || id.startsWith(k))?.[1]) : null;
  return { name: s?.name || fallback, state: s?.state || "idle", wait: s ? (s.state === "readyForReview" ? "ready" : s.wait || "") : "" };
}

function propertiesDecorations(state) {
  const fm = frontmatterLines(state.doc);
  if (!fm) return Decoration.none;
  const doc = state.doc, ctx = state.field(contextField);
  const active = new Set();
  for (const r of state.selection.ranges) for (let n = doc.lineAt(r.from).number; n <= doc.lineAt(r.to).number; n++) active.add(n);
  const out = [];
  let count = 0, key = null;
  const isTask = ctx.task || Array.from({ length: fm[1] - 2 }, (_, i) => doc.line(i + 2).text).some((t) => /^type:\s*["']?task["']?\s*$/.test(t));
  for (let n = fm[0] + 1; n < fm[1]; n++) {
    const line = doc.line(n), t = line.text;
    const cls = ["duo-fm"];
    if (n === fm[0] + 1) cls.push("duo-fm-first");
    if (n === fm[1] - 1) cls.push("duo-fm-last");
    if (active.has(n)) cls.push("duo-fm-active");
    const km = /^([^\s#:-][^:#]*?):(?=\s|$)/.exec(t);
    const item = /^(\s*)-\s+(.*)$/.exec(t);
    if (km) {
      count++; key = km[1].trim();
      out.push(Decoration.line({ class: cls.join(" ") }).range(line.from));
      out.push(Decoration.mark({ class: "duo-fm-key" }).range(line.from, line.from + km[0].length));
      const vFrom = line.from + km[0].length + (/^\s*/.exec(t.slice(km[0].length))[0].length);
      const value = doc.sliceString(vFrom, line.to).trim().replace(/^["']|["']$/g, "");
      if (isTask && key === "status" && value) {
        out.push(Decoration.replace({ widget: new StatusWidget(value) }).range(vFrom, line.to));
      } else if (isTask && key === "sessions" && vFrom === line.to) {
        out.push(Decoration.widget({ widget: new AddWidget(key), side: 1 }).range(line.to));
      }
    } else if (item && key === "sessions" && !active.has(n)) {
      cls.push("duo-fm-item");
      out.push(Decoration.line({ class: cls.join(" ") }).range(line.from));
      const raw = item[2].trim().replace(/^["']|["']$/g, "");
      const lm = /^\[([^\]]*)\]\(([^)\s]+)\)$/.exec(raw);
      if (lm && SESSION_URL.test(lm[2])) {
        const info = sessionInfo(ctx, lm[2], lm[1]);
        out.push(Decoration.replace({ widget: new SessionLineWidget(lm[2], info.name, info.state, info.wait) }).range(line.from, line.to));
      }
    } else {
      if (item) cls.push("duo-fm-item");
      out.push(Decoration.line({ class: cls.join(" ") }).range(line.from));
    }
  }
  // The fences: the opening one becomes the heading, the closing one the rule under the block
  // (with the blank line after it, so the text starts where the target puts it).
  out.push(Decoration.replace({ widget: new HeadingWidget(count), block: true }).range(doc.line(fm[0]).from, doc.line(fm[0]).to));
  const close = doc.line(fm[1]);
  const next = fm[1] < doc.lines ? doc.line(fm[1] + 1) : null;
  const end = next && next.text.trim() === "" && fm[1] + 1 < doc.lines ? next.to : close.to;
  out.push(Decoration.replace({ widget: new RuleWidget(), block: true }).range(close.from, end));
  return Decoration.set(out, true);
}
const propertiesField = StateField.define({
  create: (state) => propertiesDecorations(state),
  update(deco, tr) {
    if (tr.docChanged || tr.selection || tr.effects.some((e) => e.is(setContext))) return propertiesDecorations(tr.state);
    return deco;
  },
  provide: (f) => [
    EditorView.decorations.from(f),
    // With a properties block the heading sits 14 from the top (frontmatter-handoff §2).
    EditorView.contentAttributes.compute([f], (state) => (frontmatterLines(state.doc) ? { class: "duo-has-fm" } : {})),
  ],
});

// The heading's +: a new empty line at the end of the block, ready for a name.
function addProperty(view) {
  const fm = frontmatterLines(view.state.doc);
  if (!fm) return;
  const at = view.state.doc.line(fm[1]).from;
  view.dispatch({ changes: { from: at, insert: "\n" }, selection: { anchor: at }, userEvent: "input" });
  view.focus();
}

// Sets one property's value in the buffer, or removes it (null), touching only that line (LR-37).
// A new property goes on the end, before the closing fence.
function setProperty(key, value) {
  const doc = view.state.doc, fm = frontmatterLines(doc);
  if (!fm) return false;
  for (let n = fm[0] + 1; n < fm[1]; n++) {
    const line = doc.line(n), m = new RegExp(`^${key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}:(\\s*)(.*)$`).exec(line.text);
    if (!m) continue;
    if (value == null) {
      view.dispatch({ changes: { from: line.from, to: Math.min(doc.length, line.to + 1) }, userEvent: "input" });
    } else {
      const from = line.from + key.length + 1;
      view.dispatch({ changes: { from, to: line.to, insert: " " + value }, userEvent: "input" });
    }
    return true;
  }
  if (value == null) return true;
  view.dispatch({ changes: { from: doc.line(fm[1]).from, insert: `${key}: ${value}\n` }, userEvent: "input" });
  return true;
}

// Adds an item to a list property, one per line, after its last item (DL-93).
function addListItem(key, item) {
  const doc = view.state.doc, fm = frontmatterLines(doc);
  if (!fm) return false;
  let at = -1;
  for (let n = fm[0] + 1; n < fm[1]; n++) {
    const t = doc.line(n).text;
    if (at < 0 && t.startsWith(key + ":")) { at = doc.line(n).to; continue; }
    if (at >= 0) { if (/^\s*-\s/.test(t)) at = doc.line(n).to; else break; }
  }
  if (at < 0) return setProperty(key, "") && addListItem(key, item);
  view.dispatch({ changes: { from: at, insert: `\n  - ${item}` }, userEvent: "input" });
  return true;
}

// ---------- "added by Claude" highlight (DL-5, LR-33) ----------

// Opened from search (search-open-file): the matched lines outlined in 1.5 text, labelled
// `L40–58 · from search`, matched words semibold. Separate from Claude's `selected` fill, so
// both can show at once. Cleared by the next edit.
const markSearch = StateEffect.define();
const searchField = StateField.define({
  create: () => Decoration.none,
  update(deco, tr) {
    for (const e of tr.effects) if (e.is(markSearch)) deco = e.value;
    return tr.docChanged ? Decoration.none : deco;
  },
  provide: (f) => EditorView.decorations.from(f),
});
function searchDecorations(state, a, b, label, words) {
  const doc = state.doc, out = [];
  const first = Math.min(Math.max(1, a), doc.lines), last = Math.min(Math.max(first, b), doc.lines);
  for (let n = first; n <= last; n++) {
    const cls = "duo-fs" + (n === first ? " duo-fs-first" : "") + (n === last ? " duo-fs-last" : "");
    out.push(Decoration.line({ class: cls, attributes: n === first ? { "data-label": label } : {} }).range(doc.line(n).from));
  }
  const from = doc.line(first).from, to = doc.line(last).to, text = doc.sliceString(from, to).toLowerCase();
  for (const w of words || []) {
    const lw = w.toLowerCase();
    if (!lw) continue;
    for (let i = text.indexOf(lw); i >= 0; i = text.indexOf(lw, i + lw.length)) out.push(strong.range(from + i, from + i + lw.length));
  }
  return Decoration.set(out, true);
}
const markAdded = StateEffect.define();
const clearAdded = StateEffect.define();
const addedField = StateField.define({
  create: () => Decoration.none,
  update(deco, tr) {
    deco = deco.map(tr.changes);
    for (const e of tr.effects) {
      if (e.is(markAdded)) deco = deco.update({ add: e.value.map(([f, t]) => Decoration.mark({ class: "duo-added" }).range(f, t)) });
      if (e.is(clearAdded)) deco = Decoration.none;
    }
    return deco;
  },
  provide: (f) => EditorView.decorations.from(f),
});

// Claude's changes, revertable while they're highlighted (ENH-4): where each landed in the
// current text (mapped through later edits) and the text it replaced. Same lifetime as the highlight.
const recordChanges = StateEffect.define();
const dropChange = StateEffect.define();
const changesField = StateField.define({
  create: () => [],
  update(list, tr) {
    list = list.map((c) => ({ ...c, from: tr.changes.mapPos(c.from, -1), to: tr.changes.mapPos(c.to, 1) }));
    for (const e of tr.effects) {
      if (e.is(recordChanges)) list = list.concat(e.value);
      if (e.is(dropChange)) list = list.filter((c) => !e.value.includes(c.id));
      if (e.is(clearAdded)) list = [];
    }
    return list;
  },
});
let changeSeq = 0;
// What a change set replaced, for each inserted or deleted range, so it can be put back.
function changeRecords(set, beforeDoc) {
  const out = [];
  set.iterChanges((fA, tA, fB, tB) => out.push({ id: ++changeSeq, from: fB, to: tB, removed: beforeDoc.sliceString(fA, tA) }));
  return out;
}
function changeAt(pos) {
  const list = view.state.field(changesField);
  return list.find((c) => pos >= c.from && pos <= c.to) ?? null;
}
// Puts back what one change (or all of them) replaced. Not a user edit, so other highlights stay.
function revert(ids) {
  const list = view.state.field(changesField).filter((c) => ids == null || ids.includes(c.id)).sort((a, b) => a.from - b.from);
  if (!list.length) return 0;
  const changes = list.map((c) => ({ from: c.from, to: c.to, insert: c.removed }));
  view.dispatch({ changes, effects: dropChange.of(list.map((c) => c.id)), userEvent: "revert" });
  return list.length;
}

// The highlight lasts until the user's next edit (DL-5, LR-33).
const clearOnUserEdit = EditorView.updateListener.of((u) => {
  if (!u.docChanged || u.state.field(addedField).size === 0) return;
  if (u.transactions.some((t) => t.isUserEvent("input") || t.isUserEvent("delete") || t.isUserEvent("move"))) {
    u.view.dispatch({ effects: clearAdded.of(null) });
  }
});

// ---------- text helpers ----------

// CodeMirror splits lines on \r\n, \r and \n and joins with the line separator. Keeping the
// file's own separator makes an unedited document round-trip byte for byte (mixed endings
// can't round-trip; Duo then opens the file read-only, LR-30).
function lineSeparatorOf(text) {
  const crlf = (text.match(/\r\n/g) || []).length;
  const lf = (text.match(/(^|[^\r])\n/g) || []).length;
  const cr = (text.match(/\r(?!\n)/g) || []).length;
  const kinds = [crlf > 0, lf > 0, cr > 0].filter(Boolean).length;
  return { sep: crlf ? "\r\n" : cr ? "\r" : "\n", mixed: kinds > 1 };
}

// The smallest single replacement turning a into b: common prefix and suffix.
function diffOne(a, b) {
  let s = 0;
  const max = Math.min(a.length, b.length);
  while (s < max && a.charCodeAt(s) === b.charCodeAt(s)) s++;
  let e = 0;
  while (e < max - s && a.charCodeAt(a.length - 1 - e) === b.charCodeAt(b.length - 1 - e)) e++;
  return { from: s, to: a.length - e, insert: b.slice(s, b.length - e) };
}

// ---------- the editor ----------

// Read-only when a file can't round-trip byte for byte (mixed line endings, LR-30).
const readOnlyCompartment = new Compartment();

// Duo's look (handoff §3.4: body 13/20, headings 14 semibold, padding 22 28, pane background).
// Colours and sizes come from Duo's tokens as CSS variables set by the app; nothing is hard-coded.
const duoTheme = EditorView.theme({
  "&": { height: "100%", backgroundColor: "var(--duo-pane)", color: "var(--duo-text)", fontSize: "13px" },
  "&.cm-focused": { outline: "none" },
  ".cm-scroller": { fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif", lineHeight: "20px" },
  ".cm-content": { padding: "22px 28px", caretColor: "var(--duo-text)" },
  ".cm-line": { padding: "0" },
  ".duo-h": { fontSize: "14px", fontWeight: "600" },
  ".duo-strong": { fontWeight: "600" },
  ".duo-em": { fontStyle: "italic" },
  ".duo-code": { fontFamily: "'SF Mono', ui-monospace, monospace", fontSize: "12px" },
  ".duo-link": { color: "var(--duo-text)", textDecoration: "underline", textDecorationColor: "var(--duo-control-edge)" },
  ".duo-fs": { boxShadow: "inset 1.5px 0 0 var(--duo-text), inset -1.5px 0 0 var(--duo-text)", paddingLeft: "12px", paddingRight: "12px", marginLeft: "-12px", marginRight: "-12px" },
  ".duo-fs-first": { boxShadow: "inset 1.5px 0 0 var(--duo-text), inset -1.5px 0 0 var(--duo-text), inset 0 1.5px 0 var(--duo-text)", borderTopLeftRadius: "6px", borderTopRightRadius: "6px", paddingTop: "8px", position: "relative" },
  ".duo-fs-last": { boxShadow: "inset 1.5px 0 0 var(--duo-text), inset -1.5px 0 0 var(--duo-text), inset 0 -1.5px 0 var(--duo-text)", borderBottomLeftRadius: "6px", borderBottomRightRadius: "6px", paddingBottom: "8px" },
  ".duo-fs-first.duo-fs-last": { boxShadow: "inset 0 0 0 1.5px var(--duo-text)" },
  ".duo-fs-first::after": { content: "attr(data-label)", position: "absolute", right: "12px", top: "8px", color: "var(--duo-text2)", fontFamily: "-apple-system, sans-serif", fontSize: "13px" },
  ".duo-added": { backgroundColor: "var(--duo-selected)", borderRadius: "var(--duo-radius-card)" },
  ".duo-task": { margin: "0 6px 0 0", verticalAlign: "-1px" },
  // The properties block (frontmatter-handoff §2, slice2 task-note): sizes from tokens size.propertiesBlock.
  "&.duo-has-fm .cm-content, .cm-content.duo-has-fm": { paddingTop: "14px" },
  ".duo-fm-head": { display: "flex", alignItems: "center", gap: "6px", margin: "0 -8px", paddingBottom: "6px", fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif", fontSize: "13px", lineHeight: "20px", color: "var(--duo-text2)" },
  ".duo-fm-label": { fontSize: "11px", lineHeight: "16px", fontWeight: "600", letterSpacing: "0.06em" },
  ".duo-fm-plus": { marginLeft: "auto", cursor: "default" },
  ".cm-line.duo-fm": { position: "relative", zIndex: "0", margin: "0 -12px", padding: "1.5px 12px 1.5px 32px", minHeight: "19px", backgroundColor: "var(--duo-ground)", fontFamily: "'SF Mono', ui-monospace, monospace", fontSize: "12px", lineHeight: "19px" },
  ".cm-line.duo-fm-first": { paddingTop: "9.5px", borderTopLeftRadius: "var(--duo-radius-card)", borderTopRightRadius: "var(--duo-radius-card)" },
  ".cm-line.duo-fm-last": { paddingBottom: "9.5px", borderBottomLeftRadius: "var(--duo-radius-card)", borderBottomRightRadius: "var(--duo-radius-card)" },
  ".cm-line.duo-fm-active::before": { content: "''", position: "absolute", left: "6px", right: "6px", top: "0", bottom: "0", backgroundColor: "var(--duo-pane)", borderRadius: "4px", zIndex: "-1" },
  ".cm-line.duo-fm-first.duo-fm-active::before": { top: "8px" },
  ".cm-line.duo-fm-last.duo-fm-active::before": { bottom: "8px" },
  ".duo-fm-key": { color: "var(--duo-text2)" },
  ".duo-fm-popup": { display: "inline-flex", alignItems: "center", gap: "4px", height: "20px", padding: "0 6px", border: "1px solid var(--duo-rule)", borderRadius: "var(--duo-radius-card)", fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif", fontSize: "13px", lineHeight: "20px", verticalAlign: "top", margin: "-1.5px 0", cursor: "default" },  // 22 tall in a 22 line
  ".duo-fm-add": { float: "right", fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif", fontSize: "12px", color: "var(--duo-text2)", cursor: "default" },
  ".cm-line.duo-fm-item": { paddingLeft: "32px" },
  ".duo-fm-session": { display: "inline-flex", alignItems: "center", gap: "6px", width: "100%", verticalAlign: "top" },
  ".duo-fm-session-name": { textDecoration: "underline", textDecorationColor: "var(--duo-control-edge)", textUnderlineOffset: "3px", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", cursor: "default" },
  ".duo-fm-wait": { marginLeft: "auto", flex: "none", fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif", fontSize: "12px", color: "var(--duo-text2)" },
  ".duo-glyph": { display: "inline-flex", width: "9px", height: "9px", flex: "none" },
  ".duo-link-glyph": { marginRight: "4px", verticalAlign: "-0.5px" },
  ".duo-fm-rule": { height: "1px", margin: "14px -28px 22px", backgroundColor: "var(--duo-rule)" },
  ".cm-searchMatch": { backgroundColor: "var(--duo-selected)" },
  // Find panel: a stub in Duo's tokens until it has a design (Q-20).
  ".cm-panels": { backgroundColor: "var(--duo-pane)", color: "var(--duo-text)", borderColor: "var(--duo-rule)" },
  ".cm-panels-top": { borderBottom: "1px solid var(--duo-rule)" },
  ".cm-search": { fontFamily: "-apple-system, sans-serif", fontSize: "12px", padding: "6px 28px" },
});

let view = null;
// The text last read from or written to disk, with "\n" line breaks: CodeMirror counts a line
// break as one position whatever the file uses, so diffs and positions are computed on this form.
let base = "";
let baseDoc = Text.empty;  // the same, as a document tree: dirty checks compare trees, no copies
const setBase = (t) => { base = t; baseDoc = Text.of(t.split("\n")); };
const canon = (t) => t.replace(/\r\n?/g, "\n");
// The document as the file should be written: CodeMirror's toString() always joins with "\n";
// sliceDoc() uses the file's own separator.
const fileText = () => view.state.sliceDoc();
let sepInfo = { sep: "\n", mixed: false };

function post(kind, body) {
  if (window.duoFlags?.noPost) return;
  try { window.webkit?.messageHandlers?.duo?.postMessage({ kind, ...body }); } catch (_) {}
}

// Chords Duo's menus own (Commands.swift); the editor must not consume them.
const DUO_CHORDS = new Set(["Mod-d", "Mod-i", "Mod-b", "Mod-s", "Mod-w", "Mod-n", "Shift-Mod-n", "Mod-k", "Shift-Mod-a", "Shift-Mod-p", "Shift-Mod-h", "Mod-Enter"]);

// Links (DL-87): a click on a rendered link (its line not showing raw markdown) opens it, as in
// Obsidian's live preview; ⌘-click opens it from anywhere. Duo decides what opening means
// (`duo2://session/<id>` resumes the session; web links go to the browser).
function linkAt(state, pos) {
  let node = syntaxTree(state).resolveInner(pos, 1);
  while (node && node.name !== "Link") node = node.parent;
  if (!node) return null;
  const url = node.getChild("URL");
  return url ? state.sliceDoc(url.from, url.to).trim() : null;
}
const linkClicks = EditorView.domEventHandlers({
  mousedown(e, view) {
    if (e.button !== 0 || !e.target.closest?.(".duo-link")) return false;
    const pos = view.posAtCoords({ x: e.clientX, y: e.clientY });
    if (pos == null) return false;
    const line = view.state.doc.lineAt(pos).number;
    const raw = view.state.selection.ranges.some((r) => line >= view.state.doc.lineAt(r.from).number && line <= view.state.doc.lineAt(r.to).number);
    if (raw && !e.metaKey) return false;
    const url = linkAt(view.state, pos);
    if (!url) return false;
    e.preventDefault();
    post("openLink", { url });
    return true;
  },
});

function create(parent, text) {
  sepInfo = lineSeparatorOf(text);
  setBase(canon(text));
  const state = EditorState.create({
    doc: text,
    extensions: [
      EditorState.lineSeparator.of(sepInfo.sep),
      readOnlyCompartment.of([EditorState.readOnly.of(sepInfo.mixed), EditorView.editable.of(!sepInfo.mixed)]),
      duoTheme,
      EditorView.lineWrapping,
      history(),
      markdown({ base: markdownLanguage }),  // GitHub-flavoured: task lists, tables, strikethrough
      search({ top: true }),
      ...(window.duoFlags?.noPreview ? [] : [livePreview]),
      contextField,
      ...(window.duoFlags?.noPreview ? [] : [propertiesField]),
      addedField,
      changesField,
      searchField,
      clearOnUserEdit,
      linkClicks,
      // Duo's menu chords win over CodeMirror's: ⌘D is Send Selection to Claude (DL-79), ⌘I is
      // Italic (CodeMirror's select-parent-syntax took it, so Format › Italic never fired).
      keymap.of([...defaultKeymap, ...historyKeymap, ...searchKeymap].filter((b) => !DUO_CHORDS.has(b.key))),
      EditorView.contentAttributes.of({ spellcheck: "true", autocorrect: "on", autocapitalize: "on" }),
      EditorView.updateListener.of((u) => {
        if (u.selectionSet || u.docChanged) {
          const r = u.state.selection.main;
          // Never stringify the document per keystroke: 1.2 MB × every edit was 280 MB of garbage (F-34).
          const claude = u.state.field(changesField);
          post("selection", { from: r.from, to: r.to, empty: r.empty, dirty: !u.state.doc.eq(baseDoc),
                              claudeChanges: claude.length, atClaudeChange: claude.some((c) => r.head >= c.from && r.head <= c.to) });
        }
      }),
    ],
  });
  if (view) view.destroy();
  view = new EditorView({ state, parent });
  // Duo's context for the note (its sessions' states) outlives the document: apply it again.
  if (window.__ctx) view.dispatch({ effects: setContext.of(window.__ctx) });
  return { mixedLineEndings: sepInfo.mixed, separator: JSON.stringify(sepInfo.sep) };
}

function wrap(marker) {
  const r = view.state.selection.main;
  const text = view.state.sliceDoc(r.from, r.to);
  view.dispatch({
    changes: { from: r.from, to: r.to, insert: marker + text + marker },
    selection: { anchor: r.from + marker.length, head: r.to + marker.length },
    userEvent: "input.format",  // a user edit: clears Claude's highlight (DL-5)
  });
}

const commands = {
  bold: () => wrap("**"),
  italic: () => wrap("*"),
  code: () => wrap("`"),
};

// Lines with their terminators, so joining the pieces gives the text back exactly.
const chunks = (t) => t.match(/[^\n]*\n|[^\n]+$/g) || [];

// Myers diff over two arrays of lines: the changed ranges, in order, as
// { aFrom, aTo, bFrom, bTo } (line indexes, end exclusive). A rewrite too big to diff cheaply
// comes back as one hunk.
function diffLines(a, b) {
  let s = 0;
  while (s < a.length && s < b.length && a[s] === b[s]) s++;
  let ea = a.length, eb = b.length;
  while (ea > s && eb > s && a[ea - 1] === b[eb - 1]) { ea--; eb--; }
  const N = ea - s, M = eb - s;
  if (N === 0 && M === 0) return [];
  if (N === 0 || M === 0) return [{ aFrom: s, aTo: ea, bFrom: s, bTo: eb }];
  const max = N + M, off = max + 1, limit = Math.min(max, 4000);
  const v = new Int32Array(2 * max + 3);
  const trace = [];
  let done = false;
  for (let d = 0; d <= limit && !done; d++) {
    trace.push(v.slice());
    for (let k = -d; k <= d; k += 2) {
      let x = (k === -d || (k !== d && v[off + k - 1] < v[off + k + 1])) ? v[off + k + 1] : v[off + k - 1] + 1;
      let y = x - k;
      while (x < N && y < M && a[s + x] === b[s + y]) { x++; y++; }
      v[off + k] = x;
      if (x >= N && y >= M) { done = true; break; }
    }
  }
  if (!done) return [{ aFrom: s, aTo: ea, bFrom: s, bTo: eb }];
  // Walk back to the matched lines, then the gaps between them are the hunks.
  const matches = [];
  let x = N, y = M;
  for (let d = trace.length - 1; d >= 0; d--) {
    const tv = trace[d], k = x - y;
    const prevK = (k === -d || (k !== d && tv[off + k - 1] < tv[off + k + 1])) ? k + 1 : k - 1;
    const prevX = d === 0 ? 0 : tv[off + prevK], prevY = d === 0 ? 0 : prevX - prevK;
    while (x > prevX && y > prevY) { x--; y--; matches.push([x, y]); }
    x = prevX; y = prevY;
  }
  matches.reverse();
  const hunks = [];
  let ai = 0, bi = 0;
  for (const [mx, my] of matches) {
    if (mx > ai || my > bi) hunks.push({ aFrom: s + ai, aTo: s + mx, bFrom: s + bi, bTo: s + my });
    ai = mx + 1; bi = my + 1;
  }
  if (ai < N || bi < M) hunks.push({ aFrom: s + ai, aTo: ea, bFrom: s + bi, bTo: eb });
  return hunks;
}

// Three-way merge by line (DL-77): base → theirs and base → mine are each a list of hunks;
// hunks that don't touch the same lines both apply; the same change on both sides applies once;
// anything else is a conflict and nothing is merged. Returns the merged lines and which output
// lines came from `theirs`.
function merge3(base, mine, theirs) {
  const hm = diffLines(base, mine).map((h) => ({ ...h, side: "mine", lines: mine.slice(h.bFrom, h.bTo) }));
  const ht = diffLines(base, theirs).map((h) => ({ ...h, side: "theirs", lines: theirs.slice(h.bFrom, h.bTo) }));
  const all = [...hm, ...ht].sort((p, q) => p.aFrom - q.aFrom || (p.aTo - p.aFrom) - (q.aTo - q.aFrom));
  const touches = (p, q) => (p.aFrom < q.aTo && q.aFrom < p.aTo) || (p.aFrom === q.aFrom && (p.aFrom === p.aTo || q.aFrom === q.aTo));
  const groups = [];
  for (const h of all) {
    const g = groups[groups.length - 1];
    if (g && g.some((o) => touches(o, h))) { g.push(h); } else { groups.push([h]); }
  }
  const out = [];
  const fromTheirs = [];
  let at = 0;
  const conflicts = [];
  for (const g of groups) {
    const from = Math.min(...g.map((h) => h.aFrom)), to = Math.max(...g.map((h) => h.aTo));
    for (; at < from; at++) out.push(base[at]);
    const sides = new Set(g.map((h) => h.side));
    let take;
    if (sides.size === 1) {
      take = g;
    } else {
      const text = (side) => g.filter((h) => h.side === side).map((h) => `${h.aFrom}:${h.aTo}:${h.lines.join("")}`).join("|");
      if (text("mine") !== text("theirs")) { conflicts.push([from, to]); take = g.filter((h) => h.side === "mine"); }
      else take = g.filter((h) => h.side === "mine");
    }
    // Rebuild base[from, to) with the chosen hunks applied.
    let pos = from;
    for (const h of take.sort((p, q) => p.aFrom - q.aFrom)) {
      for (; pos < h.aFrom; pos++) out.push(base[pos]);
      const start = out.length;
      out.push(...h.lines);
      if (h.side === "theirs" && h.lines.length) fromTheirs.push([start, out.length]);
      pos = Math.max(pos, h.aTo);
    }
    for (; pos < to; pos++) out.push(base[pos]);
    at = to;
  }
  for (; at < base.length; at++) out.push(base[at]);
  const theirsChanged = ht.reduce((n, h) => n + Math.max(h.aTo - h.aFrom, h.bTo - h.bFrom), 0);
  return { out, fromTheirs, conflicts, destructive: theirsChanged > base.length * 0.5 && base.length > 4 };
}

// External change (S5, DL-77): `disk` is the file's new text. Three-way by line: base → disk is
// the outside edit, base → buffer is the user's. Edits to different lines merge and carets map
// through; edits to the same lines are a conflict and nothing is applied.
function external(diskText) {
  const disk = canon(diskText);
  const buffer = view.state.doc.toString();
  if (disk === buffer) { setBase(disk); return { result: "same" }; }
  const userEdited = buffer !== base;
  const m = merge3(chunks(base), chunks(buffer), chunks(disk));
  if (m.conflicts.length) return { result: "conflict", lines: m.conflicts.map(([a, b]) => [a + 1, b]) };
  // Turn buffer → merged into small character changes, line hunk by line hunk.
  const mine = chunks(buffer), merged = m.out;
  const startOf = (lines) => { const r = [0]; for (const l of lines) r.push(r[r.length - 1] + l.length); return r; };
  const ms = startOf(mine), os = startOf(merged);
  const changes = [];
  for (const h of diffLines(mine, merged)) {
    const oldText = mine.slice(h.aFrom, h.aTo).join(""), newText = merged.slice(h.bFrom, h.bTo).join("");
    const d = diffOne(oldText, newText);
    changes.push({ from: ms[h.aFrom] + d.from, to: ms[h.aFrom] + d.to, insert: d.insert });
  }
  const set = ChangeSet.of(changes, buffer.length);
  // What arrived from outside (in Duo, usually Claude) is highlighted until the next edit (LR-33).
  const added = [];
  set.iterChanges((fromA, toA, fromB, toB) => { if (toB > fromB) added.push([fromB, toB]); });
  const records = changeRecords(set, view.state.doc);
  view.dispatch({ changes: set, effects: [recordChanges.of(records), ...(added.length ? [markAdded.of(added)] : [])], userEvent: "external" });
  setBase(disk);
  return { result: userEdited ? "merged" : "applied", added: added.length, destructive: m.destructive };
}

// Claude's Edit / MultiEdit / Write, applied to the buffer instead of the file (DL-78): each
// edit is checked against the text the user sees, with the Edit tool's rules (old text must be
// there, once unless replace_all), then the whole change lands as small, highlighted changes.
function agentEdit(edits, content) {
  const before = view.state.doc.toString();
  let text = before;
  if (content != null) {
    text = canon(content);
  } else {
    for (const e of edits) {
      const old = canon(e.old_string ?? ""), rep = canon(e.new_string ?? "");
      if (!old) return { result: "error", reason: "old_string is empty" };
      const at = text.indexOf(old);
      if (at < 0) return { result: "error", reason: "old_string isn't in the document as the user has it" };
      if (!e.replace_all && text.indexOf(old, at + 1) >= 0) return { result: "error", reason: "old_string appears more than once; add context or use replace_all" };
      text = e.replace_all ? text.split(old).join(rep) : text.slice(0, at) + rep + text.slice(at + old.length);
    }
  }
  if (text === before) return { result: "unchanged" };
  const a = chunks(before), b = chunks(text);
  const starts = [0]; for (const l of a) starts.push(starts[starts.length - 1] + l.length);
  const changes = diffLines(a, b).map((h) => {
    const d = diffOne(a.slice(h.aFrom, h.aTo).join(""), b.slice(h.bFrom, h.bTo).join(""));
    return { from: starts[h.aFrom] + d.from, to: starts[h.aFrom] + d.to, insert: d.insert };
  });
  const set = ChangeSet.of(changes, before.length);
  const added = [];
  set.iterChanges((fA, tA, fB, tB) => { if (tB > fB) added.push([fB, tB]); });
  const records = changeRecords(set, view.state.doc);
  view.dispatch({ changes: set, effects: [recordChanges.of(records), ...(added.length ? [markAdded.of(added)] : [])], userEvent: "agent" });
  const first = added.length ? view.state.doc.lineAt(added[0][0]).number : null;
  if (added.length) view.dispatch({ effects: EditorView.scrollIntoView(added[0][0], { y: "center" }) });
  return { result: "applied", changes: changes.length, line: first };
}

// Agent edits go through the buffer (LR-34) and are highlighted until accepted (DL-5).
function agentInsert(at, text) {
  view.dispatch({ changes: { from: at, insert: text }, effects: [markAdded.of([[at, at + text.length]]), recordChanges.of([{ id: ++changeSeq, from: at, to: at + text.length, removed: "" }])] });
}

// Human-paced typing: one character every `gap` ms, so the engine has idle time as it would
// with a person typing. Resolves when done.
function typeSlowly(n, gap) {
  return new Promise((resolve) => {
    let i = 0;
    const tick = () => {
      const at = view.state.selection.main.head;
      view.dispatch({ changes: { from: at, insert: "x" }, selection: { anchor: at + 1 } });
      if (++i < n) setTimeout(tick, gap); else resolve(i);
    };
    tick();
  });
}

// Typing latency: dispatch n single-character inserts at the caret, measuring dispatch plus the
// synchronous DOM update CM does. A proxy for keystroke latency (no input pipeline).
function bench(n) {
  const times = [];
  for (let i = 0; i < n; i++) {
    const at = view.state.selection.main.head;
    const t0 = performance.now();
    view.dispatch({ changes: { from: at, insert: "x" }, selection: { anchor: at + 1 } });
    if (!window.duoFlags?.noLayout) view.coordsAtPos(at + 1); // forces layout
    times.push(performance.now() - t0);
  }
  times.sort((a, b) => a - b);
  return { p50: times[Math.floor(n * 0.5)], p95: times[Math.floor(n * 0.95)], max: times[n - 1] };
}

window.duo = {
  // The note's context from Duo: { task, sessions: { id: { state, name, wait } } } (S2-5).
  setContext: (c) => { view.dispatch({ effects: setContext.of(c) }); return true; },
  setProperty,
  addListItem,
  properties: () => { const fm = frontmatterLines(view.state.doc); return fm ? document.querySelectorAll(".duo-fm").length : 0; },
  setReadOnly: (ro) => view.dispatch({ effects: readOnlyCompartment.reconfigure([EditorState.readOnly.of(ro), EditorView.editable.of(!ro)]) }),
  focus: () => view.focus(),
  create: (text) => create(document.getElementById("editor"), text),
  text: fileText,
  markSaved: () => setBase(view.state.doc.toString()),
  exec: (name) => { commands[name]?.(); return view.state.doc.length; },
  select: (from, to) => view.dispatch({ selection: { anchor: from, head: to ?? from } }),
  caret: () => view.state.selection.main.head,
  // The selected text and its lines (1-based), for Send to Claude; null when nothing is selected.
  selection: () => {
    const { from, to } = view.state.selection.main;
    if (from === to) return null;
    const doc = view.state.doc;
    return { text: view.state.sliceDoc(from, to), fromLine: doc.lineAt(from).number, toLine: doc.lineAt(Math.max(from, to - 1)).number };
  },
  external,
  merge3: (b, m, t) => merge3(chunks(b), chunks(m), chunks(t)),
  setBaseText: (t) => setBase(canon(t)),
  agentInsert,
  agentEdit,
  // Checks only: a person's typing (not highlighted, makes the buffer dirty).
  userReplace: (find, text) => {
    const doc = view.state.doc.toString(), at = doc.indexOf(find);
    if (at < 0) return false;
    view.dispatch({ changes: { from: at, to: at + find.length, insert: text }, userEvent: "input.type" });
    return true;
  },
  // duo2 doc insert / doc replace / doc select (DL-71): agent edits go through the buffer and are
  // highlighted as added by Claude (LR-34, DL-5).
  agentInsertAtLine: (line, text) => {
    const doc = view.state.doc;
    const at = line == null ? view.state.selection.main.head : (line > doc.lines ? doc.length : doc.line(Math.max(1, line)).from);
    agentInsert(at, text);
    return at;
  },
  agentReplace: (find, text) => {
    const doc = view.state.doc.toString();
    const at = doc.indexOf(find);
    if (at < 0) return { result: "not found" };
    if (doc.indexOf(find, at + 1) >= 0) return { result: "not unique" };
    view.dispatch({ changes: { from: at, to: at + find.length, insert: text },
                    effects: [markAdded.of([[at, at + text.length]]), recordChanges.of([{ id: ++changeSeq, from: at, to: at + text.length, removed: find }])] });
    return { result: "replaced", line: view.state.doc.lineAt(at).number };
  },
  // ENH-4: revert Claude's change at the caret (or at `pos`), or all of them.
  revertAt: (pos) => { const c = changeAt(pos ?? view.state.selection.main.head); return c ? revert([c.id]) : 0; },
  revertAll: () => revert(null),
  revertAtLine: (n) => {
    const l = view.state.doc.line(Math.min(Math.max(1, n), view.state.doc.lines));
    const c = view.state.field(changesField).find((c) => c.to >= l.from && c.from <= l.to);
    return c ? revert([c.id]) : 0;
  },
  claudeChanges: () => view.state.field(changesField).map((c) => ({ from: view.state.doc.lineAt(c.from).number, to: view.state.doc.lineAt(Math.max(c.from, c.to)).number, removed: c.removed.length, inserted: c.to - c.from })),
  revealFromSearch: (a, b, label, words) => {
    view.dispatch({ effects: markSearch.of(searchDecorations(view.state, a, b, label, words)),
                    selection: { anchor: view.state.doc.line(Math.min(Math.max(1, a), view.state.doc.lines)).from },
                    scrollIntoView: true });
    view.dispatch({ effects: EditorView.scrollIntoView(view.state.doc.line(Math.min(Math.max(1, a), view.state.doc.lines)).from, { y: "center" }) });
    return true;
  },
  selectLines: (a, b) => {
    const doc = view.state.doc;
    const from = doc.line(Math.min(Math.max(1, a), doc.lines)).from, to = doc.line(Math.min(Math.max(1, b ?? a), doc.lines)).to;
    view.dispatch({ selection: { anchor: from, head: to }, scrollIntoView: true });
    return to - from;
  },
  addedCount: () => view.state.field(addedField).size,
  find: (q) => { setSearchQuery.of(new SearchQuery({ search: q })); view.dispatch({ effects: setSearchQuery.of(new SearchQuery({ search: q })) }); findNext(view); return view.state.selection.main.from; },
  bench,
  typeSlowly,
  // The Edit > Find menu items (performTextFinderAction:) arrive here: CodeMirror only renders
  // the visible lines, so a browser-level find would miss the rest of a long document.
  findAction: (tag) => {
    if (tag === 1 || tag === 12) { openSearchPanel(view); return true; }   // show find / find-and-replace
    if (tag === 2) return findNext(view);
    if (tag === 3) return findPrevious(view);
    return false;
  },
  typeOne: (at) => view.dispatch({ changes: { from: at, insert: "x" }, selection: { anchor: at + 1 } }),
  hiddenCount: () => document.querySelectorAll(".cm-line").length,
};
post("ready", {});
