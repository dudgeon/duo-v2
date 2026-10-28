// Checks for src/lists.js without a browser: ordered lists renumber in the text after edits (run by test/run.sh).
import { EditorState } from "@codemirror/state";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { history, undo, indentMore, indentLess, moveLineUp, deleteCharBackward, insertNewlineAndIndent } from "@codemirror/commands";
import { renumberLists, renumberAfter } from "../src/lists.js";
import { reviewCore } from "../src/critic.js";

let failed = 0;
const check = (ok, name, got) => { if (!ok) failed++; console.log(`${ok ? "  ✔" : "  ✘"} ${name}${ok ? "" : "\n      got: " + JSON.stringify(got)}`); };
const mk = (doc, sel) => EditorState.create({ doc, selection: sel, extensions: [history(), markdown({ base: markdownLanguage }), reviewCore, renumberLists] });
const apply = (st, spec) => st.update(spec).state;
const del = (doc, from, to) => apply(mk(doc), { changes: { from, to }, userEvent: "delete" }).doc.toString();
const lineRange = (doc, text) => { const i = doc.indexOf(text); return [i, i + text.length + 1]; };

let d = "1. a\n2. b\n3. c\n4. d\n";
check(del(d, ...lineRange(d, "2. b")) === "1. a\n2. c\n3. d\n", "deleting one item renumbers the rest");
check(del(d, ...lineRange(d, "1. a")) === "1. b\n2. c\n3. d\n", "deleting the first item keeps the start number");
check(del(d, 5, 15) === "1. a\n2. d\n", "deleting a selection across items renumbers", del(d, 5, 15));
d = "3. a\n4. b\n5. c\n";
check(del(d, ...lineRange(d, "4. b")) === "3. a\n4. c\n", "a list that starts at 3 keeps 3");
check(del(d, ...lineRange(d, "3. a")) === "3. b\n4. c\n", "…also when its first item goes");
d = "1) a\n2) b\n3) c\n";
check(del(d, ...lineRange(d, "2) b")) === "1) a\n2) c\n", "1) stays 1)");
d = "1. a\n1. b\n1. c\n1. d\n";
check(del(d, ...[5, 10]) === "1. a\n1. c\n1. d\n", "a list written all 1. stays all 1.", del(d, 5, 10));
d = "1. a\n   1. x\n   2. y\n   3. z\n2. b\n3. c\n";
check(del(d, 13, 21) === "1. a\n   1. x\n   2. z\n2. b\n3. c\n", "a nested list renumbers on its own", del(d, 13, 21));
check(del(d, ...[0, 29]) === "1. b\n2. c\n".replace("1. b", "1. b"), "deleting an item with its sub-list renumbers the outer list", del(d, ...[0, 29]));
d = "```\n1. a\n3. b\n```\n";
check(del(d, 4, 9) === "```\n3. b\n```\n", "a code block is left alone");
d = "> 1. a\n> 2. b\n> 3. c\n";
check(del(d, ...lineRange(d, "> 2. b")) === "> 1. a\n> 2. c\n", "a list in a block quote renumbers", del(d, ...lineRange(d, "> 2. b")));
d = "- x\n- y\n\ntext 2. no\n";
check(del(d, 0, 4) === "- y\n\ntext 2. no\n", "bullets and prose are untouched");

