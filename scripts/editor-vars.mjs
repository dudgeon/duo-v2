// The page variables the app sets that are not colours (the faces, the document's type, the radii and sizes, the popover shadow),
// from tokens.json, for the scripts that load the built pages on their own and set only the colours they need.
// EditorController.tokenCSS() is the app's version of this list (DuoWebTokens, generated); keep them in step.
import fs from "fs";
const root = new URL("..", import.meta.url).pathname;
const t = JSON.parse(fs.readFileSync(root + "docs/design/build-handoff/tokens.json", "utf8"));
const kebab = (k) => k.replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase();

export function typeVars() {
  const v = [];
  for (const [k, f] of Object.entries(t.font.family)) v.push(`--duo-font-${k}:${f.css}`);
  // DUO_SCHEME=classic draws the page in Classic's type (New York 16/27), so the geometry can be checked at another size.
  const d = { ...t.font.document, ...(process.env.DUO_SCHEME === "classic" ? t.font.document.scheme.classic : {}) };
  v.push(`--duo-font-document:${t.font.family[d.family].css}`, `--duo-document-size:${d.size}px`, `--duo-document-line:${d.lineHeight}px`,
    `--duo-document-heading-weight:${d.headingWeight}`, `--duo-document-h1:${d.h1.size}px`, `--duo-document-h1-line:${d.h1.lineHeight}px`, `--duo-document-h2:${d.h2.size}px`,
    `--duo-document-padding-y:${t.space.documentPadding.vertical}px`, `--duo-document-padding-x:${t.space.documentPadding.horizontal}px`);
  for (const [k, r] of Object.entries(t.radius)) if (typeof r === "number") v.push(`--duo-radius-${kebab(k)}:${r}px`);
  for (const [k, s] of Object.entries(t.font.style)) v.push(`--duo-size-${kebab(k)}:${s.size}px`, `--duo-line-${kebab(k)}:${s.lineHeight}px`);
  const p = t.shadow.popover;
  v.push(`--duo-shadow-popover:${p.x}px ${p.y}px ${p.blur}px ${p.color}`);
  return v.join(";") + ";";
}

/** After the page loads: the non-colour variables, as a stylesheet rule (the scripts' own style attribute keeps the colours). */
export async function addTypeVars(page) {
  await page.addStyleTag({ content: `:root{${typeVars()}}` });
}
