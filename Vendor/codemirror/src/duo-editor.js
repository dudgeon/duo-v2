// Duo's editor in one WKWebView (stack rec #8–9, spikes S4/S5). Markdown text is the only source
// of truth: the live preview hides syntax with decorations and never rewrites the text, so a
// save writes back exactly what was read plus the user's edits (LR-30).
import { EditorState, ChangeSet, StateField, StateEffect, RangeSetBuilder, Text, Compartment, Prec } from "@codemirror/state";
import { EditorView, ViewPlugin, Decoration, WidgetType, keymap } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { syntaxTree } from "@codemirror/language";
import { autocompletion, startCompletion, completionStatus, acceptCompletion } from "@codemirror/autocomplete";
import { search, searchKeymap, SearchQuery, setSearchQuery, getSearchQuery, findNext, findPrevious, openSearchPanel, closeSearchPanel, replaceNext } from "@codemirror/search";

// ---------- live preview ----------

// A task box, drawn (S3-5): 12, radius 3; done is filled `text` with a white check. Clicking
// rewrites `[ ]` ↔ `[x]`: the text stays the truth.
class CheckboxWidget extends WidgetType {
  constructor(checked, from) { super(); this.checked = checked; this.from = from; }
  eq(o) { return o.checked === this.checked && o.from === this.from; }
  toDOM(view) {
    const box = document.createElement("span");
    box.className = "duo-task";
    box.setAttribute("role", "checkbox");
    box.setAttribute("aria-checked", String(this.checked));
    box.innerHTML = this.checked
      ? `<svg width="12" height="12" viewBox="0 0 12 12" aria-hidden="true"><rect x="0.5" y="0.5" width="11" height="11" rx="3" fill="var(--duo-text)"/><path d="M3 6.2 5 8.2 9 3.8" fill="none" stroke="var(--duo-pane)" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>`
      : `<svg width="12" height="12" viewBox="0 0 12 12" aria-hidden="true"><rect x="0.65" y="0.65" width="10.7" height="10.7" rx="3" fill="none" stroke="var(--duo-text2)" stroke-width="1.3"/></svg>`;
    box.addEventListener("mousedown", (e) => {
      e.preventDefault();
      view.dispatch({ changes: { from: this.from + 1, to: this.from + 2, insert: this.checked ? " " : "x" } });
    });
    return box;
  }
  ignoreEvent() { return false; }
}
// A list's mark, hung in text2 (S3-5): • for -, * and +; the number as written for ordered lists.
class ListMarkWidget extends WidgetType {
  constructor(text) { super(); this.text = text; }
  eq(o) { return o.text === this.text; }
  toDOM() { const s = document.createElement("span"); s.className = "duo-li-mark"; s.textContent = this.text; return s; }
}
// `---` away from the caret: a hairline (S3-5).
class RuleLineWidget extends WidgetType {
  eq() { return true; }
  toDOM() { const s = document.createElement("span"); s.className = "duo-hr"; return s; }
}
// A code block's language, top right (S3-5).
class CodeLangWidget extends WidgetType {
  constructor(lang) { super(); this.lang = lang; }
  eq(o) { return o.lang === this.lang; }
  toDOM() { const s = document.createElement("span"); s.className = "duo-code-lang"; s.textContent = this.lang; return s; }
}

const hide = Decoration.replace({});
const headingMarks = [1, 2, 3, 4, 5, 6].map((l) => Decoration.mark({ class: `duo-h duo-h${l}` }));
const headingMark = (level) => headingMarks[level - 1];
// The heading's line, so H2 and smaller can sit a little lower than the 10 between blocks (C-22).
const headingLines = [1, 2, 3, 4, 5, 6].map((l) => Decoration.line({ class: `duo-hl duo-hl${l}` }));
const strong = Decoration.mark({ class: "duo-strong" });
const em = Decoration.mark({ class: "duo-em" });
const code = Decoration.mark({ class: "duo-code" });
const link = Decoration.mark({ class: "duo-link" });

