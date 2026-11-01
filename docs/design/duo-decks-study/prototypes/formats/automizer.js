// pptx-automizer: load a template pptx (here: pandoc's output, as a stand-in corporate deck),
// clone slide 3 ("Title and Content") twice, replace text by shape name. Then inspect XML.
const { default: Automizer, modify } = require("pptx-automizer");
const dir = __dirname + "/../automizer";
const automizer = new Automizer({ templateDir: dir, outputDir: dir, removeExistingSlides: true });
const pres = automizer.loadRoot("template.pptx").load("template.pptx", "tpl");
(async () => {
  const info = await pres.getInfo();
  const slides = info.slidesByTemplate("tpl");
  console.log("template slides:", slides.map((s) => s.number + ":" + s.elements.map((e) => e.name).join("|")).join("  "));
  const n = slides[2].number;
  const names = slides[2].elements.map((e) => e.name);
  pres.addSlide("tpl", n, (slide) => {
    slide.modifyElement(names[0], [modify.setText("Wins")]);
    slide.modifyElement(names[1], [modify.setText("Shipped voice input")]);
  });
  pres.addSlide("tpl", n, (slide) => {
    slide.modifyElement(names[0], [modify.setText("Risks")]);
    slide.modifyElement(names[1], [modify.replaceText([{ replace: "Shipped voice input", by: { text: "Hiring" } }])]);
  });
  const r = await pres.write("out.pptx");
  console.log(r);
})();
