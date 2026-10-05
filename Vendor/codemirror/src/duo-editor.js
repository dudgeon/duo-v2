// Duo's editor in one WKWebView (stack rec #8–9, spikes S4/S5). Markdown text is the only source
// of truth: the live preview hides syntax with decorations and never rewrites the text, so a
// save writes back exactly what was read plus the user's edits (LR-30).
import { EditorState, ChangeSet, StateField, StateEffect, RangeSetBuilder, Text, Compartment, Prec } from "@codemirror/state";
import { EditorView, ViewPlugin, Decoration, WidgetType, keymap } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { syntaxTree } from "@codemirror/language";
import { autocompletion, startCompletion, completionStatus, acceptCompletion } from "@codemirror/autocomplete";
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

// ---------- the properties block (DB-16, frontmatter-handoff; S2-5, DL-100) ----------

// The document's own frontmatter lines, decorated in place: the text stays the truth (LR-30), and
// undo is the document's undo. Nothing here rewrites a line the user didn't act on (LR-37).
// A task note keeps its own approved look (slice2 task-note.html): fences hidden, no icons, a status
// popup and live session lines. Every other document follows frontmatter.html: fences in text2, a
// type icon in the gutter, the value's control after it, a fold chevron.
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

// What Duo knows: the sessions a note links to (id → { state, name, wait }) and, for suggestions,
// the property names and values used across the project (names: [{ name, type, count }], values:
// { name: [{ value, count }] }). Pushed from Swift.
const setContext = StateEffect.define();
const contextField = StateField.define({
  create: () => ({ task: false, sessions: {}, names: [], values: {} }),
  update(v, tr) { for (const e of tr.effects) if (e.is(setContext)) v = { ...v, ...e.value }; return v; },
});

