// Spike (research/pdf-viewing, F-644): what PDF.js (pdfjs-dist 4.10.38) sees of a PDF comment
// thread, and whether its saveDocument() writes an incremental update.
// Usage: node pdfjs-check.mjs <pdfjs-dist dir> <in.pdf> <out.pdf>
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const [dist, inPath, outPath] = process.argv.slice(2);
const pdfjs = await import(pathToFileURL(path.join(dist, "legacy/build/pdf.mjs")).href);
const original = new Uint8Array(fs.readFileSync(inPath));
const doc = await pdfjs.getDocument({ data: original.slice(), isEvalSupported: false }).promise;
const page = await doc.getPage(1);
const annots = await page.getAnnotations();
for (const a of annots) {
  console.log(JSON.stringify({
    subtype: a.subtype, id: a.id, title: a.titleObj?.str, contents: a.contentsObj?.str?.slice(0, 40),
    inReplyTo: a.inReplyTo ?? null, replyType: a.replyType ?? null, hidden: !!a.hidden || a.noView || undefined,
    creationDate: a.creationDate ?? null, modificationDate: a.modificationDate ?? null,
    state: a.state ?? null, stateModel: a.stateModel ?? null,
  }));
}
// Add one FreeText through the editor serialization path and save.
doc.annotationStorage.setValue("pdfjs_internal_editor_0", {
  annotationType: pdfjs.AnnotationEditorType.FREETEXT, color: [0, 0, 0], fontSize: 10,
  value: "Added by PDF.js", pageIndex: 0, rect: [60, 60, 260, 80], rotation: 0, id: null,
});
const saved = await doc.saveDocument();
fs.writeFileSync(outPath, saved);
const prefix = original.every((b, i) => saved[i] === b);
console.log(`saved ${saved.length} B from ${original.length} B; original is byte prefix: ${prefix}`);
