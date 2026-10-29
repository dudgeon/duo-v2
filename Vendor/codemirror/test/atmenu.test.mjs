// Checks for src/atmenu.js without a browser: when `@` opens the menu, the filter, the keys and the insertion.
// Run by `Vendor/codemirror/test/run.sh` (also called from DuoChecks).
import { atQuery, atFilter, atKey, atInsert } from "../src/atmenu.js";

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

if (failed) { console.log(`${failed} failed`); process.exit(1); }