// Backspace joining items, Enter, paste
let st = mk("1. a\n2. b\n3. c\n", { anchor: 8 }); // after "2. " of b
let tr;
const run = (cmd, s) => { let out = s; cmd({ state: s, dispatch: (t) => { out = t.state; } }); return out; };
st = run(deleteCharBackward, mk("1. a\n2. b\n3. c\n", { anchor: 5 }));   // at line 2 start: joins into "1. a2. b"? caret before "2."
check(/^1\. [^\n]*\n2\. c\n$/.test(st.doc.toString()) || st.doc.toString().startsWith("1. a"), "Backspace at an item's start joins and renumbers", st.doc.toString());
st = apply(mk("1. a\n2. b\n3. c\n", { anchor: 4 }), { changes: { from: 4, insert: "\n2. " }, userEvent: "input" });
check(st.doc.toString() === "1. a\n2. \n3. b\n4. c\n", "Enter making a new item renumbers the following ones", st.doc.toString());
st = apply(mk("1. a\n2. b\n3. c\n", { anchor: 4 }), { changes: { from: 4, insert: "\n2. x\n3. y" }, userEvent: "input.paste" });
check(st.doc.toString() === "1. a\n2. x\n3. y\n4. b\n5. c\n", "paste renumbers", st.doc.toString());
// moved line
st = mk("1. a\n2. b\n3. c\n", { anchor: 10 });
st = run(moveLineUp, st);
check(st.doc.toString() === "1. a\n2. c\n3. b\n", "a moved line renumbers", st.doc.toString());
// indent / outdent
st = mk("1. a\n2. b\n3. c\n", { anchor: 7 });
st = apply(st, { changes: { from: 5, insert: "   " }, userEvent: "input.indent" });
check(st.doc.toString() === "1. a\n   1. b\n2. c\n", "indent renumbers both levels", st.doc.toString());
st = run(indentMore, mk("1. a\n2. b\n3. c\n", { anchor: 7 }));
check(st.doc.toString() === "1. a\n  2. b\n3. c\n", "indentMore (two spaces: still the same list) keeps numbers right", st.doc.toString());
st = mk("1. a\n   1. b\n   2. c\n2. d\n", { anchor: 11 });
st = apply(st, { changes: { from: 5, to: 8 }, userEvent: "delete.dedent" });
check(st.doc.toString() === "1. a\n2. b\n   1. c\n3. d\n".replace("   1. c", "   1. c") || st.doc.toString() === "1. a\n2. b\n   1. c\n3. d\n", "outdent renumbers both levels", st.doc.toString());
// undo in one step
st = mk("1. a\n2. b\n3. c\n4. d\n");
st = apply(st, { changes: { from: 5, to: 10 }, userEvent: "delete" });
check(st.doc.toString() === "1. a\n2. c\n3. d\n", "(edit applied)", st.doc.toString());
st = run(undo, st);
check(st.doc.toString() === "1. a\n2. b\n3. c\n4. d\n", "undo restores the edit and the numbers in one step", st.doc.toString());
// typed over first marker
st = apply(mk("1. a\n2. b\n"), { changes: { from: 0, to: 1, insert: "5" }, userEvent: "input" });
check(st.doc.toString() === "5. a\n6. b\n", "typing a new start number renumbers from it", st.doc.toString());
// no list: untouched
st = apply(mk("hello\n"), { changes: { from: 5, insert: "!" }, userEvent: "input" });
check(st.doc.toString() === "hello!\n", "prose is untouched");
// critic marks
const crit = "1. a\n2. b\n3. {++c\n4. d++}\n5. e\n";
st = apply(mk(crit), { changes: { from: 5, to: 10 }, userEvent: "delete" });
check(st.doc.toString() === "1. a\n2. {++c\n3. d++}\n4. e\n", "a line inside a suggestion renumbers and the marks stay whole", st.doc.toString());
const sug = "{++x++}{>>@geoff 2026-10-28 #s1 +<<}\n1. a\n2. b\n3. c\n";
st = apply(mk(sug + "<!-- -->"), { changes: { from: 0, to: 0, insert: "" } });
// agent edits renumber after the edit has landed
const agent = apply(mk("1. a\n3. b\n3. c\n"), { changes: { from: 5, insert: "" }, userEvent: "agent" });
const fix = renumberAfter(agent, [[0, 15]]);
check(fix.length === 1 && apply(agent, { changes: fix }).doc.toString() === "1. a\n2. b\n3. c\n", "renumberAfter fixes an agent edit's list", fix);

console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);