function buildDecorations(view) {
  const { state } = view;
  // The caret's line shows raw markdown (Obsidian's live preview).
  const active = rawLines(state);
  const ranges = [];
  const codeLines = new Set();
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
        if (name === "ListMark" && node.node.parent?.name === "ListItem") {
          const item = node.node.parent, task = item.getChild("Task");
          const lineStart = state.doc.lineAt(node.from).from;
          ranges.push([lineStart, lineStart, Decoration.line({ class: "duo-li" })]);
          if (!raw) {
            const text = state.sliceDoc(node.from, node.to);
            const ordered = item.parent?.name === "OrderedList";
            // A task item shows only its box; others hang their mark (• or the number).
            // Nested items take a dash, as the design draws them.
            let depth = 0;
            for (let p = item.parent; p; p = p.parent) if (p.name === "ListItem") depth++;
            if (task) ranges.push([node.from, Math.min(node.to + 1, state.doc.lineAt(node.from).to), hide]);
            else ranges.push([node.from, Math.min(node.to + 1, state.doc.lineAt(node.from).to), Decoration.replace({ widget: new ListMarkWidget(ordered ? text : depth ? "–" : "•") })]);
          }
          return;
        }
        if (name === "Task" && /^\[[xX]\]/.test(state.sliceDoc(node.from, node.from + 3))) {
          ranges.push([node.from + 3, node.to, Decoration.mark({ class: "duo-done" })]);
        }
        if (name === "Blockquote") {
          for (let n = state.doc.lineAt(node.from).number; n <= state.doc.lineAt(node.to).number; n++) {
            const l = state.doc.line(n);
            ranges.push([l.from, l.from, Decoration.line({ class: "duo-quote" })]);
          }
        } else if (name === "QuoteMark" && !raw) {
          ranges.push([node.from, Math.min(node.to + 1, state.doc.lineAt(node.from).to), hide]);
        } else if (name === "HorizontalRule" && !raw) {
          ranges.push([node.from, node.to, Decoration.replace({ widget: new RuleLineWidget() })]);
        } else if (name === "FencedCode") {
          const first = state.doc.lineAt(node.from).number, last = state.doc.lineAt(node.to).number;
          for (let n = first; n <= last; n++) codeLines.add(n);
          const info = node.node.getChild("CodeInfo");
          for (let n = first; n <= last; n++) {
            const l = state.doc.line(n), fence = (n === first || n === last) && /^\s*(```|~~~)/.test(l.text);
            const fenceRaw = active.has(n);
            ranges.push([l.from, l.from, Decoration.line({ class: "duo-codeblock" + (n === first ? " duo-codeblock-first" : "") + (n === last ? " duo-codeblock-last" : "") + (fence && !fenceRaw ? " duo-codeblock-fence" : "") })]);
            if (fence && !fenceRaw && l.to > l.from) ranges.push([l.from, l.to, hide]);
          }
          if (info && !active.has(first)) {
            const l = state.doc.line(first);
            ranges.push([l.to, l.to, Decoration.widget({ widget: new CodeLangWidget(state.sliceDoc(info.from, info.to).trim()), side: 1 })]);
          }
          return false;
        }
        if (m) {
          if (state.doc.lineAt(node.from).from === node.from) ranges.push([node.from, node.from, headingLines[m[1] - 1]]);
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
  // Blocks sit 10 apart, as the design draws them (S3-5): a blank line away from the caret is 10 high.
  for (const { from, to } of view.visibleRanges) {
    for (let pos = from; pos <= to;) {
      const l = state.doc.lineAt(pos);
      if (l.length === 0 && !active.has(l.number) && !codeLines.has(l.number) && l.from > fmEnd) ranges.push([l.from, l.from, Decoration.line({ class: "duo-blank" })]);
      pos = l.to + 1;
    }
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

// Which lines show raw markdown: the line each selection starts on (its anchor), not every line it
// covers. Revealing the lines a drag or shift+arrow passes over moved the text under it (a blank
// line grows from 10 to 20, a table turns into its source), so the selection landed lines away (C-25).
function rawLines(state) {
  const out = new Set();
  if (tmpl?.preview) return out;   // a template's preview is read, not edited: no line is raw (board A2)
  for (const r of state.selection.ranges) out.add(state.doc.lineAt(r.anchor).number);
  return out;
}
// Rebuild only when that set changes, not on every caret move.
const activeLines = (state) => state.selection.ranges.map((r) => state.doc.lineAt(r.anchor).number).join(",");
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
// One look everywhere (DL-102, Q-33), as frontmatter.html draws it: fences in text2, a type icon in
// the gutter, the value's control after it, a fold chevron. A task note adds its status popup,
// `+ Add` on `sessions:` and live session lines (S2-5).
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
// A template open in the editor (DL-146, templates-handoff): { kind: "task"|"project", preview }.
// Placeholders show as chips, the task look (status popup, session lines) is off, and a value
// that is a placeholder takes the type of what it becomes ({{date}} is a date).
let tmpl = null;
const setTemplate = StateEffect.define();
const PLACEHOLDER = /\{\{\s*(title|date|time)\s*(?::[^}\n]*)?\}\}/g;
const TEMPLATER = /<%[^\n]*?%>/g;
const asFilled = (v) => v.replace(/^(["']?)\{\{\s*date\s*\}\}\1$/, "2026-01-01").replace(/^(["']?)\{\{\s*time\s*\}\}\1$/, "09:00");

function valueType(key, value, hasItems) {
  const v = tmpl ? asFilled(value.trim()) : value.trim();
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
    box.style.display = "flow-root";   // keeps the rule's margins inside the height CodeMirror measures (F-249)
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
  constructor(message, hint) { super(); this.message = message || ""; this.hint = hint || null; }
  eq(o) { return o.message === this.message && JSON.stringify(o.hint) === JSON.stringify(this.hint); }
  toDOM() {
    const box = document.createElement("div");
    box.style.display = "flow-root";   // the rule's 14 above and 22 below count in the block's height, or clicks and arrows land lines away (F-249)
    if (this.message) { const m = document.createElement("div"); m.className = "duo-fm-message"; m.textContent = this.message; box.appendChild(m); }
    if (this.hint) {
      // A template's hint (board A1): its placeholders in mono.
      const m = document.createElement("div"); m.className = "duo-fm-message duo-tmpl-hint";
      for (const [text, mono] of this.hint) { const s = document.createElement("span"); if (mono) s.className = "duo-tmpl-code"; s.textContent = text; m.appendChild(s); }
      box.appendChild(m);
    }
    const r = document.createElement("div"); r.className = "duo-fm-rule"; box.appendChild(r);
    return box;
  }
}
// A quiet note at the right of a property line: "set by Duo" on a template's sessions (board A1).
class NoteWidget extends WidgetType {
  constructor(text) { super(); this.text = text; }
  eq(o) { return o.text === this.text; }
  toDOM() { const s = document.createElement("span"); s.className = "duo-fm-note"; s.textContent = this.text; return s; }
  ignoreEvent() { return true; }
}
const templateHint = (kind) => [[`When a ${kind} is made, `, false], ["{{title}}", true], [" becomes its name and ", false], ["{{date}}", true], [" today's date, as in Obsidian's Templates.", false]];

// Placeholders as chips (board A1): {{…}} framed, Templater's <% … %> dashed (board A3).
function placeholderDecorations(state) {
  if (!tmpl || tmpl.preview) return Decoration.none;
  const out = [], doc = state.doc;
  for (let n = 1; n <= doc.lines; n++) {
    const line = doc.line(n);
    if (!line.text.includes("{{") && !line.text.includes("<%")) continue;
    const heading = /^#{1,6}\s/.test(line.text) ? " duo-ph-h" : "";
    for (const [re, cls] of [[PLACEHOLDER, "duo-ph"], [TEMPLATER, "duo-ph duo-ph-tp"]]) {
      re.lastIndex = 0;
      for (let m; (m = re.exec(line.text));) out.push(Decoration.mark({ class: cls + heading }).range(line.from + m.index, line.from + m.index + m[0].length));
    }
  }
  return Decoration.set(out, true);
}
const placeholderField = StateField.define({
  create: (state) => placeholderDecorations(state),
  update(deco, tr) { return tr.docChanged || tr.effects.some((e) => e.is(setTemplate)) ? placeholderDecorations(tr.state) : deco.map(tr.changes); },
  provide: (f) => EditorView.decorations.from(f),
});

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
// A task's references (DL-150, task-board board 13): a file, folder or globe mark, the link's text
// (underlined, opens it), then its path in the project or its domain, mono text2.
const REF_ICONS = {
  file: '<svg width="10" height="12" viewBox="0 0 10 12"><path d="M1.5 1.5h4.5l2.5 2.5v6.5H1.5z" fill="none" stroke="currentColor" stroke-width="1.1" stroke-linejoin="round"/><path d="M6 1.5V4h2.5" fill="none" stroke="currentColor" stroke-width="1.1"/></svg>',
  folder: '<svg width="12" height="10" viewBox="0 0 12 10"><path d="M1 2.2c0-.7.5-1.2 1.2-1.2h2.3l1.2 1.3h4.1c.7 0 1.2.5 1.2 1.2v4.3c0 .7-.5 1.2-1.2 1.2H2.2C1.5 9 1 8.5 1 7.8z" fill="none" stroke="currentColor" stroke-width="1.1"/></svg>',
  url: '<svg width="11" height="11" viewBox="0 0 12 12"><circle cx="6" cy="6" r="4.8" fill="none" stroke="currentColor" stroke-width="1.1"/><path d="M1.2 6h9.6M6 1.2c1.6 1.4 1.6 8.2 0 9.6M6 1.2c-1.6 1.4-1.6 8.2 0 9.6" fill="none" stroke="currentColor" stroke-width="1.1"/></svg>',
};
const isURL = (u) => /^[a-z][a-z0-9+.-]*:\/\//i.test(u);
function refKind(url) { return isURL(url) ? "url" : url.endsWith("/") ? "folder" : "file"; }
// A link relative to the note, as a path in the project: tasks/ + ../docs/a.md → docs/a.md.
function projectPath(noteDir, rel) {
  const out = noteDir ? noteDir.split("/").filter(Boolean) : [];
  for (const part of decodeURI(rel).split("/")) {
    if (part === "..") out.pop(); else if (part !== "." && part !== "") out.push(part);
  }
  return out.join("/") + (rel.endsWith("/") ? "/" : "");
}
// The other way: a project path as a link from the note's folder.
function relativeTo(noteDir, path) {
  const from = noteDir ? noteDir.split("/").filter(Boolean) : [], to = path.split("/").filter(Boolean);
  let i = 0;
  while (i < from.length && i < to.length - 1 && from[i] === to[i]) i++;
  const rel = "../".repeat(from.length - i) + to.slice(i).join("/") + (path.endsWith("/") ? "/" : "");
  return encodeURI(rel);
}
function refDetail(ctx, url) {
  if (isURL(url)) { try { return new URL(url).hostname.replace(/^www\./, ""); } catch { return url; } }
  return projectPath(ctx.noteDir ?? "", url);
}
class ReferenceLineWidget extends WidgetType {
  constructor(url, title, detail) { super(); this.url = url; this.title = title; this.detail = detail; }
  eq(o) { return o.url === this.url && o.title === this.title && o.detail === this.detail; }
  toDOM() {
    const d = document.createElement("span");
    d.className = "duo-fm-ref";
    const i = document.createElement("span");
    i.className = "duo-fm-ref-icon";
    i.innerHTML = REF_ICONS[refKind(this.url)];
    d.appendChild(i);
    const n = document.createElement("span");
    n.className = "duo-fm-ref-name";
    n.textContent = this.title || this.detail;
    d.appendChild(n);
    const w = document.createElement("span");
    w.className = "duo-fm-ref-path";
    w.textContent = this.detail;
    d.appendChild(w);
    // A document opens in a right-pane tab, a folder is revealed, a URL opens per DL-3.
    n.addEventListener("mousedown", (e) => { e.preventDefault(); post("openLink", { url: this.url }); });
    d.addEventListener("contextmenu", (e) => { e.preventDefault(); post("propertyReference", { url: this.url, x: e.clientX, y: e.clientY }); });
    return d;
  }
  ignoreEvent(e) { return (e.type === "mousedown" && e.target.closest?.(".duo-fm-ref-name") != null) || e.type === "contextmenu"; }
}
// The field under a task's references (board 13): completes the project's files and folders as
// you type (matched words in bold, the folder at the right), takes a pasted URL; Return adds the
// link, relative to the note. With no references yet, it sits on its own `references` row.
class ReferenceFieldWidget extends WidgetType {
  constructor(labelled) { super(); this.labelled = labelled; }
  eq(o) { return o.labelled === this.labelled; }
  toDOM(view) {
    const row = document.createElement("div");
    row.className = "duo-fm-reffield-row" + (this.labelled ? " duo-fm-reffield-labelled" : "");
    if (this.labelled) {
      const k = document.createElement("span");
      k.className = "duo-fm-reffield-key";
      k.textContent = "references";
      row.appendChild(k);
    }
    const box = document.createElement("span");
    box.className = "duo-fm-reffield";
    const input = document.createElement("input");
    input.type = "text";
    input.placeholder = "Add a file, folder or link";
    input.spellcheck = false;
    box.appendChild(input);
    const list = document.createElement("div");
    list.className = "duo-fm-refmenu";
    list.hidden = true;
    box.appendChild(list);
    row.appendChild(box);
    let hits = [], sel = 0;
    const ctx = () => view.state.field(contextField);
    const render = () => {
      list.innerHTML = "";
      const q = input.value.trim();
      if (!q) { list.hidden = true; return; }
      const words = q.toLowerCase().split(/\s+/).filter(Boolean);
      const self = projectPath(ctx().noteDir ?? "", "./" + (view.state.field(contextField).noteName ?? ""));
      const files = (ctx().files ?? []).filter((f) => f !== self);
      hits = isURL(q) ? [] : files.filter((f) => { const l = f.toLowerCase(); return words.every((w) => l.includes(w)); })
        .sort((a, b) => {
          const an = a.split("/").filter(Boolean).pop().toLowerCase(), bn = b.split("/").filter(Boolean).pop().toLowerCase();
          const as = an.startsWith(words[0]) ? 0 : 1, bs = bn.startsWith(words[0]) ? 0 : 1;
          return as - bs || a.length - b.length || a.localeCompare(b);
        }).slice(0, 8);
      sel = Math.min(sel, Math.max(0, hits.length - 1));
      hits.forEach((f, n) => {
        const it = document.createElement("div");
        it.className = "duo-fm-refitem" + (n === sel ? " duo-fm-refitem-on" : "");
        const parts = f.split("/").filter(Boolean), name = parts.pop() + (f.endsWith("/") ? "/" : "");
        const ic = document.createElement("span"); ic.className = "duo-fm-ref-icon"; ic.innerHTML = REF_ICONS[f.endsWith("/") ? "folder" : "file"]; it.appendChild(ic);
        const nm = document.createElement("span"); nm.className = "duo-fm-refitem-name";
        const lower = name.toLowerCase(), w = words.find((x) => lower.includes(x));
        if (w) { const at = lower.indexOf(w); nm.append(name.slice(0, at)); const b = document.createElement("b"); b.textContent = name.slice(at, at + w.length); nm.append(b, name.slice(at + w.length)); }
        else nm.textContent = name;
        it.appendChild(nm);
        const dir = document.createElement("span"); dir.className = "duo-fm-refitem-dir"; dir.textContent = parts.length ? parts.join("/") + "/" : ""; it.appendChild(dir);
        it.addEventListener("mousedown", (e) => { e.preventDefault(); choose(f); });
        list.appendChild(it);
      });
      const hint = document.createElement("div");
      hint.className = "duo-fm-refhint";
      hint.innerHTML = REF_ICONS.url + "<span>" + (isURL(q) ? "Return adds this link" : "Paste a link, or drag a file here") + "</span>";
      list.appendChild(hint);
      list.hidden = false;
    };
    const quote = (s) => '"' + s.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
    const esc = (t) => t.replace(/[\[\]]/g, (m) => "\\" + m);
    const choose = (f) => {
      const noteDir = ctx().noteDir ?? "";
      const name = f.split("/").filter(Boolean).pop();
      const title = f.endsWith("/") ? name : name.replace(/\.md$/i, "");
      addListItem("references", quote(`[${esc(title)}](${relativeTo(noteDir, f)})`));
      finish();
    };
    // A pasted path (absolute, ~/, file:// or ./ ../ from the note) becomes a link relative to the
    // note, wherever the file is; null when it isn't one.
    const pathLink = (raw) => {
      let q = raw.replace(/^["']|["']$/g, "").trim();
      if (/^file:\/\//i.test(q)) { try { q = decodeURI(q.replace(/^file:\/\//i, "")); } catch { return null; } }
      const c = ctx(), root = (c.root ?? "").replace(/\/$/, ""), noteDir = c.noteDir ?? "";
      let abs = null;
      if (q.startsWith("~/") && c.home) abs = c.home.replace(/\/$/, "") + q.slice(1);
      else if (q.startsWith("/")) abs = q;
      else if (/^\.\.?\//.test(q) && root) abs = "/" + projectPath(noteDir ? root.slice(1) + "/" + noteDir : root.slice(1), q).replace(/^\//, "");
      if (!abs || abs === "/") return null;
      let folder = abs.endsWith("/");
      if (root && abs.startsWith(root + "/") && (c.files ?? []).includes(abs.slice(root.length + 1).replace(/\/?$/, "/"))) folder = true;
      const noteAbs = root ? root + (noteDir ? "/" + noteDir : "") : "";
      const name = abs.split("/").filter(Boolean).pop();
      const rel = noteAbs ? relativeTo(noteAbs, abs.replace(/\/?$/, folder ? "/" : "")) : encodeURI(abs);
      return { title: folder ? name : name.replace(/\.md$/i, ""), rel };
    };
    const addPath = (l) => { addListItem("references", quote(`[${esc(l.title)}](${l.rel})`)); finish(); };
    const finish = () => { input.value = ""; render(); input.blur(); view.focus(); };
    const addURL = (u) => {
      let title = u;
      try { title = new URL(u).hostname.replace(/^www\./, ""); } catch {}
      addListItem("references", quote(`[${esc(title)}](${u})`));
      finish();
    };
    input.addEventListener("input", () => { sel = 0; render(); });
    input.addEventListener("blur", () => { setTimeout(() => { list.hidden = true; }, 100); });
    input.addEventListener("keydown", (e) => {
      e.stopPropagation();
      if (e.key === "ArrowDown") { e.preventDefault(); sel = Math.min(sel + 1, hits.length - 1); render(); }
      else if (e.key === "ArrowUp") { e.preventDefault(); sel = Math.max(sel - 1, 0); render(); }
      else if (e.key === "Escape") { e.preventDefault(); input.value = ""; render(); input.blur(); view.focus(); }
      else if (e.key === "Enter") {
        e.preventDefault();
        const q = input.value.trim();
        const pl = isURL(q) && !/^file:\/\//i.test(q) ? null : pathLink(q);
        if (isURL(q) && !pl) addURL(q); else if (hits[sel]) choose(hits[sel]); else if (pl) addPath(pl);
      }
    });
    return row;
  }
  ignoreEvent() { return true; }
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
  const doc = state.doc, ctx = state.field(contextField), task = !tmpl && (ctx.task || p.isTask);
  const folded = state.field(foldField);
  const active = rawLines(state);
  const claude = new Set();
  state.field(addedField).between(doc.line(p.fm[0]).from, doc.line(p.fm[1]).to, (f, t) => {
    for (let n = doc.lineAt(f).number; n <= doc.lineAt(Math.max(f, t - 1)).number; n++) claude.add(n);
  });
  const out = [];
  const open = doc.line(p.fm[0]), close = doc.line(p.fm[1]);
  // The references field (DL-150) goes under the last reference, or on its own row before the fence.
  const refs = p.lines.filter((L) => L.key === "references");
  const lastRef = task && !tmpl && !p.invalid ? (refs.length ? refs[refs.length - 1].n : -1) : null;
  const next = p.fm[1] < doc.lines ? doc.line(p.fm[1] + 1) : null;
  const blankAfter = next && next.text.trim() === "" && p.fm[1] + 1 < doc.lines;
  if (folded) {
    // The heading alone, chevron pointing right, and the rule 6 under it.
    out.push(Decoration.replace({ widget: new HeadingWidget(p.count, true, true, p.invalid, true), block: true }).range(open.from, blankAfter ? next.to : close.to));
    return Decoration.set(out, true);
  }
  for (const L of p.lines) {
    const cls = ["duo-fm"];
    if (active.has(L.n)) cls.push("duo-fm-active");
    else if (claude.has(L.n)) cls.push("duo-fm-claude");
    if (p.invalid === L.n) cls.push("duo-fm-error");
    const broken = p.invalid != null && L.n >= p.invalid;  // from the error on: no icons or controls
    if (L.kind === "item") cls.push("duo-fm-item");
    if (L.kind === "item" && L.key === "references" && task && !active.has(L.n)) {
      const lm = MD_LINK.exec(L.value.trim());
      out.push(Decoration.line({ class: cls.join(" ") }).range(L.from));
      const url = lm ? lm[2] : L.value.trim().replace(/^["']|["']$/g, "");
      if (url) out.push(Decoration.replace({ widget: new ReferenceLineWidget(url, lm ? lm[1].replace(/\\([\[\]])/g, "$1") : "", refDetail(ctx, url)) }).range(L.from, L.to));
      if (L.n === lastRef) out.push(Decoration.widget({ widget: new ReferenceFieldWidget(false), block: true, side: 1 }).range(L.to));
      continue;
    }
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
    if (L.key === "references" && L.n === lastRef && !active.has(L.n)) out.push(Decoration.widget({ widget: new ReferenceFieldWidget(false), block: true, side: 1 }).range(L.to));
    out.push(Decoration.mark({ class: "duo-fm-key" }).range(L.from, L.keyEnd));
    if (claude.has(L.n) && !active.has(L.n)) out.push(Decoration.widget({ widget: new ClaudeLabelWidget(), side: 2 }).range(L.to));
    if (broken) continue;
    out.push(Decoration.widget({ widget: new IconWidget(L.type, L.n, L.key), side: -1 }).range(L.from));
    if (tmpl && !tmpl.preview && tmpl.kind === "task" && L.key === "sessions") out.push(Decoration.widget({ widget: new NoteWidget("set by Duo"), side: 2 }).range(L.to));
    if (tmpl && (tmpl.preview || L.value.includes("{{"))) continue;   // no controls on a placeholder, or in a preview (A2)
    if (task) {
      if (L.key === "status" && L.value) { out.push(Decoration.replace({ widget: new StatusWidget(L.value.replace(/^["']|["']$/g, "")) }).range(L.vFrom, L.vTo)); continue; }
      if (L.key === "sessions" && L.value === "") { out.push(Decoration.widget({ widget: new AddWidget(L.key), side: 1 }).range(L.to)); continue; }
    }
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
  {
    out.push(Decoration.widget({ widget: new HeadingWidget(p.count, true, false, p.invalid, false), block: true, side: -1 }).range(open.from));
    if (lastRef === -1) out.push(Decoration.widget({ widget: new ReferenceFieldWidget(true), block: true, side: -1 }).range(close.from));
    for (const f of [open, close]) {
      out.push(Decoration.line({ class: `duo-fm duo-fm-fence ${f === open ? "duo-fm-first" : "duo-fm-last"}${active.has(f.number) ? " duo-fm-active" : ""}` }).range(f.from));
      out.push(Decoration.mark({ class: "duo-fm-key" }).range(f.from, f.to));
    }
    const hint = !p.invalid && tmpl && !tmpl.preview ? templateHint(tmpl.kind) : null;
    const msg = p.invalid ? p.why + " Keep typing: it is saved as it is, and the icons and suggestions come back once it reads correctly." : "";
    if (blankAfter) out.push(Decoration.replace({ widget: new RuleWidget(msg, hint), block: true }).range(next.from, next.to));
    else out.push(Decoration.widget({ widget: new RuleWidget(msg, hint), block: true, side: 1 }).range(close.to));
  }
  return Decoration.set(out, true);
}
const propertiesField = StateField.define({
  create: (state) => propertiesDecorations(state),
  update(deco, tr) {
    if (tr.docChanged || tr.selection || tr.effects.some((e) => e.is(setContext) || e.is(setFolded) || e.is(markAdded) || e.is(clearAdded) || e.is(setTemplate))) return propertiesDecorations(tr.state);
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
// `a, "b, c", d` split on commas outside quotes (Frontmatter.splitInlineList), blanks dropped.
function splitInline(s) {
  const out = [];
  let cur = "", q = null;
  for (const ch of s) {
    if (q) { if (ch === q) q = null; cur += ch; }
    else if (ch === "\"" || ch === "'") { q = ch; cur += ch; }
    else if (ch === ",") { out.push(cur.trim()); cur = ""; }
    else cur += ch;
  }
  out.push(cur.trim());
  return out.filter(Boolean);
}

// A change from the properties block's own controls: the caret stays where it was, mapped before
// an insert at its place. Mapped after, it would land on the new line, which then shows as raw text
// and not as the link it is (F-250).
function dispatchKeepingCaret(spec) {
  const cs = view.state.changes(spec.changes), sel = view.state.selection.main;
  view.dispatch({ ...spec, changes: cs, selection: { anchor: cs.mapPos(sel.anchor, -1), head: cs.mapPos(sel.head, -1) } });
}

function addListItem(key, item) {
  const p = parseFrontmatter(view.state.doc);
  if (!p) return setProperty(key, "") && addListItem(key, item);
  const L = p.lines.find((l) => l.kind === "key" && l.key === key);
  // A new list: the key and its first item before the closing fence, no trailing space.
  if (!L) { dispatchKeepingCaret({ changes: { from: view.state.doc.line(p.fm[1]).from, insert: `${key}:\n  - ${item}\n` }, userEvent: "input" }); return true; }
  const v = L.value.trim();
  if (v) {
    // `sessions: []` (a new task) or `key: a`: the line becomes a block list with what it held
    // first, as TaskNotes.adding writes it. An item under an inline list isn't YAML.
    const inline = /^\[.*\]$/.test(v), old = inline ? splitInline(v.slice(1, -1)) : [v];
    const insert = `${key}:` + [...old, item].map((x) => `\n  - ${x}`).join("");
    dispatchKeepingCaret({ changes: { from: L.from, to: L.to, insert }, userEvent: "input" });
    return true;
  }
  let at = L.to;
  for (const o of p.lines) if (o.n > L.n) { if (o.kind === "item" && o.key === key) at = o.to; else if (o.kind === "key") break; }
  dispatchKeepingCaret({ changes: { from: at, insert: `\n  - ${item}` }, userEvent: "input" });
  return true;
}

// Removes the item of a list property whose value links to `url` (Remove from Task on a
// reference, DL-150); the key goes too when it was the last item. Nothing else changes.
function removeListItem(key, url) {
  const p = parseFrontmatter(view.state.doc);
  if (!p) return false;
  const items = p.lines.filter((l) => l.kind === "item" && l.key === key);
  const it = items.find((l) => { const m = MD_LINK.exec(l.value.trim()); return (m ? m[2] : l.value.trim().replace(/^["']|["']$/g, "")) === url; });
  if (!it) return false;
  if (items.length === 1) return setProperty(key, null);
  const line = view.state.doc.line(it.n);
  view.dispatch({ changes: { from: line.from - 1, to: line.to }, userEvent: "delete" });
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
// A conflict's lines, outlined in the text (S3-4): search's outline, labelled "Lines a–b · changed
// on disk". Stays through typing (mapped), until Duo clears it when the conflict is resolved.
const setConflict = StateEffect.define();
const conflictField = StateField.define({
  create: () => Decoration.none,
  update(deco, tr) {
    deco = deco.map(tr.changes);
    for (const e of tr.effects) if (e.is(setConflict)) {
      deco = Decoration.none;
      if (e.value) {
        const all = [];
        for (const [a, b] of e.value) {
          const set = searchDecorations(tr.state, a, b, a === b ? `Line ${a} · changed on disk` : `Lines ${a}–${b} · changed on disk`, []);
          set.between(0, tr.state.doc.length, (f, t, v) => { all.push(v.range(f, t)); });
        }
        deco = Decoration.set(all, true);
      }
    }
    return deco;
  },
  provide: (f) => EditorView.decorations.from(f),
});
const markAdded = StateEffect.define();
const clearAdded = StateEffect.define();
// Motion (DL-130): a new highlight fades in (`motion.highlightIn`), then settles to the plain
// class, so a line CodeMirror redraws later doesn't fade in again. Durations come from Duo's
// tokens (`--duo-motion-*-ms`, zero with Reduce Motion) and honour prefers-reduced-motion.
const settleAdded = StateEffect.define();
function motionMs(name) {
  if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) return 0;
  return parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--duo-motion-" + name + "-ms")) || 0;
}
function addedRanges(deco) {
  const out = [];
  deco.between(0, 1e9, (f, t) => { out.push([f, t]); });
  return out;
}
const addedField = StateField.define({
  create: () => Decoration.none,
  update(deco, tr) {
    deco = deco.map(tr.changes);
    for (const e of tr.effects) {
      // An empty insert marks nothing (a mark can't be empty).
      if (e.is(markAdded)) {
        const cls = motionMs("highlight-in") > 0 ? "duo-added duo-added-new" : "duo-added";
        deco = deco.update({ add: e.value.filter(([f, t]) => t > f).map(([f, t]) => Decoration.mark({ class: cls }).range(f, t)) });
      }
      if (e.is(settleAdded)) deco = Decoration.set(addedRanges(deco).map(([f, t]) => Decoration.mark({ class: "duo-added" }).range(f, t)), true);
      if (e.is(clearAdded)) deco = Decoration.none;
    }
    return deco;
  },
  provide: (f) => EditorView.decorations.from(f),
});
// Cleared highlights fade out (`motion.highlightOut`) rather than blink off. Only the look: the
// highlight itself (and what Revert can put back) is gone at once, as before (DL-5).
const startFade = StateEffect.define();
const endFade = StateEffect.define();
const fadingField = StateField.define({
  create: () => Decoration.none,
  update(deco, tr) {
    deco = deco.map(tr.changes);
    for (const e of tr.effects) {
      if (e.is(startFade)) deco = Decoration.set(e.value.map(([f, t]) => Decoration.mark({ class: "duo-added-fading" }).range(f, t)), true);
      if (e.is(endFade)) deco = Decoration.none;
    }
    return deco;
  },
  provide: (f) => EditorView.decorations.from(f),
});
let settleTimer = null, fadeTimer = null;
// The highlight's keyframes (from nothing to `selected`, and back), off with Reduce Motion.
{
  const st = document.createElement("style");
  st.textContent = "@keyframes duo-highlight-in { from { background-color: transparent; } to { background-color: var(--duo-selected); } }"
    + " @keyframes duo-highlight-out { from { background-color: var(--duo-selected); } to { background-color: transparent; } }"
    + " @media (prefers-reduced-motion: reduce) { .duo-added-new, .duo-added-fading { animation: none !important; } .duo-added-fading { background-color: transparent; } }";
  document.head.appendChild(st);
}
const highlightMotion = EditorView.updateListener.of((u) => {
  if (!u.transactions.some((t) => t.effects.some((e) => e.is(markAdded)))) return;
  const ms = motionMs("highlight-in");
  if (ms <= 0) return;
  clearTimeout(settleTimer);
  settleTimer = setTimeout(() => u.view.dispatch({ effects: settleAdded.of(null) }), ms + 50);
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
    const ms = motionMs("highlight-out");
    const effects = [clearAdded.of(null)];
    if (ms > 0) effects.push(startFade.of(addedRanges(u.state.field(addedField))));
    u.view.dispatch({ effects });
    if (ms > 0) { clearTimeout(fadeTimer); fadeTimer = setTimeout(() => u.view.dispatch({ effects: endFade.of(null) }), ms + 50); }
  }
});

// ---------- tables, images and Claude's deletions, drawn between lines (S3-5) ----------

// A table away from the caret is drawn as a table: `rule` borders, the header on `ground`, a
// wide one scrolling in its box. On the caret's lines it's its Markdown.
class TableWidget extends WidgetType {
  constructor(rows, align) { super(); this.rows = rows; this.align = align; }
  eq(o) { return JSON.stringify(o.rows) === JSON.stringify(this.rows) && o.align.join() === this.align.join(); }
  toDOM() {
    const box = document.createElement("div");
    box.className = "duo-table";
    const t = document.createElement("table");
    this.rows.forEach((r, i) => {
      const tr = document.createElement("tr");
      r.forEach((c, j) => {
        const td = document.createElement(i === 0 ? "th" : "td");
        // `<br>` is how a cell holds several lines in GFM (a paste into a cell writes it, DL-113).
        c.split(/<br\s*\/?>/i).forEach((part, k) => { if (k) td.appendChild(document.createElement("br")); td.appendChild(document.createTextNode(part)); });
        td.style.textAlign = this.align[j] || "left"; tr.appendChild(td);
      });
      t.appendChild(tr);
    });
    box.appendChild(t);
    return box;
  }
  ignoreEvent() { return false; }
}
function parseTable(text) {
  const lines = text.split("\n").filter((l) => l.trim());
  if (lines.length < 2) return null;
  const align = splitRow(lines[1]).map((d) => (/^:-+:$/.test(d) ? "center" : /-+:$/.test(d) ? "right" : "left"));
  const shown = (r) => splitRow(r).map((c) => c.replace(/\\\|/g, "|"));
  return { rows: [shown(lines[0]), ...lines.slice(2).map(shown)], align };
}

// ---------- editing tables (DL-113): Markdown on the caret, Format › Table, the bar, Tab ----------

// A row's cells, split on pipes that aren't escaped; `\|` stays in the cell's text (GFM).
function splitRow(line) {
  let t = line.trim();
  if (t.startsWith("|")) t = t.slice(1);
  if (t.endsWith("|") && !t.endsWith("\\|")) t = t.slice(0, -1);
  const cells = [];
  let cur = "";
  for (let i = 0; i < t.length; i++) {
    if (t[i] === "\\" && t[i + 1] === "|") { cur += "\\|"; i++; } else if (t[i] === "|") { cells.push(cur.trim()); cur = ""; } else cur += t[i];
  }
  cells.push(cur.trim());
  return cells;
}

// The table around a position: its lines, its cells, each column's alignment, and where the
// position is (row 0 is the header; the delimiter line counts as the header).
function tableAt(state, pos) {
  let node = null;
  syntaxTree(state).iterate({ from: pos, to: pos, enter: (n) => { if (n.name === "Table") { node = { from: n.from, to: n.to }; return false; } } });
  if (!node) return null;
  const a = state.doc.lineAt(node.from), b = state.doc.lineAt(node.to);
  const lines = [];
  for (let n = a.number; n <= b.number; n++) lines.push(state.doc.line(n));
  if (lines.length < 2) return null;
  const align = splitRow(lines[1].text).map((d) => (/^:-+:$/.test(d) ? "center" : /-+:$/.test(d) ? "right" : /^:-+$/.test(d) ? "left" : "none"));
  const rows = [splitRow(lines[0].text), ...lines.slice(2).map((l) => splitRow(l.text))];
  const cols = Math.max(align.length, ...rows.map((r) => r.length));
  for (const r of rows) while (r.length < cols) r.push("");
  while (align.length < cols) align.push("none");
  const line = state.doc.lineAt(pos), li = line.number - a.number;
  const before = state.sliceDoc(line.from, pos).replace(/\\\|/g, "");
  const pipes = (before.match(/\|/g) || []).length, lead = /^\s*\|/.test(line.text) ? 1 : 0;
  return { from: a.from, to: b.to, rows, align, cols, row: li <= 1 ? 0 : li - 1, col: Math.max(0, Math.min(cols - 1, pipes - lead)) };
}

// The table written out with its columns lined up, and where each cell's text sits.
function writeTable(t) {
  const widths = [];
  for (let j = 0; j < t.cols; j++) widths.push(Math.max(3, ...t.rows.map((r) => r[j].length)));
  const spots = [];
  const row = (cells, ri, lineStart) => {
    let s = "|";
    const at = [];
    cells.forEach((c, j) => {
      const room = widths[j] - c.length, a = t.align[j];
      const left = a === "right" ? room : a === "center" ? Math.floor(room / 2) : 0;
      s += " " + " ".repeat(left);
      at.push([lineStart + s.length, lineStart + s.length + c.length]);
      s += c + " ".repeat(room - left) + " |";
    });
    spots[ri] = at;
    return s;
  };
  const dash = (j) => {
    const w = widths[j], a = t.align[j];
    return a === "center" ? ":" + "-".repeat(w - 2) + ":" : a === "right" ? "-".repeat(w - 1) + ":" : a === "left" ? ":" + "-".repeat(w - 1) : "-".repeat(w);
  };
  const out = [];
  let off = 0;
  t.rows.forEach((cells, ri) => {
    const s = row(cells, ri, off);
    out.push(s); off += s.length + 1;
    if (ri === 0) { const d = "| " + widths.map((_, j) => dash(j)).join(" | ") + " |"; out.push(d); off += d.length + 1; }
  });
  return { text: out.join("\n"), spots };
}

// Rewrites the table and puts the caret in a cell (its text selected when `select`).
function putTable(view, t, row, col, select) {
  const w = writeTable(t);
  const [s, e] = w.spots[Math.max(0, Math.min(row, t.rows.length - 1))][Math.max(0, Math.min(col, t.cols - 1))];
  view.dispatch({ changes: { from: t.from, to: t.to, insert: w.text }, selection: { anchor: t.from + (select ? s : e), head: t.from + e },
                  scrollIntoView: true, userEvent: "input.table" });
  return true;
}
const here = () => tableAt(view.state, view.state.selection.main.head);
const emptyRow = (t) => Array.from({ length: t.cols }, () => "");

function insertTable() {
  const state = view.state, line = state.doc.lineAt(state.selection.main.head);
  // A blank line before and after: other readers only see a table that stands apart (DL-113).
  const atEmpty = line.text.trim() === "";
  const from = atEmpty ? line.from : line.to;
  const before = atEmpty ? (line.number > 1 && state.doc.line(line.number - 1).text.trim() !== "" ? "\n" : "") : "\n\n";
  const next = line.number < state.doc.lines ? state.doc.line(line.number + 1) : null;
  const after = next && next.text.trim() !== "" ? "\n" : "";
  const t = { rows: [["Column 1", "Column 2", "Column 3"], ["", "", ""], ["", "", ""]], align: ["none", "none", "none"], cols: 3 };
  const w = writeTable(t), at = from + before.length;
  view.dispatch({ changes: { from, to: atEmpty ? line.to : line.to, insert: before + w.text + after },
                  selection: { anchor: at + w.spots[0][0][0], head: at + w.spots[0][0][1] }, scrollIntoView: true, userEvent: "input.table" });
  view.focus();
  return true;
}
function addRow(below) {
  const t = here(); if (!t) return false;
  const at = below || t.row === 0 ? Math.max(1, t.row + 1) : t.row;
  t.rows.splice(at, 0, emptyRow(t));
  return putTable(view, t, at, t.col, false);
}
function addColumn(after) {
  const t = here(); if (!t) return false;
  const at = after ? t.col + 1 : t.col;
  for (const r of t.rows) r.splice(at, 0, "");
  t.align.splice(at, 0, "none"); t.cols++;
  return putTable(view, t, t.row, at, false);
}
function deleteRow() {
  const t = here(); if (!t || t.row === 0) return false;   // the header stays: a table needs one
  t.rows.splice(t.row, 1);
  return putTable(view, t, Math.min(t.row, t.rows.length - 1), t.col, false);
}
function deleteColumn() {
  const t = here(); if (!t) return false;
  if (t.cols === 1) {   // the last column: the table goes
    view.dispatch({ changes: { from: t.from, to: Math.min(view.state.doc.length, t.to + 1) }, userEvent: "delete.table" });
    return true;
  }
  for (const r of t.rows) r.splice(t.col, 1);
  t.align.splice(t.col, 1); t.cols--;
  return putTable(view, t, t.row, Math.min(t.col, t.cols - 1), false);
}
function alignColumn(a) {
  const t = here(); if (!t) return false;
  t.align[t.col] = a;
  return putTable(view, t, t.row, t.col, false);
}
// Tab and ⇧Tab: the next or previous cell, its text selected; Tab in the last cell adds a row.
function tabCell(back) {
  const t = here(); if (!t) return false;
  let r = t.row, c = t.col + (back ? -1 : 1);
  if (c >= t.cols) { c = 0; r++; }
  if (c < 0) { c = t.cols - 1; r--; }
  if (r < 0) return true;
  if (r >= t.rows.length) t.rows.push(emptyRow(t));
  return putTable(view, t, r, c, true);
}
// Return: the same column in the next row; in the last row, a new row. A row never breaks in two.
function enterCell() {
  const t = here(); if (!t || !view.state.selection.main.empty) return false;
  const r = t.row + 1;
  if (r >= t.rows.length) t.rows.push(emptyRow(t));
  return putTable(view, t, r, t.col, false);
}
const tableKeymap = Prec.high(keymap.of([
  { key: "Tab", run: () => tabCell(false) },
  { key: "Shift-Tab", run: () => tabCell(true) },
  { key: "Enter", run: () => enterCell() },
]));
// Pasting into a cell: one line, pipes escaped, so the row stays a row everywhere (DL-113).
function pasteIntoCell(e, v) {
  const sel = v.state.selection.main, text = e.clipboardData?.getData("text/plain");
  if (!text || v.state.doc.lineAt(sel.from).number !== v.state.doc.lineAt(sel.to).number || !tableAt(v.state, sel.head)) return false;
  if (!/[\n|]/.test(text)) return false;
  const one = text.replace(/\r\n?/g, "\n").replace(/\n+$/, "").replace(/(^|[^\\])\|/g, "$1\\|").replace(/\n/g, "<br>");
  e.preventDefault();
  v.dispatch({ changes: { from: sel.from, to: sel.to, insert: one }, selection: { anchor: sel.from + one.length }, userEvent: "input.paste" });
  return true;
}

// Pasting or dropping a picture (LR-39): Duo saves the file beside the document and `insertImage`
// puts a relative link on its own line. Never a blob or absolute URL.
const IMAGE_TYPES = /^image\/(png|jpe?g|gif|webp)$/;
function sendImages(files, pos) {
  let any = false;
  for (const f of files) {
    if (!IMAGE_TYPES.test(f.type)) continue;
    any = true;
    const r = new FileReader();
    r.onload = () => post("pasteImage", { mime: f.type, data: String(r.result).split(",")[1] || "", pos });
    r.readAsDataURL(f);
  }
  return any;
}
function pasteImage(e, v) {
  const files = [...(e.clipboardData?.files || [])];
  if (!files.some((f) => IMAGE_TYPES.test(f.type))) return false;
  e.preventDefault();
  return sendImages(files, v.state.selection.main.head);
}
function dropImage(e, v) {
  const files = [...(e.dataTransfer?.files || [])];
  if (!files.some((f) => IMAGE_TYPES.test(f.type))) return false;
  e.preventDefault();
  const at = v.posAtCoords({ x: e.clientX, y: e.clientY }) ?? v.state.selection.main.head;
  return sendImages(files, at);
}
function insertImage(md, pos) {
  const st = view.state;
  let at = Math.max(0, Math.min(pos >= 0 ? pos : st.selection.main.head, st.doc.length));
  let line = st.doc.lineAt(at);
  if (/^!\[[^\]]*\]\([^)]*\)\s*$/.test(line.text)) at = line.to; // a drop on a picture's own line goes after it
  const before = st.sliceDoc(line.from, at).trim() !== "", after = st.sliceDoc(at, line.to).trim() !== "";
  const prevBlank = line.number === 1 || st.doc.line(line.number - 1).text.trim() === "";
  const lead = before ? "\n\n" : (prevBlank ? "" : "\n");
  const nextBlank = line.number === st.doc.lines || st.doc.line(line.number + 1).text.trim() === "";
  const tail = after ? "\n\n" : (nextBlank ? "" : "\n");
  const ins = lead + md + tail;
  view.dispatch({ changes: { from: at, insert: ins }, selection: { anchor: at + lead.length + md.length }, userEvent: "input.paste", scrollIntoView: true });
  return true;
}

// The bar over a table while the caret is in it (DL-113, tables-handoff `tables-bar`).
class TableBarWidget extends WidgetType {
  eq() { return true; }
  toDOM() {
    const d = document.createElement("div");
    d.className = "duo-table-bar";
    d.innerHTML = `<button type="button" data-a="row">+ Row</button><button type="button" data-a="column">+ Column</button>` +
                  `<button type="button" data-a="align">Align ▾</button><button type="button" data-a="delete">Delete ▾</button>`;
    d.addEventListener("mousedown", (e) => {
      const b = e.target.closest("button"); if (!b) return;
      e.preventDefault();
      const a = b.dataset.a;
      if (a === "row") addRow(true);
      else if (a === "column") addColumn(true);
      else { const r = b.getBoundingClientRect(); post("tableMenu", { menu: a, x: r.left, y: r.bottom }); }
    });
    return d;
  }
  ignoreEvent() { return true; }
}

// An image on its own line: the picture (Duo reads the file and hands it over, since the page
// can't), radius 6 with a `rule` border, its alt text as a 12 `text2` caption. A missing file is a
// dashed box naming it.
const imageWaiters = new Map();
let imageSeq = 0;
class ImageWidget extends WidgetType {
  constructor(src, alt) { super(); this.src = src; this.alt = alt; }
  eq(o) { return o.src === this.src && o.alt === this.alt; }
  toDOM() {
    const fig = document.createElement("div");
    fig.className = "duo-figure";
    const show = (url) => {
      fig.textContent = "";
      if (url) {
        const img = document.createElement("img"); img.src = url; img.alt = this.alt; img.className = "duo-img"; fig.appendChild(img);
        if (this.alt) { const c = document.createElement("div"); c.className = "duo-caption"; c.textContent = this.alt; fig.appendChild(c); }
      } else {
        const m = document.createElement("div"); m.className = "duo-img-missing";
        const name = this.src.split("/").pop(), dir = this.src.includes("/") ? this.src.slice(0, this.src.lastIndexOf("/") + 1) : "this folder";
        m.innerHTML = `<code></code>&nbsp;isn’t in ${dir.replace(/[<&]/g, "")}`; m.querySelector("code").textContent = name;
        fig.appendChild(m);
      }
    };
    if (/^(https?:|data:)/.test(this.src)) show(this.src);
    else {
      const id = ++imageSeq;
      imageWaiters.set(id, show);
      post("image", { id, src: this.src });
      if (window.duoFlags?.noPost) show(null);
    }
    return fig;
  }
  ignoreEvent() { return false; }
}

// Where Claude deleted text (DL-5, S3-5): a hairline marker, "2 lines removed by Claude · Show ·
// Revert", until the highlight clears. Show opens what went, struck through.
class DeletionWidget extends WidgetType {
  constructor(id, removed, block) { super(); this.id = id; this.removed = removed; this.block = block; }
  eq(o) { return o.id === this.id && o.block === this.block; }
  toDOM(view) {
    const d = document.createElement(this.block ? "div" : "span");
    d.className = "duo-deleted" + (this.block ? " duo-deleted-block" : "");
    const n = this.removed.replace(/\n$/, "").split("\n").length;
    const what = this.removed.includes("\n") ? `${n} line${n === 1 ? "" : "s"} removed by Claude` : "Removed by Claude";
    d.innerHTML = `<span class="duo-deleted-rule"></span><span class="duo-deleted-text"></span><a href="#" class="duo-deleted-show">Show</a><a href="#" class="duo-deleted-revert">Revert</a><span class="duo-deleted-rule"></span>`;
    d.querySelector(".duo-deleted-text").textContent = what;
    const body = document.createElement("div"); body.className = "duo-deleted-body"; body.textContent = this.removed; body.hidden = true;
    d.appendChild(body);
    d.querySelector(".duo-deleted-show").addEventListener("mousedown", (e) => { e.preventDefault(); body.hidden = !body.hidden; e.target.textContent = body.hidden ? "Show" : "Hide"; view.requestMeasure(); });
    d.querySelector(".duo-deleted-revert").addEventListener("mousedown", (e) => { e.preventDefault(); revert([this.id]); });
    return d;
  }
  ignoreEvent() { return true; }
}

function blockDecorations(state) {
  const out = [];
  const active = rawLines(state);
  if (state.doc.length < 400000) {
    const fm = frontmatterLines(state.doc), fmEnd = fm ? state.doc.line(fm[1]).to : -1;
    syntaxTree(state).iterate({
      enter: (node) => {
        if (node.to <= fmEnd) return false;
        if (node.name === "Table") {
          const a = state.doc.lineAt(node.from), b = state.doc.lineAt(node.to);
          for (let n = a.number; n <= b.number; n++) if (active.has(n)) {
            out.push(Decoration.widget({ widget: new TableBarWidget(), block: true, side: -1 }).range(a.from));
            return false;
          }
          const t = parseTable(state.sliceDoc(a.from, b.to));
          if (t) out.push(Decoration.replace({ widget: new TableWidget(t.rows, t.align), block: true }).range(a.from, b.to));
          return false;
        }
        if (node.name === "Image") {
          const l = state.doc.lineAt(node.from);
          if (active.has(l.number) || l.text.trim() !== state.sliceDoc(node.from, node.to).trim()) return false;
          const text = state.sliceDoc(node.from, node.to), m = /^!\[([^\]]*)\]\(\s*<?([^)\s>]+)>?/.exec(text);
          if (m) out.push(Decoration.replace({ widget: new ImageWidget(m[2], m[1]), block: true }).range(l.from, l.to));
          return false;
        }
      },
    });
  }
  for (const c of state.field(changesField)) {
    if (c.from !== c.to || !c.removed.trim()) continue;
    const pos = Math.min(c.from, state.doc.length), atStart = state.doc.lineAt(pos).from === pos;
    out.push(Decoration.widget({ widget: new DeletionWidget(c.id, c.removed, atStart), block: atStart, side: atStart ? -1 : 1 }).range(pos));
  }
  return Decoration.set(out, true);
}
const blocksField = StateField.define({
  create: (state) => blockDecorations(state),
  update(deco, tr) {
    if (tr.docChanged || tr.selection || tr.effects.length) return blockDecorations(tr.state);
    return deco;
  },
  provide: (f) => EditorView.decorations.from(f),
});

// ---------- find, in Duo's look (S3-5) ----------

// A field with "n of m" inside it, then ‹ › and Done, under the tabs. Return finds the next,
// ⇧Return the previous, Escape closes. (Replace is CodeMirror's keys only; its panel isn't drawn.)
function findPanel(view) {
  const dom = document.createElement("div");
  dom.className = "duo-find";
  dom.innerHTML = `<label class="duo-find-field"><input type="text" main-field="true" aria-label="Find" placeholder="Find"><span class="duo-find-count"></span></label>`
    + `<button type="button" class="duo-find-btn" aria-label="Previous">‹</button><button type="button" class="duo-find-btn" aria-label="Next">›</button><button type="button" class="duo-find-btn">Done</button>`;
  const input = dom.querySelector("input"), count = dom.querySelector(".duo-find-count");
  const [prev, next, done] = dom.querySelectorAll("button");
  const tally = () => {
    const q = getSearchQuery(view.state);
    if (!q.search || !q.valid) { count.textContent = ""; return; }
    let n = 0, at = 0;
    const head = view.state.selection.main.from;
    const cur = q.getCursor(view.state);
    for (let r = cur.next(); !r.done && n < 9999; r = cur.next()) { n++; if (r.value.from <= head) at = n; }
    count.textContent = n ? `${Math.max(at, 1)} of ${n}` : "None";
  };
  input.value = getSearchQuery(view.state).search;
  input.addEventListener("input", () => { view.dispatch({ effects: setSearchQuery.of(new SearchQuery({ search: input.value })) }); findNext(view); tally(); });
  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter") { e.preventDefault(); (e.shiftKey ? findPrevious : findNext)(view); tally(); }
    if (e.key === "Escape") { e.preventDefault(); closeSearchPanel(view); view.focus(); }
  });
  prev.onmousedown = (e) => { e.preventDefault(); findPrevious(view); tally(); };
  next.onmousedown = (e) => { e.preventDefault(); findNext(view); tally(); };
  done.onmousedown = (e) => { e.preventDefault(); closeSearchPanel(view); view.focus(); };
  return { dom, top: true, mount() { input.focus(); input.select(); tally(); }, update(u) { if (u.selectionSet || u.docChanged) tally(); } };
}

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
  // How documents are drawn (S3-5, DL-101): H1 18/24, H2 14/20, the rest 13/20, all semibold.
  ".duo-h": { fontSize: "13px", fontWeight: "600" },
  ".duo-h1": { fontSize: "18px", lineHeight: "24px" },
  ".duo-h2": { fontSize: "14px" },
  // H2 and smaller sit 4 lower than the 10 between blocks, as editor-document draws them (C-22):
  // space.gap.aboveDocumentHeading, set by the app as --duo-heading-above. Padding, not margin, so
  // CodeMirror measures the line's height with it.
  ".cm-line.duo-hl2, .cm-line.duo-hl3, .cm-line.duo-hl4, .cm-line.duo-hl5, .cm-line.duo-hl6": { paddingTop: "var(--duo-heading-above)" },
  ".cm-line.duo-li": { paddingLeft: "20px", textIndent: "-20px" },
  ".duo-li-mark": { display: "inline-block", width: "12px", marginRight: "8px", textAlign: "right", textIndent: "0", color: "var(--duo-text2)" },
  ".duo-done": { color: "var(--duo-text2)" },
  ".cm-line.duo-quote": { borderLeft: "2px solid var(--duo-control-edge)", paddingLeft: "12px", color: "var(--duo-text2)" },
  ".cm-line.duo-codeblock": { position: "relative", padding: "0 12px", backgroundColor: "var(--duo-ground)", fontFamily: "'SF Mono', ui-monospace, monospace", fontSize: "12px", lineHeight: "19px", whiteSpace: "pre-wrap" },
  ".cm-line.duo-codeblock-first": { borderTopLeftRadius: "6px", borderTopRightRadius: "6px" },
  ".cm-line.duo-codeblock-last": { borderBottomLeftRadius: "6px", borderBottomRightRadius: "6px" },
  ".cm-line.duo-codeblock-fence": { height: "8px", lineHeight: "8px", fontSize: "0", overflow: "visible" },
  // No margin: the blank lines around it give the 10 between blocks, as the target draws it (C-22).
  ".duo-table": { overflowX: "auto" },
  ".duo-table table": { borderCollapse: "collapse", width: "100%", fontSize: "13px", lineHeight: "20px" },
  ".cm-line.duo-blank": { height: "10px", lineHeight: "10px" },
  ".duo-hr": { display: "inline-block", width: "100%", height: "1px", verticalAlign: "middle", backgroundColor: "var(--duo-rule)" },
  ".duo-table th, .duo-table td": { padding: "4px 8px", border: "1px solid var(--duo-rule)", whiteSpace: "nowrap" },
  ".duo-table-bar": { display: "flex", gap: "6px", margin: "0 0 6px" },
  ".duo-table-bar button": { font: "inherit", fontSize: "12px", lineHeight: "16px", padding: "2px 8px", border: "1px solid var(--duo-control-edge)",
                             borderRadius: "6px", background: "var(--duo-pane)", color: "var(--duo-text)", cursor: "default", whiteSpace: "nowrap" },
  ".duo-table th": { backgroundColor: "var(--duo-ground)", fontWeight: "600" },
  ".duo-figure": { display: "flex", flexDirection: "column", gap: "4px", margin: "4px 0" },
  ".duo-img": { maxWidth: "100%", borderRadius: "6px", border: "1px solid var(--duo-rule)" },
  ".duo-caption": { fontSize: "12px", color: "var(--duo-text2)" },
  ".duo-img-missing": { display: "flex", alignItems: "center", justifyContent: "center", height: "72px", border: "1px dashed var(--duo-control-edge)", borderRadius: "6px", color: "var(--duo-text2)" },
  ".duo-img-missing code": { fontFamily: "'SF Mono', ui-monospace, monospace", fontSize: "12px" },
  ".duo-deleted": { display: "inline-flex", alignItems: "center", gap: "8px", fontSize: "12px", lineHeight: "16px", color: "var(--duo-text2)", flexWrap: "wrap" },
  ".duo-deleted-block": { display: "flex", margin: "2px 0" },
  ".duo-deleted-rule": { flex: "1", minWidth: "12px", height: "1px", backgroundColor: "var(--duo-rule)" },
  ".duo-deleted a": { color: "var(--duo-text2)", textDecoration: "underline", textDecorationColor: "var(--duo-control-edge)", textUnderlineOffset: "3px", cursor: "default" },
  ".duo-deleted-body": { flexBasis: "100%", whiteSpace: "pre-wrap", textDecoration: "line-through", fontSize: "13px", lineHeight: "20px" },
  ".duo-code-lang": { position: "absolute", right: "10px", top: "6px", fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif", fontSize: "11px", lineHeight: "16px", color: "var(--duo-text2)", zIndex: "1" },
  ".duo-strong": { fontWeight: "600" },
  ".duo-em": { fontStyle: "italic" },
  ".duo-code": { fontFamily: "'SF Mono', ui-monospace, monospace", fontSize: "12px", backgroundColor: "var(--duo-ground)", borderRadius: "4px", padding: "1px 4px" },
  ".duo-link": { color: "var(--duo-text)", textDecoration: "underline", textDecorationColor: "var(--duo-control-edge)" },
  ".duo-fs": { boxShadow: "inset 1.5px 0 0 var(--duo-text), inset -1.5px 0 0 var(--duo-text)", paddingLeft: "12px", paddingRight: "12px", marginLeft: "-12px", marginRight: "-12px" },
  ".duo-fs-first": { boxShadow: "inset 1.5px 0 0 var(--duo-text), inset -1.5px 0 0 var(--duo-text), inset 0 1.5px 0 var(--duo-text)", borderTopLeftRadius: "6px", borderTopRightRadius: "6px", paddingTop: "8px", position: "relative" },
  ".duo-fs-last": { boxShadow: "inset 1.5px 0 0 var(--duo-text), inset -1.5px 0 0 var(--duo-text), inset 0 -1.5px 0 var(--duo-text)", borderBottomLeftRadius: "6px", borderBottomRightRadius: "6px", paddingBottom: "8px" },
  ".duo-fs-first.duo-fs-last": { boxShadow: "inset 0 0 0 1.5px var(--duo-text)" },
  ".duo-fs-first::after": { content: "attr(data-label)", position: "absolute", right: "12px", top: "8px", color: "var(--duo-text2)", fontFamily: "-apple-system, sans-serif", fontSize: "13px" },
  ".duo-added": { backgroundColor: "var(--duo-selected)", borderRadius: "var(--duo-radius-card)" },
  ".duo-added-new": { animation: "duo-highlight-in calc(var(--duo-motion-highlight-in-ms, 0) * 1ms) ease-out both" },
  ".duo-added-fading": { borderRadius: "var(--duo-radius-card)", animation: "duo-highlight-out calc(var(--duo-motion-highlight-out-ms, 0) * 1ms) ease-in-out both" },
  ".duo-task": { display: "inline-flex", margin: "0 8px 0 0", verticalAlign: "-1px", cursor: "default", textIndent: "0" },
  // The properties block (frontmatter-handoff §2, slice2 task-note): sizes from tokens size.propertiesBlock.
  "&.duo-has-fm .cm-content, .cm-content.duo-has-fm": { paddingTop: "14px" },
  ".duo-fm-head": { display: "flex", alignItems: "center", gap: "6px", margin: "0 -8px", paddingBottom: "6px", fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif", fontSize: "13px", lineHeight: "20px", color: "var(--duo-text2)" },
  ".duo-fm-label": { fontSize: "11px", lineHeight: "16px", fontWeight: "600", letterSpacing: "0.06em" },
  ".duo-fm-plus": { marginLeft: "auto", cursor: "default" },
  ".duo-fm-note": { float: "right", fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif", fontSize: "11px", color: "var(--duo-text2)" },
  ".duo-tmpl-code": { fontFamily: "ui-monospace, 'SF Mono', SFMono-Regular, Menlo, monospace", fontSize: "11px" },
  ".duo-ph": { padding: "0 4px", border: "1px solid var(--duo-rule)", borderRadius: "4px", backgroundColor: "var(--duo-pane)" },
  ".duo-ph-h": { backgroundColor: "var(--duo-ground)", fontFamily: "ui-monospace, 'SF Mono', SFMono-Regular, Menlo, monospace", fontSize: "0.8em", fontWeight: "400" },
  ".cm-line:not(.duo-fm) .duo-ph:not(.duo-ph-h)": { fontFamily: "ui-monospace, 'SF Mono', SFMono-Regular, Menlo, monospace", fontSize: "12px" },
  ".duo-ph.duo-ph-tp": { border: "1px dashed var(--duo-control-edge)", backgroundColor: "transparent" },
  "&.duo-tmpl-preview .duo-fm-plus, .duo-tmpl-preview .duo-fm-plus": { display: "none" },
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
  ".duo-fm-ref": { display: "inline-flex", alignItems: "center", gap: "6px", maxWidth: "100%", verticalAlign: "top", color: "var(--duo-text)" },
  ".duo-fm-ref-icon": { display: "inline-flex", flex: "none", color: "var(--duo-text2)" },
  ".duo-fm-ref-name": { textDecoration: "underline", textDecorationColor: "var(--duo-control-edge)", textUnderlineOffset: "3px", fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif", whiteSpace: "nowrap", cursor: "default" },
  ".duo-fm-ref-path": { color: "var(--duo-text2)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" },
  ".duo-fm-reffield-row": { display: "flex", alignItems: "center", gap: "10px", margin: "0 -12px", padding: "2px 12px 4px 32px", position: "relative", zIndex: "1", backgroundColor: "var(--duo-ground)", fontFamily: "'SF Mono', ui-monospace, monospace", fontSize: "12px", lineHeight: "19px" },
  ".duo-fm-reffield-key": { color: "var(--duo-text2)", flex: "none" },
  ".duo-fm-reffield": { position: "relative", display: "block", flex: "1", maxWidth: "340px", minWidth: "0" },
  ".duo-fm-reffield input": { width: "100%", height: "22px", boxSizing: "border-box", border: "1px solid var(--duo-rule)", borderRadius: "6px", padding: "0 8px", font: "12px -apple-system, BlinkMacSystemFont, sans-serif", color: "var(--duo-text)", background: "var(--duo-pane)", outline: "none" },
  ".duo-fm-reffield input:focus": { borderColor: "var(--duo-text)" },
  ".duo-fm-refmenu": { position: "absolute", top: "26px", left: "0", right: "0", zIndex: "20", backgroundColor: "var(--duo-pane)", border: "1px solid var(--duo-rule)", borderRadius: "10px", boxShadow: "0 12px 32px rgba(31, 35, 40, 0.22)", padding: "6px", font: "13px -apple-system, BlinkMacSystemFont, sans-serif" },
  ".duo-fm-refitem": { display: "flex", alignItems: "center", gap: "8px", height: "26px", padding: "0 8px", borderRadius: "6px", color: "var(--duo-text)" },
  ".duo-fm-refitem-on": { backgroundColor: "var(--duo-selected)" },
  ".duo-fm-refitem-name": { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" },
  ".duo-fm-refitem-name b": { fontWeight: "600" },
  ".duo-fm-refitem-dir": { marginLeft: "auto", flex: "none", fontFamily: "ui-monospace, 'SF Mono', Menlo, monospace", fontSize: "12px", color: "var(--duo-text2)" },
  ".duo-fm-refhint": { display: "flex", alignItems: "center", gap: "8px", height: "26px", padding: "0 8px", marginTop: "4px", borderTop: "1px solid var(--duo-rule)", color: "var(--duo-text2)", fontSize: "12px" },
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
  ".cm-panels.cm-panels-top": { borderBottom: "1px solid var(--duo-rule)", backgroundColor: "var(--duo-pane)" },
  ".duo-find": { display: "flex", alignItems: "center", gap: "6px", padding: "6px 20px", fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif", fontSize: "13px" },
  ".duo-find-field": { display: "flex", alignItems: "center", gap: "6px", flex: "1", height: "24px", boxSizing: "border-box", padding: "0 8px", border: "1px solid var(--duo-rule)", borderRadius: "6px", backgroundColor: "var(--duo-pane)" },
  ".duo-find-field input": { flex: "1", minWidth: "0", border: "0", outline: "none", background: "transparent", font: "inherit", color: "var(--duo-text)" },
  ".duo-find-count": { color: "var(--duo-text2)", whiteSpace: "nowrap" },
  ".duo-find-btn": { font: "12px/16px -apple-system, BlinkMacSystemFont, sans-serif", padding: "4px 10px", border: "1px solid var(--duo-control-edge)", borderRadius: "6px", backgroundColor: "var(--duo-pane)", color: "var(--duo-text)", cursor: "default" },
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
// The document, even while a template preview shows (DL-146): never the preview.
const fileText = () => (stash || view.state).sliceDoc();
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
    const raw = rawLines(view.state).has(line);
    if (raw && !e.metaKey) return false;
    const url = linkAt(view.state, pos);
    if (!url) return false;
    e.preventDefault();
    post("openLink", { url });
    return true;
  },
});

// ---------- a note's name: `title:` and its heading ----------

// A task note names itself twice, in `title:` and in the `# ` heading that opens its text (Make a
// Task, + New task); Duo's lists read `title:`. While the two agree, a person's edit to one is made
// to the other in the same step (one undo), so renaming a task by its heading renames it everywhere.
// Once they differ on purpose, each is left alone.
function nameSpots(doc) {
  const p = parseFrontmatter(doc);
  const L = p?.lines.find((l) => l.kind === "key" && l.key === "title");
  let title = null, heading = null;
  // A quote still being typed isn't a name yet.
  const unclosed = L && /^["']/.test(L.value) && !(L.value.length > 1 && L.value.endsWith(L.value[0]));
  if (L && !unclosed) {
    title = { from: L.vFrom, to: L.vTo, raw: L.value, name: unquoteYAML(L.value) };
  }
  // The heading is the text's first line that isn't blank, if it's a level-1 heading.
  for (let n = (p ? p.fm[1] : 0) + 1; n <= doc.lines; n++) {
    const line = doc.line(n);
    if (!line.text.trim()) continue;
    const m = /^#(?:[ \t]+|$)(.*)$/.exec(line.text);
    if (m) {
      const from = line.to - m[1].length, name = m[1].trim();
      heading = { from, to: line.to, name, nameTo: from + m[1].trimEnd().length };
    }
    break;
  }
  return { title, heading };
}

function unquoteYAML(v) {
  if (v.length > 1 && v.startsWith("\"") && v.endsWith("\"")) return v.slice(1, -1).replace(/\\(["\\])/g, "$1");
  if (v.length > 1 && v.startsWith("'") && v.endsWith("'")) return v.slice(1, -1).replace(/''/g, "'");
  return v.replace(/\s+#.*$/, "");
}

// The name written as `old` was: quoted the same way, or plain when plain is safe YAML.
function quoteYAMLLike(old, s) {
  if (old.startsWith("'")) return "'" + s.replace(/'/g, "''") + "'";
  if (old.startsWith("\"") || s === "" || /^[\s'"\[\]{}>|*&!%@`#,?:-]|: | #|\s$|^(true|false|yes|no|null|~|-?\d+(\.\d+)?)$/i.test(s)) {
    return "\"" + s.replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\"";
  }
  return s;
}

const titleFollowsHeading = EditorState.transactionFilter.of((tr) => {
  if (!tr.docChanged || !(tr.isUserEvent("input") || tr.isUserEvent("delete"))) return tr;
  const before = nameSpots(tr.startState.doc);
  if (!before.title || !before.heading || before.title.name !== before.heading.name) return tr;
  const after = nameSpots(tr.newDoc);
  if (!after.title || !after.heading) return tr;
  const headingMoved = after.heading.name !== before.heading.name, titleMoved = after.title.name !== before.title.name;
  if (headingMoved && !titleMoved) {
    return [tr, { changes: { from: after.title.from, to: after.title.to, insert: quoteYAMLLike(after.title.raw, after.heading.name) }, sequential: true }];
  }
  if (titleMoved && !headingMoved) {
    return [tr, { changes: { from: after.heading.from, to: after.heading.to, insert: after.title.name }, sequential: true }];
  }
  return tr;
});

function create(parent, text) {
  sepInfo = lineSeparatorOf(text);
  setBase(canon(text));
  stash = null;
  const state = EditorState.create({ doc: text, extensions: extensions(sepInfo.mixed) });
  if (view) view.destroy();
  view = new EditorView({ state, parent });
  // Duo's context for the note (its sessions' states) outlives the document: apply it again.
  if (window.__ctx) view.dispatch({ effects: setContext.of(window.__ctx) });
  return { mixedLineEndings: sepInfo.mixed, separator: JSON.stringify(sepInfo.sep) };
}

// Preview (board A2): the file a template would make, read-only, over the template, which comes
// back exactly as it was (its history too). Nothing is posted while it shows, so nothing saves it.
let stash = null;
function preview(text) {
  if (!stash) stash = view.state;
  view.setState(EditorState.create({ doc: text, extensions: extensions(true) }));
  if (window.__ctx) view.dispatch({ effects: setContext.of(window.__ctx) });
  return true;
}
function endPreview() {
  if (!stash) return false;
  view.setState(stash);
  stash = null;
  return true;
}

function extensions(readOnly) {
    return [
      EditorState.lineSeparator.of(sepInfo.sep),
      readOnlyCompartment.of([EditorState.readOnly.of(readOnly), EditorView.editable.of(!readOnly)]),
      EditorView.editorAttributes.compute([placeholderField], () => (tmpl?.preview ? { class: "duo-tmpl-preview" } : {})),
      placeholderField,
      duoTheme,
      EditorView.lineWrapping,
      history(),
      markdown({ base: markdownLanguage }),  // GitHub-flavoured: task lists, tables, strikethrough
      search({ top: true, createPanel: findPanel }),
      ...(window.duoFlags?.noPreview ? [] : [livePreview]),
      contextField,
      foldField,
      ...(window.duoFlags?.noPreview ? [] : [propertiesField, propertiesKeymap, tableKeymap, EditorView.domEventHandlers({ paste: (e, v) => pasteImage(e, v) || pasteIntoCell(e, v), drop: dropImage }), suggestionKeys,
        autocompletion({ override: [propertyCompletions], icons: false, activateOnTyping: true,
          tooltipClass: (st) => (inBlock(st) && !st.sliceDoc(st.doc.lineAt(st.selection.main.head).from, st.selection.main.head).includes(":") ? "duo-sugg-names" : "duo-sugg-values"),
          addToOptions: [{ position: 20, render: (c) => { const s = document.createElement("span"); s.className = "duo-sugg-icon";
            if (PROP_ICONS[c.type]) s.innerHTML = iconSvg(c.type); return s; } }] })]),
      addedField,
      fadingField,
      highlightMotion,
      conflictField,
      ...(window.duoFlags?.noPreview ? [] : [blocksField]),
      changesField,
      searchField,
      clearOnUserEdit,
      titleFollowsHeading,
      linkClicks,
      // Duo's menu chords win over CodeMirror's: ⌘D is Send Selection to Claude (DL-79), ⌘I is
      // Italic (CodeMirror's select-parent-syntax took it, so Format › Italic never fired).
      keymap.of([...defaultKeymap, ...historyKeymap, ...searchKeymap].filter((b) => !DUO_CHORDS.has(b.key))),
      EditorView.contentAttributes.of({ spellcheck: "true", autocorrect: "on", autocapitalize: "on" }),
      EditorView.updateListener.of((u) => {
        if (stash) return;   // a preview: not the document
        if (u.selectionSet || u.docChanged) {
          const r = u.state.selection.main;
          // Never stringify the document per keystroke: 1.2 MB × every edit was 280 MB of garbage (F-34).
          const claude = u.state.field(changesField);
          post("selection", { from: r.from, to: r.to, empty: r.empty, dirty: !u.state.doc.eq(baseDoc),
                              claudeChanges: claude.length, atClaudeChange: claude.some((c) => r.head >= c.from && r.head <= c.to),
                              inTable: !!tableAt(u.state, r.head) });
        }
      }),
    ];
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

// Format › Link… (⌘K, DL-108): the selection becomes a link's text and the caret waits for its
// address; with nothing selected, the caret waits for the text.
function insertLink() {
  const r = view.state.selection.main;
  const text = view.state.sliceDoc(r.from, r.to);
  const at = r.empty ? r.from + 1 : r.from + text.length + 3;
  view.dispatch({ changes: { from: r.from, to: r.to, insert: `[${text}]()` }, selection: { anchor: at }, userEvent: "input.format" });
}

// Format › Heading ▸ and Task (DL-108): each selected line's leading mark is replaced; choosing
// the mark a line already has takes it off.
function lineMark(mark, pattern, isOn = (t) => t.startsWith(mark)) {
  const state = view.state, changes = [];
  const lines = new Set();
  for (const r of state.selection.ranges) {
    for (let n = state.doc.lineAt(r.from).number; n <= state.doc.lineAt(r.to).number; n++) lines.add(n);
  }
  const all = [...lines].map((n) => state.doc.line(n));
  const has = all.every((l) => isOn(l.text));
  for (const l of all) {
    const old = pattern.exec(l.text)?.[0] ?? "";
    changes.push({ from: l.from, to: l.from + old.length, insert: has ? "" : mark });
  }
  view.dispatch({ changes, userEvent: "input.format" });
}
const HEADING_MARK = /^#{1,6}[ \t]+/;
const LIST_MARK = /^\s*(?:[-*+][ \t]+(?:\[[ xX]\][ \t]+)?|\d+[.)][ \t]+)/;

// Format › Add Properties (DL-108, frontmatter-handoff's `frontmatter-none`): starts the block on
// the first line with the most-used names on offer; with a block already there, a new line in it.
function addProperties() {
  if (frontmatterLines(view.state.doc)) { addProperty(view); return; }
  view.dispatch({ changes: { from: 0, insert: "---\n\n---\n" }, selection: { anchor: 4 }, userEvent: "input" });
  view.focus();
  startCompletion(view);
}

const commands = {
  bold: () => wrap("**"),
  italic: () => wrap("*"),
  code: () => wrap("`"),
  link: insertLink,
  heading1: () => lineMark("# ", HEADING_MARK),
  heading2: () => lineMark("## ", HEADING_MARK),
  heading3: () => lineMark("### ", HEADING_MARK),
  task: () => lineMark("- [ ] ", LIST_MARK, (t) => /^\s*[-*+][ \t]+\[[ xX]\][ \t]/.test(t)),
  properties: addProperties,
  tableInsert: insertTable,
  tableRowAbove: () => addRow(false),
  tableRowBelow: () => addRow(true),
  tableColumnBefore: () => addColumn(false),
  tableColumnAfter: () => addColumn(true),
  tableDeleteRow: deleteRow,
  tableDeleteColumn: deleteColumn,
  tableAlignLeft: () => alignColumn("left"),
  tableAlignCenter: () => alignColumn("center"),
  tableAlignRight: () => alignColumn("right"),
  tableNext: () => tabCell(false),
  tablePrevious: () => tabCell(true),
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
  insertImage,
  imageLoaded: (id, url) => { const f = imageWaiters.get(id); imageWaiters.delete(id); if (f) f(url); return true; },
  markConflict: (lines) => { view.dispatch({ effects: setConflict.of(lines && lines.length ? lines : null) }); return true; },
  setProperty,
  addListItem,
  removeListItem,
  listProperties,
  agentSetProperty: (k, v) => setProperty(k, v, true),
  propertyLine: (k) => parseFrontmatter(view.state.doc)?.lines.find((l) => l.kind === "key" && l.key === k)?.n ?? null,
  convertProperty,
  setPropertyLine,
  setFolded: (f) => { view.dispatch({ effects: setFolded.of(!!f) }); return true; },
  properties: () => { const fm = frontmatterLines(view.state.doc); return fm ? document.querySelectorAll(".duo-fm").length : 0; },
  // A template (DL-146): { kind, preview } or null; preview(text) shows the file it makes.
  setTemplate: (t) => { tmpl = t || null; view.dispatch({ effects: setTemplate.of(tmpl) }); return true; },
  preview: (t) => { tmpl = { ...(tmpl || {}), preview: true }; preview(t); view.dispatch({ effects: setTemplate.of(tmpl) }); return true; },
  endPreview: () => { if (tmpl) tmpl = { ...tmpl, preview: false }; const r = endPreview(); view.dispatch({ effects: setTemplate.of(tmpl) }); return r; },
  insertAtCaret: (t) => {
    const r = view.state.selection.main;
    view.dispatch({ changes: { from: r.from, to: r.to, insert: t }, selection: { anchor: r.from + t.length }, userEvent: "input.type" });
    view.focus();
    return true;
  },
  setReadOnly: (ro) => view.dispatch({ effects: readOnlyCompartment.reconfigure([EditorState.readOnly.of(ro), EditorView.editable.of(!ro)]) }),
  focus: () => view.focus(),
  // + New task: the heading's name selected, so typing names the task.
  selectHeading: () => {
    const h = nameSpots(view.state.doc).heading;
    if (!h) return false;
    view.dispatch({ selection: { anchor: h.from, head: h.nameTo }, scrollIntoView: true });
    view.focus();
    return true;
  },
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
