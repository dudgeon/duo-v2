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
      changesField,
      searchField,
      clearOnUserEdit,
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