// Folded or not, remembered per document by Duo (frontmatter-handoff §2).
const setFolded = StateEffect.define();
const foldField = StateField.define({
  create: () => !!window.__folded,
  update(v, tr) { for (const e of tr.effects) if (e.is(setFolded)) v = e.value; return v; },
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

const KEY_RE = /^([^\s#:\-][^:#]*?):(?=\s|$)/;
const ITEM_RE = /^(\s*)-(\s+|$)(.*)$/;
const MD_LINK = /^["']?\[([^\]]*)\]\(([^)\s]+)\)["']?$/;
// The type, read from how the value is written: nothing is stored outside the file (DL-20).
function valueType(key, value, hasItems) {
  const v = value.trim();
  if (hasItems || /^(aliases|tags|cssclasses)$/.test(key) || /^\[.*\]$/.test(v)) return "list";
  if (/^(true|false)$/i.test(v)) return "checkbox";
  if (/^-?\d+(\.\d+)?$/.test(v)) return "number";
  if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(v)) return "datetime";
  if (/^\d{4}-\d{2}-\d{2}$/.test(v)) return "date";
  if (MD_LINK.test(v) || /^["']?https?:\/\/\S+["']?$/.test(v)) return "link";
  return "text";
}

// One pass over the frontmatter: each line's kind, key, value range and type, the count of
// properties, and the first line that isn't valid YAML (with why), if any.
function parseFrontmatter(doc, typingLine = -1) {
  const fm = frontmatterLines(doc);
  if (!fm) return null;
  const lines = [];
  let count = 0, key = null, invalid = null, why = "";
  for (let n = fm[0] + 1; n < fm[1]; n++) {
    const line = doc.line(n), t = line.text;
    const km = KEY_RE.exec(t), im = ITEM_RE.exec(t);
    const L = { n, from: line.from, to: line.to, text: t, kind: "other" };
    if (km) {
      count++; key = km[1].trim();
      const lead = km[0].length + /^\s*/.exec(t.slice(km[0].length))[0].length;
      Object.assign(L, { kind: "key", key, keyEnd: line.from + km[0].length, vFrom: line.from + lead, vTo: line.to, value: t.slice(lead).trimEnd() });
      const v = L.value;
      if (!invalid && /^"/.test(v) && !/[^\\]"$|^""$/.test(v.length > 1 ? v : "")) { invalid = n; why = `Line ${n} has a quote that never closes.`; }
      else if (!invalid && /^'/.test(v) && !/'$/.test(v.slice(1))) { invalid = n; why = `Line ${n} has a quote that never closes.`; }
      else if (!invalid && /^\[/.test(v) && !/\]$/.test(v)) { invalid = n; why = `Line ${n} has a list that never closes.`; }
    } else if (im) {
      Object.assign(L, { kind: "item", key, vFrom: line.from + im[1].length + 1 + im[2].length, vTo: line.to, value: im[3].trimEnd() });
    } else if (/^\s*(#.*)?$/.test(t)) {
      L.kind = "blank";
    } else if (/^\s+\S/.test(t)) {
      L.kind = "cont";
    } else if (n === typingLine && /^[^\s#:\-][^:#]*$/.test(t)) {
      L.kind = "pending";  // a name being typed on the caret's line: not an error yet
    } else if (!invalid) {
      invalid = n; why = `Line ${n} isn’t a property: a name, a colon, then its value.`;
    }
    lines.push(L);
  }
  for (const L of lines) if (L.kind === "key") L.type = valueType(L.key, L.value, L.value === "" && lines.some((o) => o.kind === "item" && o.key === L.key));
  const isTask = lines.some((L) => L.kind === "key" && L.key === "type" && /^["']?task["']?$/.test(L.value));
  return { fm, lines, count, invalid, why, isTask };
}

const PROP_ICONS = {
  text: `<path d="M2 3h8M2 6h8M2 9h5"/>`,
  list: `<path d="M4.5 3H10M4.5 6H10M4.5 9H10"/><path d="M2 3h.01M2 6h.01M2 9h.01" stroke-width="1.7"/>`,
  number: `<path d="M4.7 1.5 3.7 10.5M8.3 1.5 7.3 10.5M2 4.5h8.5M1.5 7.5H10"/>`,
  checkbox: `<rect x="1.8" y="1.8" width="8.4" height="8.4" rx="2"/><path d="M4 6.2 5.4 7.6 8 4.6"/>`,
  date: `<rect x="1.5" y="2.5" width="9" height="8" rx="1.5"/><path d="M1.5 5h9M4 1.2v2.2M8 1.2v2.2"/>`,
  datetime: `<circle cx="6" cy="6" r="4.5"/><path d="M6 3.5V6l1.8 1.2"/>`,
  link: `<path d="M5 7 7 5"/><path d="M5.6 3.6 6.5 2.7a2 2 0 0 1 2.8 2.8l-.9.9M6.4 8.4l-.9.9a2 2 0 0 1-2.8-2.8l.9-.9"/>`,
  open: `<path d="M4.5 2.5H9.5V7.5M9.5 2.5 3 9"/>`,
};
const TYPE_NAMES = { text: "Text", list: "List", number: "Number", checkbox: "Checkbox", date: "Date", datetime: "Date and time", link: "Link" };
const iconSvg = (k) => `<svg width="12" height="12" viewBox="0 0 12 12" aria-hidden="true" fill="none" stroke="var(--duo-text2)" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round">${PROP_ICONS[k]}</svg>`;
const chevronSvg = (down) => down
  ? `<svg width="10" height="8" viewBox="0 0 10 8" aria-hidden="true"><path d="M1.5 2 5 6 8.5 2" fill="none" stroke="var(--duo-text2)" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>`
  : `<svg width="8" height="10" viewBox="0 0 8 10" aria-hidden="true"><path d="M2 1.5 6 5 2 8.5" fill="none" stroke="var(--duo-text2)" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
const where = (el) => { const r = el.getBoundingClientRect(); return { x: r.left, y: r.bottom }; };

// The heading: a fold chevron (not on a task note), PROPERTIES · n, then + (or, when the YAML
// doesn't read, "Not valid YAML · line n" in its place).
class HeadingWidget extends WidgetType {
  constructor(count, chevron, folded, invalid, rule) { super(); Object.assign(this, { count, chevron, folded, invalid, rule }); }
  eq(o) { return o.count === this.count && o.chevron === this.chevron && o.folded === this.folded && o.invalid === this.invalid && o.rule === this.rule; }
  toDOM(view) {
    const box = document.createElement("div");
    const d = document.createElement("div");
    d.className = this.chevron ? "duo-fm-head duo-fm-head-chev" : "duo-fm-head";  // with a chevron the row is 16 high (frontmatter.html), else 20 (task-note.html)
    const label = this.invalid ? "PROPERTIES" : `PROPERTIES · ${this.count}`;
    d.innerHTML = (this.chevron ? `<span class="duo-fm-chev" role="button" aria-label="${this.folded ? "Show" : "Hide"} properties">${chevronSvg(!this.folded)}</span>` : "")
      + `<span class="duo-fm-label">${label}</span>`
      + (this.invalid ? `<span class="duo-fm-invalid-note">Not valid YAML · line ${this.invalid}</span>`
                      : `<span class="duo-fm-plus" role="button" aria-label="Add a property">+</span>`);
    d.querySelector(".duo-fm-plus")?.addEventListener("mousedown", (e) => { e.preventDefault(); addProperty(view); });
    d.querySelector(".duo-fm-chev")?.addEventListener("mousedown", (e) => {
      e.preventDefault();
      const folded = !view.state.field(foldField);
      view.dispatch({ effects: setFolded.of(folded) });
      post("propertiesFolded", { folded });
    });
    box.appendChild(d);
    if (this.rule) { const r = document.createElement("div"); r.className = "duo-fm-rule duo-fm-rule-folded"; box.appendChild(r); }
    return box;
  }
  ignoreEvent() { return true; }
}
class RuleWidget extends WidgetType {
  constructor(message) { super(); this.message = message || ""; }
  eq(o) { return o.message === this.message; }
  toDOM() {
    const box = document.createElement("div");
    if (this.message) { const m = document.createElement("div"); m.className = "duo-fm-message"; m.textContent = this.message; box.appendChild(m); }
    const r = document.createElement("div"); r.className = "duo-fm-rule"; box.appendChild(r);
    return box;
  }
}
// The type icon in the gutter; a button that opens the type menu (§3).
class IconWidget extends WidgetType {
  constructor(type, line, key) { super(); Object.assign(this, { type, line, key }); }
  eq(o) { return o.type === this.type && o.line === this.line && o.key === this.key; }
  toDOM() {
    const s = document.createElement("span");
    s.className = "duo-fm-icon";
    s.setAttribute("role", "button");
    s.setAttribute("aria-label", `Type: ${TYPE_NAMES[this.type].toLowerCase()}. Change type.`);
    s.innerHTML = iconSvg(this.type);
    s.addEventListener("mousedown", (e) => { e.preventDefault(); post("propertyType", { line: this.line, key: this.key, type: this.type, ...where(s) }); });
    return s;
  }
  ignoreEvent() { return true; }
}
// A checkbox before true/false: clicking rewrites the word.
class BoolWidget extends WidgetType {
  constructor(on, from, to) { super(); Object.assign(this, { on, from, to }); }
  eq(o) { return o.on === this.on && o.from === this.from && o.to === this.to; }
  toDOM(view) {
    const box = document.createElement("input");
    box.type = "checkbox"; box.checked = this.on; box.className = "duo-fm-check";
    box.addEventListener("mousedown", (e) => {
      e.preventDefault();
      view.dispatch({ changes: { from: this.from, to: this.to, insert: this.on ? "false" : "true" }, userEvent: "input.toggle" });
    });
    return box;
  }
  ignoreEvent() { return false; }
}
// A small button after the value: the calendar for dates, open for links.
class ControlWidget extends WidgetType {
  constructor(kind, payload) { super(); this.kind = kind; this.payload = payload; }
  eq(o) { return o.kind === this.kind && JSON.stringify(o.payload) === JSON.stringify(this.payload); }
  toDOM() {
    const s = document.createElement("span");
    s.className = "duo-fm-control";
    s.setAttribute("role", "button");
    s.setAttribute("aria-label", this.kind === "open" ? `Open ${this.payload.title || "the link"}` : "Pick a date");
    s.innerHTML = iconSvg(this.kind === "open" ? "open" : this.payload.time ? "datetime" : "date");
    s.addEventListener("mousedown", (e) => {
      e.preventDefault();
      if (this.kind === "open") post("openLink", { url: this.payload.url });
      else post("propertyDate", { ...this.payload, ...where(s) });
    });
    return s;
  }
  ignoreEvent() { return true; }
}
// A link away from the caret: its title, underlined (§3).
class LinkTitleWidget extends WidgetType {
  constructor(title) { super(); this.title = title; }
  eq(o) { return o.title === this.title; }
  toDOM() { const s = document.createElement("span"); s.className = "duo-fm-link"; s.textContent = this.title; return s; }
}
class ClaudeLabelWidget extends WidgetType {
  eq() { return true; }
  toDOM() { const s = document.createElement("span"); s.className = "duo-fm-claude-label"; s.textContent = "changed by Claude"; return s; }
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

const caretLine = (state) => state.doc.lineAt(state.selection.main.head).number;
function propertiesDecorations(state) {
  const p = parseFrontmatter(state.doc, caretLine(state));
  if (!p) return Decoration.none;
  const doc = state.doc, ctx = state.field(contextField), task = ctx.task || p.isTask;
  const folded = !task && state.field(foldField);
  const active = new Set();
  for (const r of state.selection.ranges) for (let n = doc.lineAt(r.from).number; n <= doc.lineAt(r.to).number; n++) active.add(n);
  const claude = new Set();
  state.field(addedField).between(doc.line(p.fm[0]).from, doc.line(p.fm[1]).to, (f, t) => {
    for (let n = doc.lineAt(f).number; n <= doc.lineAt(Math.max(f, t - 1)).number; n++) claude.add(n);
  });
  const out = [];
  const open = doc.line(p.fm[0]), close = doc.line(p.fm[1]);
  const next = p.fm[1] < doc.lines ? doc.line(p.fm[1] + 1) : null;
  const blankAfter = next && next.text.trim() === "" && p.fm[1] + 1 < doc.lines;
  if (folded) {
    // The heading alone, chevron pointing right, and the rule 6 under it.
    out.push(Decoration.replace({ widget: new HeadingWidget(p.count, true, true, p.invalid, true), block: true }).range(open.from, blankAfter ? next.to : close.to));
    return Decoration.set(out, true);
  }
  for (const L of p.lines) {
    const cls = ["duo-fm"];
    if (task && L === p.lines[0]) cls.push("duo-fm-first");
    if (task && L === p.lines[p.lines.length - 1]) cls.push("duo-fm-last");
    if (active.has(L.n)) cls.push("duo-fm-active");
    else if (claude.has(L.n)) cls.push("duo-fm-claude");
    if (p.invalid === L.n) cls.push("duo-fm-error");
    const broken = p.invalid != null && L.n >= p.invalid;  // from the error on: no icons or controls
    if (L.kind === "item") cls.push("duo-fm-item");
    if (L.kind === "item" && L.key === "sessions" && task && !active.has(L.n)) {
      const lm = MD_LINK.exec(L.value.trim());
      out.push(Decoration.line({ class: cls.join(" ") }).range(L.from));
      if (lm && SESSION_URL.test(lm[2])) {
        const info = sessionInfo(ctx, lm[2], lm[1]);
        out.push(Decoration.replace({ widget: new SessionLineWidget(lm[2], info.name, info.state, info.wait) }).range(L.from, L.to));
      }
      continue;
    }
    out.push(Decoration.line({ class: cls.join(" ") }).range(L.from));
    if (L.kind !== "key") continue;
    out.push(Decoration.mark({ class: "duo-fm-key" }).range(L.from, L.keyEnd));
    if (claude.has(L.n) && !active.has(L.n)) out.push(Decoration.widget({ widget: new ClaudeLabelWidget(), side: 2 }).range(L.to));
    if (task) {
      if (L.key === "status" && L.value) out.push(Decoration.replace({ widget: new StatusWidget(L.value.replace(/^["']|["']$/g, "")) }).range(L.vFrom, L.vTo));
      else if (L.key === "sessions" && L.value === "") out.push(Decoration.widget({ widget: new AddWidget(L.key), side: 1 }).range(L.to));
      continue;
    }
    if (broken) continue;
    out.push(Decoration.widget({ widget: new IconWidget(L.type, L.n, L.key), side: -1 }).range(L.from));
    const v = L.value.trim();
    if (L.type === "checkbox") {
      out.push(Decoration.widget({ widget: new BoolWidget(/^true$/i.test(v), L.vFrom, L.vFrom + v.length), side: -1 }).range(L.vFrom));
    } else if (L.type === "date" || L.type === "datetime") {
      out.push(Decoration.widget({ widget: new ControlWidget("date", { line: L.n, key: L.key, value: v, time: L.type === "datetime" }), side: 1 }).range(L.to));
    } else if (L.type === "link") {
      const lm = MD_LINK.exec(v), url = lm ? lm[2] : v.replace(/^["']|["']$/g, ""), title = lm ? lm[1] : url;
      if (!active.has(L.n)) out.push(Decoration.replace({ widget: new LinkTitleWidget(title) }).range(L.vFrom, L.vFrom + v.length));
      out.push(Decoration.widget({ widget: new ControlWidget("open", { url, title }), side: 1 }).range(L.to));
    }
  }
  if (task) {
    // The approved task-note look: the fences give way to the heading and the rule.
    out.push(Decoration.replace({ widget: new HeadingWidget(p.count, false, false, p.invalid, false), block: true }).range(open.from, open.to));
    out.push(Decoration.replace({ widget: new RuleWidget(p.invalid ? p.why : ""), block: true }).range(close.from, blankAfter ? next.to : close.to));
  } else {
    out.push(Decoration.widget({ widget: new HeadingWidget(p.count, true, false, p.invalid, false), block: true, side: -1 }).range(open.from));
    for (const f of [open, close]) {
      out.push(Decoration.line({ class: `duo-fm duo-fm-fence ${f === open ? "duo-fm-first" : "duo-fm-last"}${active.has(f.number) ? " duo-fm-active" : ""}` }).range(f.from));
      out.push(Decoration.mark({ class: "duo-fm-key" }).range(f.from, f.to));
    }
    if (blankAfter) out.push(Decoration.replace({ widget: new RuleWidget(p.invalid ? p.why + " Keep typing: it is saved as it is, and the icons and suggestions come back once it reads correctly." : ""), block: true }).range(next.from, next.to));
    else out.push(Decoration.widget({ widget: new RuleWidget(p.invalid ? p.why + " Keep typing: it is saved as it is, and the icons and suggestions come back once it reads correctly." : ""), block: true, side: 1 }).range(close.to));
  }
  return Decoration.set(out, true);
}
const propertiesField = StateField.define({
  create: (state) => propertiesDecorations(state),
  update(deco, tr) {
    if (tr.docChanged || tr.selection || tr.effects.some((e) => e.is(setContext) || e.is(setFolded) || e.is(markAdded) || e.is(clearAdded))) return propertiesDecorations(tr.state);
    return deco;
  },
  provide: (f) => [
    EditorView.decorations.from(f),
    // With a properties block the heading sits 14 from the top (frontmatter-handoff §2).
    EditorView.contentAttributes.compute([f], (state) => (frontmatterLines(state.doc) ? { class: "duo-has-fm" } : {})),
  ],
});

// The heading's +: a new empty line at the end of the block, ready for a name, with suggestions.
function addProperty(view) {
  const fm = frontmatterLines(view.state.doc);
  if (!fm) return;
  if (view.state.field(foldField)) { view.dispatch({ effects: setFolded.of(false) }); post("propertiesFolded", { folded: false }); }
  const at = view.state.doc.line(fm[1]).from;
  view.dispatch({ changes: { from: at, insert: "\n" }, selection: { anchor: at }, userEvent: "input" });
  view.focus();
  startCompletion(view);
}

// Tab and ⇧Tab move between values; Tab past the last one starts a new line for a name; Tab on a
// new line left empty removes it and carries on into the document (§4). Only inside the block.
function valueRanges(state) {
  const p = parseFrontmatter(state.doc);
  return p ? { p, ranges: p.lines.filter((L) => L.kind === "key" || L.kind === "item").map((L) => ({ n: L.n, from: L.vFrom, to: L.vTo })) } : null;
}
function inBlock(state) {
  const fm = frontmatterLines(state.doc);
  if (!fm) return null;
  const n = state.doc.lineAt(state.selection.main.head).number;
  return n > fm[0] && n < fm[1] ? { fm, n } : null;
}
function tabProperty(view, back) {
  const at = inBlock(view.state);
  if (!at) return false;
  if (!back && completionStatus(view.state) === "active") return acceptCompletion(view);
  const vr = valueRanges(view.state), head = view.state.selection.main.head, doc = view.state.doc;
  const line = doc.line(at.n);
  if (!back && line.text.trim() === "") {
    // An empty new line: take it out and go into the document.
    const after = at.fm[1] < doc.lines ? doc.line(at.fm[1] + 1).from - (line.length + 1) : doc.length - (line.length + 1);
    view.dispatch({ changes: { from: line.from, to: Math.min(doc.length, line.to + 1) }, selection: { anchor: Math.max(0, after) }, userEvent: "delete" });
    return true;
  }
  const list = vr.ranges;
  const i = list.findIndex((r) => r.n === at.n);
  const target = back ? list[Math.max(0, i - 1)] : list[i + 1];
  if (target && (back ? i > 0 : true)) {
    view.dispatch({ selection: { anchor: target.from, head: target.to }, scrollIntoView: true });
    return true;
  }
  if (back) return true;
  const end = doc.line(at.fm[1]).from;
  view.dispatch({ changes: { from: end, insert: "\n" }, selection: { anchor: end }, userEvent: "input" });
  startCompletion(view);
  return true;
}
const propertiesKeymap = Prec.highest(keymap.of([
  { key: "Tab", run: (v) => tabProperty(v, false) },
  { key: "Shift-Tab", run: (v) => tabProperty(v, true) },
  { key: "Alt-Escape", run: (v) => { if (!inBlock(v.state)) return false; const p = parseFrontmatter(v.state.doc), L = p.lines.find((l) => l.n === inBlock(v.state).n);
      if (L && (L.type === "date" || L.type === "datetime")) { const c = v.coordsAtPos(L.vFrom); post("propertyDate", { line: L.n, key: L.key, value: L.value, time: L.type === "datetime", x: c?.left ?? 0, y: c?.bottom ?? 0 }); return true; }
      return startCompletion(v); } },
  { key: "Mod-Enter", run: (v) => { const at = inBlock(v.state); if (!at) return false; const p = parseFrontmatter(v.state.doc), L = p.lines.find((l) => l.n === at.n);
      if (!L || L.type !== "link") return false; const lm = MD_LINK.exec(L.value.trim()); post("openLink", { url: lm ? lm[2] : L.value.trim().replace(/^["']|["']$/g, "") }); return true; } },
  { key: "Alt-ArrowUp", run: (v) => moveProperty(v, -1) },
  { key: "Alt-ArrowDown", run: (v) => moveProperty(v, 1) },
]));
// ⌥↑ ⌥↓: swap the caret's line with its neighbour inside the block.
function moveProperty(view, dir) {
  const at = inBlock(view.state);
  if (!at) return false;
  const other = at.n + dir;
  if (other <= at.fm[0] || other >= at.fm[1]) return true;
  const doc = view.state.doc, a = doc.line(Math.min(at.n, other)), b = doc.line(Math.max(at.n, other));
  const head = view.state.selection.main.head, col = head - doc.line(at.n).from;
  const insert = b.text + view.state.lineBreak + a.text;
  const newLineStart = dir < 0 ? a.from : a.from + b.text.length + 1;
  view.dispatch({ changes: { from: a.from, to: b.to, insert }, selection: { anchor: newLineStart + Math.min(col, doc.line(at.n).length) }, userEvent: "move.line" });
  return true;
}

// Suggestions (§4): names used elsewhere (this project first, most used first, leaving out names
// this document has), ending with New property "…"; values used under the same name. Never limits
// what can be typed. Duo sends the lists (contextField).
// The suggestions' last line names the keys (§4).
const suggestionKeys = EditorView.updateListener.of((u) => {
  const tip = u.view.dom.querySelector(".cm-tooltip-autocomplete");
  if (tip && !tip.querySelector(".duo-sugg-keys")) {
    const k = document.createElement("div");
    k.className = "duo-sugg-keys";
    k.innerHTML = "<span>tab Choose</span><span>↑↓ Move</span><span>esc Cancel</span>";
    tip.appendChild(k);
  }
});
// Sections only to keep New property "…" last; their headers are hidden.
const NAMES_SECTION = { name: "names", rank: 0 }, NEW_SECTION = { name: "new", rank: 1 };
function propertyCompletions(context) {
  const state = context.state, at = inBlock(state);
  if (!at) return null;
  const line = state.doc.line(at.n), before = state.sliceDoc(line.from, context.pos), ctx = state.field(contextField);
  const p = parseFrontmatter(state.doc, at.n);
  if (p.invalid && at.n >= p.invalid) return null;
  if (!before.includes(":") && !/^\s*-/.test(before)) {
    const typed = before.trim();
    const have = new Set(p.lines.filter((L) => L.kind === "key" && L.n !== at.n).map((L) => L.key));
    const options = (ctx.names || []).filter((o) => !have.has(o.name)).map((o) => ({
      label: o.name, type: o.type || "text", detail: `${TYPE_NAMES[o.type || "text"].toLowerCase()} · ${o.count} document${o.count === 1 ? "" : "s"}`, boost: (o.here ? 50 : 0) + Math.min(40, o.count), section: NAMES_SECTION,
      apply: (view, c, from, to) => acceptName(view, o.name, o.type || "text", from, to),
    }));
    if (typed && !(ctx.names || []).some((o) => o.name === typed)) options.push({ label: typed, displayLabel: `New property “${typed}”`, type: "text", detail: "text", section: NEW_SECTION,
      apply: (view, c, from, to) => acceptName(view, typed, "text", from, to) });
    return { from: line.from + (before.length - before.trimStart().length), options, filter: true };
  }
  const L = p.lines.find((l) => l.n === at.n);
  const key = L?.key;
  if (!key) return null;
  const vals = (ctx.values || {})[key] || [];
  if (!vals.length) return null;
  const from = L.kind === "item" ? L.vFrom : (L.vFrom > context.pos ? context.pos : L.vFrom);
  return { from, options: vals.map((v) => ({ label: v.value, detail: `${v.count} document${v.count === 1 ? "" : "s"}`, type: L.kind === "item" ? "list" : (L.type || "text") })), filter: true };
}
// Taking a name writes `name: ` and sets up its value for its type.
function acceptName(view, name, type, from, to) {
  const insert = type === "checkbox" ? `${name}: false` : type === "list" ? `${name}:\n  - ` : `${name}: `;
  view.dispatch({ changes: { from, to: view.state.doc.lineAt(from).to, insert }, selection: { anchor: from + insert.length }, userEvent: "input.complete" });
  if (type === "date" || type === "datetime") {
    const n = view.state.doc.lineAt(from).number, c = view.coordsAtPos(from + insert.length);
    post("propertyDate", { line: n, key: name, value: "", time: type === "datetime", x: c?.left ?? 0, y: c?.bottom ?? 0 });
  }
}

// One change to the frontmatter: the user's (an ordinary edit) or Claude's through duo2, which is
// highlighted and revertable like any change of Claude's (DL-5, frontmatter-claude.html).
function applyPropChange(change, agent, userEvent = "input") {
  if (!agent) { view.dispatch({ changes: change, userEvent }); return; }
  const removed = view.state.sliceDoc(change.from, change.to ?? change.from), ins = change.insert ?? "";
  const effects = [recordChanges.of([{ id: ++changeSeq, from: change.from, to: change.from + ins.length, removed }])];
  if (ins.length) effects.push(markAdded.of([[change.from, change.from + ins.length]]));
  view.dispatch({ changes: change, effects, userEvent: "agent" });
}

// Sets one property's value in the buffer, or removes it (null), touching only that line (LR-37).
// A new property goes on the end, before the closing fence.
function setProperty(key, value, agent = false) {
  const p = parseFrontmatter(view.state.doc);
  if (!p) {
    if (value == null) return true;
    applyPropChange({ from: 0, insert: `---\n${key}: ${value}\n---\n\n` }, agent);
    return true;
  }
  const L = p.lines.find((l) => l.kind === "key" && l.key === key);
  if (L) {
    if (value == null) {
      // The property and its list items go together.
      let end = L.n;
      while (end + 1 < p.fm[1] && p.lines.find((l) => l.n === end + 1)?.kind === "item") end++;
      const last = view.state.doc.line(end);
      applyPropChange({ from: L.from, to: Math.min(view.state.doc.length, last.to + 1) }, agent);
    } else {
      let end = L.to;
      for (const o of p.lines) if (o.n > L.n) { if (o.kind === "item" && o.key === key) end = o.to; else break; }
      applyPropChange({ from: L.keyEnd, to: end, insert: value === "" ? "" : " " + value }, agent);
    }
    return true;
  }
  if (value == null) return true;
  applyPropChange({ from: view.state.doc.line(p.fm[1]).from, insert: `${key}: ${value}\n` }, agent);
  return true;
}

// Adds an item to a list property, one per line, after its last item (DL-93).
function addListItem(key, item) {
  const p = parseFrontmatter(view.state.doc);
  if (!p) return setProperty(key, "") && addListItem(key, item);
  const L = p.lines.find((l) => l.kind === "key" && l.key === key);
  if (!L) return setProperty(key, "") && addListItem(key, item);
  let at = L.to;
  for (const o of p.lines) if (o.n > L.n) { if (o.kind === "item" && o.key === key) at = o.to; else if (o.kind === "key") break; }
  view.dispatch({ changes: { from: at, insert: `\n  - ${item}` }, userEvent: "input" });
  return true;
}

// The properties as Duo and duo2 read them: name, type, value (lists as arrays), line.
function listProperties() {
  const p = parseFrontmatter(view.state.doc);
  if (!p) return { properties: [], invalid: null };
  const props = p.lines.filter((L) => L.kind === "key").map((L) => {
    const items = p.lines.filter((o) => o.kind === "item" && o.key === L.key).map((o) => o.value.replace(/^["']|["']$/g, ""));
    const v = L.value.trim();
    const value = L.type === "list" ? (items.length ? items : v.replace(/^\[|\]$/g, "").split(",").map((x) => x.trim()).filter(Boolean)) : v.replace(/^["']|["']$/g, "");
    return { name: L.key, type: L.type, value: Array.isArray(value) ? value.filter((x) => x !== "") : value, line: L.n };
  });
  return { properties: props, invalid: p.invalid, why: p.why };
}

// Changing a type rewrites the value to match when it can (§3): text to a one-item list, a list
// to text joined by commas, text that reads as a date to the ISO form. When it can't, nothing
// changes and Duo says so (for a date, it opens the calendar instead).
function convertProperty(lineNo, type) {
  const p = parseFrontmatter(view.state.doc);
  const L = p?.lines.find((l) => l.n === lineNo && l.kind === "key");
  if (!L) return { result: "no property on that line" };
  if (L.type === type) return { result: "unchanged" };
  const items = p.lines.filter((o) => o.kind === "item" && o.key === L.key);
  const raw = L.value.trim().replace(/^["']|["']$/g, "");
  const words = L.type === "list" ? (items.length ? items.map((o) => o.value.replace(/^["']|["']$/g, "")) : raw.replace(/^\[|\]$/g, "").split(",").map((x) => x.trim()).filter(Boolean)) : [raw];
  let value = null;
  const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  switch (type) {
    case "text": value = words.join(", "); break;
    case "list": value = raw ? `[${raw}]` : "[]"; break;
    case "number": if (/^-?\d+(\.\d+)?$/.test(words.join(""))) value = words.join(""); break;
    case "checkbox": value = /^(true|yes|1|done)$/i.test(raw) ? "true" : "false"; break;
    case "link": if (/^https?:\/\//.test(raw) || /\.md$/.test(raw)) value = `"[${raw.split("/").pop()}](${raw})"`; break;
    case "date": case "datetime": {
      const d = parseDate(raw);
      if (d) value = type === "date" ? iso(d) : `${iso(d)}T${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
      else return { result: "needs date" };
      break;
    }
  }
  if (value == null) return { result: `can't read “${raw}” as ${TYPE_NAMES[type].toLowerCase()}` };
  const end = items.length ? items[items.length - 1].to : L.to;
  view.dispatch({ changes: { from: L.keyEnd, to: end, insert: value === "" ? "" : " " + value }, userEvent: "input.type" });
  return { result: "changed", value };
}
// Dates typed loosely: "2026-10-14", "oct 14", "October 14, 2026", "tomorrow", "next fri".
function parseDate(text) {
  const t = text.trim().toLowerCase(), now = new Date(), day = 86400000;
  if (!t) return null;
  if (t === "today") return now;
  if (t === "tomorrow") return new Date(now.getTime() + day);
  if (t === "yesterday") return new Date(now.getTime() - day);
  const wd = /^(next\s+)?(sun|mon|tue|wed|thu|fri|sat)[a-z]*$/.exec(t);
  if (wd) {
    const target = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"].indexOf(wd[2]);
    let add = (target - now.getDay() + 7) % 7 || 7;
    return new Date(now.getTime() + add * day);
  }
  if (/^\d{4}-\d{2}-\d{2}/.test(t)) { const d = new Date(t.length === 10 ? t + "T00:00" : t); return isNaN(d) ? null : d; }
  const withYear = /\d{4}/.test(t) ? t : `${t} ${now.getFullYear()}`;
  const d = new Date(withYear);
  return isNaN(d) ? null : d;
}
// Sets the value on one line (the date picker's choice), touching only that line.
function setPropertyLine(lineNo, value) {
  const p = parseFrontmatter(view.state.doc);
  const L = p?.lines.find((l) => l.n === lineNo && l.kind === "key");
  if (!L) return false;
  view.dispatch({ changes: { from: L.keyEnd, to: L.to, insert: " " + value }, userEvent: "input" });
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
  ".duo-fm-head.duo-fm-head-chev": { lineHeight: "16px" },
  ".duo-fm-chev": { display: "flex", alignItems: "center", cursor: "default" },
  ".duo-fm-invalid-note": { marginLeft: "auto", fontSize: "12px", lineHeight: "16px" },
  ".cm-line.duo-fm-fence": { color: "var(--duo-text2)" },
  ".duo-fm-icon": { position: "absolute", left: "12px", top: "0", width: "14px", height: "22px", display: "flex", alignItems: "center", justifyContent: "center", cursor: "default" },
  ".cm-line.duo-fm-first .duo-fm-icon": { top: "8px" },
  ".duo-fm-check": { margin: "0 4px 0 0", verticalAlign: "-2px" },
  ".duo-fm-control": { display: "inline-flex", alignItems: "center", marginLeft: "12px", verticalAlign: "-2px", cursor: "default" },
  ".duo-fm-link": { textDecoration: "underline", textDecorationColor: "var(--duo-control-edge)", textUnderlineOffset: "3px" },
  ".cm-line.duo-fm-claude::before": { content: "''", position: "absolute", left: "6px", right: "6px", top: "0", bottom: "0", backgroundColor: "var(--duo-selected)", borderRadius: "4px", zIndex: "-1" },
  ".duo-fm-claude-label": { float: "right", paddingLeft: "8px", fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif", fontSize: "12px", color: "var(--duo-text2)", whiteSpace: "nowrap" },
  ".cm-line.duo-fm-error::after": { content: "''", position: "absolute", left: "6px", right: "6px", top: "0", bottom: "0", boxShadow: "inset 0 0 0 1.5px var(--duo-text)", borderRadius: "4px", pointerEvents: "none" },
  ".duo-fm-message": { margin: "8px -8px 0", fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif", fontSize: "12px", lineHeight: "16px", color: "var(--duo-text2)" },
  ".duo-fm-rule.duo-fm-rule-folded": { margin: "6px -28px 22px" },
  // Suggestions (§4): pane, rule border, radius 10, the popover shadow; rows 26, radius 6.
  ".cm-tooltip.cm-tooltip-autocomplete": { backgroundColor: "var(--duo-pane)", border: "1px solid var(--duo-rule)", borderRadius: "10px", boxShadow: "0 12px 32px rgba(31, 35, 40, 0.22)", padding: "6px", fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif", fontSize: "13px" },
  ".cm-tooltip.duo-sugg-names > ul": { width: "286px" },
  ".cm-tooltip.duo-sugg-values > ul": { width: "266px" },
  ".cm-tooltip.cm-tooltip-autocomplete > ul": { fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif", maxHeight: "260px" },
  ".cm-tooltip.cm-tooltip-autocomplete > ul > li": { display: "flex", alignItems: "center", gap: "8px", height: "26px", lineHeight: "26px", padding: "0 8px", borderRadius: "6px", color: "var(--duo-text)" },
  ".cm-tooltip.cm-tooltip-autocomplete > ul > li[aria-selected]": { backgroundColor: "var(--duo-selected)", color: "var(--duo-text)" },
  ".cm-tooltip.cm-tooltip-autocomplete.cm-tooltip > ul > completion-section": { display: "none" },
  // The hairline before New property "…": the second section's header, drawn as a rule.
  ".cm-tooltip.cm-tooltip-autocomplete.cm-tooltip > ul > li + completion-section": { display: "block", height: "1px", margin: "4px 8px", padding: "0", border: "0", fontSize: "0", backgroundColor: "var(--duo-rule)", opacity: "1" },
  ".duo-sugg-keys": { display: "flex", gap: "12px", padding: "6px 8px 2px", fontSize: "12px", lineHeight: "16px", color: "var(--duo-text2)", whiteSpace: "nowrap" },
  ".cm-completionMatchedText": { textDecoration: "none", fontWeight: "600" },
  ".cm-completionDetail": { marginLeft: "auto", fontStyle: "normal", fontSize: "12px", color: "var(--duo-text2)" },
  ".duo-sugg-icon": { display: "inline-flex", width: "14px", justifyContent: "center", flex: "none" },
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
      foldField,
      ...(window.duoFlags?.noPreview ? [] : [propertiesField, propertiesKeymap, suggestionKeys,
        autocompletion({ override: [propertyCompletions], icons: false, activateOnTyping: true,
          tooltipClass: (st) => (inBlock(st) && !st.sliceDoc(st.doc.lineAt(st.selection.main.head).from, st.selection.main.head).includes(":") ? "duo-sugg-names" : "duo-sugg-values"),
          addToOptions: [{ position: 20, render: (c) => { const s = document.createElement("span"); s.className = "duo-sugg-icon";
            if (PROP_ICONS[c.type]) s.innerHTML = iconSvg(c.type); return s; } }] })]),
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
  listProperties,
  agentSetProperty: (k, v) => setProperty(k, v, true),
  propertyLine: (k) => parseFrontmatter(view.state.doc)?.lines.find((l) => l.kind === "key" && l.key === k)?.n ?? null,
  convertProperty,
  setPropertyLine,
  setFolded: (f) => { view.dispatch({ effects: setFolded.of(!!f) }); return true; },
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
