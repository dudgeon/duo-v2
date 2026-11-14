// Dictating into a document (DL-266 item 6): a phrase at a time at the caret, one undo for the whole
// dictation, a not-yet-settled tail drawn in `text2` beside the caret. The logic is state-only so it
// runs in node tests (test/dictation.test.mjs); duo-editor.js wires it to the view.
//
// Undo: every phrase of one dictation is stamped with the dictation's start time, so the history
// (`newGroupDelay`, 500 ms) joins them however long the speaker pauses, and `isolateHistory` closes
// the group at both ends so neither typing before nor typing after joins it.
// Suggest Edits: a phrase is an `input.type` change, so `suggestTyping` signs it and the next phrase
// extends the same insertion; with it off the words are plain text.
import { Annotation, Transaction, StateField, StateEffect } from "@codemirror/state";
import { Decoration, WidgetType, EditorView } from "@codemirror/view";
import { isolateHistory } from "@codemirror/commands";

// Marks a transaction as the dictation's own, so a user edit or caret move can be told from it.
export const dictationOwn = Annotation.define();

// The words still changing: not in the document, so Suggest Edits and undo never see them.
export const setTail = StateEffect.define();
class TailWidget extends WidgetType {
  constructor(text) { super(); this.text = text; }
  eq(o) { return o.text === this.text; }
  toDOM() { const s = document.createElement("span"); s.className = "duo-dict-tail"; s.textContent = this.text; return s; }
  ignoreEvent() { return true; }
}
export const tailField = StateField.define({
  create: () => ({ at: 0, text: "" }),
  update(v, tr) {
    for (const e of tr.effects) if (e.is(setTail)) return e.value;
    if (!v.text) return v;
    return tr.docChanged || tr.selection ? { at: tr.state.selection.main.head, text: v.text } : v;
  },
  provide: (f) => EditorView.decorations.from(f, (v) => (v.text ? Decoration.set([Decoration.widget({ widget: new TailWidget(v.text), side: 1 }).range(v.at)]) : Decoration.none)),
});

// A space between phrases unless the caret is at a line's start or after a space, and the phrase doesn't open with punctuation.
export function joiner(state, text) {
  const head = state.selection.main.from;
  if (!text || /^[\s.,;:!?)\]}%]/.test(text) || head === 0) return "";
  const before = state.sliceDoc(head - 1, head);
  return /[\s(\[{"“‘'\-]/.test(before) ? "" : " ";
}

// The change for one settled phrase. `d.first` replaces the selection (and starts the undo group);
// later phrases go at the caret.
export function phraseSpec(state, text, d) {
  const r = state.selection.main;
  const insert = joiner(state, text) + text;
  const annotations = [dictationOwn.of(true), Transaction.time.of(d.t0)];
  if (d.first) annotations.push(isolateHistory.of("before"));
  return { changes: { from: r.from, to: r.to, insert }, selection: { anchor: r.from + insert.length }, userEvent: "input.type", annotations,
           scrollIntoView: true, effects: setTail.of({ at: r.from + insert.length, text: "" }) };
}

// Closes the history group: the next change, however soon, is its own undo step.
export function endSpec(state) {
  return { annotations: [dictationOwn.of(true), isolateHistory.of("after")], effects: setTail.of({ at: state.selection.main.head, text: "" }) };
}

// True when a transaction is the user typing, deleting, undoing or clicking rather than the dictation.
export function breaksDictation(tr) {
  if (tr.annotation(dictationOwn)) return false;
  if (tr.docChanged) return tr.isUserEvent("input") || tr.isUserEvent("delete") || tr.isUserEvent("undo") || tr.isUserEvent("redo") || tr.isUserEvent("move");
  return tr.selection !== undefined && tr.isUserEvent("select");
}

export const dictationTheme = EditorView.baseTheme({ ".duo-dict-tail": { color: "var(--duo-text2)" } });
