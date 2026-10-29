// Checks for src/atmenu.js without a browser: when `@` opens the menu, the filter, the keys and the insertion.
// Run by `Vendor/codemirror/test/run.sh` (also called from DuoChecks).
import { atQuery, atFilter, atKey, atInsert, atPeople, AT_ITEMS } from "../src/atmenu.js";
import { parseReview } from "../src/critic.js";

let failed = 0;
const check = (ok, name) => { if (!ok) failed++; console.log(`${ok ? "  ✔" : "  ✘"} ${name}`); };
const key = (k, o = {}) => ({ key: k, metaKey: false, ctrlKey: false, altKey: false, shiftKey: false, ...o });

check(atQuery("@", 1)?.query === "" && atQuery("@", 1).start === 0, "an @ at the start opens the menu with nothing typed");
check(atQuery("ask @cl", 7)?.query === "cl" && atQuery("ask @cl", 7).start === 4, "an @ after a space keeps what's typed after it");
check(atQuery("a@b", 3) === null, "an @ inside a word (an email) doesn't open it");
check(atQuery("ask @claude now", 15) === null, "past the word the menu is closed");
check(atQuery("ask @claude now", 11)?.query === "claude", "the caret inside the word still reads it");
check(atQuery("ask claude", 10) === null, "no @, no menu");
check(atQuery("line\n@x", 7)?.start === 5, "an @ after a new line opens it");

check(atFilter("")[0].name === "claude", "Claude is the first item with nothing typed");
check(atFilter("cl").length === 1 && atFilter("CL").length === 1, "@cl keeps Claude, in any case");
check(atFilter("zz").length === 0, "a name that matches nothing leaves the menu empty");

check(atKey(key("ArrowDown")) === "down" && atKey(key("ArrowUp")) === "up", "↑ and ↓ move");
check(atKey(key("Enter")) === "insert" && atKey(key("Tab")) === "insert", "Return and Tab insert");
check(atKey(key("Escape")) === "close", "Esc closes the menu");
check(atKey(key("Enter", { metaKey: true })) === null, "⌘Return is left to Post");
check(atKey(key("Enter", { shiftKey: true })) === null && atKey(key("a")) === null, "⇧Return and letters go to the field");

let r = atInsert("ask @cl", 4, 7, "claude");
check(r.text === "ask @claude " && r.caret === 12, "inserting writes exactly @claude and a space");
r = atInsert("ask @cl please", 4, 7, "claude");
check(r.text === "ask @claude please" && r.caret === 11, "before a space it adds none");
check(/@claude\b/i.test(atInsert("@", 0, 1, "claude").text), "what it writes routes to Claude (the @claude test the margin uses)");

// People (stage 2): the names in the document, newest first.
const pdoc = [
  "A {==one==}{>>@sam 2026-10-26 #c1: first<<}{>>@geoff 2026-10-27 #c1.1: yes<<} and {==two==}{>>@lena 2026-10-28 #c2: @Sam can you check? Also @claude<<}.",
  "Then {++three++}{>>@Dana-Ops 2026-10-25 #s1: from the deck<<} and {==four==}{>>@geoff 2026-10-27 #c3: ask @pat and a@b.com<<}",
  "```", "{==code==}{>>@ghost 2026-10-29 #c9: @nobody<<}", "```",
].join("\n");
const parsed = parseReview(pdoc);
const names = atPeople(parsed, "geoff").map((p) => p.name);
check(names.join(",") === "lena,Sam,pat,Dana-Ops", "people: newest first, signers and mentions, no Claude, not yourself, none from code (" + names.join(",") + ")");
check(names.includes("Sam") && !names.includes("sam"), "names that differ in case are one person, spelled as last written");
check(!names.includes("b.com") && !names.includes("b"), "an @ inside a word (an email) names nobody");
check(atPeople(parsed, "").some((p) => p.name === "geoff"), "with no name of your own, you are listed too");
check(atPeople(parsed, "geoff").every((p) => p.hint === ""), "a person's row has no hint");
const items = AT_ITEMS.concat(atPeople(parsed, "geoff"));
check(atFilter("", items)[0].name === "claude" && atFilter("", items).length === 5, "the menu is Claude, then the people");
check(atFilter("s", items).map((i) => i.name).join() === "Sam", "typing filters the people too, in any case");
check(atInsert("ask @l", 4, 6, "lena").text === "ask @lena ", "a person is inserted as written, as text");
check(!/@claude\b/i.test(atInsert("@l", 0, 2, "lena").text), "a person's tag is not the @claude that routes");
check(atPeople({ threads: [], suggestions: [] }, "x").length === 0, "no names in the document: only Claude");

if (failed) { console.log(`${failed} failed`); process.exit(1); }
