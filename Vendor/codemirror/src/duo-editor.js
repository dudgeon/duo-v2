// Duo's editor in one WKWebView (stack rec #8–9, spikes S4/S5). Markdown text is the only source
// of truth: the live preview hides syntax with decorations and never rewrites the text, so a
// save writes back exactly what was read plus the user's edits (LR-30).
import { EditorState, ChangeSet, StateField, StateEffect, RangeSetBuilder, Text, Compartment } from "@codemirror/state";
import { EditorView, ViewPlugin, Decoration, WidgetType, keymap } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { syntaxTree } from "@codemirror/language";
import { search, searchKeymap, SearchQuery, setSearchQuery, findNext } from "@codemirror/search";

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
  for (const { from, to } of view.visibleRanges) {
    syntaxTree(state).iterate({
      from, to,
      enter: (node) => {
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
    if (u.docChanged || u.viewportChanged || lines !== this.lines) this.decorations = buildDecorations(u.view);
    this.lines = lines;
  }
}, { decorations: (v) => v.decorations });

// ---------- "added by Claude" highlight (DL-5, LR-33) ----------

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
  ".duo-added": { backgroundColor: "var(--duo-selected)", borderRadius: "var(--duo-radius-card)" },
  ".duo-task": { margin: "0 6px 0 0", verticalAlign: "-1px" },
  ".cm-searchMatch": { backgroundColor: "var(--duo-selected)" },
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
      addedField,
      keymap.of([...defaultKeymap, ...historyKeymap, ...searchKeymap]),
      EditorView.contentAttributes.of({ spellcheck: "true", autocorrect: "on", autocapitalize: "on" }),
      EditorView.updateListener.of((u) => {
        if (u.selectionSet || u.docChanged) {
          const r = u.state.selection.main;
          // Never stringify the document per keystroke: 1.2 MB × every edit was 280 MB of garbage (F-34).
          post("selection", { from: r.from, to: r.to, empty: r.empty, dirty: !u.state.doc.eq(baseDoc) });
        }
      }),
    ],
  });
  if (view) view.destroy();
  view = new EditorView({ state, parent });
  return { mixedLineEndings: sepInfo.mixed, separator: JSON.stringify(sepInfo.sep) };
}

function wrap(marker) {
  const r = view.state.selection.main;
  const text = view.state.sliceDoc(r.from, r.to);
  view.dispatch({
    changes: { from: r.from, to: r.to, insert: marker + text + marker },
    selection: { anchor: r.from + marker.length, head: r.to + marker.length },
  });
}

const commands = {
  bold: () => wrap("**"),
  italic: () => wrap("*"),
  code: () => wrap("`"),
};

// External change (S5): `disk` is the file's new text. Three-way: base → disk is the outside
// edit, base → buffer is the user's. Disjoint edits merge, carets map through; overlapping ones
// are a conflict and nothing is applied (the banner is a design stub, §13).
function external(diskText) {
  const disk = canon(diskText);
  const buffer = view.state.doc.toString();
  if (disk === buffer) { setBase(disk); return { result: "same" }; }
  const outside = diffOne(base, disk);
  const mine = diffOne(base, buffer);
  const userEdited = buffer !== base;
  if (userEdited) {
    const overlap = outside.from < mine.to && mine.from < outside.to ||
      (outside.from === mine.from && outside.to === mine.to);
    if (overlap) return { result: "conflict", outside: [outside.from, outside.to], mine: [mine.from, mine.to] };
  }
  const outsideSet = ChangeSet.of([outside], base.length);
  const mineSet = ChangeSet.of(userEdited ? [mine] : [], base.length);
  const mapped = outsideSet.map(mineSet, true);
  view.dispatch({ changes: mapped, annotations: [], userEvent: "external" });
  setBase(disk);
  return { result: userEdited ? "merged" : "applied" };
}

// Agent edits go through the buffer (LR-34) and are highlighted until accepted (DL-5).
function agentInsert(at, text) {
  view.dispatch({ changes: { from: at, insert: text }, effects: markAdded.of([[at, at + text.length]]) });
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
  setReadOnly: (ro) => view.dispatch({ effects: readOnlyCompartment.reconfigure([EditorState.readOnly.of(ro), EditorView.editable.of(!ro)]) }),
  focus: () => view.focus(),
  create: (text) => create(document.getElementById("editor"), text),
  text: fileText,
  markSaved: () => setBase(view.state.doc.toString()),
  exec: (name) => { commands[name]?.(); return view.state.doc.length; },
  select: (from, to) => view.dispatch({ selection: { anchor: from, head: to ?? from } }),
  caret: () => view.state.selection.main.head,
  external,
  agentInsert,
  addedCount: () => view.state.field(addedField).size,
  find: (q) => { setSearchQuery.of(new SearchQuery({ search: q })); view.dispatch({ effects: setSearchQuery.of(new SearchQuery({ search: q })) }); findNext(view); return view.state.selection.main.from; },
  bench,
  typeSlowly,
  typeOne: (at) => view.dispatch({ changes: { from: at, insert: "x" }, selection: { anchor: at + 1 } }),
  hiddenCount: () => document.querySelectorAll(".cm-line").length,
};
post("ready", {});
