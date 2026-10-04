// The editor's three-way line merge (DL-77), run outside the app: node scripts/check-merge.mjs
import fs from "fs";
const src = fs.readFileSync("Vendor/codemirror/src/duo-editor.js", "utf8");
const grab = (name) => { const i = src.indexOf(name); let depth = 0, j = src.indexOf("{", i); for (let k = j; k < src.length; k++) { if (src[k] === "{") depth++; else if (src[k] === "}" && --depth === 0) return src.slice(i, k + 1); } };
const code = ["const chunks = (t) => t.match(/[^\\n]*\\n|[^\\n]+$/g) || [];", grab("function diffLines"), grab("function merge3")].join("\n");
const { diffLines, merge3, chunks } = new Function(code + "; return { diffLines, merge3, chunks };")();
const M = (b, m, t) => { const r = merge3(chunks(b), chunks(m), chunks(t)); return r.conflicts.length ? "CONFLICT " + JSON.stringify(r.conflicts) : r.out.join(""); };
const base = "a\nb\nc\nd\ne\nf\n";
const cases = [
  ["disjoint", base, "a\nB\nc\nd\ne\nf\n", "a\nb\nc\nd\nE\nf\n", "a\nB\nc\nd\nE\nf\n"],
  ["adjacent lines", base, "a\nB\nc\nd\ne\nf\n", "a\nb\nC\nd\ne\nf\n", "a\nB\nC\nd\ne\nf\n"],
  ["same line", base, "a\nB1\nc\nd\ne\nf\n", "a\nB2\nc\nd\ne\nf\n", "CONFLICT"],
  ["same change both", base, "a\nX\nc\nd\ne\nf\n", "a\nX\nc\nd\ne\nf\n", "a\nX\nc\nd\ne\nf\n"],
  ["two user edits, one outside between", base, "A\nb\nc\nd\ne\nF\n", "a\nb\nC\nd\ne\nf\n", "A\nb\nC\nd\ne\nF\n"],
  ["insert vs insert same spot", base, "a\nb\nNEW1\nc\nd\ne\nf\n", "a\nb\nNEW2\nc\nd\ne\nf\n", "CONFLICT"],
  ["append at end, user edits top", base, "A\nb\nc\nd\ne\nf\n", base + "g\n", "A\nb\nc\nd\ne\nf\ng\n"],
  ["delete vs edit elsewhere", base, "a\nc\nd\ne\nf\n", "a\nb\nc\nd\ne\nF\n", "a\nc\nd\ne\nF\n"],
  ["no trailing newline", "x\ny", "X\ny", "x\nY", "X\nY"],
];
let bad = 0;
for (const [n, b, m, t, want] of cases) { const got = M(b, m, t); const ok = want === "CONFLICT" ? got.startsWith("CONFLICT") : got === want; if (!ok) bad++; console.log(ok ? "ok  " : "BAD ", n, ok ? "" : JSON.stringify(got)); }
const big = Array.from({ length: 30000 }, (_, i) => `line ${i}\n`).join("");
const t0 = Date.now(); const r = M(big, big.replace("line 10\n", "LINE 10\n"), big.replace("line 29990\n", "LINE 29990\n")); console.log("30k lines:", Date.now() - t0, "ms", r.includes("LINE 10") && r.includes("LINE 29990") ? "merged" : "WRONG");
process.exit(bad);
