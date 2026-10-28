// The Word viewer's look where a document says nothing (DL-233, Geoff 2026-10-27: draw default text like Google Docs).
// The values come from the design tokens (`docxDefaults` in tokens.json, as `window.__duoDocxDefaults`).
//
// The defaults go in at the document's own level, before the renderer reads it: the .docx's bytes are opened in
// memory, `word/styles.xml` gets what's missing (Arial 11 and 1.15 line spacing in docDefaults where it names no
// font, size or line; Title, Subtitle and Heading 1 to 6 where it defines no such style), and the renderer is handed
// the result. A style the document has is never touched, so its own styles win. The file on disk is never written.
import JSZip from './jszip.mjs';

const W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const STYLE_IDS = {
  title: ['Title', 'title'], subtitle: ['Subtitle', 'subtitle'],
  heading1: ['Heading1', 'heading 1'], heading2: ['Heading2', 'heading 2'], heading3: ['Heading3', 'heading 3'],
  heading4: ['Heading4', 'heading 4'], heading5: ['Heading5', 'heading 5'], heading6: ['Heading6', 'heading 6'],
};

const el = (doc, name, attrs = {}, ...kids) => {
  const e = doc.createElementNS(W, `w:${name}`);
  for (const [k, v] of Object.entries(attrs)) e.setAttributeNS(W, `w:${k}`, String(v));
  for (const k of kids) if (k) e.append(k);
  return e;
};
const child = (parent, name) => [...parent.children].find((c) => c.namespaceURI === W && c.localName === name) || null;
const hasAttr = (e, name) => !!e && e.hasAttributeNS(W, name);
const twips = (pt) => Math.round(pt * 20);

// Fills docDefaults: a font, a size and a line spacing, each only where the document names none.
function fillDefaults(doc, root, d) {
  let dd = child(root, 'docDefaults');
  if (!dd) { dd = el(doc, 'docDefaults'); root.prepend(dd); }
  let rPrD = child(dd, 'rPrDefault');
  if (!rPrD) { rPrD = el(doc, 'rPrDefault'); dd.prepend(rPrD); }
  let rPr = child(rPrD, 'rPr');
  if (!rPr) { rPr = el(doc, 'rPr'); rPrD.append(rPr); }
  if (!child(rPr, 'rFonts')) rPr.prepend(el(doc, 'rFonts', { ascii: d.font, hAnsi: d.font, eastAsia: d.font, cs: d.font }));
  if (!child(rPr, 'sz')) rPr.append(el(doc, 'sz', { val: d.size * 2 }), el(doc, 'szCs', { val: d.size * 2 }));
  let pPrD = child(dd, 'pPrDefault');
  if (!pPrD) { pPrD = el(doc, 'pPrDefault'); dd.append(pPrD); }
  let pPr = child(pPrD, 'pPr');
  if (!pPr) { pPr = el(doc, 'pPr'); pPrD.append(pPr); }
  let sp = child(pPr, 'spacing');
  if (!sp) { sp = el(doc, 'spacing'); pPr.append(sp); }
  if (!hasAttr(sp, 'line')) { sp.setAttributeNS(W, 'w:line', String(Math.round(d.lineSpacing * 240))); sp.setAttributeNS(W, 'w:lineRule', 'auto'); }
  return Number(child(rPr, 'sz')?.getAttributeNS(W, 'val')) / 2 || d.size;   // the document's default size, in points
}

