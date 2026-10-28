import { parser, GFM } from "@lezer/markdown";
import { critic } from "./critic.mjs";
const p = parser.configure([GFM, critic]);
const show = (src) => {
  const t = p.parse(src), out = []; let d = 0;
  t.iterate({ enter: n => { if (n.name !== "Document") out.push("  ".repeat(d) + n.name + " " + JSON.stringify(src.slice(n.from, n.to))); d++; }, leave: () => { d--; } });
  return { out };
};
const names = src => { const s = []; p.parse(src).iterate({ enter: n => s.push(n.name) }); return s; };
const has = (src, ...n) => n.every(x => names(src).includes(x));
const not = (src, ...n) => n.every(x => !names(src).includes(x));
const cases = [
 ["add", "a {++b++} c", s => has(s, "CriticAddition")],
 ["del", "{--x--}", s => has(s, "CriticDeletion")],
 ["subst", "{~~old~>new~~}", s => has(s, "CriticSubstitution", "CriticSubstitutionArrow")],
 ["hl+comment", "{==hi==}{>>note<<}", s => has(s, "CriticHighlight", "CriticComment")],
 ["sig+mention", "{>>@geoff 2026-10-27 #c2: @claude tighten this<<}", s => has(s, "CriticSignature", "CriticMention")],
 ["reply", "{>>@claude 2026-10-27 #c2.1: done<<}", s => has(s, "CriticSignature") && not(s, "CriticMention")],
 ["emphasis inside", "{++**bold** add++}", s => has(s, "CriticAddition", "StrongEmphasis")],
 ["inline code", "`{++not markup++}`", s => not(s, "CriticAddition") && has(s, "InlineCode")],
 ["fenced code", "```\n{++x++}\n```", s => not(s, "CriticAddition") && has(s, "FencedCode")],
 ["multi-para", "{++## Pricing\n\nIt is free.++}", s => has(s, "CriticAddition")],
 ["unclosed", "{++ never closed", s => not(s, "CriticAddition")],
 ["strike inside subst", "{~~a ~~x~~ b~>c~~}", s => has(s, "CriticSubstitution", "Strikethrough", "CriticSubstitutionArrow")],
 ["comment with << and }", "{>>a << b } c<<}", s => has(s, "CriticComment")],
 ["list item", "- item {++new++}", s => has(s, "ListItem", "CriticAddition")],
 ["table cell", "| a | b |\n|---|---|\n| {--x--} | {>>@geoff: hi<<} |", s => has(s, "TableCell", "CriticDeletion", "CriticComment")],
 ["plain strike unaffected", "~~gone~~", s => has(s, "Strikethrough") && not(s, "CriticSubstitution")],
];
const rows = [];
for (const [name, src, ok] of cases) {
  console.log("\n### " + name + "  " + JSON.stringify(src));
  console.log(show(src).out.join("\n"));
  rows.push([name, ok(src) ? "PASS" : "FAIL"]);
}
console.log("\n" + rows.map(r => r[1].padEnd(5) + r[0]).join("\n"));
