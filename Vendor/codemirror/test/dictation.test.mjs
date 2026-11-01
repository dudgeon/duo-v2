// Dictation into a document (DL-266): one undo for the whole dictation, Suggest Edits signs the words,
// and typing or a click after it is told apart. Run by test/run.sh.
import { EditorState } from "@codemirror/state";
import { history, undo, undoDepth } from "@codemirror/commands";
import { reviewCore, reviewField } from "../src/critic.js";
import { phraseSpec, endSpec, breaksDictation, tailField } from "../src/dictation.js";

let failed = 0;
const check = (ok, name) => { if (!ok) failed++; console.log(`${ok ? "  ✔" : "  ✘"} ${name}`); };
const mk = (doc, extra = []) => EditorState.create({ doc, extensions: [history(), tailField, ...extra] });
const apply = (st, spec) => st.update(spec).state;
const undoOnce = (st) => { let out = st; undo({ state: st, dispatch: (tr) => { out = tr.state; } }); return out; };

// Phrases seconds apart still undo as one.
{
  let st = mk("Hello\n\nWorld");
  st = apply(st, { changes: { from: 5, insert: "!" }, userEvent: "input.type" });   // typed before
  st = apply(st, { selection: { anchor: st.doc.length } });
  // Every phrase is stamped with the group's start, so a long pause between them never splits the undo; the
  // typing that follows comes inside the history's 500 ms, so only `isolateHistory` keeps it apart.
  const t0 = Date.now();
  st = apply(st, phraseSpec(st, "Who approves async refunds", { first: true, t0 }));
  st = apply(st, phraseSpec(st, "over a thousand", { first: false, t0 }));
  st = apply(st, phraseSpec(st, "dollars.", { first: false, t0 }));
  st = apply(st, endSpec(st));
  check(st.doc.toString() === "Hello!\n\nWorld Who approves async refunds over a thousand dollars.", "phrases are joined with single spaces: " + JSON.stringify(st.doc.toString()));
  st = apply(st, { changes: { from: 0, insert: "X" }, userEvent: "input.type" });   // typed after
  st = undoOnce(st);
  check(st.doc.toString().startsWith("Hello!") && st.doc.toString().includes("dollars."), "typing after the dictation is its own undo step");
  st = undoOnce(st);
  check(!st.doc.toString().includes("Who approves") && st.doc.toString().startsWith("Hello!"), "one undo takes out the whole dictation, and not the typing before it");
  check(undoDepth(st) === 1, "the typing before it is still in the history");
}

// A phrase over a selection replaces it.
{
  let st = mk("abc DEF ghi");
  st = apply(st, { selection: { anchor: 4, head: 7 } });
  st = apply(st, phraseSpec(st, "xyz", { first: true, t0: 1 }));
  check(st.doc.toString() === "abc xyz ghi", "the first phrase replaces the selection");
}

// Suggest Edits signs the words and the phrases extend one insertion.
{
  let st = mk("One line.\n", [reviewCore]);
  st = apply(st, { changes: { from: 0, insert: "---\nsuggest-edits: true\n---\n" }, userEvent: "setup" });
  const on = st.field(reviewField).suggest;
  check(on === true, "the document's switch turns Suggest Edits on");
  st = apply(st, { selection: { anchor: st.doc.length - 1 } });
  st = apply(st, phraseSpec(st, "and more", { first: true, t0: 5 }));
  st = apply(st, phraseSpec(st, "words", { first: false, t0: 5 }));
  const t = st.doc.toString();
  check((t.match(/\{\+\+/g) || []).length === 1 && t.includes("and more words"), "with Suggest Edits on the phrases are one signed insertion: " + JSON.stringify(t));
  // The signed rewrite of a phrase is still the dictation's own (else the page would think the user broke in).
  const tr = st.update(phraseSpec(st, "again", { first: false, t0: 5 }));
  check(!breaksDictation(tr), "a phrase rewritten as a signed insertion is still the dictation's own, not a user edit");
}

// What counts as the user breaking in.
{
  const st = mk("abc");
  const typed = st.update({ changes: { from: 0, insert: "x" }, userEvent: "input.type" });
  const clicked = st.update({ selection: { anchor: 2 }, userEvent: "select.pointer" });
  const own = st.update(phraseSpec(st, "hi", { first: true, t0: 1 }));
  const programmatic = st.update({ selection: { anchor: 1 } });
  check(breaksDictation(typed) && breaksDictation(clicked) && !breaksDictation(own) && !breaksDictation(programmatic), "typing and a click break a dictation; its own phrases and a scripted move don't");
}
if (failed) { console.log(`${failed} failed`); process.exit(1); }
