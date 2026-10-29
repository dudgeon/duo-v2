// Ordered lists stay numbered in the text: after an edit that changes a list's items, the list (and each
// nested ordered list on its own) is renumbered from its start number, in the same transaction, so undo
// restores the edit and the numbers together. Only lists the Markdown tree sees are touched, so code
// blocks are left alone. A list written all `1.` stays all `1.`; `1)` stays `1)`; one starting at 3 keeps 3.
import { EditorState } from "@codemirror/state";
import { syntaxTree, ensureSyntaxTree } from "@codemirror/language";
import { reviewField } from "./critic.js";

const ORDERED_MARK = /^[ \t]*(?:>[ \t]*)*\d{1,9}[.)](?:[ \t]|$)/m;
const MARK = /^(\d+)([.)])$/;

const treeOf = (state) => ensureSyntaxTree(state, state.doc.length, 200) || syntaxTree(state);

// Every OrderedList in `state` touching one of the [from, to] ranges, plus its ancestors; { node, items }.
function listsAt(state, ranges) {
  const seen = new Map(), tree = treeOf(state), doc = state.doc;
  // A list and every ordered list inside it: an item moved in or out carries its sub-lists along.
  const add = (node) => {
    if (seen.has(node.from)) return;
    seen.set(node.from, node.node);
    tree.iterate({ from: node.from, to: node.to, enter: (n) => { if (n.name === "OrderedList" && !seen.has(n.from)) seen.set(n.from, n.node); } });
  };
  for (const [a, b] of ranges) {
    const from = doc.lineAt(Math.min(a, doc.length)).from, to = Math.min(doc.length, doc.lineAt(Math.min(b, doc.length)).to + 1);
    tree.iterate({ from, to, enter: (n) => { if (n.name === "OrderedList") add(n); } });
    // a range inside a list item's own text: the list encloses it without the iteration entering from the top
    for (let n = tree.resolveInner(from, 1); n; n = n.parent) if (n.name === "OrderedList") add(n);
  }
  return [...seen.values()];
}

const depthOf = (list) => { let d = 0; for (let n = list.parent; n; n = n.parent) if (n.name === "OrderedList") d++; return d; };

function itemMarks(list) {
  const marks = [];
  for (let c = list.firstChild; c; c = c.nextSibling) {
    if (c.name !== "ListItem") continue;
    const m = c.firstChild;
    if (m?.name === "ListMark") marks.push(m);
  }
  return marks;
}

// Changes (in `state`'s coordinates) that number the lists touching `ranges`. `startOf(list)` may give the
// number the list started at before the edit (so deleting its first item keeps the start); null/undefined
// means the first mark as written.
function renumber(state, ranges, startOf) {
  const out = [];
  for (const list of listsAt(state, ranges)) {
    const marks = itemMarks(list);
    if (!marks.length) continue;
    const nums = marks.map((m) => MARK.exec(state.sliceDoc(m.from, m.to)));
    if (nums.some((x) => !x)) continue;
    let start = +nums[0][1];
    let lazy = nums.length > 1 && +nums[0][1] === +nums[1][1];
    const was = startOf?.(list, marks[0]);
    if (was) { start = was.start; lazy = was.lazy; }
    marks.forEach((m, i) => {
      const want = String(lazy ? start : start + i);
      if (nums[i][1] !== want) out.push({ from: m.from, to: m.from + nums[i][1].length, insert: want });
    });
  }
  return out;
}

// The new-document ranges an edit changed.
function changedRanges(tr) {
  const r = [];
  tr.changes.iterChangedRanges((_a, _b, fromB, toB) => r.push([fromB, toB]));
  return r;
}

const oldRanges = (tr) => { const r = []; tr.changes.iterChangedRanges((a, b) => r.push([a, b])); return r; };

// Is any ordered-list mark on a line the edit touched, before or after? (Keeps typing in prose free of a parse.)
function mentionsOrdered(tr) {
  let hit = false;
  const look = (doc, a, b) => { if (!hit && ORDERED_MARK.test(doc.sliceString(doc.lineAt(a).from, doc.lineAt(b).to))) hit = true; };
  tr.changes.iterChangedRanges((fromA, toA, fromB, toB) => { look(tr.startState.doc, fromA, toA); look(tr.newDoc, fromB, toB); });
  return hit;
}

const suggesting = (state) => { try { return state.field(reviewField).suggest; } catch { return false; } };

export const renumberLists = EditorState.transactionFilter.of((tr) => {
  if (!tr.docChanged) return tr;
  if (!(tr.isUserEvent("input") || tr.isUserEvent("delete") || tr.isUserEvent("move") || tr.isUserEvent("review"))) return tr;
  if (tr.isUserEvent("input.complete") || suggesting(tr.startState)) return tr;   // suggested edits are marks, not text
  if (!mentionsOrdered(tr)) return tr;
  // Lists as they were: a list whose first item went keeps the number it began at, unless its first mark was typed over.
  const before = listsAt(tr.startState, oldRanges(tr)).map((l) => {
    const ms = itemMarks(l), x = ms[0] && MARK.exec(tr.startState.sliceDoc(ms[0].from, ms[0].to));
    const y = ms[1] && MARK.exec(tr.startState.sliceDoc(ms[1].from, ms[1].to));
    return x ? { from: tr.changes.mapPos(l.from, 1), to: tr.changes.mapPos(l.to, -1), start: +x[1], lazy: !!y && +y[1] === +x[1], depth: depthOf(l) } : null;
  }).filter(Boolean);
  const startOf = (list, mark) => {
    let typed = false;   // an edit that reaches into the mark, not one that ends where it begins
    tr.changes.iterChangedRanges((_a, _b, fromB, toB) => { if (fromB < mark.to && toB > mark.from) typed = true; });
    if (typed) return null;
    let best = null;
    const depth = depthOf(list);
    for (const b of before) if (b.depth === depth && (b.from === list.from || (b.from <= list.from && b.to >= list.from))) if (!best || b.from >= best.from) best = b;
    if (!best && (tr.isUserEvent("input.indent") || tr.isUserEvent("delete.dedent")) && depth > 0) return { start: 1, lazy: false };   // a list made by indenting starts again at 1
    return best;
  };
  const state = tr.state;
  const changes = renumber(state, changedRanges(tr), startOf);
  return changes.length ? [tr, { changes, sequential: true }] : tr;
});

// For edits that aren't transactions of the user's (Claude's, DL-186): numbers fixed after the edit has landed,
// as one plain change. Returns the changes to dispatch, or [].
export function renumberAfter(state, ranges) {
  if (suggesting(state)) return [];
  return renumber(state, ranges, null);
}
