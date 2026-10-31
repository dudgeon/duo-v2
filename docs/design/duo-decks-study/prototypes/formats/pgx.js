// pptxgenjs: define a master with named placeholders, fill them, then inspect XML.
const pptxgen = require("pptxgenjs");
const pptx = new pptxgen();
pptx.layout = "LAYOUT_16x9";
pptx.defineSlideMaster({
  title: "TITLE_AND_BULLETS",
  background: { color: "FFFFFF" },
  objects: [
    { placeholder: { options: { name: "title", type: "title", x: 0.5, y: 0.3, w: 9, h: 0.8 }, text: "" } },
    { placeholder: { options: { name: "body", type: "body", x: 0.5, y: 1.3, w: 9, h: 3.8 }, text: "" } },
  ],
});
const s = pptx.addSlide({ masterName: "TITLE_AND_BULLETS" });
s.addText("Wins", { placeholder: "title" });
s.addText([{ text: "Shipped voice input", options: { bullet: true } }, { text: "Latency down 40%", options: { bullet: true } }], { placeholder: "body" });
s.addNotes("Mention the beta users.");
pptx.writeFile({ fileName: process.argv[2] || "pgx.pptx" }).then((f) => console.log("wrote", f));
