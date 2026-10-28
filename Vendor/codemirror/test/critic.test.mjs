// Checks for src/critic.js without a browser: the parse (the same document as Swift's ReviewChecks, so the two
// grammars can't drift), Accept and Reject, and Suggest Edits turning typing and Claude's hunks into signed marks.
// Run by `Vendor/codemirror/test/run.sh` (also called from DuoChecks).
import { EditorState } from "@codemirror/state";
import { parseReview, reviewCore, reviewSummary, suggestHunks, reviewField } from "../src/critic.js";

let failed = 0;
const check = (ok, name) => { if (!ok) failed++; console.log(`${ok ? "  ✔" : "  ✘"} ${name}`); };

const doc = [
  "---", "title: One-pager", "---", "# Offline", "",
  "The price is {~~30~>10~~}{>>@sam 2026-10-27 #s1: matches the deck<<} euros. It is {==cheap enough==}{>>@geoff 2026-10-27 #c1: really?<<}{>>@sam 2026-10-27 #c1.1: yes<<}.",
  "Add {++a line++}{>>@claude 2026-10-28 #s2<<} and {--cut this--}{>>@geoff 2026-10-28 #s3: drop<<}.",
  "`{++not a mark++}` stays. @claude can you tighten this? {>>@geoff 2026-10-28 #c2: bare<<}", "",
  "```", "{==code==}{>>@x 2026-10-28 #c9: no<<}", "```",
].join("\n");
const p = parseReview(doc);
check(p.suggestions.length === 3, "three suggestions are read, none from code");
check(p.suggestions[0].kind === "sub" && doc.slice(...p.suggestions[0].old) === "30" && doc.slice(...p.suggestions[0].new) === "10", "a substitution reads old and new");
check(p.suggestions[0].author === "sam" && p.suggestions[0].date === "2026-10-27" && p.suggestions[0].id === "s1" && p.suggestions[0].note === "matches the deck", "its signature note gives author, date, id and note");
check(p.suggestions[1].kind === "ins" && p.suggestions[1].id === "s2" && p.suggestions[1].note === "", "an insertion with a signature and no note");
check(p.suggestions[2].kind === "del" && doc.slice(...p.suggestions[2].old) === "cut this", "a deletion");
check(p.threads.length === 2, "two threads");
const c1 = p.threads.find((t) => t.id === "c1");
check(doc.slice(...c1.anchor) === "cheap enough" && c1.comments.length === 2 && c1.comments[1].text === "yes" && !c1.closed, "a thread has its anchor, comment and reply");
check(p.threads.find((t) => t.id === "c2").anchor === null, "a comment with no highlight is a thread with no anchor");
const closed = parseReview("a {==x==}{>>@geoff 2026-10-28 #c1: q<<}{>>@sam 2026-10-28 #c1.1 closed<<} b");
check(closed.threads[0].closed && closed.threads[0].comments[1].closing, "a closing line closes the thread");
check(parseReview("plain {braces} and {+ nothing +}").suggestions.length === 0, "text that only looks like marks is left alone");
check(parseReview("{++open never closed").suggestions.length === 0, "an unclosed mark is text");
check(parseReview("{++one\n\ntwo++}{>>@a 2026-10-28 #s1<<}").suggestions[0].kind === "ins", "an insertion spans paragraphs");

// What the Word converter writes (Q-283): a deletion inside a commented range, and a comment over two paragraphs.
const conv = "Some {=={--some old words--}{>>@morgan-editor 2026-09-06 #s2: <<}==}{>>@riley-reviewer 2026-09-06 #c3: why<<} here.\n\n{==First paragraph.==}\n\n{==Second paragraph.==}{>>@riley-reviewer 2026-09-05 #c5: both<<}{>>@dana-writer 2026-09-05 #c5.1: yes<<}\n";
const pc = parseReview(conv);
check(pc.suggestions.length === 1 && pc.suggestions[0].id === "s2" && pc.suggestions[0].kind === "del" && conv.slice(...pc.suggestions[0].old) === "some old words", "a deletion inside a highlight is a suggestion of its own");
check(pc.threads.map((t) => t.id).join() === "c3,c5" && pc.threads[0].pieces.length === 1 && pc.threads[0].anchorText === "some old words", "the highlight stays the thread's anchor");
check(pc.threads[1].pieces.length === 2 && pc.threads[1].anchorText === "First paragraph.\n\nSecond paragraph." && pc.threads[1].comments.length === 2 && pc.threads[1].from === conv.indexOf("{==First"), "a comment over two paragraphs is one thread with a highlight in each");
check(!pc.threads.some((t) => t.id.startsWith("u")), "no unsigned thread is made of a paragraph's highlight");

const state = (text) => EditorState.create({ doc: text, extensions: [reviewCore] });
const sum = reviewSummary(state(doc));
check(sum.suggestions === 3 && sum.threads === 2 && !sum.suggestEdits && sum.marks, "the summary counts marks");
check(sum.people.find((x) => x.name === "claude").colour === 3, "Claude is always review colour 3");
check(sum.people.find((x) => x.name === "sam").colour === 1 && sum.people.find((x) => x.name === "geoff").colour === 2, "people take 1, 2, 4, 5 in order of appearance");

// Suggest Edits
const on = "---\nsuggest-edits: true\n---\nHello world.\n";
check(reviewSummary(state(on)).suggestEdits, "suggest-edits: true in the frontmatter turns it on");
check(!reviewSummary(state("---\nsuggest-edits: false\n---\nx")).suggestEdits, "false is off");
const s0 = state(on), W = on.indexOf("world");
const typed = s0.update({ changes: { from: W, insert: "big " }, userEvent: "input.type" }).state;
check(/Hello \{\+\+big \+\+\}\{>>@me \d{4}-\d{2}-\d{2} #s1<<\}world\./.test(typed.doc.toString()), "typing becomes a signed insertion");
const more = typed.update({ changes: { from: typed.doc.toString().indexOf("++}") , insert: "x" }, userEvent: "input.type" }).state;
check(more.doc.toString().includes("{++big x++}"), "typing on inside your own insertion extends it");
const deleted = s0.update({ changes: { from: W, to: W + 5 }, userEvent: "delete.backward" }).state.doc.toString();
check(/Hello \{--world--\}\{>>@me \d{4}-\d{2}-\d{2} #s1<<\}\./.test(deleted), "deleting becomes a signed deletion");
const over = s0.update({ changes: { from: W, to: W + 5, insert: "there" }, userEvent: "input.type" }).state.doc.toString();
check(over.includes("{~~world~>there~~}"), "typing over a selection becomes a substitution");
const fm = s0.update({ changes: { from: 4, insert: "x" }, userEvent: "input.type" }).state.doc.toString();
check(fm.startsWith("---\nxsuggest-edits"), "frontmatter edits stay plain");
const agent = suggestHunks(s0, [{ from: W, to: W + 5, insert: "there" }], "claude");
check(agent.length === 1 && agent[0].insert.includes("{~~world~>there~~}") && agent[0].insert.includes("@claude"), "Claude's hunk becomes a signed substitution");
const off = state("Hello world.\n").update({ changes: { from: 6, insert: "big " }, userEvent: "input.type" }).state.doc.toString();
check(off === "Hello big world.\n", "with the switch off typing is plain");
const programmatic = s0.update({ changes: { from: W, insert: "z" }, userEvent: "review" }).state.doc.toString();
check(programmatic.includes("worldz") || programmatic.includes("zworld") || !programmatic.includes("{++z"), "Accept and Reject edits are never turned into marks");

console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);