// Adds Title, Subtitle and Heading 1 to 6 where the document has no style by that id or name.
function fillStyles(doc, root, d) {
  const styles = [...root.children].filter((c) => c.localName === 'style' && c.namespaceURI === W);
  const have = new Set();
  for (const s of styles) {
    have.add((s.getAttributeNS(W, 'styleId') || '').toLowerCase());
    const n = child(s, 'name');
    if (n) have.add((n.getAttributeNS(W, 'val') || '').toLowerCase());
  }
  const hasNormal = styles.some((s) => s.getAttributeNS(W, 'styleId') === 'Normal');
  for (const [key, [id, name]] of Object.entries(STYLE_IDS)) {
    const spec = d.styles?.[key];
    if (!spec || have.has(id.toLowerCase()) || have.has(name)) continue;
    const ppr = el(doc, 'pPr', {}, el(doc, 'keepNext'), el(doc, 'keepLines'),
      el(doc, 'spacing', { before: twips(spec.before), after: twips(spec.after) }),
      key.startsWith('heading') ? el(doc, 'outlineLvl', { val: Number(key.slice(7)) - 1 }) : null);
    const rpr = el(doc, 'rPr', {}, spec.italic ? el(doc, 'i') : null, spec.color ? el(doc, 'color', { val: spec.color.replace('#', '') }) : null,
      el(doc, 'sz', { val: spec.size * 2 }), el(doc, 'szCs', { val: spec.size * 2 }));
    root.append(el(doc, 'style', { type: 'paragraph', styleId: id }, el(doc, 'name', { val: name }),
      hasNormal ? el(doc, 'basedOn', { val: 'Normal' }) : null, hasNormal ? el(doc, 'next', { val: 'Normal' }) : null, el(doc, 'qFormat'), ppr, rpr));
  }
}

const STYLES_REL = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles';
const STYLES_TYPE = 'application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml';

// A document with no styles part at all gets one (with its relationship and content type).
async function addStylesPart(zip) {
  const rels = await zip.file('word/_rels/document.xml.rels')?.async('string');
  const types = await zip.file('[Content_Types].xml')?.async('string');
  if (rels == null || types == null) return false;
  if (!rels.includes(STYLES_REL)) zip.file('word/_rels/document.xml.rels', rels.replace('</Relationships>', `<Relationship Id="rIdDuoStyles" Type="${STYLES_REL}" Target="styles.xml"/></Relationships>`));
  if (!types.includes('/word/styles.xml')) zip.file('[Content_Types].xml', types.replace('</Types>', `<Override PartName="/word/styles.xml" ContentType="${STYLES_TYPE}"/></Types>`));
  zip.file('word/styles.xml', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles xmlns:w="${W}"/>`);
  return true;
}

/// The document's bytes with Google Docs' defaults filled in where it says nothing, and its default text size in
/// points (the renderer's paragraphs carry its own 10.5 pt, which would set the height of a line of smaller text).
/// Anything it can't read comes back unchanged for the renderer to report.
export async function withGoogleLook(bytes, d) {
  if (!d) return { bytes, size: null };
  try {
    const zip = await JSZip.loadAsync(bytes);
    if (!zip.file('word/document.xml')) return { bytes, size: null };
    if (!zip.file('word/styles.xml') && !(await addStylesPart(zip))) return { bytes, size: null };
    const doc = new DOMParser().parseFromString(await zip.file('word/styles.xml').async('string'), 'application/xml');
    const root = doc.documentElement;
    if (root.localName !== 'styles' || doc.querySelector('parsererror')) return { bytes, size: null };
    const size = fillDefaults(doc, root, d);
    fillStyles(doc, root, d);
    zip.file('word/styles.xml', new XMLSerializer().serializeToString(doc));
    return { bytes: await zip.generateAsync({ type: 'arraybuffer' }), size };
  } catch (_) {
    return { bytes, size: null };
  }
}

// A font the Mac doesn't have is drawn in a stand-in instead of the browser's serif: @font-face by the Office
// font's name whose first choice is the real font (so it wins where installed) and then the stand-in.
export function fontAliasCSS(map) {
  const face = (family, weight, style, names) => `@font-face { font-family: "${family}"; font-weight: ${weight}; font-style: ${style}; src: ${names.map((n) => `local("${n}")`).join(', ')}; }`;
  const suffixes = [['normal', 'normal', ''], ['bold', 'normal', 'Bold'], ['normal', 'italic', 'Italic'], ['bold', 'italic', 'Bold Italic']];
  const names = (f, s) => s ? [`${f} ${s}`, `${f}-${s.replace(' ', '')}`, `${f}-${s.replace(' ', '')}MT`] : [f, `${f}MT`];
  return Object.entries(map || {}).map(([from, to]) =>
    suffixes.map(([w, st, s]) => face(from, w, st, [...names(from, s), ...names(to, s)])).join('\n')).join('\n');
}
