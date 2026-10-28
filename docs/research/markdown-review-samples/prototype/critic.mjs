// CriticMarkup as a @lezer/markdown inline extension (throwaway prototype).
const OPEN = { "++": "CriticAddition", "--": "CriticDeletion", "~~": "CriticSubstitution", "==": "CriticHighlight" };
const DELIM = {}; // one DelimiterType per kind
for (const k in OPEN) DELIM[k] = { resolve: OPEN[k], mark: "CriticMark" };
const COMMENT_DELIM = null;
const SIG = /^\s*@[\w-]+(?: \d{4}-\d{2}-\d{2})?(?: #[\w.]+)?:/;
const MENTION = /@claude\b/g;

export const critic = {
  defineNodes: [
    "CriticAddition", "CriticDeletion", "CriticSubstitution", "CriticSubstitutionArrow",
    "CriticHighlight", "CriticComment", "CriticMark", "CriticSignature", "CriticMention",
  ].map(name => ({ name })),
  parseInline: [
    { // openers: {++ {-- {~~ {== {>>
      name: "CriticOpen",
      parse(cx, next, pos) {
        if (next !== 123) return -1;
        const kind = cx.slice(pos + 1, pos + 3), rest = cx.slice(pos, cx.end);
        if (kind === ">>") {
          const close = rest.indexOf("<<}", 3);
          if (close < 0) return -1;
          const from = pos, to = pos + close + 3, cFrom = pos + 3, cTo = pos + close;
          const body = rest.slice(3, close), kids = [cx.elt("CriticMark", from, cFrom)];
          const sig = SIG.exec(body);
          if (sig) kids.push(cx.elt("CriticSignature", cFrom + sig[0].search(/\S/), cFrom + sig[0].length));
          let m; MENTION.lastIndex = sig ? sig[0].length : 0;
          while ((m = MENTION.exec(body))) kids.push(cx.elt("CriticMention", cFrom + m.index, cFrom + m.index + m[0].length));
          kids.push(cx.elt("CriticMark", cTo, to));
          return cx.addElement(cx.elt("CriticComment", from, to, kids));
        }
        if (!OPEN[kind]) return -1;
        if (rest.indexOf(kind + "}", 3) < 0) return -1; // unclosed: plain text
        return cx.addDelimiter(DELIM[kind], pos, pos + 3, true, false);
      },
      before: "Emphasis",
    },
    { // closers: ++} --} ~~} ==}  and the ~> arrow
      name: "CriticClose",
      parse(cx, next, pos) {
        if (next !== 43 && next !== 45 && next !== 61 && next !== 126) return -1;
        if (next === 126 && cx.char(pos + 1) === 62) { // ~>
          const i = cx.findOpeningDelimiter(DELIM["~~"]);
          return i == null ? -1 : cx.append(cx.elt("CriticSubstitutionArrow", pos, pos + 2));
        }
        const kind = cx.slice(pos, pos + 2);
        if (!OPEN[kind] || cx.char(pos + 2) !== 125) return -1;
        const i = cx.findOpeningDelimiter(DELIM[kind]);
        if (i == null) return -1;
        const open = cx.parts[i], kids = cx.takeContent(i);
        kids.unshift(cx.elt("CriticMark", open.from, open.to));
        kids.push(cx.elt("CriticMark", pos, pos + 3));
        return cx.addElement(cx.elt(OPEN[kind], open.from, pos + 3, kids));
      },
      before: "Strikethrough",
    },
  ],
};
